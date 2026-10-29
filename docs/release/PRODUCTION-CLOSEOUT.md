# España Outdoor — Production closeout

This document is the release-control checklist for the final parallel workstream.

## A. Android physical QA

The CI Android artifact is necessary but not sufficient. Install the exact CI APK/AAB build under test on a physical Android device and record:

- device model and Android version;
- build identifier / commit SHA;
- clean install and cold start;
- runtime permissions;
- GPS acquisition and accuracy;
- map rendering;
- route planning;
- navigation guidance and reroute;
- offline region download and airplane-mode rendering;
- SOS preparation and 112 handoff without routine live calls;
- Rescue Link create/copy/revoke;
- background location / screen-off;
- battery and thermal sanity.

The Mapbox migration must be built with `MAPBOX_ACCESS_TOKEN`. A successful build does not replace physical validation of map rendering, offline downloads and airplane-mode reopening.

## B. iOS physical QA

CI already verifies the native location configuration and produces a no-code-sign release build. Physical validation still requires Apple device/test distribution and the same core route, map, offline, navigation, SOS and Rescue Link flows.

## C. External production infrastructure

The application boundary is already provider-neutral. Do not hard-code credentials or silently substitute public demo endpoints.

Required production services:

1. **Mapbox** — valid `MAPBOX_ACCESS_TOKEN`, account configuration, required style access and verified offline-region behaviour.
2. **Valhalla** — dedicated production instance with Spain routing tiles and HTTPS.
3. **Live Data Gateway** — HTTPS endpoint with real AEMET credentials, OIDC and monitoring.
4. **Rescue Link** — HTTPS service, Keycloak/OIDC realm, PostgreSQL, managed secret material, backups and monitoring.

All four must have health checks and an application-level smoke test before release.

## D. Visual pack

Current repository assets include the LAND-01, LAND-02 and LAND-03 landscape assets plus the page background system. LAND assets are visual content only; UI controls never belong inside the images.

The Home hero now consumes the repository LAND-01 asset. The final BG-01 hero (person + dog on a Spanish trail) remains a replacement asset requirement if it has not yet been committed as a real image file.

Continue with LAND-04 and the flora/fauna pack without changing the locked UI structure.

## E. Navigation E2E

Release evidence must cover:

`GPS -> route request -> Valhalla -> route geometry -> guidance -> off-route detection -> reroute -> arrival`

The unit-level navigation guidance and Valhalla adapter tests are not a substitute for this physical E2E run.

## F. Final QA

No release candidate is green until Android and iOS evidence is attached to the physical QA gate and all critical failures have a reproducible resolution.

## G. Stores

Only after A-F:

- Android signed AAB;
- Play Console release track and policy/privacy material;
- iOS signed archive;
- App Store Connect / TestFlight;
- final screenshots and metadata;
- production monitoring and rollback plan.

## Runtime configuration

Production values are injected at build/deployment time. Example:

```text
--dart-define=APP_ENV=production
--dart-define=MAPBOX_ACCESS_TOKEN=<token-injected-by-CI>
--dart-define=VALHALLA_BASE_URL=https://<routing-domain>/
--dart-define=SOURCE_GATEWAY_BASE_URL=https://<gateway-domain>/
--dart-define=RESCUE_LINK_BASE_URL=https://<rescue-domain>/
```

Do not commit actual credentials or privileged keys. Inject `MAPBOX_ACCESS_TOKEN` through the protected build configuration. A placeholder is intentionally not treated as a working production configuration.
