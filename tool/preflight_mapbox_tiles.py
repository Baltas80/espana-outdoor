#!/usr/bin/env python3
"""Check Mapbox style access and inspect a real Streets v8 vector tile.

The token is read only from the environment and is never printed or included in
an exception message. The tile probe decodes the Mapbox Vector Tile protobuf so
a successful HTTP response cannot be mistaken for a tile containing renderable
road features.
"""
from __future__ import annotations

import argparse
import gzip
import json
import math
import os
from collections.abc import Iterator
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


class PreflightError(RuntimeError):
    """A sanitized Mapbox preflight failure."""


SUPPORTED_STYLES = {
    "mapbox://styles/mapbox/outdoors-v12",
    "mapbox://styles/mapbox/standard",
}


def _style_endpoint(style_uri: str, token: str) -> str:
    prefix = "mapbox://styles/"
    if not style_uri.startswith(prefix):
        raise PreflightError("unsupported_style_uri")
    identity = style_uri[len(prefix):].strip("/")
    parts = identity.split("/")
    if len(parts) != 2 or not all(parts):
        raise PreflightError("invalid_style_uri")
    owner, style_id = parts
    return f"https://api.mapbox.com/styles/v1/{owner}/{style_id}?{urlencode({'access_token': token})}"


def _request_bytes(url: str, label: str, opener=urlopen) -> bytes:
    request = Request(
        url,
        headers={
            "Accept": "application/json, application/x-protobuf",
            "Accept-Encoding": "identity",
            "User-Agent": "espana-outdoor-mapbox-preflight/2",
        },
    )
    try:
        response = opener(request, timeout=20)
        with response:
            status = getattr(response, "status", None)
            if status is None:
                status = response.getcode()
            if status != 200:
                raise PreflightError(f"{label}_http_status={status}")
            return response.read()
    except HTTPError as error:
        # Never stringify HTTPError: its URL may contain the access token.
        raise PreflightError(f"{label}_http_status={error.code}") from None
    except URLError as error:
        reason = getattr(error, "reason", None)
        reason_type = type(reason).__name__ if reason is not None else "unknown"
        raise PreflightError(f"{label}_network_error={reason_type}") from None
    except TimeoutError:
        raise PreflightError(f"{label}_timeout") from None
    except PreflightError:
        raise
    except Exception as error:
        raise PreflightError(f"{label}_error={type(error).__name__}") from None


def _streets_tileset(style: dict, style_uri: str) -> str:
    sources = style.get("sources")
    if not isinstance(sources, dict):
        if style_uri in SUPPORTED_STYLES:
            return "mapbox.mapbox-streets-v8"
        raise PreflightError("style_sources_missing")
    for source in sources.values():
        if not isinstance(source, dict):
            continue
        source_url = source.get("url")
        if isinstance(source_url, str) and source_url.startswith("mapbox://"):
            ids = source_url[len("mapbox://"):].split(",")
            for tileset_id in ids:
                tileset_id = tileset_id.strip()
                if tileset_id.endswith("mapbox-streets-v8") or tileset_id == "mapbox.mapbox-streets-v8":
                    return tileset_id
    # Mapbox Standard exposes its basemap through style imports rather than
    # root-level sources. Both staging-supported styles use the public Streets
    # v8 vector tileset, so probe that known source when the root style is
    # imported/fragment-based.
    if style_uri in SUPPORTED_STYLES:
        return "mapbox.mapbox-streets-v8"
    raise PreflightError("style_has_no_mapbox_streets_v8_source")


def _tile_xy(longitude: float, latitude: float, zoom: int) -> tuple[int, int]:
    if not -180 <= longitude <= 180 or not -85.05112878 <= latitude <= 85.05112878:
        raise PreflightError("coordinates_out_of_range")
    if not 0 <= zoom <= 22:
        raise PreflightError("zoom_out_of_range")
    scale = 1 << zoom
    x = int((longitude + 180.0) / 360.0 * scale)
    lat_radians = math.radians(latitude)
    y = int((1.0 - math.asinh(math.tan(lat_radians)) / math.pi) / 2.0 * scale)
    return min(max(x, 0), scale - 1), min(max(y, 0), scale - 1)


def _read_varint(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while offset < len(data) and shift < 70:
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, offset
        shift += 7
    raise PreflightError("vector_tile_protobuf_invalid")


def _protobuf_fields(data: bytes) -> Iterator[tuple[int, int, int | bytes]]:
    """Read protobuf wire fields without depending on generated code."""
    offset = 0
    while offset < len(data):
        tag, offset = _read_varint(data, offset)
        field_number, wire_type = tag >> 3, tag & 0x07
        if field_number == 0:
            raise PreflightError("vector_tile_protobuf_invalid")
        if wire_type == 0:
            value, offset = _read_varint(data, offset)
        elif wire_type == 1:
            end = offset + 8
            if end > len(data):
                raise PreflightError("vector_tile_protobuf_truncated")
            value = data[offset:end]
            offset = end
        elif wire_type == 2:
            length, offset = _read_varint(data, offset)
            end = offset + length
            if end > len(data):
                raise PreflightError("vector_tile_protobuf_truncated")
            value = data[offset:end]
            offset = end
        elif wire_type == 5:
            end = offset + 4
            if end > len(data):
                raise PreflightError("vector_tile_protobuf_truncated")
            value = data[offset:end]
            offset = end
        else:
            # Mapbox Vector Tile does not use deprecated protobuf groups.
            raise PreflightError("vector_tile_protobuf_wire_type_unsupported")
        yield field_number, wire_type, value


def _feature_geometry_type(feature: bytes) -> int | None:
    for field_number, wire_type, value in _protobuf_fields(feature):
        if field_number == 3 and wire_type == 0:
            return int(value)
    return None


def inspect_vector_tile(tile_bytes: bytes) -> dict[str, object]:
    """Return layer and road-feature counts from an MVT protobuf payload."""
    payload = tile_bytes
    if payload.startswith(b"\x1f\x8b"):
        try:
            payload = gzip.decompress(payload)
        except OSError:
            raise PreflightError("vector_tile_gzip_invalid") from None
    if len(payload) < 8:
        raise PreflightError("vector_tile_empty_or_truncated")

    layer_names: list[str] = []
    road_features = 0
    road_line_features = 0
    for field_number, wire_type, layer_bytes in _protobuf_fields(payload):
        if field_number != 3 or wire_type != 2 or not isinstance(layer_bytes, bytes):
            continue
        name: str | None = None
        feature_payloads: list[bytes] = []
        for layer_field, layer_wire, value in _protobuf_fields(layer_bytes):
            if layer_field == 1 and layer_wire == 2 and isinstance(value, bytes):
                try:
                    name = value.decode("utf-8")
                except UnicodeDecodeError:
                    raise PreflightError("vector_tile_layer_name_invalid") from None
            elif layer_field == 2 and layer_wire == 2 and isinstance(value, bytes):
                feature_payloads.append(value)
        if name is None:
            raise PreflightError("vector_tile_layer_name_missing")
        layer_names.append(name)
        if name == "road":
            road_features += len(feature_payloads)
            road_line_features += sum(
                _feature_geometry_type(feature) == 2
                for feature in feature_payloads
            )

    if not layer_names:
        raise PreflightError("vector_tile_layers_missing")
    if "road" not in layer_names:
        raise PreflightError("vector_tile_road_layer_missing")
    if road_features == 0:
        raise PreflightError("vector_tile_road_features_missing")
    if road_line_features == 0:
        raise PreflightError("vector_tile_road_line_features_missing")

    return {
        "layer_count": len(layer_names),
        "layer_names": sorted(set(layer_names)),
        "road_features": road_features,
        "road_line_features": road_line_features,
    }


def run_preflight(
    *,
    style_uri: str,
    access_token: str,
    longitude: float = -4.7794,
    latitude: float = 37.8882,
    zoom: int = 12,
    opener=urlopen,
) -> dict[str, object]:
    token = access_token.strip()
    if not token:
        raise PreflightError("access_token_missing")
    if style_uri not in SUPPORTED_STYLES:
        raise PreflightError("unsupported_style_uri")

    style_url = _style_endpoint(style_uri, token)
    style_bytes = _request_bytes(style_url, "style", opener)
    try:
        style = json.loads(style_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise PreflightError("style_json_invalid") from None
    if not isinstance(style, dict):
        raise PreflightError("style_json_not_object")

    tileset_id = _streets_tileset(style, style_uri)
    x, y = _tile_xy(longitude, latitude, zoom)
    tile_url = (
        f"https://api.mapbox.com/v4/{tileset_id}/{zoom}/{x}/{y}.vector.pbf?"
        f"{urlencode({'access_token': token})}"
    )
    tile_bytes = _request_bytes(tile_url, "vector_tile", opener)
    tile_info = inspect_vector_tile(tile_bytes)

    return {
        "style": style_uri,
        "tileset": tileset_id,
        "tile": f"{zoom}/{x}/{y}",
        "tile_bytes": len(tile_bytes),
        **tile_info,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--style-uri",
        default=os.environ.get("MAPBOX_STYLE_URI", "mapbox://styles/mapbox/outdoors-v12"),
    )
    parser.add_argument("--longitude", type=float, default=-4.7794)
    parser.add_argument("--latitude", type=float, default=37.8882)
    parser.add_argument("--zoom", type=int, default=12)
    args = parser.parse_args()

    token = os.environ.get("MAPBOX_ACCESS_TOKEN", "")
    try:
        result = run_preflight(
            style_uri=args.style_uri,
            access_token=token,
            longitude=args.longitude,
            latitude=args.latitude,
            zoom=args.zoom,
        )
    except PreflightError as error:
        print(f"MAPBOX_PREFLIGHT failed reason={error}")
        return 1

    print(
        "MAPBOX_PREFLIGHT ok "
        f"style={result['style']} tileset={result['tileset']} "
        f"tile={result['tile']} bytes={result['tile_bytes']} "
        f"layers={result['layer_count']} road_features={result['road_features']} "
        f"road_line_features={result['road_line_features']} token_present=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
