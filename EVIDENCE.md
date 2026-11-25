# Evidence ledger — Smart Room software package

All assistant work is local. No global dependencies were installed and the
assistant did not connect or energize mains. During software packaging, no flash
or physical test was performed. The separately authorized isolated USB-only flash
attempt stopped during chip-identity reading, before backup or flash writes. A
later bounded live preview from pre-existing camera firmware produced 860 valid
VGA JPEGs; no new firmware was written and the main-project camera test remains
blocked. This is not approval of connected peripherals.
The user has reported mains-related wiring; COM-to-L/NO-to-N is
a direct short on closure, not an approved circuit. It must not be energized or
touched live and requires qualified electrical isolation/review. The preserved
`esp32cam_live` project was not modified.

Recorded on 2026-11-24. Evidence transcripts and build outputs are retained under
`C:\Users\khale\AppData\Local\Temp\opencode\` unless a path is given.

## Current request — ESP32-CAM OV2640 CH340 compatibility and 4GB card need

The operator specified **ESP32-CAM OV2640 Camera CH340** and a **4GB microSD**,
asking to check that the main code suits this board and to use the card only if
its space is needed. This review performs no new serial, upload, card mount,
format, file read/write on the card or peripheral enabling. The existing waiver
of a full-board backup remains in effect; it is not reinstated by this review.
Scope: `logs/board-sd-review-scope-20261124-231624-927.json`.
The upload batch's actual 1/4 record was archived byte-for-byte under
`progress/history/main-paused-for-board-sd-review-20261124-231624-927.json`.

### Executed inert source/build characterization

`logs/board-sd-review-20261124-231624-927.json` records the successful Python
**3.14.7** isolated source/build-data validation (**exit 0**), including exact
paths and SHA-256 fingerprints. No new compile was run: the prior compile exit0
is still tied to all nine unchanged firmware source hashes and four matching
recorded build artifacts. **50 preserved files** and the prior batch archive
matched. The old source projects, helper, peripheral declarations, CMD and
historical `dist/` remain unchanged.

- Installed board target: **AI Thinker ESP32-CAM / ESP32**; recorded chip type
  ESP32-D0WD-V3 and historical PnP `USB-SERIAL CH340 (COM13)` are compatible with
  this class. CH340 is the UART bridge, not a different firmware processor.
  Product naming and historical identities do not independently certify the
  physical module, pin wiring, PSRAM capacity or current boot mode.
- **16 camera pin fields** match the old source and the AI-Thinker example in
  the installed core. The selected qio_qspi SDK enables OV2640, PSRAM, Bluedroid
  and BLE; the preserved map has linked addresses for OV2640 detect/init,
  `esp_camera_init` and Bluedroid init/enable. Cache ELF/map/application match
  their preserved run copies. These are build facts, not radio/camera execution.
- The **actual compiled partition binary** matched the installed `huge_app.csv`
  and its MD5 trailer. The **1,306,528 B** image fits the **3,145,728 B** app slot;
  the `spiffs`-label data partition used by LittleFS is **917,504 B**. The table
  is configured for 4MB internal flash, not the 4GB card. No new physical flash
  capacity or free-filesystem-space measurement was made.
- IR storage is limited in code to **16 full-state records** / **1,024 pulses**
  each. Maximum serialized record: **2,120 B**; primary payload total **33,920 B**.
  With previous per-record files and one pending write, file payload is bounded
  to **69,960 B**, excluding filesystem overhead. This is below the configured
  data partition, not proof of successful LittleFS mount or measured free space.
  IR `.bak` fallback files are not a 4MB board backup. A card would not remove
  the slot/protocol limit or supply RAM/PSRAM.
- All nine firmware files were checked for SD backend includes/calls: **none**.
  Installed ESP32 SD_MMC slot1 uses 14/15/2 in 1-bit mode, conflicting with the
  configured OLED SCL / relay / IR receiver roles if enabled. 4-bit adds 4/12/13
  and also conflicts with IR TX / OLED SDA. Those roles are currently disabled;
  this is an integration design conflict, not an observed active SD collision.
  The installed driver cannot remap classic-ESP32 slot1 arbitrarily.

**Recommendation:** keep microSD unused for this project's current 16-state IR
storage. Optional future image/log recording needs explicit requirements,
privacy/retention, pin/power/boot review and non-auto-format SD support. No card
filesystem or contents were inspected, and no card data was deleted.

**Whole-project operation is still blocked:** camera setup requires detected
PSRAM; the current build disables OLED/IR/relay. First phone ownership requires
a working OLED for secure passkey display, so it cannot be completed with the
present `ENABLE_OLED=false`. The 65,380 B static-globals report is not runtime heap
headroom after camera/UART/BLE allocations. No main firmware was uploaded; its
last `0x73` failure occurred before application transmission and does not prove
a code/board mismatch. Runtime status/JPEG, memory stability, phone, actual IR,
room-count accuracy and electrical acceptance remain unverified.

Details: `docs/board-compatibility.md`; pin conflicts also added to
`docs/hardware.md`. The reusable review batch keeps source/build compatibility
and the storage decision separate from the blocked physical runtime task and
the existing five physical project gates.

### Review ledger and rendered progress checks

- **12/12 dashboard tests passed**, Python 3.14.7, **0.266 s**, exit0,
  zero failures/errors/skips; transcript and exact record hash in
  `logs/board-sd-dashboard-20261124-231624-927.{json,txt}`. These test the validated
  record and owned loopback-only HTTP fixtures, not the board or microSD.
- Existing Review tab returned **HTTP200** and rendered **2/3** with
  `verified / verified / blocked`, matching saved record SHA-256
  `03142ce08772528cc8b45ce5fea7a5e6ef5d1d075ff70a9518d55984d492de91`.
  The card decision, unverified runtime/OLED prerequisite and backup waiver
  remained visible; all five physical project gates remained blocked.
  `logs/board-sd-browser-20261124-231624-927.json`.
- Final documentary-state/preservation receipt path:
  `logs/board-sd-final-verification-20261124-231624-927.json`.
  No firmware, helper, CMD, toolchain or distribution change belongs to this review.

## Paused request — replace board camera firmware with the main project

The operator requested the main `esp32cam_smart_room` upload after seeing live
camera preview. The earlier **USB فقط؛ FLASH** authorizations required a full4MB
board backup. **The latest explicit user request supersedes that backup condition:**
upload normally without a backup, with permission to overwrite or erase existing
board firmware/data. The operator then selected **جاهزة؛ الأزرار متروكة**, confirming
USB-only isolation, disconnected external components/power and released FLASH/RST.
This does not authorize deleting source projects, enabling peripherals, changing
tools/drivers, microSD access, mains or an automatic retry loop. The planned method
uses the existing `-SkipBackup` option, not a separate erase-all.

The preceding camera-only request is superseded; its source/build/evidence are
retained, not flashed. `../esp32cam_camera_test/EVIDENCE.md` and
`../esp32cam_camera_test/logs/camera-current-view-20261124-202325-323.json` record
**860 CRC-valid VGA JPEGs** from the **pre-existing** board firmware during a
120second/16MiB-bounded live preview. The serial port and owned HTTP thread closed.
The browser read was HTTP200 with a visible640×480 image and7.39FPS at that time.
No new marker/MAC was observed and no write or backup occurred. This is not proof
that a new upload is accepted, nor a root-cause diagnosis of previous failures.
The unchanged, software-disabled main peripheral configuration remains mandatory.

### Latest normal/no-backup attempt — 22:49:25–22:50:06 UTC

The newly authorized run called the **unchanged corrected helper once**, with
`-Port COM13 -ExpectedMac f0:24:f9:10:80:a4 -ConfirmHardwareReviewed -SkipBackup`.
Both buttons were reported released; the ordinary `default-reset` / `hard-reset`
behavior was retained, with no manual button holding, driver or baud change.
Authorization: `logs/main-nobackup-authorization-20261124-224738-130.json`.

Compilation succeeded at **exit 0**: 1,306,373 B program, 65,380 B globals and
1,306,528 B application. The one native `read-mac` invocation failed at **exit 2**
with **"Invalid head of packet (0x73): Possible serial noise or corruption"**;
the helper stopped at **exit 5**, before the skip-backup branch, delegated FLASH
prompt, second identity check or upload. `skip_backup_warning_observed:false`
means that branch was not reached; the wrapper's actual `-SkipBackup` argument
was separately verified. **No read-flash, board backup, upload or erase-all occurred.**
The permission to lose existing board contents remains explicit; the failure was
not a refusal to waive the backup.

- Result/native exits **[0, 2]**: `logs/main-nobackup-result-20261124-224738-130.json`.
- Transcripts: `logs/main-nobackup-run-20261124-224738-130.txt` and
  `logs/flash-20261125-004927-fc02cdfe.log`.
- The create-new start marker prevents replay of this consumed run:
  `logs/main-nobackup-start-20261124-224738-130.json`.
- Offline wrapper controls passed: PS5.1 parsing, exactly one original-helper
  call with the supported SkipBackup option, exact delegated FLASH input reaching
  child scope, rejection of unexpected prompts, disabled-output/source/tool hashes
  and read-only COM13 inventory. Runner Ruff 0.17.4 isolated E9/F **exit 0**.
  `logs/main-nobackup-wrapper-check-20261124-224738-130.json`.
- Four build artifacts are retained under
  `smart_room_flash/runs/20261125-004927-fc02cdfe/build`; application SHA-256 remains
  `a70e1bf1e9f7544a576bd7b82eec15aeccd1f851f3d2f1781af1be859e272b70`.
  The compiler's 4MB `merged.bin` is **a new-build artifact, not a board backup**.
- Post-upload prerequisites only: **6 inert controls passed** on a synthetic VGA
  JPEG, bounded SOF rejection, target/disabled-output status controls and fragmented
  CRC framing. The reviewed pyserial loader was loaded without opening a port;
  Python 3.14.7, pyserial 3.5, OpenCV 5.0.0 and NumPy 2.5.4. No `read_camera` call,
  physical camera image or saved image. `logs/main-nobackup-usb-prerequisites-20261124-224738-130.json`.

The serial bytes were not accepted as bootloader replies; **their source and the
cause are unconfirmed**. The esptool error's suggestion is not a measured diagnosis
of cable noise. Waiving a backup does not resolve this failure, which occurs before
application transmission. The previous successful MAC read and camera preview
remain historical evidence, not acceptance of this main-project upload. Further
device work is paused for diagnostic evidence rather than another guessed retry.
The board application was not replaced; main USB/runtime, BLE, IR, room accuracy
and external wiring acceptance remain unverified.

### Prior corrected-helper attempt — 22:31:52–22:32:36 UTC

After the local correction, the operator explicitly authorized **one new attempt**
with USB-only isolation and delegated FLASH, then confirmed holding FLASH with a
single RST pulse. Authorization/preparation are operator assertions, not electrical
inspection: `logs/main-fixed-authorization-20261124-222830-005.json` and
`logs/main-fixed-buttons-20261124-222830-005.json`.

The corrected helper compiled unchanged sources successfully (**exit 0**, 1,306,373 B
program / 65,380 B globals / 1,306,528 B application). Its one native `read-mac`
invocation then returned **exit 2**, **"No serial data received"**. The helper stopped
at **exit 5**, **before read-flash, FLASH confirmation, the second identity check or
upload**. No backup was produced and no standalone erase/all-flash write was requested.
The operator was told to release FLASH. No automatically repeated helper run or
post-upload camera read followed this consumed authorization; the later explicitly
requested no-backup run is recorded above.

- Result and transcripts: `logs/main-fixed-result-20261124-222830-005.json`,
  `logs/main-fixed-run-20261124-222830-005.txt` and
  `logs/flash-20261125-003154-3ad28031.log`.
- A create-new start record consumes this authorization before helper execution;
  the wrapper rejects its reuse. `logs/main-fixed-start-20261124-222830-005.json`.
- Wrapper controls: parsed PS5.1, exact delegated FLASH prompt reaches child scope,
  unexpected prompt rejected, five disabled declarations and corrected-helper/CLI
  hashes match, COM13 present without opening; runner Ruff E9/F exit0.
  `logs/main-fixed-wrapper-check-20261124-222830-005.json`.
- Four fresh artifacts are retained under
  `smart_room_flash/runs/20261125-003154-3ad28031/build`; application SHA-256 remains
  `a70e1bf1e9f7544a576bd7b82eec15aeccd1f851f3d2f1781af1be859e272b70`.

This failure occurred **before any application image was sent**. It cannot establish
main-project runtime behavior or rejection of its code. The earlier successful MAC
read and the latest no-data result are different measurements; the cause of the
USB/boot-mode/reset inconsistency is **unconfirmed**. Further attempts remain paused
pending new diagnostic evidence and explicit authorization, not baud/driver guessing.
The pre-existing camera application was not replaced. Source projects, prior failure
records and the old `dist/` delivery remain preserved; no microSD, BLE provisioning,
IR, relay, mains or actual post-upload camera test was performed.

### Main attempt and local MAC-parser correction — 22:01–22:14 UTC

The one newly authorized helper invocation compiled unchanged main sources, then
completed one native `read-mac` command at **exit 0**. esptool 5.3.1 reported
ESP32-D0WD-V3 and **f0:24:f9:10:80:a4 twice**, before and after starting its RAM
stub. The original helper required exactly one matched row, so it stopped at
**exit 9** as "missing or ambiguous". **Neither read-flash nor upload was invoked**;
no backup was produced or application flash replaced. `identity_match_reported:false`
in the immutable result means the **helper gate** did not pass; it does not deny
the two expected MAC rows in the successful native transcript.

- Attempt: `logs/main-upload-result-20261124-215028-015.json` and
  `logs/main-upload-run-20261124-215028-015.txt`.
- Build: 1,306,373 B program, 65,380 B globals, **1,306,528 B application**,
  SHA-256 `a70e1bf1e9f7544a576bd7b82eec15aeccd1f851f3d2f1781af1be859e272b70`;
  four artifacts preserved under `smart_room_flash/runs/20261125-000140-5c7ea256/build`.
- The preceding coordinated boot-text read captured no recognized ROM lines;
  `logs/main-boot-20261124-215028-015.json` is not Download Mode proof. The later
  successful native handshake is separate evidence. This does not diagnose the
  causes of the three older 0x56/0xA5/0x04 failures.

Only `Get-ChipMac` in `flash_esp32cam.ps1` was changed: normalize valid MAC rows
and require exactly one **distinct address**. Repetition of the same address is
allowed; conflicting/wrong/missing/malformed identities and nonzero native exits
still stop the caller. The matching grammar, expected-MAC comparison, backup,
FLASH prompt, second identity check, source/artifact gates and native lifecycle
are unchanged. This is a local correction, **not an automatically repeated upload**.

| Executed check | Result | Evidence |
|---|---|---|
| Regression red, before implementation | **8 tests, 5 failing assertions including subtests**, 0 errors/skips, exit 1; recorded esptool stdout and repeated/case/label/CRLF controls reached the intended ambiguity error | `logs/macfix-red-20261124-221004-327.{json,txt}` |
| Same regression after minimal fix | **8/8 OK**, 0 errors/skips, exit 0 | `logs/macfix-green-20261124-221004-327.{json,txt}` |
| Final affected controls | **45/45 OK**, 0 failures/errors/skips, 28.412 s: **24 helper**, **9 CMD**, **12 dashboard**; Python 3.14.7 | `logs/macfix-impacted-20261124-221004-327.{json,txt}` |
| Negative mutation control | A first-MAC-only mutant in a disposable helper copy admits a conflicting address and demonstrably fails the rejection oracle; production copy stays unchanged | same final 45-test run |
| Lint | Ruff 0.17.4, isolated/no-cache E9/F, **exit 0** on the three affected test modules and progress server | `logs/macfix-ruff-20261124-221004-327.txt` |
| Scoped change and preservation | Prefix/suffix outside `Get-ChipMac` byte-identical; **40 unchanged files** match, including firmware, originals, CMD, distribution, old failure evidence and four fresh build artifacts | `logs/macfix-preservation-20261124-221004-327.json`, `logs/macfix-helper-diff-20261124-221004-327.txt` |

Original helper (28,004 B) is preserved byte-for-byte as
`logs/flash-helper-before-macfix-20261124-221004-327.ps1`, SHA-256
`048c7d1512b3f94a1f59dcfd45fdbd572b5569a9e3896ebe8ae45747e6845714`.
Corrected working helper (28,307 B) SHA-256:
`ccd14d042945d7c463c404d478dce1754e6156ab6bd08864e41e0106b1c1c683`.
`dist/MANIFEST.json` and its artifact/hash files remain the **prior delivery
snapshot**, whose helper entry does not describe the corrected working file.
No repackaging or new full transfer-manifest verification is claimed.

The 45 checks are scoped inert tests, not a new full app/firmware suite or physical
acceptance. No board serial, radio, external load, microSD, images or tools/driver
changes were involved in this correction. The one-attempt hardware authorization
has been consumed; another guarded run needs fresh operator confirmation, a
matching current identity, complete 4MB backup and all original write gates.
That backup condition belongs to the preceding authorization; the later explicit
no-backup request above supersedes it without changing the other write gates.

## Completed file request — workspace CMD and Arabic upload instructions

The new entry point is **`E:\محمد كريم\UPLOAD_ESP32CAM.cmd`**, with
**`E:\محمد كريم\UPLOAD_INSTRUCTIONS_AR.txt`** next to it. It displays the Arabic
instructions before launching the existing `flash_esp32cam.ps1 -Interactive`
menu. It does not forward caller arguments, opt into review, skip backup, allow
outputs, install tools, bypass PowerShell policy or retry. Missing instructions
or helper stop before helper execution. The original project launcher/helper,
firmware, APK and `dist/` metadata were not modified.

| Executed check | Result / scope | Evidence |
|---|---|---|
| Pre-change archive and preserved-file baseline | previous paused USB record archived byte-for-byte; **23** fixed existing files fingerprinted, no serial | `logs/cmd-delivery-baseline-20261124-200206-506.json` |
| Required-artifact red stage | **8 tests**, **11 failing assertions including subtests**, exit **1**: new CMD/instructions absent before creation | `logs/cmd-entrypoint-red-20261124-200206-506.txt` |
| First post-implementation run | **8 tests**, **6 failures**, exit **1**: inert fixture serialized its empty argument array as null; wrapper behavior was reached successfully | `logs/cmd-entrypoint-green-20261124-200206-506.json` and `.txt` |
| Final entry-point controls | **9/9 OK**, no errors/skips, **3.470 s**, Python **3.14.7**: Arabic display before menu; Arabic/spaced/`&`/`!`/literal-percent paths and unrelated CWD; missing files; exit 0/2/5/6; no caller override forwarding; one invocation only | `logs/cmd-entrypoint-green2-20261124-200206-506.json` and `.txt` |
| Mutation control | a `SkipBackup` mutation in a **disposable launcher copy only** is visible to the inert-helper oracle; delivery CMD unchanged | same final 9-test run |
| Existing impacted helper/dashboard checks | **29/29 OK** (**17** helper + **12** dashboard), no errors/skips, **17.788 s**; inert native/helper/identity controls and owned loopback HTTP only | `logs/cmd-impacted-tests-20261124-200206-506.json` and `.txt` |
| Final test lint and preservation | Ruff **0.17.4**, E9/F, isolated/no-cache, **exit 0**; all **23** baseline files and previous batch archive hashes match | `logs/cmd-quality-preservation-20261124-200206-506.json` |

Only the authored inert test fixture was corrected after its null/empty-array
serialization mismatch, using an explicit unbound-argument count. No production
behavior was changed to accommodate that fixture. These **38 passing affected
checks** are not a new full application suite, firmware compile, actual upload or
camera/phone/appliance test. No serial port, card or load was accessed for this
request. The three prior identity failures and all five physical acceptance gates
remain unresolved. The instructions explicitly say that the new CMD does not
resolve bootloader synchronization and that a failed upload/verify does not prove
no write began.

The previous USB batch is preserved in
`progress/history/usb-flash-paused-20261124-200206-506.json`, SHA-256
`c2bdca3a1ea693b04227d326e657ab9959d2044353462d4e47d78e28d0547bab`.
`progress/state.json` now displays only the CMD/instructions delivery batch;
hardware acceptance is not merged into its completion denominator.

## Paused authorized USB-only flash/test batch

The operator explicitly selected **USB فقط؛ المكونات مفصولة** and **FLASH**,
confirming review of the bare USB-only test setup and delegating the final input.
This is an operator assertion, not an independent photo inspection or electrical
measurement. `logs/upload-authorization-20261124-191158.json` preserves the scope;
`docs/usb-flash-batch.md` records the gates and limitations. No peripheral enabling
or mains-load test is authorized.

| Gate | Current executed evidence |
|---|---|
| Operator review/authorization of isolated USB-only setup | explicit two-question confirmation; all external peripheral flags and HARDWARE_REVIEWED remain false |
| Fresh helper `-CheckOnly` | exit 0, COM13 and tools present, no serial opened; `smart_room_upload_preflight_20261124-210954.txt` |
| Guarded source build | **exit 0**, 1,306,373 B program / 65,380 B globals / 1,306,528 B application image; `logs/flash-20261124-211356-e1d14944.log` |
| Chip identity on COM13 | **failed**: esptool 5.3.1 `read-mac` returned exit 2, `Invalid head of packet (0x56)`; helper exited 5, `logs/upload-result-20261124-191158.json` |
| Separately authorized single ROM identity diagnostic | **failed**: `no-reset`, `no-stub`, `--connect-attempts 1`, baud 460800; native exit **2**, `Invalid head of packet (0xA5)`, wrapper exit **5**; `logs/identity-result-20261124-193858.json` and `logs/identity-log-20261124-193858.txt` |
| Operator-confirmed FLASH-held ROM diagnostic | **failed**, 19:50:19–19:50:21 UTC: same single ROM-only command, `Invalid head of packet (0x04)`, native **2** / wrapper **5**, no resolved MAC; `logs/identity-result-20261124-195019-496.json` |
| Reassessment after three failed identity runs | COM13 registered; PnP **USB-SERIAL CH340 (COM13), OK**. Win32_SerialPort had zero records, a coverage gap, not port absence. No new serial operation; `logs/serial-metadata-20261124-195021.json`, `logs/serial-pnp-metadata-20261124-195021.json`, `logs/diagnostics-reassessment-20261124-195325.json` |
| Post-diagnostic read-only verification | **exit 0**: exact single ROM command and failure checked, previous failure records/archive and helper/config hashes preserved, state valid at **1/4** with five physical gates blocked; `logs/identity-verification-20261124-194133.json`; no additional serial operation |
| Third-diagnostic read-only verification | **exit 0**, Python 3.14.7: `0x04` failure/single invocation and template adaptation verified, prior evidence/source hashes preserved, **1/4** with five physical gates blocked; `logs/identity-verification-20261124-195019-496.json`; no fourth identity attempt |
| 4MB backup and firmware upload | **not attempted**: identity prerequisite failed before backup or final write gate; `logs/upload-run-20261124-191158.txt`; no automatic retry |
| Bounded camera checker fixtures | 6/6 inert controls passed, Ruff E9/F passed, no serial; `smart_room_usb_check_selftest_20261124-191158.txt` |
| Real USB-camera check | **blocked / not run**: no verified upload or backup; no image recording performed |
| Follow-up saved-record/dashboard validation | **12/12 passed**, Python 3.14.7, 0.144 s; `smart_room_usb_flash_blocked_dashboard_20261124-192532.txt` |
| Read-only preservation/outcome check | archive, 5 distribution artifacts, both helpers and 3 manifest source hashes match; current **1/4**, one failed gate and two dependent blocked tasks; `logs/usb-flash-blocked-verification-20261124-192532.json` |
| Existing Review progress tab | HTTP 200; **7/7** record/render checks true, `verified/failed/blocked/blocked`, five physical gates blocked; `logs/usb-flash-blocked-browser-20261124-192707.json` |

The source-built application from this attempt is retained in
`C:\Users\khale\AppData\Local\Temp\opencode\smart_room_flash\runs\20261124-211356-e1d14944\build`,
SHA-256 `a70e1bf1e9f7544a576bd7b82eec15aeccd1f851f3d2f1781af1be859e272b70`.
It was not uploaded or substituted for the existing `dist/` package. The serial
error establishes failed bootloader synchronization, **not** a confirmed cause:
manual download mode/reset behavior, USB signal integrity and power are still
unassessed. No helper, baud setting, driver or firmware change was made in response.

The operator subsequently reported a **4GB microSD card**. Capacity/content and
whether it was present during the failed identity check are unverified. The source
uses internal NVS/Preferences and LittleFS, not SD/SD_MMC; the card is separate
from the **4MB internal flash** backup. No card access, formatting or SD feature
change was performed or authorized. A powered-off temporary card removal and
identification of BOOT/IO0/RST controls are requested before any new serial attempt.

The initial two read-only verifier invocations failed before running the dashboard
suite: first an inline quoted-token assertion affected by PowerShell argument
transport, then an explicit discovery top level incompatible with the existing
non-package `tests/` directory. Those outcomes and the corrected invocation are
retained in the verification JSON; no project/toolchain or hardware change was
made to correct them. These were not additional attempts to communicate with the
ESP32. The status-record SHA-256 at the 19:28:44 UTC follow-up check was
`b478ac1fea110e481aed38517ce02ffd1c5ac7af54eac412209dbecb78ad907a`.
The operator later identified **RST and FLASH** buttons and said **جرب**,
authorizing one subsequent identity-only diagnostic. It ran once at
19:41:32–19:41:33 UTC and failed with `0xA5`; no MAC was resolved. The temporary
ASCII PowerShell wrapper loaded only five previously tested function definitions
from the unchanged, SHA-256-verified helper (not its compile/backup/upload code).
Native work was bounded to 45 seconds and 65,536 output characters and completed
with the private Job cleanup; no reset or flasher stub was requested. The original
failed-upload evidence and installed toolchain were preserved.

`firmware/smart_room/firmware_app.hpp:525` and the preserved original
`../esp32cam_live/esp32cam_live.ino:39` both use JPEG prefix `0xA5 0x5A`.
The observed single `0xA5` byte is consistent with application streaming, **not**
proof of a valid frame or a confirmed wrong boot mode; no extra serial capture
was performed to test that hypothesis. The operator then answered **تم** to the
FLASH-held preparation instructions. That was recorded as an assertion of completion,
not independent physical inspection. A third identity run failed with `0x04` before
any MAC, backup or flash write. Current states are
`verified/failed/blocked/blocked`.

The third run reused the fingerprinted diagnostic template in memory, changing
only the three evidence filename suffixes. The original template/helper were not
modified; the launch metadata records both template and adapted-source SHA-256:
`logs/identity-launch-20261124-195019-496.json`. Native Job cleanup completed.
The clean per-tool transcript is `logs/identity-log-20261124-195019-496.txt`;
the outer encoded PowerShell host also emitted CLIXML information records, which
are not serial/device bytes and did not supply the observed `0x04` error.

Same-version public source was fetched for reference, never executed:
`esptool/loader.py:347` defines ROM baud **115200** and
`esptool/__init__.py:504–509` starts `no-reset` synchronization at
`min(ROM baud, requested baud)`. The later baud increase follows connection.
Thus the log does not show a failed 460800 transfer; no blindly lowered baud,
driver update or firmware change was attempted. This is reference-source coverage,
not an independently analyzed copy of the installed executable. The root cause
remains unconfirmed. Repeated handshakes are paused pending board/base photos and
an explicitly authorized bounded boot-log experiment; no fourth attempt was made.

## Previous verified software batch — safeguards and double-click entry point

This supersedes the old current-batch counters below, not the original transcripts.
The previous software ledger is preserved in
`progress/history/software-20261124.json`. Physical acceptance remains blocked.

| Check run on the current sources (2026-11-24) | Result | Evidence |
|---|---|---|
| Full Python suite, existing Python **3.14.7** | **91/91 OK**, 29.590 s | `smart_room_python314_full_20261124.txt` |
| Board configuration compile regressions | **11 passed** in the full suite, including a disposable GPIO16 policy mutant | `tests/test_board_config.py`; initial red and green transcripts plus `smart_room_safety_green_20261124.txt` |
| Native helper / double-click / chip-identity / source-flag regressions | **17 passed** in the full suite; inert subprocesses and fixtures only | `tests/test_flash_helper.py`; `smart_room_flash_helper_red_20261124.txt`, `smart_room_flash_launcher_red_20261124.txt`, `smart_room_flash_policy_red_20261124.txt`, final green/full logs |
| Focused safety and dashboard run | **40/40 OK**, 23.110 s | `smart_room_safety_green_20261124.txt` |
| C++ controller / protocol / authentication | **26 + 10 + 10 passed**, strict C++17, zero failed | `smart_room_cpp_guarded_20261124-203943/{core,protocol,auth}-run.txt` and `*-compile.txt` |
| Cross-language dispatcher / Dart contract | **18/18 OK**, 10.917 s, **237** actual Dart model/event checks | `smart_room_contract_guarded_20261124.txt` |
| Flutter client / protocol / UI | **47/47 passed** | `smart_room_flutter_guarded_20261124.txt` |
| Native Android adapter, JVM fixtures | **17/17 passed**, no radio | `smart_room_native_guarded_20261124.txt` |
| Direct Dart analyzer | **No issues found!** | `smart_room_dart_guarded_20261124.txt` |
| Ruff E9/F on `host`, `tests`, `tools` | **All checks passed!** | `smart_room_ruff_guarded_20261124.txt` |
| Bridge preflight on Python 3.14 | **exit 0**, no serial or hardware | `smart_room_bridge314_guarded_20261124.txt` |
| Actual helper `-CheckOnly` | **exit 0**, COM13 now present; no port opened or chip identity read | `smart_room_flash_readiness_guarded_20261124.txt` |
| Original four asset hashes and previous five artifact hashes/sizes | **all matched** before packaging | `smart_room_preservation_before_delivery_20261124.json` |
| Helper `-CompileOnly -CleanBuild` | **exit 0**: 1,306,373 B program / 65,380 B globals / 1,306,528 B application image; no serial/upload | `smart_room_guarded_firmware_compile_20261124.txt` |
| Final delivery verification | **all matched**: 5 files, 2 entry points, 3 source hashes, 4 archived binaries and 4 original assets; manifest and hash list agree | `smart_room_final_delivery_verification_20261124.json`, 18:51:45 UTC |
| Final saved-record/dashboard tests | **12/12 OK**, Python 3.14.7, 0.169 s | `smart_room_dashboard_guarded_final_20261124.txt` |
| Live progress page plus page-local unavailable-response fixture | **10/10 checks true**, 4/4 current tasks, all 5 physical gates blocked, 7 blockers, no console errors | `smart_room_dashboard_browser_guarded_final_20261124.json`, 18:55:11 UTC |

### Current guarded delivery

The clean two-worker compile uses ESP32 Arduino 3.3.12, huge_app, with
`HARDWARE_REVIEWED` and all four external peripheral ENABLE flags **false**.
It used a new cache without deleting the earlier cache. Build directory:
`C:\Users\khale\AppData\Local\Temp\opencode\smart_room_flash\runs\20261124-203737-5483dfc6\build`.
The exact source/artifact inventory is
`smart_room_guarded_artifact_inventory_20261124.json`.

| Current file | Bytes | SHA-256 |
|---|---:|---|
| `dist/app-debug.apk` | 180,842,567 | `a9afa88e9847966570b8c34335457cef48e8c608230b73edf1530bb9d9578098` |
| `dist/smart_room.ino.bin` | 1,306,528 | `f1990888988be81bb2594bd1b83fc04ceb9d0d40186abdc00b80a12ffa7b4c3c` |
| `dist/smart_room.ino.bootloader.bin` | 24,992 | `47bbbfca119fe87190f63a67af9d85adff6433bcf3812ec92a9b9c9416a53ad1` |
| `dist/smart_room.ino.partitions.bin` | 3,072 | `aaae2888c5a6a348004b5b436f47abb25ae32e72d9003902955a998eda723edd` |
| `dist/smart_room.ino.merged.bin` | 4,194,304 | `2ab5e0ed98071ee246d636d05b5f3d421c4944bfdb673f161c9c68a60eae715a` |
| `flash_esp32cam.ps1` | 28,004 | `048c7d1512b3f94a1f59dcfd45fdbd572b5569a9e3896ebe8ae45747e6845714` |
| `flash_esp32cam.cmd` | 661 | `5a2e875781534ba12d42eaa1b163b8310d60494027681fe8cb6fbb8824076325` |

The original four firmware binaries and metadata were hash-verified and retained
at `dist/history/software-20261124T034423Z/`; the unchanged APK remains in the
dist root. The historical hashes in §3 below refer to that earlier build, not
the current root package. Per-build hashes differ because build timestamps are
embedded; equal program/memory sizes alone are not functional equivalence proof.

Current configuration SHA-256:
`29e02996a775fe0c667c8c9aa706d499809efa8ffc8091bf2871c1e06aa040c0`;
policy header SHA-256:
`72663285b28e12eb7f902bd2dacf6af6d4ca079770cd6b72850f7bf707374510`.
`dist/MANIFEST.json` records these and the helper hashes, disabled outputs,
unflashed status and blocked hardware review.

The final transfer verifier returned exit 0 and `all_ok:true` for the current
manifest/hash list, helpers, source fields, archived binaries and originals.
The final dashboard suite passed 12/12 against saved-state SHA-256
`f1651cc1f14a6eed36d7447fab49186559b784850e7db97513d3db5fa871e818`.
The existing Review tab loaded HTTP 200, matched the saved record exactly and
rendered **4/4 current-batch tasks** separately from the previous software
milestone and **5 blocked physical gates**. A page-local unavailable-response
fixture showed an explicit stale/offline status without changing counts/tasks;
the original fetch was restored and the page returned online. This was a browser
fixture, not an interruption of the running server. The full-page screenshot
path is retained in the browser JSON report. No operations targeted the preserved
viewer tab; its existing connection-refused state was not repaired or reopened.
Compiling and copying files did not flash the board or approve the user's wiring.

The earlier Python 3.12 run's five `pyserial` errors were an interpreter selection
problem. The installed Python 3.14.7 has pyserial 3.5, NumPy 2.5.4 and OpenCV
5.0.0.93; the full detector-reuse suite passed without any installation. The
native adapter still emits one non-blocking warning at `RoomBle.kt:178`.

`flash_esp32cam.cmd` was exercised unchanged in an owned Arabic/spaced/`&` path
with an inert sibling helper. The real helper was exercised for menu cancellation,
rejected review, default refusal, invalid/mixed modes, readiness and compile-only.
No `-ConfirmHardwareReviewed` invocation on a real port was made in this batch.
Identity and write branches were not tested against a physical device.

The source and pin-policy tests observed real red failures before fixes:
unsafe pin configurations compiled; native quoting lost a literal quote; stderr
prevented preserving an exit 7; no deadline existed; and a nonliteral duplicate
flag could be misread as false. Green tests now cover these cases, overflow,
owned process-job cleanup (also when the parent exits), wrong/ambiguous/failed
chip identity, disabled flags, and a known-negative GPIO16 mutant. Tests are not
a full security audit, C++ preprocessor, electrical review or hardware sandbox.

### Commands used for the current batch

From the project root, using installed tools and existing dependencies:

```powershell
& 'C:\Users\khale\AppData\Local\Programs\Python\Python314\python.exe' -m unittest discover -s tests -v
& 'C:\Users\khale\AppData\Local\Programs\Python\Python314\python.exe' tools/run_contract_tests.py
& 'C:\Users\khale\AppData\Local\Programs\Python\Python314\python.exe' tools/run_native_android_tests.py
& 'C:\Users\khale\AppData\Local\Programs\Python\Python314\python.exe' -m host.bridge --check
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File .\flash_esp32cam.ps1 -CheckOnly
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File .\flash_esp32cam.ps1 -CompileOnly -CleanBuild
& 'C:\Users\khale\AppData\Local\OpenCodeEngineering\venvs\quality\Scripts\ruff.exe' check --select E9,F host tests tools
```

The three C++ suites used `C:\msys64\mingw64\bin\g++.exe` with
`-std=c++17 -Wall -Wextra -Werror -pedantic`; their executables and compiler/run
logs are in `smart_room_cpp_guarded_20261124-203943/`.

From `app/`, with project-root `PUB_CACHE` and `GRADLE_USER_HOME`:

```powershell
C:\src\flutter\bin\flutter.bat test --no-pub --reporter expanded
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze
```

The APK was not rebuilt in this batch: the unchanged adapter/app sources passed
their tests again, and the previously delivered APK's bytes/hash were verified.
No install, toolchain upgrade, policy bypass, serial open or flash was required.

## 1. Previous package results — historical snapshot

| Check | Result | Evidence |
|---|---|---|
| C++ controller/policy (`tests/core_tests.cpp`) | **26 passed, 0 failed** | `smart_room_core_review_20261124.txt` |
| C++ framing/CRC/IR slots (`tests/protocol_tests.cpp`) | **10 passed, 0 failed** | `smart_room_protocol_review_20261124.txt` |
| C++ auth/flat JSON/Unicode (`tests/auth_tests.cpp`) | **10 passed, 0 failed** | `smart_room_auth_unicode_green_20261124.txt` |
| Cross-language contract (`tools/run_contract_tests.py`) | **18 tests OK**, 8.150 s | `smart_room_cross_contract_green_20261124.txt` |
| Dart event/model checks inside the contract suite | **227 valid + 10 negative = 237 checks** | same transcript |
| Native Android BLE adapter (JVM fixtures) | **17 passed, 0 failed** | `smart_room_native_ble_callback_green_20261124.txt` |
| Flutter client/protocol/widget tests | **47 passed**, all tests passed | `smart_room_app_cleanup_unicode_green_20261124.txt` |
| `dart analyze` (app, including contract fixture) | **No issues found!** | `smart_room_dart_final_analyze_20261124.txt` |
| Python host/bridge/dashboard/detector | **63 tests: 58 passed, 5 errors**; all 5 errors confined to `tests/test_detector_reuse.py` and caused by the missing `pyserial` module/metadata in the current `C:\Python312` interpreter; dashboard subset re-run separately: **12/12 OK** | latest full run 2026-11-24 (`python -m unittest discover -s tests`, 1.421 s); `python -m unittest tests.test_progress_dashboard` (12/12 OK); ruff E9/F after the test fix: **All checks passed!** |
| Ruff E9/F | **All checks passed!** (latest recorded run; not re-run after docs) | `smart_room_ruff_final_20261124.txt` |
| ESP32 firmware compile | **success**, 1,306,373 B program / 65,380 B globals | `smart_room_firmware_integrated_final_20261124.txt` |
| Android debug APK | **built**, 180,842,567 B | `smart_room_android_native_final_20261124.txt` |
| Bridge preflight (`--check`) | **exit 0**, `serial_opened:false`, `hardware_tested:false` | `smart_room_bridge_preflight_final_20261124.txt`; re-run below |

Historically, the Python 63-test suite was re-run after the documentation and progress-state
updates and passed in 2.027 s; an earlier full run passed in 1.911 s. The
47-test Flutter run and the C++/contract/native runs remain the latest recorded
runs in their transcripts. Documentation-only changes do not alter firmware or
app source. The standalone `ruff` executable used for the green E9/F run is not
on `PATH` in the current shell, so Ruff was not re-run after the docs; the
recorded result still refers to the unchanged Python sources.

That batch's full Python run (63 tests) was followed by a correction to the saved
progress record expectations in `tests/test_progress_dashboard.py` (9 task IDs,
5 milestones) and a re-run of that module (12/12 OK, 0.123 s). The final full run
after the correction reported 58 passes and 5 errors, all in
`tests/test_detector_reuse.py` and all failing on the missing `pyserial`
module/metadata in the active `C:\Python312` interpreter; no failure remains from
the record/dashboard changes. That run took 1.421 s; the installed Python 3.14
had not yet been re-tested in that follow-up. The current 91-test run above
resolves the interpreter issue without installing anything.

## 2. Commands actually used — previous snapshot

### C++ suites

```powershell
g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/core_tests.cpp -o <temp>\core_tests.exe
g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/protocol_tests.cpp -o <temp>\protocol_tests.exe
g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/auth_tests.cpp -o <temp>\auth_tests.exe
& <temp>\core_tests.exe
& <temp>\protocol_tests.exe
& <temp>\auth_tests.exe
```

The executables and their transcripts are retained as
`smart_room_core_review.exe`, `smart_room_protocol_review.exe` and
`smart_room_auth_unicode_green.exe`. Each prints a `RESULT n passed, 0 failed`
line.

### Cross-language contract

```powershell
C:\Users\khale\AppData\Local\Programs\Python\Python314\python.exe tools\run_contract_tests.py
```

It compiles an **unmodified slice** of the real dispatcher (`void command` and
`void usbCommand` from `firmware_app.hpp`) against inert I/O fixtures with the
real ArduinoJson headers, `auth_core`, `command_fields`, `wire`, `room_core`, and
the real Dart encoders from `app/tool/contract_fixture.dart`.

- actual `firmware_app.hpp` SHA-256:
  `58d51dbd92b3546c6ca67b07b91359f6708fede37b8e04e7c126869222cfd37c`
- extracted dispatcher slice SHA-256:
  `e5a76d9d031ed9ebcc1d0db25bde6c3b74ef2c348e6bfccc38dc4287a817e507`
- includes a disposable session-binding mutant that admits a known-negative
  request; the negative control fails detection if the mutant leaks through.

### Native Android adapter

```powershell
C:\Users\khale\AppData\Local\Programs\Python\Python314\python.exe tools\run_native_android_tests.py
```

Compiles the real `RoomBle.kt` with cached Kotlin/JDK artifacts only. No Android
device, emulator or radio was used. Result: 17/17 JVM tests. One non-blocking
Kotlin warning remains at `RoomBle.kt:178` (unnecessary safe call on
`ScanResult.scanRecord`); it does not fail the suite.

### Flutter / Dart

```powershell
$env:PUB_CACHE="$PWD\.pub-cache"
$env:GRADLE_USER_HOME="$PWD\.gradle-user-home"
$env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze
C:\src\flutter\bin\flutter.bat test
C:\src\flutter\bin\flutter.bat build apk --debug --no-pub `
  -PsdkDownload=false -Porg.gradle.jvmargs=-Xmx2G -Porg.gradle.workers.max=2
```

`flutter analyze --no-pub` is not used in this environment: it crashes with
`FormatException: Unexpected end of input`. The direct Dart analyzer is the
accepted check and reports no issues. The Gradle build emitted only JDK
native-access warnings and completed in 77.8 s.

### Python, Ruff, bridge

```powershell
python -m unittest discover -s tests -v          # 63 tests, OK
ruff check --select E9,F host tests tools        # All checks passed!
python -m host.bridge --check                    # exit 0, no serial
```

`ruff` is the installed standalone tool; the Python 3.14 interpreter itself does
not provide the `ruff` module.

### Progress page — historical batch

```powershell
python tools\progress_server.py --port 8799
```

At that historical check, the owned loopback server ran as PID 14188. `GET /state.json` returned
HTTP 200; the existing tab `tab_bfbf650d-98e2-44c7-b483-fa7e3407b638` was
reloaded and rendered **8/8 verified tasks in the current batch**, 4 hardware
milestones, 5 blockers and no console errors. The batch count is explicitly not a
hardware acceptance percentage. The targeted dashboard suite was re-run after the
state update: **12/12 passed**.

The preserved viewer tab `tab_885abdc2-b7c9-4d60-b1f1-7a0bd4343434`
(`http://127.0.0.1:8081/`) was left untouched; its server is still unavailable and
`COM13` was not reopened.

Re-verified while writing this ledger:

```json
{
  "python": "3.14.7",
  "opencv_python": "5.0.0.93",
  "numpy": "2.5.4",
  "pyserial": "3.5",
  "people_sha256": "4b4a9d317876ec630a02864ca005b353601b34f3c6e0279023f6f8db1751b19f",
  "model_sha256": "c5c2d13e59ae883e6af3b45daea64af4833a4951c92d116ec270d9ddbe998063",
  "serial_opened": false,
  "hardware_tested": false
}
```

### Firmware

```powershell
arduino-cli compile --fqbn esp32:esp32:esp32cam:PartitionScheme=huge_app `
  --output-dir <temp>\out firmware/smart_room
```

- core: ESP32 Arduino 3.3.12, `PartitionScheme=huge_app`
- sketch: 1,306,373 bytes (41% of 3,145,728)
- globals: 65,380 bytes (19% of 327,680), 262,300 bytes free
- output files: `smart_room.ino.bin`, `.bootloader.bin`, `.partitions.bin`,
  `.merged.bin`, `.elf`, `.map`
- no upload; outputs disabled in `board_config.h`

The compile was re-run after the dispatcher sequencing fix; the final log is
`smart_room_firmware_integrated_final_20261124.txt`. The extracted build directory
is `smart_room_firmware_final_20261124T013953Z`.

### Flash helper — historical version, non-writing paths only

`flash_esp32cam.ps1` is the single flashing entry point. It was syntax-checked
and exercised only where it cannot write:

| Invocation | Host exit | Observed |
|---|---:|---|
| `-CheckOnly` | 3 | arduino-cli 1.5.1, board/core 3.3.12 and esptool 5.3.1 found; `COM13` absent, so "NOT READY" |
| `-CompileOnly -CleanBuild` | 0 | 1,306,373 program bytes, 65,380 globals, `smart_room.ino.bin` 1,306,528 bytes |
| no arguments | 2 | refused before any port use: hardware review not confirmed |
| `-ConfirmHardwareReviewed` | 3 | stopped before compiling: `COM13` not present |

The helper builds in `%TEMP%\opencode\smart_room_flash`, keeps the Arduino object
cache out of the Arabic project path, logs to `logs\`, and on a real run backs up
the whole 4 MB flash to `backups\` before the typed `FLASH` gate. No upload and no
serial port open occurred in any run above.

A clean rebuild at 06:52 embedded its build time, so its `smart_room.ino.bin`
SHA-256 (`bea3c2581e20ceb82db0229dcdcf1ab3c9a23cb1c87dbca6022ea749d37a4a71`)
differs from the delivered
`bdda158d241dde6f980607207c803a6b597a975ef1d6b4d1026a2bdd5812dae7` although the
size and compiler figures match. Firmware image hashes are per build; compare
size and memory figures, and use the hash the helper prints for the image it
actually writes.

## 3. Artifact hashes — previous package snapshot

### Android APK

| Field | Value |
|---|---|
| Path | `app/build/app/outputs/flutter-apk/app-debug.apk` |
| Bytes | 180,842,567 |
| Modified (UTC) | 2026-11-24T01:30:38.4033191Z |
| SHA-256 | `a9afa88e9847966570b8c34335457cef48e8c608230b73edf1530bb9d9578098` |
| Type | debug build, not signed for production |

### Firmware binaries

| File | Bytes | SHA-256 |
|---|---:|---|
| `smart_room.ino.bin` | 1,306,528 | `bdda158d241dde6f980607207c803a6b597a975ef1d6b4d1026a2bdd5812dae7` |
| `smart_room.ino.bootloader.bin` | 24,992 | `47bbbfca119fe87190f63a67af9d85adff6433bcf3812ec92a9b9c9416a53ad1` |
| `smart_room.ino.partitions.bin` | 3,072 | `aaae2888c5a6a348004b5b436f47abb25ae32e72d9003902955a998eda723edd` |
| `smart_room.ino.merged.bin` | 4,194,304 | `a7f1bdf846571f7bd3e33bc10fb8f6848802437c8ab5e98f307821affc1ade7d` |
| `smart_room.ino.elf` | 15,679,140 | `54fd19c93cf842b168f8a930983883a8898a291d332ccfca3f9a55b9130d71dc` |
| `smart_room.ino.map` | 22,011,250 | `68dfe7190a0fd5c34675072f3dd1343cd1d8a3004e73fc5660182429151c77a0` |

The `.bin` sizes differ from the “sketch uses” figure because the reported number
is the linked program size, not the padded image length.

### Preserved original project

| File | Bytes | SHA-256 |
|---|---:|---|
| `esp32cam_live/esp32cam_live.ino` | 4,234 | `6e19aace68cac56429ca6983c88d62b69a8921df626403cb8280e5741f1297d7` |
| `esp32cam_live/viewer.py` | 25,386 | `2f0c39025034fc3cfbfcf60835c5857b58d80f4203978a2e69252ef3f1740b8b` |
| `esp32cam_live/people.py` | 12,935 | `4b4a9d317876ec630a02864ca005b353601b34f3c6e0279023f6f8db1751b19f` |
| `esp32cam_live/models/yolox_s.onnx` | 35,858,002 | `c5c2d13e59ae883e6af3b45daea64af4833a4951c92d116ec270d9ddbe998063` |

These hashes were re-read from disk during this work. They identify the rollback
artifacts; they are not a claim that the old viewer is currently running.

### Flash helper script — historical version

| File | Bytes | SHA-256 |
|---|---:|---|
| `flash_esp32cam.ps1` | 14,892 | `69238e3f51176bf6ceaf84e104f0338f8d0997891ce1ca149c1ecb698b3d2871` |

This is the exact version that produced the check/compile/refusal results above.
Later edits changed this hash; the current helper's hash and non-writing checks
are recorded in the current-batch section above.

## 4. What the tests establish

- The pure controller distinguishes unknown/stale from zero, requires continuous
  fresh zero through the empty grace period, debounces band changes, bounds manual
  leases, preserves last requested outputs on loss of vision, rate-limits IR and
  handles `millis()` wraparound.
- The command parser rejects duplicate/escaped/nested/trailing input, NUL
  truncation, lone surrogates, oversized documents and non-scalar values.
- The authentication gate binds a proof to device/session/challenge, expires it in
  30 s, consumes it on failure and compares in constant time.
- The actual dispatcher accepts only owner-authorized controls, refuses disabled
  hardware outputs instead of claiming success, requires complete learned AC
  states, stores before acknowledging a claim and refuses claim outside the
  display-backed window.
- The Dart encoders and Python host agree with the compiled dispatcher on envelopes,
  event bounds, HMAC and the local-action success codes.
- The native adapter gates permissions, detaches notification bytes, rejects
  malformed/oversized/wrong-epoch writes and tears down stale callbacks.

## 5. Pre-upload limitations snapshot

These describe the previous software batch. Current USB upload/camera evidence
above supersedes only the corresponding flash/camera items after checks pass;
peripheral, mains, phone, AC and real-room accuracy gates remain separate.

1. **No hardware was tested.** No flash, no relay, no IR LED/receiver, no OLED, no
   level converter, no 2N2222/555 circuit. Pin assumptions and polarity remain
   hypotheses pending photographs and measurements.
2. **No real BLE.** No pairing, passkey entry, bonding, owner authentication,
   second-phone rejection or radio range test was performed.
3. **No real AC.** No appliance waveform was captured, no carrier was measured, no
   command was replayed to an AC, and no appliance state was confirmed.
4. **No real-room accuracy.** Counting was not evaluated in the target room;
   software fixtures and a public blank image are not an accuracy measurement.
5. **No mains safety.** The prototype board and jumpers are not a mains-rated
    assembly. No 220/230 V connection was made or approved by the assistant. The
    user's reported wiring has not been inspected and contains a critical L-N
    short hazard; software-disabled outputs are not electrical isolation.
6. **Dependency coverage is partial.** The resolved inventory is in
   `docs/resolved-dependency-inventory.md`. Only earlier direct-pin/POM advisory
   queries exist; there was no new online advisory query and no full-graph audit.
7. **No production security claims.** Secure boot, flash encryption, signed
   releases, anti-tamper and physical enclosure security are not implemented.
8. **Debug artifacts.** The APK is a debug build; the firmware is an unflashed
   compile output.

## 6. Reproducing the checks

Follow `README.md` §“بناء وتشغيل”. The short version:

```powershell
g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/core_tests.cpp -o "$env:LOCALAPPDATA\Temp\opencode\core_tests.exe"
g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/protocol_tests.cpp -o "$env:LOCALAPPDATA\Temp\opencode\protocol_tests.exe"
g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/auth_tests.cpp -o "$env:LOCALAPPDATA\Temp\opencode\auth_tests.exe"
py -3.14 -m unittest discover -s tests -v
py -3.14 tools\run_contract_tests.py
py -3.14 tools\run_native_android_tests.py
& "$env:LOCALAPPDATA\OpenCodeEngineering\venvs\quality\Scripts\ruff.exe" check --select E9,F host tests tools
py -3.14 -m host.bridge --check
powershell -NoProfile -File .\flash_esp32cam.ps1 -CompileOnly
```

Do not add `--upload`, `--allow-serial`, or a mains load without the separate
hardware review gate.

## 7. Public repository publication — 2026-11-25

The source snapshot was committed and pushed to
`https://github.com/khaled6747/esp32-cam` without a board backup and without a
new upload attempt.

- Local repository: `esp32cam_smart_room`, branch `main`, root commit
  `313287be97adfaf4f952bb3fb1e2999d841bd6d4`.
- Published content: **115 files, 12,837 insertions, 0.72 MB**. Build caches,
  Gradle/Pub caches, `dist/`, `logs/`, board backups and local paths were
  excluded; `git status` was clean after the commit.
- Remote check: `git ls-remote --heads origin` and the GitHub commits API both
  report `313287be97adfaf4f952bb3fb1e2999d841bd6d4` on `refs/heads/main`; the
  API reports 115 changed files and 152 tree entries.
- Secret scan: the approved Gitleaks 8.30.1 launcher scanned the exact exported
  snapshot, **0 findings, 0 errors, 75/75 selected text files**. Scope is
  working-tree text only, decode depth 2; no Git history, archives or binaries.
  This is not proof that the content is secret-free beyond that scope.
- Issues opened (all `open` at creation): #1 `0x73` upload failure, #2 disabled
  OLED/IR/relay and BLE pairing, #3 microSD pin conflicts, #4 unmeasured room
  counting accuracy, #5 mains/pin safety, #6 unmeasured PSRAM/memory/LittleFS,
  #7 partial dependency advisory coverage.
- `docs/known-issues.md` links each issue; `README.md` lists them.

Publication is not runtime acceptance. The five hardware gates and the blocked
upload remain exactly as described in sections 5 and 6 above.

