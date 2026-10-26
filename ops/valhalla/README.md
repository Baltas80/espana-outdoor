# Valhalla production deployment

España Outdoor delegates outdoor routing to the mature Valhalla engine. The repository contains deployment tooling, but the production instance and regional OSM tiles remain external infrastructure.

## Runtime contract

The mobile client receives only the first-party `VALHALLA_BASE_URL`. In production this URL must be HTTPS and must not point to the public Valhalla demo endpoint.

Required production properties:

- Valhalla image pinned to `3.9.0` and recorded in the deployment change record.
- Spain regional tiles built from an approved OSM/Geofabrik extract.
- Health endpoint exposed only through the controlled routing service.
- Reverse proxy/TLS termination in front of Valhalla.
- No public direct exposure of port 8002.
- Backups or reproducible rebuild procedure for the regional tile set.
- Monitoring for `/status` and route latency/error rates.

## Build Spain tiles

Run the build from a controlled Linux host with Docker:

```bash
OSM_SPAIN_PBF_URL="https://download.geofabrik.de/europe/spain-latest.osm.pbf" \
  ./ops/valhalla/build-spain.sh
```

The generated PBF and Valhalla tiles are intentionally outside Git. For reproducible production rebuilds, record the exact source URL/date and artifact digest in the infrastructure change record before deployment.

## Start the service

```bash
cd ops/valhalla
docker compose up -d
```

The compose file binds Valhalla to loopback on port 8002. Put the HTTPS reverse proxy in front of it and expose only the proxy publicly.

## Smoke test

The production smoke gate requires an HTTPS endpoint, matching the mobile production policy and `.github/workflows/valhalla-smoke.yml`. Set `VALHALLA_BASE_URL` to the controlled HTTPS reverse-proxy endpoint and run:

```bash
VALHALLA_BASE_URL="${VALHALLA_BASE_URL:?configure the real HTTPS endpoint first}" bash ./ops/valhalla/smoke-test.sh
```

This is a placeholder for operator-supplied configuration, not a real service address. The gate validates service health, a real pedestrian route and elevation response; it does not fabricate a fallback route. Local HTTP-only testing is intentionally not accepted by this production gate.

## Mobile configuration

The Flutter application accepts:

```text
VALHALLA_BASE_URL=https://routing.example.com/
```

Routing is disabled when this value is absent or invalid. HTTP endpoints are accepted only in debug/development configuration.
