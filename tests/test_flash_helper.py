"""Inert helper subprocess tests; no Arduino, serial port, firmware write or radio."""

from __future__ import annotations

import base64
import ctypes
import json
import os
import subprocess
import sys
import tempfile
import unittest
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"
CMD = Path(os.environ["SystemRoot"]) / "System32/cmd.exe"


@dataclass(frozen=True)
class NativeResult:
    returncode: int
    stdout: bytes
    stderr: bytes
    log: str


class FlashNativeTests(unittest.TestCase):
    def native(self, program: str, arguments: list[str] | None = None, *, timeout: int = 10,
               output_limit: int | None = None) -> NativeResult:
        temporary = Path(os.environ["LOCALAPPDATA"]) / "Temp/opencode"
        with tempfile.TemporaryDirectory(prefix="smart_room_native_test_", dir=temporary) as directory:
            # Load only the authored native invocation functions, not the upload
            # branch. The child executable is this test's Python interpreter.
            encoded = base64.b64encode(json.dumps({"program": program, "args": arguments or []}).encode()).decode()
            script = r'''
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $env:SMART_ROOM_TEST_ROOT 'flash_esp32cam.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Helper parse failed' }
foreach ($name in @('Quote-NativeArg', 'Invoke-Native')) {
    $functions = @($ast.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    if ($functions.Count -eq 1) { . ([scriptblock]::Create($functions[0].Extent.Text)) }
}
function Say { param([string]$Text, [string]$Color = 'Gray'); Write-Host $Text }
$script:Log = Join-Path $env:SMART_ROOM_TEST_TEMP 'native.log'
$data = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:SMART_ROOM_TEST_DATA)) | ConvertFrom-Json
$argsForChild = @('-c', [string]$data.program) + @($data.args)
'''
            script += "\n$captured = ''\n$code = Invoke-Native -File $env:SMART_ROOM_TEST_PYTHON -Arguments $argsForChild"
            if "[ref]$Output" in (ROOT / "flash_esp32cam.ps1").read_text(encoding="utf-8"):
                script += " -Output ([ref]$captured)"
            if "TimeoutSeconds" in (ROOT / "flash_esp32cam.ps1").read_text(encoding="utf-8"):
                script += f" -TimeoutSeconds {timeout}"
            if output_limit is not None:
                if "MaxOutputChars" not in (ROOT / "flash_esp32cam.ps1").read_text(encoding="utf-8"):
                    self.fail("Native helper has no output bound")
                script += f" -MaxOutputChars {output_limit}"
            script += ('\nWrite-Host ("CAPTURE_BASE64=" + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($captured)))'
                       '\nWrite-Host ("NATIVE_RESULT=" + $code)\nexit $code\n')
            environment = os.environ | {
                "SMART_ROOM_TEST_ROOT": str(ROOT), "SMART_ROOM_TEST_TEMP": directory,
                "SMART_ROOM_TEST_DATA": encoded, "SMART_ROOM_TEST_PYTHON": sys.executable,
            }
            result = subprocess.run([str(POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
                                    env=environment, capture_output=True, timeout=20, check=False)
            log_path = Path(directory) / "native.log"
            log = log_path.read_text(encoding="utf-8-sig") if log_path.exists() else ""
            return NativeResult(result.returncode, result.stdout, result.stderr, log)

    def test_stderr_is_logged_and_real_nonzero_exit_is_preserved(self) -> None:
        result = self.native("import sys; print('NATIVE_STDOUT'); sys.stderr.write('NATIVE_WARNING\\n'); sys.exit(7)")
        self.assertEqual(result.returncode, 7, (result.stdout + result.stderr).decode(errors="replace"))
        self.assertIn(b"NATIVE_STDOUT", result.stdout)
        self.assertIn(b"NATIVE_WARNING", result.stdout)
        self.assertIn(b"NATIVE_RESULT=7", result.stdout)
        self.assertIn("NATIVE_WARNING", result.log)

    def test_arguments_are_not_interpreted_by_a_shell(self) -> None:
        arguments = ["", "space separated", 'literal"quote', "trailing\\", "double\\\\",
                     'slash\\"quote', "& echo NOT_A_COMMAND", "x;y", "عربي"]
        result = self.native("import json,sys; print('ARGUMENT_JSON:'+json.dumps(sys.argv[1:]))", arguments)
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode(errors="replace"))
        line = next(row for row in result.stdout.decode(errors="replace").splitlines() if row.startswith("ARGUMENT_JSON:"))
        self.assertEqual(json.loads(line.removeprefix("ARGUMENT_JSON:")), arguments)

    def test_owned_child_timeout_is_not_reported_as_success(self) -> None:
        if "TimeoutSeconds" not in (ROOT / "flash_esp32cam.ps1").read_text(encoding="utf-8"):
            self.fail("Native helper has no bounded subprocess deadline")
        result = self.native("import time; time.sleep(10)", timeout=1)
        self.assertEqual(result.returncode, 124, (result.stdout + result.stderr).decode(errors="replace"))
        self.assertIn(b"NATIVE_RESULT=124", result.stdout)

    def test_stdout_capture_does_not_treat_stderr_as_chip_identity(self) -> None:
        result = self.native("import sys; print('STDOUT_ONLY'); sys.stderr.write('STDERR_NOT_IDENTITY\\n')")
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode(errors="replace"))
        marker = next(row for row in result.stdout.decode(errors="replace").splitlines() if row.startswith("CAPTURE_BASE64="))
        captured = base64.b64decode(marker.removeprefix("CAPTURE_BASE64=")).decode()
        self.assertEqual(captured.strip(), "STDOUT_ONLY")
        self.assertIn("STDERR_NOT_IDENTITY", result.log)

    def test_output_overflow_cannot_be_reported_as_success(self) -> None:
        result = self.native("import sys; sys.stdout.write('X'*2000000)", output_limit=4096)
        self.assertEqual(result.returncode, 125, (result.stdout + result.stderr).decode(errors="replace")[:8000])
        self.assertLess(len(result.stdout), 12000)
        self.assertIn(b"NATIVE_RESULT=125", result.stdout)

    def test_timeout_cleans_up_only_the_owned_child_process_tree(self) -> None:
        if "TimeoutSeconds" not in (ROOT / "flash_esp32cam.ps1").read_text(encoding="utf-8"):
            self.fail("Native helper has no bounded subprocess deadline")
        program = ("import subprocess,sys,time; "
                   "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']); "
                   "print('SPAWNED_CHILD='+str(child.pid),flush=True); time.sleep(60)")
        result = self.native(program, timeout=1)
        self.assertEqual(result.returncode, 124, (result.stdout + result.stderr).decode(errors="replace"))
        self.assert_owned_child_stopped(result)

    def test_exited_parent_with_an_inherited_open_pipe_still_has_bounded_cleanup(self) -> None:
        program = ("import subprocess,sys; "
                   "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']); "
                   "print('SPAWNED_CHILD='+str(child.pid),flush=True)")
        result = self.native(program, timeout=1)
        self.assertEqual(result.returncode, 124, (result.stdout + result.stderr).decode(errors="replace"))
        self.assert_owned_child_stopped(result)

    def assert_owned_child_stopped(self, result: NativeResult) -> None:
        marker = next(line for line in result.log.splitlines() if line.startswith("SPAWNED_CHILD="))
        pid = int(marker.removeprefix("SPAWNED_CHILD="))
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        kernel.TerminateProcess.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x00100001, False, pid)  # SYNCHRONIZE | PROCESS_TERMINATE
        if not handle:
            self.assertEqual(ctypes.get_last_error(), 87, "Unexpected process inspection error")
            return  # the owned child was already reaped
        try:
            wait = kernel.WaitForSingleObject(handle, 5000)
            if wait != 0:
                # On regression, clean up only this spawned inert test process.
                kernel.TerminateProcess(handle, 1)
            self.assertEqual(wait, 0, "Owned descendant survived native deadline cleanup")
        finally:
            kernel.CloseHandle(handle)


class FlashLauncherTests(unittest.TestCase):
    def test_doubleclick_entrypoint_handles_unicode_spaces_and_no_review_opt_in(self) -> None:
        launcher_source = ROOT / "flash_esp32cam.cmd"
        self.assertTrue(launcher_source.is_file(), "Promised double-click entry point is missing")
        temporary = Path(os.environ["LOCALAPPDATA"]) / "Temp/opencode"
        with tempfile.TemporaryDirectory(prefix="smart_room_launcher_عربي & path_", dir=temporary) as directory:
            fixture = Path(directory)
            launcher = fixture / launcher_source.name
            launcher.write_bytes(launcher_source.read_bytes())
            # The actual wrapper executes only this authored inert sibling, not
            # the real firmware helper or any Arduino/serial tool.
            (fixture / "flash_esp32cam.ps1").write_text(r'''
[CmdletBinding()]
param([switch]$Interactive)
if (-not $Interactive) { exit 8 }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'invocation.json'), '{"interactive":true,"review_confirmed":false}')
exit 2
''', encoding="utf-8")
            command = f'"{CMD}" /d /s /c ""{launcher}""'
            result = subprocess.run(command, input=b"\r\n", capture_output=True, timeout=20, check=False)
            self.assertEqual(result.returncode, 2, (result.stdout + result.stderr).decode(errors="replace"))
            request = json.loads((fixture / "invocation.json").read_text(encoding="utf-8"))
            self.assertEqual(request, {"interactive": True, "review_confirmed": False})
            self.assertNotIn("ExecutionPolicy", launcher_source.read_text(encoding="utf-8"))

    def test_cancel_at_the_real_menu_happens_before_tools_or_serial(self) -> None:
        if "[switch]$Interactive" not in (ROOT / "flash_esp32cam.ps1").read_text(encoding="utf-8"):
            self.fail("Helper does not offer an interactive menu")
        result = subprocess.run([str(POWERSHELL), "-NoLogo", "-NoProfile", "-File",
                                 str(ROOT / "flash_esp32cam.ps1"), "-Interactive"],
                                input=b"\n", capture_output=True, timeout=20, check=False)
        self.assertEqual(result.returncode, 2, (result.stdout + result.stderr).decode(errors="replace"))
        self.assertIn(b"Cancelled before tool or serial access", result.stdout)
        self.assertNotIn(b"Compiling from source", result.stdout)

    def test_default_flash_refuses_without_hardware_review(self) -> None:
        result = subprocess.run([str(POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-File",
                                 str(ROOT / "flash_esp32cam.ps1")],
                                capture_output=True, timeout=20, check=False)
        self.assertEqual(result.returncode, 2, (result.stdout + result.stderr).decode(errors="replace"))
        self.assertIn(b"hardware review", result.stdout.lower())
        self.assertNotIn(b"Compiling from source", result.stdout)

    def test_flash_menu_cannot_confirm_hardware_review_by_itself(self) -> None:
        result = subprocess.run([str(POWERSHELL), "-NoLogo", "-NoProfile", "-File",
                                 str(ROOT / "flash_esp32cam.ps1"), "-Interactive"],
                                input=b"3\n\n", capture_output=True, timeout=20, check=False)
        self.assertEqual(result.returncode, 2, (result.stdout + result.stderr).decode(errors="replace"))
        self.assertIn(b"Cancelled before tool or serial access", result.stdout)
        self.assertNotIn(b"Compiling from source", result.stdout)

    def test_conflicting_modes_and_malformed_port_refuse_before_tools(self) -> None:
        for arguments in (("-CheckOnly", "-CompileOnly"), ("-Port", "COM13;echo BAD"),
                          ("-ExpectedMac", "not-a-mac")):
            with self.subTest(arguments=arguments):
                result = subprocess.run([str(POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-File",
                                         str(ROOT / "flash_esp32cam.ps1"), *arguments],
                                        capture_output=True, timeout=20, check=False)
                self.assertEqual(result.returncode, 2, (result.stdout + result.stderr).decode(errors="replace"))
                self.assertNotIn(b"Compiling from source", result.stdout)
                self.assertNotIn(b"arduino-cli :", result.stdout)


class FlashSourcePolicyTests(unittest.TestCase):
    def policy(self, config: str) -> dict[str, str]:
        script = r'''
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $env:SMART_ROOM_TEST_ROOT 'flash_esp32cam.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Helper parse failed' }
$functions = @($ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-PeripheralFlags'
}, $true))
if ($functions.Count -ne 1) { throw 'Expected one actual source-policy function' }
. ([scriptblock]::Create($functions[0].Extent.Text))
$config = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:SMART_ROOM_TEST_CONFIG))
Get-PeripheralFlags $config | ConvertTo-Json -Compress
'''
        environment = os.environ | {"SMART_ROOM_TEST_ROOT": str(ROOT),
                                    "SMART_ROOM_TEST_CONFIG": base64.b64encode(config.encode()).decode()}
        result = subprocess.run([str(POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
                                env=environment, capture_output=True, timeout=20, check=False)
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode(errors="replace"))
        return json.loads(result.stdout)

    def test_real_configuration_proves_only_literal_disabled_peripherals(self) -> None:
        flags = self.policy((ROOT / "firmware/smart_room/board_config.h").read_text(encoding="utf-8"))
        self.assertEqual(set(flags.values()), {"false"})

    def test_commented_and_quoted_false_cannot_hide_an_enabled_declaration(self) -> None:
        config = ('// constexpr bool ENABLE_RELAY = false;\n'
                  '/* constexpr bool ENABLE_RELAY = false; */\n'
                  'constexpr const char *text = "constexpr bool ENABLE_RELAY = false;";\n'
                  'constexpr bool ENABLE_RELAY = true; // reviewed in a disposable fixture only\n')
        self.assertEqual(self.policy(config)["ENABLE_RELAY"], "true")

    def test_missing_duplicate_or_expression_declarations_are_not_provably_false(self) -> None:
        for config in ('', 'constexpr bool ENABLE_RELAY = (false);\n',
                       'constexpr bool ENABLE_RELAY = false;\nconstexpr bool ENABLE_RELAY = true;\n',
                       '#if 0\nconstexpr bool ENABLE_RELAY = false;\n#else\nconstexpr bool ENABLE_RELAY = !false;\n#endif\n'):
            with self.subTest(config=config):
                self.assertEqual(self.policy(config)["ENABLE_RELAY"], "unknown")


class FlashChipIdentityTests(unittest.TestCase):
    def identity(self, text: str, *, native_exit: int = 0, helper_root: Path = ROOT) -> dict:
        script = r'''
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $env:SMART_ROOM_TEST_ROOT 'flash_esp32cam.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Helper parse failed' }
foreach ($name in @('Get-ChipMac', 'Confirm-ChipIdentity')) {
    $functions = @($ast.FindAll({ param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    if ($functions.Count -ne 1) { throw 'Expected one actual chip-identity function' }
    . ([scriptblock]::Create($functions[0].Extent.Text))
}
$script:data = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:SMART_ROOM_TEST_IDENTITY)) | ConvertFrom-Json
$Port = 'COM13'; $ExpectedMac = 'f0:24:f9:10:80:a4'; $script:calls = 0
function Invoke-Native {
    param($File, $Arguments, $TimeoutSeconds, [ref]$Output)
    $script:calls++
    $Output.Value = $script:data.text
    return $script:data.native_exit
}
function Say { param($Text, $Color) }
function Stop-With { param($Message, $Code); throw ('STOP_WITH_' + $Code + ': ' + $Message) }
try { Confirm-ChipIdentity 'inert-tool'; $ok = $true; $message = '' }
catch { $ok = $false; $message = $_.Exception.Message }
@{ok=$ok; message=$message; calls=$script:calls} | ConvertTo-Json -Compress
'''
        data = json.dumps({"text": text, "native_exit": native_exit}).encode()
        environment = os.environ | {"SMART_ROOM_TEST_ROOT": str(helper_root),
                                    "SMART_ROOM_TEST_IDENTITY": base64.b64encode(data).decode()}
        result = subprocess.run([str(POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
                                env=environment, capture_output=True, timeout=20, check=False)
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode(errors="replace"))
        return json.loads(result.stdout)

    def test_matching_chip_mac_is_the_positive_inert_control(self) -> None:
        result = self.identity('esptool v5.3.1\nMAC: F0:24:F9:10:80:A4\n')
        self.assertEqual(result, {"ok": True, "message": "", "calls": 1})

    def test_esptool_same_mac_before_and_after_stub_is_accepted(self) -> None:
        # Native stdout transcribed from the successful read-mac command in
        # main-upload-run-20261124-215028-015.txt. This is data, not a tool call.
        text = (ROOT / "tests/fixtures/esptool_5_3_1_read_mac.txt").read_text(encoding="utf-8")
        self.assertEqual(text.count("f0:24:f9:10:80:a4"), 2)
        self.assertEqual(self.identity(text), {"ok": True, "message": "", "calls": 1})

    def test_same_mac_case_labels_and_line_endings_are_normalized(self) -> None:
        for text in ("MAC: f0:24:f9:10:80:a4\nMAC: F0:24:F9:10:80:A4\n",
                     "MAC: F0:24:F9:10:80:A4\r\r\nMAC: f0:24:f9:10:80:a4\r\r\n",
                     "Base MAC address: F0:24:F9:10:80:A4\r\nMAC: f0:24:f9:10:80:a4\r\n",
                     "Base MAC: f0:24:f9:10:80:a4\nMAC address: F0:24:F9:10:80:A4\n"):
            with self.subTest(text=text):
                self.assertEqual(self.identity(text), {"ok": True, "message": "", "calls": 1})

    def test_repeated_wrong_mac_is_rejected_without_retry(self) -> None:
        result = self.identity("MAC: 00:11:22:33:44:55\nBase MAC: 00:11:22:33:44:55\n")
        self.assertFalse(result["ok"], result)
        self.assertEqual(result["calls"], 1)
        self.assertTrue(result["message"])

    def test_conflicting_macs_are_rejected_in_either_order_with_duplicates(self) -> None:
        expected = "MAC: f0:24:f9:10:80:a4\n"
        other = "Base MAC address: 00:11:22:33:44:55\n"
        for text in (expected + other, other + expected, expected + expected + other,
                     other + other + expected):
            with self.subTest(text=text):
                result = self.identity(text)
                self.assertFalse(result["ok"], result)
                self.assertEqual(result["calls"], 1)
                self.assertTrue(result["message"])

    def test_incomplete_unlabelled_or_malformed_mac_is_rejected(self) -> None:
        for text in ("", "f0:24:f9:10:80:a4\n", "MAC: f0:24:f9:10:80\n",
                     "MAC: f0:24:f9:10:80:a4:55\n", "MAC: f0:24:f9:10:80:gg\n",
                     "MAC: f024f91080a4\n", "MAC: f0:24:f9:10:80:a4 trailing text\n"):
            with self.subTest(text=text):
                result = self.identity(text)
                self.assertFalse(result["ok"], result)
                self.assertEqual(result["calls"], 1)
                self.assertTrue(result["message"])

    def test_failed_native_exit_cannot_be_rescued_by_repeated_correct_mac(self) -> None:
        for code in (7, 124, 125):
            with self.subTest(native_exit=code):
                result = self.identity("MAC: f0:24:f9:10:80:a4\nMAC: f0:24:f9:10:80:a4\n",
                                       native_exit=code)
                self.assertFalse(result["ok"], result)
                self.assertEqual(result["calls"], 1)
                self.assertTrue(result["message"])

    def test_disposable_first_mac_only_mutant_fails_the_conflict_oracle(self) -> None:
        source = (ROOT / "flash_esp32cam.ps1").read_bytes()
        self.assertEqual(source.count(b"Select-Object -Unique"), 1)
        mutant = source.replace(b"Select-Object -Unique", b"Select-Object -First 1")
        conflict = "MAC: f0:24:f9:10:80:a4\nMAC: 00:11:22:33:44:55\n"
        actual = self.identity(conflict)
        self.assertFalse(actual["ok"], actual)
        approved = Path(os.environ["LOCALAPPDATA"]) / "Temp/opencode"
        with tempfile.TemporaryDirectory(prefix="smart_room_mac_mutant_", dir=approved) as directory:
            fixture = Path(directory)
            (fixture / "flash_esp32cam.ps1").write_bytes(mutant)
            # Only the two AST-selected functions are loaded. No upload branch,
            # serial port or real native executable can run in this fixture.
            mutated = self.identity(conflict, helper_root=fixture)
            self.assertEqual(mutated, {"ok": True, "message": "", "calls": 1})
            with self.assertRaises(self.failureException):
                self.assertFalse(mutated["ok"], mutated)
        self.assertEqual((ROOT / "flash_esp32cam.ps1").read_bytes(), source)

    def test_wrong_missing_ambiguous_or_failed_chip_identity_refuses_without_retry(self) -> None:
        for text, code in (("MAC: 00:11:22:33:44:55\n", 0), ("not a MAC result", 0),
                           ("MAC: f0:24:f9:10:80:a4\nMAC: 00:11:22:33:44:55\n", 0),
                           ("MAC: f0:24:f9:10:80:a4\n", 7)):
            with self.subTest(text=text, code=code):
                result = self.identity(text, native_exit=code)
                self.assertFalse(result["ok"], result)
                self.assertEqual(result["calls"], 1)
                self.assertTrue(result["message"])


if __name__ == "__main__":
    unittest.main()
