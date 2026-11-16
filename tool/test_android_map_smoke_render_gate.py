#!/usr/bin/env python3
"""Prevent Android map smoke from accepting a live process with a blank viewport."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SMOKE = ROOT / "tool" / "smoke_android_map.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "staging-android.yml"
NETWORK_PREFLIGHT = ROOT / "tool" / "ensure_android_emulator_online.sh"
source = SMOKE.read_text(encoding="utf-8")
if not NETWORK_PREFLIGHT.is_file():
    raise SystemExit("Android map smoke references a missing emulator network preflight script.")
network_preflight = NETWORK_PREFLIGHT.read_text(encoding="utf-8")
workflow = WORKFLOW.read_text(encoding="utf-8")

required = (
    "ensure_android_emulator_online.sh",
    'ANDROID_EMULATOR_CI:-false',
    "dumpsys window windows",
    "mCurrentFocus|mFocusedApp",
    "mResumedActivity|topResumedActivity",
    "MAP_SMOKE_FOREGROUND",
    "verify_android_map_screenshot.py",
    '--foreground-package "${package_name}"',
)
for marker in ("ANDROID_EMULATOR_CI", "validated_internet=1", "Active default network", "INTERNET", "VALIDATED"):
    if marker not in network_preflight:
        raise SystemExit(f"Android emulator network preflight is missing validation: {marker}")

for marker in required:
    if marker not in source:
        raise SystemExit(f"Android map smoke is missing foreground/render gate: {marker}")

if source.index("MAP_SMOKE_FOREGROUND") > source.index('adb exec-out screencap -p'):
    raise SystemExit("Foreground verification must happen before the screenshot is captured.")
if source.index("verify_android_map_screenshot.py") < source.index('adb exec-out screencap -p'):
    raise SystemExit("Screenshot validation must happen after the PNG is captured.")
if source.index("verify_android_map_screenshot.py") > source.index('echo "PASS: Mapbox map remained alive'):
    raise SystemExit("The smoke must validate the screenshot before reporting PASS.")

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

print("android_map_smoke_network_preflight=true")
print("android_map_smoke_render_gate=true")
