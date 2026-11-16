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
    "val mapPixelRatio = appContext.resources.displayMetrics.density",
    ".pixelRatio(mapPixelRatio)",
    ".networkRestriction(NetworkRestriction.NONE)",
    'val mapRegionId = "$regionId-maps"',
    'val routingRegionId = "$regionId-routing-walking"',
    ".descriptors(listOf(mapsDescriptor))",
    ".descriptors(listOf(navigationDescriptor))",
    "mapCompletedResourceCount",
    "routingCompletedResourceCount",
    '"offline:$regionId:maps"',
    '"offline:$regionId:routing-walking"',
    '"offline:$regionId:styleUri"',
    '"offline:$regionId:pixelRatio"',
    'fun verifyOfflineRegion(',
    'tileRegionContainsDescriptors(mapRegionId',
    'MapboxMapsOptions.tileStore === store',
    'descriptorExpected.value == true',
)
for fragment in required:
    if fragment not in source:
        raise SystemExit(f"Shared Mapbox TileStore configuration is missing: {fragment}")

# MapboxMapsOptions are snapshotted when Maps API objects are constructed.
# Configure the shared store before Navigation bootstrap and reapply it before
# OfflineManager so both SDKs cannot silently retain different stores.
first_store_assignment = source.index("MapboxMapsOptions.tileStore = store")
navigation_creation = source.index("MapboxNavigationProvider.create(")
last_store_assignment = source.rindex("MapboxMapsOptions.tileStore = store")
offline_manager_creation = source.index("offlineManager = OfflineManager()")
if not (
    first_store_assignment < navigation_creation < last_store_assignment < offline_manager_creation
):
    raise SystemExit(
        "Configure the shared Maps TileStore before Navigation and reapply it before OfflineManager."
    )

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

for fragment in (
    "it.id == mapRegionId",
    "it.id == routingRegionId",
    "mapCompleted <= 0",
    "routingCompleted <= 0",
    "mapErrors > 0",
    "routingErrors > 0",
):
    if fragment not in source:
        raise SystemExit(
            f"Offline acceptance must verify map and routing TileRegions independently: {fragment}"
        )

# The app's TileStore must live outside the evictable cache and survive a
# force-stop/process restart. The SDK root path must be set before create().
root_path_setup = source.index("TileStore.setRootPath(path)")
tile_store_create = source.index("TileStore.create()")
if not (0 <= root_path_setup < tile_store_create):
    raise SystemExit("Set the persistent TileStore root path before creating the process TileStore.")
for fragment in (
    "File(context.noBackupFilesDir, TILE_STORE_DIRECTORY)",
    "directory.mkdirs()",
    "check(rootPath.isValue)",
    "directory.absolutePath + File.separator",
):
    if fragment not in source:
        raise SystemExit(f"Persistent private TileStore path is not guarded: {fragment}")
if "context.cacheDir" in source or "context.externalCacheDir" in source:
    raise SystemExit("Offline TileStore must not be placed in an evictable cache directory.")
destroy_body = source.split("fun destroy()", 1)[1].split("private companion object", 1)[0]
if "delete" in destroy_body or "removeTileRegion" in destroy_body:
    raise SystemExit("Destroying the navigation bridge must not delete persistent offline regions.")

if "TileStoreUsageMode.READ_AND_UPDATE" in source:
    raise SystemExit(
        "Do not set READ_AND_UPDATE globally: it converts free-pan map requests "
        "to tile-pack-only requests and can leave viewports outside downloaded "
        "regions without online individual-tile fallback."
    )

NATIVE_VERIFIER = ROOT / "tool" / "verify_mobile_native.py"
native_verifier = NATIVE_VERIFIER.read_text(encoding="utf-8")
for fragment in (
    ".descriptors(listOf(mapsDescriptor))",
    ".descriptors(listOf(navigationDescriptor))",
    'val mapRegionId = "$regionId-maps"',
    'val routingRegionId = "$regionId-routing-walking"',
):
    if fragment not in native_verifier:
        raise SystemExit(
            f"Native Android verifier must accept the separate Maps/Navigation regions: {fragment}"
        )
if "descriptors(listOf(mapsDescriptor, navigationDescriptor))" in native_verifier:
    raise SystemExit("Native Android verifier still expects the obsolete combined TileRegion.")

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
    "verifyOfflineRegion",
    "mapDescriptorPresentInMapsStore",
    "mapTileStoreSameInstance",
    "mapPixelRatio",
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
