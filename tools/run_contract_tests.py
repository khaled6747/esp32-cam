"""Cross-language characterization of real Dart encoders and C++ dispatchers.

Compiles an unchanged, bounded slice of firmware_app.hpp against inert I/O APIs.
Uses actual command_fields/auth/wire/controller code and installed ArduinoJson.
No serial, Bluetooth, flash, image recording, dependency install or network call.
The SHA256 provider is an explicitly labelled independent Python oracle fixture.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import subprocess
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from host.core import BridgeState, Detection, encode_control, parse_event  # noqa: E402

CPP = Path(r"C:\msys64\mingw64\bin\g++.exe")
DART = Path(r"C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe")
ARDUINO_JSON = Path(r"C:\Users\khale\OneDrive\Documents\Arduino\libraries\ArduinoJson\src")
DEVICE, SESSION, CHALLENGE = "f024f91080a4", bytes(range(16)).hex(), bytes(range(16, 48)).hex()
USB_SESSION = "01" * 16
CONTEXT = f"smart-room/v1|{DEVICE}|{SESSION}|{CHALLENGE}"
PROOF = hmac.new(bytes(range(32)), CONTEXT.encode(), hashlib.sha256).hexdigest()


def run(arguments: list[str | Path], *, stdin: bytes | None = None, timeout: int = 30) -> bytes:
    result = subprocess.run(list(map(str, arguments)), cwd=ROOT / "app", input=stdin,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)
    if len(result.stdout) > 1048576 or len(result.stderr) > 1048576:
        raise RuntimeError("Contract process output bound")
    if result.returncode:
        raise RuntimeError(f"Contract process exit {result.returncode}: {result.stderr.decode('utf-8', errors='replace')[:8000]}")
    return result.stdout


def ble(data: dict | str | bytes, now: int = 10) -> dict:
    if isinstance(data, dict):
        data = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    if isinstance(data, str):
        data = data.encode("utf-8")
    return {"bluetooth": True, "wire": (data + b"\n").hex(), "now": now}


def usb(data: dict, now: int = 10) -> dict:
    return {"bluetooth": False, "wire": encode_control(data).hex(), "now": now}


class ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        cls.owned = Path(os.environ["LOCALAPPDATA"]) / "Temp/opencode" / f"smart_room_cross_contract_{stamp}"
        cls.owned.mkdir()
        app = (ROOT / "firmware/smart_room/firmware_app.hpp").read_text(encoding="utf-8")
        start, end = app.index("using room::fields::exact;"), app.index("bool setupCamera()")
        pairing_start = app.index("bool pairingWindow(uint32_t now)")
        pairing = app[pairing_start:app.index("void advertiseIfFree()", pairing_start)]
        dispatcher = app[start:end]
        if not 1000 < len(dispatcher) < 50000 or dispatcher.count("void command(") != 1 or dispatcher.count("void usbCommand(") != 1:
            raise RuntimeError("Actual dispatcher source boundary changed; review the slice")
        generated = cls.owned / "actual_dispatch.cpp"
        generated.write_text('#include "firmware_contract_fixture.hpp"\nnamespace smart {\n'
            + pairing + dispatcher + '\n}\n#include "firmware_contract_main.hpp"\n', encoding="utf-8")
        cls.binary = cls.owned / "contract.exe"
        run([CPP, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-pedantic",
             "-I", ARDUINO_JSON, "-I", ROOT / "tests", generated, "-o", cls.binary], timeout=120)
        cls.emitted = json.loads(run([DART, "run", "tool/contract_fixture.dart", "emit"]))
        if cls.emitted["proof"] != PROOF:
            raise RuntimeError("Actual Dart proof does not match independent Python HMAC")
        cls.events: list[dict] = []
        cls.cases: list[dict] = []
        cls.source_sha256 = hashlib.sha256(app.encode()).hexdigest()
        print(f"Actual firmware_app.hpp SHA256: {cls.source_sha256}", flush=True)
        print(f"Dispatcher slice SHA256: {hashlib.sha256(dispatcher.encode()).hexdigest()}", flush=True)
        print(f"Evidence directory: {cls.owned}", flush=True)

    @classmethod
    def tearDownClass(cls) -> None:
        records = {"firmware_app_sha256": cls.source_sha256, "cases": cls.cases,
                   "limitations": "Inert I/O and HMAC provider fixture; no radio, GPIO, flash or appliance feedback"}
        (cls.owned / "cases.json").write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
        rows = list(cls.events)
        for name, raw in (("duplicate", b'{"v":1,"v":1,"type":"ack"}'),
                          ("escaped_duplicate", b'{"v":1,"type":"ack","id":1,"\\u0069d":2}'),
                          ("float", b'{"v":1.0,"type":"ack"}'),
                          ("null_truncation", b'{"v":1,"type":"ack","id":1,"ok":true,"code":"ok\\u0000hidden"}'),
                          ("surrogate", b'{"v":1,"type":"ack","id":1,"ok":true,"code":"\\ud800"}'),
                          ("bad_utf8", b'{"v":1,"type":"ack","code":"\xc0\x80"}'),
                          ("deep", b'{"v":1,"type":"ack","a":[[[[[[0]]]]]]}')):
            with unittest.TestCase().assertRaises((ValueError, UnicodeError)):
                parse_event(raw)
            rows.append({"name": name, "wire": raw.hex(), "valid": False})
        status = cls.cases[0]["result"]["status"]
        for name, mutated in (("false_zero_presence", status | {"presence": "empty"}),
                              ("truthy_relay", status | {"relay_enabled": 1}),
                              ("bad_config", status | {"config": cls.emitted["config"] | {"normal_max": 2}})):
            rows.append({"name": name, "wire": json.dumps(mutated, separators=(",", ":")).encode().hex(), "valid": False})
        summary = json.loads(run([DART, "run", "tool/contract_fixture.dart", "verify"],
            stdin=json.dumps(rows, ensure_ascii=False).encode("utf-8")))
        (cls.owned / "dart_event_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(f"Actual Dart event/model checks: {summary}", flush=True)

    def generated(self, name: str, now: int = 10) -> dict:
        return {"bluetooth": True, "wire": self.emitted["commands"][name], "now": now}

    def authenticated(self, operation: dict | None = None) -> list[dict]:
        result = [self.generated("hello", 1), self.generated("auth", 2)]
        return result if operation is None else result + [operation]

    def execute(self, messages: list[dict], *, final_now: int = 20, **options: object) -> dict:
        fixture = {"expected_context": CONTEXT, "expected_hmac": PROOF, **options}
        request = {"fixture": fixture, "messages": messages, "final_now": final_now}
        result = json.loads(run([self.binary], stdin=(json.dumps(request, ensure_ascii=False) + "\n").encode("utf-8")))
        self.assertTrue(result["io_simulated"])
        name = self.id().rsplit(".", 1)[-1]
        self.cases.append({"name": name, "request": request, "result": result})
        for item in result["events"]:
            raw = json.dumps(item["data"], ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            self.assertEqual(parse_event(raw), item["data"])
            self.events.append({"name": name, "wire": raw.hex(), "valid": True})
        raw = json.dumps(result["status"], ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.assertEqual(parse_event(raw), result["status"])
        self.events.append({"name": name + "_final_status", "wire": raw.hex(), "valid": True})
        return result

    def acknowledgment(self, result: dict, code: str, ok: bool) -> dict:
        value = result["events"][-1]["data"]
        self.assertEqual((value["type"], value["code"], value["ok"]), ("ack", code, ok))
        return value

    def test_actual_dart_hmac_and_authorized_status(self) -> None:
        result = self.execute(self.authenticated(self.generated("status")))
        self.assertTrue(result["authorized"])
        self.assertTrue(result["provider_context_verified"])
        self.assertEqual(result["provider_calls"], 1)
        self.assertEqual(result["events"][-1]["data"]["people"], -1)
        self.assertEqual(result["storage_writes"], 0)

    def test_every_control_requires_owner_proof_not_only_secure_transport(self) -> None:
        for name in ("lights", "set_sleep", "ac", "configure", "learn_start", "erase_slot", "storage_init"):
            with self.subTest(operation=name):
                result = self.execute([self.generated("hello"), self.generated(name)], simulate_enabled=True, slots=[1])
                self.acknowledgment(result, "auth_required", False)
                self.assertEqual((result["storage_writes"], result["receiver_starts"]), (0, 0))

    def test_bad_or_expired_proof_and_crypto_provider_failure_close_without_controls(self) -> None:
        bad = {"v": 1, "id": 2, "op": "auth", "session": SESSION, "proof": "0" * 64}
        for name, messages, options in (
                ("wrong", [self.generated("hello", 1), ble(bad, 2)], {}),
                ("expired", [self.generated("hello", 1), self.generated("auth", 30002)], {}),
                ("provider", self.authenticated(), {"provider_available": False})):
            with self.subTest(case=name):
                result = self.execute(messages + [self.generated("configure", 30003)], final_now=30004, **options)
                self.acknowledgment(result, "bad_proof", False)
                self.assertFalse(result["authorized"])
                self.assertEqual((result["disconnect_requests"], result["storage_writes"]), (1, 0))

    def test_claim_stores_before_success_and_failed_storage_does_not_authorize(self) -> None:
        for fail in (False, True):
            with self.subTest(storage_failure=fail):
                result = self.execute([self.generated("hello", 1), self.generated("claim", 2)], owned=False, storage_failure=fail)
                self.acknowledgment(result, "storage_failed" if fail else "claimed", not fail)
                self.assertEqual((result["owner_exists"], result["authorized"], result["storage_writes"]), (not fail, not fail, 1))

    def test_claim_outside_display_window_has_no_storage_write(self) -> None:
        result = self.execute([self.generated("hello", 120001), self.generated("claim", 120002)], final_now=120003, owned=False)
        self.acknowledgment(result, "claim_denied", False)
        self.assertEqual(result["storage_writes"], 0)

    def test_same_request_id_and_previous_session_never_execute_again(self) -> None:
        result = self.execute(self.authenticated(self.generated("configure")) + [self.generated("configure")])
        self.acknowledgment(result, "replayed_request", False)
        self.assertEqual(result["storage_writes"], 1)
        stale = {"v": 1, "id": 4, "op": "configure", "session": "ff" * 16, **self.emitted["config"]}
        result = self.execute(self.authenticated() + [ble(stale)])
        self.acknowledgment(result, "auth_required", False)
        self.assertEqual(result["storage_writes"], 0)

    def test_disabled_outputs_reject_commands_not_false_success(self) -> None:
        for name in ("lights", "send_slot", "learn_start"):
            with self.subTest(operation=name):
                result = self.execute(self.authenticated(self.generated(name)), slots=[1])
                self.acknowledgment(result, "hardware_disabled", False)
                self.assertEqual(result["receiver_starts"], 0)
                self.assertFalse(result["status"]["relay_enabled"])

    def test_actual_config_roundtrip_and_saved_policy(self) -> None:
        result = self.execute(self.authenticated(self.generated("configure")))
        self.acknowledgment(result, "configuration_saved", True)
        self.assertEqual(result["status"]["config"], self.emitted["config"])
        for name, mode in (("set_auto", "auto"), ("set_manual", "manual"), ("set_sleep", "sleep")):
            result = self.execute(self.authenticated(self.generated(name)), slots=[4])
            self.acknowledgment(result, "policy_saved", True)
            self.assertEqual(result["status"]["mode"], mode)

    def test_typed_bad_configuration_is_transactional(self) -> None:
        for changed in ({"ttl_ms": True}, {"quiet_max": 4}, {"empty_ms": 2000}, {"busy_slot": 17}, {"manual_ms": 59999}):
            with self.subTest(changed=changed):
                command = {"v": 1, "op": "configure", "id": 3, "session": SESSION, **self.emitted["config"], **changed}
                result = self.execute(self.authenticated(ble(command)))
                self.acknowledgment(result, "invalid_configuration", False)
                self.assertEqual(result["storage_writes"], 0)
                self.assertEqual(result["status"]["config"], self.emitted["config"])

    def test_matching_full_ir_state_queues_and_unknown_combination_has_no_fallback(self) -> None:
        result = self.execute(self.authenticated(self.generated("ac")), simulate_enabled=True, slots=[1])
        self.acknowledgment(result, "queued", True)
        self.assertEqual((result["status"]["requested_slot"], result["status"]["sent_slot"], result["status"]["ir_result"]), (1, 0, "queued"))
        command = {"v": 1, "op": "ac", "id": 3, "session": SESSION, **self.emitted["state"], "sleep": True, "lease_ms": 60000}
        result = self.execute(self.authenticated(ble(command)), simulate_enabled=True, slots=[1])
        self.acknowledgment(result, "unlearned_state", False)
        self.assertEqual(result["status"]["requested_slot"], 0)

    def test_learning_arabic_utf8_and_cancel_roundtrip(self) -> None:
        result = self.execute(self.authenticated(self.generated("learn_start")) + [self.generated("learn_cancel")], simulate_enabled=True)
        self.acknowledgment(result, "learning_cancelled", True)
        self.assertEqual(result["events"][-2]["data"]["code"], "press_original_remote")
        self.assertEqual((result["receiver_starts"], result["status"]["learn_slot"]), (1, 0))
        for changed in ({"label": "ن" * 24}, {"hz": 37000}, {"power": 1}, {"slot": 0}):
            command = {"v": 1, "op": "learn_start", "id": 3, "session": SESSION, "slot": 1, "label": "نوم", "hz": 38000, **self.emitted["state"], **changed}
            result = self.execute(self.authenticated(ble(command)), simulate_enabled=True)
            self.acknowledgment(result, "invalid_fields", False)
            self.assertEqual(result["receiver_starts"], 0)

    def test_actual_profile_events_and_confirmed_storage_commands(self) -> None:
        result = self.execute(self.authenticated(self.generated("profiles")), slots=[1, 4])
        self.assertEqual([item["slot"] for item in result["events"][-1]["data"]["items"]], [1, 4])
        for name, code in (("erase_slot", "slot_erased"), ("storage_init", "storage_ready")):
            result = self.execute(self.authenticated(self.generated(name)), slots=[1], storage_ready=name != "storage_init")
            self.acknowledgment(result, code, True)
            self.assertEqual(result["storage_writes"], 1)

    def test_flat_input_ambiguity_never_reaches_storage(self) -> None:
        for raw in (b'{"v":1,"v":1,"id":3,"op":"configure"}', b'{"\\u0076":1,"id":3,"op":"configure"}',
                    b'{"v":1,"id":3.0,"op":"configure"}', b'{"v":1,"id":3,"op":"hello\\u0000hidden"}',
                    b'{"v":1,"id":3,"op":"learn_start","label":"\\ud800"}', b'{"v":1,"id":3,"op":"configure","nested":{}}',
                    b'{"v":1,"id":3,"op":"configure","label":"\xc0\x80"}'):
            with self.subTest(raw=raw):
                result = self.execute(self.authenticated(ble(raw)))
                self.acknowledgment(result, "invalid_json", False)
                self.assertEqual(result["storage_writes"], 0)

    def test_usb_action_session_id_specific_code_and_replay_contract(self) -> None:
        for action in ("open_pairing", "reset_owner"):
            state = BridgeState(DEVICE); hello = state.begin(USB_SESSION)
            preliminary = self.execute([usb(hello)])
            self.assertTrue(state.accept_hello(preliminary["events"][0]["data"]))
            local = state.local_command(action)
            result = self.execute([usb(hello), usb(local), usb(local)])
            specific = result["events"][-2]["data"]
            self.assertTrue(state.accepts_action_ack(specific, action))
            self.acknowledgment(result, "replayed_request", False)
            self.assertFalse(state.accepts_action_ack(result["events"][-1]["data"], action))
            self.assertEqual(result["storage_writes"], 1 if action == "reset_owner" else 0)
            for changed in ({"session": "ff" * 16}, {"id": True}, {"confirm": "wrong"}, {"id": 0}, {"extra": 1}):
                result = self.execute([usb(hello), usb(local | changed)])
                self.acknowledgment(result, "invalid_local_action", False)
                self.assertEqual(result["storage_writes"], 0)

    def test_usb_bond_removal_failure_is_not_success(self) -> None:
        state = BridgeState(DEVICE); hello = state.begin(USB_SESSION)
        state.accept_hello(self.execute([usb(hello)])["events"][0]["data"])
        result = self.execute([usb(hello), usb(state.local_command("reset_owner"))], bond_count=1, bond_failure=True)
        ack = self.acknowledgment(result, "bond_removal_failed", False)
        self.assertFalse(state.accepts_action_ack(ack, "reset_owner"))

    def test_actual_bridge_age_reaches_firmware_and_stale_is_not_zero(self) -> None:
        state = BridgeState(DEVICE); hello = state.begin(USB_SESSION)
        state.accept_hello(self.execute([usb(hello)])["events"][0]["data"])
        state.ingest(b"\xff\xd8inert-control\xff\xd9", 10.0)
        source = state.take_source(); self.assertIsNotNone(source)
        self.assertTrue(state.publish(Detection(source, 4), 11.4))
        observation = state.observation(11.4); self.assertEqual(observation["age_ms"], 1400)
        result = self.execute([usb(hello), usb(observation, 11400), usb({"v": 1, "op": "status"}, 11400)], final_now=12001)
        self.assertEqual(result["events"][-1]["data"]["people"], 4)
        self.assertEqual((result["status"]["people"], result["status"]["presence"], result["status"]["lights"]), (-1, "unknown", True))

    def test_crc_corruption_and_split_control_recover_without_replaying_action(self) -> None:
        hello = {"v": 1, "op": "hello", "session": USB_SESSION}
        local = {"v": 1, "op": "reset_owner", "id": 1, "session": USB_SESSION, "confirm": "ERASE_OWNER_AND_BONDS"}
        packet = encode_control(local); broken = bytearray(packet); broken[-1] ^= 1
        prefix, suffix = packet[:9], packet[9:]
        result = self.execute([usb(hello), {"bluetooth": False, "wire": bytes(broken).hex(), "now": 10},
            {"bluetooth": False, "wire": prefix.hex(), "now": 11}, {"bluetooth": False, "wire": suffix.hex(), "now": 12}])
        self.acknowledgment(result, "owner_reset_bond_removal_requested", True)
        self.assertEqual(result["storage_writes"], 1)

    def test_disposable_session_binding_mutant_is_detected_by_negative_control(self) -> None:
        # The real source is never edited. Removing only the local-action session
        # equality in a disposable copy must admit the known-negative request.
        mutant = self.owned / "session_mutant"
        (mutant / "tests").mkdir(parents=True)
        (mutant / "firmware/smart_room").mkdir(parents=True)
        for name in ("firmware_contract_fixture.hpp", "firmware_contract_main.hpp"):
            (mutant / "tests" / name).write_bytes((ROOT / "tests" / name).read_bytes())
        equality = '&& !std::strcmp(session,object["session"].as<const char *>())'
        for name in ("auth_core.hpp", "wire.hpp", "room_core.hpp", "command_fields.hpp"):
            content = (ROOT / "firmware/smart_room" / name).read_text(encoding="utf-8")
            if name == "command_fields.hpp":
                self.assertEqual(content.count(equality), 1)
                content = content.replace(equality, "&& true")
            (mutant / "firmware/smart_room" / name).write_text(content, encoding="utf-8")
        source = mutant / "actual_dispatch.cpp"
        source.write_bytes((self.owned / "actual_dispatch.cpp").read_bytes())
        executable = mutant / "mutant.exe"
        run([CPP, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-pedantic", "-I", ARDUINO_JSON,
             "-I", mutant / "tests", source, "-o", executable], timeout=120)
        hello = {"v": 1, "op": "hello", "session": USB_SESSION}
        stale = {"v": 1, "op": "open_pairing", "id": 1, "session": "ff" * 16, "confirm": "LOCAL_PAIRING_WINDOW"}
        original = self.execute([usb(hello), usb(stale)])
        self.acknowledgment(original, "invalid_local_action", False)
        request = {"fixture": {"expected_context": CONTEXT, "expected_hmac": PROOF},
                   "messages": [usb(hello), usb(stale)], "final_now": 20}
        result = json.loads(run([executable], stdin=(json.dumps(request) + "\n").encode()))
        changed = result["events"][-1]["data"]
        self.assertEqual((changed["code"], changed["ok"]), ("pairing_window_open", True))
        (mutant / "fault_evidence.json").write_text(json.dumps({"original_denied": True,
            "mutant_admitted_known_negative": True, "regression_would_fail": True}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    unittest.main(verbosity=2)
