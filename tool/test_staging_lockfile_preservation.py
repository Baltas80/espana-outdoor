#!/usr/bin/env python3
"""Ensure staging builds from committed native files without project regeneration."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
workflow = (ROOT / ".github" / "workflows" / "staging-android.yml").read_text(encoding="utf-8")
gradle = (ROOT / "android" / "app" / "build.gradle.kts").read_text(encoding="utf-8")

for forbidden in ("flutter create .", "configure_mobile_native.py"):
    if forbidden in workflow:
        raise SystemExit(f"Staging workflow must not regenerate/patch Android: {forbidden}")

if "flutter pub get --enforce-lockfile" not in workflow:
    raise SystemExit("Staging must resolve dependencies from the committed lockfile.")
if "git diff --exit-code -- pubspec.lock" not in workflow:
    raise SystemExit("Staging must fail if dependency resolution changes pubspec.lock.")
if "flutter build apk --flavor staging --release" not in workflow:
    raise SystemExit("Staging must build the committed staging flavor.")
if 'applicationIdSuffix = ".iconspreview"' not in gradle:
    raise SystemExit("Native Gradle must provide an isolated staging application ID suffix.")
if "create(\"production\")" not in gradle:
    raise SystemExit("Native Gradle must retain an explicit production flavor.")

print("staging_native_project_not_regenerated=true")
print("staging_dependencies_use_enforced_lockfile=true")
print("staging_lockfile_immutability_checked=true")
print("staging_flavor_application_id_isolated=true")
