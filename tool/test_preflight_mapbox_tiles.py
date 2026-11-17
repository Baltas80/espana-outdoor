#!/usr/bin/env python3
"""Offline tests for the sanitized Mapbox style/vector-tile preflight."""
from __future__ import annotations

import json
from urllib.error import HTTPError
from urllib.request import Request

from preflight_mapbox_tiles import PreflightError, _tile_xy, run_preflight


class FakeResponse:
    def __init__(self, body: bytes, status: int = 200):
        self._body = body
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def getcode(self):
        return self.status

    def read(self):
        return self._body


def main() -> int:
    token = "pk-test-secret-must-never-be-printed"
    style = {
        "version": 8,
        "sources": {
            "composite": {
                "type": "vector",
                "url": "mapbox://mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2",
            }
        },
    }
    calls: list[str] = []

    def successful_opener(request: Request, timeout: int = 20):
        calls.append(request.full_url)
        if len(calls) == 1:
            return FakeResponse(json.dumps(style).encode("utf-8"))
        return FakeResponse(b"x" * 256)

    result = run_preflight(
        style_uri="mapbox://styles/mapbox/standard",
        access_token=token,
        opener=successful_opener,
    )
    assert result["tileset"] == "mapbox.mapbox-streets-v8"
    assert result["tile"] == "12/1993/1581"
    assert result["tile_bytes"] == 256
    assert len(calls) == 2
    assert all(token in url for url in calls)

    # Mapbox Standard can expose its basemap via imports, with no root-level
    # source URL. The preflight must still probe the known Streets v8 source.
    imported_style = {
        "version": 8,
        "imports": [{"id": "basemap", "url": "mapbox://styles/mapbox/standard"}],
    }
    imported_calls: list[str] = []

    def imported_opener(request: Request, timeout: int = 20):
        imported_calls.append(request.full_url)
        if len(imported_calls) == 1:
            return FakeResponse(json.dumps(imported_style).encode("utf-8"))
        return FakeResponse(b"vector-tile" * 40)

    imported_result = run_preflight(
        style_uri="mapbox://styles/mapbox/standard",
        access_token=token,
        opener=imported_opener,
    )
    assert imported_result["tileset"] == "mapbox.mapbox-streets-v8"
    assert imported_result["tile_bytes"] == len(b"vector-tile" * 40)

    def forbidden_opener(request: Request, timeout: int = 20):
        raise HTTPError(request.full_url, 403, "Forbidden", hdrs=None, fp=None)

    try:
        run_preflight(
            style_uri="mapbox://styles/mapbox/standard",
            access_token=token,
            opener=forbidden_opener,
        )
    except PreflightError as error:
        assert str(error) == "style_http_status=403"
        assert token not in str(error)
    else:
        raise AssertionError("HTTP 403 must fail the Mapbox preflight.")

    try:
        run_preflight(
            style_uri="mapbox://styles/mapbox/standard",
            access_token=token,
            opener=lambda *_args, **_kwargs: FakeResponse(
                json.dumps({"version": 8, "sources": {}}).encode("utf-8")
            ),
        )
    except PreflightError as error:
        assert str(error) == "style_has_no_mapbox_streets_v8_source"
        assert token not in str(error)
    else:
        raise AssertionError("A style without the Streets source must fail closed.")

    assert _tile_xy(-4.7794, 37.8882, 12) == (1993, 1581)
    print("Mapbox token preflight unit tests: PASS (HTTP errors redact credentials).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
