# Production readiness

## Current product boundary

España Outdoor uses mature third-party infrastructure for commodity layers and keeps proprietary code focused on product differentiation and safety-critical orchestration.

### Mature components

- Flutter/Dart: mobile application shell.
- Mapbox Maps SDK: cartographic rendering and native offline regions.
- Valhalla: outdoor routing, map matching and turn-by-turn data.
- Hive CE: local route/offline metadata and crash-recoverable active-route segments during MVP.
- background_downloader: resumable native downloads.
- RevenueCat: subscription/billing entitlements.
- OpenID Connect / Keycloak: standards-based identity.
- Sentry: crash/error telemetry.
- GitHub Actions + Dependabot + Trivy + Gitleaks: CI and supply-chain baseline.
- Rescue Link first-party Go service: server-authoritative expiry, revocation and role-scoped location access.

## Rescue Link backend

The service lives under `services/rescue-link`. It uses PostgreSQL/pgx, OIDC verification and a small standard-library HTTP surface.

Security controls implemented in the service:

- opaque random share tokens; only SHA-256 hashes are stored;
- AES-256-GCM encryption for exact emergency coordinates;
- server-side expiry and immediate revocation;
- role-derived access from OIDC claims;
- responder limits and rate limiting;
- approximate public discovery;
- capability tokens with independent expiry;
- no exact coordinates or tokens in normal application logs;
- automatic retention cleanup.

Production deployment still requires a controlled Keycloak realm, role assignment/verification, HTTPS edge, a secret-managed AES-256 key, database backups and integration tests on real credentials. See `docs/api/rescue-link.md`.

## Runtime configuration

Secrets and provider endpoints are injected at build/deployment time. They must never be committed.

| Variable | Purpose | Required in production |
|---|---|---|
| VALHALLA_BASE_URL | Routing endpoint | Yes |

| SOURCE_GATEWAY_BASE_URL | First-party normalized official-data gateway | Yes |
| RESCUE_LINK_BASE_URL | First-party Rescue Link API | Yes |
| SENTRY_DSN | Error/crash telemetry | Yes |
| APP_ENV | Environment label | Yes |
| MAPBOX_ACCESS_TOKEN | Mapbox SDK access token injected at build time | Yes |

| REVENUECAT_API_KEY | Public RevenueCat SDK key | Yes for store billing |
| OIDC_ISSUER | Keycloak/OIDC issuer | Yes |
| OIDC_CLIENT_ID | Public OIDC client identifier | Yes |
| OIDC_REDIRECT_URI | Registered OIDC callback | Yes |

## Safety data policy

The risk engine is deterministic and auditable. A risk score is not a safety guarantee. Every dynamic signal must carry source, freshness and expiry where applicable.

Emergency features must not depend on analytics, billing or remote map availability.

## Release gates

A production release is blocked unless:

1. flutter analyze passes with no warnings/errors.
2. Unit and widget tests pass.
3. Routing/offline focused tests pass.
4. Go backend tests and vet pass.
5. Gitleaks reports no secrets.
6. Trivy has no unfixed HIGH/CRITICAL finding accepted without an explicit security decision.
7. Dependency licences have been reviewed.
8. Dynamic sources have documented attribution, freshness and fallback behaviour.
9. No production endpoint or secret is hard-coded in the client.
10. SOS/112 flows have been tested on supported mobile hardware.
11. Offline navigation has been tested with connectivity disabled.
12. Android release APK/AAB and iOS release (no-code-sign CI build) complete successfully.
13. Rescue Link backend expiry, revocation and role-based visibility have been integration-tested.

## Known external prerequisites

The repository can implement and validate client contracts without inventing infrastructure credentials. Production still requires deployment of the backend/source gateway, Valhalla regional tiles, Mapbox access-token configuration, Keycloak realm/client configuration, RevenueCat store configuration, Sentry project and Rescue Link service. These are environment/service configuration tasks, not values that should be fabricated in Git.
