# Resolved dependency inventory

Generated from the project's own lock/caches at the time of writing. This is an
inventory, not a legal opinion and not a complete advisory audit.

## Scope and method

- Pub: every entry in `app/pubspec.lock` (59 packages). Version and
  archive SHA-256 are copied from the lock; license SHA-256 is the package's local
  license file in `.pub-cache` and the marker is its first line, not an SPDX ruling.
- Maven: every `group/artifact/version` directory in the project-local
  `.gradle-user-home/caches/modules-2/files-2.1` cache (305 coordinates).
  This cache also contains Gradle/AGP/Kotlin build tooling, not only code packaged
  in the debug APK; a packaged-runtime subset was not independently established.
- License names are the POM `<licenses><license><name>` declarations when present;
  `undeclared` means no such element was found in the cached POM. A parent POM or
  repository LICENSE may still apply. License texts were not re-verified here.
- Firmware libraries are listed separately; their local license files were read
  directly.
- **Advisory coverage is partial.** No new online OSV/network query was made for
  this inventory. Earlier checks and their timestamps are in `docs/dependencies.md`.

## Pub packages (resolved)

| Package | Version | Dependency | Archive SHA-256 | License SHA-256 | License file first line |
|---|---|---|---|---|---|
| `args` | 2.7.0 | transitive | `d0481093c50b1da8910eb0bb301626d4d8eb7284aa739614d2b394ee09e3ea04` | `dfb09c74e29386cd3e2719f32d4995d59526179753931d31840757c77fbf2791` | Copyright 2013, the Dart project authors. |
| `async` | 2.13.1 | transitive | `e2eb0491ba5ddb6177742d2da23904574082139b07c1e33b8503b9f46f3e1a37` | `ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73` | Copyright 2015, the Dart project authors. |
| `boolean_selector` | 2.1.2 | transitive | `8aab1771e1243a5063b8b0ff68042d67334e3feab9e95b9490f9a6ebf73b42ea` | `b71519245009a3b8f126196a5408ec031e216e8e0d985085958c6543f82a8a2a` | Copyright 2016, the Dart project authors. |
| `characters` | 1.4.1 | transitive | `faf38497bda5ead2a8c7615f4f7939df04333478bf32e4173fcb06d428b5716b` | `0371d1da6a57fb791db29d29b95333429205f51f3cb2eb3a0c12d91838a38744` | Copyright 2019, the Dart project authors. |
| `clock` | 1.1.3 | transitive | `e51d50bca3217c9a9fa2b41a30e4a38971133f5f9ec7a3d57bae095007f1d28e` | `58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd` | Apache License |
| `code_assets` | 1.2.1 | transitive | `bf394f466ba9205f1812a0433b392d6af280f155f56651eda7c18cc32ed493b8` | `21ae23b0b9ff67a2dc75ab085d1e8db8ac548c5faf370af17f28dd2ef3b52b7b` | Copyright 2025, the Dart project authors. |
| `collection` | 1.19.1 | transitive | `2f5709ae4d3d59dd8f7cd309b4e023046b57d8a6c82130785d2b0e5868084e76` | `ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73` | Copyright 2015, the Dart project authors. |
| `crypto` | 3.0.8 | direct main | `e3626ae6270383c9e3a549f34c9e4cd26c09ae6a9adaab2bf4737a00340efdc4` | `ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888` | Copyright 2015, the Dart project authors. |
| `fake_async` | 1.3.3 | transitive | `5368f224a74523e8d2e7399ea1638b37aecfca824a3cc4dfdf77bf1fa905ac44` | `58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd` | Apache License |
| `ffi` | 2.2.0 | transitive | `6d7fd89431262d8f3125e81b50d3847a091d846eafcd4fdb88dd06f36d705a45` | `0371d1da6a57fb791db29d29b95333429205f51f3cb2eb3a0c12d91838a38744` | Copyright 2019, the Dart project authors. |
| `ffi_leak_tracker` | 0.1.2 | transitive | `4093d4ef9ca06ffe2786e73bfb25e22aa92112b9bb4ec941f11e3e6b61489a97` | `332f290333e64ed007b4f59aeeebd8fd3ceaadfbfa226a6cf2a3ab1583281624` | BSD 3-Clause License |
| `flutter` | 0.0.0 | direct main | `-` | `-` | SDK-provided / no package LICENSE file |
| `flutter_lints` | 6.0.0 | direct dev | `3105dc8492f6183fb076ccf1f351ac3d60564bff92e20bfc4af9cc1651f4e7e1` | `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` | Copyright 2013 The Flutter Authors. All rights reserved. |
| `flutter_secure_storage` | 11.2.0 | direct main | `d4e1fb6b2cb524868929e78dc0282fa000554b22060fb53789dc481c9fc95bb8` | `55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa` | BSD 3-Clause License |
| `flutter_secure_storage_darwin` | 0.4.3 | transitive | `a031ceac9b070e62ef183cd7f7d1a8798ebde402d5049f0fe6eb3a51bd797a21` | `3754c516086c62307896512b68024837bee5d2bea42a55cfd03f7448b92b06c8` | BSD 3-Clause License |
| `flutter_secure_storage_linux` | 3.0.3 | transitive | `caa75bd78f017422912e3a904933113b2428eb79f981ac37acd2dd2a700458ea` | `55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa` | BSD 3-Clause License |
| `flutter_secure_storage_platform_interface` | 2.1.1 | transitive | `64951127f001f546891c86f414972bf49ef2c4c8a4c92c65f5790cc0c9100045` | `55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa` | BSD 3-Clause License |
| `flutter_secure_storage_web` | 2.1.1 | transitive | `073a62b3aeb866ab4ce795f960413948e51e5a42a9b0c8333b6daf5bb3208a1c` | `55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa` | BSD 3-Clause License |
| `flutter_secure_storage_windows` | 4.2.2 | transitive | `471951813a97006d899db4948acc654a4f28c440083ea08178935ce20b173ec1` | `55dafb084270616f95b9bea53654adda8bdcad95c022a83c4cf8769073f829fa` | BSD 3-Clause License |
| `flutter_test` | 0.0.0 | direct dev | `-` | `-` | SDK-provided / no package LICENSE file |
| `flutter_web_plugins` | 0.0.0 | transitive | `-` | `-` | SDK-provided / no package LICENSE file |
| `hooks` | 2.0.2 | transitive | `9a62a50b50b769a737bc0a8ff381f333529df3ab746b2f6b02e83760231455ba` | `21ae23b0b9ff67a2dc75ab085d1e8db8ac548c5faf370af17f28dd2ef3b52b7b` | Copyright 2025, the Dart project authors. |
| `jni` | 1.2.1 | transitive | `19764f78f6b9e0d40f6395b04649d1046eb57f5ccf05afce50cc63e5a82777b0` | `08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6` | Copyright 2022, the Dart project authors. |
| `jni_flutter` | 1.1.0 | transitive | `586594ad345b403bda8a794b0b8a9e34298238b86c2a7d7f15160b092fe9ef3d` | `b1fcb475d67817411f335ac92872507011e574c4cb29cfdaaf7707b75641932c` | Copyright 2026, the Dart project authors. |
| `jni_util` | 1.0.0 | transitive | `1ba86da04a5f2bf18fde2edb235587e70c5b0fc5bd4ba955f46b00942c3fc35f` | `b1fcb475d67817411f335ac92872507011e574c4cb29cfdaaf7707b75641932c` | Copyright 2026, the Dart project authors. |
| `leak_tracker` | 11.0.2 | transitive | `33e2e26bdd85a0112ec15400c8cbffea70d0f9c3407491f672a2fad47915e2de` | `08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6` | Copyright 2022, the Dart project authors. |
| `leak_tracker_flutter_testing` | 3.0.10 | transitive | `1dbc140bb5a23c75ea9c4811222756104fbcd1a27173f0c34ca01e16bea473c1` | `08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6` | Copyright 2022, the Dart project authors. |
| `leak_tracker_testing` | 3.0.2 | transitive | `8d5a2d49f4a66b49744b23b018848400d23e54caf9463f4eb20df3eb8acb2eb1` | `08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6` | Copyright 2022, the Dart project authors. |
| `lints` | 6.1.0 | transitive | `12f842a479589fea194fe5c5a3095abc7be0c1f2ddfa9a0e76aed1dbd26a87df` | `421fe78c3b5df297f8b4ab2c74f2450a274ee6d245a113091f6b9f90570af193` | Copyright 2021, the Dart project authors. |
| `logging` | 1.3.0 | transitive | `c8245ada5f1717ed44271ed1c26b8ce85ca3228fd2ffdb75468ab01979309d61` | `dfb09c74e29386cd3e2719f32d4995d59526179753931d31840757c77fbf2791` | Copyright 2013, the Dart project authors. |
| `matcher` | 0.12.20 | transitive | `31bd099b47c10cd1aeb55146a2d46ce0277630ecef3f7dae54ad7873f36696cd` | `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` | Copyright 2014, the Dart project authors. |
| `material_color_utilities` | 0.13.0 | transitive | `9c337007e82b1889149c82ed242ed1cb24a66044e30979c44912381e9be4c48b` | `d103f246ef4c18dab8af0c1dcf6a8af884e5cff554da7261a48ac43c17d98f2e` | Apache License |
| `meta` | 1.18.3 | transitive | `c82594181e3312f3d0695fc95aaaf7758d75b8d4ae2bbecf223b9fd5109a059d` | `b71519245009a3b8f126196a5408ec031e216e8e0d985085958c6543f82a8a2a` | Copyright 2016, the Dart project authors. |
| `objective_c` | 9.5.0 | transitive | `b7fb95a6d9a4f009edd63dc5ac69f07420b23a16161c6dd8660290b59c602e8e` | `1cda25a8de6880c5338de0b4a06ee89e8537c213eb1379c16a4c035bfd198b5c` | Copyright 2024, the Dart project authors. |
| `package_config` | 3.0.0 | transitive | `ffcf4cf3d6c0b74ac43708d9f56625506e8a68aa935abe9d267a7330f320eb5d` | `0371d1da6a57fb791db29d29b95333429205f51f3cb2eb3a0c12d91838a38744` | Copyright 2019, the Dart project authors. |
| `path` | 1.9.1 | transitive | `75cca69d1490965be98c73ceaea117e8a04dd21217b37b292c9ddbec0d955bc5` | `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` | Copyright 2014, the Dart project authors. |
| `path_provider` | 2.1.6 | transitive | `a7f4874f987173da295a61c181b8ee71dab59b332a486b391babf26a1b884825` | `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` | Copyright 2013 The Flutter Authors |
| `path_provider_android` | 2.3.1 | transitive | `69cbd515a62b94d32a7944f086b2f82b4ac40a1d45bebfc00813a430ab2dabcd` | `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` | Copyright 2013 The Flutter Authors |
| `path_provider_foundation` | 2.6.0 | transitive | `2a376b7d6392d80cd3705782d2caa734ca4727776db0b6ec36ef3f1855197699` | `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` | Copyright 2013 The Flutter Authors |
| `path_provider_linux` | 2.2.2 | transitive | `58c2005f147315b11e9b4a7bc889cd5203e250cba8e3f012dae259b4972b5c16` | `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` | Copyright 2013 The Flutter Authors |
| `path_provider_platform_interface` | 2.1.3 | transitive | `484838772624c3a4b94f1e44a3e19897fee738f2d5c4ce448443b0417f7c9dda` | `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` | Copyright 2013 The Flutter Authors |
| `path_provider_windows` | 2.3.0 | transitive | `bd6f00dbd873bfb70d0761682da2b3a2c2fccc2b9e84c495821639601d81afe7` | `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` | Copyright 2013 The Flutter Authors. All rights reserved. |
| `platform` | 3.2.0 | transitive | `a36d119c13416516a7b5913fbe8af8531e11633d784c550b2125f76c758524ec` | `143839f62c9b7f88143ea9f688361c27050888acde7696b34e04414bd254fafc` | Copyright 2017, the Dart project authors. All rights reserved. |
| `plugin_platform_interface` | 2.1.8 | transitive | `4820fbfdb9478b1ebae27888254d445073732dae3d6ea81f0b7e06d5dedc3f02` | `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` | Copyright 2013 The Flutter Authors. All rights reserved. |
| `pub_semver` | 2.2.1 | transitive | `261236774e8b1d69cfc6b9eabbc96c40f25e7a2d6b171f3385d4f65d5734fb24` | `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` | Copyright 2014, the Dart project authors. |
| `record_use` | 0.6.0 | transitive | `2551bd8eecfe95d14ae75f6021ad0248be5c27f138c2ec12fcb52b500b3ba1ed` | `1cda25a8de6880c5338de0b4a06ee89e8537c213eb1379c16a4c035bfd198b5c` | Copyright 2024, the Dart project authors. |
| `sky_engine` | 0.0.0 | transitive | `-` | `-` | SDK-provided / no package LICENSE file |
| `source_span` | 1.10.2 | transitive | `56a02f1f4cd1a2d96303c0144c93bd6d909eea6bee6bf5a0e0b685edbd4c47ab` | `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` | Copyright 2014, the Dart project authors. |
| `stack_trace` | 1.12.2 | transitive | `277654b3034d17ac6f9f1cb5595db011b1d5d41e8806866db28e0abaa101c490` | `ff0b91d4f3c32b25cb6ec84985e8da89b0ba2a2b2f7eef353cda5e5423a20390` | Copyright 2014, the Dart project authors. |
| `stream_channel` | 2.1.4 | transitive | `969e04c80b8bcdf826f8f16579c7b14d780458bd97f56d107d3950fdbeef059d` | `ff15faa32a2e638107b7789592b14426162a75ba620044ee2340a20ec6ce5e73` | Copyright 2015, the Dart project authors. |
| `string_scanner` | 1.4.1 | transitive | `921cd31725b72fe181906c6a94d987c78e3b98c2e205b397ea399d4054872b43` | `3c32b53167c7dae9190c38dab5dd9fe1789c53623ebc7d1babcb29914c5b3f16` | Copyright 2014, the Dart project authors. |
| `term_glyph` | 1.2.2 | transitive | `7f554798625ea768a7518313e58f83891c7f5024f88e46e7182a4558850a4b8e` | `ea97a7558a7bd7cee4e2355f7529e3cbebb0dcbb546ddb9a90f10c9eb6b08da5` | Copyright 2017, the Dart project authors. |
| `test_api` | 0.7.12 | transitive | `2a122cbe059f8b610d3a5415f42e255b6c17b1f21eee1d960f31080237fb4f11` | `ff1b9f0df9036c04be424b1e3ce12789bea880ad5ffc3a48e069ae2d40a087a4` | Copyright 2018, the Dart project authors. |
| `vector_math` | 2.4.0 | transitive | `1d774bbdf6b72a0b12122fc1560c9c2d2a67db5a4a4cc2bd8a5c990ab20e3188` | `420f7739f169097f0aad1242045169cd643c8f1d94e62866fad265ae4c369b7d` | Copyright 2013 The Flutter Authors |
| `vm_service` | 15.4.0 | transitive | `89b11d62e1040ee681af3b4f1c97a803ecbf010c6e8b9c5896ee5b08c3bf7b78` | `ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888` | Copyright 2015, the Dart project authors. |
| `web` | 1.1.2 | transitive | `e119e82ac4795c7925103b7cf3768191f33941b99e7ccffbd6c645201d9f606b` | `aa913ff50d7542eb8cc35b9f48a80928ac6819ba9057f85d424655e3e8dc271c` | Copyright 2023, the Dart project authors. |
| `win32` | 6.4.0 | transitive | `a0b93865d5644f11cf6a8c3f6db909f1ec168958b5805f6cc684adea957cd63d` | `87ef8bccdd619f2345ba5b9026cf1d6cccb305e36ab83849a8a3af9293abde7e` | BSD 3-Clause License |
| `xdg_directories` | 1.1.0 | transitive | `7a3f37b05d989967cdddcbb571f1ea834867ae2faa29725fd085180e0883aa15` | `89519eca6f7b9529b35bdddd623a58c3af06a88c458dbd6531ddb4675acf75a9` | Copyright 2013 The Flutter Authors. All rights reserved. |
| `yaml` | 3.1.4 | transitive | `f67cdd8e07d3c6329146aaef1ba043542b3134c12489f553ca9a7435d1068aea` | `d47b93335401b052d79a2f5a3710e4cf7b5aed782faedf84d40fbdd6eb934ec7` | Copyright (c) 2014, the Dart project authors. |

Note: the rejected, unused `flutter_reactive_ble 5.6.0` directory also exists under
`.pub-cache` but is **not** in `pubspec.lock` and is not part of the app.

## Maven cache coordinates

Format: `group:artifact:version` — declared license name(s).

```text
androidx.activity:activity:1.8.1 — The Apache Software License, Version 2.0
androidx.annotation:annotation:1.8.1 — The Apache Software License, Version 2.0
androidx.annotation:annotation-experimental:1.4.0 — The Apache Software License, Version 2.0
androidx.annotation:annotation-jvm:1.8.1 — The Apache Software License, Version 2.0
androidx.annotation:annotation-jvm:1.8.2 — The Apache Software License, Version 2.0
androidx.annotation:annotation-jvm:1.9.1 — The Apache Software License, Version 2.0
androidx.arch.core:core-common:2.2.0 — The Apache Software License, Version 2.0
androidx.arch.core:core-runtime:2.2.0 — The Apache Software License, Version 2.0
androidx.collection:collection:1.1.0 — The Apache Software License, Version 2.0
androidx.concurrent:concurrent-futures:1.0.0 — The Apache Software License, Version 2.0
androidx.concurrent:concurrent-futures:1.1.0 — The Apache Software License, Version 2.0
androidx.core:core:1.13.1 — The Apache Software License, Version 2.0
androidx.core:core-ktx:1.13.1 — The Apache Software License, Version 2.0
androidx.core:core-ktx:1.2.0 — The Apache Software License, Version 2.0
androidx.customview:customview:1.0.0 — The Apache Software License, Version 2.0
androidx.databinding:databinding-common:9.1.0 — The Apache Software License, Version 2.0
androidx.databinding:databinding-compiler-common:9.1.0 — The Apache Software License, Version 2.0
androidx.exifinterface:exifinterface:1.4.1 — The Apache Software License, Version 2.0
androidx.fragment:fragment:1.7.1 — The Apache Software License, Version 2.0
androidx.interpolator:interpolator:1.0.0 — The Apache Software License, Version 2.0
androidx.lifecycle:lifecycle-common:2.7.0 — The Apache Software License, Version 2.0
androidx.lifecycle:lifecycle-common-java8:2.7.0 — The Apache Software License, Version 2.0
androidx.lifecycle:lifecycle-livedata:2.7.0 — The Apache Software License, Version 2.0
androidx.lifecycle:lifecycle-livedata-core:2.7.0 — The Apache Software License, Version 2.0
androidx.lifecycle:lifecycle-livedata-core-ktx:2.7.0 — The Apache Software License, Version 2.0
androidx.lifecycle:lifecycle-process:2.7.0 — The Apache Software License, Version 2.0
androidx.lifecycle:lifecycle-runtime:2.7.0 — The Apache Software License, Version 2.0
androidx.lifecycle:lifecycle-viewmodel:2.7.0 — The Apache Software License, Version 2.0
androidx.lifecycle:lifecycle-viewmodel-savedstate:2.7.0 — The Apache Software License, Version 2.0
androidx.loader:loader:1.0.0 — The Apache Software License, Version 2.0
androidx.profileinstaller:profileinstaller:1.3.0 — The Apache Software License, Version 2.0
androidx.profileinstaller:profileinstaller:1.3.1 — The Apache Software License, Version 2.0
androidx.savedstate:savedstate:1.2.1 — The Apache Software License, Version 2.0
androidx.startup:startup-runtime:1.1.1 — The Apache Software License, Version 2.0
androidx.tracing:tracing:1.2.0 — The Apache Software License, Version 2.0
androidx.versionedparcelable:versionedparcelable:1.1.1 — The Apache Software License, Version 2.0
androidx.viewpager:viewpager:1.0.0 — The Apache Software License, Version 2.0
androidx.window:window:1.2.0 — The Apache Software License, Version 2.0
androidx.window:window-java:1.2.0 — The Apache Software License, Version 2.0
androidx.window.extensions.core:core:1.0.0 — The Apache Software License, Version 2.0
com.android:signflinger:9.1.0 — The Apache Software License, Version 2.0
com.android:zipflinger:8.11.1 — The Apache Software License, Version 2.0
com.android:zipflinger:9.1.0 — The Apache Software License, Version 2.0
com.android.application:com.android.application.gradle.plugin:9.1.0 — The Apache Software License, Version 2.0
com.android.databinding:baseLibrary:9.1.0 — The Apache Software License, Version 2.0
com.android.tools:annotations:32.1.0 — The Apache Software License, Version 2.0
com.android.tools:common:32.1.0 — The Apache Software License, Version 2.0
com.android.tools:dvlib:32.1.0 — The Apache Software License, Version 2.0
com.android.tools:play-sdk-proto:32.1.0 — The Apache Software License, Version 2.0
com.android.tools:repository:32.1.0 — The Apache Software License, Version 2.0
com.android.tools:sdk-common:32.1.0 — The Apache Software License, Version 2.0
com.android.tools:sdklib:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.analytics-library:crash:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.analytics-library:protos:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.analytics-library:shared:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.analytics-library:tracker:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.build:aapt2:9.1.0-14792394 — The Apache Software License, Version 2.0
com.android.tools.build:aapt2-proto:9.1.0-14792394 — The Apache Software License, Version 2.0
com.android.tools.build:aaptcompiler:9.1.0 — The Apache Software License, Version 2.0
com.android.tools.build:apksig:8.11.1 — The Apache Software License, Version 2.0
com.android.tools.build:apksig:9.1.0 — The Apache Software License, Version 2.0
com.android.tools.build:apkzlib:8.11.1 — The Apache Software License, Version 2.0
com.android.tools.build:apkzlib:9.1.0 — The Apache Software License, Version 2.0
com.android.tools.build:builder:8.11.1 — The Apache Software License, Version 2.0
com.android.tools.build:builder:9.1.0 — The Apache Software License, Version 2.0
com.android.tools.build:builder-model:8.11.1 — The Apache Software License, Version 2.0
com.android.tools.build:builder-model:9.1.0 — The Apache Software License, Version 2.0
com.android.tools.build:builder-test-api:9.1.0 — The Apache Software License, Version 2.0
com.android.tools.build:bundletool:1.18.3 — The Apache Software License, Version 2.0
com.android.tools.build:gradle:8.11.1 — The Apache Software License, Version 2.0
com.android.tools.build:gradle:9.1.0 — The Apache Software License, Version 2.0
com.android.tools.build:gradle-api:8.11.1 — The Apache Software License, Version 2.0
com.android.tools.build:gradle-api:9.1.0 — The Apache Software License, Version 2.0
com.android.tools.build:gradle-common-api:9.1.0 — The Apache Software License, Version 2.0
com.android.tools.build:gradle-settings-api:9.1.0 — The Apache Software License, Version 2.0
com.android.tools.build:manifest-merger:31.11.1 — The Apache Software License, Version 2.0
com.android.tools.build:manifest-merger:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.build.jetifier:jetifier-core:1.0.0-beta10 — The Apache Software License, Version 2.0
com.android.tools.build.jetifier:jetifier-processor:1.0.0-beta10 — The Apache Software License, Version 2.0
com.android.tools.ddms:ddmlib:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.external.com-intellij:intellij-core:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.external.com-intellij:kotlin-compiler:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.external.org-jetbrains:uast:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.layoutlib:layoutlib-api:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.lint:lint:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.lint:lint-api:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.lint:lint-checks:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.lint:lint-gradle:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.lint:lint-model:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.lint:lint-typedef-remover:32.1.0 — The Apache Software License, Version 2.0
com.android.tools.utp:gradle-work-action-api:32.1.0 — The Apache Software License, Version 2.0
com.getkeepsafe.relinker:relinker:1.4.5 — The Apache Software License, Version 2.0
com.google.auto:auto-parent:6 — Apache 2.0
com.google.auto.value:auto-value-annotations:1.6.2 — undeclared
com.google.auto.value:auto-value-parent:1.6.2 — undeclared
com.google.code.findbugs:jsr305:3.0.2 — The Apache Software License, Version 2.0
com.google.code.gson:gson:2.11.0 — Apache-2.0
com.google.code.gson:gson:2.13.2 — Apache-2.0
com.google.code.gson:gson-parent:2.11.0 — Apache-2.0
com.google.code.gson:gson-parent:2.13.2 — Apache-2.0
com.google.crypto.tink:tink:1.7.0 — Apache License, Version 2.0
com.google.crypto.tink:tink-android:1.23.0 — Apache License, Version 2.0
com.google.dagger:dagger:2.28.3 — Apache 2.0
com.google.errorprone:error_prone_annotations:2.18.0 — Apache 2.0
com.google.errorprone:error_prone_annotations:2.27.0 — Apache 2.0
com.google.errorprone:error_prone_annotations:2.28.0 — Apache 2.0
com.google.errorprone:error_prone_annotations:2.3.1 — Apache 2.0
com.google.errorprone:error_prone_annotations:2.41.0 — Apache 2.0
com.google.errorprone:error_prone_parent:2.18.0 — Apache 2.0
com.google.errorprone:error_prone_parent:2.27.0 — Apache 2.0
com.google.errorprone:error_prone_parent:2.28.0 — Apache 2.0
com.google.errorprone:error_prone_parent:2.3.1 — Apache 2.0
com.google.errorprone:error_prone_parent:2.41.0 — Apache 2.0
com.google.flatbuffers:flatbuffers-java:1.12.0 — Apache License V2.0
com.google.guava:failureaccess:1.0.2 — undeclared
com.google.guava:guava:33.3.1-jre — undeclared
com.google.guava:guava-parent:26.0-android — The Apache Software License, Version 2.0
com.google.guava:guava-parent:33.3.1-jre — Apache License, Version 2.0
com.google.guava:listenablefuture:1.0 — undeclared
com.google.guava:listenablefuture:9999.0-empty-to-avoid-conflict-with-guava — undeclared
com.google.j2objc:j2objc-annotations:2.8 — Apache License, Version 2.0
com.google.j2objc:j2objc-annotations:3.0.0 — Apache License, Version 2.0
com.google.jimfs:jimfs:1.1 — undeclared
com.google.jimfs:jimfs-parent:1.1 — The Apache Software License, Version 2.0
com.google.protobuf:protobuf-bom:3.25.5 — BSD-3-Clause
com.google.protobuf:protobuf-java:3.25.5 — undeclared
com.google.protobuf:protobuf-java-util:3.25.5 — undeclared
com.google.protobuf:protobuf-parent:3.25.5 — BSD-3-Clause
com.googlecode.juniversalchardet:juniversalchardet:1.0.3 — Mozilla Public License 1.1 (MPL 1.1)
com.squareup:javapoet:1.13.0 — Apache 2.0
com.squareup:javawriter:2.5.0 — Apache 2.0
com.sun.activation:all:1.2.1 — EDL 1.0
com.sun.istack:istack-commons:3.0.8 — Eclipse Distribution License - v 1.0
com.sun.istack:istack-commons-runtime:3.0.8 — undeclared
com.sun.xml.bind:jaxb-bom-ext:2.3.2 — undeclared
com.sun.xml.bind.mvn:jaxb-parent:2.3.2 — Eclipse Distribution License - v 1.0
com.sun.xml.bind.mvn:jaxb-runtime-parent:2.3.2 — undeclared
com.sun.xml.bind.mvn:jaxb-txw-parent:2.3.2 — undeclared
com.sun.xml.fastinfoset:FastInfoset:1.2.16 — undeclared
com.sun.xml.fastinfoset:fastinfoset-project:1.2.16 — Apache License, Version 2.0; Eclipse Distribution License - v 1.0
commons-codec:commons-codec:1.17.1 — undeclared
commons-io:commons-io:2.16.1 — undeclared
commons-logging:commons-logging:1.2 — undeclared
io.flutter:arm64_v8a_debug:1.0.0-cf636b1dfb818dd6a3ff16e390e93b1a036969c8 — undeclared
io.flutter:armeabi_v7a_debug:1.0.0-cf636b1dfb818dd6a3ff16e390e93b1a036969c8 — undeclared
io.flutter:flutter_embedding_debug:1.0.0-cf636b1dfb818dd6a3ff16e390e93b1a036969c8 — undeclared
io.flutter:x86_64_debug:1.0.0-cf636b1dfb818dd6a3ff16e390e93b1a036969c8 — undeclared
jakarta.activation:jakarta.activation-api:1.2.1 — undeclared
jakarta.xml.bind:jakarta.xml.bind-api:2.3.2 — undeclared
jakarta.xml.bind:jakarta.xml.bind-api-parent:2.3.2 — Eclipse Distribution License - v 1.0
javax.inject:javax.inject:1 — The Apache Software License, Version 2.0
net.java.dev.jna:jna:5.6.0 — Apache License v2.0; LGPL, version 2.1
net.java.dev.jna:jna-platform:5.6.0 — Apache License v2.0; LGPL, version 2.1
net.sf.jopt-simple:jopt-simple:4.9 — The MIT License
net.sf.kxml:kxml2:2.3.0 — BSD style; Public Domain
org.apache:apache:13 — The Apache Software License, Version 2.0
org.apache:apache:18 — Apache License, Version 2.0
org.apache:apache:21 — Apache License, Version 2.0
org.apache:apache:31 — Apache-2.0
org.apache:apache:32 — Apache-2.0
org.apache:apache:33 — Apache-2.0
org.apache.commons:commons-compress:1.27.1 — undeclared
org.apache.commons:commons-lang3:3.16.0 — undeclared
org.apache.commons:commons-parent:34 — undeclared
org.apache.commons:commons-parent:69 — undeclared
org.apache.commons:commons-parent:71 — undeclared
org.apache.commons:commons-parent:72 — undeclared
org.apache.httpcomponents:httpclient:4.5.14 — undeclared
org.apache.httpcomponents:httpclient:4.5.6 — undeclared
org.apache.httpcomponents:httpcomponents-client:4.5.14 — Apache License, Version 2.0
org.apache.httpcomponents:httpcomponents-client:4.5.6 — Apache License, Version 2.0
org.apache.httpcomponents:httpcomponents-core:4.4.16 — Apache License, Version 2.0
org.apache.httpcomponents:httpcomponents-parent:10 — undeclared
org.apache.httpcomponents:httpcomponents-parent:11 — undeclared
org.apache.httpcomponents:httpcore:4.4.16 — undeclared
org.apache.httpcomponents:httpmime:4.5.6 — undeclared
org.bitbucket.b_c:jose4j:0.9.5 — The Apache Software License, Version 2.0
org.bouncycastle:bcpkix-jdk18on:1.79 — Bouncy Castle Licence
org.bouncycastle:bcprov-jdk18on:1.79 — Bouncy Castle Licence
org.bouncycastle:bcutil-jdk18on:1.79 — Bouncy Castle Licence
org.checkerframework:checker-qual:2.5.8 — The MIT License
org.checkerframework:checker-qual:3.43.0 — The MIT License
org.codehaus.groovy:groovy:3.0.22 — The Apache Software License, Version 2.0
org.eclipse.ee4j:project:1.0.2 — Eclipse Public License v. 2.0; GNU General Public License, version 2 with the GNU Classpath Exception
org.eclipse.ee4j:project:1.0.5 — Eclipse Public License v. 2.0; GNU General Public License, version 2 with the GNU Classpath Exception
org.glassfish.jaxb:jaxb-bom:2.3.2 — undeclared
org.glassfish.jaxb:jaxb-runtime:2.3.2 — undeclared
org.glassfish.jaxb:txw2:2.3.2 — undeclared
org.gradle.kotlin:gradle-kotlin-dsl-plugins:6.4.2 — The Apache License, Version 2.0
org.gradle.kotlin.kotlin-dsl:org.gradle.kotlin.kotlin-dsl.gradle.plugin:6.4.2 — undeclared
org.jdom:jdom2:2.0.6 — Similar to Apache License but with the acknowledgment clause removed
org.jetbrains:annotations:13.0 — The Apache Software License, Version 2.0
org.jetbrains:annotations:23.0.0 — The Apache Software License, Version 2.0
org.jetbrains.kotlin:abi-tools-api:2.2.21 — Apache-2.0
org.jetbrains.kotlin:fus-statistics-gradle-plugin:2.2.21 — Apache-2.0
org.jetbrains.kotlin:fus-statistics-gradle-plugin:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-assignment:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-assignment-compiler-plugin-embeddable:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-build-statistics:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-build-statistics:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-build-tools-api:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-build-tools-api:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-build-tools-compat:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-build-tools-cri-impl:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-build-tools-impl:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-build-tools-impl:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-compiler-embeddable:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-compiler-embeddable:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-compiler-runner:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-compiler-runner:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-daemon-client:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-daemon-client:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-daemon-embeddable:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-daemon-embeddable:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin:2.0.0 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-annotations:2.0.0 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-annotations:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-annotations:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-api:2.0.0 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-api:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-api:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-idea:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-idea:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-idea-proto:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-idea-proto:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-model:2.0.0 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-gradle-plugin-model:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugins-bom:2.0.0 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-gradle-plugins-bom:2.2.20 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugins-bom:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-gradle-plugins-bom:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-klib-commonizer-api:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-klib-commonizer-api:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-native-utils:2.0.0 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-native-utils:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-native-utils:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-reflect:1.6.10 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-reflect:2.2.10 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-reflect:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-sam-with-receiver:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-sam-with-receiver-compiler-plugin-embeddable:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-script-runtime:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-script-runtime:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-scripting-common:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-scripting-compiler-embeddable:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-scripting-compiler-impl-embeddable:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-scripting-jvm:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-stdlib:2.2.10 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-stdlib:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-stdlib:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-stdlib-common:1.7.10 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-stdlib-common:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-stdlib-common:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.8.0 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.8.20 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.2.10 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.7.10 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.8.0 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.8.20 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.2.10 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-tooling-core:2.0.0 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-tooling-core:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-tooling-core:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-util-io:2.0.0 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-util-io:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-util-io:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-util-klib:2.0.0 — The Apache License, Version 2.0
org.jetbrains.kotlin:kotlin-util-klib:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-util-klib:2.4.0 — Apache-2.0
org.jetbrains.kotlin:kotlin-util-klib-metadata:2.2.21 — Apache-2.0
org.jetbrains.kotlin:kotlin-util-klib-metadata:2.4.0 — Apache-2.0
org.jetbrains.kotlin.android:org.jetbrains.kotlin.android.gradle.plugin:2.4.0 — Apache-2.0
org.jetbrains.kotlin.jvm:org.jetbrains.kotlin.jvm.gradle.plugin:2.2.20 — undeclared
org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.1 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-coroutines-bom:1.7.1 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-coroutines-bom:1.8.0 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-coroutines-bom:1.9.0 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.1 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm:1.7.1 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm:1.8.0 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm:1.9.0 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-serialization-core:1.4.0 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-serialization-core-jvm:1.4.0 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-serialization-json:1.4.0 — The Apache Software License, Version 2.0
org.jetbrains.kotlinx:kotlinx-serialization-json-jvm:1.4.0 — The Apache Software License, Version 2.0
org.jspecify:jspecify:1.0.0 — The Apache License, Version 2.0
org.junit:junit-bom:5.10.2 — Eclipse Public License v2.0
org.junit:junit-bom:5.11.0-M2 — Eclipse Public License v2.0
org.jvnet.staxex:stax-ex:1.8.1 — Eclipse Distribution License - v 1.0
org.ow2:ow2:1.5.1 — The Apache Software License, Version 2.0
org.ow2.asm:asm:9.7.1 — BSD-3-Clause
org.ow2.asm:asm:9.9 — BSD-3-Clause
org.ow2.asm:asm-analysis:9.9 — BSD-3-Clause
org.ow2.asm:asm-commons:9.9 — BSD-3-Clause
org.ow2.asm:asm-tree:9.9 — BSD-3-Clause
org.ow2.asm:asm-util:9.9 — BSD-3-Clause
org.slf4j:slf4j-api:1.7.30 — undeclared
org.slf4j:slf4j-parent:1.7.30 — MIT License
org.sonatype.oss:oss-parent:7 — undeclared
org.sonatype.oss:oss-parent:9 — undeclared
org.tensorflow:tensorflow-lite-metadata:0.2.0 — The Apache Software License, Version 2.0
```

## Firmware and toolchain

| Component | Resolved version | Local license evidence |
|---|---|---|
| ESP32 Arduino core | 3.3.12 | No package-level LICENSE file found in the installed core; upstream project declares LGPL-2.1 (not re-verified locally) |
| ArduinoJson | 7.4.3 | `LICENSE.txt` first line: The MIT License (MIT) |
| IRremoteESP8266 | 2.9.0 | `LICENSE.txt` first line: GNU LESSER GENERAL PUBLIC LICENSE Version 2.1 |
| Arduino CLI | 1.5.1 | Build tool, not linked into the firmware; license not re-checked here |
| Flutter / Dart SDK | 3.47.8 / 3.13.7 | SDK-provided; packages `flutter`, `flutter_test`, `flutter_web_plugins`, `sky_engine` have no package LICENSE file |
| Python | 3.14.7 | Local runtime; package licenses not enumerated here |
| OpenCV / NumPy / pyserial | 5.0.0.93 / 2.5.4 / 3.5 | Existing local runtime; licenses not enumerated here |

## What is still missing

- A full advisory query over all 59 Pub archives and all Maven coordinates.
- Separation of Maven build tooling from the exact packaged APK runtime graph.
- SPDX/legal review of license texts, notices and any LGPL relinking obligations.
- Firmware SBOM generation and reproducible-build comparison.

These gaps mean the dependency set must not be described as audited-clean.
