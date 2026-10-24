# España Outdoor — estado técnico

Última auditoría documental: 2026-10-23

## Objetivo MVP

Android primero. El criterio de aceptación principal es un APK instalable que abra el mapa sin cerrar la aplicación, renderice cartografía vectorial real y permita usar GPS, rutas y mapas offline.

## Arquitectura cartográfica actual

- Renderer móvil: MapLibre Flutter mediante `maplibre_gl`.
- Distribución cartográfica: PMTiles, con catálogo y endpoint controlados por entorno.
- Offline: los archivos regionales verificados en `offline_regions` tienen prioridad cuando están disponibles.
- Flutter/Riverpod/go_router.
- Routing mediante Valhalla, configurado externamente con `VALHALLA_BASE_URL`.
- Android es la plataforma prioritaria del MVP; el soporte de otras plataformas no debe darse por validado por inferencia.

## Estado conocido del repositorio

- `pubspec.yaml` declara `maplibre_gl: 0.27.1`.
- La pantalla cartográfica activa está en `lib/features/map/maplibre_map_page.dart`.
- La carga de estilos y fuentes locales se encuentra en `lib/core/maps/`.
- El flujo de descargas offline utiliza `background_downloader` y los servicios de catálogo/verificación en `lib/core/offline/`.
- La configuración de producción debe suministrar `MAP_PMTILES_URL` o una configuración de estilo aprobada que apunte a una fuente PMTiles válida.
- Un APK que compile no demuestra por sí solo cobertura regional detallada ni funcionamiento físico en todos los dispositivos.

## Riesgos y comprobaciones pendientes

### P0 — Validación física del mapa

Confirmar en el dispositivo objetivo que la pantalla del mapa se abre, el proceso permanece vivo, el estilo y la fuente cartográfica cargan correctamente y el GPS no interrumpe la experiencia.

### P0 — Cobertura cartográfica

Verificar que los paquetes publicados contienen el nivel de detalle esperado para España: carreteras, caminos, poblaciones, hidrografía y etiquetas. No confundir que el renderer funcione con que exista cobertura regional completa.

### P1 — Integridad de paquetes offline

Mantener verificación de tamaño, metadatos y SHA-256 antes de activar paquetes descargados. La procedencia y las condiciones de licencia deben acompañar a los datos publicados.

### P1 — Resiliencia de descargas y GPS

Probar reanudación de descargas, recuperación tras interrupciones, permisos de ubicación y notificación persistente en los dispositivos objetivo.

### P1 — Routing

Validar la configuración externa de Valhalla, la calidad de las rutas y el comportamiento sin conectividad o sin endpoint disponible.

### P2 — Elevación y sombreado

La integración de DEM/hillshading requiere una fuente de elevación y un pipeline verificados; no se debe simular un sombreado que no proceda de datos reales.

## Conservación

- Conservar los recursos visuales compartidos mientras existan referencias desde la app o la web.
- No borrar licencias, activos, datos ni artefactos ajenos a la integración cartográfica sin una auditoría específica.
- Mantener los servicios de backend de seguridad y datos, que son independientes del renderer.
- No realizar cambios sobre la pantalla cartográfica activa ni su configuración nativa como parte de una limpieza documental.

## Siguiente orden de QA

1. Ejecutar el guard de proveedor cartográfico y el análisis estático.
2. Ejecutar pruebas de routing, offline y seguridad.
3. Compilar el APK de staging con la configuración real aprobada.
4. Ejecutar el smoke test de mapa Android y revisar los logs nativos.
5. Comprobar físicamente el APK en el dispositivo objetivo.
6. Verificar cobertura y atribución de los paquetes PMTiles publicados.
7. Preparar el release candidate solo después de superar los criterios anteriores.

## Criterio de cierre del incidente del mapa

El incidente queda cerrado cuando el smoke test abre la pantalla del mapa, el proceso Android permanece vivo, la fuente cartográfica se carga sin error nativo y el APK resultante se instala y comprueba físicamente sin cierre de la aplicación.
