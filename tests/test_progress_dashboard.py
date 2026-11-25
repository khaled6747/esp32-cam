"""Record/schema and owned loopback HTTP controls; leaves live progress untouched."""

from __future__ import annotations

import copy
import json
import os
import tempfile
import threading
import unittest
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

from tools import progress_server as progress


def fixture() -> dict:
    return {"updated_at": "2026-11-24T00:58:19Z", "activity": "اختبار محلي فقط",
            "batch": {"title": "الدفعة الحالية", "tasks": [
                {"id": "test-one", "title": "تحقق برمجي", "state": "verified", "evidence": "fixture"},
                {"id": "test-two", "title": "متبقٍ", "state": "active", "evidence": "fixture"}]},
            "milestones": [{"id": "hardware", "title": "هاردوير", "state": "blocked", "evidence": "صور مطلوبة"}],
            "blockers": ["لا فلاش في هذه الاختبارات"]}


def encoded(record: dict) -> bytes:
    return json.dumps(record, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


class RecordTests(unittest.TestCase):
    def test_valid_record_and_equal_task_count_do_not_merge_hardware(self) -> None:
        record = progress.validate_record(encoded(fixture()))
        self.assertEqual(sum(t["state"] == "verified" for t in record["batch"]["tasks"]), 1)
        self.assertEqual(len(record["batch"]["tasks"]), 2)
        self.assertEqual(record["milestones"][0]["state"], "blocked")

    def test_exact_record_batch_and_task_keys(self) -> None:
        cases = []
        item = fixture(); item["execute"] = "not code"; cases.append(item)
        item = fixture(); item["batch"]["percent"] = 100; cases.append(item)
        item = fixture(); item["batch"]["tasks"][0]["onclick"] = "not code"; cases.append(item)
        for record in cases:
            with self.subTest(record=record), self.assertRaises(ValueError):
                progress.validate_record(encoded(record))

    def test_duplicate_json_keys_cannot_silently_replace_a_task_state(self) -> None:
        raw = encoded(fixture()).replace(b'"state":"active"', b'"state":"active","state":"verified"')
        with self.assertRaisesRegex(ValueError, "Duplicate|duplicate"):
            progress.validate_record(raw)

    def test_duplicate_ids_across_batch_and_hardware_are_rejected(self) -> None:
        record = fixture(); record["milestones"][0]["id"] = "test-one"
        with self.assertRaises(ValueError):
            progress.validate_record(encoded(record))

    def test_invalid_states_have_actionable_validation_errors(self) -> None:
        for state in ("done", True, [], {}):
            record = fixture(); record["batch"]["tasks"][0]["state"] = state
            with self.subTest(state=state), self.assertRaises(ValueError):
                progress.validate_record(encoded(record))

    def test_byte_text_collection_and_depth_bounds(self) -> None:
        for field, bad in (("activity", ""), ("activity", "x" * 1501), ("blockers", ["x"] * 31),
                           ("blockers", [False])):
            record = fixture(); record[field] = bad
            with self.subTest(field=field), self.assertRaises(ValueError):
                progress.validate_record(encoded(record))
        with self.assertRaises(ValueError):
            progress.validate_record(b" " * 65537)
        with self.assertRaises(ValueError):
            progress.validate_record(b'{' + b'"bad":' + b'[' * 1000 + b'0' + b']' * 1000 + b'}')

    def test_current_batch_must_not_have_an_empty_acceptance_denominator(self) -> None:
        record = fixture(); record["batch"]["tasks"] = []
        with self.assertRaises(ValueError):
            progress.validate_record(encoded(record))

    def test_timestamp_requires_an_offset_and_text_has_no_null_or_surrogates(self) -> None:
        for stamp in ("not a date", "2026-11-24T00:00:00"):
            record = fixture(); record["updated_at"] = stamp
            with self.subTest(stamp=stamp), self.assertRaises(ValueError):
                progress.validate_record(encoded(record))
        for text in ("nul\x00text", "surrogate\ud800"):
            record = fixture(); record["activity"] = text
            raw = json.dumps(record, ensure_ascii=True).encode("utf-8")
            with self.subTest(text=repr(text)), self.assertRaises(ValueError):
                progress.validate_record(raw)

    def test_saved_current_record_obeys_the_same_contract(self) -> None:
        record = progress.validate_record((progress.ROOT / "state.json").read_bytes())
        # The current batch is reusable; it must not freeze the previous batch's
        # task IDs/count or silently merge physical acceptance into its total.
        batch_ids = {task["id"] for task in record["batch"]["tasks"]}
        milestones = {task["id"]: task for task in record["milestones"]}
        self.assertTrue(batch_ids)
        self.assertFalse(batch_ids.intersection(milestones))
        physical = {"hardware", "flash", "ble-phone", "ir-ac", "vision-scene"}
        self.assertTrue(physical.issubset(milestones))
        for name in physical:
            with self.subTest(milestone=name):
                self.assertEqual(milestones[name]["state"], "blocked")


class HttpTests(unittest.TestCase):
    def setUp(self) -> None:
        approved = Path(os.environ["LOCALAPPDATA"]) / "Temp" / "opencode"
        self.temporary = tempfile.TemporaryDirectory(prefix="smart_room_progress_test_", dir=approved)
        self.root = Path(self.temporary.name)
        for filename in ("index.html", "progress.js", "style.css"):
            (self.root / filename).write_bytes((progress.ROOT / filename).read_bytes())
        (self.root / "state.json").write_bytes(encoded(fixture()))
        self.patch = patch.object(progress, "ROOT", self.root)
        self.patch.start()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), progress.Handler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=lambda: self.server.serve_forever(poll_interval=0.02),
                                       name="test-owned-progress")
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)
        self.assertFalse(self.thread.is_alive())
        self.patch.stop()
        self.temporary.cleanup()

    def request(self, path, method="GET"):
        connection = HTTPConnection("127.0.0.1", self.port, timeout=2)
        try:
            connection.request(method, path)
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def test_only_allowed_assets_are_served_with_no_store_and_csp(self) -> None:
        for path in ("/", "/progress.js", "/style.css", "/state.json"):
            code, headers, raw = self.request(path)
            self.assertEqual(code, 200)
            self.assertTrue(raw)
            self.assertEqual(headers["Cache-Control"], "no-store")
            self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
            self.assertIn("frame-ancestors 'none'", headers["Content-Security-Policy"])
        for path in ("/../PLAN.md", "/README.md", "/state.json?verified=all", "/%2e%2e/PLAN.md"):
            self.assertEqual(self.request(path)[0], 404, path)
        self.assertEqual(self.request("/state.json", "POST")[0], 405)

    def test_invalid_missing_or_oversized_record_is_explicitly_unavailable(self) -> None:
        path = self.root / "state.json"
        for raw in (b'{}', b'{"incomplete":', b' ' * 65537):
            path.write_bytes(raw)
            self.assertEqual(self.request("/state.json")[0], 503)
        path.unlink()
        self.assertEqual(self.request("/state.json")[0], 503)

    def test_task_text_is_inert_data_and_refresh_does_not_change_completion(self) -> None:
        record = copy.deepcopy(fixture())
        record["batch"]["tasks"][0]["title"] = '<img src=x onerror="alert(1)">'
        (self.root / "state.json").write_bytes(encoded(record))
        first = json.loads(self.request("/state.json")[2])
        second = json.loads(self.request("/state.json")[2])
        self.assertEqual(first, second)
        self.assertEqual(first["batch"]["tasks"][0]["title"], record["batch"]["tasks"][0]["title"])
        self.assertEqual(sum(t["state"] == "verified" for t in first["batch"]["tasks"]), 1)


if __name__ == "__main__":
    unittest.main()
