"""Owned fake serial / bounded loopback HTTP controls; never opens a COM port."""

from __future__ import annotations

import contextlib
import io
import json
import struct
import threading
import unittest
from http.client import HTTPConnection
from http.server import HTTPServer
from types import SimpleNamespace
from unittest.mock import Mock, patch

from host import bridge
from host.core import BridgeState, Detection, crc16

DEVICE = "f024f91080a4"
BOOT = "1011121314151617"
SESSION = "01" * 16
JPEG = b"\xff\xd8inert-runtime-frame\xff\xd9"


def event_packet(event: dict) -> bytes:
    raw = json.dumps(event, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return b"\xc3\x3c" + struct.pack("<IH", len(raw), crc16(raw)) + raw


def jpeg_packet() -> bytes:
    return b"\xa5\x5a" + struct.pack("<IH", len(JPEG), crc16(JPEG)) + JPEG


def hello(session: str, boot: str = BOOT) -> dict:
    return {"v": 1, "type": "hello", "device": DEVICE, "boot": boot,
            "session": session, "ttl_ms": 2000}


class ScriptSerial:
    """Every read is a finite fixture action; exhaustion stops the owned loop."""

    def __init__(self, stop: threading.Event, steps=()) -> None:
        self.stop = stop
        self.steps = list(steps)
        self.writes: list[dict] = []
        self.now = 10.0
        self.closed = False

    def read(self, size: int) -> bytes:
        if size != 4096:
            raise AssertionError("Unexpected serial read bound")
        if not self.steps:
            self.stop.set()
            return b""
        return self.steps.pop(0)(self)

    def write(self, packet: bytes) -> int:
        if packet[:2] != b"\xc3\x3c":
            raise AssertionError("Unexpected command magic")
        length, checksum = struct.unpack_from("<IH", packet, 2)
        if length != len(packet) - 8 or checksum != crc16(packet[8:]):
            raise AssertionError("Invalid fixture command frame")
        self.writes.append(json.loads(packet[8:]))
        return len(packet)

    def close(self) -> None:
        self.closed = True

    def handshake(self) -> bytes:
        return event_packet(hello(self.writes[-1]["session"]))

    def action_ack(self, code: str, **changes) -> bytes:
        action = self.writes[-1]
        return event_packet({"v": 1, "type": "ack", "id": action.get("id", 0),
                             "session": action.get("session", self.writes[0]["session"]),
                             "ok": True, "code": code, **changes})


class LinkRuntimeTests(unittest.TestCase):
    def run_fixture(self, steps, action="bridge"):
        state, diagnostics, stop = BridgeState(DEVICE), bridge.Diagnostics(), threading.Event()
        connection = ScriptSerial(stop)
        connection.steps = list(steps(state, connection))
        tokens = iter([SESSION, "02" * 16, "03" * 16])
        with patch.object(bridge, "time", SimpleNamespace(monotonic=lambda: connection.now)), \
                patch.object(bridge.secrets, "token_hex", side_effect=lambda _: next(tokens)):
            bridge.run_link(connection, state, diagnostics, stop, action)
        return state, diagnostics, connection

    def test_actual_loop_mixed_frames_and_original_age_sent_only_once(self) -> None:
        def steps(state, connection):
            def detect(port):
                port.now = 10.5
                self.assertTrue(bridge.detect_once(state, lambda source: Detection(source, 4), lambda: port.now))
                return b""
            return [lambda port: b"boot noise\r\n" + port.handshake() + jpeg_packet(), detect]

        state, diagnostics, connection = self.run_fixture(steps)
        self.assertTrue(state.ready)
        self.assertEqual([c["op"] for c in connection.writes], ["hello", "observe", "observe"])
        self.assertEqual(connection.writes[-1], {"v": 1, "op": "observe", "session": SESSION,
                                                "seq": 2, "frame": 1, "age_ms": 500, "people": 4})
        self.assertEqual(diagnostics.snapshot()["stream_errors"], 0)

    def test_wrong_target_never_receives_an_occupancy_command(self) -> None:
        def steps(_state, connection):
            wrong = hello(SESSION) | {"device": "001122334455"}
            return [lambda _port: event_packet(wrong)]
        with self.assertRaisesRegex(ValueError, "explicitly selected device"):
            self.run_fixture(steps)

    def test_handshake_timeout_is_terminal_not_a_port_search_or_retry(self) -> None:
        def steps(_state, _connection):
            def expire(port):
                port.now += 8.01
                return b""
            return [expire]
        with self.assertRaisesRegex(TimeoutError, "handshake"):
            self.run_fixture(steps)

    def test_reboot_rebinds_source_and_rejects_previous_inflight_detection(self) -> None:
        retained = []
        new_boot = "99" * 8
        def steps(state, _connection):
            def reboot(port):
                retained.append(state.take_source())
                port.now += 0.1
                return event_packet({"v": 1, "type": "status", "device": DEVICE, "boot": new_boot})
            def bind(port):
                self.assertFalse(state.publish(Detection(retained[0], 0), port.now))
                return event_packet(hello(port.writes[-1]["session"], new_boot)) + jpeg_packet()
            def detect(port):
                port.now += 0.2
                self.assertTrue(bridge.detect_once(state, lambda source: Detection(source, 3), lambda: port.now))
                return b""
            return [lambda port: port.handshake() + jpeg_packet(), reboot, bind, detect]
        state, _, connection = self.run_fixture(steps)
        self.assertEqual([c["session"] for c in connection.writes if c["op"] == "hello"], [SESSION, "02" * 16])
        self.assertEqual(connection.writes[-1]["session"], "02" * 16)
        self.assertEqual(connection.writes[-1]["people"], 3)
        self.assertEqual(state.snapshot(connection.now)["boot"], new_boot)

    def test_local_action_requires_its_specific_success_code(self) -> None:
        with self.assertRaisesRegex(ValueError, "acknowledgment|acknowledgement"):
            self.run_fixture(lambda _state, _connection: [lambda port: port.handshake(),
                lambda port: port.action_ack("some_positive_ack")], action="open_pairing")

    def test_local_action_rejects_a_success_from_another_session(self) -> None:
        with self.assertRaisesRegex(ValueError, "acknowledgment|acknowledgement"):
            self.run_fixture(lambda _state, _connection: [lambda port: port.handshake(),
                lambda port: port.action_ack("pairing_window_open", session="fe" * 16)], action="open_pairing")

    def test_local_action_rejects_wrong_or_boolean_request_id(self) -> None:
        for bad in (2, True):
            with self.subTest(id=bad), self.assertRaisesRegex(ValueError, "acknowledgment|acknowledgement"):
                self.run_fixture(lambda _state, _connection: [lambda port: port.handshake(),
                    lambda port: port.action_ack("pairing_window_open", id=bad)], action="open_pairing")

    def test_specific_local_action_is_bound_to_the_new_handshake(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            _, _, connection = self.run_fixture(lambda _state, _connection: [lambda port: port.handshake(),
                lambda port: port.action_ack("pairing_window_open")], action="open_pairing")
        self.assertEqual(connection.writes[-1], {"v": 1, "op": "open_pairing", "id": 1,
            "session": SESSION, "confirm": "LOCAL_PAIRING_WINDOW"})
        self.assertEqual(output.getvalue().strip(), "pairing_window_open")

    def test_restart_during_local_action_never_automatically_repeats_it(self) -> None:
        def steps(_state, _connection):
            return [lambda port: port.handshake(), lambda _port: event_packet({
                "v": 1, "type": "status", "device": DEVICE, "boot": "99" * 8})]
        with self.assertRaisesRegex(RuntimeError, "unknown|restart"):
            self.run_fixture(steps, action="reset_owner")


class PreviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.now = 10.0
        self.state = BridgeState(DEVICE)
        self.state.begin(SESSION)
        self.state.accept_hello(hello(SESSION))
        self.diagnostics = bridge.Diagnostics()
        self.server = HTTPServer(("127.0.0.1", 0), bridge.preview_handler(
            self.state, self.diagnostics, lambda: self.now))
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=lambda: self.server.serve_forever(poll_interval=0.02),
                                       name="test-owned-preview")
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)
        self.assertFalse(self.thread.is_alive(), "Owned preview did not terminate")
        replacement = HTTPServer(("127.0.0.1", self.port), bridge.preview_handler(self.state, self.diagnostics))
        replacement.server_close()

    def request(self, path, method="GET"):
        connection = HTTPConnection("127.0.0.1", self.port, timeout=2)
        try:
            connection.request(method, path)
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def test_unknown_and_stale_frames_are_not_published_as_current_zero(self) -> None:
        code, _, raw = self.request("/status")
        self.assertEqual(code, 200)
        self.assertIsNone(json.loads(raw)["people"])
        self.assertEqual(self.request("/frame.jpg")[0], 503)
        self.state.ingest(JPEG, self.now)
        self.state.publish(Detection(self.state.take_source(), 0), self.now)
        code, headers, raw = self.request("/frame.jpg?123")
        self.assertEqual((code, raw), (200, JPEG))
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(json.loads(self.request("/status")[2])["people"], 0)
        self.now += 2.01
        self.assertIsNone(json.loads(self.request("/status")[2])["people"])
        self.assertEqual(self.request("/frame.jpg?124")[0], 503)

    def test_asset_allowlist_no_source_browsing_and_no_control_route(self) -> None:
        for path in ("/", "/page.js", "/page.css"):
            code, headers, raw = self.request(path)
            self.assertEqual(code, 200)
            self.assertTrue(raw)
            self.assertIn("frame-ancestors 'none'", headers["Content-Security-Policy"])
            self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        for path in ("/README.md", "/../PLAN.md", "/%2e%2e/PLAN.md", "/status?on=1", "/frame.jpg?invalid"):
            self.assertEqual(self.request(path)[0], 404, path)
        self.assertEqual(self.request("/status", "POST")[0], 405)


class MainLifetimeTests(unittest.TestCase):
    def test_absent_serial_permission_or_confirmation_never_constructs_adapter(self) -> None:
        with patch.object(bridge, "serial_link") as factory, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(bridge.main([]), 1)
            with self.assertRaises(SystemExit) as error:
                bridge.main(["--port", "COM13", "--allow-serial", "--action", "reset_owner"])
            self.assertEqual(error.exception.code, 2)
        factory.assert_not_called()

    def test_vision_worker_exception_is_visible_terminal_and_not_zero(self) -> None:
        state, stop = BridgeState(DEVICE), threading.Event()
        state.begin(SESSION)
        state.accept_hello(hello(SESSION))
        state.ingest(JPEG, 10.0)
        errors = io.StringIO()
        def fail(_source):
            raise RuntimeError("inert detector regression")
        with contextlib.redirect_stderr(errors):
            worker = threading.Thread(target=bridge.vision_worker, args=(state, fail, stop))
            worker.start()
            worker.join(2)
        self.assertFalse(worker.is_alive())
        self.assertTrue(stop.is_set())
        self.assertEqual(state.snapshot(10.0)["status"], "error")
        self.assertEqual(state.observation(10.0)["people"], -1)
        self.assertIn("inert detector regression", errors.getvalue())

    def run_main(self, run_loop, partial=False):
        stop = threading.Event()
        connection = ScriptSerial(stop)
        shutdown = threading.Event()
        server = Mock()
        server.serve_forever.side_effect = lambda: shutdown.wait(2)
        server.shutdown.side_effect = shutdown.set
        if partial:
            full_write = connection.write
            connection.write = lambda packet: full_write(packet) - 1
        @contextlib.contextmanager
        def owned_fake(*_args, **_kwargs):
            try:
                yield connection
            finally:
                connection.close()
        with patch.object(bridge, "serial_link", side_effect=owned_fake), \
                patch.object(bridge, "preflight", return_value={}), \
                patch.object(bridge, "create_analyzer", return_value=lambda source: Detection(source, 0)), \
                patch.object(bridge, "HTTPServer", return_value=server), \
                patch.object(bridge, "run_link", side_effect=run_loop), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            result = bridge.main(["--port", "COM13", "--allow-serial"])
        self.assertTrue(connection.closed)
        server.shutdown.assert_called_once()
        server.server_close.assert_called_once()
        self.assertFalse(any(t.name in ("smart-room-preview", "smart-room-vision")
                             for t in threading.enumerate()))
        return result, connection

    def test_clean_shutdown_attempts_one_unknown_then_releases_resources(self) -> None:
        retained = []
        def finish(_connection, state, _diagnostics, _stop, _action):
            state.begin(SESSION)
            state.accept_hello(hello(SESSION))
            retained.append(state)
        result, connection = self.run_main(finish)
        self.assertEqual(result, 0)
        self.assertEqual([c["people"] for c in connection.writes], [-1])
        self.assertFalse(retained[0].ready)

    def test_partial_serial_write_does_not_trigger_an_extra_shutdown_write(self) -> None:
        def fail(connection, state, _diagnostics, _stop, _action):
            state.begin(SESSION)
            state.accept_hello(hello(SESSION))
            bridge.write_command(connection, {"v": 1, "op": "status"})
        result, connection = self.run_main(fail, partial=True)
        self.assertEqual(result, 1)
        self.assertEqual([c["op"] for c in connection.writes], ["status"])


if __name__ == "__main__":
    unittest.main()
