#!/usr/bin/env python3
"""Guard Android staging against flutter create replacing the committed Pub lockfile."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "staging-android.yml"
source = WORKFLOW.read_text(encoding="utf-8")

generate = source.split("- name: Generate Android project", 1)[1].split(
    "- name: Apply Android native configuration", 1
)[0]
dependencies = source.split("- name: Resolve dependencies and export the refreshed lockfile", 1)[1].split(
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
if "flutter pub get\n" not in dependencies:
    raise SystemExit("The one-time lockfile refresh must resolve the restored app pubspec.")
if "resolved-pub-lock/pubspec.lock" not in dependencies:
    raise SystemExit("The resolved lockfile must be exported as a workflow artifact.")
if "name: resolved-pubspec-lock" not in dependencies:
    raise SystemExit("The resolved lockfile artifact must have a stable name.")

print("staging_lockfile_saved_before_flutter_create=true")
print("staging_lockfile_restored_after_flutter_create=true")
print("staging_lockfile_refreshed_from_application_pubspec=true")
print("staging_resolved_lockfile_exported=true")
