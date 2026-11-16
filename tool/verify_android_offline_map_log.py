#!/usr/bin/env python3
"""Verify that the production MapboxMapViewport rendered only offline tiles."""

from __future__ import annotations

import math
from pathlib import Path
import re
import sys

MIN_LONGITUDE = -4.84
MAX_LONGITUDE = -4.72
MIN_LATITUDE = 37.78
MAX_LATITUDE = 37.97
ZOOM = 13


def _tile_latitude(y: int, scale: float) -> float:
    radians = 2 * math.atan(math.exp(math.pi * (1 - 2 * y / scale))) - math.pi / 2
    return math.degrees(radians)


def _tile_is_covered(z: int, x: int, y: int) -> bool:
    scale = float(1 << z)
    west = x / scale * 360 - 180
    east = (x + 1) / scale * 360 - 180
    north = _tile_latitude(y, scale)
    south = _tile_latitude(y + 1, scale)
    epsilon = 1e-7
    return (
        west >= MIN_LONGITUDE - epsilon
        and east <= MAX_LONGITUDE + epsilon
        and south >= MIN_LATITUDE - epsilon
        and north <= MAX_LATITUDE + epsilon
    )


def verify_log_text(text: str) -> dict[str, object]:
    required_markers = (
        "MAPBOX_MAP_STYLE_LOADED",
        "MAPBOX_MAP_LOADED",
        "MAPBOX_MAP_FULL_FRAME",
        "MAPBOX_MAP_IDLE",
    )
    errors = [f"missing {marker}" for marker in required_markers if marker not in text]

    network_events = re.findall(
        r"MAPBOX_RESOURCE_OK kind=([A-Z_]+) data_source=NETWORK\\b", text
    )
    if network_events:
        errors.append(f"offline map used network resources: {','.join(network_events[:8])}")

    tile_misses = re.findall(
        r"MAPBOX_RESOURCE_(?:LOOKUP_MISS|CANCELLED) kind=TILE\\b", text
    )
    if tile_misses:
        errors.append(f"offline TileStore tile misses/cancellations: {len(tile_misses)}")

    resource_failures = re.findall(r"MAPBOX_RESOURCE_FAILURE\\b", text)
    if resource_failures:
        errors.append(f"offline resource failures: {len(resource_failures)}")

    tile_ids = {
        (int(z), int(x), int(y))
        for z, x, y in re.findall(
            r"MAPBOX_SOURCE_DATA\\b.*?tile_id=(\\d+)/(\\d+)/(\\d+)", text
        )
    }
    zoom_tiles = sorted(tile for tile in tile_ids if tile[0] == ZOOM)
    if not zoom_tiles:
        errors.append(f"no z{ZOOM} source tiles observed from the production MapboxMapViewport")
    uncovered = [tile for tile in zoom_tiles if not _tile_is_covered(*tile)]
    if uncovered:
        errors.append(f"viewport tiles outside the downloaded Córdoba polygon: {uncovered}")

    if errors:
        raise ValueError("; ".join(errors))

    return {
        "tiles": len(zoom_tiles),
        "tile_ids": [f"{z}/{x}/{y}" for z, x, y in zoom_tiles],
        "network_requests": len(network_events),
        "tile_misses": len(tile_misses),
        "resource_failures": len(resource_failures),
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: verify_android_offline_map_log.py <sanitized-logcat.txt>", file=sys.stderr)
        return 2
    text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
    try:
        result = verify_log_text(text)
    except ValueError as error:
        print(f"MAPBOX_OFFLINE_LOG_REJECTED reason={error}")
        return 1
    tile_ids = ",".join(result["tile_ids"])
    print(
        "MAPBOX_OFFLINE_LOG_VERIFIED "
        f"tiles={result['tiles']} tile_ids={tile_ids} "
        f"network_requests={result['network_requests']} "
        f"tile_misses={result['tile_misses']} "
        f"resource_failures={result['resource_failures']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
