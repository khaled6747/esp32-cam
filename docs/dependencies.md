# Dependency and build boundary

Existing, unchanged toolchains: Arduino CLI 1.5.1, ESP32 Arduino core 3.3.12,
IRremoteESP8266 2.9.0, ArduinoJson 7.4.3, Flutter 3.47.8 / Dart 3.13.7, and the
existing Python 3.14/OpenCV/NumPy/pyserial runtime. No core/SDK upgrade is requested.

Current direct Pub pins (official pub.dev metadata inspected before resolution):

| Package | Exact version | Published archive SHA-256 |
|---|---|---|
| flutter_secure_storage | 11.2.0 | `d4e1fb6b2cb524868929e78dc0282fa000554b22060fb53789dc481c9fc95bb8` |
| crypto | 3.0.8 | `e3626ae6270383c9e3a549f34c9e4cd26c09ae6a9adaab2bf4737a00340efdc4` |

These packages use BSD-style licenses. Official repository license text was
inspected; exact resolved archive licenses and `pubspec.lock` must be retained and
checked after resolution. App Settings exposes Flutter's license registry.

The initially resolved `flutter_reactive_ble 5.6.0` was **rejected before use**.
Its Android implementation requires compileSdk/targetSdk 37 (installed SDKs are
35/36), and declares `protobuf-javalite 3.25.3`, affected by the HIGH advisory
`GHSA-735f-pc8j-v9w8 / CVE-2024-7254`. A public OSV query at
`2026-11-23T23:48:30.598Z` confirmed that entry. Version 5.5.0 was inspected from a
SHA-256-verified inert archive; it also declares affected Protobuf 3.21.9 and
older Android build plugins. Neither library is used by the app. The local
Android BLE adapter has no external Bluetooth dependency. See ADR 002. Unused
downloaded archives are not build acceptance or runtime dependencies.

A direct-pin OSV query of public Pub names/versions at
`2026-11-23T23:34:32.434Z` returned no advisory entries for these three pins.
**This is not full dependency/security acceptance**: transitive Pub pins and
native Android/Maven/Gradle/SDK dependencies are separate coverage. No camera,
private source, keys or credentials were sent to an advisory service.

Pub downloads use this project's `.pub-cache`, not a global package installation.
Builds use installed SDK/core versions. `flutter pub upgrade`, Flutter/core
upgrades and unreviewed installers are not part of the task. Debug APKs are
development artifacts, not a signed production release or a commercial license
compliance certification. Native dependency/build coverage and remaining gates
are recorded in final evidence; unknown coverage is not labeled clean.

The exact resolved inventory is now recorded in
`docs/resolved-dependency-inventory.md`: **59 Pub packages** from
`app/pubspec.lock` and **305 Maven coordinates** present in the project-local
Gradle cache, with the license declaration found for each coordinate. That file
also lists the firmware/toolchain components. It is an inventory only: the Maven
cache mixes build tooling with APK runtime code, license texts were not legally
reviewed, and no new online advisory query was authorized. The previous
direct-pin/POM results below remain the only advisory evidence.

The inspected `tink-android 1.23.0` POM declares annotation-jvm 1.8.2,
jsr305 3.0.2, gson 2.13.2 and error_prone_annotations 2.41.0. Public OSV
queries for those five exact Maven pairs at `2026-11-24T00:20:01.893Z`
returned no entries. This is declared-POM coverage, not a resolved Android graph.
JNI's CMake source/Gradle files were inspected; its CMake >=3.10 requirement is
configured to use already installed 3.22.1. SDK auto-download is disabled,
Gradle memory/workers are bounded to preserve the running viewer, and the wrapper
uses the official Gradle 9.3.1 distribution SHA-256. No dependency source is patched.
