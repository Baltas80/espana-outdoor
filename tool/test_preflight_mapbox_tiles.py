#!/usr/bin/env python3
"""Offline tests for the sanitized Mapbox style/vector-tile preflight."""
from __future__ import annotations

import json
from urllib.error import HTTPError
from urllib.request import Request

from preflight_mapbox_tiles import (
    PreflightError,
    _tile_xy,
    inspect_vector_tile,
    run_preflight,
)


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


def _varint(value: int) -> bytes:
    encoded = bytearray()
    while value > 0x7F:
        encoded.append((value & 0x7F) | 0x80)
        value >>= 7
    encoded.append(value)
    return bytes(encoded)


def _varint_field(number: int, value: int) -> bytes:
    return _varint(number << 3) + _varint(value)


def _bytes_field(number: int, value: bytes) -> bytes:
    return _varint((number << 3) | 2) + _varint(len(value)) + value


def _mvt_tile(
    *,
    road_features: int = 1,
    other_layer: str = "water",
    include_road: bool = True,
) -> bytes:
    # MVT Tile.layers is field 3. Layer.name is field 1 and repeated
    # Layer.features is field 2. Feature.type=2 means LINESTRING.
    tile = b""
    if include_road:
        road_layer = _bytes_field(1, b"road")
        for _ in range(road_features):
            road_layer += _bytes_field(2, _varint_field(3, 2))
        road_layer += _varint_field(15, 2)  # MVT layer version.
        tile += _bytes_field(3, road_layer)
    other = _bytes_field(1, other_layer.encode("utf-8")) + _varint_field(15, 2)
    return tile + _bytes_field(3, other)


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
    tile = _mvt_tile(road_features=3)
    calls: list[Request] = []

    def successful_opener(request: Request, timeout: int = 20):
        calls.append(request)
        if len(calls) == 1:
            return FakeResponse(json.dumps(style).encode("utf-8"))
        return FakeResponse(tile)

    result = run_preflight(
        style_uri="mapbox://styles/mapbox/standard",
        access_token=token,
        opener=successful_opener,
    )
    assert result["tileset"] == "mapbox.mapbox-streets-v8"
    assert result["tile"] == "12/1993/1581"
    assert result["tile_bytes"] == len(tile)
    assert result["layer_count"] == 2
    assert result["road_features"] == 3
    assert result["road_line_features"] == 3
    assert len(calls) == 2
    assert all(token in request.full_url for request in calls)
    assert calls[1].get_header("Accept-encoding") == "identity"

    # Mapbox Standard can expose its basemap via imports, with no root-level
    # source URL. The preflight must still inspect a real Streets v8 MVT.
    imported_style = {
        "version": 8,
        "imports": [{"id": "basemap", "url": "mapbox://styles/mapbox/standard"}],
    }
    imported_calls: list[str] = []

    def imported_opener(request: Request, timeout: int = 20):
        imported_calls.append(request.full_url)
        if len(imported_calls) == 1:
            return FakeResponse(json.dumps(imported_style).encode("utf-8"))
        return FakeResponse(_mvt_tile(road_features=2))

    imported_result = run_preflight(
        style_uri="mapbox://styles/mapbox/standard",
        access_token=token,
        opener=imported_opener,
    )
    assert imported_result["tileset"] == "mapbox.mapbox-streets-v8"
    assert imported_result["road_features"] == 2
    assert imported_result["road_line_features"] == 2

    try:
        inspect_vector_tile(_mvt_tile(road_features=0))
    except PreflightError as error:
        assert str(error) == "vector_tile_road_features_missing"
    else:
        raise AssertionError("A vector tile without road features must fail closed.")

    try:
        inspect_vector_tile(_mvt_tile(include_road=False, other_layer="transportation"))
    except PreflightError as error:
        assert str(error) == "vector_tile_road_layer_missing"
    else:
        raise AssertionError("A vector tile without the road source-layer must fail closed.")

    try:
        inspect_vector_tile(b"not-a-vector-tile")
    except PreflightError as error:
        assert str(error).startswith("vector_tile_protobuf")
    else:
        raise AssertionError("Malformed protobuf must fail closed.")

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
            style_uri="mapbox://styles/example/not-supported",
            access_token=token,
            opener=lambda *_args, **_kwargs: FakeResponse(b"{}"),
        )
    except PreflightError as error:
        assert str(error) == "unsupported_style_uri"
        assert token not in str(error)
    else:
        raise AssertionError("An unapproved style URI must fail closed.")

    assert _tile_xy(-4.7794, 37.8882, 12) == (1993, 1581)
    print("Mapbox vector-tile preflight tests: PASS (MVT road layer/features decoded; credentials redacted).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
