# España Outdoor — production infrastructure runbook

This document is the deployment gate for the external services. It intentionally does not contain credentials.

## Required production services

- PostgreSQL/PostGIS
- Keycloak
- Source/Live Data Gateway
- Rescue Link
- Martin tile service
- Valhalla routing
- NATS
- Prometheus/Grafana

## Pre-deployment

1. Provision a dedicated production host/network and TLS termination.
2. Create production secrets outside Git (`POSTGRES_PASSWORD`, `KEYCLOAK_DB_PASSWORD`, `KEYCLOAK_ADMIN_PASSWORD`, `DATABASE_URL` with `sslmode=require` or `verify-full`, `LOCATION_ENCRYPTION_KEY`, provider credentials). Both Source Gateway and Rescue Link must use TLS-protected PostgreSQL URLs.
3. Configure a real `PUBLIC_SHARE_BASE_URL` using HTTPS.
4. Configure the licensed offline map provider and populate `MAP_PMTILES_URL`/tile storage as required.
5. Provision Valhalla Spain/required-region tiles from a licensed source and verify the dataset version.
6. Configure the AEMET API credential and expiry metadata.
7. Route `https://api.espanaoutdoor.es` to the private Source Gateway service. Set `SOURCE_GATEWAY_BASE_URL` and `COMMUNITY_API_BASE_URL` to that exact HTTPS origin for Android builds; the web account page uses the same origin. Configure the dedicated Keycloak resource-server audience `espana-outdoors-api`, map it into both public clients' access tokens, and set `OIDC_REQUIRED_ROLE=source.read` under that API client. Verify `/healthz` externally and test authenticated `GET /v1/me` from web and Android.
8. Configure a different dedicated Rescue Link audience (for example `espana-outdoors-rescue-api`), map it into access tokens, and set `RESCUE_LINK_OIDC_AUDIENCE`. Do not reuse either public client ID or the Source Gateway audience.
9. Set `ALLOW_HTTP_DEV=false` in production; the local Compose exception must never be carried into production.
10. Restrict database, Keycloak, Martin, Valhalla, NATS and monitoring ports to the private network. Only intended public HTTPS endpoints may be exposed.

## Bring-up order

1. `postgres` and database initialization
2. `keycloak`
3. `source-gateway`
4. `rescue-link`
5. `martin`
6. `valhalla`
7. `nats`
8. `prometheus` / `grafana`

Use the healthchecks and service logs before exposing the mobile endpoints.

## Acceptance checks

- Live Data Gateway authenticates with OIDC and returns fresh/stale data according to its cache policy.
- AEMET failures do not expose provider credentials and produce a controlled degraded response.
- Valhalla `/status` is healthy and route requests return valid routes for representative Spanish outdoor coordinates.
- Martin serves only the licensed offline/map data configured for production.
- Rescue Link creates, expires, revokes and authorizes shares according to the configured TTL/capability policy.
- TLS/HSTS is active on public endpoints.
- No production credential is present in the repository or application bundle.
- Backups and restore procedures are verified before release.

## Release blocker

The repository infrastructure definition is not proof of production deployment. The production gate remains blocked until a real environment is deployed and the above checks are evidenced.

## Safety

Do not perform a real emergency call to 112 as routine QA. Validate the application handoff and integration using the documented test/sandbox mechanisms; physical emergency behavior must be verified separately with the supported platform/operator procedures.
