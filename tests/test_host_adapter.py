from __future__ import annotations

import unittest
from unittest.mock import Mock

from host.bridge import detect_once, serial_link, write_command
from host.core import BridgeState, Detection


class FakeSerial:
    def __init__(self, fail_open: bool = False) -> None:
        self.fail_open = fail_open
        self.opened = self.closed = False
        self.at_open = None
        self.writes = []

    def open(self) -> None:
        self.at_open = (self.port, self.baudrate, self.dtr, self.rts, self.timeout, self.write_timeout)
        if self.fail_open:
            raise OSError('inert open failure')
        self.opened = True

    def close(self) -> None:
        self.closed = True

    def write(self, data: bytes) -> int:
        self.writes.append(data)
        return len(data)


class AdapterTests(unittest.TestCase):
    def test_no_permission_means_not_even_constructing_serial(self) -> None:
        factory = Mock()
        with self.assertRaises(ValueError):
            with serial_link('COM13', allow_serial=False, factory=factory):
                self.fail('must not open serial')
        factory.assert_not_called()

    def test_dtr_rts_and_deadlines_are_set_before_open(self) -> None:
        connection = FakeSerial()
        with serial_link('COM13', allow_serial=True, factory=lambda: connection) as handle:
            self.assertIs(handle, connection)
            self.assertEqual(connection.at_open, ('COM13', 921600, False, False, 0.05, 0.3))
        self.assertTrue(connection.closed)

    def test_failed_open_still_closes_only_owned_adapter(self) -> None:
        connection = FakeSerial(True)
        with self.assertRaises(OSError):
            with serial_link('COM13', allow_serial=True, factory=lambda: connection):
                self.fail('expected open failure')
        self.assertTrue(connection.closed)

    def test_partial_write_is_failure_not_retry(self) -> None:
        connection = Mock(); connection.write.return_value = 1
        with self.assertRaises(OSError):
            write_command(connection, {'v': 1, 'op': 'status'})
        self.assertEqual(connection.write.call_count, 1)

    def test_detector_sees_the_same_immutable_source_and_no_duplicate_work(self) -> None:
        state = BridgeState('f024f91080a4'); session = '01' * 16
        state.begin(session)
        state.accept_hello({'v': 1, 'type': 'hello', 'session': session,
                            'device': state.device, 'boot': '02' * 8, 'ttl_ms': 2000})
        state.ingest(b'\xff\xd8inert\xff\xd9', 1.0)
        sources = []

        def analyze(source):
            sources.append(source)
            return Detection(source, 3)

        self.assertTrue(detect_once(state, analyze, lambda: 1.3))
        self.assertFalse(detect_once(state, analyze, lambda: 1.4))
        self.assertEqual(len(sources), 1)
        self.assertEqual(state.observation(1.5)['people'], 3)

    def test_detector_error_removes_zero_and_marks_explicit_unknown(self) -> None:
        state = BridgeState('f024f91080a4'); session = '01' * 16; state.begin(session)
        state.accept_hello({'v': 1, 'type': 'hello', 'session': session,
                            'device': state.device, 'boot': '02' * 8, 'ttl_ms': 2000})
        state.ingest(b'\xff\xd8inert\xff\xd9', 1.0)
        self.assertTrue(detect_once(state, lambda source: Detection(source, 0), lambda: 1.1))
        self.assertEqual(state.observation(1.2)['people'], 0)
        state.detector_failed('inert detector error')
        self.assertEqual(state.observation(1.3)['people'], -1)
        self.assertIsNone(state.display(1.3))
        self.assertEqual(state.snapshot(1.3)['status'], 'error')


if __name__ == '__main__':
    unittest.main()
