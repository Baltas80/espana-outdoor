# Seguimiento de recuperación cartográfica — 26/10/2026

## Objetivo

Recuperar el arranque normal de España Outdoor sin perder la prueba específica de PMTiles de Córdoba y documentar la evidencia real de mapa online/offline.

## Estado de la prueba de dispositivo comunicado durante la intervención

- Dispositivo objetivo: OPPO CPH2009.
- La aplicación abrió el mapa online y renderizó cartografía vectorial real.
- Se verificó un archivo PMTiles local en el almacenamiento privado de la aplicación:
  - Ruta: `offline_regions/spain-f410f9961397.pmtiles` (ruta absoluta Android observada: `/data/user/0/com.example.espana_outdoors/files/offline_regions/spain-f410f9961397.pmtiles`).
  - Tamaño: 1,269,114,296 bytes.
  - SHA-256: `f410f9961397ed502876a1843844a00b4fcf77f7d037c4ed12d716190ad73d4d`.
- En la prueba sin conexión, MapLibre seleccionó el PMTiles local verificado y dibujó geometrías vectoriales. No se observaron errores de PMTiles, glifos, sprites ni HTTP en esa prueba.
- La prueba offline no mostró etiquetas: el estilo probado tenía 83 capas y ninguna capa `symbol`. La compatibilidad completa de etiquetas/glifos/sprites queda pendiente.
- La prueba de Córdoba está diseñada para activarse únicamente si se define `CORDOBA_PMTILES_TEST_PATH`; sin esa variable, el arranque normal conserva `/splash`.

Estas observaciones son evidencia de la prueba de dispositivo comunicada en la sesión, no una nueva ejecución realizada por este commit.

## Cambios locales identificados, aún no incorporados en este commit

El estado local comunicado incluye modificaciones en:

- `assets/maps/offline_style.json`
- `lib/app/app.dart`
- `lib/core/maps/maplibre_style_loader.dart`
- `lib/features/map/maplibre_map_viewport.dart`

Y nuevos archivos de la prueba Córdoba y tests focalizados:

- `assets/testing/cordoba_senderos_style.json`
- `docs/CORDOBA_PMTILES_TEST.md`
- `lib/core/maps/cordoba_pmtiles_test_style.dart`
- `lib/features/map/cordoba_pmtiles_test_page.dart`
- `test/core/cordoba_pmtiles_test_style_test.dart`
- `test/core/map_configuration_error_test.dart`
- `test/core/offline_map_style_test.dart`

Este commit registra el progreso y no sustituye esos archivos locales: el contenido íntegro de todos ellos no estaba disponible para transferirlo con seguridad mediante la integración de GitHub en esta operación.

## Hallazgos de código revisados

- El cargador prioriza un PMTiles local verificado.
- La falta de configuración de catálogo/archivo local se expresa mediante `MissingMapConfigurationException` y un título de error específico.
- La selección del arranque de Córdoba está condicionada por `CORDOBA_PMTILES_TEST_PATH`; el arranque predeterminado permanece en `/splash`.
- El estilo offline revisado elimina la URL remota del origen vectorial. Es necesario validar que todas las capas y los recursos de estilo sean compatibles con el archivo PMTiles y que las etiquetas se resuelvan sin red.
- Los avisos LF/CRLF observados por Git son avisos de finales de línea, no errores funcionales por sí mismos.

## Pendiente prioritario

1. Incorporar los cambios locales íntegros a GitHub, preservando los archivos de prueba Córdoba.
2. Confirmar que el estilo offline puede representar etiquetas con recursos locales o una estrategia compatible con offline.
3. Mantener una sola validación focalizada por cambio; no repetir baterías generales ni reconstruir APK sin un cambio que lo justifique.
4. No considerar producción el catálogo o la distribución PMTiles hasta disponer de endpoint y recursos aprobados.
5. No declarar cerrada la funcionalidad offline completa solo porque las geometrías renderizan: etiquetas, cobertura y recursos auxiliares siguen pendientes.

## Alcance de validación

Este documento no afirma que este commit haya ejecutado Flutter, tests, Gradle, compilación APK o una prueba nueva en dispositivo. Recoge el estado y las evidencias comunicadas en la intervención.
