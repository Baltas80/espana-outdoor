#!/usr/bin/env python3
"""Validate that Flutter resolved and locked the Mapbox packages used by Android."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
lock = (ROOT / "pubspec.lock").read_text(encoding="utf-8")

if "mapbox_maps_flutter: 3.34.1" not in pubspec:
    raise SystemExit("pubspec.yaml must pin mapbox_maps_flutter 3.34.1.")
if "integration_test:" not in pubspec:
    raise SystemExit("pubspec.yaml must declare the integration_test SDK package.")
if "assets/visuals/icons/library/premium/" not in pubspec:
    raise SystemExit("pubspec.yaml must include the premium icon asset directory.")
if "dependency_overrides:" in pubspec:
    raise SystemExit("Do not pin federated Mapbox packages through dependency_overrides.")


def package_version(name: str) -> str:
    pattern = rf"(?ms)^  {re.escape(name)}:\n(.*?)(?=^  [A-Za-z0-9_]+:|\Z)"
    match = re.search(pattern, lock)
    if not match:
        raise SystemExit(f"pubspec.lock is missing {name}.")
    version = re.search(r'^    version: "([^"]+)"$', match.group(1), re.MULTILINE)
    if not version:
        raise SystemExit(f"pubspec.lock has no resolved version for {name}.")
    return version.group(1)


main_version = package_version("mapbox_maps_flutter")
if main_version != "3.34.1":
    raise SystemExit(
        f"pubspec.lock resolves mapbox_maps_flutter {main_version}; expected 3.34.1."
    )

federated = (
    "mapbox_maps_flutter_mobile",
    "mapbox_maps_flutter_platform_interface",
    "mapbox_maps_flutter_web",
)
for package in federated:
    package_version(package)

if "  integration_test:\n" not in lock or "    source: sdk\n" not in lock:
    raise SystemExit("pubspec.lock must contain integration_test from the Flutter SDK.")

android_gradle = (ROOT / "android" / "app" / "build.gradle.kts").read_text(encoding="utf-8")
required_native = {
    "Maps SDK 11.35.0 / NDK27": 'com.mapbox.maps:android-ndk27:11.35.0',
    "Navigation SDK 3.35.0 / NDK27": 'com.mapbox.navigationcore:android-ndk27:3.35.0',
    "Core Common 24.35.0 / NDK27": 'com.mapbox.common:common-ndk27:24.35.0',
    "Android NDK 28.2.13676358": 'ndkVersion = "28.2.13676358"',
}
for label, fragment in required_native.items():
    if fragment not in android_gradle:
        raise SystemExit(f"Android Mapbox native dependency alignment is missing: {label}.")

if 'com.mapbox.common:common:24.35.0' in android_gradle:
    raise SystemExit(
        "Do not mix the regular Mapbox Common artifact with NDK27 variants; "
        "it duplicates libc++_shared.so."
    )

print(f"mapbox_maps_flutter={main_version}")
for package in federated:
    print(f"{package}={package_version(package)}")
print("maps_android=11.35.0-ndk27")
print("navigation_android=3.35.0-ndk27")
print("mapbox_common=24.35.0-ndk27")
print("android_ndk=28.2.13676358")
print("premium_assets=declared")
print("integration_test=sdk")
