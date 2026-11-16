#!/usr/bin/env python3
"""Unit tests for the Mapbox runtime access preflight."""

from __future__ import annotations

import json
import unittest
from urllib.error import HTTPError
from urllib.request import Request

from verify_mapbox_runtime_access import PreflightError, verify_runtime_access


class FakeResponse:
    def __init__(self, body: bytes, status: int = 200):
        self.body = body
        self.status = status

    def read(self) -> bytes:
        return self.body

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class MapboxRuntimeAccessTests(unittest.TestCase):
    token = "pk." + "x" * 40

    def opener(self, request: Request, timeout: int = 20):
        url = request.full_url
        self.assertEqual(timeout, 20)
        if "/styles/v1/" in url:
            return FakeResponse(
                json.dumps(
                    {
                        "version": 8,
                        "sources": {
                            "composite": {
                                "type": "vector",
                                "url": "mapbox://mapbox.mapbox-streets-v8",
                            }
                        },
                    }
                ).encode()
            )
        if "/v4/mapbox.mapbox-streets-v8.json" in url:
            return FakeResponse(
                json.dumps(
                    {"tiles": ["https://tiles.example/{z}/{x}/{y}.vector.pbf"]}
                ).encode()
            )
        if "tiles.example" in url:
            self.assertIn("access_token=", url)
            return FakeResponse(b"vector-tile")
        self.fail("Unexpected Mapbox endpoint")

    def test_style_tilejson_and_real_vector_tile_are_checked(self):
        result = verify_runtime_access(self.token, self.opener)
        self.assertEqual(result["style_http"], 200)
        self.assertEqual(result["tilejson_http"], "200")
        self.assertEqual(result["vector_tile_http"], 200)
        self.assertEqual(result["vector_tile_bytes"], len(b"vector-tile"))
        self.assertEqual(result["dataset"], "mapbox.mapbox-streets-v8")

    def test_rejects_missing_or_non_public_token(self):
        with self.assertRaisesRegex(PreflightError, "public_access_token"):
            verify_runtime_access("sk." + "x" * 40, self.opener)

    def test_http_failure_does_not_echo_token_or_url(self):
        def unauthorized(_request, timeout=20):
            raise HTTPError(
                "https://api.mapbox.com/styles/v1/private?access_token=" + self.token,
                401,
                "Unauthorized",
                {},
                None,
            )

        with self.assertRaisesRegex(PreflightError, "style_http_status=401") as raised:
            verify_runtime_access(self.token, unauthorized)
        self.assertNotIn(self.token, str(raised.exception))
        self.assertNotIn("access_token", str(raised.exception))

    def test_rejects_empty_vector_tile(self):
        def empty_tile(request: Request, timeout=20):
            if "/styles/v1/" in request.full_url:
                return FakeResponse(
                    json.dumps(
                        {
                            "version": 8,
                            "sources": {
                                "composite": {
                                    "type": "vector",
                                    "url": "mapbox://mapbox.mapbox-streets-v8",
                                }
                            },
                        }
                    ).encode()
                )
            if "/v4/" in request.full_url:
                return FakeResponse(
                    json.dumps(
                        {"tiles": ["https://tiles.example/{z}/{x}/{y}.pbf"]}
                    ).encode()
                )
            return FakeResponse(b"")

        with self.assertRaisesRegex(PreflightError, "vector_tile_empty_response"):
            verify_runtime_access(self.token, empty_tile)


if __name__ == "__main__":
    unittest.main()
