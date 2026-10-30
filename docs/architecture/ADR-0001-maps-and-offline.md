# ADR-0001 — Motor cartográfico y estrategia offline

**Estado: sustituido por ADR 0003.** Este documento histórico queda supersedido; la arquitectura vigente está descrita en ADR 0003.

## Decisión vigente

- Mapbox Maps SDK (mapbox_maps_flutter) es el único motor cartográfico de la aplicación.
- Mapbox OfflineManager y TileStore gestionan los estilos y regiones descargadas.
- Mantener Mapbox como único motor y su sistema offline nativo como única solución cartográfica descargable.
- GPS, grabación y persistencia de rutas, GPX, Valhalla, seguridad y sincronización offline genérica permanecen independientes del motor.
- No utilizar los servidores públicos de teselas OSM para descargas masivas.

Consultar ADR 0003 — Mapbox como motor cartográfico y offline y docs/MAP_OFFLINE.md para el estado de validación y las limitaciones actuales.

## Condiciones de validación

Una descarga de región no implica cobertura nacional. Antes de declarar el modo offline listo para producción se deben verificar descarga completa, recursos de estilo, progreso/errores, integridad según las capacidades del SDK, apertura en frío y funcionamiento en Android con todas las redes desactivadas. Debe mantenerse la atribución y cumplirse la licencia y las condiciones de uso de Mapbox.
