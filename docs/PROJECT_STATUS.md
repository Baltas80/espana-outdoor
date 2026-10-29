# España Outdoor — estado técnico

Última revisión remota: 29/10/2026. Durante esta intervención se modificó la rama de limpieza en GitHub; no se ha ejecutado Flutter/Android localmente.

## Objetivo MVP

Android primero. El criterio de aceptación es un APK instalable que abra el mapa, renderice cartografía real, permita usar GPS y rutas, y gestione errores y pérdida de conectividad.

## Arquitectura cartográfica actual

- Motor cartográfico único: Mapbox Maps SDK mediante mapbox_maps_flutter.
- Estilo Mapbox Outdoors; el token MAPBOX_ACCESS_TOKEN se inyecta durante la compilación y no se almacena en Git.
- Cartografía offline mediante Mapbox OfflineManager y TileStore. La región de Córdoba, zoom 8–15, es una prueba limitada, no cobertura de España.
- El usuario informa que el mapa de la región de prueba funciona sin conexión en el OPPO y que lo comprobó dos veces. Es evidencia manual comunicada por el usuario, no una prueba reproducida durante esta intervención.
- GPS, grabación y persistencia de recorridos, GPX, Valhalla, seguridad y sincronización offline genérica se conservan como módulos independientes.
- La configuración de routing sigue usando VALHALLA_BASE_URL.

## Limpieza remota aplicada en esta rama

- Eliminada la infraestructura de publicación y catálogo PMTiles/R2, sus scripts de comprobación y la documentación de MBTiles/PMTiles que ya no corresponde a la solución elegida.
- Eliminada la dependencia directa maplibre_gl y los archivos de viewport/carga de estilo MapLibre.
- Migradas las vistas de planificación y detalle de rutas a un viewport Mapbox compartido; se conservan selección de destino, geometría de ruta y visualización de trazas GPX mediante anotaciones Mapbox.
- Actualizados README, estrategia offline y ADR para reflejar la decisión vigente.

## Validación disponible

| Comprobación | Estado |
|---|---|
| Inspección remota de árbol y configuración | Realizada |
| Eliminación de archivos PMTiles/R2 antiguos | Aplicada en rama de limpieza |
| Referencias por nombre a archivos MapLibre/PMTiles en el árbol | Ninguna en el último inventario de rutas |
| Análisis estático Dart | Pendiente de CI |
| Pruebas automatizadas | Pendientes de CI |
| Compilación APK | Pendiente de CI |
| Instalación y prueba en OPPO | No ejecutada durante esta intervención |
| Modo avión / reapertura en frío | Evidencia manual del usuario para la región de prueba; repetición independiente pendiente |
| Routing real con Valhalla | No verificado durante esta intervención |

## Pendientes prioritarios

1. Ejecutar CI sobre esta rama y resolver cualquier error de análisis, tests o compilación.
2. Regenerar/verificar pubspec.lock con Flutter Pub tras retirar maplibre_gl.
3. Compilar e instalar un APK de staging y probar el mapa Mapbox principal, planificación, detalle GPX, GPS y modo avión en el OPPO.
4. Documentar los límites exactos de la región offline y comprobar la reapertura en frío.
5. Mantener la cobertura nacional como pendiente: no está implementada por la región de prueba de Córdoba.

## Criterio de seguridad

No usar servidores públicos de teselas de OpenStreetMap para descargas masivas. No inventar endpoints ni datos de cobertura. No marcar funciones como completadas sin evidencia reproducible.
