"""Bounded wire and source-association policies, independent of OpenCV/serial."""

from __future__ import annotations

import binascii
import json
import math
import re
import struct
import threading
from dataclasses import dataclass

JPEG_MAGIC = b"\xa5\x5a"
CONTROL_MAGIC = b"\xc3\x3c"
MAX_JPEG = 256000
MAX_EVENT = 4095
LOCAL_ACTIONS = {
    "open_pairing": ("LOCAL_PAIRING_WINDOW", "pairing_window_open"),
    "reset_owner": ("ERASE_OWNER_AND_BONDS", "owner_reset_bond_removal_requested"),
}


def finite_time(value: float) -> bool:
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def valid_hex(value: object, count: int) -> bool:
    return isinstance(value, str) and re.fullmatch(rf"[0-9a-f]{{{count * 2}}}", value) is not None


def crc16(data: bytes) -> int:
    return binascii.crc_hqx(data, 0xFFFF)


def encode_control(data: dict) -> bytes:
    if (not isinstance(data, dict) or not 2 <= len(data) <= 32
            or type(data.get("v")) is not int or data["v"] != 1
            or not isinstance(data.get("op"), str)
            or re.fullmatch(r"[a-z_]{1,24}", data["op"]) is None):
        raise ValueError("Invalid USB command envelope")
    for key, value in data.items():
        if (not isinstance(key, str) or re.fullmatch(r"[a-z][a-z0-9_]{0,23}", key) is None
                or type(value) not in (str, bool, int)
                or (type(value) is int and not -2147483648 <= value <= 4294967295)
                or (isinstance(value, str) and "\x00" in value)):
            raise ValueError("USB commands require bounded flat scalar fields")
    raw = json.dumps(data, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    if len(raw) > 768:
        raise ValueError("USB command exceeds 768 UTF-8 bytes")
    return CONTROL_MAGIC + struct.pack("<IH", len(raw), crc16(raw)) + raw


def guard_depth(data: bytes) -> None:
    depth = 0
    quoted = escaped = False
    for byte in data:
        if quoted:
            if escaped:
                escaped = False
            elif byte == 92:
                escaped = True
            elif byte == 34:
                quoted = False
        elif byte == 34:
            quoted = True
        elif byte in (91, 123):
            depth += 1
            if depth > 6:
                raise ValueError("Event nesting limit")
        elif byte in (93, 125):
            depth -= 1
            if depth < 0:
                raise ValueError("Event nesting mismatch")
    if depth or quoted:
        raise ValueError("Incomplete event")


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate event field")
        result[key] = value
    return result


def no_constant(_value: str) -> None:
    raise ValueError("Nonfinite JSON number")


def parse_event(data: bytes) -> dict:
    if not isinstance(data, bytes) or not 1 <= len(data) <= MAX_EVENT:
        raise ValueError("Event size limit")
    guard_depth(data)
    decoded = json.loads(data.decode("utf-8"), object_pairs_hook=unique_object, parse_constant=no_constant)
    nodes = 0

    def bounded(value: object) -> None:
        nonlocal nodes
        nodes += 1
        if nodes > 256:
            raise ValueError("Event node limit")
        if isinstance(value, dict):
            if len(value) > 64:
                raise ValueError("Event field limit")
            for key, item in value.items():
                if not isinstance(key, str) or not 1 <= len(key) <= 64:
                    raise ValueError("Invalid event field")
                bounded(item)
        elif isinstance(value, list):
            if len(value) > 32:
                raise ValueError("Event list limit")
            for item in value:
                bounded(item)
        elif isinstance(value, str):
            if len(value.encode("utf-8")) > 1024 or "\x00" in value:
                raise ValueError("Event string limit")
        elif type(value) is int:
            if not -2147483648 <= value <= 4294967295:
                raise ValueError("Event integer limit")
        elif value is not None and type(value) is not bool:
            raise ValueError("Invalid event scalar")

    bounded(decoded)
    if (not isinstance(decoded, dict) or type(decoded.get("v")) is not int or decoded["v"] != 1
            or not isinstance(decoded.get("type"), str)
            or re.fullmatch(r"[a-z_]{1,32}", decoded["type"]) is None):
        raise ValueError("Invalid event envelope")
    return decoded


def validate_port(port: str, *, allow_serial: bool) -> str:
    if (allow_serial is not True or not isinstance(port, str)
            or re.fullmatch(r"COM[1-9][0-9]{0,2}", port) is None or int(port[3:]) > 256):
        raise ValueError("Serial is opt-in; choose one canonical COM1..COM256 port")
    return port


@dataclass(frozen=True)
class Packet:
    kind: str
    data: bytes


class MixedParser:
    def __init__(self) -> None:
        self.errors = 0
        self._buffer = bytearray()
        self._started: float | None = None
        self._last_time = 0.0

    def feed(self, chunk: bytes, now: float) -> list[Packet]:
        if not isinstance(chunk, bytes) or len(chunk) > 8192 or not finite_time(now) or now < self._last_time:
            raise ValueError("Invalid parser chunk or monotonic receipt time")
        self._last_time = now
        if self._started is not None and now - self._started > 4.0:
            self._buffer.clear()
            self._started = None
            self.errors += 1
        self._buffer.extend(chunk)
        packets = []
        while self._buffer:
            indexes = [index for magic in (JPEG_MAGIC, CONTROL_MAGIC)
                       if (index := self._buffer.find(magic)) >= 0]
            if not indexes:
                if self._buffer[-1] in (JPEG_MAGIC[0], CONTROL_MAGIC[0]):
                    del self._buffer[:-1]
                else:
                    self._buffer.clear()
                self._started = None
                break
            index = min(indexes)
            if index:
                del self._buffer[:index]
                self._started = None
            if self._started is None:
                self._started = now
            if len(self._buffer) < 8:
                break
            jpeg = self._buffer[:2] == JPEG_MAGIC
            length, checksum = struct.unpack_from("<IH", self._buffer, 2)
            if not 1 <= length <= (MAX_JPEG if jpeg else MAX_EVENT):
                del self._buffer[0]
                self._started = None
                self.errors += 1
                continue
            if len(self._buffer) < length + 8:
                break
            raw = bytes(self._buffer[8:8 + length])
            del self._buffer[:8 + length]
            self._started = None
            if crc16(raw) != checksum or (jpeg and (raw[:2] != b"\xff\xd8" or raw[-2:] != b"\xff\xd9")):
                self.errors += 1
                continue
            packets.append(Packet("jpeg" if jpeg else "control", raw))
        # A valid pending frame is bounded by its checked header + one read chunk.
        if len(self._buffer) > MAX_JPEG + 8:
            raise ValueError("Parser bound violated")
        return packets

    @property
    def buffered(self) -> int:
        return len(self._buffer)


@dataclass(frozen=True)
class SourceFrame:
    epoch: int
    sequence: int
    device: str
    boot: str
    received_at: float
    jpeg: bytes


@dataclass(frozen=True)
class Detection:
    source: SourceFrame
    people: int
    elapsed_ms: float = 0.0
    annotated: bytes | None = None


class BridgeState:
    def __init__(self, device: str) -> None:
        if not valid_hex(device, 6):
            raise ValueError("Device ID must be 12 lowercase MAC hex digits")
        self.device = device
        self.epoch = 0
        self._lock = threading.RLock()
        self.available = threading.Event()
        self._session = ""
        self._boot = ""
        self._ready = False
        self._ttl_ms = 2000
        self._latest: SourceFrame | None = None
        self._active: SourceFrame | None = None
        self._result: Detection | None = None
        self._frame_sequence = self._wire_sequence = self._sent_frame = 0
        self._unknown_sent = False
        self._error = ""

    def _invalidate(self) -> None:
        self.epoch += 1
        self._ready = False
        self._boot = ""
        self._latest = self._active = self._result = None
        self._frame_sequence = self._wire_sequence = self._sent_frame = 0
        self._unknown_sent = False
        self.available.clear()

    def begin(self, session: str) -> dict:
        if not valid_hex(session, 16):
            raise ValueError("USB session must have 16 random bytes as hex")
        with self._lock:
            self._invalidate()
            self._error = ""
            self._session = session
            return {"v": 1, "op": "hello", "session": session}

    def accept_hello(self, event: dict) -> bool:
        with self._lock:
            if (not isinstance(event, dict) or set(event) != {"v", "type", "device", "boot", "session", "ttl_ms"}
                    or type(event.get("v")) is not int or event["v"] != 1 or event["type"] != "hello"
                    or event["device"] != self.device or event["session"] != self._session
                    or not valid_hex(event["boot"], 8) or type(event["ttl_ms"]) is not int
                    or not 1000 <= event["ttl_ms"] <= 10000):
                return False
            if self._ready and self._boot != event["boot"]:
                self._invalidate()
            self._boot = event["boot"]
            self._ttl_ms = event["ttl_ms"]
            self._ready = True
            return True

    def accept_status(self, event: dict) -> bool:
        with self._lock:
            if (not isinstance(event, dict) or type(event.get("v")) is not int or event["v"] != 1
                    or event.get("type") != "status" or event.get("device") != self.device
                    or not self._ready or event.get("boot") != self._boot):
                if self._ready:
                    self._invalidate()
                return False
            config = event.get("config")
            if isinstance(config, dict):
                ttl = config.get("ttl_ms")
                if type(ttl) is not int or not 1000 <= ttl <= 10000:
                    self._invalidate()
                    return False
                self._ttl_ms = ttl
            return True

    def ingest(self, jpeg: bytes, now: float) -> None:
        if (not isinstance(jpeg, bytes) or not 4 <= len(jpeg) <= MAX_JPEG
                or jpeg[:2] != b"\xff\xd8" or jpeg[-2:] != b"\xff\xd9" or not finite_time(now)):
            raise ValueError("Invalid source JPEG or receipt time")
        with self._lock:
            if not self._ready or self._error:
                return
            if self._frame_sequence == 2147483647:
                raise ValueError("Frame sequence exhausted; reconnect explicitly")
            self._frame_sequence += 1
            self._latest = SourceFrame(self.epoch, self._frame_sequence, self.device,
                                       self._boot, now, bytes(jpeg))
            self.available.set()

    def take_source(self) -> SourceFrame | None:
        with self._lock:
            if not self._ready or self._active is not None:
                return None
            source = self._latest
            self._latest = None
            self.available.clear()
            self._active = source
            return source

    def publish(self, result: Detection, now: float) -> bool:
        with self._lock:
            if not isinstance(result, Detection) or result.source is not self._active or self._active is None:
                return False
            source = result.source
            self._active = None
            if (not self._ready or self._error or source.epoch != self.epoch or source.device != self.device
                    or source.boot != self._boot or not finite_time(now) or now < source.received_at
                    or (now - source.received_at) * 1000 > self._ttl_ms
                    or type(result.people) is not int or not 0 <= result.people <= 100
                    or not finite_time(result.elapsed_ms)
                    or (result.annotated is not None and (not isinstance(result.annotated, bytes)
                        or len(result.annotated) > MAX_JPEG))):
                return False
            self._result = result
            return True

    def _fresh_result(self, now: float) -> Detection | None:
        result = self._result
        if (not self._ready or self._error or result is None or not finite_time(now)
                or now < result.source.received_at or (now - result.source.received_at) * 1000 > self._ttl_ms):
            return None
        return result

    def observation(self, now: float) -> dict | None:
        if not finite_time(now):
            raise ValueError("Invalid observation time")
        with self._lock:
            if not self._ready:
                return None
            result = self._fresh_result(now)
            if result is not None:
                if result.source.sequence <= self._sent_frame:
                    return None  # Never give one old frame a new freshness lease.
                age = max(0, math.ceil((now - result.source.received_at) * 1000 - 1e-6))
                if age > self._ttl_ms:
                    result = None
            if result is None:
                if self._unknown_sent:
                    return None
                people, frame, age = -1, self._sent_frame, 0
                self._unknown_sent = True
            else:
                people, frame = result.people, result.source.sequence
                self._sent_frame = frame
                self._unknown_sent = False
            if self._wire_sequence == 2147483647:
                raise ValueError("Observation sequence exhausted; reconnect explicitly")
            self._wire_sequence += 1
            return {"v": 1, "op": "observe", "session": self._session,
                    "seq": self._wire_sequence, "frame": frame, "age_ms": age, "people": people}

    def local_command(self, action: str) -> dict:
        with self._lock:
            if not self._ready or action not in LOCAL_ACTIONS:
                raise ValueError("Local action requires the current source handshake")
            return {"v": 1, "op": action, "id": 1, "session": self._session,
                    "confirm": LOCAL_ACTIONS[action][0]}

    def accepts_action_ack(self, event: dict, action: str) -> bool:
        with self._lock:
            return (self._ready and action in LOCAL_ACTIONS and isinstance(event, dict)
                    and set(event) == {"v", "type", "id", "session", "ok", "code"}
                    and type(event["v"]) is int and event["v"] == 1 and event["type"] == "ack"
                    and type(event["id"]) is int and event["id"] == 1
                    and event["session"] == self._session and event["ok"] is True
                    and event["code"] == LOCAL_ACTIONS[action][1])

    def disconnect(self) -> None:
        with self._lock:
            self._invalidate()
            self._session = ""

    def detector_failed(self, message: str) -> None:
        with self._lock:
            self._error = str(message)[:250]
            self._result = self._latest = self._active = None
            self._unknown_sent = False

    def snapshot(self, now: float) -> dict:
        with self._lock:
            result = self._fresh_result(now)
            return {"device": self.device, "boot": self._boot, "connected": self._ready,
                    "people": result.people if result else None,
                    "status": "error" if self._error else "ready" if result else "unknown",
                    "source_seq": result.source.sequence if result else None,
                    "result_age_ms": round((now - result.source.received_at) * 1000, 1) if result else None,
                    "det_ms": round(result.elapsed_ms, 1) if result else None, "error": self._error}

    def display(self, now: float) -> bytes | None:
        with self._lock:
            result = self._fresh_result(now)
            return (result.annotated or result.source.jpeg) if result else None

    @property
    def ready(self) -> bool:
        with self._lock:
            return self._ready
