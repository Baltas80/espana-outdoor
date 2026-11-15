#!/usr/bin/env python3
"""Guard the Android emulator validation order and cancellation policy.

The native online/download/offline routing proof is the highest-value check.
Run it before the release APK smoke so an interrupted emulator run does not
spend its first validation window only on the separate UI smoke. New commits
must queue behind an active emulator run instead of cancelling its evidence.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "staging-android.yml"
ORCHESTRATOR = ROOT / "tool" / "staging_android_emulator_validation.sh"

workflow = WORKFLOW.read_text(encoding="utf-8")
orchestrator = ORCHESTRATOR.read_text(encoding="utf-8")

if "cancel-in-progress: false" not in workflow:
    raise SystemExit(
        "Android staging must not cancel an active emulator run when a newer "
        "commit is queued; preserve its diagnostic artifacts."
    )

route_call = 'bash "${script_dir}/staging_android_route_integration.sh"'
smoke_call = 'bash "${script_dir}/smoke_android_map.sh" "${apk_path}" online'
route_index = orchestrator.find(route_call)
smoke_index = orchestrator.find(smoke_call)
if route_index < 0 or smoke_index < 0:
    raise SystemExit("Both Android routing integration and release map smoke must run.")
if route_index > smoke_index:
    raise SystemExit(
        "Run online/download/offline routing before the separate release APK map smoke."
    )

for phase in ("online_offline_routing", "map_smoke"):
    if f"ANDROID_VALIDATION_PHASE_RESULT phase={phase}" not in orchestrator:
        raise SystemExit(f"Android validation must report the {phase} result independently.")


if "| sed -u -E " not in (ROOT / "tool" / "staging_android_route_integration.sh").read_text(encoding="utf-8"):
    raise SystemExit(
        "The offline screenshot marker must be streamed without sed buffering; "
        "the host capture must run while the integration app is foregrounded."
    )

route_script = (ROOT / "tool" / "staging_android_route_integration.sh").read_text(encoding="utf-8")
integration_test = (ROOT / "integration_test" / "mapbox_android_live_route_test.dart").read_text(encoding="utf-8")
if "adb -s \"$DEVICE_SERIAL\" logcat -c" not in route_script:
    raise SystemExit("Clear stale Android logcat before waiting for the offline screenshot marker.")
if "logcat -d -s EspanaOfflineTest:I" not in route_script or "offline_logcat" not in route_script:
    raise SystemExit("Capture synchronization must poll the dedicated native test logcat tag, not buffered host stdout.")
if "logcat -d -s flutter:I" in route_script:
    raise SystemExit("Do not poll Flutter stdout for the native screenshot-ready signal.")
if 'grep -q \'MAPBOX_OFFLINE_SCREENSHOT_READY\' "$TEST_LOG_PATH"' in route_script:
    raise SystemExit("Do not use flutter test stdout as the screenshot trigger; it may be buffered until exit.")
if "invokeMethod<void>('markOfflineScreenshotReady')" not in integration_test:
    raise SystemExit("The integration app must invoke the native screenshot-ready signal.")
main_activity = (ROOT / "android" / "app" / "src" / "main" / "kotlin" / "com" / "example" / "espana_outdoors" / "MainActivity.kt").read_text(encoding="utf-8")
for marker in (
    '"markOfflineScreenshotReady" ->',
    'ApplicationInfo.FLAG_DEBUGGABLE',
    'Log.i("EspanaOfflineTest", "MAPBOX_OFFLINE_SCREENSHOT_READY")',
):
    if marker not in main_activity:
        raise SystemExit(f"MainActivity is missing the debug-only native screenshot signal: {marker}")
if '*"$TEST_PACKAGE_NAME/"*' not in route_script:
    raise SystemExit("Offline screenshot capture must verify the integration-test package is foregrounded.")

if "if: always()" not in workflow:
    raise SystemExit("Android staging must retain unconditional evidence-upload steps.")

print("android_validation_order=routing_before_release_smoke")
print("android_validation_concurrency=non_cancelling")
print("android_validation_evidence_upload=always")
