# España Outdoor — Offline Strategy v0.1

## Principle
Outdoor operation must remain useful when connectivity disappears.

## Download package tiers

### Critical
- Map data for the selected area
- Active route geometry
- Basic route metadata
- Emergency contacts/instructions
- Downloaded safety notices
- Trusted-contact configuration needed for emergency workflows

### Recommended
- Nearby points of interest
- Weather snapshot
- Wildlife guidance
- Pet suitability data
- Conservation restrictions

### Optional
- Extended discovery content
- Large photo/media assets
- Historical/community content

## Package lifecycle

Each package records:
- area identifier
- provider/version
- creation time
- last validation time
- expiry/freshness state
- approximate storage size
- license/attribution requirements

Downloads must support pause, resume, retry and integrity validation.

## Storage management

The application should show package size before download, allow deletion, and protect critical active-route data from accidental eviction where practical.

## Map provider abstraction

Tile and vector providers must sit behind an application interface so providers can be changed without changing route or safety features.

## Degraded mode

When online data cannot be refreshed, show the last known state with its timestamp rather than pretending it is current.


## Estado comprobado el 2026-10-26

Los puntos de este documento describen criterios de producto, no verificaciones ya superadas. En la revisión remota de `main` no se ha acreditado una ejecución de dispositivo que cubra pérdida de conexión, reapertura desde paquete local, frescura de avisos de seguridad o recuperación de descargas. El flujo de cartografía offline no se considera implementado ni validado. La próxima implementación debe probarse en un dispositivo Android real con todas las redes desactivadas.
