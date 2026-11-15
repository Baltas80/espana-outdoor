#!/usr/bin/env python3
"""Guard the shared Mapbox TileStore configuration and source diagnostics.

The app map supports free panning. READ_ONLY checks downloaded tile packs and
falls back to individual online tiles when a tile is not in a pack. A global
READ_AND_UPDATE setting converts all requests to tile-pack requests and is
not appropriate for the unrestricted app map viewport.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "android" / "app" / "src" / "main" / "kotlin" / "com" / "espana" / "outdoors" / "navigation" / "MapboxNavigationBridge.kt"
source = BRIDGE.read_text(encoding="utf-8")

required = (
    "MapboxMapsOptions.tileStore = store",
    "MapboxMapsOptions.tileStoreUsageMode = TileStoreUsageMode.READ_ONLY",
    ".tileStore(store)",
    ".pixelRatio(appContext.resources.displayMetrics.density)",
    ".networkRestriction(NetworkRestriction.NONE)",
    'val mapRegionId = "$regionId-maps"',
    'val routingRegionId = "$regionId-routing-walking"',
    ".descriptors(listOf(mapsDescriptor))",
    ".descriptors(listOf(navigationDescriptor))",
    "mapCompletedResourceCount",
    "routingCompletedResourceCount",
    '"offline:$regionId:maps"',
    '"offline:$regionId:routing-walking"',
)
for fragment in required:
    if fragment not in source:
        raise SystemExit(f"Shared Mapbox TileStore configuration is missing: {fragment}")

VIEWPORT = ROOT / "lib" / "features" / "map" / "mapbox_map_viewport.dart"
viewport = VIEWPORT.read_text(encoding="utf-8")
required_viewport = (
    "mapOptions: mapboxMapOptionsForPixelRatio(devicePixelRatio)",
    "MediaQuery.devicePixelRatioOf(context)",
    "GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY",
    "fontFamily: 'sans-serif'",
    "onSourceAddedListener:",
    "onSourceDataLoadedListener:",
    "MAPBOX_SOURCE_DATA",
)
for fragment in required_viewport:
    if fragment not in viewport:
        raise SystemExit(
            f"Flutter MapWidget configuration/diagnostics missing: {fragment}"
        )

if "TileStoreUsageMode.READ_AND_UPDATE" in source:
    raise SystemExit(
        "Do not set READ_AND_UPDATE globally: it converts free-pan map requests "
        "to tile-pack-only requests and can leave viewports outside downloaded "
        "regions without online individual-tile fallback."
    )

INTEGRATION_TEST = ROOT / "integration_test" / "mapbox_android_live_route_test.dart"
integration_test = INTEGRATION_TEST.read_text(encoding="utf-8")
for fragment in (
    "mapboxMapOptionsForPixelRatio(",
    "WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio",
    "onSourceAddedListener:",
    "onSourceDataLoadedListener:",
    "source_data_events=",
    "mapCompletedResourceCount",
    "routingCompletedResourceCount",
    "routingTiles",
):
    if fragment not in integration_test:
        raise SystemExit(
            f"Android offline integration is missing required diagnostic/configuration: {fragment}"
        )


OFFLINE_PAGE = ROOT / "lib" / "features" / "offline" / "offline_page.dart"
offline_page = OFFLINE_PAGE.read_text(encoding="utf-8")
for fragment in (
    "result['routingTiles'] != true",
    "mapCompletedResourceCount",
    "routingCompletedResourceCount",
):
    if fragment not in offline_page:
        raise SystemExit(
            f"Offline UI must require separate map/routing resources: {fragment}"
        )

print("mapbox_maps_tile_store=shared")
print("mapbox_maps_tile_store_usage=READ_ONLY")
print("mapbox_source_diagnostics=enabled")
print("navigation_routing_tile_store=shared")
