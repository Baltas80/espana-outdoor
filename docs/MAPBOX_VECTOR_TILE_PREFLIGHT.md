# Mapbox vector-tile preflight

## Purpose

A successful HTTP 200 for a Mapbox vector-tile URL proves that the token can
retrieve bytes. It does not prove that the response is a valid Mapbox Vector
Tile (MVT), that the expected source layer exists, or that the layer contains
line features which the diagnostic MapWidget can render.

tool/preflight_mapbox_tiles.py now parses the MVT protobuf payload without an
additional dependency. It reports:

- Total layer count and layer names.
- Feature count in the road source layer.
- Number of LINESTRING road features.

The preflight fails closed if the payload is malformed, has no layers, omits
the road layer, or contains no road line features. It requests identity
encoding and transparently handles a gzip payload if a proxy returns one.

The Mapbox access token is read only from MAPBOX_ACCESS_TOKEN. It is used in
the request URL but never printed, returned in a result, or included in a
sanitized exception.

## Current Android evidence

Run [44168737622](https://github.com/Baltas80/espana-outdoor/actions/runs/44168737622),
source commit 2666ac2dcff0499b6d3703cf7389e2b1a650449a:

- Primary APK: Standard + Virtual Display/TextureView + Impeller + TileStore
  default.
- Diagnostic APK: same style, hosting and renderer, with TileStore disabled.
- Both APKs built, passed package/hash checks, installed and opened the Map
  page in the API 35 CI emulator.
- The vector diagnostic style was accepted by the live MapWidget.
- Each variant recorded 14 non-empty successful network tile responses,
  totalling 459,888 bytes in the captured diagnostic window.
- Primary recorded 14 SOURCE_DATA loaded=false events and no
  loaded=true event. The TileStore-disabled variant recorded 13
  loaded=false and one loaded=true event.
- Both screenshots were uniformly the diagnostic background:
  line_pixels=0, background_ratio=1.000.
- Neither variant reached MAP_LOADED, MAP_IDLE or RenderMode.FULL.
- The workflow's required smoke gate failed. The artifact upload was retained
  so the failure can be inspected; APK compilation is not a map pass.

Artifacts:
- [Primary APK](https://github.com/Baltas80/espana-outdoor/actions/runs/44168737622/artifacts/14366714979)
- [TileStore-disabled APK](https://github.com/Baltas80/espana-outdoor/actions/runs/44168737622/artifacts/14367748385)
- [Smoke screenshots and logcat](https://github.com/Baltas80/espana-outdoor/actions/runs/44168737622/artifacts/14368552612)

## Interpretation and next action

The run proves that the style JSON was accepted and that the SDK received
non-empty tile responses. It does not yet prove that the downloaded tile
contains the road source layer and line features, nor that the SDK decoded
those features successfully.

The updated preflight closes that evidence gap before another expensive
emulator run. If it confirms road features in the exact Córdoba tile while
the live MapWidget still produces zero road pixels, the investigation moves
to source-layer/style application and SDK decoding/rendering. If it fails, the
preflight error identifies whether the tile is malformed or lacks the
expected layer/features.

This preflight is an online diagnostic only. It does not certify offline tile
download, persistence, routing, restart behavior, or a physical Android device.
