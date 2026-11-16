#!/usr/bin/env python3
"""Prevent Android map smoke from accepting a live process with a blank viewport."""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SMOKE = ROOT / "tool" / "smoke_android_map.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "staging-android.yml"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
NETWORK_PREFLIGHT = ROOT / "tool" / "ensure_android_emulator_online.sh"
MAPBOX_VIEWPORT = ROOT / "lib" / "features" / "map" / "mapbox_map_viewport.dart"
MAPBOX_PAGE = ROOT / "lib" / "features" / "map" / "mapbox_map_page.dart"
MAP_SCREEN_VERIFIER = ROOT / "tool" / "verify_android_map_screen.py"
source = SMOKE.read_text(encoding="utf-8")
if not MAPBOX_PAGE.is_file():
    raise SystemExit("Android map smoke requires the main Mapbox page.")
mapbox_page = MAPBOX_PAGE.read_text(encoding="utf-8")
if not MAP_SCREEN_VERIFIER.is_file():
    raise SystemExit("Android map smoke requires the actual map-page hierarchy verifier.")
map_screen_verifier = MAP_SCREEN_VERIFIER.read_text(encoding="utf-8")
if not MAPBOX_VIEWPORT.is_file():
    raise SystemExit("Android map smoke requires the shared Mapbox viewport.")
mapbox_viewport = MAPBOX_VIEWPORT.read_text(encoding="utf-8")
if not NETWORK_PREFLIGHT.is_file():
    raise SystemExit("Android map smoke references a missing emulator network preflight script.")
network_preflight = NETWORK_PREFLIGHT.read_text(encoding="utf-8")
workflow = WORKFLOW.read_text(encoding="utf-8")
ci_workflow = CI_WORKFLOW.read_text(encoding="utf-8")


def job_block(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^  {re.escape(name)}:\n(.*?)(?=^  [a-z0-9-]+:|\Z)",
        source,
    )
    if match is None:
        raise SystemExit(f"CI workflow is missing job: {name}")
    return match.group(1)


for job, minutes in (
    ("rescue-link", 20),
    ("source-gateway", 30),
    ("flutter", 75),
    ("ios-build", 60),
):
    if f"timeout-minutes: {minutes}" not in job_block(ci_workflow, job):
        raise SystemExit(f"CI job {job} must have a {minutes}-minute upper bound.")

android_job = job_block(workflow, "android-staging")
if "timeout-minutes: 75" not in android_job:
    raise SystemExit("Android staging job must have a 75-minute upper bound.")
if "cancel-in-progress: true" not in workflow.split("concurrency:", 1)[1].split("permissions:", 1)[0]:
    raise SystemExit("A newer Android staging commit must supersede queued stale runs on the same branch.")

# A/B style selection is a staging-only build input. The default and all PR
# builds remain Outdoors; Standard can be selected explicitly on workflow_dispatch.
for marker in (
    "mapbox_style_variant",
    "type: choice",
    "default: outdoors-v12",
    "mapbox://styles/mapbox/standard",
    '--dart-define=MAPBOX_STYLE_URI="$MAPBOX_STYLE_URI"',
    'echo "mapbox_style_uri=$MAPBOX_STYLE_URI"',
):
    if marker not in workflow:
        raise SystemExit(f"Android staging workflow is missing controlled style selection: {marker}")
if "defaultValue: 'mapbox://styles/mapbox/outdoors-v12'" not in mapbox_viewport:
    raise SystemExit("Production Mapbox style default must remain Outdoors v12.")
if "'MAPBOX_STYLE_URI'" not in mapbox_viewport or "String.fromEnvironment(" not in mapbox_viewport:
    raise SystemExit("Shared Mapbox viewport must accept a compile-time style override.")
if "_logMapboxDiagnostic('STYLE_URI', 'value=$mapboxStyleUri')" not in mapbox_viewport:
    raise SystemExit("Mapbox diagnostic output must identify the selected style URI.")
if "MAPBOX_STYLE_URI=mapbox://styles/mapbox/standard" not in ci_workflow:
    raise SystemExit("CI must compile the diagnostic test with the Standard style override.")

required = (
    "ensure_android_emulator_online.sh",
    'ANDROID_EMULATOR_CI:-false',
    "stabilize_emulator_setup_packages",
    "pm disable-user --user 0",
    "com.google.android.googlesdksetup",
    "ANDROID_EMULATOR_SYSTEM_PACKAGE",
    "adb() {",
    "timeout --foreground --signal=TERM",
    "UIAutomator dump failed or timed out",
    "capture_failure_evidence()",
    "trap 'exit 124' TERM",
    "trap capture_failure_evidence EXIT",
    "dumpsys window windows",
    "mCurrentFocus|mFocusedApp",
    "mResumedActivity|topResumedActivity",
    "MAP_SMOKE_FOREGROUND",
    "verify_android_map_screenshot.py",
    '--foreground-package "${package_name}"',
    "MAPBOX_RENDER_WAIT_SECONDS",
    "MAPBOX_RENDER_READY",
    "MAPBOX_RENDER_NOT_READY",
    "verify_android_map_screen.py",
    "MAPBOX_MAP_PAGE_WAIT",
    "MAPBOX_DIAGNOSTIC event=MAP_LOADED",
    "MAPBOX_DIAGNOSTIC event=MAP_IDLE",
    "MAPBOX_DIAGNOSTIC event=RENDER_FRAME mode=RenderMode.FULL",
)
for marker in ("ANDROID_EMULATOR_CI", "adb_run() {", "timeout --foreground --signal=TERM", "ADB_COMMAND_TIMEOUT_SECONDS", "command -v timeout", "validated_internet=1", "Active default network", "INTERNET", "VALIDATED"):
    if marker not in network_preflight:
        raise SystemExit(f"Android emulator network preflight is missing validation: {marker}")

for marker in required:
    if marker not in source:
        raise SystemExit(f"Android map smoke is missing foreground/render gate: {marker}")

if 'owner == "com.google.android.googlesdksetup"' not in source:
    raise SystemExit("The known Google SDK setup ANR must be closed, not repeatedly dismissed with Wait.")
if source.index("stabilize_emulator_setup_packages") > source.index('adb install -r "${apk_path}"'):
    raise SystemExit("The known setup ANR must be disabled before the app is installed/launched.")
if source.index("verify_android_map_screen.py") > source.index("MAPBOX_RENDER_WAIT_SECONDS"):
    raise SystemExit("The smoke must prove the map page is open before waiting for Mapbox render callbacks.")
for marker in (
    "REQUIRED_CONTROLS",
    "Mapa cartográfico",
    "window_owned_by_",
    "home_page_still_visible",
):
    if marker not in map_screen_verifier:
        raise SystemExit(f"Map page hierarchy verifier is missing: {marker}")
if "label: 'Mapa cartográfico'" not in mapbox_page or "explicitChildNodes: true" not in mapbox_page:
    raise SystemExit("The Mapbox viewport must expose its stable accessibility marker.")
map_screen_test = subprocess.run(
    [sys.executable, str(MAP_SCREEN_VERIFIER), "--self-test"],
    capture_output=True,
    text=True,
    check=False,
)
if map_screen_test.returncode != 0:
    raise SystemExit(f"Map page hierarchy verifier self-test failed: {map_screen_test.stderr}")

ui_dump_body = source.split("ui_dump() {", 1)[1].split("\n}", 1)[0]
if "|| true" in ui_dump_body:
    raise SystemExit("UIAutomator dump failures/timeouts must not be swallowed.")
for marker in (
    'adb shell uiautomator dump "$remote_file"',
    'adb shell cat "$remote_file"',
    "45s",
):
    if marker not in ui_dump_body:
        raise SystemExit(f"UIAutomator must use a bounded device-file capture: {marker}")
if "/dev/tty" in ui_dump_body:
    raise SystemExit("UIAutomator must not write to /dev/tty from a non-interactive adb session.")
if source.index('logcat_file="${RUNNER_TEMP:-/tmp}/espana-outdoor-map-logcat.txt"') > source.index("trap capture_failure_evidence EXIT"):
    raise SystemExit("Failure-evidence paths must be initialized before installing the EXIT trap.")
capture_body = source.split("capture_failure_evidence() {", 1)[1].split("\n}", 1)[0]
for marker in ("adb logcat -d", "ui_dump", "adb exec-out screencap -p"):
    if marker not in capture_body:
        raise SystemExit(f"Failure evidence trap is missing: {marker}")

if "uiautomator) limit=45" not in source or "limit=120" not in source or "limit=180" not in source:
    raise SystemExit("adb wrapper must give UIAutomator, device boot, and APK install explicit bounds.")

screenshot_capture = source.rindex('adb exec-out screencap -p')
if source.index("MAP_SMOKE_FOREGROUND") > screenshot_capture:
    raise SystemExit("Foreground verification must happen before the application screenshot is captured.")
if source.index("verify_android_map_screenshot.py") < screenshot_capture:
    raise SystemExit("Screenshot validation must happen after the application PNG is captured.")
if source.index("verify_android_map_screenshot.py") > source.index('echo "PASS: Mapbox reached a complete idle viewport'):
    raise SystemExit("The smoke must validate the screenshot before reporting PASS.")

if source.index("MAPBOX_RENDER_WAIT_SECONDS") > screenshot_capture:
    raise SystemExit("Mapbox readiness must be polled before capturing the screenshot.")

print("android_map_smoke_foreground_gate=true")
script_dir = 'script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"'
network_call = 'bash "${script_dir}/ensure_android_emulator_online.sh"'
if script_dir not in source or source.index(script_dir) > source.index(network_call):
    raise SystemExit("The smoke script must resolve its own directory before invoking the network preflight.")
launch_call = source.rfind("\nlaunch_app\n\nif test")
if launch_call < 0 or source.index(network_call) > launch_call:
    raise SystemExit("Online network preflight must run before launching the Mapbox smoke.")
smoke_job = workflow.split("- name: Android map native smoke", 1)[1]
smoke_job = smoke_job.split("- name: Upload Android map smoke evidence", 1)[0]
if 'ANDROID_EMULATOR_CI: "true"' not in smoke_job:
    raise SystemExit("The Android map smoke job must explicitly enable the CI emulator network preflight.")
if "timeout-minutes: 25" not in smoke_job:
    raise SystemExit("The Android map smoke action must have an explicit upper time bound.")
if "continue-on-error: true" not in smoke_job:
    raise SystemExit("The smoke step must preserve the job long enough to upload failure evidence.")

AB_RUNNER = ROOT / "tool" / "smoke_android_map_ab.sh"
if not AB_RUNNER.is_file():
    raise SystemExit("The Android map A/B orchestration script is missing.")
ab_runner_source = AB_RUNNER.read_text(encoding="utf-8")
for marker in (
    'primary_apk="${runner_temp}/primary-build/app-release.apk"',
    'standard_apk="${runner_temp}/standard-build/app-release.apk"',
    'RUNNER_TEMP="${primary_evidence}" timeout',
    'RUNNER_TEMP="${standard_evidence}" timeout',
    'primary_status=${primary_status}',
    'standard_manifest="${runner_temp}/standard-build/android-staging-validation.txt"',
    'timeout --foreground --signal=TERM --kill-after=15s 45s adb shell pm clear',
    'if ! grep -Fxq "Success" <<<"${clear_output}"; then',
    'standard_run=${standard_run}',
    'standard_status=${standard_status}',
    '--kill-after=150s 20m',
):
    if marker not in ab_runner_source:
        raise SystemExit(f"Android A/B runner is missing required behavior: {marker}")

script_lines = [
    line.strip()
    for line in smoke_job.split("script:", 1)[1].split("avd-name:", 1)[0].splitlines()
    if line.strip()
]
if script_lines != ['bash tool/smoke_android_map_ab.sh "$RUNNER_TEMP" "$MAPBOX_STYLE_URI"']:
    raise SystemExit(
        "The emulator action script must invoke one checked-in Bash runner command; "
        "multi-line shell variables do not persist between action shell invocations."
    )

# Exercise the orchestration with a stub timeout command. The emulator action
# invokes script lines in separate shells, so all variable state must live in
# the checked-in Bash process, not in the action's multi-line input.
with tempfile.TemporaryDirectory(prefix="mapbox-ab-runner-") as temp_dir:
    temp_root = Path(temp_dir)
    (temp_root / "primary-build").mkdir()
    (temp_root / "standard-build").mkdir()
    (temp_root / "primary-build" / "app-release.apk").write_bytes(b"primary-apk")
    (temp_root / "standard-build" / "app-release.apk").write_bytes(b"standard-apk")
    (temp_root / "primary-build" / "android-staging-validation.txt").write_text(
        "application_id=com.espanaoutdoors.espana_outdoors.iconspreview\n"
        "version_code=5\nsource_commit=test-commit\n"
        "mapbox_style_uri=mapbox://styles/mapbox/outdoors-v12\n",
        encoding="utf-8",
    )
    (temp_root / "standard-build" / "android-staging-validation.txt").write_text(
        "application_id=com.espanaoutdoors.espana_outdoors.iconspreview\n"
        "version_code=5\nsource_commit=test-commit\n"
        "mapbox_style_uri=mapbox://styles/mapbox/standard\n",
        encoding="utf-8",
    )
    fake_bin = temp_root / "bin"
    fake_bin.mkdir()
    call_log = temp_root / "timeout-calls.txt"
    timeout_stub = fake_bin / "timeout"
    timeout_stub.write_text(
        "#!/usr/bin/env bash\n"
        'printf "RUNNER_TEMP=%s\n" "${RUNNER_TEMP:-}" >> "$CALL_LOG"\n'
        'printf "ARGS=%s\n" "$*" >> "$CALL_LOG"\n'
        'if [[ "$*" == *"adb shell pm clear"* ]]; then echo "Success"; exit 0; fi\n'
        'if [[ "${FAIL_PRIMARY:-false}" == "true" && "$*" == *primary-build/app-release.apk* ]]; then exit 7; fi\n'
        "exit 0\n",
        encoding="utf-8",
    )
    timeout_stub.chmod(0o755)
    test_env = os.environ.copy()
    test_env["PATH"] = str(fake_bin) + os.pathsep + test_env.get("PATH", "")
    test_env["CALL_LOG"] = str(call_log)

    successful = subprocess.run(
        ["bash", str(AB_RUNNER), str(temp_root), "mapbox://styles/mapbox/outdoors-v12"],
        capture_output=True,
        text=True,
        env=test_env,
        check=False,
    )
    if successful.returncode != 0 or "standard_run=true" not in successful.stdout:
        raise SystemExit(f"Android A/B runner failed its success-path test: {successful.stderr}")
    calls = call_log.read_text(encoding="utf-8")
    if calls.count("bash tool/smoke_android_map.sh") != 2 or "primary-build/app-release.apk" not in calls or "standard-build/app-release.apk" not in calls:
        raise SystemExit("Android A/B runner did not invoke both APKs in the success-path test.")
    if f"RUNNER_TEMP={temp_root}/primary" not in calls or f"RUNNER_TEMP={temp_root}/standard" not in calls:
        raise SystemExit("Android A/B runner did not isolate primary and Standard evidence directories.")
    if "adb shell pm clear com.espanaoutdoors.espana_outdoors.iconspreview" not in calls:
        raise SystemExit("The A/B runner must clear the shared app data before installing Standard.")

    call_log.write_text("", encoding="utf-8")
    failing_env = test_env.copy()
    failing_env["FAIL_PRIMARY"] = "true"
    failed_primary = subprocess.run(
        ["bash", str(AB_RUNNER), str(temp_root), "mapbox://styles/mapbox/outdoors-v12"],
        capture_output=True,
        text=True,
        env=failing_env,
        check=False,
    )
    calls_after_failure = call_log.read_text(encoding="utf-8")
    if failed_primary.returncode == 0 or calls_after_failure.count("bash tool/smoke_android_map.sh") != 2:
        raise SystemExit("A primary smoke failure must not prevent the Standard comparison from running.")

    (temp_root / "standard-build" / "app-release.apk").unlink()
    call_log.write_text("", encoding="utf-8")
    primary_only = subprocess.run(
        ["bash", str(AB_RUNNER), str(temp_root), "mapbox://styles/mapbox/outdoors-v12"],
        capture_output=True,
        text=True,
        env=test_env,
        check=False,
    )
    if primary_only.returncode != 0 or "standard_run=false" not in primary_only.stdout:
        raise SystemExit("The A/B runner must still support non-PR-79 staging runs without a Standard APK.")
    primary_only_calls = call_log.read_text(encoding="utf-8")
    if primary_only_calls.count("bash tool/smoke_android_map.sh") != 1:
        raise SystemExit("A non-A/B staging run must invoke only the primary APK.")
    if "adb shell pm clear" in primary_only_calls:
        raise SystemExit("A non-A/B staging run must not clear app data for a nonexistent Standard comparison.")

standard_build = workflow.split("- name: Build Mapbox Standard A/B APK", 1)[1]
standard_build = standard_build.split("- name: Upload Android staging APK", 1)[0]
for marker in (
    "github.event.pull_request.number == 79",
    "continue-on-error: true",
    'primary_dir="$RUNNER_TEMP/primary-build"',
    'standard_dir="$RUNNER_TEMP/standard-build"',
    'cp "$primary_apk" "$primary_dir/app-release.apk"',
    'cp build/android-staging-validation.txt "$primary_dir/android-staging-validation.txt"',
    "flutter clean",
    "flutter pub get --enforce-lockfile",
    '--dart-define=MAPBOX_STYLE_URI="mapbox://styles/mapbox/standard"',
    'cp "$standard_apk" "$standard_dir/app-release.apk"',
    'echo "mapbox_style_uri=mapbox://styles/mapbox/standard"',
    'echo "validation_scope=runtime-capable-artifact"',
):
    if marker not in standard_build:
        raise SystemExit(f"Mapbox Standard A/B build is missing: {marker}")
if "--build-dir" in workflow:
    raise SystemExit("Flutter 3.47.5 does not support --build-dir; preserve A/B APKs outside build/ instead.")
if standard_build.index('cp "$primary_apk" "$primary_dir/app-release.apk"') > standard_build.index("flutter clean"):
    raise SystemExit("The verified primary APK must be preserved before flutter clean.")
if standard_build.index("flutter clean") > standard_build.index("flutter pub get --enforce-lockfile"):
    raise SystemExit("A clean Standard build must restore dependencies from the committed lockfile.")

require_standard = workflow.split("- name: Require Mapbox Standard A/B APK", 1)[1]
for marker in (
    "steps.build_standard_apk.outcome",
    'standard_apk="$RUNNER_TEMP/standard-build/app-release.apk"',
    'standard_manifest="$RUNNER_TEMP/standard-build/android-staging-validation.txt"',
    'expected_sha="$(sed -n \'s/^apk_sha256=//p\' "$standard_manifest")"',
    'actual_sha="$(sha256sum "$standard_apk" | cut -d \' \' -f1)"',
    'test "$expected_sha" = "$actual_sha"',
    'grep -Fxq "mapbox_style_uri=mapbox://styles/mapbox/standard" "$standard_manifest"',
):
    if marker not in require_standard:
        raise SystemExit(f"Mapbox Standard A/B artifact verification is missing: {marker}")

apk_upload = workflow.split("- name: Upload Android staging APK", 1)[1]
apk_upload = apk_upload.split("- name: Upload Mapbox Standard A/B APK", 1)[0]
for marker in (
    "${{ runner.temp }}/primary-build/app-release.apk",
    "${{ runner.temp }}/primary-build/android-staging-validation.txt",
):
    if marker not in apk_upload:
        raise SystemExit(f"Primary Android staging artifact upload is missing: {marker}")
if "if: success() && steps.build_apk.outputs.built == 'true'" not in apk_upload:
    raise SystemExit("The primary APK must upload only after its verification step succeeds.")
standard_upload = workflow.split("- name: Upload Mapbox Standard A/B APK", 1)[1]
standard_upload = standard_upload.split("- name: Enable KVM for Android emulator", 1)[0]
for marker in (
    "${{ runner.temp }}/standard-build/app-release.apk",
    "${{ runner.temp }}/standard-build/android-staging-validation.txt",
):
    if marker not in standard_upload:
        raise SystemExit(f"Standard A/B artifact upload is missing: {marker}")
if "if: success() && steps.build_standard_apk.outcome == 'success'" not in standard_upload:
    raise SystemExit("The Standard artifact upload must be conditional on a successful comparison build.")
if "if: success() && steps.build_apk.outputs.built == 'true'" not in workflow:
    raise SystemExit("The primary APK must upload only after its verification step succeeds.")
if "- name: Require Mapbox Standard A/B APK" not in workflow:
    raise SystemExit("The PR #79 comparison build must fail closed when its APK/manifest is missing.")
if "steps.build_standard_apk.outcome != 'skipped'" not in workflow:
    raise SystemExit("The Standard APK requirement must not turn an early cancellation into a false build failure.")

evidence_upload = workflow.split("- name: Upload Android map smoke evidence", 1)[1]
if "if: always()" not in evidence_upload.split("- name: Require Android map native smoke", 1)[0]:
    raise SystemExit("Android smoke evidence must upload even when the smoke command fails.")
require_smoke = workflow.split("- name: Require Android map native smoke", 1)[1]
require_smoke = require_smoke.split("- name: Require Mapbox Standard A/B APK", 1)[0]
for marker in (
    'steps.android_map_smoke.outcome',
    '!= "success"',
    'inspect the uploaded android-map-smoke artifact',
):
    if marker not in require_smoke:
        raise SystemExit(f"Android smoke failure must be enforced after evidence upload: {marker}")

for marker in (
    "${{ runner.temp }}/primary/espana-window-post-map.xml",
    "${{ runner.temp }}/primary/espana-system-dialog.xml",
    "${{ runner.temp }}/primary/espana-map-page-check.txt",
    "${{ runner.temp }}/primary/espana-outdoor-map.png",
    "${{ runner.temp }}/standard/espana-system-dialog.xml",
    "${{ runner.temp }}/standard/espana-map-page-check.txt",
    "${{ runner.temp }}/standard/espana-outdoor-map.png",
    "${{ runner.temp }}/standard/espana-mapbox-diagnostics.txt",
):
    if marker not in evidence_upload:
        raise SystemExit(f"Android smoke evidence upload is missing A/B artifact path: {marker}")

print("android_map_smoke_network_preflight=true")
print("android_map_smoke_render_gate=true")
