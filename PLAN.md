# Smart Room — current authorized development batch

## Accepted scope (2026-11-24)

The user chose a **USB-connected laptop for vision in this first version**, an
**Android-first Flutter app**, and **learning complete IR states before knowing
the AC protocol**. Hardware photographs are being supplied. The old
`../esp32cam_live/` application, its firmware/build, running viewer, model and
selected toolchains must remain unchanged.

Build a new, local prototype in this directory. Do not flash the board, connect a
mains load, install global dependencies, change toolchain versions, record/upload
camera images, claim automatic sleep recognition, or claim a working standalone
vision product. Hardware outputs are disabled in the checked-in configuration.

## Architecture

```
Camera -- USB JPEG --> existing local YOLOX on laptop
                       -- bounded, expiring occupancy --> ESP32
Android -- encrypted BLE + owner authentication --> ESP32 controller
ESP32 --> learned complete IR state / relay / I2C OLED
```

One active BLE connection; no advertising while connected. A private service UUID
filters the app's scan, but generic BLE scanners can still see advertisements.
Secure Connections with a displayed passkey plus a per-owner challenge/response
protect controls. The app shows requested/sent AC state, never pretends to have
feedback from the AC or a room-temperature sensor.

The ESP32 owns automation. Unknown/stale vision freezes automatic changes; only
continuous, fresh zero occupancy for a configurable grace period may select an
empty-room scene. Explicit timed sleep mode is not inferred from immobility.
Manual overrides have an explicit lease. Missing IR states must fail visibly.

## File-level tasks and acceptance

| ID | Task / files | Executable gate |
|---|---|---|
| scope | `PLAN.md`, `docs/architecture.md`, `docs/hardware.md` | Review actual pin map, user decisions, equations and unresolved hardware labels |
| rules | `firmware/smart_room/room_core.hpp`, `tests/core_tests.cpp` | Native C++ tests: fresh zero vs unknown, continuous grace, debounce, wraparound, manual leases, missing IR, single connection |
| firmware | `firmware/smart_room/` | Arduino CLI compile against existing ESP32 3.3.12; no upload; bounded commands/storage, default disabled outputs |
| bridge | `host/`, `tests/test_host.py` | Existing Python 3.14 runtime; CRC/parser, source association, TTL/reconnect and serial restrictions; no real serial access |
| app | `app/` | Existing Flutter 3.47.8 / Dart 3.13.7; analyze, unit/widget tests, Android debug APK; no claimed physical BLE test |
| integration | `tests/`, `docs/protocol.md`, `docs/security.md` | Valid/negative protocol controls, authentication/replay, no false acknowledgments, cross-language contract |
| docs | `README.md`, `docs/`, `progress/` | Accurate wiring prerequisites, current-batch ledger, preserved old hashes, visible read-only progress |
| delivery | `EVIDENCE.md`, `dist/` | Inspect actual exit codes/artifacts and record remaining hardware gates |

Example checks, finalized as files become available:

- `g++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/core_tests.cpp -o <owned-temp>/core_tests.exe`
- selected `python.exe -m unittest discover -s tests -v`
- `flutter analyze`, `flutter test`, `flutter build apk --debug`
- `arduino-cli compile --fqbn esp32:esp32:esp32cam:PartitionScheme=huge_app --output-dir <owned-temp>/smart-room-build firmware/smart_room`

BLE, IR and relay/OLED physical validation are **separate project gates**, not
software-test completion. The unconfirmed relay polarity, receiver supply and
OLED controller/pull-ups prevent an approved wiring/flash step at this time.

## Preservation / rollback

All development stays in this new sibling directory; no changes to the running
viewer are needed. Flashing later would replace the old board firmware and needs
an explicit reviewed step. Existing old binaries remain the rollback artifact.
New Pub dependencies will be exact-pinned and locked after source/license review;
no SDK/core upgrade is authorized. Work is inline, without delegation or commits.
