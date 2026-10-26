# España Outdoor — estado técnico

Última revisión documental remota: 2026-10-26 (sin ejecución local de Flutter/Android en esta sesión)

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

## Evidencias verificadas el 2026-10-26

- Rama consultada: `main`; HEAD auditado antes de cambios documentales: `ec0c1fdc2f19284a157273ed426f13b238df147b`. Los cambios de auditoría están en commits posteriores de `main`.
- Existe `pubspec.lock` y declara versiones resueltas para `maplibre_gl` y `flutter_appauth`. El registro de licencias se corrigió en un commit separado; el cambio documental no valida licencias transitivas ni produce un SBOM.
- `assets/maps/` contiene `offline_style.json` y `.gitkeep`; no contiene un PMTiles regional de producción.
- `assets/testing/` contiene `offline_smoke.pmtiles` (508 bytes, fixture de pruebas) y `.gitkeep`. No es cartografía de producción ni acredita cobertura de España.
- El manifiesto consultado en la rama `main` contiene permiso de Internet, pero no declara permisos de ubicación gruesa/fina ni de ubicación en segundo plano. El guard `tool/verify_mobile_native.py` exige esos permisos, además de `minSdk 24`; por tanto, los archivos nativos actuales y el guard deben reconciliarse en CI antes de dar por válida la configuración Android.
- `android/app/build.gradle.kts` conserva `com.example.espana_outdoors` como `applicationId` y firma `release` con la configuración `debug`. Esto no es una configuración apta para publicar; el identificador definitivo y la firma de release deben configurarse con los valores/secretos reales autorizados.
- Los workflows `.github/workflows/ci.yml` y `.github/workflows/staging-android.yml` tenían filtros de rama `master`; ambos se han corregido en commits separados para apuntar a `main`. Hay que comprobar que las siguientes ejecuciones completan correctamente.
- GitHub Actions consultado el 2026-10-26 mostró un fallo en la ejecución programada de Security baseline sobre el HEAD anterior. Los logs identifican fallos de análisis Dart por contenido de `espana_outdoor_backtrack_patch/` versionado fuera de `lib/` (importaciones inexistentes como `../domain/outdoor_models.dart`), fallo de política OG image en `site/index.html` y cinco hallazgos Gitleaks. El despliegue web anterior terminó correctamente; no equivale a prueba Android.

## Niveles de validación (no confundir)

| Nivel | Estado acreditado |
|---|---|
| Código presente | MapLibre, configuración PMTiles, GPS, registro/persistencia GPX y adaptadores de routing/rescue están presentes en el repositorio; se necesita revisión funcional de cada flujo. |
| Validación documental remota | Realizada parcialmente el 2026-10-26; se identificaron discrepancias Android/CI/registro de licencias. |
| Análisis estático ejecutado en esta sesión | No ejecutado: el entorno de esta sesión no dispone de una copia de trabajo Flutter/Android demostrada. |
| Pruebas automatizadas ejecutadas en esta sesión | No ejecutadas. Hay suites y workflows definidos en GitHub. |
| APK compilado en esta sesión | No. |
| APK instalado o probado en emulador/dispositivo físico | No acreditado en esta sesión. |
| Prueba online/offline de mapa | No acreditada. El fixture offline de CI no prueba cobertura productiva. |
| Petición real a Valhalla / Rescue Link | No acreditada. No se ha verificado endpoint operativo en esta sesión. |

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


### Seguimiento de auditoría — 26/10/2026

Actualización respecto a la revisión anterior:

- Se han corregido los filtros de rama de `.github/workflows/ci.yml` y `.github/workflows/staging-android.yml` para que apunten a `main`.
- Se han declarado permisos Android de ubicación y servicios de ubicación, y se ha fijado `minSdk = 24`, alineándolo con el guard nativo de CI.
- Sigue siendo provisional `applicationId = com.example.espana_outdoors`; no se ha inventado un identificador definitivo. La configuración `release` continúa usando firma `debug`, por lo que no es publicable.
- No se ha ejecutado Flutter/Gradle localmente desde esta sesión. Los cambios anteriores son commits remotos, pendientes de que CI los valide.
- La auditoría del directorio local de elevación `Espana-outdoor-maps` no se ha podido reconstruir con el historial accesible. No hay evidencia disponible de archivos concretos que falten en ese directorio.


## Hallazgos de código adicionales (no equivalen a pruebas de ejecución)

- `lib/features/map/maplibre_map_page.dart` usa la integración `maplibre_gl`; el estilo es producido por `lib/core/maps/maplibre_style_loader.dart`.
- El cargador da prioridad a un PMTiles local verificado. Si no lo hay, intenta un PMTiles remoto o el catálogo, y el estilo por defecto incluye `https://tiles.openfreemap.org/styles/liberty`. Por tanto, sin paquete local y sin endpoint/catálogo de producción, no hay garantía de mapa funcional sin conexión.
- El verificador `OfflinePackageVerifier` valida existencia, tamaño opcional y SHA-256; el downloader ofrece pausa/reanudación y verificación. No se ha ejecutado en este entorno contra un archivo productivo real ni contra almacenamiento Android.
- `LocationController` utiliza `geolocator` para revisar permisos/servicio y abrir el stream de posiciones. `RouteRecorder` y `RouteRecordingStore` implementan recuperación/persistencia con Hive CE; existen pruebas de recuperación de sesiones, pero no se han ejecutado aquí.
- `ValhallaRoutingService` realiza POST HTTP con timeout de 20 s, parsea shape polyline6 y maniobras. Las pruebas disponibles usan un cliente HTTP simulado; no demuestran conexión al Valhalla real.
- GPX: dependencia `gpx` presente en `pubspec.yaml`; el flujo de importación/exportación requiere una prueba integral en dispositivo.
- Rescue Link: gateway HTTP y pruebas de política están en el árbol; no se ha verificado un backend real ni el envío/recuperación extremo a extremo.
