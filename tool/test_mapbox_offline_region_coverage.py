#!/usr/bin/env python3
"""Guard production and emulator download geometry against viewport tile misses.

The z13 tile IDs were captured from Mapbox integration run 43799514133. If the
camera/viewport changes, refresh this fixture from MAPBOX_SOURCE_DATA evidence.
"""
from __future__ import annotations

import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEST = ROOT / "integration_test" / "mapbox_android_live_route_test.dart"
OFFLINE_PAGE = ROOT / "lib" / "features" / "offline" / "offline_page.dart"


def parse_ring(path: Path, identifier: str) -> list[tuple[float, float]]:
    source = path.read_text(encoding="utf-8")
    match = re.search(
        rf"const {re.escape(identifier)} = <List<double>>\[(.*?)\];",
        source,
        flags=re.DOTALL,
    )
    if match is None:
        raise SystemExit(f"Could not find {identifier} in {path.relative_to(ROOT)}.")
    ring = [
        (float(lon), float(lat))
        for lon, lat in re.findall(
            r"\[\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\]",
            match.group(1),
        )
    ]
    if len(ring) < 5 or ring[0] != ring[-1]:
        raise SystemExit(f"{identifier} must be a closed polygon ring.")
    return ring


ring = parse_ring(TEST, "_regionRing")
production_ring = parse_ring(OFFLINE_PAGE, "_cordobaRing")
if ring != production_ring:
    raise SystemExit(
        "The Android integration fixture and OfflinePage must download the same polygon."
    )

min_lon = min(point[0] for point in ring)
max_lon = max(point[0] for point in ring)
min_lat = min(point[1] for point in ring)
max_lat = max(point[1] for point in ring)


def tile_bounds(z: int, x: int, y: int) -> tuple[float, float, float, float]:
    scale = 2**z
    west = x / scale * 360.0 - 180.0
    east = (x + 1) / scale * 360.0 - 180.0

    def latitude(tile_y: int) -> float:
        return math.degrees(
            math.atan(math.sinh(math.pi * (1.0 - 2.0 * tile_y / scale)))
        )

    north = latitude(y)
    south = latitude(y + 1)
    return west, south, east, north


# Full tile bounds, not merely tile centres, must fit inside the download
# polygon. The previous 37.85° southern edge clipped most of row y=3164.
expected_tiles = [
    (13, x, y)
    for x in (3986, 3987)
    for y in (3162, 3163, 3164)
]
uncovered: list[str] = []
for z, x, y in expected_tiles:
    west, south, east, north = tile_bounds(z, x, y)
    if not (
        min_lon <= west
        and east <= max_lon
        and min_lat <= south
        and north <= max_lat
    ):
        uncovered.append(f"{z}/{x}/{y}")

if uncovered:
    raise SystemExit(
        "Offline polygon does not fully cover the recorded viewport tiles: "
        + ", ".join(uncovered)
    )

print(
    "MAPBOX_OFFLINE_REGION_COVERAGE "
    f"tiles={len(expected_tiles)} "
    f"bounds=lon:{min_lon}..{max_lon},lat:{min_lat}..{max_lat} "
    "integration_and_production_geometry=identical"
)
