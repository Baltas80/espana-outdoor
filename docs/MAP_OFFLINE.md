# MapLibre + PMTiles + offline

## Alcance

España Outdoor concentra el producto actual en **Android y iOS/iPadOS**. Este documento describe exclusivamente el pipeline cartográfico móvil del MVP.

## Architecture

España Outdoor uses MapLibre Flutter as the primary renderer on Android and iOS/iPadOS, with PMTiles vector archives as the priority distribution format. The application does not embed a third-party demo tileset in production.

A production/staging build must provide `MAP_PMTILES_URL` or a configured `MAP_STYLE_JSON` whose PMTiles source points to an approved España Outdoor-controlled distribution endpoint. Production must not silently fall back to the public OSM tile service.

For mobile, a downloaded `.pmtiles` region in the application-support `offline_regions` directory takes precedence over the remote PMTiles endpoint. Downloads use `background_downloader`, which provides persistent/background transfers and pause/resume support on the supported native platforms.

## Configuration

Recommended build-time variables:

- `MAP_PMTILES_URL`: HTTPS URL of the approved vector PMTiles archive.
- `MAP_STYLE_URL`: optional HTTPS style JSON. The provider replaces `__PMTILES_URL__` in that JSON when present.
- `MAP_STYLE_JSON`: optional inline style JSON for controlled builds. Prefer a checked-in style or approved style endpoint rather than arbitrary runtime input.
- `OFFLINE_CATALOG_URL`: HTTPS catalog endpoint for published regional packages.

A missing production `MAP_PMTILES_URL` with no local offline archive is treated as a configuration error. This prevents the app from silently depending on a demonstration dataset.

## Offline lifecycle

1. The region catalog publishes an immutable region id, URL, byte size, update timestamp and SHA-256 digest.
2. `background_downloader` stores the completed archive under application support in `offline_regions/<region>.pmtiles`.
3. The package verifier validates metadata and SHA-256 before the archive becomes active.
4. Mobile MapLibre resolves the newest verified local PMTiles archive before using the configured remote archive.
5. If connectivity disappears, the verified local archive remains usable for map rendering.
6. Dynamic safety/weather information is never inferred from the age of the map archive; freshness must be represented separately.
7. A future update may publish a newer archive for the same region. The downloader can resume interrupted transfers where the origin supports HTTP range requests.

## Production distribution

The production pipeline is defined in `.github/workflows/pmtiles-production-release.yml` and uses an immutable versioned object path in Cloudflare R2. The pipeline verifies the generated PMTiles archive, records SHA-256 and size metadata, publishes a catalog entry and performs HTTPS byte-range verification before producing release evidence.

The real R2 account, bucket, public base URL, license URL and attribution are environment configuration. They must never be replaced with invented values in the application or release documentation.

## Licensing and attribution

The basemap distribution must retain OpenStreetMap attribution and comply with the license of every included source. The repository contains rendering style and integration code; production map archives are distributed separately so they can be updated without shipping a new application binary.

## Security requirements

- Only HTTPS map endpoints are accepted for remote distribution in production.
- No provider API keys are committed to the repository.
- Offline package metadata is untrusted input and is validated before use.
- Region archives are published with SHA-256 digests and verified before activation.
- Emergency and alert layers remain logically separate from the basemap and carry their own source, timestamp and validity metadata.

## Why PMTiles

PMTiles is an open, single-file tiled-data format designed for HTTP range access and direct cloud/object-storage distribution. This keeps the map stack portable and makes it possible to self-host the production archive instead of coupling the application to a proprietary map API.


## Evidencia de inventario del repositorio (2026-10-26)

La revisión remota de `main` encontró `assets/maps/offline_style.json`, pero no un archivo PMTiles regional de producción bajo `assets/maps/`. En `assets/testing/` existe `offline_smoke.pmtiles` de 508 bytes, que es un fixture de pruebas y no debe promocionarse a paquete productivo. La presencia del estilo y del fixture no acredita un mapa offline completo: faltan evidencias de un paquete regional real publicado, sus recursos de fuente/glifos, la integridad del conjunto, selección local y renderizado en Android sin red.

Esta comprobación es del inventario Git de la rama `main`; no describe el inventario local de `C:\\Users\\PAGREY\\Desktop\\Espana-outdoor-maps`.
