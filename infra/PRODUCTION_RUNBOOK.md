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
2. Set `KEYCLOAK_HOSTNAME=https://auth.espanaoutdoor.es`, `KEYCLOAK_PROXY_HEADERS=xforwarded` and keep `KC_HOSTNAME_STRICT=true`. Set `OIDC_ISSUER=https://auth.espanaoutdoor.es/realms/espana-outdoor` to the exact same issuer advertised by discovery. With edge TLS termination, Keycloak listens on private HTTP (`KC_HTTP_ENABLED=true`) while the public hostname remains HTTPS.
3. Configure the reverse proxy to overwrite (not append or trust client-supplied) `X-Forwarded-Host`, `X-Forwarded-Proto`, `X-Forwarded-Port` and `X-Forwarded-For`. Keep Keycloak port 8080 private and reachable only from the reverse proxy and trusted internal services. Do not disable hostname strictness to make discovery work.
4. Create production secrets outside Git (`POSTGRES_PASSWORD`, `KEYCLOAK_DB_PASSWORD`, `KEYCLOAK_ADMIN_PASSWORD`, `DATABASE_URL` with `sslmode=require` or `verify-full`, `LOCATION_ENCRYPTION_KEY`, provider credentials). Both Source Gateway and Rescue Link must use TLS-protected PostgreSQL URLs.
5. Configure a real `PUBLIC_SHARE_BASE_URL` using HTTPS.
6. Configure the licensed offline map provider and populate `MAP_PMTILES_URL`/tile storage as required.
7. Provision Valhalla Spain/required-region tiles from a licensed source and verify the dataset version.
8. Configure the AEMET API credential and expiry metadata.
9. Configure a dedicated Keycloak resource-server audience for Source Gateway (for example `espana-outdoors-api`) and map it into access tokens. Set `OIDC_REQUIRED_ROLE` under that API client.
10. Configure a different dedicated Rescue Link audience (for example `espana-outdoors-rescue-api`), map it into access tokens, and set `RESCUE_LINK_OIDC_AUDIENCE`. Do not reuse either public client ID or the Source Gateway audience.
11. Set `ALLOW_HTTP_DEV=false` in production; the local Compose exception must never be carried into production.
12. Restrict database, Keycloak, Martin, Valhalla, NATS and monitoring ports to the private network. Only intended public HTTPS endpoints may be exposed.

## Bring-up order

The Postgres entrypoint runs `infra/postgres/init/99-ensure-keycloak-db.sh` only when the data directory is initialized for the first time. It idempotently creates the `keycloak` role/database and synchronizes the role password with `KEYCLOAK_DB_PASSWORD`. If a persistent volume already exists, adding this file does not rerun initialization: apply the equivalent role/database SQL as a controlled migration before starting Keycloak. Never delete a production volume to force initialization.

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
