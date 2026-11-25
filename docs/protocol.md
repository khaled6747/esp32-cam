# Wire protocol — BLE control and USB bridge

Status: implemented and exercised by the test suites described in `EVIDENCE.md`.
The appliance-side meaning of every field is owned by the firmware; this document
describes the envelopes that are actually accepted, not a future API.

## 1. Transport matrix

| Path | Direction | Purpose | Framing |
|---|---|---|---|
| BLE command characteristic | phone → ESP32 | authenticated commands | UTF-8 JSON + `\n`, one message per write |
| BLE event characteristic | ESP32 → phone | notifications, chunked | UTF-8 JSON, `\n`-terminated stream |
| USB serial TX (device → laptop) | ESP32 → laptop | VGA JPEG stream + JSON events | binary magic packets |
| USB serial RX (laptop → device) | laptop → ESP32 | occupancy and local actions | binary magic packets |

Both paths carry the same JSON **envelope version 1**. Neither path accepts
nested command values, duplicate keys, non-finite numbers or unbounded strings.

## 2. BLE GATT

Service and characteristics use a 128-bit UUID derived from the same base:

- service `6f875ca0-24ad-47e0-a36f-50f38e4d9301`
- command `6f875ca0-24ad-47e0-a36f-50f38e4d9302` (write, encrypted + MITM)
- event `6f875ca0-24ad-47e0-a36f-50f38e4d9303` (read/notify, encrypted + MITM)
- CCCD on the event characteristic (encrypted read/write)

Firmware facts that clients must respect:

- Advertisements are filtered by service UUID for app discovery. The device name
  `SmartRoom` is in the **scan response**, so generic scanners can still observe
  it. UUID filtering is discovery UX, not a secret.
- Advertising stops as soon as any link is accepted. A second connection is
  disconnected immediately; there is no multi-phone mode.
- The device requests a 247-byte ATT MTU but accepts the negotiated value.
  A command write is limited to **200 bytes** by the attribute definition, and
  writes are only accepted from the admitted, encrypted, MITM-authenticated link.
- Prepared/long writes, nonzero write offsets and Execute Write are rejected with
  `ESP_GATT_REQ_NOT_SUPPORTED`. There is no prepare queue to overflow.
- Event notifications are chunked to `min(160, MTU - 3)` bytes with a 4 ms
  pacing delay. The last chunk includes `\n`. Reassembly is the client's job.
- Each event document is at most **4095 bytes** before the newline is added.
- An unauthenticated link is disconnected 90 seconds after connection, and any
  failed `auth` disconnects immediately.

When a link drops, the firmware resets the session gate, the request sequence,
the line assembler, learning and the current generation. A reconnect always starts
from `hello`; nothing from the previous link is resumable.

## 3. Command envelope (BLE)

```json
{"v":1,"id":17,"op":"lights","session":"<32 hex>","on":true,"lease_ms":600000}
```

Rules enforced before dispatch:

- `v` must be the integer `1`.
- `id` is an integer from 1 to 2147483647 and must be strictly greater than every
  previously accepted `id` on this link. Reuse returns `replayed_request`.
  `hello` is the first request of a link.
- `op` matches `^[a-z_]{1,24}$`; only the operations in §5 exist.
- The whole document is a **flat** object: scalar string, boolean or integer
  values only, at most 32 keys, at most 768 UTF-8 bytes.
- Keys match `^[a-z][a-z0-9_]{0,23}$`. `v`, `id`, `op` and `session` are reserved.
  Duplicate keys, escaped keys, `\u0000`, lone surrogates, trailing bytes and
  nesting deeper than 2 are rejected (`invalid_json` / `invalid_envelope`).
- Every operation re-validates its exact field set against the typed schema.
  An unknown field is `invalid_fields` (or `unknown_operation_or_fields`).
- `session` is present on every command after `hello` and must equal the session
  returned by `hello`; `hello` itself must not carry `session`.

The phone sends a command as one or more GATT writes, each at most the 200-byte
attribute limit. The firmware reassembles newline-terminated frames up to 768
bytes, so a command may span writes but must not span connections. The app uses
`min(160, MTU - 3)` chunks, matching the notification side.

## 4. Event envelope

```json
{"v":1,"type":"status","id":17,...}
```

`type` matches `^[a-z_]{1,32}$`. Event types are `hello`, `ack`, `status`,
`profiles`, `learned` and `ir_sent`. Limits: 4095 bytes, depth 6, 256 nodes,
64 keys per object, 32 list items, 1024 UTF-8 bytes per string. The Dart client
and Python bridge independently enforce the same bounds.

`ack` events carry `id`, `ok` and `code`. A USB `ack` additionally echoes
`session`; a BLE `ack` does not.

## 5. BLE operations

### 5.1 `hello`

Request: `{"v":1,"id":N,"op":"hello"}`.

Response: `{"v":1,"type":"hello","id":N,"device":"<12 hex>","session":"<32 hex>",
"challenge":"<64 hex>","owned":true|false,"claim_open":true|false}`.

`hello` creates a fresh 16-byte session and 32-byte challenge and invalidates any
previous authorization on this link. It is rejected if extra fields are present.

### 5.2 `auth` (returning owner)

Request: `{"v":1,"id":N,"op":"auth","session":"<32 hex>","proof":"<64 hex>"}`.
Requires an existing owner key. Success is `ok:true, code:"authenticated"`;
failure is `bad_proof` and an immediate disconnect. The proof is one-use and must
arrive within 30 seconds of `hello`. See `docs/security.md` for the exact HMAC
context.

### 5.3 `claim` (first owner)

Request: `{"v":1,"id":N,"op":"claim","session":"<32 hex>","key":"<64 hex>"}`.
Accepted only when no owner exists, the pairing window is open (OLED present,
≤120 s since boot/`open_pairing`/`reset_owner`), and the `hello` session is
active and no older than 30 s. The 32-byte key is written to NVS **before**
`claimed` is sent; any storage failure returns `storage_failed` and leaves no
owner. A claimed device never re-opens claim through Bluetooth.

### 5.4 Authenticated operations

All of these require a successful `auth` or `claim` on the current link.

| op | Exact fields after `v,id,op,session` | Success code |
|---|---|---|
| `status` | none | event `status` |
| `profiles` | none | event `profiles` |
| `set_mode` | `mode` (`auto`/`manual`/`sleep`), `lease_ms` | `policy_saved` |
| `lights` | `on` (bool), `lease_ms` | `requested_no_feedback` |
| `send_slot` | `slot` 1–16, `lease_ms` | `queued` |
| `ac` | `temperature` 16–30, `fan` 0–3, `mode` 0–4, `power` bool, `sleep` bool, `lease_ms` | `queued` |
| `configure` | all 11 config fields, see §7 | `configuration_saved` |
| `learn_start` | `slot`, `label`, `temperature`, `fan`, `mode`, `power`, `sleep`, `hz` | `press_original_remote` |
| `learn_cancel` | none | `learning_cancelled` |
| `erase_slot` | `slot`, `confirm:true` | `slot_erased` |
| `storage_init` | `confirm:"INIT_UNMOUNTED_STORAGE"` | `storage_ready` |

`lease_ms` is 0 (use the configured default) or 60000–43200000. `auto` ignores the
lease. A manual/sleep lease always expires back to `auto`.

`ac` does not invent a temperature: it searches saved slots for a byte-for-byte
match of `(temperature, fan, mode, power, sleep)` and queues that slot. If no
saved state matches, it returns `unlearned_state` and no IR is transmitted.

`hz` must resolve to one of 36000, 38000, 40000 or 56000 Hz. `label` is a non-empty
UTF-8 string shorter than 48 bytes with no control characters.

## 6. IR slot semantics

A learned slot stores a complete raw waveform, not one button press: carrier
frequency, pulse count (16–1024), and the raw on/off durations in microseconds.
Metadata is `slot`, `label`, `temperature`, `fan`, `mode`, `power`, `sleep`,
`carrier_hz`, `pulse_count`.

- `learn_start` arms the receiver for 30 seconds. The next decodable frame is
  stored; timeout produces a `learned` event with
  `code:"learning_timeout"`. Noise or overflow produces
  `code:"incomplete_or_noise"`. A stored but unverified capture is
  `saved_raw_unverified`; storage failure is `storage_failed`.
- Learning is cancelled by `learn_cancel`, a disconnect, `erase_slot` or timeout.
- A slot is sent at most once per `ir_gap_ms` (default 15 s), and only when the
  selected scene/slot changes or a manual request invalidates the last-sent slot.
- `ir_sent` means the pulses were handed to the IR driver with
  `confirmed_by_ac:false`. It is **not** proof that the appliance changed state.
- If a saved record fails its CRC or validation at send time, no pulses are sent
  and `ir_result` reports `record_corrupt`.
- Slots live on LittleFS as `/irNN.sir` with `/irNN.bak`. Writes go to
  `/ir.pending`, are read back and CRCs verified, then renamed. Mount failure
  never formats storage; `storage_init` is the explicit, confirmed exception.

## 7. Configuration and policy

Default configuration, settable only through `configure`:

| Field | Default | Accepted range |
|---|---|---|
| `ttl_ms` | 2000 | 1000–10000 |
| `empty_ms` | 120000 | 10000–3600000, must exceed `ttl_ms` |
| `settle_ms` | 5000 | 1000–60000 |
| `manual_ms` | 1800000 | 60000–43200000 |
| `ir_gap_ms` | 15000 | 5000–300000 |
| `quiet_max` | 2 | 1–49 |
| `normal_max` | 4 | 2–50, must exceed `quiet_max` |
| `quiet_slot` | 1 | 1–16 |
| `normal_slot` | 2 | 1–16 |
| `busy_slot` | 3 | 1–16 |
| `sleep_slot` | 4 | 1–16 |

Policy behavior that the wire contract exposes:

- A person count of `-1` means unknown/stale. It is never treated as zero.
- Fresh zero must persist continuously for `empty_ms` before lights-off/sleep is
  requested. A stale gap resets that continuity.
- A non-zero band change must persist for `settle_ms` before it is selected.
- In auto mode, unknown data only clears the pending timers; it does not change
  the last requested outputs. `status.presence` is `unknown`.
- On boot the engine has no sensor data, lights are off and mode is `auto`.

## 8. `status` event

Representative fields; `id` is the request id (0 for unsolicited USB status):

`device`, `boot`, `uptime_ms`, `people`, `presence` (`unknown`/`occupied`/`empty`),
`mode`, `scene` (`quiet`/`normal`/`busy`/`sleep`/`manual`/`none`), `lights`,
`override_ms`, `empty_remaining_ms`, `requested_slot`, `sent_slot`, `ir_result`,
`relay_enabled`, `ir_rx_enabled`, `ir_tx_enabled`, `oled_ready`, `camera_ready`,
`storage_ready`, `last_frame`, `last_seq`, `learn_slot`, `stream_errors`,
`ble_tx_errors`, `ble_ready`, `config{...}`.

`ir_result` is one of `learning`, `disabled`, `no_request`, `unlearned`, `queued`,
`pulses_sent_unconfirmed`, or a fault such as `record_corrupt`.

`requested_slot`/`sent_slot` and the OLED say what was asked for and handed to the
driver. They do not report the AC's real state, and there is no room-temperature
sensor.

## 9. USB serial bridge

Baud rate **921600**. Two packet types share the stream:

```
JPEG:    A5 5A | uint32 LE length | uint16 LE CRC-16/CCITT-FALSE | JPEG bytes
CONTROL: C3 3C | uint32 LE length | uint16 LE CRC-16/CCITT-FALSE | JSON bytes
```

Limits: JPEG 4–256000 bytes, JSON control frames 1–768 bytes, JSON event
documents 1–4095 bytes. The camera sends at
most one VGA JPEG every 125 ms. A receiver resynchronizes on the next magic byte
and must reject a length/CRC that exceeds bounds. The assembler resets after 2 s
of an incomplete control frame; the line assembler resets after 5 s.

### 9.1 Device → laptop

- JPEG frames, as above, tagged by the bridge with `device`, `boot` and a
  monotonically increasing local `frame` sequence.
- `{"v":1,"type":"hello","device":"...","boot":"<16 hex>","session":"<32 hex>","ttl_ms":2000}`
- `{"v":1,"type":"status","id":0,...}` every second (id 0, no session).
- `{"v":1,"type":"ack","id":N,"session":"<32 hex>","ok":true|false,"code":"..."}`
  for USB actions and rejected observations.

### 9.2 Laptop → device

`hello` must be first and carries a 16-byte random session:

```json
{"v":1,"op":"hello","session":"<32 hex>"}
```

It resets the device sensor state, the USB request sequence and frame counters.
The reply binds the bridge to `device`, `boot`, `session` and `ttl_ms`.

`observe` is the only occupancy source:

```json
{"v":1,"op":"observe","session":"...","seq":42,"frame":17,"age_ms":340,"people":2}
```

Accepted only when the session matches, `seq` is strictly increasing, `age_ms`
is within the current `ttl_ms`, and `people` is -1 or 0–100. Bounds violations
return `invalid_observation`; reordering/stale/unknown sessions return
`rejected_observation`.

`status` (`{"v":1,"op":"status"}`) requests an unsolicited status event.

Local actions must be explicit and are bound to the live USB session:

| op | Exact fields | Confirm phrase | Success code |
|---|---|---|---|
| `open_pairing` | `v,op,id,session,confirm` | `LOCAL_PAIRING_WINDOW` | `pairing_window_open` |
| `reset_owner` | `v,op,id,session,confirm` | `ERASE_OWNER_AND_BONDS` | `owner_reset_bond_removal_requested` |

`open_pairing` requires a working OLED; it opens a 120-second claim window.
`reset_owner` erases the stored owner, disconnects the BLE link, removes bonds
and re-opens the pairing window. A caller must treat a timeout, a partial write
or a device restart as **unknown**, not as success, and must not automatically
repeat the action. Only the exact success code above counts as success.

## 10. Markers, codes and replay rules

- The firmware’s request sequence is per link/session. A new session starts at 0.
- The USB rule is deliberately stronger for destructive local actions: the
  current handshake session, a request id and the exact confirmation phrase must
  all match, and the success `code` must match exactly.
- A timed-out ack is unknown; the host/phone surfaces it rather than retrying
  silently. `hello`/reconnect is the only way to re-establish certainty.
- Error codes are stable strings; clients must show them as text and must not
  interpret an unknown code as success.

## 11. Compatibility and non-goals

- Envelope version `v:1` only. There is no negotiation and no JSON schema URL.
- No BLE write is a firmware update, filesystem browser or arbitrary command
  channel.
- No cloud transport, no multi-user accounts, no remote internet access.
- No AC feedback or measured temperature exists on this prototype; “requested”
  and “sent” are the strongest claims the protocol can make.

## 12. Verification status

The Dart encoders, Python host framers and the firmware dispatcher are compiled
and tested together by `tools/run_contract_tests.py`; C++, Dart, Python and native
Android suites cover the bounds above. These are software checks only. Real BLE
pairing, real AC waveform completeness, IR range and appliance behavior remain
hardware acceptance gates.
