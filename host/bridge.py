"""Explicit serial adapter and local preview for the separate smart-room firmware.

Use --check without opening a port. Real serial use requires --allow-serial.
No uploader, automatic port search, model download, camera recording or retry loop.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
import math
import platform
import secrets
import sys
import threading
import time
import traceback
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Callable, Iterator, Protocol

from .core import (
    LOCAL_ACTIONS, BridgeState, Detection, MixedParser, SourceFrame,
    encode_control, parse_event, validate_port,
)

ROOT = Path(__file__).resolve().parents[1]
OLD = ROOT.parent / "esp32cam_live"
PEOPLE_SHA256 = "4b4a9d317876ec630a02864ca005b353601b34f3c6e0279023f6f8db1751b19f"
MODEL_SHA256 = "c5c2d13e59ae883e6af3b45daea64af4833a4951c92d116ec270d9ddbe998063"
ASSETS = {"/": ("page.html", "text/html; charset=utf-8"),
          "/page.js": ("page.js", "text/javascript; charset=utf-8"),
          "/page.css": ("page.css", "text/css; charset=utf-8")}


class SerialPort(Protocol):
    port: str
    baudrate: int
    timeout: float
    write_timeout: float
    dtr: bool
    rts: bool

    def open(self) -> None: ...
    def close(self) -> None: ...
    def read(self, size: int) -> bytes: ...
    def write(self, data: bytes) -> int: ...


@contextmanager
def serial_link(port: str, *, allow_serial: bool,
                factory: Callable[[], SerialPort] | None = None) -> Iterator[SerialPort]:
    validate_port(port, allow_serial=allow_serial)  # Before importing/constructing any adapter.
    if factory is None:
        import serial

        factory = serial.Serial
    connection = factory()
    try:
        connection.port, connection.baudrate = port, 921600
        connection.timeout, connection.write_timeout = 0.05, 0.3
        connection.dtr = connection.rts = False
        connection.open()
        yield connection
    finally:
        connection.close()


class SerialCommandError(OSError):
    """A write may have partly reached the MCU; this link must not write again."""


def write_command(connection: SerialPort, command: dict) -> None:
    packet = encode_control(command)
    try:
        written = connection.write(packet)
    except (OSError, KeyboardInterrupt) as exc:
        raise SerialCommandError("Serial write interrupted; result unknown, no automatic retry") from exc
    if type(written) is not int or written != len(packet):
        raise SerialCommandError("Partial serial command; stop rather than retry an uncertain operation")


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def preflight() -> dict:
    """Read-only artifact/version checks; no model load and no serial connection."""
    for relative, expected in (("people.py", PEOPLE_SHA256), ("models/yolox_s.onnx", MODEL_SHA256)):
        path = OLD / relative
        if file_hash(path) != expected:
            raise RuntimeError(f"Preserved {path} changed; review it, do not overwrite it")
    return {"python": platform.python_version(),
            "opencv_python": importlib.metadata.version("opencv-python"),
            "numpy": importlib.metadata.version("numpy"),
            "pyserial": importlib.metadata.version("pyserial"),
            "people_sha256": PEOPLE_SHA256, "model_sha256": MODEL_SHA256,
            "serial_opened": False, "hardware_tested": False}


def create_analyzer(size: int, confidence: float) -> Callable[[SourceFrame], Detection]:
    # Only the fixed, hash-checked existing Python detector is reused. The old
    # viewer/main/serial reader are never imported or started.
    if size not in (320, 448, 512, 640) or not math.isfinite(confidence) or not 0 < confidence < 1:
        raise ValueError("Invalid detector size/confidence")
    preflight()
    import cv2
    import numpy as np

    spec = importlib.util.spec_from_file_location("smart_room_existing_people", OLD / "people.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load preserved detector")
    people = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(people)
    detector = people.build_detector(str(OLD / "models/yolox_s.onnx"),
                                     conf_threshold=confidence, input_size=(size, size))

    def analyze(source: SourceFrame) -> Detection:
        image = cv2.imdecode(np.frombuffer(source.jpeg, dtype=np.uint8), cv2.IMREAD_COLOR)
        if image is None or image.ndim != 3 or image.shape[2] != 3:
            raise ValueError("JPEG decode failed; count is unknown, not zero")
        started = time.perf_counter()
        boxes = detector.detect(image)
        elapsed = (time.perf_counter() - started) * 1000
        annotated = people.annotate(image, boxes, len(boxes), 0, elapsed)
        ok, encoded = cv2.imencode(".jpg", annotated, [int(cv2.IMWRITE_JPEG_QUALITY), 80])
        if not ok:
            raise RuntimeError("Cannot encode the source-bound preview")
        return Detection(source, len(boxes), elapsed, encoded.tobytes())

    return analyze


def detect_once(state: BridgeState, analyze: Callable[[SourceFrame], Detection],
                clock: Callable[[], float] = time.monotonic) -> bool:
    source = state.take_source()
    if source is None:
        return False
    return state.publish(analyze(source), clock())


def vision_worker(state: BridgeState, analyze: Callable[[SourceFrame], Detection], stop: threading.Event) -> None:
    try:
        while not stop.is_set():
            if state.available.wait(0.2):
                detect_once(state, analyze)
    except Exception as exc:
        # Unexpected worker exceptions are visible and terminal, never retried as
        # a zero-person result. The serial owner attempts one unknown packet.
        state.detector_failed(f"Vision worker failed: {type(exc).__name__}: {exc}")
        traceback.print_exc()
        stop.set()


class Diagnostics:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._controller: dict | None = None
        self._stream_errors = 0

    def update(self, event: dict | None, errors: int) -> None:
        with self._lock:
            if event is not None:
                self._controller = dict(event)
            self._stream_errors = errors

    def snapshot(self) -> dict:
        with self._lock:
            return {"controller": self._controller, "stream_errors": self._stream_errors}


def preview_handler(state: BridgeState, diagnostics: Diagnostics,
                    clock: Callable[[], float] = time.monotonic) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        def setup(self) -> None:
            super().setup()
            self.connection.settimeout(3)

        def log_message(self, *_args: object) -> None:
            pass

        def do_GET(self) -> None:
            frame_query = self.path.startswith("/frame.jpg?") and self.path[11:].isdigit() and len(self.path) <= 32
            if self.path == "/status":
                raw = json.dumps(state.snapshot(clock()) | diagnostics.snapshot(),
                                 ensure_ascii=False, allow_nan=False).encode("utf-8")
                media, code = "application/json; charset=utf-8", 200
            elif self.path == "/frame.jpg" or frame_query:
                raw = state.display(clock())
                if raw is None:
                    self.send_error(503, "No fresh source-bound detection")
                    return
                media, code = "image/jpeg", 200
            elif self.path in ASSETS:
                file, media = ASSETS[self.path]
                raw = (ROOT / "host" / file).read_bytes()
                code = 200
            else:
                self.send_error(404)
                return
            self.send_response(code)
            self.send_header("Content-Type", media)
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'none'")
            self.end_headers()
            self.wfile.write(raw)

        def do_POST(self) -> None:
            self.send_error(405)

    return Handler


def run_link(connection: SerialPort, state: BridgeState, diagnostics: Diagnostics,
             stop: threading.Event, action: str = "bridge") -> None:
    parser = MixedParser()
    handshake_at = time.monotonic()
    write_command(connection, state.begin(secrets.token_hex(16)))
    action_sent = False
    while not stop.is_set():
        chunk = connection.read(4096)
        now = time.monotonic()
        for packet in parser.feed(chunk, now):
            if packet.kind == "jpeg":
                state.ingest(packet.data, now)
                continue
            event = parse_event(packet.data)
            kind = event["type"]
            if kind in ("hello", "status") and event.get("device") != state.device:
                raise ValueError("USB target is not the explicitly selected device")
            if kind == "hello":
                if not state.accept_hello(event):
                    raise ValueError("Device rejected the source-bound USB handshake")
            elif kind == "status":
                was_ready = state.ready
                if state.accept_status(event):
                    diagnostics.update(event, parser.errors)
                elif was_ready:
                    if action != "bridge" and action_sent:
                        raise RuntimeError("Device restart during local action; result unknown, no automatic retry")
                    # Same cable, new MCU boot/config identity: discard in-flight
                    # results and establish a fresh source session, not old counts.
                    handshake_at = now
                    write_command(connection, state.begin(secrets.token_hex(16)))
                    action_sent = False
            elif kind == "ack":
                if type(event.get("ok")) is not bool or not isinstance(event.get("code"), str):
                    raise ValueError("Invalid USB acknowledgment")
                if not event["ok"]:
                    raise ValueError(f"USB command rejected: {event['code']}")
                if action != "bridge" and action_sent:
                    if not state.accepts_action_ack(event, action):
                        raise ValueError("Invalid or uncorrelated USB action acknowledgment")
                    print(event["code"], flush=True)
                    return
        diagnostics.update(None, parser.errors)
        if not state.ready and now - handshake_at > 8:
            raise TimeoutError("No smart-room handshake. Do not replace/steal the old viewer's port")
        if state.ready and action != "bridge" and not action_sent:
            write_command(connection, state.local_command(action))
            action_sent = True
            handshake_at = now
        if action != "bridge" and action_sent and now - handshake_at > 8:
            raise TimeoutError("Local action result unknown; do not retry automatically")
        if action == "bridge":
            observation = state.observation(now)
            if observation is not None:
                write_command(connection, observation)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Separate smart-room bridge; never flashes firmware")
    parser.add_argument("--check", action="store_true", help="Read-only versions and preserved hashes, no serial")
    parser.add_argument("--port", help="Explicit COM port, never auto-discovered")
    parser.add_argument("--device", default="f024f91080a4", help="Expected device MAC as 12 lowercase hex digits")
    parser.add_argument("--allow-serial", action="store_true", help="Explicitly permit opening the selected port")
    parser.add_argument("--http-port", type=int, default=8082)
    parser.add_argument("--det-size", type=int, choices=(320, 448, 512, 640), default=640)
    parser.add_argument("--confidence", type=float, default=0.35)
    parser.add_argument("--action", choices=("bridge", "open_pairing", "reset_owner"), default="bridge")
    parser.add_argument("--confirm", default="", help="Required exact phrase for local pairing/owner actions")
    args = parser.parse_args(argv)
    if args.check:
        print(json.dumps(preflight(), indent=2, ensure_ascii=False))
        return 0
    if not 1 <= args.http_port <= 65535 or not math.isfinite(args.confidence) or not 0 < args.confidence < 1:
        parser.error("Invalid preview port/confidence")
    try:
        validate_port(args.port, allow_serial=args.allow_serial)
        state, diagnostics = BridgeState(args.device), Diagnostics()
        if args.action != "bridge":
            phrase = LOCAL_ACTIONS[args.action][0]
            if args.confirm != phrase:
                parser.error(f"This local action requires --confirm {phrase}; it changes pairing/ownership")
        preflight()
        stop = threading.Event()
        server: HTTPServer | None = None
        http_thread: threading.Thread | None = None
        worker: threading.Thread | None = None
        outcome = 0
        link_failed = False
        analyze = create_analyzer(args.det_size, args.confidence) if args.action == "bridge" else None
        with serial_link(args.port, allow_serial=args.allow_serial) as connection:
            try:
                if args.action == "bridge":
                    server = HTTPServer(("127.0.0.1", args.http_port), preview_handler(state, diagnostics))
                    http_thread = threading.Thread(target=server.serve_forever, daemon=True, name="smart-room-preview")
                    worker = threading.Thread(target=vision_worker, args=(state, analyze, stop), daemon=True, name="smart-room-vision")
                    http_thread.start()
                    worker.start()
                    print(f"Local-only preview: http://127.0.0.1:{args.http_port}/ — no image recording", flush=True)
                run_link(connection, state, diagnostics, stop, args.action)
                if state.snapshot(time.monotonic())["error"]:
                    outcome = 1
            except KeyboardInterrupt:
                print("Stopping only this bridge", flush=True)
            except Exception:
                # Do not append even an unknown packet to a failed/uncertain
                # transport. The device's existing TTL is the safety fallback.
                link_failed = True
                raise
            finally:
                stop.set()
                if args.action == "bridge" and state.ready and not link_failed:
                    state.detector_failed("Bridge stopped")
                    unknown = state.observation(time.monotonic())
                    if unknown is not None:
                        try:
                            write_command(connection, unknown)
                        except OSError as exc:
                            print(f"Unknown packet could not be delivered; controller TTL must expire: {exc}", file=sys.stderr)
                state.disconnect()
                if server is not None:
                    if http_thread is not None and http_thread.is_alive():
                        server.shutdown()
                    server.server_close()
                for thread in (http_thread, worker):
                    if thread is not None:
                        thread.join(timeout=5)
                        if thread.is_alive():
                            print(f"Owned {thread.name} did not stop within 5 s; no force-kill", file=sys.stderr)
                            outcome = 2
        return outcome
    except (OSError, ValueError, RuntimeError, TimeoutError) as exc:
        print(f"Bridge unavailable: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
