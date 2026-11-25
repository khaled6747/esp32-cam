"""Compile the actual board config in isolated copies; never execute or flash it."""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKETCH = ROOT / "firmware/smart_room"
CPP = Path(r"C:\msys64\mingw64\bin\g++.exe")


class BoardConfigTests(unittest.TestCase):
    def compile(self, *, reviewed: bool = False, policy_source: str | None = None,
                **changes: object) -> subprocess.CompletedProcess:
        source = (SKETCH / "board_config.h").read_text(encoding="utf-8")
        if "constexpr bool HARDWARE_REVIEWED" in source:
            changes["HARDWARE_REVIEWED"] = reviewed
        else:
            # The pre-guard configuration has no such switch. Keep that red-stage
            # fixture syntactically valid so negatives reach the missing policy.
            source = f"constexpr bool HARDWARE_REVIEWED = {str(reviewed).lower()};\n" + source
        for name, value in changes.items():
            literal = str(value).lower() if type(value) is bool else str(value)
            pattern = rf"(?m)^(constexpr\s+(?:bool|int)\s+{re.escape(name)}\s*=\s*)[^;]+;"
            source, count = re.subn(pattern, lambda match: match[1] + literal + ";", source)
            self.assertEqual(count, 1, f"Fixture must change exactly one {name}")
        temporary = Path(os.environ["LOCALAPPDATA"]) / "Temp/opencode"
        with tempfile.TemporaryDirectory(prefix="smart_room_board_test_", dir=temporary) as directory:
            fixture = Path(directory)
            (fixture / "board_config.h").write_text(source, encoding="utf-8")
            if policy_source is not None:
                (fixture / "board_policy.hpp").write_text(policy_source, encoding="utf-8")
            unit = fixture / "config.cpp"
            unit.write_text('#include <cstdint>\n#include "board_config.h"\n', encoding="utf-8")
            return subprocess.run(
                [str(CPP), "-std=c++17", "-Wall", "-Wextra", "-Werror", "-pedantic",
                 "-fsyntax-only", "-I", str(SKETCH), str(unit)],
                capture_output=True, text=True, timeout=30, check=False,
            )

    def accepted(self, **changes: object) -> None:
        result = self.compile(**changes)
        self.assertEqual(result.returncode, 0, result.stderr[:8000])

    def refused(self, diagnostic: str, **changes: object) -> None:
        result = self.compile(**changes)
        self.assertNotEqual(result.returncode, 0, "Unsafe configuration was accepted by the actual compiler")
        self.assertIn(diagnostic, result.stderr[:16000])

    def test_delivered_configuration_remains_disabled_and_compiles(self) -> None:
        self.accepted()

    def test_each_peripheral_requires_hardware_review(self) -> None:
        for flag in ("ENABLE_OLED", "ENABLE_IR_TRANSMIT", "ENABLE_IR_RECEIVE", "ENABLE_RELAY"):
            with self.subTest(flag=flag):
                self.refused("Hardware review required before enabling peripherals", **{flag: True})

    def test_reviewed_conditional_pin_map_is_a_valid_control_not_hardware_approval(self) -> None:
        self.accepted(reviewed=True, ENABLE_OLED=True, ENABLE_IR_TRANSMIT=True,
                      ENABLE_IR_RECEIVE=True, ENABLE_RELAY=True)

    def test_psram_tx_pin_is_rejected_even_when_review_switch_is_true(self) -> None:
        for pin in (16, 17):
            with self.subTest(pin=pin):
                self.refused("IR transmitter pin is reserved or unsupported", reviewed=True,
                             ENABLE_IR_TRANSMIT=True, IR_TX_PIN=pin)

    def test_camera_usb_flash_and_nonexistent_pins_cannot_be_repurposed(self) -> None:
        for pin in (-1, 0, 1, 3, 5, 6, 11, 18, 19, 21, 22, 23, 25, 26, 27, 32, 34, 35, 36, 39, 40):
            with self.subTest(pin=pin):
                self.refused("IR transmitter pin is reserved or unsupported", reviewed=True,
                             ENABLE_IR_TRANSMIT=True, IR_TX_PIN=pin)

    def test_gpio12_is_not_available_for_any_enabled_peripheral(self) -> None:
        for flag, pin in (("ENABLE_OLED", "OLED_SDA"), ("ENABLE_OLED", "OLED_SCL"),
                          ("ENABLE_IR_TRANSMIT", "IR_TX_PIN"), ("ENABLE_IR_RECEIVE", "IR_RX_PIN"),
                          ("ENABLE_RELAY", "RELAY_PIN")):
            with self.subTest(role=pin):
                self.refused("reserved or unsupported", reviewed=True, **{flag: True, pin: 12})

    def test_receiver_and_oled_cannot_drive_the_flash_led_pin(self) -> None:
        for flag, pin in (("ENABLE_IR_RECEIVE", "IR_RX_PIN"), ("ENABLE_OLED", "OLED_SDA"),
                          ("ENABLE_OLED", "OLED_SCL")):
            with self.subTest(role=pin):
                self.refused("reserved or unsupported", reviewed=True, **{flag: True, pin: 4})

    def test_enabled_roles_cannot_share_a_pin(self) -> None:
        for changes in ({"ENABLE_OLED": True, "OLED_SDA": 14},
                        {"ENABLE_OLED": True, "ENABLE_RELAY": True, "RELAY_PIN": 14},
                        {"ENABLE_IR_RECEIVE": True, "ENABLE_IR_TRANSMIT": True, "IR_TX_PIN": 2},
                        {"ENABLE_IR_RECEIVE": True, "ENABLE_RELAY": True, "RELAY_PIN": 2}):
            with self.subTest(changes=changes):
                self.refused("Enabled peripheral pins must be distinct", reviewed=True, **changes)

    def test_disabled_roles_do_not_reserve_pins_from_enabled_roles(self) -> None:
        self.accepted(reviewed=True, ENABLE_RELAY=True, RELAY_PIN=14)

    def test_current_user_wiring_is_rejected_without_enabling_real_hardware(self) -> None:
        self.refused("IR transmitter pin is reserved or unsupported", reviewed=True,
                     ENABLE_OLED=True, OLED_SDA=15, OLED_SCL=14,
                     ENABLE_IR_TRANSMIT=True, IR_TX_PIN=16,
                     ENABLE_IR_RECEIVE=True, IR_RX_PIN=4,
                     ENABLE_RELAY=True, RELAY_PIN=12)

    def test_disposable_psram_pin_mutant_is_detected_by_the_negative_regression(self) -> None:
        policy = (SKETCH / "board_policy.hpp").read_text(encoding="utf-8")
        expression = "return pin == 4 || auxiliaryPin(pin);"
        self.assertEqual(policy.count(expression), 1)
        mutated = policy.replace(expression, "return pin == 16 || pin == 4 || auxiliaryPin(pin);")
        self.refused("IR transmitter pin is reserved or unsupported", reviewed=True,
                     ENABLE_IR_TRANSMIT=True, IR_TX_PIN=16)
        # Only this isolated header admits the known-negative input. The same
        # negative compiler assertion must fail, not pass vacuously.
        with self.assertRaisesRegex(AssertionError, "Unsafe configuration was accepted"):
            self.refused("IR transmitter pin is reserved or unsupported", policy_source=mutated,
                         reviewed=True, ENABLE_IR_TRANSMIT=True, IR_TX_PIN=16)
        self.assertEqual((SKETCH / "board_policy.hpp").read_text(encoding="utf-8"), policy)


if __name__ == "__main__":
    unittest.main()
