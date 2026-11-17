#!/usr/bin/env python3
"""Prevent Android map smoke from accepting a live process with a blank viewport."""

import os
import re
import shlex
import subprocess
import sys
import tempfile
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SMOKE = ROOT / "tool" / "smoke_android_map.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "staging-android.yml"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
NETWORK_PREFLIGHT = ROOT / "tool" / "ensure_android_emulator_online.sh"
MAPBOX_PREFLIGHT = ROOT / "tool" / "preflight_mapbox_tiles.py"
MAPBOX_PREFLIGHT_TEST = ROOT / "tool" / "test_preflight_mapbox_tiles.py"
MAPBOX_VIEWPORT = ROOT / "lib" / "features" / "map" / "mapbox_map_viewport.dart"
MAIN_DART = ROOT / "lib" / "main.dart"
MAPBOX_PAGE = ROOT / "lib" / "features" / "map" / "mapbox_map_page.dart"
MAP_SCREEN_VERIFIER = ROOT / "tool" / "verify_android_map_screen.py"
source = SMOKE.read_text(encoding="utf-8")

# UIAutomator can transiently return success before the device-side hierarchy
# file exists on a cold emulator. Exercise the exact shell function with a
# fake ADB transport: two missing files must retry, then a valid XML succeeds.
ui_dump_block = source.split("ui_dump() {", 1)[1].split("\n}\n\nwindow_file=", 1)[0]
for marker in (
    "for attempt in $(seq 1 4)",
    'adb shell rm -f "${remote_file}"',
    'adb shell test -s "${remote_file}"',
    'adb shell cat "${remote_file}"',
    "ANDROID_UIAUTOMATOR_DUMP",
):
    if marker not in ui_dump_block:
        raise SystemExit(f"UIAutomator hierarchy retry guard is missing: {marker}")
if ui_dump_block.index('adb shell test -s "${remote_file}"') > ui_dump_block.index('adb shell cat "${remote_file}"'):
    raise SystemExit("UIAutomator must verify the remote XML exists before reading it.")
if 'node.attrib.get("clickable") != "true"' not in source or 'desc not in ("Mapa", "Mapa\\nMapa")' not in source:
    raise SystemExit("Android smoke must tap a clickable Mapa navigation node, not its decorative icon.")

ui_dump_harness = r'''set -euo pipefail
state_file="$STATE_FILE"
read_state() {
  read -r dump_calls remote_present < "$state_file"
}
write_state() {
  printf '%s %s\n' "$dump_calls" "$remote_present" > "$state_file"
}
adb() {
  if [[ "$1" == "shell" && "$2" == "rm" ]]; then
    read_state
    remote_present=0
    write_state
    return 0
  fi
  if [[ "$1" == "shell" && "$2" == "uiautomator" ]]; then
    read_state
    dump_calls=$((dump_calls + 1))
    if [[ "$NEVER_CREATE" != "true" && "$dump_calls" -ge 3 ]]; then
      remote_present=1
    fi
    write_state
    if [[ "$NEVER_CREATE" == "true" || "$dump_calls" -lt 3 ]]; then
      return 1
    fi
    return 0
  fi
  if [[ "$1" == "shell" && "$2" == "test" && "$3" == "-s" ]]; then
    read_state
    [[ "$remote_present" == "1" ]]
    return $?
  fi
  if [[ "$1" == "shell" && "$2" == "cat" ]]; then
    read_state
    if [[ "$remote_present" == "1" ]]; then
      printf '<?xml version="1.0"?><hierarchy></hierarchy>'
      return 0
    fi
    return 1
  fi
  echo "unexpected adb args: $*" >&2
  return 99
}
sleep() { :; }
'''
ui_dump_script = (
    ui_dump_harness
    + "ui_dump() {"
    + ui_dump_block
    + "\n}\nread -r dump_calls remote_present < \"$STATE_FILE\"\n"
    + "if ui_dump \"$1\"; then read -r dump_calls remote_present < \"$STATE_FILE\"; "
    + "echo \"UI_DUMP_RESULT=success dump_calls=$dump_calls remote_present=$remote_present\"; "
    + "else read -r dump_calls remote_present < \"$STATE_FILE\"; "
    + "echo \"UI_DUMP_RESULT=failure dump_calls=$dump_calls remote_present=$remote_present\"; exit 17; fi\n"
)
with tempfile.TemporaryDirectory(prefix="android-uiautomator-retry-") as directory:
    hierarchy = Path(directory) / "hierarchy.xml"
    state_file = Path(directory) / "state.txt"
    state_file.write_text("0 0\n", encoding="utf-8")
    recovered_env = {**os.environ, "STATE_FILE": str(state_file), "NEVER_CREATE": "false"}
    recovered = subprocess.run(
        ["bash", "-c", ui_dump_script, "--", str(hierarchy)],
        capture_output=True,
        text=True,
        env=recovered_env,
        check=False,
    )
    if recovered.returncode != 0 or "UI_DUMP_RESULT=success dump_calls=3 remote_present=1" not in recovered.stdout:
        raise SystemExit(f"UIAutomator retry did not recover after two transient misses: {recovered.stdout} {recovered.stderr}")
    if "<hierarchy" not in hierarchy.read_text(encoding="utf-8"):
        raise SystemExit("UIAutomator retry accepted no valid hierarchy XML.")

    state_file.write_text("0 0\n", encoding="utf-8")
    never_created_env = {**recovered_env, "NEVER_CREATE": "true"}
    never_created = subprocess.run(
        ["bash", "-c", ui_dump_script, "--", str(hierarchy)],
        capture_output=True,
        text=True,
        env=never_created_env,
        check=False,
    )
    if never_created.returncode != 17 or "UI_DUMP_RESULT=failure dump_calls=4 remote_present=0" not in never_created.stdout:
        raise SystemExit("UIAutomator retry must fail closed after four missing hierarchy files.")
if not MAPBOX_PAGE.is_file():
    raise SystemExit("Android map smoke requires the main Mapbox page.")
mapbox_page = MAPBOX_PAGE.read_text(encoding="utf-8")
if not MAP_SCREEN_VERIFIER.is_file():
    raise SystemExit("Android map smoke requires the actual map-page hierarchy verifier.")
map_screen_verifier = MAP_SCREEN_VERIFIER.read_text(encoding="utf-8")
if not MAPBOX_VIEWPORT.is_file():
    raise SystemExit("Android map smoke requires the shared Mapbox viewport.")
mapbox_viewport = MAPBOX_VIEWPORT.read_text(encoding="utf-8")
if not MAIN_DART.is_file():
    raise SystemExit("Android staging TileStore diagnostic requires the application entry point.")
main_dart = MAIN_DART.read_text(encoding="utf-8")
for marker in (
    "MAPBOX_TILE_STORE_USAGE_MODE",
    "MapboxMapsOptions.setTileStoreUsageMode(TileStoreUsageMode.DISABLED)",
    "MapboxMapsOptions.setTileStoreUsageMode(TileStoreUsageMode.READ_ONLY)",
    "MapboxMapsOptions.getTileStoreUsageMode()",
    "effective=${effectiveMode.name.toLowerCase()}",
    "await _configureMapboxTileStoreUsage();",
    "_appEnvironment == 'staging'",
    "TargetPlatform.android",
):
    if marker not in main_dart:
        raise SystemExit(f"Android staging TileStore mode guard is missing: {marker}")
if main_dart.index("await _configureMapboxTileStoreUsage();") > main_dart.index("runApp("):
    raise SystemExit("TileStore mode must be configured before any Mapbox API object is created.")
if "snapshotter!.style" in mapbox_viewport:
    raise SystemExit("Snapshotter diagnostics must use the direct v3 style API.")
for marker in (
    "Future<void> _inspectLoadedStyle()",
    "map.getStyleJSON()",
    "map.getSize()",
    "map.getCameraState()",
    "map.isStyleLoaded()",
    "MAPBOX_STYLE_INSPECTION",
    "background_layer_count=",
    "unawaited(_inspectLoadedStyle())",
    "import 'dart:ui' as ui;",
    "ui.ImageFilter.isShaderFilterSupported",
    "_logMapboxDiagnostic('FLUTTER_RENDERER', 'backend=$renderer')",
    "mapbox.Snapshotter.create(",
    "mapbox.MapSnapshotOptions(",
    "setStyleJSON(styleJson)",
    "mapboxSnapshotterVectorStyleJson()",
    "mapbox://mapbox.mapbox-streets-v8",
    "'source-layer': 'road'",
    "mapboxStyleDiagnosticsJson(rawStyleJson)",
    "mapboxSnapshotterDiagnosticsEnabled",
    "MAPBOX_SNAPSHOTTER_DIAGNOSTICS",
    "reason=map_widget_isolation",
    "'SNAPSHOTTER_STAGE'",
    "logSnapshotterStage('create_started')",
    "logSnapshotterStage('create_completed')",
    "label + '_capture_completed'",
    ".timeout(const Duration(seconds: 30))",
    ".timeout(const Duration(seconds: 15))",
    "activeSnapshotter.dispose().timeout(const Duration(seconds: 10))",
    "MAPBOX_SNAPSHOTTER_PNG",
    "MAPBOX_SNAPSHOTTER_VECTOR_PNG",
    "prefix + '_CHUNK index='",
    "sha256.convert(png)",
):
    if marker not in mapbox_viewport:
        raise SystemExit(f"Mapbox style inspection is missing: {marker}")
SKIA_PREPARE = ROOT / "tool" / "prepare_android_skia_ab.py"
if not SKIA_PREPARE.is_file():
    raise SystemExit("The Android Skia A/B manifest preparation helper is missing.")
skia_prepare_test = subprocess.run(
    [sys.executable, str(SKIA_PREPARE), "--self-test"],
    capture_output=True,
    text=True,
    check=False,
)
if skia_prepare_test.returncode != 0:
    raise SystemExit(f"Android Skia A/B manifest self-test failed: {skia_prepare_test.stderr}")

SNAPSHOTTER_EXTRACTOR = ROOT / "tool" / "extract_mapbox_snapshotter_png.py"
if not SNAPSHOTTER_EXTRACTOR.is_file():
    raise SystemExit("The Mapbox Snapshotter logcat extractor is missing.")
snapshotter_test = subprocess.run(
    [sys.executable, str(SNAPSHOTTER_EXTRACTOR), "--self-test"],
    capture_output=True,
    text=True,
    check=False,
)
if snapshotter_test.returncode != 0:
    raise SystemExit(f"Mapbox Snapshotter extractor self-test failed: {snapshotter_test.stderr}")
if "extract_mapbox_snapshotter_png.py" not in source:
    raise SystemExit("Android smoke must attempt to extract the native Snapshotter PNG.")
if "--kind baseline" not in source or "--kind vector" not in source:
    raise SystemExit("Android smoke must extract both baseline and vector Snapshotter captures.")
if "espana-mapbox-snapshotter-vector.png" not in source:
    raise SystemExit("Android smoke must preserve the vector Snapshotter PNG separately.")
if source.rfind("extract_mapbox_snapshotter_png.py") > source.rfind('adb exec-out screencap -p'):
    raise SystemExit("Snapshotter evidence must be extracted from logcat before the smoke exits.")
if 'snapshotter_mode="${3:-disabled}"' not in source:
    raise SystemExit("Android MapWidget A/B smoke must default to Snapshotter-disabled isolation.")
if 'MAPBOX_SNAPSHOTTER_DIAGNOSTIC skipped=true reason=map_widget_isolation' not in source:
    raise SystemExit("Android smoke must explicitly report when Snapshotter is skipped.")
if 'if [[ "${snapshotter_mode}" == "enabled" ]]; then' not in source:
    raise SystemExit("Snapshotter evidence collection must remain available as an explicit opt-in.")
snapshotter_wait_block = source.split("snapshotter_wait_seconds=", 1)[1].split('adb logcat -d >"${logcat_file}"', 1)[0]
for marker in (
    "MAPBOX_SNAPSHOTTER_WAIT_SECONDS",
    "MAPBOX_DIAGNOSTIC event=SNAPSHOTTER_STAGE stage=(disposed|failed|dispose_failed)",
    "MAPBOX_SNAPSHOTTER_TERMINAL_WAIT",
    "snapshotter_terminal=true",
):
    if marker not in snapshotter_wait_block:
        raise SystemExit(f"Opt-in Snapshotter capture must wait for terminal evidence: {marker}")
if source.index("snapshotter_wait_seconds=") > source.rindex('adb logcat -d >"${logcat_file}"'):
    raise SystemExit("Opt-in Snapshotter completion must precede the final logcat dump.")

if not NETWORK_PREFLIGHT.is_file():
    raise SystemExit("Android map smoke references a missing emulator network preflight script.")
network_preflight = NETWORK_PREFLIGHT.read_text(encoding="utf-8")
if not MAPBOX_PREFLIGHT.is_file() or not MAPBOX_PREFLIGHT_TEST.is_file():
    raise SystemExit("Android staging requires the Mapbox style/vector-tile preflight and its tests.")
preflight_test = subprocess.run(
    [sys.executable, str(MAPBOX_PREFLIGHT_TEST)],
    capture_output=True,
    text=True,
    check=False,
)
if preflight_test.returncode != 0:
    raise SystemExit(f"Mapbox token preflight tests failed: {preflight_test.stdout} {preflight_test.stderr}")
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
if "timeout-minutes: 105" not in android_job:
    raise SystemExit("Android staging job must allow three APK builds and the bounded A/B smoke to finish.")

# The renderer APK metadata parser must stay byte-for-byte aligned with the
# primary parser. A prior extra escape made sed fail after a successful build,
# so the comparison APK was never preserved or installed.
primary_build_block = android_job.split("- name: Build Android staging APK", 1)[1].split("- name: Verify APK", 1)[0]
renderer_build_block = android_job.split("- name: Build Mapbox Skia comparison APK (Impeller disabled)", 1)[1].split("- name: Upload Android staging APK", 1)[0]
primary_metadata_lines = []
renderer_metadata_lines = []
for key in ("application_id", "version_code", "version_name"):
    prefix = f'{key}="$(sed -n '
    primary_line = next((line.strip() for line in primary_build_block.splitlines() if line.strip().startswith(prefix)), None)
    renderer_line = next((line.strip() for line in renderer_build_block.splitlines() if line.strip().startswith(prefix)), None)
    if primary_line is None or renderer_line is None:
        raise SystemExit(f"Android APK metadata parser is missing {key}.")
    if primary_line != renderer_line:
        raise SystemExit(f"Renderer APK {key} parser must match the verified primary parser exactly.")
    primary_metadata_lines.append(primary_line)

badging_fixture = "package: name='com.example.app' versionCode='42' versionName='1.2.3' platformBuildVersionName='15'"
metadata_script = (
    f"badging={shlex.quote(badging_fixture)}\n"
    + "\n".join(primary_metadata_lines)
    + '\nprintf "%s\t%s\t%s\n" "$application_id" "$version_code" "$version_name"\n'
)
metadata_result = subprocess.run(["bash", "-c", metadata_script], capture_output=True, text=True, check=False)
if metadata_result.returncode != 0 or metadata_result.stdout != "com.example.app\t42\t1.2.3\n":
    raise SystemExit(
        "Android APK metadata parser failed its aapt badging fixture: "
        + (metadata_result.stderr or metadata_result.stdout)
    )
if "cancel-in-progress: true" not in workflow.split("concurrency:", 1)[1].split("permissions:", 1)[0]:
    raise SystemExit("A newer Android staging commit must supersede queued stale runs on the same branch.")

# Style A/B is staging-only. The normal workflow_dispatch default and
# production MapWidget default remain Outdoors; PR #79 automatically runs a
# Standard-only diagnostic so the style itself is isolated from the renderer.
for marker in (
    "mapbox_style_variant",
    "type: choice",
    "default: outdoors-v12",
    "android_view_mode",
    "inputs.android_view_mode == 'virtual-texture'",
    "MAPBOX_ANDROID_VIEW_MODE:",
    "virtual-texture",
    "inputs.mapbox_style_variant == 'standard'",
    "github.event_name == 'pull_request' && github.event.pull_request.number == 79",
    "mapbox://styles/mapbox/standard",
    "mapbox://styles/mapbox/outdoors-v12",
    '--dart-define=MAPBOX_STYLE_URI="$MAPBOX_STYLE_URI"',
    'echo "mapbox_style_uri=$MAPBOX_STYLE_URI"',
):
    if marker not in workflow:
        raise SystemExit(f"Android staging workflow is missing controlled style selection: {marker}")
skia_step = workflow.split(
    "- name: Build Mapbox Skia comparison APK (Impeller disabled)", 1
)[1].split("\n      - name:", 1)[0]
if "env.MAPBOX_STYLE_URI == 'mapbox://styles/mapbox/outdoors-v12'" not in skia_step:
    raise SystemExit("The Skia comparison APK must remain limited to the Outdoors experiment.")

tile_store_step = workflow.split(
    "- name: Build Mapbox TileStore-disabled diagnostic APK", 1
)[1].split("\n      - name:", 1)[0]
if "env.MAPBOX_STYLE_URI ==" in tile_store_step:
    raise SystemExit("The TileStore-disabled diagnostic must also run for imported Mapbox Standard styles.")

if "defaultValue: 'mapbox://styles/mapbox/outdoors-v12'" not in mapbox_viewport:
    raise SystemExit("Production Mapbox style default must remain Outdoors v12.")
if "'MAPBOX_STYLE_URI'" not in mapbox_viewport or "String.fromEnvironment(" not in mapbox_viewport:
    raise SystemExit("Shared Mapbox viewport must accept a compile-time style override.")
if "_logMapboxDiagnostic('STYLE_URI', 'value=$mapboxStyleUri')" not in mapbox_viewport:
    raise SystemExit("Mapbox diagnostic output must identify the selected style URI.")
if "MAPBOX_STYLE_URI=mapbox://styles/mapbox/standard" not in ci_workflow:
    raise SystemExit("CI must compile the diagnostic test with the Standard style override.")
if "tool/preflight_mapbox_tiles.py --style-uri \"$MAPBOX_STYLE_URI\"" not in workflow:
    raise SystemExit("Android staging must preflight the selected Mapbox style and vector-tile endpoint.")
if "python3 tool/test_preflight_mapbox_tiles.py" not in workflow:
    raise SystemExit("Android staging must execute the Mapbox preflight unit tests before building.")

# The native offline TileStore descriptor uses Android display density. The
# live MapWidget must request the same pixel-ratio variant instead of relying
# on MapOptions' 1.0 default.
for marker in (
    "MapOptions mapboxMapOptionsForPixelRatio(double pixelRatio)",
    "MediaQuery.devicePixelRatioOf(context)",
    "mapOptions: mapboxMapOptionsForPixelRatio(devicePixelRatio)",
    "GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY",
):
    if marker not in mapbox_viewport:
        raise SystemExit(f"Mapbox MapOptions must stay aligned with the offline TileStore: {marker}")

for marker in (
    "MAPBOX_ANDROID_VIEW_MODE",
    "mapboxAndroidViewConfiguration(String mode)",
    "AndroidPlatformViewHostingMode.HC",
    "AndroidPlatformViewHostingMode.VD",
    "textureView: androidView.textureView",
    "androidHostingMode: androidView.hostingMode",
):
    if marker not in mapbox_viewport:
        raise SystemExit(f"Mapbox Android hosting mode must be explicit and testable: {marker}")

required = (
    "ensure_android_emulator_online.sh",
    'ANDROID_EMULATOR_CI:-false',
    "stabilize_emulator_setup_packages",
    "pm disable-user --user 0",
    "com.google.android.googlesdksetup",
    "ANDROID_EMULATOR_SYSTEM_PACKAGE",
    "adb() {",
    "timeout --foreground --signal=TERM",
    "UIAutomator did not produce a readable hierarchy after 4 bounded attempts.",
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

logcat_reset_block = source.split("adb wait-for-device", 1)[1].split('adb install -r', 1)[0]
if "adb logcat -c" not in logcat_reset_block:
    raise SystemExit("Each Android smoke must clear logcat before installing its APK so A/B evidence is isolated.")

ui_dump_body = source.split("ui_dump() {", 1)[1].split("\n}", 1)[0]
for marker in (
    "set +e",
    "dump_status=$?",
    "set -e",
    "command_status=${dump_status}",
):
    if marker not in ui_dump_body:
        raise SystemExit(f"UIAutomator must preserve command status while retrying: {marker}")
for marker in (
    'adb shell uiautomator dump "${remote_file}"',
    'adb shell cat "${remote_file}"',
):
    if marker not in ui_dump_body:
        raise SystemExit(f"UIAutomator must use a bounded device-file capture: {marker}")
if "uiautomator) limit=45" not in source:
    raise SystemExit("UIAutomator device capture must retain its 45-second adb timeout.")
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
if "timeout-minutes: 55" not in smoke_job:
    raise SystemExit("The Android map smoke action must allow both bounded Standard/TileStore variants to finish.")
if "continue-on-error: true" not in smoke_job:
    raise SystemExit("The smoke step must preserve the job long enough to upload failure evidence.")

AB_RUNNER = ROOT / "tool" / "smoke_android_map_ab.sh"
if not AB_RUNNER.is_file():
    raise SystemExit("The Android map renderer A/B orchestration script is missing.")
ab_runner_source = AB_RUNNER.read_text(encoding="utf-8")
for marker in (
    'primary_apk="${runner_temp}/primary-build/app-release.apk"',
    'renderer_apk="${runner_temp}/skia-build/app-release.apk"',
    'tile_store_disabled_apk="${runner_temp}/tile-store-disabled-build/app-release.apk"',
    'RUNNER_TEMP="${tile_store_disabled_evidence}" timeout',
    'bash tool/smoke_android_map.sh "${primary_apk}" online disabled',
    'bash tool/smoke_android_map.sh "${renderer_apk}" online disabled',
    'bash tool/smoke_android_map.sh "${tile_store_disabled_apk}" online disabled',
    'MAPBOX_TILE_STORE_USAGE requested=disabled effective=disabled',
    'diagnostic_tile_store_mode',
    'RUNNER_TEMP="${primary_evidence}" timeout',
    'RUNNER_TEMP="${renderer_evidence}" timeout',
    'primary_status=${primary_status}',
    'renderer_manifest="${runner_temp}/skia-build/android-staging-validation.txt"',
    'timeout --foreground --signal=TERM --kill-after=15s 45s adb shell pm clear',
    'if ! grep -Fxq "Success" <<<"${clear_output}"; then',
    'comparison_run=${renderer_run}',
    'comparison_status=${renderer_status}',
    'comparison_mode=${renderer_view_mode}',
    'primary_mode=${primary_view_mode}',
    'MAPBOX_ANDROID_VIEW mode=${primary_view_mode}',
    'MAPBOX_ANDROID_VIEW_MODE_AB primary_mode=${primary_view_mode}',
    'virtual-texture',
    'primary_renderer=impeller',
    'MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=impeller',
    'MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=skia',
    'grep -Fq "MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=impeller" "${diagnostic_logcat}"',
    'tile_store_renderer_status=',
    '--kill-after=150s 20m',
):
    if marker not in ab_runner_source:
        raise SystemExit(f"Android renderer A/B runner is missing required behavior: {marker}")

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

# Exercise the orchestration with a stub timeout command. Both APKs must use
# the same style and source commit; only Android platform-view hosting differs.
with tempfile.TemporaryDirectory(prefix="mapbox-renderer-ab-runner-") as temp_dir:
    temp_root = Path(temp_dir)
    (temp_root / "primary-build").mkdir()
    (temp_root / "skia-build").mkdir()
    (temp_root / "primary-build" / "app-release.apk").write_bytes(b"primary-apk")
    (temp_root / "skia-build" / "app-release.apk").write_bytes(b"renderer-apk")
    (temp_root / "primary-build" / "android-staging-validation.txt").write_text(
        "application_id=com.espanaoutdoors.espana_outdoors.iconspreview\n"
        "version_code=5\nsource_commit=test-commit\n"
        "mapbox_style_uri=mapbox://styles/mapbox/outdoors-v12\n"
        "mapbox_android_view_mode=hybrid-surface\n"
        "flutter_renderer=impeller-default\nimpeller_enabled=default\n"
        "mapbox_tile_store_usage_mode=default\n"
        "mapbox_snapshotter_diagnostics=false\n",
        encoding="utf-8",
    )
    (temp_root / "skia-build" / "android-staging-validation.txt").write_text(
        "application_id=com.espanaoutdoors.espana_outdoors.iconspreview\n"
        "version_code=5\nsource_commit=test-commit\n"
        "mapbox_style_uri=mapbox://styles/mapbox/outdoors-v12\n"
        "mapbox_android_view_mode=hybrid-surface\n"
        "flutter_renderer=skia-optout\nimpeller_enabled=false\n"
        "mapbox_tile_store_usage_mode=default\n"
        "mapbox_snapshotter_diagnostics=false\n",
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
        'if [[ "$*" == *"bash tool/smoke_android_map.sh"* ]]; then\n'
        '  mkdir -p "$RUNNER_TEMP"\n'
        '  if [[ "$RUNNER_TEMP" == */primary ]]; then\n'
        '    printf "%s\\n" "MAPBOX_ANDROID_VIEW mode=${VIEW_MODE:-hybrid-surface}" "MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=impeller" "MAPBOX_TILE_STORE_USAGE requested=default effective=read_only" > "$RUNNER_TEMP/espana-outdoor-map-logcat.txt"\n'
        '  elif [[ "$RUNNER_TEMP" == */tile-store-disabled ]]; then\n'
        '    if [[ "${FAIL_TILE_STORE_RENDERER:-false}" == "true" ]]; then\n'
        '      printf "%s\\n" "MAPBOX_ANDROID_VIEW mode=${VIEW_MODE:-hybrid-surface}" "MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=skia" "MAPBOX_TILE_STORE_USAGE requested=disabled effective=disabled" > "$RUNNER_TEMP/espana-outdoor-map-logcat.txt"\n'
        '    else\n'
        '      printf "%s\\n" "MAPBOX_ANDROID_VIEW mode=${VIEW_MODE:-hybrid-surface}" "MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=impeller" "MAPBOX_TILE_STORE_USAGE requested=disabled effective=disabled" > "$RUNNER_TEMP/espana-outdoor-map-logcat.txt"\n'
        '    fi\n'
        '  elif [[ "${FAIL_SKIA_DIAGNOSTIC:-false}" == "true" ]]; then\n'
        '    printf "%s\\n" "MAPBOX_ANDROID_VIEW mode=${VIEW_MODE:-hybrid-surface}" "MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=impeller" "MAPBOX_TILE_STORE_USAGE requested=default effective=read_only" > "$RUNNER_TEMP/espana-outdoor-map-logcat.txt"\n'
        '  else\n'
        '    printf "%s\\n" "MAPBOX_ANDROID_VIEW mode=${VIEW_MODE:-hybrid-surface}" "MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=skia" "MAPBOX_TILE_STORE_USAGE requested=default effective=read_only" > "$RUNNER_TEMP/espana-outdoor-map-logcat.txt"\n'
        '  fi\n'
        'fi\n'
        'if [[ "$*" == *"adb shell pm clear"* ]]; then echo "Success"; exit 0; fi\n'
        'if [[ "${FAIL_PRIMARY:-false}" == "true" && "$*" == *primary-build/app-release.apk* ]]; then exit 7; fi\n'
        'if [[ "${FAIL_RENDERER:-false}" == "true" && "$*" == *skia-build/app-release.apk* ]]; then exit 8; fi\n'
        'if [[ "${FAIL_TILE_STORE:-false}" == "true" && "$*" == *tile-store-disabled-build/app-release.apk* ]]; then exit 9; fi\n'
        "exit 0\n",
        encoding="utf-8",
    )
    timeout_stub.chmod(0o755)
    test_env = os.environ.copy()
    test_env["PATH"] = str(fake_bin) + os.pathsep + test_env.get("PATH", "")
    test_env["CALL_LOG"] = str(call_log)
    test_env["VIEW_MODE"] = "hybrid-surface"

    successful = subprocess.run(
        ["bash", str(AB_RUNNER), str(temp_root), "mapbox://styles/mapbox/outdoors-v12"],
        capture_output=True,
        text=True,
        env=test_env,
        check=False,
    )
    if successful.returncode != 0 or "comparison_run=true" not in successful.stdout:
        raise SystemExit(f"Android Skia A/B runner failed its success-path test: {successful.stderr}")
    if "primary_renderer=impeller" not in successful.stdout or "comparison_renderer=skia" not in successful.stdout:
        raise SystemExit("Android Skia A/B runner did not prove the two runtime renderers.")
    calls = call_log.read_text(encoding="utf-8")
    if calls.count("bash tool/smoke_android_map.sh") != 2 or "primary-build/app-release.apk" not in calls or "skia-build/app-release.apk" not in calls:
        raise SystemExit("Android renderer A/B runner did not invoke both APKs in the success-path test.")
    if f"RUNNER_TEMP={temp_root}/primary" not in calls or f"RUNNER_TEMP={temp_root}/skia" not in calls:
        raise SystemExit("Android renderer A/B runner did not isolate primary and comparison evidence directories.")
    if "adb shell pm clear com.espanaoutdoors.espana_outdoors.iconspreview" not in calls:
        raise SystemExit("The Skia A/B runner must clear app data before installing the comparison APK.")

    # Verify the A/B harness with Virtual Display + TextureView.
    for manifest_path in (
        temp_root / "primary-build" / "android-staging-validation.txt",
        temp_root / "skia-build" / "android-staging-validation.txt",
    ):
        manifest_text = manifest_path.read_text(encoding="utf-8")
        manifest_path.write_text(
            manifest_text.replace(
                "mapbox_android_view_mode=hybrid-surface",
                "mapbox_android_view_mode=virtual-texture",
            ),
            encoding="utf-8",
        )
    virtual_env = test_env.copy()
    virtual_env["VIEW_MODE"] = "virtual-texture"
    virtual_texture = subprocess.run(
        ["bash", str(AB_RUNNER), str(temp_root), "mapbox://styles/mapbox/outdoors-v12"],
        capture_output=True,
        text=True,
        env=virtual_env,
        check=False,
    )
    if (
        virtual_texture.returncode != 0
        or "primary_mode=virtual-texture" not in virtual_texture.stdout
        or "comparison_mode=virtual-texture" not in virtual_texture.stdout
        or "identity_status=0" not in virtual_texture.stdout
    ):
        raise SystemExit(
            f"Android A/B runner did not validate Virtual Display/TextureView mode: "
            f"{virtual_texture.stdout} {virtual_texture.stderr}"
        )
    for manifest_path in (
        temp_root / "primary-build" / "android-staging-validation.txt",
        temp_root / "skia-build" / "android-staging-validation.txt",
    ):
        manifest_text = manifest_path.read_text(encoding="utf-8")
        manifest_path.write_text(
            manifest_text.replace(
                "mapbox_android_view_mode=virtual-texture",
                "mapbox_android_view_mode=hybrid-surface",
            ),
            encoding="utf-8",
        )

    mismatch_env = test_env.copy()
    mismatch_env["FAIL_SKIA_DIAGNOSTIC"] = "true"
    mismatched = subprocess.run(
        ["bash", str(AB_RUNNER), str(temp_root), "mapbox://styles/mapbox/outdoors-v12"],
        capture_output=True,
        text=True,
        env=mismatch_env,
        check=False,
    )
    if mismatched.returncode == 0 or "renderer_identity_status=1" not in mismatched.stdout:
        raise SystemExit("The Skia A/B runner must reject a comparison APK that still reports Impeller.")

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
        raise SystemExit("A primary smoke failure must not prevent the renderer comparison from running.")

    call_log.write_text("", encoding="utf-8")
    failing_renderer_env = test_env.copy()
    failing_renderer_env["FAIL_RENDERER"] = "true"
    failed_renderer = subprocess.run(
        ["bash", str(AB_RUNNER), str(temp_root), "mapbox://styles/mapbox/outdoors-v12"],
        capture_output=True,
        text=True,
        env=failing_renderer_env,
        check=False,
    )
    if failed_renderer.returncode == 0:
        raise SystemExit("A renderer comparison failure must fail the A/B smoke.")

    (temp_root / "tile-store-disabled-build").mkdir()
    (temp_root / "tile-store-disabled-build" / "app-release.apk").write_bytes(b"tile-store-disabled-apk")
    (temp_root / "tile-store-disabled-build" / "android-staging-validation.txt").write_text(
        "application_id=com.espanaoutdoors.espana_outdoors.iconspreview\n"
        "version_code=5\nsource_commit=test-commit\n"
        "mapbox_style_uri=mapbox://styles/mapbox/outdoors-v12\n"
        "mapbox_android_view_mode=hybrid-surface\n"
        "flutter_renderer=impeller-default\nimpeller_enabled=default\n"
        "mapbox_tile_store_usage_mode=disabled\n"
        "mapbox_snapshotter_diagnostics=false\n"
        "validation_scope=diagnostic-only-tile-store-disabled\n",
        encoding="utf-8",
    )
    failing_tile_store_renderer_env = test_env.copy()
    failing_tile_store_renderer_env["FAIL_TILE_STORE_RENDERER"] = "true"
    failed_tile_store_renderer = subprocess.run(
        ["bash", str(AB_RUNNER), str(temp_root), "mapbox://styles/mapbox/outdoors-v12"],
        capture_output=True,
        text=True,
        env=failing_tile_store_renderer_env,
        check=False,
    )
    if failed_tile_store_renderer.returncode == 0 or "renderer_identity_status=1" not in failed_tile_store_renderer.stdout:
        raise SystemExit("The TileStore-disabled A/B must reject a Skia APK after the manifest is restored.")

    shutil.rmtree(temp_root / "tile-store-disabled-build")

    (temp_root / "skia-build" / "app-release.apk").unlink()
    call_log.write_text("", encoding="utf-8")
    primary_only = subprocess.run(
        ["bash", str(AB_RUNNER), str(temp_root), "mapbox://styles/mapbox/outdoors-v12"],
        capture_output=True,
        text=True,
        env=test_env,
        check=False,
    )
    if primary_only.returncode != 0 or "comparison_run=false" not in primary_only.stdout:
        raise SystemExit("The renderer A/B runner must support staging runs without a comparison APK.")
    primary_only_calls = call_log.read_text(encoding="utf-8")
    if primary_only_calls.count("bash tool/smoke_android_map.sh") != 1:
        raise SystemExit("A non-A/B staging run must invoke only the primary APK.")
    if "adb shell pm clear" in primary_only_calls:
        raise SystemExit("A non-A/B staging run must not clear app data without a comparison APK.")
    # Exercise the exact PR #79 Standard + Virtual Display/TextureView diagnostic.
    # The primary and diagnostic APKs must differ only in TileStore usage.
    primary_manifest_path = temp_root / "primary-build" / "android-staging-validation.txt"
    primary_manifest_text = primary_manifest_path.read_text(encoding="utf-8")
    primary_manifest_text = primary_manifest_text.replace(
        "mapbox_style_uri=mapbox://styles/mapbox/outdoors-v12",
        "mapbox_style_uri=mapbox://styles/mapbox/standard",
    ).replace(
        "mapbox_android_view_mode=hybrid-surface",
        "mapbox_android_view_mode=virtual-texture",
    )
    primary_manifest_path.write_text(primary_manifest_text, encoding="utf-8")

    tile_store_dir = temp_root / "tile-store-disabled-build"
    tile_store_dir.mkdir()
    (tile_store_dir / "app-release.apk").write_bytes(b"tile-store-disabled-apk")
    (tile_store_dir / "android-staging-validation.txt").write_text(
        "application_id=com.espanaoutdoors.espana_outdoors.iconspreview\\n"
        "version_code=5\\nsource_commit=test-commit\\n"
        "mapbox_style_uri=mapbox://styles/mapbox/standard\\n"
        "mapbox_android_view_mode=virtual-texture\\n"
        "flutter_renderer=impeller-default\\nimpeller_enabled=default\\n"
        "mapbox_tile_store_usage_mode=disabled\\n"
        "mapbox_snapshotter_diagnostics=false\\n"
        "validation_scope=diagnostic-only-tile-store-disabled\\n",
        encoding="utf-8",
    )
    standard_env = test_env.copy()
    standard_env["VIEW_MODE"] = "virtual-texture"
    call_log.write_text("", encoding="utf-8")
    tile_store_run = subprocess.run(
        ["bash", str(AB_RUNNER), str(temp_root), "mapbox://styles/mapbox/standard"],
        capture_output=True,
        text=True,
        env=standard_env,
        check=False,
    )
    tile_store_calls = call_log.read_text(encoding="utf-8")
    if tile_store_run.returncode != 0 or "diagnostic_run=true" not in tile_store_run.stdout:
        raise SystemExit(f"TileStore-disabled Standard A/B runner failed its success-path test: {tile_store_run.stderr}")
    if "primary_mode=virtual-texture" not in tile_store_run.stdout or "diagnostic_mode=virtual-texture" not in tile_store_run.stdout or "identity_status=0" not in tile_store_run.stdout:
        raise SystemExit("Standard TileStore A/B must preserve Virtual Display/TextureView in both APKs.")
    if tile_store_calls.count("bash tool/smoke_android_map.sh") != 2:
        raise SystemExit("TileStore-disabled A/B must run primary and diagnostic APKs exactly once.")
    if f"RUNNER_TEMP={temp_root}/tile-store-disabled" not in tile_store_calls:
        raise SystemExit("TileStore-disabled evidence must use an isolated directory.")
    diagnostic_log = (temp_root / "tile-store-disabled" / "espana-outdoor-map-logcat.txt").read_text(encoding="utf-8")
    if "MAPBOX_TILE_STORE_USAGE requested=disabled effective=disabled" not in diagnostic_log:
        raise SystemExit("TileStore-disabled A/B did not verify the runtime usage mode.")
    failing_tile_store_env = standard_env.copy()
    failing_tile_store_env["FAIL_TILE_STORE"] = "true"
    failed_tile_store = subprocess.run(
        ["bash", str(AB_RUNNER), str(temp_root), "mapbox://styles/mapbox/standard"],
        capture_output=True,
        text=True,
        env=failing_tile_store_env,
        check=False,
    )
    if failed_tile_store.returncode == 0:
            raise SystemExit("A TileStore-disabled diagnostic failure must fail the A/B smoke.")

prepare_primary = workflow.split("- name: Preserve verified primary Android staging APK", 1)[1]
prepare_primary = prepare_primary.split("- name: Build Mapbox Skia comparison APK (Impeller disabled)", 1)[0]
for marker in (
    "steps.build_apk.outputs.built == 'true'",
    'primary_dir="$RUNNER_TEMP/primary-build"',
    'cp "$apk" "$primary_dir/app-release.apk"',
    'cp "$manifest" "$primary_dir/android-staging-validation.txt"',
    'test "$expected_sha" = "$actual_sha"',
):
    if marker not in prepare_primary:
        raise SystemExit(f"Primary Android staging artifact must be preserved and reverified: {marker}")

skia_build_step = "- name: Build Mapbox Skia comparison APK (Impeller disabled)"
if workflow.count(skia_build_step) != 1 or workflow.count("id: build_skia_apk") != 1:
    raise SystemExit("Android staging must define exactly one Skia comparison build step and ID.")
if workflow.count("id: build_tile_store_disabled_apk") != 1:
    raise SystemExit("Android staging must define exactly one TileStore-disabled diagnostic build step.")

renderer_build = workflow.split("- name: Build Mapbox Skia comparison APK (Impeller disabled)", 1)[1]
renderer_build = renderer_build.split("- name: Upload Android staging APK", 1)[0]
for marker in (
    "github.event.pull_request.number == 79",
    "steps.build_apk.outputs.built == 'true'",
    "env.MAPBOX_ACCESS_TOKEN != ''",
    "env.MAPBOX_DOWNLOADS_TOKEN != ''",
    "continue-on-error: true",
    'renderer_dir="$RUNNER_TEMP/skia-build"',
    "flutter clean",
    "flutter pub get --enforce-lockfile",
    "python3 tool/prepare_android_skia_ab.py android/app/src/main/AndroidManifest.xml",
    '--dart-define=MAPBOX_STYLE_URI="$MAPBOX_STYLE_URI"',
    "--dart-define=MAPBOX_ANDROID_VIEW_MODE=hybrid-surface",
    'cp "$renderer_apk" "$renderer_dir/app-release.apk"',
    'echo "mapbox_style_uri=$MAPBOX_STYLE_URI"',
    'echo "mapbox_android_view_mode=hybrid-surface"',
    'echo "flutter_renderer=skia-optout"',
    'echo "impeller_enabled=false"',
    'echo "validation_scope=runtime-capable-artifact"',
    "--dart-define=MAPBOX_TILE_STORE_USAGE_MODE=default",
    'echo "mapbox_tile_store_usage_mode=default"',
    "--dart-define=MAPBOX_SNAPSHOTTER_DIAGNOSTICS=false",
    'echo "mapbox_snapshotter_diagnostics=false"',
):
    if marker not in renderer_build:
        raise SystemExit(f"Mapbox Skia/Impeller renderer build is missing: {marker}")
if "--build-dir" in workflow:
    raise SystemExit("Flutter 3.47.5 does not support --build-dir; preserve A/B APKs outside build/ instead.")
if renderer_build.index("flutter clean") > renderer_build.index("flutter pub get --enforce-lockfile"):
    raise SystemExit("A clean renderer build must restore dependencies from the committed lockfile.")

primary_build = workflow.split("- name: Build Android staging APK", 1)[1]
primary_build = primary_build.split("- name: Verify APK", 1)[0]
if '--dart-define=MAPBOX_ANDROID_VIEW_MODE="$MAPBOX_ANDROID_VIEW_MODE"' not in primary_build:
    raise SystemExit("The primary Android APK must compile with the selected Android platform-view mode.")
if 'echo "mapbox_android_view_mode=$MAPBOX_ANDROID_VIEW_MODE"' not in primary_build:
    raise SystemExit("The primary APK manifest must record the selected Android platform-view mode.")
if '--dart-define=MAPBOX_TILE_STORE_USAGE_MODE=default' not in primary_build:
    raise SystemExit("The primary Android APK must explicitly select the default TileStore usage mode.")
if 'echo "mapbox_tile_store_usage_mode=default"' not in primary_build:
    raise SystemExit("The primary APK manifest must record its default TileStore usage mode.")
if "--dart-define=MAPBOX_SNAPSHOTTER_DIAGNOSTICS=false" not in primary_build or 'echo "mapbox_snapshotter_diagnostics=false"' not in primary_build:
    raise SystemExit("The primary MapWidget smoke must disable concurrent Snapshotter diagnostics and record the setting.")

require_renderer = workflow.split("- name: Require Mapbox Skia A/B APK", 1)[1]
for marker in (
    "steps.build_skia_apk.outcome",
    'renderer_apk="$RUNNER_TEMP/skia-build/app-release.apk"',
    'renderer_manifest="$RUNNER_TEMP/skia-build/android-staging-validation.txt"',
    'expected_sha="$(sed -n \'s/^apk_sha256=//p\' "$renderer_manifest")"',
    "actual_sha=\"$(sha256sum \"$renderer_apk\" | cut -d ' ' -f1)\"",
    'test "$expected_sha" = "$actual_sha"',
    'grep -Fxq "mapbox_style_uri=$MAPBOX_STYLE_URI" "$renderer_manifest"',
    'grep -Fxq "mapbox_android_view_mode=hybrid-surface" "$renderer_manifest"',
    'grep -Fxq "flutter_renderer=skia-optout" "$renderer_manifest"',
    'grep -Fxq "impeller_enabled=false" "$renderer_manifest"',
):
    if marker not in require_renderer:
        raise SystemExit(f"Mapbox renderer A/B artifact verification is missing: {marker}")

apk_upload = workflow.split("- name: Upload Android staging APK", 1)[1]
apk_upload = apk_upload.split("- name: Upload Mapbox Skia A/B APK", 1)[0]
for marker in (
    "${{ runner.temp }}/primary-build/app-release.apk",
    "${{ runner.temp }}/primary-build/android-staging-validation.txt",
):
    if marker not in apk_upload:
        raise SystemExit(f"Primary Android staging artifact upload is missing: {marker}")
if "if: success() && steps.build_apk.outputs.built == 'true'" not in apk_upload:
    raise SystemExit("The primary APK must upload only after its verification step succeeds.")
renderer_upload = workflow.split("- name: Upload Mapbox Skia A/B APK", 1)[1]
renderer_upload = renderer_upload.split("- name: Enable KVM for Android emulator", 1)[0]
for marker in (
    "${{ runner.temp }}/skia-build/app-release.apk",
    "${{ runner.temp }}/skia-build/android-staging-validation.txt",
    "name: mapbox-skia-ab-apk",
):
    if marker not in renderer_upload:
        raise SystemExit(f"Skia/Impeller A/B artifact upload is missing: {marker}")
if "if: success() && steps.build_skia_apk.outcome == 'success'" not in renderer_upload:
    raise SystemExit("The renderer artifact upload must be conditional on a successful comparison build.")
if "- name: Require Mapbox Skia A/B APK" not in workflow:
    raise SystemExit("The PR #79 renderer comparison build must fail closed when its APK/manifest is missing.")
if "steps.build_skia_apk.outcome != 'skipped'" not in workflow:
    raise SystemExit("The renderer APK requirement must not turn an early cancellation into a false build failure.")

evidence_upload = workflow.split("- name: Upload Android map smoke evidence", 1)[1]
if "if: always()" not in evidence_upload.split("- name: Require Android map native smoke", 1)[0]:
    raise SystemExit("Android smoke evidence must upload even when the smoke command fails.")
require_smoke = workflow.split("- name: Require Android map native smoke", 1)[1]
require_smoke = require_smoke.split("- name: Require Mapbox Skia A/B APK", 1)[0]
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
    "${{ runner.temp }}/primary/espana-mapbox-snapshotter.png",
    "${{ runner.temp }}/primary/espana-mapbox-snapshotter-vector.png",
    "${{ runner.temp }}/skia/espana-system-dialog.xml",
    "${{ runner.temp }}/skia/espana-map-page-check.txt",
    "${{ runner.temp }}/skia/espana-outdoor-map.png",
    "${{ runner.temp }}/skia/espana-mapbox-snapshotter.png",
    "${{ runner.temp }}/skia/espana-mapbox-snapshotter-vector.png",
    "${{ runner.temp }}/skia/espana-mapbox-diagnostics.txt",
):
    if marker not in evidence_upload:
        raise SystemExit(f"Android smoke evidence upload is missing renderer A/B artifact path: {marker}")

print("android_map_smoke_network_preflight=true")
tile_store_build = workflow.split("- name: Build Mapbox TileStore-disabled diagnostic APK", 1)[1].split("- name: Upload Android staging APK", 1)[0]
for marker in (
    "steps.build_apk.outputs.built == 'true'",
    'manifest_backup="$RUNNER_TEMP/android-manifest-before-skia.xml"',
    'if [[ ! -s "$manifest_backup" ]]; then',
    'cp android/app/src/main/AndroidManifest.xml "$manifest_backup"',
    'test -s "$manifest_backup"',
    'cp "$manifest_backup" android/app/src/main/AndroidManifest.xml',
    'cmp -s "$manifest_backup" android/app/src/main/AndroidManifest.xml',
    "MAPBOX_TILE_STORE_USAGE_MODE=disabled",
    'tile_store_dir="$RUNNER_TEMP/tile-store-disabled-build"',
    '--dart-define=MAPBOX_ANDROID_VIEW_MODE="$MAPBOX_ANDROID_VIEW_MODE"',
    'echo "mapbox_tile_store_usage_mode=disabled"',
    'echo "mapbox_android_view_mode=$MAPBOX_ANDROID_VIEW_MODE"',
    "--dart-define=MAPBOX_SNAPSHOTTER_DIAGNOSTICS=false",
    'echo "mapbox_snapshotter_diagnostics=false"',
    'echo "validation_scope=diagnostic-only-tile-store-disabled"',
):
    if marker not in tile_store_build:
        raise SystemExit(f"TileStore-disabled diagnostic build is missing: {marker}")
if tile_store_build.index('cp "$manifest_backup" android/app/src/main/AndroidManifest.xml') > tile_store_build.index("flutter build apk --release"):
    raise SystemExit("Restore the pre-Skia configured manifest before building the TileStore diagnostic.")
tile_store_condition = tile_store_build.split("shell:", 1)[0]
if "env.MAPBOX_STYLE_URI ==" in tile_store_condition:
    raise SystemExit("The TileStore-disabled diagnostic must also run for imported Mapbox Standard styles.")
skia_build = workflow.split("- name: Build Mapbox Skia comparison APK (Impeller disabled)", 1)[1].split("- name: Build Mapbox TileStore-disabled diagnostic APK", 1)[0]
for marker in (
    'manifest_backup="$RUNNER_TEMP/android-manifest-before-skia.xml"',
    'cp android/app/src/main/AndroidManifest.xml "$manifest_backup"',
    "python3 tool/prepare_android_skia_ab.py android/app/src/main/AndroidManifest.xml",
):
    if marker not in skia_build:
        raise SystemExit(f"Skia comparison must preserve the configured manifest before mutation: {marker}")
if skia_build.index('cp android/app/src/main/AndroidManifest.xml "$manifest_backup"') > skia_build.index("python3 tool/prepare_android_skia_ab.py"):
    raise SystemExit("Capture the configured Android manifest before applying the Skia opt-out.")
tile_store_upload = workflow.split("- name: Upload Mapbox TileStore-disabled diagnostic APK", 1)[1].split("- name: Enable KVM", 1)[0]
for marker in (
    "mapbox-tile-store-disabled-apk",
    "${{ runner.temp }}/tile-store-disabled-build/app-release.apk",
    "${{ runner.temp }}/tile-store-disabled-build/android-staging-validation.txt",
):
    if marker not in tile_store_upload:
        raise SystemExit(f"TileStore-disabled diagnostic artifact upload is missing: {marker}")
tile_store_requirement = workflow.split("- name: Require Mapbox TileStore-disabled diagnostic APK", 1)[1]
tile_store_requirement_condition = tile_store_requirement.split("shell:", 1)[0]
if "env.MAPBOX_STYLE_URI ==" in tile_store_requirement_condition:
    raise SystemExit("The TileStore-disabled APK requirement must also apply to imported Mapbox Standard styles.")
for marker in (
    "steps.build_tile_store_disabled_apk.outcome",
    'flutter_renderer=impeller-default',
    'impeller_enabled=default',
    'mapbox_tile_store_usage_mode=disabled',
    'validation_scope=diagnostic-only-tile-store-disabled',
    'test "$expected_sha" = "$actual_sha"',
):
    if marker not in tile_store_requirement:
        raise SystemExit(f"TileStore-disabled APK requirement is missing: {marker}")

print("android_map_smoke_render_gate=true")
