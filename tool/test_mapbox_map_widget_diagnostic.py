#!/usr/bin/env python3
"""Guard the Android-only live MapWidget diagnostic and its screenshot contract."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VIEWPORT = (ROOT / "lib/features/map/mapbox_map_viewport.dart").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github/workflows/staging-android.yml").read_text(encoding="utf-8")
SMOKE = (ROOT / "tool/smoke_android_map.sh").read_text(encoding="utf-8")
SCREENSHOT = (ROOT / "tool/verify_android_map_screenshot.py").read_text(encoding="utf-8")

required_viewport = (
    "MAPBOX_MAP_WIDGET_DIAGNOSTIC_STYLE",
    "defaultValue: 'none'",
    "mapboxMapWidgetDiagnosticStyleJson",
    "case 'geojson':",
    "mapboxMapWidgetGeoJsonStyleJson",
    "await map.loadStyleJson(styleJson)",
    "_mapWidgetDiagnosticAppEnvironment == 'staging'",
    "defaultTargetPlatform == TargetPlatform.android",
    "result=rejected reason=staging_android_only",
)
for marker in required_viewport:
    if marker not in VIEWPORT:
        raise SystemExit(f"Live MapWidget diagnostic guard is missing: {marker}")

if "defaultValue: 'mapbox://styles/mapbox/outdoors-v12'" not in VIEWPORT:
    raise SystemExit("Production must retain Outdoors v12 as the default style.")
if "defaultValue: 'hybrid-surface'" not in VIEWPORT:
    raise SystemExit("Production must retain Hybrid Composition/SurfaceView as the default.")

required_workflow = (
    "MAPBOX_MAP_WIDGET_DIAGNOSTIC_STYLE:",
    "&& 'geojson' || (github.event_name == 'workflow_dispatch' && inputs.map_widget_diagnostic_style) || 'none'",
    "map_widget_diagnostic_style:",
    "- geojson",
    "--dart-define=MAPBOX_MAP_WIDGET_DIAGNOSTIC_STYLE=",
    "mapbox_map_widget_diagnostic_style=$MAPBOX_MAP_WIDGET_DIAGNOSTIC_STYLE",
    "MAPBOX_ANDROID_VIEW_MODE: ${{ inputs.android_view_mode == 'virtual-texture' && 'virtual-texture' || 'hybrid-surface' }}",
)
for marker in required_workflow:
    if marker not in WORKFLOW:
        raise SystemExit(f"Android staging vector diagnostic wiring is missing: {marker}")

if 'case "${map_widget_diagnostic_style}" in\n  none|baseline|vector|geojson)' not in SMOKE:
    raise SystemExit("Android smoke must validate the selected local diagnostic style.")
if '--expected-solid-color "#d9e6c7"' not in SMOKE:
    raise SystemExit("Baseline smoke must verify the expected MapWidget background color.")
if 'elif [[ "${map_widget_diagnostic_style}" == "vector" || "${map_widget_diagnostic_style}" == "geojson" ]]' not in SMOKE:
    raise SystemExit("Android staging smoke must execute the live vector diagnostic branch.")
if '--expected-line-color "#c43c39"' not in SMOKE:
    raise SystemExit("Vector smoke must require road-colored pixels in the viewport.")
if "def verify_expected_solid_color(" not in SCREENSHOT:
    raise SystemExit("Screenshot verifier must support the isolated solid-color baseline.")
if "expected_background_color" not in SCREENSHOT:
    raise SystemExit("Screenshot verifier must reject the wrong baseline color.")
if "def verify_expected_line_render(" not in SCREENSHOT:
    raise SystemExit("Screenshot verifier must require visible line pixels for GeoJSON and vector diagnostics.")

print("MAPBOX_MAP_WIDGET_DIAGNOSTIC_GUARD passed")
