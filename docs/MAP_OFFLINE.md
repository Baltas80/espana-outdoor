# Cartografía y modo offline

## Estado actual

El mapa principal Android se está migrando a Mapbox Maps SDK (`mapbox_maps_flutter`). Las pantallas de planificación y detalle que todavía usan `maplibre_gl` quedan pendientes de migración para unificar el motor.

El mapa principal usa el estilo Mapbox Outdoors y necesita `MAPBOX_ACCESS_TOKEN` inyectado en compilación. Las vistas MapLibre restantes siguen usando su configuración independiente.

## Modo offline

La integración inicial implementa la descarga de un style pack y una región de prueba de Córdoba mediante `OfflineManager` y `TileStore`, con zoom 8–15. Es una cobertura de prueba, no un mapa offline de España. La app principal todavía necesita compilación, instalación y validación en modo avión antes de declarar operativa esta integración.

Las funciones críticas independientes de la cartografía, como la geometría de una ruta activa y los datos de seguridad que estén guardados localmente, deben mantener su propio estado y fecha de actualización.

## Requisitos para una implementación futura

- Completar la migración del resto de vistas cartográficas a Mapbox después de validar la pantalla principal.
- Mantener `OfflineManager`/`TileStore` como mecanismo offline para Mapbox; verificar estilo, recursos y teselas con el dispositivo desconectado.
- No usar servidores públicos de teselas de OpenStreetMap para descargas masivas.
- Mostrar progreso, errores, espacio necesario, reintentos y estado de integridad.
- Verificar que estilo, fuentes, sprites y teselas funcionan sin red.
- Probar apertura, navegación por el mapa y recuperación tras perder conexión en un dispositivo Android real.
- No marcar la funcionalidad como terminada solo porque el APK compile.

## Evidencia

La POC aislada de Mapbox ya se probó en el OPPO, pero la integración en la app principal todavía no está validada. Estado actual: **código de integración en rama; build/instalación/prueba offline de la app principal pendientes**.
