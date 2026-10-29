# Production adapters

## Routing — Valhalla

`ValhallaRoutingService` is the application adapter for a self-hosted Valhalla deployment. The application does not implement routing algorithms.

Recommended production endpoint:

```text
https://routing.example.com/
```

The endpoint must be controlled by España Outdoor or a contracted infrastructure provider. Do not depend on a public demo endpoint for production traffic.

Supported application profiles currently map to Valhalla `pedestrian`, `bicycle` and `auto` costing models. The adapter also exposes Valhalla map matching through `trace_route`.

Valhalla supports route, map matching, matrix, isochrone and elevation services. Keep those capabilities behind provider-neutral contracts so another engine can be introduced without changing product features.

## Weather — AEMET OpenData

`AemetOpenDataSource` consumes the official AEMET OpenData REST envelope and follows its `datos` URL to retrieve the actual dataset.

The API key is runtime configuration only. Never commit it to Git. AEMET currently requires API keys and has announced that keys without an expiration date will stop working on 15 October 2026; new keys have a three-month validity period. Operationally, key renewal must therefore be part of deployment management.

Suggested runtime configuration:

```text
AEMET_API_KEY=<secret-manager-value>
AEMET_SOURCE_BASE=https://opendata.aemet.es/opendata/api/
```

AEMET attribution must be retained in user-facing source information where applicable.

## Maps and offline regions

Mapbox Maps SDK (`mapbox_maps_flutter`) is the sole cartographic renderer. The client uses the native offline-region capabilities of the SDK; no parallel map-package catalog is required. Validate token configuration, download lifecycle, persistence and offline rendering on Android before declaring production readiness.

A production map-region record should include:

- region identifier
- geographic bounds
- tile format
- source dataset
- attribution
- license
- dataset version
- generated timestamp
- minimum/maximum zoom
- byte size
- checksum
- expiry/update policy

Do not ship a map catalog claiming data availability until the corresponding artifact exists and has passed integrity validation.

## Security boundary

All three integrations are infrastructure adapters. API keys and private service URLs belong in deployment secret management. Public clients must not receive provider credentials unless the provider explicitly requires public client credentials.
