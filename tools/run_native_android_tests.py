"""Compile the actual RoomBle.kt against owned narrow JVM API fixtures.

This is NOT Android instrumentation or a BLE radio test. Uses only the installed
JDK/Kotlin artifacts; no Gradle configuration, dependency install or download.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".gradle-user-home/caches/modules-2/files-2.1"
JAVA = Path(r"C:\Program Files\Android\Android Studio\jbr\bin\java.exe")


def jar(group: str, name: str, version: str) -> Path:
    found = list((CACHE / group / name / version).glob(f"*/{name}-{version}.jar"))
    if len(found) != 1:
        raise RuntimeError(f"Existing exact compiler dependency unavailable: {group}:{name}:{version}; no download")
    return found[0]


def main() -> int:
    kotlin = [jar("org.jetbrains.kotlin", name, version) for name, version in (
        ("kotlin-compiler-embeddable", "2.4.0"), ("kotlin-build-tools-api", "2.4.0"),
        ("kotlin-stdlib", "2.4.0"), ("kotlin-script-runtime", "2.4.0"),
        ("kotlin-reflect", "1.6.10"), ("kotlin-daemon-embeddable", "2.4.0"))]
    kotlin.append(jar("org.jetbrains.kotlinx", "kotlinx-coroutines-core-jvm", "1.8.0"))
    annotations = jar("org.jetbrains", "annotations", "23.0.0")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    owned = Path(os.environ["LOCALAPPDATA"]) / "Temp/opencode" / f"smart_room_native_android_{stamp}"
    owned.mkdir()
    output = owned / "tests.jar"
    actual = ROOT / "app/android/app/src/main/kotlin/com/example/smart_room/RoomBle.kt"
    sources = sorted((ROOT / "tests/native_android").glob("*.kt")) + [actual]
    if not 2 <= len(sources) <= 30 or any(source.stat().st_size > 512000 for source in sources):
        raise RuntimeError("Native fixture source bound")
    print(f"Actual adapter SHA256: {hashlib.sha256(actual.read_bytes()).hexdigest()}", flush=True)
    print(f"Evidence directory: {owned}", flush=True)
    compile_command = [str(JAVA), "-Xmx512m", "-cp", os.pathsep.join(map(str, [*kotlin, annotations])),
        "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler", "-no-stdlib", "-no-reflect", "-jvm-target", "17",
        "-classpath", os.pathsep.join(map(str, [kotlin[2], annotations])), "-d", str(output), *map(str, sources)]
    result = subprocess.run(compile_command, cwd=ROOT, timeout=180, check=False)
    if result.returncode:
        return result.returncode
    result = subprocess.run([str(JAVA), "-Xmx256m", "-cp", os.pathsep.join(map(str, [output, kotlin[2]])),
        "room.test.NativeBleTestsKt"], cwd=ROOT, timeout=30, check=False)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
