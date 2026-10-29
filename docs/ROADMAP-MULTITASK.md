# España Outdoor — Parallel Delivery Roadmap

The project is developed in parallel tracks so no major capability waits for another track to finish. Checked items are implemented foundations/contracts; unchecked production integrations remain explicitly tracked.

## Track A — Product & UX
- [x] premium responsive design system
- [x] home/discovery foundation
- [x] safety center foundation
- [x] pet mode foundation
- [x] wildlife guidance foundation
- [ ] route detail production UX
- [ ] navigation HUD
- [ ] offline download flow backed by real tile packs
- [ ] emergency UX hardening
- [ ] weather presentation using the shared icon family

## Track B — Maps & GIS
- [x] provider configuration abstraction
- [x] OSM-compatible attribution
- [x] GPX import/export foundation
- [x] offline capability contract
- [x] offline region model validation
- [x] persistent offline region state store
- [x] provider-neutral `MapService` boundary
- [ ] production vector-tile provider selection
- [ ] offline region downloader with pause/resume/update/delete
- [ ] elevation/profile provider
- [ ] routing engine evaluation and integration
- [ ] geospatial cache and tile budget controls

## Track C — Official data
- [x] AEMET provider-neutral contract
- [x] AEMET OpenData adapter foundation
- [x] provenance/freshness model
- [x] normalized official-alert contract
- [x] provider-neutral Source Gateway contract
- [ ] secure runtime API-key injection
- [ ] cache + retry/backoff + 429 handling policy
- [ ] official warning/CAP adapter
- [ ] wildfire/disaster adapters
- [ ] protected-area and environmental data
- [ ] stale-data safeguards at UI/query level

## Track D — Safety
- [x] GPS foundation
- [x] trusted contacts foundation
- [x] temporary location-sharing policy
- [x] SOS domain foundation
- [x] Rescue Link anti-abuse policy foundation
- [x] emergency location privacy model
- [x] offline sync contract for safety events
- [ ] 112 platform handoff hardening
- [ ] battery/connectivity telemetry in emergency snapshot
- [ ] emergency-session expiry enforcement
- [ ] end-to-end SOS tests on real devices

## Track E — Nature & pets
- [x] pet profiles
- [x] route compatibility foundation
- [x] wildlife encounter guidance foundation
- [ ] heat/water/shade factors from verified sources
- [ ] sensitive habitat protection
- [ ] conservation-aware recommendations
- [ ] Natura Protect index

## Track F — Platform
- [x] Flutter architecture targeting Android and iOS/iPadOS
- [ ] Android production build validation
- [ ] iOS production build validation
- [ ] platform-specific permission adapters
- [ ] wearable/GNSS/Bluetooth integration contracts
- Web/PWA, Windows, macOS and Linux are explicitly out of active product scope (ADR-0006).

## Track G — Security & privacy
- [x] secure local storage foundation
- [x] permission minimization policy foundation
- [x] temporary location-sharing policy
- [ ] retention matrix enforcement
- [ ] audit events
- [ ] threat model review
- [x] dependency/security scanning baseline
- [ ] SBOM release generation
- [ ] API authentication/authorization layer
- [ ] abuse/rate-limit controls

## Track H — Quality & delivery
- [x] unit tests for core GPX/safety/pet logic
- [x] CI static analysis/test workflow
- [x] dependency scanning baseline
- [ ] integration tests
- [ ] E2E tests
- [ ] offline/GPS/map test matrix
- [ ] accessibility test suite
- [ ] performance/battery tests
- [ ] release checklist and signed artifacts

## Immediate execution order

1. Wire `WeatherService` to secure runtime configuration and cache AEMET results with freshness metadata.
2. Implement the normalized official-alert model and AEMET CAP adapter.
3. Enforce the provider-neutral `MapService` boundary across map-dependent features.
4. Connect persistent offline-region state to a real licensed vector-tile/offline provider; never fake downloads.
5. Validate the existing Mapbox integration on Android with measured rendering, native offline-region downloads, cold reopen, airplane-mode rendering and GPS-following tests.
6. Add routing/elevation providers only after licence/cost/coverage validation.
7. Harden SOS and Rescue Link with expiry, device-state capture and end-to-end tests.

## Delivery rule
A track may use mock adapters or deterministic local fixtures while upstream credentials/data feeds are unavailable. Production integration must never be faked as live data.
