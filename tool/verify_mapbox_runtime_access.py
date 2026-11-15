#!/usr/bin/env python3
"""Verify that the configured public Mapbox token can fetch the app's style and vector tiles.

The script prints only endpoint labels, HTTP status codes and byte counts. It never
prints request URLs, response bodies, or the access token.
"""

from __future__ import annotations

import json
import math
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen

STYLE_ENDPOINT = "https://api.mapbox.com/styles/v1/mapbox/outdoors-v12"
CORDOBA = (37.8882, -4.7794)
ZOOM = 12


class PreflightError(RuntimeError):
    pass


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
    except HTTPError as error:
        raise PreflightError(f"{label}_http_status={error.code}") from None
    except URLError as error:
        reason = getattr(error, "reason", None)
        reason_name = type(reason).__name__ if reason is not None else "unknown"
        raise PreflightError(f"{label}_network_error={reason_name}") from None
    except TimeoutError:
        raise PreflightError(f"{label}_timeout=true") from None

    with response:
        status = getattr(response, "status", 200)
        body = response.read()
    if status != 200:
        raise PreflightError(f"{label}_http_status={status}")
    if not body:
        raise PreflightError(f"{label}_empty_response=true")
    return body


def _with_access_token(url: str, token: str) -> str:
    parts = urlsplit(url)
    query = parse_qs(parts.query, keep_blank_values=True)
    query["access_token"] = [token]
    return urlunsplit(
        (parts.scheme, parts.netloc, parts.path, urlencode(query, doseq=True), parts.fragment)
    )


def _tile_xy(latitude: float, longitude: float, zoom: int) -> tuple[int, int]:
    scale = 1 << zoom
    x = int((longitude + 180.0) / 360.0 * scale)
    latitude_radians = math.radians(latitude)
    y = int(
        (1.0 - math.asinh(math.tan(latitude_radians)) / math.pi)
        / 2.0
        * scale
    )
    return x, y


def _first_vector_dataset(style: dict) -> tuple[str, dict]:
    sources = style.get("sources")
    if not isinstance(sources, dict):
        raise PreflightError("style_sources_missing=true")
    for source in sources.values():
        if not isinstance(source, dict):
            continue
        source_url = source.get("url")
        if isinstance(source_url, str) and source_url.startswith("mapbox://"):
            dataset = source_url.removeprefix("mapbox://").split(",", 1)[0].strip()
            if dataset:
                return dataset, source
        tiles = source.get("tiles")
        if isinstance(tiles, list) and tiles and isinstance(tiles[0], str):
            return "", source
    raise PreflightError("style_vector_source_missing=true")


def verify_runtime_access(token: str, opener=urlopen) -> dict[str, int | str]:
    token = token.strip()
    if not token.startswith("pk.") or len(token) < 20:
        raise PreflightError("public_access_token_missing_or_invalid=true")

    style_url = _with_access_token(STYLE_ENDPOINT, token)
    style_payload = _request_bytes(style_url, "style", opener)
    try:
        style = json.loads(style_payload)
    except (TypeError, ValueError):
        raise PreflightError("style_json_invalid=true") from None
    if not isinstance(style, dict) or style.get("version") != 8:
        raise PreflightError("style_schema_invalid=true")

    dataset, source = _first_vector_dataset(style)
    tile_template = None
    tilejson_status = "not_required"
    if dataset:
        tilejson_url = _with_access_token(
            f"https://api.mapbox.com/v4/{dataset}.json?secure",
            token,
        )
        tilejson_payload = _request_bytes(tilejson_url, "tilejson", opener)
        try:
            tilejson = json.loads(tilejson_payload)
        except (TypeError, ValueError):
            raise PreflightError("tilejson_invalid=true") from None
        tiles = tilejson.get("tiles") if isinstance(tilejson, dict) else None
        if not isinstance(tiles, list) or not tiles or not isinstance(tiles[0], str):
            raise PreflightError("tilejson_tiles_missing=true")
        tile_template = tiles[0]
        tilejson_status = "200"
    else:
        tiles = source.get("tiles")
        if not isinstance(tiles, list) or not tiles:
            raise PreflightError("vector_tile_template_missing=true")
        tile_template = tiles[0]

    x, y = _tile_xy(CORDOBA[0], CORDOBA[1], ZOOM)
    tile_url = (
        tile_template.replace("{z}", str(ZOOM))
        .replace("{x}", str(x))
        .replace("{y}", str(y))
        .replace("{id}", dataset)
        .replace("{access_token}", token)
        .replace("{ratio}", "")
    )
    tile_url = _with_access_token(tile_url, token)
    tile_payload = _request_bytes(tile_url, "vector_tile", opener)

    return {
        "style_http": 200,
        "tilejson_http": tilejson_status,
        "vector_tile_http": 200,
        "vector_tile_bytes": len(tile_payload),
        "dataset": dataset or "style_source_tiles",
    }


def main() -> int:
    try:
        result = verify_runtime_access(os.environ.get("MAPBOX_ACCESS_TOKEN", ""))
    except PreflightError as error:
        print(f"MAPBOX_RUNTIME_PREFLIGHT failed {error}", file=sys.stderr)
        return 1
    print(
        "MAPBOX_RUNTIME_PREFLIGHT "
        f"style_http={result['style_http']} "
        f"tilejson_http={result['tilejson_http']} "
        f"vector_tile_http={result['vector_tile_http']} "
        f"vector_tile_bytes={result['vector_tile_bytes']} "
        f"dataset={result['dataset']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
