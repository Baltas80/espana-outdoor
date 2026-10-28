# España Outdoor — Architecture

## Layers

```text
Presentation / Design System
        |
Feature controllers (Riverpod)
        |
Domain models / use cases
        |
Repositories / ports
        |
Adapters: GIS, GPS, weather, alerts, storage, notifications
        |
External providers
```

## Boundaries

External providers must sit behind interfaces. Domain and UI code must not depend directly on a map, weather, routing or alert vendor. This permits replacement, fallback, licensing review and deterministic tests.

## Offline-first

Critical capabilities must remain useful without network access:

- previously downloaded maps;
- GPS and position;
- saved routes;
- safety data;
- trusted contacts;
- local activity recording.

Synchronization is eventual and conflicts must be resolved explicitly.

## Data provenance

Dynamic records should carry, when applicable:

- `source`;
- `sourceUrl`;
- `retrievedAt`;
- `validUntil`;
- `confidence`;
- `license`.

Stale data must be distinguishable from current data.

## Security

Secrets and credentials belong in secure platform storage or trusted backend infrastructure. Never commit secrets or embed privileged credentials in public builds. Emergency location must remain outside ordinary analytics unless explicitly required and legally justified.

## GIS

MapLibre Flutter is the active map renderer. The online style is configured by `MAP_STYLE_URL` or a controlled `MAP_STYLE_JSON`. Attribution, license and provider usage policies are mandatory release criteria. Offline cartography remains pending a separately validated implementation.

## Emergencies

SOS, 112, trusted contacts and Rescue Link are isolated modules. Community assistance is supplementary and must never block or delay official emergency services. Rescue Link access must be temporary, revocable and abuse-resistant.

## Wildlife and conservation

Sensitive wildlife locations must be protected. Public map layers should use generalized locations where exact coordinates could cause disturbance or exploitation.

## Scalability

Backend and synchronization services are introduced behind stable ports. The client must not assume a particular cloud vendor.

## Evolution

1. Robust local persistence and offline packages.
2. GPX and route recording/statistics.
3. AEMET and official alert adapters.
4. Wildfire/disaster data.
5. Pets, wildlife and conservation.
6. Backend and synchronization.
7. Secure Rescue Link.
8. Assistive AI with source traceability.
