#!/usr/bin/env python3
"""Build a local Cove.app with Apple's Command Line Tools."""

import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


def run(*args, capture=False):
    return subprocess.run(args, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def main():
    sdk = os.environ.get("COVE_SDK")
    if not sdk:
        older_sdk = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk")
        sdk = str(older_sdk) if older_sdk.exists() else run("xcrun", "--show-sdk-path", capture=True).strip()
    if not Path("/opt/homebrew/lib/libduckdb.dylib").exists():
        raise SystemExit("Install DuckDB first: brew install duckdb")

    run("swift", "package", "resolve")
    # Swift 6.4's TaskLocal macro incorrectly concatenates @usableFromInline
    # with nonisolated. Public visibility preserves access from inlinable code.
    if "Swift version 6.4" in run("swift", "--version", capture=True):
        source = ROOT / ".build/checkouts/oracle-nio/Sources/OracleNIO/OracleCodable.swift"
        original = "    @usableFromInline\n    @TaskLocal static var jsonMaximumFieldNameSize: Int = 255"
        replacement = "    @TaskLocal public static var jsonMaximumFieldNameSize: Int = 255"
        text = source.read_text()
        if original in text:
            source.chmod(source.stat().st_mode | 0o200)
            source.write_text(text.replace(original, replacement, 1))
            print("Applied local OracleNIO Swift 6.4 compatibility patch.", flush=True)

    # OracleNIO only bounds TCP establishment, not TLS/authentication startup.
    source = ROOT / ".build/checkouts/oracle-nio/Sources/OracleNIO/Connection/OracleConnection.swift"
    text = source.read_text()
    original = "        return eventHandler.startupDoneFuture\n"
    replacement = """        let startupTimeout = channel.eventLoop.scheduleTask(in: configuration.options.connectTimeout) {
            channel.close(promise: nil)
        }
        return eventHandler.startupDoneFuture
            .always { _ in startupTimeout.cancel() }
"""
    if "let startupTimeout =" not in text:
        if original not in text:
            raise SystemExit("OracleNIO startup code changed; review the startup timeout patch.")
        source.chmod(source.stat().st_mode | 0o200)
        source.write_text(text.replace(original, replacement, 1))

    options = ["--build-system", "native", "--sdk", sdk]
    run("swift", "build", *options, "--product", "Cove")
    binary_dir = Path(run("swift", "build", *options, "--show-bin-path", capture=True).strip())
    app = ROOT / ".build/Cove.app"
    contents = app / "Contents"
    for directory in ("MacOS", "Resources", "Frameworks"):
        (contents / directory).mkdir(parents=True, exist_ok=True)
    executable = contents / "MacOS/Cove"
    shutil.copy2(binary_dir / "Cove", executable)
    info = plistlib.loads((ROOT / "Cove/Info.plist").read_bytes())
    info["CFBundleShortVersionString"] = "0.2.0"
    info["CFBundleVersion"] = "2"
    info.pop("CFBundleIconName", None)
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))

    jdbc = contents / "Resources/OracleJDBC"
    jdbc.mkdir(exist_ok=True)
    drivers = Path.home() / "Library/Application Support/JetBrains"
    for prefix in ("ojdbc17", "oraclepki", "osdt_core", "osdt_cert"):
        candidates = sorted(drivers.glob(f"**/Oracle/23.26.2.0/**/{prefix}-*.jar"))
        if not candidates:
            raise SystemExit(f"Missing {prefix} Oracle driver library. Install the Oracle 23.26.2 driver in IntelliJ first.")
        shutil.copy2(candidates[-1], jdbc / candidates[-1].name)
    run("javac", "--release", "17", "-d", str(jdbc), str(ROOT / "Helpers/CoveOracleBridge.java"))

    assets = ROOT / "Cove/Assets.xcassets"
    for imageset in assets.glob("*.imageset"):
        images = json.loads((imageset / "Contents.json").read_text())["images"]
        image = next(item["filename"] for item in images if "filename" in item)
        shutil.copy2(imageset / image, contents / "Resources" / (imageset.stem + Path(image).suffix))
    iconset = ROOT / ".build/AppIcon.iconset"
    iconset.mkdir(exist_ok=True)
    for image in json.loads((assets / "AppIcon.appiconset/Contents.json").read_text())["images"]:
        size = image["size"]
        suffix = "@2x" if image["scale"] == "2x" else ""
        shutil.copy2(assets / "AppIcon.appiconset" / image["filename"], iconset / f"icon_{size}{suffix}.png")
    run("iconutil", "-c", "icns", str(iconset), "-o", str(contents / "Resources/AppIcon.icns"))

    for resource in binary_dir.glob("*.bundle"):
        destination = contents / "Resources" / resource.name
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(resource, contents / "Resources" / resource.name, dirs_exist_ok=True)
    # Keep the native DuckDB dependency with the app rather than tying launch
    # to a particular Homebrew Cellar version.
    dependencies = run("otool", "-L", str(executable), capture=True).splitlines()[1:]
    duckdb = next(line.strip().split(" (", 1)[0] for line in dependencies if "libduckdb" in line)
    library = contents / "Frameworks/libduckdb.dylib"
    if library.exists():
        library.chmod(library.stat().st_mode | 0o200)
    shutil.copy2(duckdb, library)
    library.chmod(library.stat().st_mode | 0o200)
    run("install_name_tool", "-change", duckdb, "@executable_path/../Frameworks/libduckdb.dylib", str(executable))
    run("codesign", "--force", "--sign", "-", str(library))
    run("codesign", "--force", "--sign", "-", str(app))
    print(f"Built {app}", flush=True)
    if "--build-only" not in sys.argv:
        run("open", str(app))


if __name__ == "__main__":
    main()
