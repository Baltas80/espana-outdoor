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
manifest = source.split("- name: Build Android staging APK", 1)[1].split(
    "- name: Verify APK", 1
)[0]
for marker in (
    'echo "application_id=$application_id"',
    'echo "version_code=$version_code"',
    'echo "apk_sha256=$apk_sha256"',
    'echo "source_commit=$source_commit"',
    'echo "workflow_commit=$GITHUB_SHA"',
):
    if marker not in manifest:
        raise SystemExit(f"Staging APK manifest is missing provenance field: {marker}")

verify = source.split("- name: Verify APK", 1)[1].split(
    "- name: Upload Android staging APK", 1
)[0]
if 'test "$expected_sha" = "$actual_sha"' not in verify:
    raise SystemExit("Staging APK verification must compare the manifest SHA-256 with the actual APK.")
upload = source.split("- name: Upload Android staging APK", 1)[1].split(
    "- name: Enable KVM", 1
)[0]
if "if: success() && steps.build_apk.outputs.built == 'true'" not in upload:
    raise SystemExit("An APK must not be uploaded when its verification step fails.")

refresh = source.split("refresh-pub-lockfile:", 1)[1]
if "always() &&" not in refresh or "needs.android-staging.outputs.apk_built == 'true'" not in refresh:
    raise SystemExit("The one-time lockfile refresh must run after a successful APK build even if the map smoke fails.")

print("staging_apk_manifest_has_hash_and_source_commit=true")
print("staging_apk_upload_requires_verification=true")
print("staging_lockfile_refresh_is_independent_of_map_smoke=true")
print("staging_lockfile_refreshed_from_application_pubspec=true")
print("staging_resolved_lockfile_exported=true")
