#!/usr/bin/env python3
"""Regression tests for native offline Mapbox log verification."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "verify_android_offline_map_log",
    ROOT / "tool" / "verify_android_offline_map_log.py",
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


VALID_LOG = "\n".join(
    (
        "MAPBOX_MAP_STYLE_LOADED",
        "MAPBOX_MAP_LOADED partial_frames=2",
        "MAPBOX_MAP_FULL_FRAME",
        "MAPBOX_MAP_IDLE",
        "MAPBOX_SOURCE_DATA id=composite type=TILE loaded=true tile_id=13/3987/3163",
    )
)


class OfflineMapLogTests(unittest.TestCase):
    def test_accepts_a_complete_offline_viewport_inside_downloaded_region(self) -> None:
        result = MODULE.verify_log_text(VALID_LOG)
        self.assertEqual(result["tiles"], 1)
        self.assertEqual(result["tile_ids"], ["13/3987/3163"])
        self.assertEqual(result["network_requests"], 0)

    def test_rejects_missing_full_render_events(self) -> None:
        with self.assertRaisesRegex(ValueError, "MAPBOX_MAP_FULL_FRAME"):
            MODULE.verify_log_text(VALID_LOG.replace("MAPBOX_MAP_FULL_FRAME\n", ""))

    def test_rejects_network_fallback(self) -> None:
        with self.assertRaisesRegex(ValueError, "used network resources"):
            MODULE.verify_log_text(VALID_LOG + "\nMAPBOX_RESOURCE_OK kind=TILE data_source=NETWORK")

    def test_rejects_tile_store_misses(self) -> None:
        with self.assertRaisesRegex(ValueError, "TileStore tile misses"):
            MODULE.verify_log_text(VALID_LOG + "\nMAPBOX_RESOURCE_LOOKUP_MISS kind=TILE data_source=DATABASE")

    def test_rejects_tiles_outside_the_downloaded_region(self) -> None:
        with self.assertRaisesRegex(ValueError, "outside the downloaded"):
            MODULE.verify_log_text(
                VALID_LOG.replace("13/3987/3163", "13/4000/3163")
            )

    def test_rejects_absent_viewport_tile_events(self) -> None:
        with self.assertRaisesRegex(ValueError, "no z13 source tiles"):
            MODULE.verify_log_text(VALID_LOG.replace(
                "MAPBOX_SOURCE_DATA id=composite type=TILE loaded=true tile_id=13/3987/3163",
                "",
            ))


if __name__ == "__main__":
    unittest.main()
