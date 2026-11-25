"""Exercise the actual preserved detector import with synthetic, local frames.

Tensor controls test integration, not real-room accuracy. The one real-network
blank-image control loads only the already available hash-checked ONNX model.
No serial, viewer import, image file write or network request is used.
"""

from __future__ import annotations

import math
import sys
import unittest
from unittest.mock import patch

import cv2
import numpy as np

from host import bridge
from host.core import BridgeState, SourceFrame


class TensorNet:
    def __init__(self, count: int = 4) -> None:
        self.output = np.zeros((1, 8400, 85), dtype=np.float32)
        for index in range(count):
            x, y, width, height = 80 + 150 * index, 150, 60, 160
            self.output[0, index, :6] = [x / 8 - index, y / 8,
                math.log(width / 8), math.log(height / 8), 1, 0.9]
        self.calls = 0

    def setPreferableBackend(self, _backend: int) -> None:
        pass

    def setPreferableTarget(self, _target: int) -> None:
        pass

    def setInput(self, blob: np.ndarray) -> None:
        if blob.shape != (1, 3, 640, 640):
            raise AssertionError("Detector did not use the selected shape")

    def getUnconnectedOutLayersNames(self) -> list[str]:
        return ["output"]

    def forward(self, _names: list[str]) -> list[np.ndarray]:
        self.calls += 1
        return [self.output.copy()]


def source(jpeg: bytes | None = None) -> SourceFrame:
    if jpeg is None:
        ok, encoded = cv2.imencode(".jpg", np.zeros((320, 640, 3), dtype=np.uint8))
        if not ok:
            raise AssertionError("Synthetic JPEG setup failed")
        jpeg = encoded.tobytes()
    return SourceFrame(1, 9, "f024f91080a4", "02" * 8, 10.0, jpeg)


class DetectorReuseTests(unittest.TestCase):
    def test_actual_reuse_keeps_source_identity_and_counts_four_tensor_controls(self) -> None:
        net, frame = TensorNet(), source()
        prior_viewer = sys.modules.get("viewer")
        with patch.object(cv2.dnn, "readNet", return_value=net) as read:
            analyze = bridge.create_analyzer(640, 0.35)
            result = analyze(frame)
        read.assert_called_once_with(str(bridge.OLD / "models/yolox_s.onnx"))
        self.assertIs(result.source, frame)
        self.assertEqual(result.people, 4)
        self.assertGreaterEqual(result.elapsed_ms, 0)
        self.assertEqual((result.annotated[:2], result.annotated[-2:]), (b"\xff\xd8", b"\xff\xd9"))
        self.assertEqual(net.calls, 1)
        self.assertIs(sys.modules.get("viewer"), prior_viewer)

    def test_invalid_jpeg_raises_before_inference_instead_of_returning_zero(self) -> None:
        net = TensorNet(0)
        with patch.object(cv2.dnn, "readNet", return_value=net):
            analyze = bridge.create_analyzer(640, 0.35)
        with self.assertRaisesRegex(ValueError, "unknown, not zero"):
            analyze(source(b"\xff\xd8inert-invalid\xff\xd9"))
        self.assertEqual(net.calls, 0)

    def test_preview_encoding_failure_cannot_be_a_successful_detection(self) -> None:
        with patch.object(cv2.dnn, "readNet", return_value=TensorNet(0)):
            analyze = bridge.create_analyzer(640, 0.35)
        frame = source()
        with patch.object(cv2, "imencode", return_value=(False, None)), \
                self.assertRaisesRegex(RuntimeError, "preview"):
            analyze(frame)

    def test_model_load_failure_never_silently_replaces_yolox_with_hog(self) -> None:
        with patch.object(cv2.dnn, "readNet", side_effect=RuntimeError("inert model load failure")), \
                patch.object(cv2, "HOGDescriptor", create=True) as hog, self.assertRaisesRegex(RuntimeError, "model load"):
            bridge.create_analyzer(640, 0.35)
        hog.assert_not_called()

    def test_invalid_detector_parameters_fail_before_loading_any_module_or_port(self) -> None:
        with patch.object(bridge, "preflight") as preflight, patch.object(bridge, "serial_link") as serial:
            for size, confidence in ((319, 0.35), (640, math.nan), (640, math.inf), (640, 0), (640, 1)):
                with self.subTest(size=size, confidence=confidence), self.assertRaises(ValueError):
                    bridge.create_analyzer(size, confidence)
        preflight.assert_not_called()
        serial.assert_not_called()

    def test_changed_preserved_hash_prevents_import_not_automatic_overwrite(self) -> None:
        with patch.object(bridge, "file_hash", return_value="0" * 64), \
                patch.object(bridge.importlib.util, "spec_from_file_location") as load, \
                self.assertRaisesRegex(RuntimeError, "changed; review"):
            bridge.create_analyzer(640, 0.35)
        load.assert_not_called()

    def test_real_preserved_model_blank_control_and_expiring_bridge_result(self) -> None:
        analyze, frame = bridge.create_analyzer(640, 0.35), source()
        state, session = BridgeState(frame.device), "01" * 16
        state.begin(session)
        state.accept_hello({"v": 1, "type": "hello", "session": session,
            "device": frame.device, "boot": frame.boot, "ttl_ms": 2000})
        state.ingest(frame.jpeg, 10.0)
        self.assertTrue(bridge.detect_once(state, analyze, lambda: 10.5))
        self.assertEqual(state.observation(10.6)["people"], 0)
        self.assertEqual(state.observation(12.01)["people"], -1)
        self.assertIsNone(state.display(12.01))


if __name__ == "__main__":
    unittest.main()
