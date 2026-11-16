#!/usr/bin/env python3
"""Guard Android staging against flutter create replacing the committed Pub lockfile."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "staging-android.yml"
source = WORKFLOW.read_text(encoding="utf-8")

generate = source.split("- name: Generate Android project", 1)[1].split(
    "- name: Apply Android native configuration", 1
)[0]
dependencies = source.split("- name: Dependencies (enforce committed lockfile)", 1)[1].split(
    "- name: Analyze and test", 1
)[0]

save = 'cp pubspec.lock "$RUNNER_TEMP/pubspec.lock"'
restore = 'cp "$RUNNER_TEMP/pubspec.lock" pubspec.lock'
if save not in generate:
    raise SystemExit("Android project generation must preserve the committed pubspec.lock before flutter create.")
if restore not in generate:
    raise SystemExit("Android project generation must restore the committed pubspec.lock after flutter create.")
if generate.index(save) > generate.index("flutter create ."):
    raise SystemExit("The lockfile must be saved before flutter create can overwrite it.")
if generate.index(restore) < generate.index("flutter create ."):
    raise SystemExit("The lockfile must be restored after flutter create.")
if "flutter pub get --enforce-lockfile" not in dependencies:
    raise SystemExit("Android staging must resolve dependencies with --enforce-lockfile.")
if "git diff --exit-code -- pubspec.lock" not in dependencies:
    raise SystemExit("Android staging must fail if dependency resolution changes the committed lockfile.")
if "flutter pub get\n" in dependencies:
    raise SystemExit("Android staging must not silently rewrite the committed lockfile.")

print("staging_lockfile_saved_before_flutter_create=true")
print("staging_lockfile_restored_after_flutter_create=true")
print("staging_pub_get_enforces_committed_lockfile=true")
print("staging_lockfile_unchanged_after_resolution=true")
