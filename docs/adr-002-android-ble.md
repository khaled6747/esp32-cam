# ADR 002 — project-local Android BLE adapter

Status: implementation decision within the authorized Android-first Flutter
prototype, 2026-11-24; not a user-approved SDK migration.

The proposed `flutter_reactive_ble 5.6.0` Android source requires SDK 37, absent
from this user's installation, and declares vulnerable Protobuf 3.25.3. Older
5.5.0 also declares affected Protobuf and older build plugins. The user's existing
Flutter/Android toolchain must be preserved. The app needs a single GATT link,
filtered scanning, notification subscription and acknowledged, serialized writes.

**Decision:** keep the Flutter UI/domain/protocol in Dart and implement those
Android transport operations with the installed Android SDK's Bluetooth APIs
through one MethodChannel and EventChannel. Use Android's system pairing UI, not
a home-made BLE encryption mechanism. Keep `flutter_secure_storage 11.2.0` for
owner secrets and `crypto 3.0.8` for HMAC. Remove the rejected BLE package from the
manifest and regenerate the lock without upgrading SDKs or cached libraries.

Alternatives: updating SDK 37 would exceed scope; forcing library SDK/Protobuf
versions could mask untested compatibility; an older plugin adds obsolete
dependencies. A larger BLE framework is unnecessary for the single-link contract.

Consequences: fewer runtime dependencies but the project owns Android callback,
queue, cancellation, permission, service-discovery and MTU behavior. Operations
have deadlines; no queued write is retried after an uncertain acknowledgment.
Foreground exit closes the app link and ends scanning. BLE physical tests and
Android permission/pairing behavior remain explicit unperformed bench gates.
Tests cover Dart protocol/client behavior using inert adapters. APK compilation
checks Kotlin/Android API use, not real radio behavior. The adapter is Android-only
by design; iOS support would need a separate reviewed implementation.
