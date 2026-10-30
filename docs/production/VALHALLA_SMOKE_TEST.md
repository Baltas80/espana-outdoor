# Valhalla production smoke gate

The mobile app consumes Valhalla through the runtime `VALHALLA_BASE_URL`. Production routing is not considered verified until the real endpoint passes the manual **Valhalla production smoke test** workflow.

The gate checks:

- HTTPS endpoint;
- `/status` returns HTTP 200 and valid JSON;
- `/route` returns a usable pedestrian trip with at least one leg;
- the route request uses `elevation_interval: 30`; ascent/descent are shown only when the route response contains DEM samples;
- `/height` returns elevation data for the standalone elevation service check.

The workflow is intentionally manual and uses the GitHub Environment `routing-production`. No public/demo Valhalla endpoint is embedded in the release configuration.

The smoke-test request shapes follow Valhalla's documented `/status`, `/route`, and `/height` endpoints.

## Mobile route result behavior

The Android route planner submits a Valhalla `pedestrian` request through
`VALHALLA_BASE_URL`, draws the returned GeoJSON shape in Mapbox and displays
distance, estimated duration and real maneuver instructions. It requests
elevation samples at a 30 m interval. Valhalla only returns route elevation when
the deployed graph has DEM data; when no valid samples are returned, the app
shows elevation as unavailable instead of displaying a fabricated zero.
