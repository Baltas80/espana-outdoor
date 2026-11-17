#!/usr/bin/env python3
"""Check that the staging Mapbox token can read the selected style and a vector tile.

The token is read only from the environment and is never printed or included in
an exception message. This separates token/network failures from native map
rendering failures in the Android smoke test.
"""
from __future__ import annotations

import argparse
import json
import math
import os
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
            "User-Agent": "espana-outdoor-mapbox-preflight/1",
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
    if len(tile_bytes) < 64:
        raise PreflightError("vector_tile_empty_or_truncated")

    return {
        "style": style_uri,
        "tileset": tileset_id,
        "tile": f"{zoom}/{x}/{y}",
        "tile_bytes": len(tile_bytes),
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
        f"tile={result['tile']} bytes={result['tile_bytes']} token_present=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
