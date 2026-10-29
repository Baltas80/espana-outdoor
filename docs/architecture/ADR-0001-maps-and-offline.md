# ADR-0001 — Motor cartográfico y estrategia offline

**Estado: sustituido por ADR 0003.** La decisión inicial de MapLibre/PMTiles ya no representa la implementación actual y no debe usarse como guía de desarrollo.

## Decisión vigente

- Mapbox Maps SDK (mapbox_maps_flutter) es el único motor cartográfico de la aplicación.
- Mapbox OfflineManager y TileStore gestionan los estilos y regiones descargadas.
- No mantener PMTiles, catálogo PMTiles, publicación R2 ni otro sistema de paquetes cartográficos paralelo.
- GPS, grabación y persistencia de rutas, GPX, Valhalla, seguridad y sincronización offline genérica permanecen independientes del motor.
- No utilizar los servidores públicos de teselas OSM para descargas masivas.

Consultar ADR 0003 — Mapbox como motor cartográfico y offline y docs/MAP_OFFLINE.md para el estado de validación y las limitaciones actuales.

## Condiciones de validación

Una descarga de región no implica cobertura nacional. Antes de declarar el modo offline listo para producción se deben verificar descarga completa, recursos de estilo, progreso/errores, integridad según las capacidades del SDK, apertura en frío y funcionamiento en Android con todas las redes desactivadas. Debe mantenerse la atribución y cumplirse la licencia y las condiciones de uso de Mapbox.
