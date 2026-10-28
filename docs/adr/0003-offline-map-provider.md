# ADR 0003 — Migración del mapa Android a Mapbox Offline

## Estado

En revisión. La POC de Mapbox demostró descarga offline en una región acotada de Córdoba en un OPPO. La integración en la app principal debe pasar build y QA offline antes de aceptarse como solución de producción.

## Contexto

La implementación previa con MapLibre no logró una experiencia offline validada. La POC con Mapbox Maps SDK usa `OfflineManager` y `TileStore`; la adopción requiere token válido, atribución visible, cumplimiento de condiciones de uso y evaluación de costes.

## Decisión actual

- Usar Mapbox Maps SDK (`mapbox_maps_flutter`) para el mapa principal Android y el almacenamiento offline.
- Inyectar `MAPBOX_ACCESS_TOKEN` desde la configuración de compilación; no almacenar tokens en el repositorio.
- No tratar el modo offline cartográfico como una función operativa.
- Descargar style pack y región mediante `OfflineManager` y `TileStore`; la primera región de Córdoba (zoom 8–15) es solo una prueba controlada.
- No utilizar los servidores públicos de teselas de OpenStreetMap para descargas masivas.

## Consecuencias

La pantalla principal se migra a Mapbox en esta rama. Las vistas secundarias que aún usan MapLibre deben migrarse tras validar el mapa principal. La prueba offline de la aplicación integrada en modo avión es obligatoria; la compilación o la existencia de recursos guardados no bastan.

Compilar el APK no constituye evidencia suficiente de que el mapa offline funcione.
