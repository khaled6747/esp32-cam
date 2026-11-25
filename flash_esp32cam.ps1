#requires -Version 5.1
<#
  flash_esp32cam.ps1 - build and flash the Smart Room firmware to the
  AI-Thinker ESP32-CAM on the ESP32-CAM-MB USB base.

  This is the project's single flashing entry point. It never guesses a port,
  never retries an uncertain write, and never opens a serial monitor.

  Safe readiness check (no compile, no port, nothing written):
    powershell -NoProfile -File .\flash_esp32cam.ps1 -CheckOnly

  Compile only (no port, nothing written):
    powershell -NoProfile -File .\flash_esp32cam.ps1 -CompileOnly

  Force a from-scratch rebuild (use if the toolchain cache looks wrong):
    powershell -NoProfile -File .\flash_esp32cam.ps1 -CompileOnly -CleanBuild

  Flash (only after the hardware-photo and wiring review):
    powershell -NoProfile -File .\flash_esp32cam.ps1 `
      -Port COM13 -ConfirmHardwareReviewed

  Sequence of a real run:
    1. verify the opt-in flag and that the requested COM port exists
    2. compile the sketch from source
    3. back up the whole 4 MB flash and show the detected chip MAC
    4. require the operator to type FLASH
    5. upload with post-write verify

  It does not connect a mains load and does not enable the relay or IR in
  software. Sources are unchanged; only the board is written.
#>
[CmdletBinding()]
param(
    [string]$Port = 'COM13',
    [string]$ExpectedMac = 'f0:24:f9:10:80:a4',
    [switch]$Interactive,
    [switch]$ConfirmHardwareReviewed,
    [switch]$SkipBackup,
    [switch]$AllowEnabledOutputs,
    [switch]$CompileOnly,
    [switch]$CheckOnly,
    [switch]$CleanBuild,
    [string]$BuildDir = '',
    [string]$BackupDir = ''
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Sketch = Join-Path $Root 'firmware\smart_room'
$Fqbn = 'esp32:esp32:esp32cam:PartitionScheme=huge_app'
$Cli = 'C:\Program Files\Arduino CLI\arduino-cli.exe'
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$script:Log = Join-Path $Root ('logs\flash-' + $runId + '.log')

New-Item -ItemType Directory -Force -Path (Split-Path $script:Log) | Out-Null

function Say {
    param([string]$Text, [string]$Color = 'Gray')
    Write-Host $Text -ForegroundColor $Color
    Add-Content -LiteralPath $script:Log -Value $Text -Encoding utf8
}

function Stop-With {
    param([string]$Message, [int]$Code)
    Write-Host ''
    Write-Host "STOPPED: $Message" -ForegroundColor Red
    Write-Host "Log: $script:Log"
    exit $Code
}

trap {
    Stop-With ("Unexpected failure: " + $_.Exception.Message) 9
}

function Quote-NativeArg {
    param([AllowEmptyString()][string]$Value)
    # Windows argv quoting, not shell escaping. Preserve empty strings, quotes,
    # and runs of backslashes before a quote or the closing delimiter.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-Native {
    param(
        [string]$File, [string[]]$Arguments,
        [ValidateRange(1, 1800)][int]$TimeoutSeconds = 900,
        [ValidateRange(1024, 16777216)][int]$MaxOutputChars = 8388608,
        [ref]$Output
    )
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Native executable is missing: $File" }
    $quoted = @($Arguments | ForEach-Object { Quote-NativeArg $_ })
    Say ('> "' + $File + '" ' + ($quoted -join ' ')) 'DarkGray'

    # A private Windows Job attaches only to the process started below. Closing
    # it stops that process and inherited descendants, never an unrelated viewer.
    # This is lifecycle control, not a sandbox or a hardware authorization.
    if (-not ('SmartRoom.NativeJob' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
namespace SmartRoom {
  public sealed class NativeJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct Basic {
      public long ProcessTime, JobTime;
      public uint Flags;
      public UIntPtr MinWorking, MaxWorking;
      public uint ActiveLimit;
      public UIntPtr Affinity;
      public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct Counters {
      public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)] struct Extended {
      public Basic Limits;
      public Counters Io;
      public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr handle);
    IntPtr handle;
    public NativeJob() {
      handle = CreateJobObject(IntPtr.Zero, null);
      if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
      var info = new Extended();
      info.Limits.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
      int size = Marshal.SizeOf(typeof(Extended));
      IntPtr buffer = Marshal.AllocHGlobal(size);
      try {
        Marshal.StructureToPtr(info, buffer, false);
        if (!SetInformationJobObject(handle, 9, buffer, (uint)size))
          throw new Win32Exception(Marshal.GetLastWin32Error());
      } catch { Dispose(); throw; }
      finally { Marshal.FreeHGlobal(buffer); }
    }
    public void Attach(Process process) {
      if (!AssignProcessToJobObject(handle, process.Handle))
        throw new Win32Exception(Marshal.GetLastWin32Error());
    }
    public void Dispose() {
      if (handle == IntPtr.Zero) return;
      if (!CloseHandle(handle)) throw new Win32Exception(Marshal.GetLastWin32Error());
      handle = IntPtr.Zero;
      GC.SuppressFinalize(this);
    }
    ~NativeJob() { if (handle != IntPtr.Zero) CloseHandle(handle); }
  }
}
'@
    }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $File
    $info.Arguments = $quoted -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $job = New-Object SmartRoom.NativeJob
    $started = $false
    $code = $null
    $text = @((New-Object System.Text.StringBuilder), (New-Object System.Text.StringBuilder))
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $started = $process.Start()
        if (-not $started) { throw "Could not start $File" }
        $job.Attach($process)
        $readers = @($process.StandardOutput, $process.StandardError)
        [char[]]$outBuffer = New-Object char[] 4096
        [char[]]$errBuffer = New-Object char[] 4096
        $buffers = @($outBuffer, $errBuffer)
        $pending = @($readers[0].ReadAsync($outBuffer, 0, 4096), $readers[1].ReadAsync($errBuffer, 0, 4096))
        while ($true) {
            $indices = @(); $tasks = @()
            for ($i = 0; $i -lt 2; $i++) {
                if ($null -ne $pending[$i]) { $indices += $i; $tasks += $pending[$i] }
            }
            if ($tasks.Count -eq 0) { break }
            $remaining = [int]($TimeoutSeconds * 1000 - $clock.ElapsedMilliseconds)
            if ($remaining -le 0) { $code = 124; break }
            $ready = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]$tasks, $remaining)
            if ($ready -lt 0) { $code = 124; break }
            $index = $indices[$ready]
            $count = $pending[$index].GetAwaiter().GetResult()
            if ($count -eq 0) { $pending[$index] = $null; continue }
            if ($text[0].Length + $text[1].Length + $count -gt $MaxOutputChars) { $code = 125; break }
            [void]$text[$index].Append($buffers[$index], 0, $count)
            $pending[$index] = $readers[$index].ReadAsync($buffers[$index], 0, 4096)
        }
        if ($null -eq $code) {
            $remaining = [int][Math]::Max(0, $TimeoutSeconds * 1000 - $clock.ElapsedMilliseconds)
            if (-not $process.WaitForExit($remaining)) { $code = 124 }
            else { $code = $process.ExitCode }
        }
    } finally {
        # Job closure also handles a descendant that keeps stdout open after its
        # root exits. An attachment/start/cleanup failure is not success.
        try { $job.Dispose() }
        finally {
            if ($started -and -not $process.HasExited) {
                if (-not $process.WaitForExit(5000)) {
                    $process.Kill()
                    if (-not $process.WaitForExit(5000)) { throw 'Owned native process cleanup did not complete' }
                }
            }
            $process.Dispose()
        }
    }
    $stdout = $text[0].ToString()
    $stderr = $text[1].ToString()
    foreach ($stream in @($stdout, $stderr)) {
        if ($stream.Length -gt 0) {
            Write-Host $stream.TrimEnd()
            Add-Content -LiteralPath $script:Log -Value $stream.TrimEnd() -Encoding utf8
        }
    }
    if ($null -ne $Output) { $Output.Value = $stdout }
    if ($code -eq 124) { Say 'Native deadline exceeded; owned process job closed. Do not automatically retry a write.' 'Red' }
    if ($code -eq 125) { Say 'Native output bound exceeded; owned process job closed. Result is incomplete.' 'Red' }
    Say ("ExitCode: $code") 'DarkGray'
    return $code
}

function Get-SerialPorts {
    try { return @([System.IO.Ports.SerialPort]::GetPortNames()) }
    catch { Stop-With ('Serial inventory failed without opening a port: ' + $_.Exception.Message) 3 }
}

function Find-Esptool {
    $exe = Join-Path $env:LOCALAPPDATA 'Arduino15\packages\esp32\tools\esptool_py\5.3.1\esptool.exe'
    if (Test-Path -LiteralPath $exe -PathType Leaf) { return $exe }
    return $null
}

function Get-ChipMac {
    param([string]$Text)
    $matches = [regex]::Matches($Text, '(?im)^\s*(?:MAC|Base MAC)(?: address)?\s*:\s*([0-9a-f]{2}(?::[0-9a-f]{2}){5})\s*$')
    # esptool 5.3.1 reports the same MAC before and after starting its RAM stub.
    # Require one distinct normalized identity, not one occurrence. A different
    # address anywhere in the recognized output must still stop the upload.
    $macs = @($matches | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Select-Object -Unique)
    if ($macs.Count -ne 1) { throw 'Chip identity output is missing or ambiguous; upload is not permitted' }
    return $macs[0]
}

function Get-PeripheralFlags {
    param([string]$Config)
    # Strip ordinary C++ comments and quoted literals before looking for exactly
    # one literal declaration. This is conservative source inspection, not a C++
    # preprocessor/security boundary; the actual compiler enforces board_policy.
    $plain = [regex]::Replace($Config, '(?s)/\*.*?\*/|//[^\r\n]*|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''', ' ')
    $flags = @{}
    foreach ($name in @('HARDWARE_REVIEWED', 'ENABLE_OLED', 'ENABLE_IR_RECEIVE', 'ENABLE_IR_TRANSMIT', 'ENABLE_RELAY')) {
        $declarationCount = [regex]::Matches($plain, '\b(?:constexpr|const)\s+bool\s+' + $name + '\b').Count
        $declarations = [regex]::Matches($plain, '(?m)^\s*constexpr\s+bool\s+' + $name + '\s*=\s*(true|false)\s*;\s*$')
        $flags[$name] = if ($declarationCount -eq 1 -and $declarations.Count -eq 1) { $declarations[0].Groups[1].Value } else { 'unknown' }
    }
    return $flags
}

function Get-SourceFingerprint {
    $rows = @(Get-ChildItem -LiteralPath $Sketch -File | Where-Object { $_.Extension -in @('.h', '.hpp', '.ino') } |
        Sort-Object Name | ForEach-Object { $_.Name + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })
    if ($rows.Count -lt 5) { throw 'Sketch source inventory is unexpectedly incomplete' }
    return $rows -join "`n"
}

function Confirm-ChipIdentity {
    param([string]$Tool)
    $identity = ''
    $code = Invoke-Native -File $Tool -Arguments @('--chip', 'esp32', '--port', $Port, '--baud', '460800',
        '--before', 'default-reset', '--after', 'hard-reset', 'read-mac') -TimeoutSeconds 45 -Output ([ref]$identity)
    if ($code -ne 0) { Stop-With 'Chip identity read did not complete. No upload was attempted.' 5 }
    $mac = Get-ChipMac $identity
    if ($mac -cne $ExpectedMac) { Stop-With ("Wrong board on $Port`: expected $ExpectedMac, observed $mac. No upload was attempted.") 5 }
    Say ('Chip identity matched: ' + $mac) 'Green'
}

# ---------------------------------------------------------------- setup -----
if (($CheckOnly -and $CompileOnly) -or ($Interactive -and ($CheckOnly -or $CompileOnly -or $ConfirmHardwareReviewed -or $SkipBackup -or $AllowEnabledOutputs))) {
    Stop-With 'Choose one mode only. The double-click menu does not accept automatic review/backup overrides.' 2
}
if ($Interactive) {
    Write-Host ''
    Write-Host 'Smart Room - choose an operation:' -ForegroundColor Cyan
    Write-Host '  1  Readiness check (no serial open, no compile, no flash)'
    Write-Host '  2  Compile only (no board or serial open)'
    Write-Host '  3  Flash ONLY after qualified hardware review and load isolation'
    Write-Host '  0  Cancel'
    Write-Host ''
    Write-Host 'Reported COM-to-L / NO-to-N wiring is a short. Do NOT energize it.' -ForegroundColor Red
    Write-Host 'GPIO16, GPIO12 and the missing IR LED current limiter also need review.' -ForegroundColor Yellow
    $choice = (Read-Host 'Choose 1, 2, 3, or press Enter to cancel').Trim()
    switch ($choice) {
        '1' { $CheckOnly = $true }
        '2' { $CompileOnly = $true }
        '3' {
            Write-Host 'A qualified review must be finished. No mains, relay/AC load or unsafe GPIO wiring may remain.' -ForegroundColor Yellow
            $review = Read-Host 'Type HARDWARE_REVIEWED_NO_LOAD to confirm, or press Enter to cancel'
            if ($review -cne 'HARDWARE_REVIEWED_NO_LOAD') {
                Say 'Cancelled before tool or serial access; hardware review was not confirmed.' 'Yellow'
                exit 2
            }
            $ConfirmHardwareReviewed = $true
        }
        default {
            Say 'Cancelled before tool or serial access; nothing was compiled or flashed.' 'Yellow'
            exit 2
        }
    }
    if (-not $CompileOnly) {
        $selectedPort = (Read-Host ('Explicit COM port [expected ' + $Port + ']')).Trim()
        if ($selectedPort) { $Port = $selectedPort }
    }
}
$Port = $Port.Trim()
if ($Port -match '^com(\d+)$') { $Port = 'COM' + $Matches[1] }
if ($Port -cnotmatch '^COM[1-9]\d{0,3}$') { Stop-With 'Invalid port. Use an explicit Windows port such as COM13.' 2 }
$ExpectedMac = $ExpectedMac.Trim().ToLowerInvariant()
if ($ExpectedMac -cnotmatch '^[0-9a-f]{2}(?::[0-9a-f]{2}){5}$') { Stop-With 'ExpectedMac must contain six colon-separated hexadecimal bytes.' 2 }

$mode = if ($CheckOnly) { 'CHECK ONLY' } elseif ($CompileOnly) { 'COMPILE ONLY' } else { 'FLASH' }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host (' Smart Room - ESP32-CAM flash helper  [' + $mode + ']') -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host ('Project : ' + $Root)
Write-Host ('Port    : ' + $Port)
Write-Host ''

Say ('Started: ' + (Get-Date).ToString('o'))
Say ('Mode: ' + $mode)
Say ('Port: ' + $Port)

if ($CheckOnly) {
    Say 'CHECK ONLY: no compile, no port opened, nothing written.' 'Cyan'
} else {
    Write-Host 'A flash replaces the board image. Required before writing:' -ForegroundColor Yellow
    Write-Host '  * relay, IR receiver, transistor and OLED photos/pinout reviewed' -ForegroundColor Yellow
    Write-Host '  * IR receiver signal disconnected from GPIO2 while flashing' -ForegroundColor Yellow
    Write-Host '  * no mains wiring and no relay/AC load connected' -ForegroundColor Yellow
    Write-Host '  * USB from the ESP32-CAM-MB only (no extra 5V into the board)' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Reported COM-to-L / NO-to-N is a direct short; do NOT energize it.' -ForegroundColor Red
    Write-Host 'Software-disabled outputs do not isolate unsafe wiring during boot/reset.' -ForegroundColor Yellow
    Write-Host ''
}

# ------------------------------------------------------- source checks -----
if (-not (Test-Path -LiteralPath $Sketch -PathType Container)) {
    Stop-With "Sketch directory not found: $Sketch" 3
}
if (-not (Test-Path -LiteralPath (Join-Path $Sketch 'smart_room.ino'))) {
    Stop-With "Missing smart_room.ino in $Sketch" 3
}
if (-not (Test-Path -LiteralPath $Cli)) {
    Stop-With 'The reviewed arduino-cli executable was not found at "C:\Program Files\Arduino CLI\arduino-cli.exe". No installation or PATH fallback is performed.' 3
}

# Fail closed: anything that is not provably "= false;" counts as enabled.
$configPath = Join-Path $Sketch 'board_config.h'
$config = Get-Content -LiteralPath $configPath -Raw
$flags = Get-PeripheralFlags $config
$dangerous = @('ENABLE_OLED', 'ENABLE_IR_RECEIVE', 'ENABLE_IR_TRANSMIT', 'ENABLE_RELAY')
$enabled = @()
foreach ($name in $dangerous) {
    if ($flags[$name] -cne 'false') {
        $enabled += $name
    }
}
$oledOn = $flags['ENABLE_OLED'] -ceq 'true'
Say ('Peripheral declarations: ' + (($dangerous | ForEach-Object { $_ + '=' + $flags[$_] }) -join ', '))

if ($enabled.Count -gt 0) {
    Say ('Peripherals are enabled or not provably disabled in board_config.h: ' + ($enabled -join ', ')) 'Red'
    if (-not $CompileOnly -and -not $CheckOnly -and -not $AllowEnabledOutputs) {
        Stop-With ('Refusing to flash firmware that may energize unreviewed hardware: ' + ($enabled -join ', ') + '. Finish the hardware review, or pass -AllowEnabledOutputs knowingly.') 2
    }
    Say 'An enabled peripheral also requires HARDWARE_REVIEWED=true and a valid board_policy at compile time. Those are assertions, not electrical measurements.' 'Yellow'
}
if (-not $oledOn) {
    Say 'NOTE: ENABLE_OLED is false, so the published app cannot complete BLE passkey ownership yet.' 'Yellow'
}

# ------------------------------------------------------------ check mode ---
if ($CheckOnly) {
    $problems = @()

    $cliVersion = ''
    $code = Invoke-Native -File $Cli -Arguments @('version') -TimeoutSeconds 30 -Output ([ref]$cliVersion)
    if ($code -ne 0) {
        $problems += 'arduino-cli does not run'
        Say ('arduino-cli : FAIL (' + $cliVersion + ')') 'Red'
    } else {
        Say ('arduino-cli : OK (' + $cliVersion.Trim() + ')') 'Green'
    }

    $details = ''
    $code = Invoke-Native -File $Cli -Arguments @('board', 'details', '-b', $Fqbn) -TimeoutSeconds 30 -Output ([ref]$details)
    if ($code -ne 0) {
        $problems += "board definition $Fqbn is not installed"
        Say ('board       : FAIL (' + $Fqbn + ')') 'Red'
    } else {
        $versionMatch = [regex]::Match($details, 'Board version:\s*(\S+)')
        $coreVersion = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { 'unknown' }
        Say ('board       : OK (' + $Fqbn + ', core ' + $coreVersion + ')') 'Green'
    }

    $esptool = Find-Esptool
    if ($esptool) {
        Say ('esptool     : OK (' + $esptool + ')') 'Green'
    } else {
        $problems += 'reviewed esptool 5.3.1 is missing (identity and backup gates cannot run)'
        Say 'esptool     : MISSING (needed for the pre-flash backup)' 'Yellow'
    }

    $ports = Get-SerialPorts
    $portList = if ($ports.Count -gt 0) { $ports -join ', ' } else { '(none)' }
    $portLabel = ('port ' + $Port).PadRight(12) + ': '
    if ($ports | Where-Object { $_ -ieq $Port }) {
        Say ($portLabel + 'OK') 'Green'
    } else {
        $problems += "port $Port is not present (available: $portList)"
        Say ($portLabel + 'MISSING (available: ' + $portList + ')') 'Red'
    }

    Say ''
    if ($problems.Count -gt 0) {
        Say ('NOT READY: ' + ($problems -join '; ')) 'Red'
        Say 'Nothing was compiled, no port was opened and nothing was written.'
        exit 3
    }
    Say 'TOOLS PRESENT: toolchain, board definition and requested port are present. This is NOT hardware approval or a chip-identity check.' 'Green'
    Say 'Nothing was compiled, no port was opened and nothing was written.'
    Say ('Log: ' + $script:Log)
    exit 0
}

# -------------------------------------------------------- flash preamble ---
if (-not $CompileOnly) {
    if (-not $ConfirmHardwareReviewed) {
        Write-Host ''
        Write-Host 'REFUSED: hardware review was not confirmed, so nothing was written.' -ForegroundColor Red
        Write-Host ''
        Write-Host 'After reviewing the photos and wiring, run:' -ForegroundColor Yellow
        Write-Host ('  powershell -NoProfile -File "' + $PSCommandPath + '" -Port ' + $Port + ' -ConfirmHardwareReviewed') -ForegroundColor White
        Write-Host ''
        exit 2
    }

    $present = Get-SerialPorts
    if (-not ($present | Where-Object { $_ -ieq $Port })) {
        $list = if ($present.Count -gt 0) { $present -join ', ' } else { '(none)' }
        Stop-With ("Port $Port is not present. Available serial ports: $list. Connect the ESP32-CAM-MB by USB and pass the matching -Port.") 3
    }
}

# -------------------------------------------------------------- compile ----
$scratch = Join-Path $env:LOCALAPPDATA 'Temp\opencode\smart_room_flash'
# A new output directory prevents stale artifacts from an earlier build from
# being uploaded. Caller-selected BuildDir is kept as the parent, not erased.
if (-not $BuildDir) { $BuildDir = Join-Path $scratch 'runs' }
$BuildDir = Join-Path (Join-Path $BuildDir $runId) 'build'
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

# Keep the toolchain's object cache in an ASCII scratch path, away from the
# sketch folder and from the Arabic project path.
$CacheDir = Join-Path $scratch 'cache'
if ($CleanBuild) {
    $CacheDir = Join-Path (Join-Path $scratch 'clean-cache') $runId
    Say ('Using a fresh toolchain cache; existing caches are preserved: ' + $CacheDir) 'Yellow'
}
$sourceFingerprint = Get-SourceFingerprint

Say ''
Say 'Compiling from source...' 'Cyan'
$compileArgs = @('compile', '--fqbn', $Fqbn, '--build-path', $CacheDir, '--output-dir', $BuildDir, '--jobs', '2', '--warnings', 'all', $Sketch)
$code = Invoke-Native $Cli $compileArgs
if ($code -ne 0) { Stop-With 'Compilation failed; nothing was flashed.' 4 }
if ((Get-SourceFingerprint) -cne $sourceFingerprint) { Stop-With 'Sketch sources changed during compilation. No upload is permitted; review the change and build again.' 4 }

$bin = Join-Path $BuildDir 'smart_room.ino.bin'
if (-not (Test-Path -LiteralPath $bin)) { Stop-With "Compiled application image not found: $bin" 4 }
$binInfo = Get-Item -LiteralPath $bin
if ($binInfo.Length -lt 100000) {
    Stop-With ('Compiled image looks wrong: ' + $binInfo.Length + ' bytes at ' + $bin) 4
}
$binHash = (Get-FileHash -LiteralPath $bin -Algorithm SHA256).Hash.ToLowerInvariant()
Say ('Application image: ' + $binInfo.Length + ' bytes') 'Green'
Say ('SHA-256: ' + $binHash)
Say ('Build output: ' + $BuildDir)
$artifactHashes = @{}
foreach ($name in @('smart_room.ino.bin', 'smart_room.ino.bootloader.bin', 'smart_room.ino.partitions.bin', 'smart_room.ino.merged.bin')) {
    $file = Join-Path $BuildDir $name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Stop-With ('Compiled artifact is missing: ' + $file) 4 }
    $artifactHashes[$name] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}

if ($CompileOnly) {
    Say ''
    Say 'Compile-only run complete. No port was opened and nothing was written.' 'Green'
    Say ('Log: ' + $script:Log)
    exit 0
}

# --------------------------------------------------------------- backup ----
$backup = $null
$esptool = Find-Esptool
if (-not $esptool) { Stop-With 'Reviewed esptool 5.3.1 is required for chip identity even when -SkipBackup is supplied. No upload was attempted.' 5 }
Confirm-ChipIdentity $esptool
if (-not $SkipBackup) {
    if (-not $BackupDir) { $BackupDir = Join-Path $Root 'backups' }
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $backup = Join-Path $BackupDir ('esp32cam-full-4mb-' + $runId + '.bin')

    Say ''
    Say ('Reading the current flash from ' + $Port + ' (this also prints the chip identity)...') 'Cyan'
    $backupArgs = @('--chip', 'esp32', '--port', $Port, '--baud', '460800',
        '--before', 'default-reset', '--after', 'hard-reset',
        'read-flash', '--no-progress', '0', '0x400000', $backup)
    $code = Invoke-Native -File $esptool -Arguments $backupArgs -TimeoutSeconds 180
    $backupLength = if (Test-Path -LiteralPath $backup) { (Get-Item -LiteralPath $backup).Length } else { 0 }
    if ($code -ne 0 -or $backupLength -ne 4194304) {
        Stop-With ('Flash backup failed or was incomplete (' + $backupLength + ' bytes). The upload was not attempted.') 5
    }
    $backupHash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant()
    Say ('Backup: ' + $backup) 'Green'
    Say ('Backup SHA-256: ' + $backupHash)
    Say ('Restore: "' + $esptool + '" --chip esp32 --port ' + $Port + ' --baud 460800 write-flash 0x0 "' + $backup + '"')
} else {
    Say 'WARNING: -SkipBackup was supplied; the current flash is not preserved.' 'Red'
}

# ------------------------------------------------------------ last gate ----
Write-Host ''
Write-Host ('About to write to ' + $Port + ':') -ForegroundColor Yellow
Write-Host ('  expected MAC: ' + $ExpectedMac)
Write-Host ('  application : ' + $binInfo.Length + ' bytes, SHA-256 ' + $binHash)
if ($backup) { Write-Host ('  backup      : ' + $backup) }
else { Write-Host '  backup      : NONE (-SkipBackup)' -ForegroundColor Red }
Write-Host '  relay/AC    : must still be disconnected' -ForegroundColor Yellow
Write-Host ''
$answer = Read-Host 'Type FLASH to write the image, or press Enter to cancel'
if ($answer -cne 'FLASH') {
    Write-Host 'Cancelled; nothing was written.' -ForegroundColor Yellow
    Say 'Cancelled by operator; nothing was written.'
    exit 2
}

# --------------------------------------------------------------- upload ----
Confirm-ChipIdentity $esptool
if ((Get-SourceFingerprint) -cne $sourceFingerprint) { Stop-With 'Sketch sources changed after the build. No upload was attempted.' 4 }
foreach ($name in $artifactHashes.Keys) {
    $hashNow = (Get-FileHash -LiteralPath (Join-Path $BuildDir $name) -Algorithm SHA256).Hash
    if ($hashNow -cne $artifactHashes[$name]) { Stop-With ('Compiled artifact changed before upload: ' + $name + '. No upload was attempted.') 4 }
}
Say ''
Say 'Uploading with post-write verify...' 'Cyan'
$uploadArgs = @('upload', '-p', $Port, '-b', $Fqbn, '--input-dir', $BuildDir, '-t', $Sketch)
$code = Invoke-Native -File $Cli -Arguments $uploadArgs -TimeoutSeconds 180
if ($code -ne 0) {
    Say ''
    Say 'Upload failed or the verify step failed. Do not retry in a loop.' 'Red'
    Say 'Check the USB cable, the ESP32-CAM-MB boot circuit and that no other program owns the port.' 'Red'
    if ($backup) { Say ('The previous image is preserved at: ' + $backup) 'Yellow' }
    exit 6
}

Say ''
Say 'UPLOAD COMPLETED AND REPORTED VERIFIED.' 'Green'
Say ('Port: ' + $Port)
Say ('Application SHA-256: ' + $binHash)
if ($backup) { Say ('Previous flash backup: ' + $backup) }
Say ''
Say 'What this run does NOT prove:' 'Yellow'
Say '  * no mains or relay load was connected or tested'
Say ('  * source peripheral declarations: ' + (($dangerous | ForEach-Object { $_ + '=' + $flags[$_] }) -join ', '))
Say '  * BLE pairing/owner provisioning needs a working OLED and a reviewed build'
Say '  * no camera-image, room-counting or AC-control test was performed'
Say '  * this helper does not open a serial monitor'
Say ('Log: ' + $script:Log)
exit 0
