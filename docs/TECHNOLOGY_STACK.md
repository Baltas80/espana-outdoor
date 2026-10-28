# España Outdoor — Technology Stack & Anti-Reinvention Policy

## Purpose

Before writing custom infrastructure, the project must first check whether Flutter, a maintained package, or an external provider already solves the problem. Custom code should stay concentrated in the domain and safety policy layers.

## Current foundation

- Flutter/Dart for the application.
- Riverpod for feature state.
- go_router for navigation.
- MapLibre Flutter (`maplibre_gl`) for map rendering.
- geolocator for location and distance calculations.
- file_picker for file import/export.
- path_provider for platform paths.
- Hive CE for current lightweight local persistence.
- flutter_secure_storage for sensitive local values.
- connectivity_plus for connectivity state.
- url_launcher for call/SMS hand-off.
- gpx for GPX parsing and generation.

## Preferred existing software by problem

### Offline maps

Current architecture:

1. MapLibre Flutter renders the map.
2. MapLibre loads the configured online style; offline map storage requires a separate implementation.
3. `MapService` and the offline-region services keep map lifecycle and application state separate from rendering details.

Do not build a custom tile renderer or custom SQLite tile reader.
Do not use `tile.openstreetmap.org` for bulk offline downloading. Production offline packages must use a provider or infrastructure whose terms explicitly permit prefetch/offline use.

### Routing

Keep a RoutingEngine application port.
Use the configured Valhalla adapter for routing; keep endpoint configuration outside source code.
Never bind domain logic directly to one routing vendor.

### Marker and POI clustering

When POI or community markers become numerous, prefer an existing maintained clustering implementation compatible with the active renderer instead of writing a custom spatial clustering system.

### Structured persistence

Hive CE remains suitable for the prototype and simple key/value data.
Before the model expands into routes, waypoints, hazards, sources, reports, pets, downloads and sync metadata, evaluate Drift/SQLite. Do not build a large relational model as nested Hive maps.

### Background work

Use platform background-task infrastructure for periodic maintenance and synchronization.
workmanager can be evaluated for periodic jobs, but it is not a replacement for continuous GPS tracking.
Continuous route/location recording needs an explicit location capability, platform permissions and a battery policy.

### Notifications

Use a maintained notification library for local reminders and operational events.
Add push notification infrastructure only after the backend, authentication and device-token lifecycle are defined.

### Permissions

Do not add another generic permission plugin merely to duplicate geolocation permissions already handled by the selected location stack. Introduce a unified permission layer only when multiple permission domains justify it.

## Official data

AEMET OpenData is the preferred first-party weather source.
AEMET uses authenticated API access. API keys are credentials and must never be embedded as privileged secrets in public client code.
Production access should sit behind controlled infrastructure where key rotation, rate limiting, caching and provenance can be managed.

## Dependency admission rule

Before adding a package, verify:

1. It replaces substantial custom code or difficult native integration.
2. It is compatible with the supported Dart/Flutter floor.
3. It is actively maintained.
4. Its license is acceptable for the product.
5. It supports the platforms required by the feature.
6. It can be hidden behind an application port where vendor lock-in would matter.
7. It can be tested deterministically.

## Current decision

Use existing libraries aggressively where they remove infrastructure work, but do not add packages simply because they exist.

Priority evaluations:

- Drift for structured local data as the domain expands.
- Marker clustering when POI density requires it.
- Local notifications for operational and safety state.
- Background task scheduling once backend synchronization exists.

## Definition of not coding blindly

For each capability, follow this order:

Existing Flutter capability -> maintained package -> provider/service -> custom domain logic.

Custom implementation is the last layer, not the first choice.
