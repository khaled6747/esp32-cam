# Security model and threat notes

Status: design and software verification for the bench prototype. This document
does not claim a certified or production-secure product. Physical, radio and
supply-chain gates remain open and are listed in §8.

## 1. Assets and trust boundaries

Protected assets:

- the room's appliance control (IR requests and the relay request),
- the learned AC profiles (a complete captured remote state),
- the owner key and the BLE bond,
- occupancy data and the single-phone control channel.

Trust boundaries:

1. **Phone ↔ ESP32 (BLE).** Untrusted radio neighbourhood. Advertisements are
   visible to anyone; only an encrypted, MITM-authenticated, owner-proven link may
   issue commands.
2. **Laptop ↔ ESP32 (USB serial).** Physical/local trust for the occupancy feed.
   The bridge is not a remote service and does not expose a network listener for
   control.
3. **ESP32 ↔ appliance (IR / relay).** Open loop. Pulses sent are not appliance
   confirmation, and mains switching is outside this software's safety claims.
4. **Phone storage.** The owner key must survive an app restart but is held by the
   phone's secure storage, not by plain preferences.

## 2. Discovery and link admission

- The app scans with a service-UUID filter. The advertised service UUID is not a
  secret; the device name is in the scan response and remains visible to generic
  scanners. Discovery filtering is UX, not access control.
- The firmware admits exactly one connection. The first connection wins; any
  second connection is disconnected in the GATT callback. Advertising is stopped
  while a link exists and restarted only when the link is gone.
- Commands are accepted only from the admitted connection id, the current link
  generation, and a link marked secure. A stale queue item from an earlier
  generation is dropped.
- A dropped link resets the session gate, request sequence and line assembler.
  Authorization never survives reconnection.

## 3. BLE pairing and encryption

- Security parameters: LE Secure Connections, MITM required, bonding, 16-byte
  keys, `ESP_IO_CAP_OUT` (display-only), and
  `ESP_BLE_ONLY_ACCEPT_SPECIFIED_AUTH_ENABLE`.
- Each accepted connection generates a fresh six-digit passkey, installs it as the
  static passkey and initiates `ESP_BLE_SEC_ENCRYPT_MITM`.
- The passkey is shown on the OLED. If the OLED is not ready, the passkey event
  disconnects the peer; numeric-comparison confirmation is refused because this
  hardware cannot display and confirm it safely.
- The command characteristic requires encrypted + MITM permission. The event
  characteristic and CCCD also require encryption. A write before security
  completes returns `ESP_GATT_INSUF_AUTHENTICATION`.
- Prepared/long writes, nonzero offsets and Execute Write are rejected. The
  attribute is limited to 200 bytes per write and the command queue is bounded;
  a full queue disconnects rather than silently dropping an authenticated command.

**Consequence:** first provisioning needs a working OLED. A headless board cannot
safely display a passkey and therefore cannot be provisioned through this design.

## 4. Owner authentication

### Enrollment (`claim`)

- A 32-byte owner key is generated on the phone and written to phone secure
  storage **before** the claim command is sent.
- The device accepts `claim` only if no owner exists, NVS is available, the
  session is active, and the OLED-backed pairing window is open (≤120 s since
  boot, `open_pairing` or `reset_owner`).
- The key is persisted to NVS before `claimed` is returned. A write failure
  returns `storage_failed` and does not leave a half-enrolled owner.
- Once an owner exists, Bluetooth `claim` is refused permanently.
- Reset is local: USB session + request id + exact phrase
  `ERASE_OWNER_AND_BONDS`. The device erases the key, drops the BLE link, removes
  bonds and re-opens the pairing window for 120 s.

### Challenge/response (`auth`)

After BLE encryption, `hello` returns a fresh session (16 random bytes) and
challenge (32 random bytes). The phone computes:

```
HMAC-SHA256(owner_key, "smart-room/v1|<device>|<session>|<challenge>")
```

and sends the 64 lowercase hex digits as `proof`.

Firmware rules:

- the context uses the device id, the current session and the current challenge;
- the HMAC is computed with mbedTLS and the expected value is zeroized after use;
- the proof is one-use: a malformed, late or wrong proof consumes it;
- the proof must arrive within 30 s of `hello`;
- comparison is constant-time over 32 bytes (no early exit);
- success authorizes only this session; failure returns `bad_proof` and
  disconnects.

Test vector used by the cross-language suite:

```
key       000102…1f
device    f024f91080a4
session   000102…0f
challenge 101112…2f
context   smart-room/v1|f024f91080a4|000102030405060708090a0b0c0d0e0f|101112…2f
HMAC      453984446bfe4f6b72ee762c6c8ed4ee53a2ad939576d11e3a33a606988bb9a2
```

The actual Dart implementation and an independent Python `hmac` oracle both
produce this value. This verifies the construction, not the secrecy of a real key.

## 5. Command-path defenses

| Threat | Control |
|---|---|
| Unauthenticated control | Encrypted MITM link + owner HMAC before any operation |
| Session confusion / replay across links | Per-link session, generation check, per-session request sequence |
| Replayed request id | `RequestSequence` rejects `id <= last`; USB reset actions use the session + exact success code |
| Duplicate JSON keys | Custom flat-command scanner rejects duplicates before ArduinoJson |
| Parser differential / smuggling | Flat scalar-only commands, ≤768 bytes, ≤32 keys, no escapes in keys, nesting ≤2, trailing bytes rejected |
| Overflow / memory abuse | 4095-byte events, 200-byte writes, 1024-pulse slots, bounded queue, bounded slot file size |
| Prepared-write accumulation | Native IDF attributes; prepared writes and offsets refused |
| Cross-peer responses | Notifications and acks target the admitted connection id only |
| Malformed IR data | Fixed LittleFS paths, header/data CRC-32, pulse-count and duration bounds, atomic pending→rename |
| Stale occupancy as “empty” | Unknown `-1` is distinct from `0`; empty needs continuous fresh zero for `empty_ms` |
| Runaway manual control | Every manual/sleep request carries a bounded lease and expires to auto |
| Destructive local action | USB session + request id + exact phrase + exact success code; no automatic retry |

## 6. Data handling

- NVS namespace `smart_room` stores the owner key and the configuration JSON.
  Learned slots live in LittleFS. There is no logging of the owner key, proof or
  session secret in the inspected firmware.
- The phone stores the owner key through `flutter_secure_storage`; the app does
  not display it or include it in status/log output.
- Status exposes operational state (counts, mode, slots, ready flags, error
  counters). It does not expose occupancy imagery over BLE.
- The USB JPEG stream is the existing camera feed. It is local serial data, not
  encrypted, and must not be exposed to an untrusted network by the host bridge.

## 7. Residual risks specific to this prototype

- **Advertisement metadata.** Device presence and name are observable; there is
  no randomized address or rotation in this firmware.
- **Denial of service.** An attacker within radio range can connect first and
  occupy the single link, or repeatedly force disconnects/pairing prompts. The
  90-second auth timeout bounds an idle link, not a determined jammer.
- **Phone compromise.** Anyone who can read the phone's secure storage and the
  device bond can control the room. There is no second factor beyond the bond and
  passkey.
- **Firmware protection.** Secure boot, flash encryption and signed release
  images are **not implemented or verified** here. Physical flash access can
  extract or replace firmware and NVS.
- **Open-loop actuation.** `ir_sent` and relay requests are not appliance
  feedback. A wrong learned waveform can be transmitted successfully and leave
  the AC in an unintended state. No measured room temperature exists.
- **IR learning is trusted input.** Any IR source captured during the 30-second
  window can become a slot. Labels and metadata are operator assertions, not
  appliance facts.
- **USB path.** Local actions rely on physical access to the serial port and the
  exact phrase. Anyone with that access can reset ownership; this is intentional
  recovery, not remote authorization.
- **Dependency coverage.** Pub/Maven advisory checks are partial; see
  `docs/dependencies.md`. No claim is made that the full resolved graph is free
  of advisories.
- **Debug artifact.** The delivered APK is a debug build, not a signed
  production release.

## 8. Open acceptance gates

These are deliberately unverified and must not be inferred from tests:

1. Real BLE pairing, passkey display, bonding and owner HMAC on a flashed board
   and an Android phone.
2. Single-phone behavior and second-connection rejection on real radios.
3. Real AC waveform capture completeness, carrier accuracy, range and whether the
   appliance reaches the requested state.
4. Relay/opto and IR driver voltages, polarity and current, based on hardware
   photographs and measurements.
5. Mains wiring and enclosure safety. The prototype board and jumpers are not a
   mains-rated assembly.
6. Real-room counting accuracy. Software fixtures and a public blank image do not
   establish field accuracy.
7. Secure boot/flash encryption and any production signing, if required later.

## 9. Verification evidence

- C++ authentication suite (session binding, one-use proof, expiry, constant-time
  comparison, malformed hex) and protocol/framing suites.
- Dart HMAC and event parser suites, including duplicate-key, depth, size and
  Unicode negatives.
- Cross-language contract suite that compiles the real dispatcher slice and
  compares it with the real Dart encoders, including a mutant that admits a
  known-negative request.
- Native Android adapter suite covering permission revocation, notification byte
  detachment and pre-33 GATT gates.

Exact counts, commands, exits and artifact hashes are recorded in `EVIDENCE.md`.
