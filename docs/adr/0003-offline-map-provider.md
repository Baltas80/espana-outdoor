# ADR 0003 — Mapbox como motor cartográfico y offline

## Estado

Aceptado para la integración Android en curso. La aplicación usa Mapbox Maps SDK y `OfflineManager`/`TileStore` para la descarga offline. El usuario ha confirmado que la región de prueba de Córdoba funciona sin conexión en su OPPO; no equivale a cobertura offline de España.

## Decisión

- Usar exclusivamente Mapbox Maps SDK (`mapbox_maps_flutter`) para representar cartografía en la aplicación.
- Usar `OfflineManager` y `TileStore` para estilos y regiones offline.
- Inyectar `MAPBOX_ACCESS_TOKEN` desde el entorno de compilación; no almacenar tokens en Git.
- Mantener GPS, grabación, GPX, Valhalla, seguridad y datos críticos offline como módulos independientes del motor cartográfico.
- Retirar la infraestructura anterior de PMTiles, catálogo PMTiles y publicación R2; no crear un segundo mecanismo de descarga cartográfica.
- No descargar en masa desde servidores públicos de teselas OSM.

## Alcance y límites

La región de Córdoba (zoom 8–15) es una cobertura de prueba, no un mapa offline nacional. Deben documentarse los límites descargados y comprobar la reapertura en frío y el modo avión en dispositivo Android. Una compilación correcta no prueba por sí sola el funcionamiento offline.

## Migración pendiente

Las vistas secundarias que todavía importen MapLibre deben migrarse a Mapbox sin perder selección de destino, geometría de rutas ni visualización GPX. Hasta completar y probar esa migración, no se debe retirar su dependencia de forma que rompa la compilación.
