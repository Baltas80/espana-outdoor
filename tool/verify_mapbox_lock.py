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

print(f"mapbox_maps_flutter={main_version}")
for package in federated:
    print(f"{package}={package_version(package)}")
print("premium_assets=declared")
print("integration_test=sdk")
