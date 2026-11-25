"""Workspace CMD controls using an inert helper only; no tools, serial or flash."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[1]
WORKSPACE = PROJECT.parent
LAUNCHER = WORKSPACE / "UPLOAD_ESP32CAM.cmd"
INSTRUCTIONS = WORKSPACE / "UPLOAD_INSTRUCTIONS_AR.txt"
CMD = Path(os.environ["SystemRoot"]) / "System32/cmd.exe"

INERT_HELPER = r'''
[CmdletBinding()]
param(
    [switch]$Interactive,
    [switch]$ConfirmHardwareReviewed,
    [switch]$SkipBackup,
    [switch]$AllowEnabledOutputs,
    [switch]$CheckOnly,
    [switch]$CompileOnly
)
$ErrorActionPreference = 'Stop'
$record = [ordered]@{
    interactive = [bool]$Interactive
    review_confirmed = [bool]$ConfirmHardwareReviewed
    backup_skipped = [bool]$SkipBackup
    outputs_override = [bool]$AllowEnabledOutputs
    check_only = [bool]$CheckOnly
    compile_only = [bool]$CompileOnly
    unbound_arg_count = $args.Count
}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'inert-invocation.json'),
    ($record | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
Write-Host 'INERT_HELPER_CALLED'
exit ([int]$env:SMART_ROOM_UPLOAD_TEST_EXIT)
'''

EXPECTED_REQUEST = {
    "interactive": True,
    "review_confirmed": False,
    "backup_skipped": False,
    "outputs_override": False,
    "check_only": False,
    "compile_only": False,
    "unbound_arg_count": 0,
}


class UploadEntrypointTests(unittest.TestCase):
    def launch_fixture(self, *, exit_code: int = 2, helper_present: bool = True,
                       instructions_present: bool = True,
                       extra_args: str = "",
                       source: bytes | None = None) -> tuple[subprocess.CompletedProcess, dict | None]:
        self.assertTrue(LAUNCHER.is_file(), "Workspace double-click CMD is missing")
        self.assertTrue(INSTRUCTIONS.is_file(), "Arabic upload instructions are missing")
        approved = Path(os.environ["LOCALAPPDATA"]) / "Temp/opencode"
        # Percent signs and exclamation marks are literal path data, not cmd
        # expansions. Run from an unrelated CWD to check use of %~dp0 as well.
        with tempfile.TemporaryDirectory(prefix="smart_room_upload_عربي & ! %TEMP% path_",
                                         dir=approved) as directory:
            fixture = Path(directory)
            launcher = fixture / LAUNCHER.name
            launcher.write_bytes(LAUNCHER.read_bytes() if source is None else source)
            project = fixture / "esp32cam_smart_room"
            project.mkdir()
            if helper_present:
                (project / "flash_esp32cam.ps1").write_text(INERT_HELPER, encoding="utf-8")
            if instructions_present:
                (fixture / INSTRUCTIONS.name).write_bytes(INSTRUCTIONS.read_bytes())
            environment = os.environ | {
                "SMART_ROOM_UPLOAD_TEST_LAUNCHER": str(launcher),
                "SMART_ROOM_UPLOAD_TEST_EXIT": str(exit_code),
            }
            command = f'"{CMD}" /d /v:off /s /c ""%SMART_ROOM_UPLOAD_TEST_LAUNCHER%"{extra_args}"'
            result = subprocess.run(command, input=b"\r\n", capture_output=True,
                                    cwd=approved, env=environment, timeout=20, check=False)
            path = project / "inert-invocation.json"
            request = json.loads(path.read_bytes()) if path.exists() else None
            return result, request

    def test_cmd_and_arabic_instructions_are_delivered_in_the_workspace_root(self) -> None:
        self.assertTrue(LAUNCHER.is_file(), "Workspace double-click CMD is missing")
        self.assertTrue(INSTRUCTIONS.is_file(), "Arabic upload instructions are missing")
        source = LAUNCHER.read_bytes().decode("ascii")
        self.assertTrue(source.startswith("@echo off"))
        self.assertIn("DisableDelayedExpansion", source)
        for forbidden in ("ExecutionPolicy", "-SkipBackup", "-AllowEnabledOutputs",
                          "-ConfirmHardwareReviewed", "%*", "esptool", "taskkill"):
            self.assertNotIn(forbidden.lower(), source.lower())

    def test_unicode_spaces_symbols_and_unrelated_cwd_reach_only_the_inert_menu(self) -> None:
        result, request = self.launch_fixture()
        self.assertEqual(result.returncode, 2, (result.stdout + result.stderr).decode(errors="replace"))
        self.assertEqual(request, EXPECTED_REQUEST)
        self.assertIn(b"INERT_HELPER_CALLED", result.stdout)

    def test_arabic_instructions_are_shown_before_the_helper_runs(self) -> None:
        result, _ = self.launch_fixture()
        heading = "تعليمات رفع كود ESP32-CAM".encode("utf-8")
        self.assertIn(heading, result.stdout)
        self.assertLess(result.stdout.index(heading), result.stdout.index(b"INERT_HELPER_CALLED"))

    def test_missing_helper_stops_without_any_helper_invocation(self) -> None:
        result, request = self.launch_fixture(helper_present=False)
        self.assertEqual(result.returncode, 3)
        self.assertIsNone(request)
        self.assertIn(b"flash_esp32cam.ps1", result.stdout)

    def test_missing_instructions_stop_before_the_helper(self) -> None:
        result, request = self.launch_fixture(instructions_present=False)
        self.assertEqual(result.returncode, 3)
        self.assertIsNone(request)
        self.assertIn(b"UPLOAD_INSTRUCTIONS_AR.txt", result.stdout)

    def test_native_result_is_preserved_and_no_retry_is_attempted(self) -> None:
        for exit_code in (0, 2, 5, 6):
            with self.subTest(exit_code=exit_code):
                result, request = self.launch_fixture(exit_code=exit_code)
                self.assertEqual(result.returncode, exit_code,
                                 (result.stdout + result.stderr).decode(errors="replace"))
                self.assertEqual(request, EXPECTED_REQUEST)
                self.assertEqual(result.stdout.count(b"INERT_HELPER_CALLED"), 1)
                self.assertIn(b"No automatic retry", result.stdout)

    def test_external_arguments_cannot_enable_review_or_backup_overrides(self) -> None:
        result, request = self.launch_fixture(
            extra_args=" -ConfirmHardwareReviewed -SkipBackup -AllowEnabledOutputs")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(request, EXPECTED_REQUEST)

    def test_disposable_backup_override_mutant_is_visible_to_the_oracle(self) -> None:
        self.assertTrue(LAUNCHER.is_file(), "Workspace double-click CMD is missing")
        source = LAUNCHER.read_bytes()
        self.assertEqual(source.count(b" -Interactive"), 1)
        mutant = source.replace(b" -Interactive", b" -Interactive -SkipBackup")
        result, request = self.launch_fixture(source=mutant)
        self.assertEqual(result.returncode, 2)
        self.assertIsNotNone(request)
        self.assertTrue(request["backup_skipped"])
        self.assertNotEqual(request, EXPECTED_REQUEST)
        self.assertEqual(LAUNCHER.read_bytes(), source, "Mutation must stay in the disposable fixture")

    def test_instruction_tokens_match_the_unchanged_helper_and_known_limitations(self) -> None:
        self.assertTrue(INSTRUCTIONS.is_file(), "Arabic upload instructions are missing")
        instructions = INSTRUCTIONS.read_text(encoding="utf-8-sig")
        helper = (PROJECT / "flash_esp32cam.ps1").read_text(encoding="utf-8")
        for token in ("COM13", "f0:24:f9:10:80:a4", "HARDWARE_REVIEWED_NO_LOAD", "FLASH"):
            with self.subTest(token=token):
                self.assertIn(token, instructions)
                self.assertIn(token, helper)
        for token in ("4,194,304", "backups", "logs", "0x56", "0xA5", "0x04", "microSD"):
            self.assertIn(token, instructions)
        self.assertIn("لا تكتب", instructions)
        self.assertIn("لا تعيد", instructions)
        self.assertIn("لا يفتح منفذ", instructions)


if __name__ == "__main__":
    unittest.main()
