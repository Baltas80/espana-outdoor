# España Outdoor — estado técnico

Última revisión del repositorio remoto: **14/11/2026**. Rama de referencia: `main`, HEAD `e81a348a907c6c6f6f717828c257056f21f4d2f2`. Este documento separa cambios integrados, checks automatizados y validaciones que requieren un dispositivo o servicios reales.

## Objetivo MVP

Android primero. El criterio de aceptación es un APK instalable que abra el mapa, renderice cartografía real, permita usar GPS y rutas, y gestione correctamente errores y pérdida de conectividad. La web pública debe seguir funcionando, pero no sustituye la validación de Android.

## Cambios integrados recientemente

- PR #43, iconos premium: integrada en `935d1e85a203c2f79ce169834a2ff0e4b5d6aaa3`.
- PR #44, firma de producción Android: integrada en `b3a2756d9dcad64389cd0d225d87849a233c0393`. Los builds con `APP_ENV=production` exigen una clave de release dedicada; el workflow comprueba la huella SHA-256 del APK y del AAB.
- PR #45, búsqueda y filtros del catálogo de rutas: integrada en `bbcb3daa706e86f4e3d7e581d58cea7119a4a52d`.
- PR #47, perfiles de Senderismo, BTT y Cicloturismo: integrada en `c7b73ba60a1a0dd312e1752598cd2bd8c2598203`; CI, Android staging y Security baseline pasaron en el HEAD de la PR antes de la fusión. La validación funcional contra un endpoint Valhalla real sigue pendiente.
- PR #50, staging de Dependabot: integrada en `c878af97e12faf19e45cfa80335310a60ab70783`. Los builds sin credenciales Maven de Mapbox quedan identificados como análisis/tests sin validación Android, sin crear artefactos que aparenten ser builds nativos comprobados.
- PR #54, actualización del estado técnico y del protocolo offline: integrada en `65609d766dec50548d48f4040634eb3bb864f631`.
- PR #56, eliminación de estadísticas ficticias del perfil: integrada en `e81a348a907c6f6f6f717828c257056f21f4d2f2`.
- PR #28, actualización de pgx a 5.12.0: integrada en `f91e69cc5c14be824a104dd60b0bda4115a307a3` para incorporar correcciones de seguridad del protocolo simple y de autenticación/channel binding.
- PR #38, CodeQL Action 4.39.3: integrada en `2202afc064c69da088643ff883298df98e420bca`.
- PR #26 y #27, imágenes builder Go 1.27.3-alpine para Rescue Link y Source Gateway: integradas en `4a25fb5ceae310a078f908c39ef405251e9a5ef8` y `7d5c95cd9339329ada7f133892e4fc3cd00087c0`.

Los checks de las ramas de PR #44 y #45 terminaron correctamente: CI, Android staging y Security baseline. CI incluyó además Flutter, Source Gateway e iOS. Las PR #28, #26, #27 y #38 también tenían CI y Security baseline correctos antes de fusionarse. Estos resultados no prueban instalación física, funcionamiento offline ni un release candidate.

Las PR #4, #7, #13 y #16 se cerraron como supersedidas porque sus cambios ya estaban incorporados en `main` o reemplazados por implementaciones posteriores.

## Arquitectura cartográfica y routing en main

- Motor cartográfico: **Mapbox**, mediante `mapbox_maps_flutter 3.33.0`.
- La pantalla de mapas offline usa `OfflineManager` y `TileStore.createDefault()` para descargar el estilo y una región de prueba de Córdoba.
- El proveedor de rutas de `main` utiliza `ValhallaRoutingService` con `VALHALLA_BASE_URL`. Ese servicio requiere conectividad; no debe presentarse como cálculo de rutas offline.
- La persistencia de teselas, la reapertura en frío, el renderizado en modo avión y el alcance de las regiones deben validarse en el APK exacto que se pretenda distribuir.
- Una región de Córdoba no demuestra cobertura cartográfica nacional.

## Estado de navegación offline

La implementación nueva está en la [PR #57 — Mapbox Navigation offline para senderismo](https://github.com/Baltas80/espana-outdoor/pull/53), rama `feat/mapbox-offline-routing-mainline-20261114`, basada en el `main` vigente a 14/11/2026. Las PR históricas #25, #52 y #53 se cerraron como supersedidas; sus ramas se conservan, pero no se deben fusionar.

La PR #57 propone:
- Mapbox Navigation 3.34.1 con Maps SDK 11.34.1 y Flutter plugin 3.34.1.
- Un `TileStore` persistente compartido por Maps y Navigation, configurado antes del primer `MapWidget`.
- Descarga de prueba de Córdoba con style pack, teselas y descriptor de routing peatonal.
- Routing compuesto: Android senderismo/peatonal con Mapbox; BTT, cicloturismo y map matching GPX con Valhalla. No se afirma routing offline de bicicleta.
- Pruebas unitarias e integración Android para ruta online, descarga, cierre del proceso, modo avión, nueva ruta con origen explícito `OFFLINE` y evidencia de carga del mapa.
- Staging con permisos de solo lectura, lockfile obligatorio y sin commits automáticos desde CI.

La nueva PR #57 se creó desde el HEAD actual de `main` en un único commit (`6e741b7c544d3ade4899d758c3b8b8db924e5f08` antes de esta actualización documental), sin divergencia de base. La ejecución anterior de Android staging instaló el APK, pero falló el smoke de UI al no encontrar el destino `Mapa`; la jerarquía estaba vacía y el artefacto no incluía logcat. La PR #57 añade diagnóstico de arranque y captura de evidencias; la causa raíz sigue pendiente de la siguiente ejecución.

La PR #57 debe superar todos los checks y demostrar en emulador una ruta nueva con origen `OFFLINE`. Después debe instalarse el APK exacto en el OPPO y repetirse la prueba tras cierre forzado y reinicio. La región de Córdoba es una prueba de concepto, no cobertura nacional.

Los perfiles de Senderismo, BTT y Cicloturismo ya están integrados mediante la PR #47. Falta validar sus respuestas contra el endpoint Valhalla real.

## Validación disponible y límites

| Comprobación | Estado |
|---|---|
| Checks CI de PR #44 y #45 | Correctos en sus HEAD previos a la fusión |
| CI/Security de PR #28, #26, #27 y #38 | Correctos antes de fusionar |
| Guard de firma de producción | Integrado; falta ejecutar Release candidate con secretos reales |
| APK/AAB staging | Android staging correcto en PR #44 y #45; firma debug, no distribuible |
| Mapa online en dispositivo físico con el HEAD actual | Pendiente de nueva evidencia |
| Descarga y persistencia de región offline en el HEAD actual | Pendiente de validación reproducible |
| Reapertura en frío y mapa renderizado en modo avión | Pendiente en dispositivo físico |
| Cálculo de una ruta nueva con origen nativo `OFFLINE` | No integrado en `main`; PR #57 pendiente de CI y validación |
| Routing real con Valhalla en producción | Pendiente de comprobar endpoint y respuesta para senderismo, BTT y cicloturismo |
| Firma release y candidato de producción | Pendiente de secretos y ejecución manual del workflow |

La PR #39 (setup-java 6.2.0) conserva una ejecución antigua de Android staging fallida y su rama está 7 commits por detrás de `main`; se solicitó a Dependabot que la rebase para repetir CI sobre el estado actual. La PR #41 (background_downloader 9.6.6) pasó CI, Security baseline, CodeQL y Android staging; sus pasos incluyen compilación y verificación del APK. Su lockfile deberá reconciliarse con Mapbox 3.34.1 si se integra después de la PR #57.

Una prueba anterior de la región de Córdoba fue reportada como funcional sin conexión en un OPPO. Es evidencia histórica de una prueba de concepto; no acredita el APK actual, reapertura tras reinicio, cálculo offline de rutas ni cobertura nacional.

## Pendientes prioritarios

1. Completar CI de la PR #57 y corregir cualquier fallo de compilación, análisis o integración.
2. Inspeccionar los artefactos de emulador: ruta nueva con origen `OFFLINE`, mapa cargado y evidencia visual; no aceptar solo el código de salida.
3. Instalar el APK exacto en el OPPO y registrar mapa online, permisos, GPS y descarga de Córdoba.
4. Con la región descargada, forzar cierre, activar modo avión y comprobar renderizado, persistencia y cálculo de una ruta nueva con origen explícito `OFFLINE`; repetir tras reiniciar el dispositivo.
5. Integrar la PR #41 y actualizar su lockfile después de resolver la versión Mapbox definitiva; revalidar la PR #39 tras el rebase de Dependabot.
6. Comprobar los perfiles Senderismo, BTT y Cicloturismo contra un endpoint Valhalla real y verificar sus respuestas.
7. Verificar Valhalla y los servicios backend con endpoints HTTPS reales.
8. Configurar de forma segura los cinco secretos de firma Android y ejecutar manualmente el workflow Release candidate. No crear una clave nueva si ya existe una clave de subida registrada en Google Play.
9. Auditar autenticación móvil/web, perfil, backend Go, PostgreSQL y permisos antes de ampliar funcionalidades de comunidad.

## Criterio de seguridad

No incluir secretos en código, Git, artefactos públicos ni logs. Los APK/AAB de CI y staging firmados con debug son exclusivamente de prueba. Respetar licencias y condiciones de uso de la cartografía. No marcar funcionalidades como completadas sin evidencia reproducible en el entorno correspondiente.


## Identidad compartida web/Android

La PR #56 ya eliminó las cifras ficticias del perfil y está integrada. El issue [#55](https://github.com/Baltas80/espana-outdoor/issues/55) continúa abierto: falta implementar el endpoint canónico autenticado `/v1/me`, la persistencia de perfiles y el flujo OIDC web con PKCE. La eliminación de estadísticas de muestra evita datos engañosos, pero no completa la identidad compartida.
