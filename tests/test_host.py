"""No hardware, model inference, network or old-viewer execution in this suite."""

from __future__ import annotations

import binascii
import json
import math
import struct
import unittest
from dataclasses import replace

from host.core import (
    BridgeState, CONTROL_MAGIC, Detection, JPEG_MAGIC, MixedParser, crc16,
    encode_control, parse_event, validate_port,
)

DEVICE = "f024f91080a4"
SESSION = "000102030405060708090a0b0c0d0e0f"
BOOT = "1011121314151617"
JPEG = b"\xff\xd8test-frame\xff\xd9"


def packet(magic: bytes, data: bytes) -> bytes:
    return magic + struct.pack("<IH", len(data), binascii.crc_hqx(data, 0xFFFF)) + data


def hello(**change: object) -> dict:
    return {"v": 1, "type": "hello", "device": DEVICE, "boot": BOOT,
            "session": SESSION, "ttl_ms": 2000, **change}


class WireTests(unittest.TestCase):
    def test_crc_independent_ccitt_false_check_value(self) -> None:
        self.assertEqual(crc16(b"123456789"), 0x29B1)

    def test_control_header_is_crc_length_and_exact_utf8(self) -> None:
        data = {"v": 1, "op": "hello", "session": SESSION}
        encoded = encode_control(data)
        self.assertEqual(encoded[:2], CONTROL_MAGIC)
        length, checksum = struct.unpack_from("<IH", encoded, 2)
        self.assertEqual(length, len(encoded) - 8)
        self.assertEqual(checksum, binascii.crc_hqx(encoded[8:], 0xFFFF))
        self.assertEqual(json.loads(encoded[8:]), data)

    def test_command_nesting_floats_bool_version_and_overflow_fail(self) -> None:
        for data in ({"v": 1, "op": "hello", "x": {}}, {"v": True, "op": "hello"},
                     {"v": 1, "op": "observe", "age_ms": 1.0},
                     {"v": 1, "op": "hello", "session": "a" * 800}):
            with self.subTest(data=str(data)[:80]), self.assertRaises(ValueError):
                encode_control(data)

    def test_mixed_packets_one_byte_fragments_and_boot_noise(self) -> None:
        parser = MixedParser()
        control = b'{"v":1,"type":"ack","id":0,"ok":true,"code":"ready"}'
        stream = b"boot message\r\n" + packet(JPEG_MAGIC, JPEG) + packet(CONTROL_MAGIC, control)
        result = []
        for byte in stream:
            result.extend(parser.feed(bytes([byte]), 1.0))
        self.assertEqual([(p.kind, p.data) for p in result], [("jpeg", JPEG), ("control", control)])
        self.assertEqual(parser.buffered, 0)

    def test_magic_inside_valid_jpeg_is_not_a_new_frame(self) -> None:
        image = b"\xff\xd8" + CONTROL_MAGIC + b"\x00\x00stuff" + JPEG_MAGIC + b"\xff\xd9"
        found = MixedParser().feed(packet(JPEG_MAGIC, image), 0.0)
        self.assertEqual(found[0].data, image)
        self.assertEqual(len(found), 1)

    def test_invalid_crc_and_invalid_jpeg_never_publish(self) -> None:
        parser = MixedParser()
        bad_crc = bytearray(packet(JPEG_MAGIC, JPEG)); bad_crc[6] ^= 1
        out = parser.feed(bytes(bad_crc) + packet(JPEG_MAGIC, b"not jpeg") + packet(JPEG_MAGIC, JPEG), 0.0)
        self.assertEqual([p.data for p in out], [JPEG])
        self.assertEqual(parser.errors, 2)

    def test_invalid_length_recovers_without_allocating_claimed_size(self) -> None:
        parser = MixedParser()
        invalid = JPEG_MAGIC + struct.pack("<IH", 0xFFFFFFFF, 0)
        out = parser.feed(invalid + packet(JPEG_MAGIC, JPEG), 0.0)
        self.assertEqual([p.data for p in out], [JPEG])
        self.assertEqual(parser.errors, 1)
        self.assertLessEqual(parser.buffered, 1)

    def test_truncated_packet_has_fixed_deadline_and_resynchronizes(self) -> None:
        parser = MixedParser()
        self.assertEqual(parser.feed(packet(JPEG_MAGIC, JPEG)[:10], 0.0), [])
        self.assertEqual(parser.feed(b"x", 3.9), [])
        out = parser.feed(packet(JPEG_MAGIC, JPEG), 4.01)
        self.assertEqual([p.data for p in out], [JPEG])
        self.assertEqual(parser.errors, 1)

    def test_oversized_chunk_and_nonfinite_time_are_not_accepted(self) -> None:
        for chunk, now in ((b"x" * 8193, 0.0), (b"x", math.nan), (b"x", -1.0)):
            with self.assertRaises(ValueError):
                MixedParser().feed(chunk, now)

    def test_event_exact_version_and_duplicate_keys(self) -> None:
        self.assertEqual(parse_event(b'{"v":1,"type":"ack","id":9}')["id"], 9)
        for data in (b'{"v":true,"type":"ack"}', b'{"v":1,"v":1,"type":"ack"}',
                     b'{"v":1,"type":"ack","x":NaN}', b"\xff", b"{}"):
            with self.subTest(data=data), self.assertRaises(ValueError):
                parse_event(data)

    def test_deep_or_large_event_is_bounded_before_decoding(self) -> None:
        for data in (b'{"v":1,"type":"status","x":' + b"[" * 10 + b"0" + b"]" * 10 + b"}", b" " * 4096):
            with self.assertRaises(ValueError):
                parse_event(data)

    def test_serial_requires_explicit_opt_in_and_canonical_port(self) -> None:
        self.assertEqual(validate_port("COM13", allow_serial=True), "COM13")
        for port, allow in (("COM13", False), ("COM0", True), ("COM999", True),
                            ("\\\\.\\COM13", True), ("COM13;dir", True), ("com13", True)):
            with self.subTest(port=port), self.assertRaises(ValueError):
                validate_port(port, allow_serial=allow)


class SourceTests(unittest.TestCase):
    def state(self) -> BridgeState:
        state = BridgeState(DEVICE)
        self.assertEqual(state.begin(SESSION), {"v": 1, "op": "hello", "session": SESSION})
        self.assertTrue(state.accept_hello(hello()))
        return state

    def test_no_measurement_before_source_bound_handshake(self) -> None:
        state = BridgeState(DEVICE); state.begin(SESSION); state.ingest(JPEG, 0.0)
        self.assertIsNone(state.take_source())
        self.assertIsNone(state.observation(1.0))

    def test_wrong_board_nonce_ttl_and_boolean_fields_do_not_authorize(self) -> None:
        state = BridgeState(DEVICE); state.begin(SESSION)
        for change in ({"device": "001122334455"}, {"session": "1" * 32},
                       {"ttl_ms": True}, {"ttl_ms": 999}, {"boot": "wrong"}, {"v": True}):
            with self.subTest(change=change):
                self.assertFalse(state.accept_hello(hello(**change)))

    def test_current_result_transmits_original_source_age_once(self) -> None:
        state = self.state(); state.ingest(JPEG, 10.0)
        source = state.take_source(); self.assertIsNotNone(source)
        self.assertTrue(state.publish(Detection(source, 4), 10.5))
        observation = state.observation(10.8)
        self.assertEqual(observation, {"v": 1, "op": "observe", "session": SESSION,
                                      "seq": 1, "frame": 1, "age_ms": 800, "people": 4})
        self.assertIsNone(state.observation(10.9))

    def test_fresh_zero_remains_zero_not_unknown(self) -> None:
        state = self.state(); state.ingest(JPEG, 1.0); source = state.take_source()
        self.assertTrue(state.publish(Detection(source, 0), 1.1))
        self.assertEqual(state.observation(1.2)["people"], 0)

    def test_expired_zero_sends_unknown_and_never_renews_age(self) -> None:
        state = self.state(); state.ingest(JPEG, 1.0); source = state.take_source()
        self.assertTrue(state.publish(Detection(source, 0), 1.1))
        self.assertEqual(state.observation(1.2)["people"], 0)
        unknown = state.observation(3.01)
        self.assertEqual(unknown["people"], -1)
        self.assertEqual(unknown["seq"], 2)
        self.assertIsNone(state.observation(4.0))

    def test_initial_handshake_unknown_is_not_invented_zero(self) -> None:
        state = self.state()
        self.assertEqual(state.observation(0.0)["people"], -1)

    def test_latest_only_queue_does_not_queue_every_frame(self) -> None:
        state = self.state()
        for index in range(200):
            state.ingest(JPEG + b"", float(index))
        self.assertEqual(state.take_source().sequence, 200)
        self.assertIsNone(state.take_source())

    def test_forged_same_sequence_source_and_future_time_are_rejected(self) -> None:
        state = self.state(); state.ingest(JPEG, 10.0); source = state.take_source()
        self.assertFalse(state.publish(Detection(replace(source, jpeg=b"fake"), 0), 10.1))
        self.assertFalse(state.publish(Detection(source, 0), 9.9))

    def test_stale_and_invalid_detector_results_never_publish(self) -> None:
        for people, completed in ((True, 1.1), (-1, 1.1), (101, 1.1), (2, 3.01), (2, math.nan)):
            state = self.state(); state.ingest(JPEG, 1.0); source = state.take_source()
            self.assertFalse(state.publish(Detection(source, people), completed))

    def test_disconnect_invalidates_inflight_and_no_old_result_after_reconnect(self) -> None:
        state = self.state(); state.ingest(JPEG, 1.0); old = state.take_source(); old_epoch = state.epoch
        state.disconnect(); state.begin(SESSION)
        self.assertTrue(state.accept_hello(hello(boot="2222222222222222")))
        self.assertGreater(state.epoch, old_epoch)
        self.assertFalse(state.publish(Detection(old, 0), 1.1))
        self.assertEqual(state.observation(1.1)["people"], -1)

    def test_device_restart_removes_handshake_until_new_hello(self) -> None:
        state = self.state()
        self.assertFalse(state.accept_status({"v": 1, "type": "status", "device": DEVICE,
                                             "boot": "9999999999999999"}))
        state.ingest(JPEG, 1.0); self.assertIsNone(state.take_source())
        self.assertIsNone(state.observation(1.0))


if __name__ == "__main__":
    unittest.main()
