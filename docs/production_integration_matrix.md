# Production integration matrix

This document separates implemented application foundations from production integrations that require deployment configuration, provider credentials or operational infrastructure.

| Capability | Mature technology | App boundary | Production requirement |
|---|---|---|---|
| Cross-platform UI | Flutter | feature layer | platform projects + store signing |
| Maps | MapLibre Flutter | `MapService` | approved HTTPS style/source |
| Offline maps | Pending implementation | `MapService` | Android offline validation required |
| Routing | Valhalla | `RoutingService` | Valhalla deployment + regional tiles |
| GIS database | PostgreSQL/PostGIS | backend API | managed PostgreSQL/PostGIS |
| GIS processing | GDAL/PROJ | data pipeline | scheduled ETL workers |
| Identity | Keycloak / OIDC | `AuthService` | hardened IdP + MFA policy |
| Subscriptions | RevenueCat | entitlement boundary | App Store/Google Play/web products |
| Weather | AEMET OpenData | `SourceGateway` | API key/configuration + quotas |
| Environment | MITECO / OGC | `SourceGateway` | endpoint catalogue + licence metadata |
| Official GIS | IGN/CNIG / OGC | `SourceGateway` | endpoint catalogue + attribution |
| Emergency | OS/platform telephony + backend | `EmergencyService` | legal/operational validation |
| Observability | Sentry + OpenTelemetry | telemetry boundary | DSN/exporter + retention policy |
| Metrics | Prometheus/Grafana | backend/infra | deployment + dashboards |
| Security | Trivy/Gitleaks/Dependabot | CI | repository permissions + remediation workflow |

## Rules

1. A provider must never be referenced directly by product features when a contract exists.
2. Official data is displayed with source, observed time and freshness/expiry metadata.
3. Missing credentials or unavailable providers produce an explicit degraded state; they never produce fabricated data.
4. Emergency features remain conservative when dependencies are unavailable and must preserve the local emergency path.
5. Third-party licences and attribution are retained independently from the proprietary Spain Outdoor licence.
6. Secrets are injected by the deployment environment and are never committed to Git.
