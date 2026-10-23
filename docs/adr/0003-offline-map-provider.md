# ADR 0003 - MapLibre and PMTiles for offline maps

## Decision

España Outdoor uses MapLibre Flutter as its map renderer and PMTiles as the controlled distribution format for vector map data. The offline-map lifecycle and product state remain behind `MapService` and `OfflineRegionManager`; route, safety and UI logic must not depend directly on renderer implementation details.

## Rationale

Offline maps are a core product capability and a potential source of unexpected infrastructure cost. PMTiles supports single-file distribution and HTTP range access, while MapLibre provides the rendering integration already used by the application. Keeping lifecycle and region state behind application interfaces limits coupling.

## Requirements

- Legal right to distribute and cache the selected map data.
- Explicit vector-data usage and attribution terms.
- Resumable downloads where supported.
- Deterministic style/version metadata.
- Storage-size estimation before download where technically possible.
- Safe cancellation, pause, resume and deletion.
- No credentials embedded in the client when protected access is required; use a secure backend/token strategy.
- Verified local packages must remain usable without connectivity.
- Production must not silently fall back to public demonstration tile services.

## Current status

The application integrates MapLibre Flutter and PMTiles-related loading code. Production availability depends on valid environment configuration or a verified local offline archive. A successful compile alone does not prove regional coverage or physical-device reliability.

## Non-goals

This layer does not invent or silently scrape proprietary map data, and it does not claim that an offline region is ready until package verification and renderer preparation succeed.
