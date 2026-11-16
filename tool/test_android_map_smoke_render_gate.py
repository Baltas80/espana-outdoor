#!/usr/bin/env python3
"""Prevent Android map smoke from accepting a live process with a blank viewport."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SMOKE = ROOT / "tool" / "smoke_android_map.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "staging-android.yml"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
NETWORK_PREFLIGHT = ROOT / "tool" / "ensure_android_emulator_online.sh"
MAPBOX_VIEWPORT = ROOT / "lib" / "features" / "map" / "mapbox_map_viewport.dart"
source = SMOKE.read_text(encoding="utf-8")
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

ui_dump_body = source.split("ui_dump() {", 1)[1].split("\n}", 1)[0]
if "|| true" in ui_dump_body:
    raise SystemExit("UIAutomator dump failures/timeouts must not be swallowed.")
if source.index('logcat_file="${RUNNER_TEMP:-/tmp}/espana-outdoor-map-logcat.txt"') > source.index("trap capture_failure_evidence EXIT"):
    raise SystemExit("Failure-evidence paths must be initialized before installing the EXIT trap.")
capture_body = source.split("capture_failure_evidence() {", 1)[1].split("\n}", 1)[0]
for marker in ("adb logcat -d", "ui_dump", "adb exec-out screencap -p"):
    if marker not in capture_body:
        raise SystemExit(f"Failure evidence trap is missing: {marker}")

if "limit=15" not in source or "limit=120" not in source or "limit=180" not in source:
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
if "timeout-minutes: 25" not in smoke_job or "--kill-after=150s 20m bash tool/smoke_android_map.sh" not in smoke_job:
    raise SystemExit("The Android map smoke action and script must have explicit upper time bounds.")

standard_build = workflow.split("- name: Build Mapbox Standard A/B APK", 1)[1]
standard_build = standard_build.split("- name: Upload Android staging APK", 1)[0]
for marker in (
    "github.event.pull_request.number == 79",
    "continue-on-error: true",
    "--build-dir=build/standard",
    '--dart-define=MAPBOX_STYLE_URI="mapbox://styles/mapbox/standard"',
    "build/standard/android-staging-validation.txt",
    "mapbox_runtime_token=available",
    "mapbox_downloads_token=available",
    "mapbox_style_uri=mapbox://styles/mapbox/standard",
):
    if marker not in standard_build:
        raise SystemExit(f"Mapbox Standard A/B build is missing: {marker}")
if "if: success() && steps.build_apk.outputs.built == 'true'" not in workflow:
    raise SystemExit("The primary APK must upload only after its verification step succeeds.")
if "- name: Require Mapbox Standard A/B APK" not in workflow:
    raise SystemExit("The PR #79 comparison build must fail closed when its APK/manifest is missing.")
if "steps.build_standard_apk.outcome != 'skipped'" not in workflow:
    raise SystemExit("The Standard APK requirement must not turn an early cancellation into a false build failure.")

for marker in (
    'RUNNER_TEMP="$RUNNER_TEMP/primary"',
    'RUNNER_TEMP="$RUNNER_TEMP/standard"',
    "primary_status=$?",
    "standard_status=$?",
    "MAPBOX_STYLE_AB primary_style=",
):
    if marker not in smoke_job:
        raise SystemExit(f"Android smoke must execute both styles and retain both results: {marker}")

evidence_upload = workflow.split("- name: Upload Android map smoke evidence", 1)[1]
for marker in (
    "${{ runner.temp }}/primary/espana-outdoor-map.png",
    "${{ runner.temp }}/standard/espana-outdoor-map.png",
    "${{ runner.temp }}/standard/espana-mapbox-diagnostics.txt",
):
    if marker not in evidence_upload:
        raise SystemExit(f"Android smoke evidence upload is missing A/B artifact path: {marker}")

print("android_map_smoke_network_preflight=true")
print("android_map_smoke_render_gate=true")
