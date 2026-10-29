# España Outdoor — External Services Contract Matrix

Status date: 2026-09-24

This document is the production gate for external services. A service is **not production-ready** until its account/terms are actually accepted and its endpoint has been verified. No credentials or URLs are fabricated in this repository.

| Service | Selected approach | Required contract/account | Current state | Production evidence |
|---|---|---|---|---|
| OSM data | Geofabrik OSM PBF + ODbL attribution | Compliant use/attribution | READY TO BUILD | PBF checksum + attribution |
| Routing | Self-hosted Valhalla | Compute/storage/operations account | BLOCKED: hosting account not provisioned | `/status` + route/elevation smoke tests |
| Weather/live data | AEMET OpenData | API key and current API terms | BLOCKED: production API key not configured | Authenticated health/data check |
| Rescue Link | Dedicated production hosting/domain | Hosting/domain + operational controls | BLOCKED: external infrastructure not provisioned | HTTPS health check + authenticated integration test |
| Android distribution | Google Play Console | Developer account + Developer Distribution Agreement | BLOCKED: store account/configuration not verified | Internal/closed release gate |
| iOS distribution | Apple Developer Program / App Store Connect | Developer membership + agreements/certificates | BLOCKED: production account/configuration not verified | TestFlight/release gate |

## Verified external facts

### AEMET
AEMET OpenData requires an API key for programmatic access. AEMET's July 2026 notice says newly issued API keys have a three-month expiry, so the production integration must include key rotation rather than assuming an indefinite credential. The application must not ship the key in the mobile binary; the gateway owns the credential.

Official sources:
- https://opendata.aemet.es/centrodedescargas/info
- https://opendata.aemet.es/centrodedescargas/novedades

### Valhalla
Valhalla is open source and can be run on infrastructure controlled by the project. The official documentation recommends Docker for running a server and documents building routing tiles from OSM extracts. A public demo server exists, but it is subject to fair-use/rate limits and is **not** selected as the production dependency for España Outdoor.

Official source: https://valhalla.github.io/valhalla/

### Google Play
Google requires a developer account, acceptance of the Developer Distribution Agreement, a registration fee, and identity/account verification. Personal and organization accounts have different requirements; the final account type must be selected before store release.

Official sources:
- https://support.google.com/googleplay/android-developer/answer/6112435
- https://support.google.com/googleplay/android-developer/answer/13628312

## Contract checklist

For every provider, record before production:

- Provider/legal entity
- Service/product
- Account owner
- Billing owner
- Contract / terms URL
- Licence and permitted use
- Data processing/DPA requirements
- Data retention
- Data region/location
- Pricing and expected monthly cost
- Rate limits/quotas
- SLA/availability terms
- Security responsibilities
- Incident/support channel
- Cancellation/export process
- Renewal/expiry date
- Production endpoint
- Health-check evidence
- Secret/configuration location

## Non-negotiable rules

1. Never commit secrets to Git.
2. Never hard-code a fake production endpoint.
3. Never use a public routing demo as the production routing backend.
4. Never distribute AEMET credentials in the mobile application.
5. Never call the real 112 number during QA; emergency behavior is tested with a non-dialing test adapter/sandbox.
6. Never declare a service production-ready based only on code/CI. The external account and endpoint must exist and be verified.
