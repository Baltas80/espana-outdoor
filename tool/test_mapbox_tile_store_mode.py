#!/usr/bin/env python3
"""Guard the Mapbox Maps/Navigation shared TileStore mode.

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
)
for fragment in required:
    if fragment not in source:
        raise SystemExit(f"Shared Mapbox TileStore configuration is missing: {fragment}")

if "TileStoreUsageMode.READ_AND_UPDATE" in source:
    raise SystemExit(
        "Do not set READ_AND_UPDATE globally: it converts free-pan map requests "
        "to tile-pack-only requests and can leave viewports outside downloaded "
        "regions without online individual-tile fallback."
    )

print("mapbox_maps_tile_store=shared")
print("mapbox_maps_tile_store_usage=READ_ONLY")
print("navigation_routing_tile_store=shared")
