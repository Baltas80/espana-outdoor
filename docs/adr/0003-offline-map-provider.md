# ADR 0003 — Mapbox como motor cartográfico y offline

## Estado

Aceptado para la integración Android en curso. La aplicación usa Mapbox Maps SDK y `OfflineManager`/`TileStore` para la descarga offline. El usuario ha confirmado que la región de prueba de Córdoba funciona sin conexión en su OPPO; no equivale a cobertura offline de España.

## Decisión

- Usar exclusivamente Mapbox Maps SDK (`mapbox_maps_flutter`) para representar cartografía en la aplicación.
- Usar `OfflineManager` y `TileStore` para estilos y regiones offline.
- Inyectar `MAPBOX_ACCESS_TOKEN` desde el entorno de compilación; no almacenar tokens en Git.
- Mantener GPS, grabación, GPX, Valhalla, seguridad y datos críticos offline como módulos independientes del motor cartográfico.
- Mantener un único mecanismo de descarga cartográfica: el sistema offline nativo de Mapbox.
- No descargar en masa desde servidores públicos de teselas OSM.

## Alcance y límites

La región de Córdoba (zoom 8–15) es una cobertura de prueba, no un mapa offline nacional. Deben documentarse los límites descargados y comprobar la reapertura en frío y el modo avión en dispositivo Android. Una compilación correcta no prueba por sí sola el funcionamiento offline.

## Migración pendiente

Las vistas de planificación y detalle se han migrado a un viewport Mapbox compartido que admite selección de destino y anotaciones de ruta/GPX. Esta modificación requiere análisis estático, pruebas y validación en dispositivo antes de considerarse cerrada.
