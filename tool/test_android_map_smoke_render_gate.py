#!/usr/bin/env python3
"""Prevent Android map smoke from accepting a live process with a blank viewport."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SMOKE = ROOT / "tool" / "smoke_android_map.sh"
source = SMOKE.read_text(encoding="utf-8")

required = (
    "dumpsys window windows",
    "mCurrentFocus|mFocusedApp",
    "mResumedActivity|topResumedActivity",
    "MAP_SMOKE_FOREGROUND",
    "verify_android_map_screenshot.py",
    '--foreground-package "${package_name}"',
)
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
print("android_map_smoke_render_gate=true")
