#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("patch_mapbox_resource_expiry.py")
SPEC = importlib.util.spec_from_file_location("patch_mapbox_resource_expiry", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class MapboxExpiryPatchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.source = """import 'package:turf/turf.dart';

ResourceResponse _resourceResponseFromJson(Map<String, dynamic> json) =>
    ResourceResponse(
      modified: json['modified'] != null
          ? DateTime.fromMicrosecondsSinceEpoch(json['modified'] as int)
          : null,
      expires: json['expires'] != null
          ? DateTime.fromMicrosecondsSinceEpoch(json['expires'] as int)
          : null,
    );
"""

    def test_maps_out_of_range_expiry_to_null(self) -> None:
        patched = MODULE.patch_source(self.source)
        self.assertIn("_mapboxDateTimeFromMicroseconds(json['modified'])", patched)
        self.assertIn("_mapboxDateTimeFromMicroseconds(json['expires'])", patched)
        self.assertIn("value < -8640000000000000000", patched)
        self.assertIn("value > 8640000000000000000", patched)
        self.assertNotIn(
            "DateTime.fromMicrosecondsSinceEpoch(json['expires'] as int)",
            patched,
        )

    def test_patch_is_idempotent(self) -> None:
        once = MODULE.patch_source(self.source)
        twice = MODULE.patch_source(once)
        self.assertEqual(once, twice)

    def test_unknown_upstream_parser_fails_closed(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.patch_source("class ResourceResponse {}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
