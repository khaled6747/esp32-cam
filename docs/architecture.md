# ADR 001 — PC-assisted vision, device-owned control

Status: accepted for this prototype through the user's answers on 2026-11-24.

## Context / decision

The existing AI-Thinker ESP32-CAM streams VGA JPEG at 921600 baud to an existing
local YOLOX-S model. The user accepts retaining that laptop for the first version.
The new firmware, host bridge and Android Flutter app live in a separate sibling
project. No board flash or old-project replacement is part of this batch.

The laptop supplies only timestamped, sequenced, expiring occupancy. The ESP32
owns the rule engine and the hardware state; BLE controls do not rely on a cloud
server. The existing JPEG framing stays compatible. A second, CRC-protected
packet type carries bounded JSON, never JPEG through BLE.

Alternatives rejected for this version:

- Claiming comparable YOLOX inference on the current ESP32-CAM: unverified and
  incompatible with the current model/resource assumptions.
- Inferring sleep from no motion: a hidden, seated or occluded awake person is a
  valid counterexample. Sleep is explicit and timed.
- Counting retained tracks: tracks are not evidence of current visible people.
- Treating vision failure as zero: could undesirably extinguish a occupied room.
- Blindly generating AC temperatures from one recorded button: many AC remotes
  transmit a complete state and checksum, not independent increment commands.
- BLE name hiding as access control: advertisements remain observable in generic
  scanners. UUID filtering is UX, not authentication.

## Control / ownership

Default bands are 1–2, 3–4, and 5+ visible people. These select complete learned
states, conventionally 26°C/Auto, 24°C/Auto and 23°C/High. They are configurable
comfort heuristics, **not a thermal model**. There is no measured room temperature
or AC/relay feedback sensor among the confirmed components.

Fresh zero must remain continuous for 120 seconds by default before selecting a
learned sleep scene and requesting lights off. Unknown/stale camera data breaks
the grace timer and freezes automatic changes. Band changes debounce for five
seconds; IR sends are rate-limited. Manual and explicit sleep overrides have
bounded leases. On reboot, outputs start disabled/inactive and vision is unknown.

One BLE link is admitted; requests from a rejected connection/session cannot
reach the controller. BLE Secure Connections + MITM/passkey require a functioning
OLED for first provisioning. The paired owner additionally authenticates with a
fresh HMAC-SHA256 challenge. All automatic/manual actions are subject to hardware
enable flags and learned-slot availability. A timed-out acknowledgment is unknown,
not a successful hardware operation.

## Verification / consequences

- Native tests cover the pure C++ rule engine, clocks, exclusive link and replay
  sequence independently of Arduino/Flutter.
- Python and Dart validate the wire contract, bounds and split-frame assembly.
- Compile/analyze/tests establish software behavior only. Power integrity,
  actual BLE pairing, IR carrier/capture completeness, AC interpretation and
  lighting hardware need independent bench tests.
- The new firmware uses the existing core and installed IR library. BLE uses the
  bundled native IDF APIs with fixed attributes and queues: the inspected C++ BLE
  wrapper grows prepare-write accumulation without an application bound. The new
  endpoint rejects prepared/long writes and nonzero offsets instead of using that
  path; it targets responses to the admitted connection ID, not all peers.
  The chosen
  3 MiB app partition leaves 896 KiB for LittleFS; recorded IR data uses fixed
  bounded slot files. Firmware and dependencies are not proof of a secure product.
- Old firmware/build/model/viewer files remain rollback artifacts. Flashing later
  is an explicit gate. Hardware output enabling requires an approved pin/voltage
  configuration; no code flag can compensate for unsafe physical wiring.
