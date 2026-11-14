# España Outdoor — estado técnico

Última revisión del repositorio remoto: **14/11/2026**. Rama de referencia: `main`, HEAD `bbcb3daa706e86f4e3d7e581d58cea7119a4a52d`. Este documento separa cambios integrados, checks automatizados y validaciones que requieren un dispositivo o servicios reales.

## Objetivo MVP

Android primero. El criterio de aceptación es un APK instalable que abra el mapa, renderice cartografía real, permita usar GPS y rutas, y gestione correctamente errores y pérdida de conectividad. La web pública debe seguir funcionando, pero no sustituye la validación de Android.

## Cambios integrados recientemente

- PR #43, iconos premium: integrada en `935d1e85a203c2f79ce169834a2ff0e4b5d6aaa3`.
- PR #44, firma de producción Android: integrada en `b3a2756d9dcad64389cd0d225d87849a233c0393`. Los builds con `APP_ENV=production` exigen una clave de release dedicada; el workflow comprueba la huella SHA-256 del APK y del AAB.
- PR #45, búsqueda y filtros del catálogo de rutas: integrada en `bbcb3daa706e86f4e3d7e581d58cea7119a4a52d`, con pruebas unitarias para búsqueda, normalización y combinación de filtros.

Los checks de las ramas de PR #44 y #45 terminaron correctamente: CI, Android staging y Security baseline; CI incluyó además los trabajos de Flutter, Source Gateway e iOS. Estos resultados corresponden a los HEAD de las PR antes de la fusión. No prueban instalación física, funcionamiento offline ni la generación de un candidato de producción.

## Arquitectura cartográfica y routing en main

- Motor cartográfico: **Mapbox**, mediante `mapbox_maps_flutter 3.33.0`.
- La pantalla de mapas offline usa `OfflineManager` y `TileStore.createDefault()` para descargar el estilo y una región de prueba de Córdoba.
- El proveedor de rutas de `main` utiliza `ValhallaRoutingService` con `VALHALLA_BASE_URL`. Ese servicio requiere conectividad; no debe presentarse como cálculo de rutas offline.
- La persistencia de teselas, la reapertura en frío, el renderizado en modo avión y el alcance de las regiones deben validarse en el APK exacto que se pretenda distribuir.
- Una región de Córdoba no demuestra cobertura cartográfica nacional.

## Estado de navegación offline

La PR [#25 — Android: Mapbox Navigation offline routing](https://github.com/Baltas80/espana-outdoor/pull/25) sigue abierta y no está integrada. Su rama `feat/mapbox-offline-navigation` está divergida respecto a `main`: **22 commits por delante y 4 por detrás** en la comparación del 14/11/2026. La rama utiliza Mapbox Maps 3.34.1, mientras que `main` mantiene 3.33.0, y modifica archivos que también han cambiado en las PR #43, #44 y #45.

El HEAD anterior de la PR #25 (`cf10f143d13a1fc98aae39120402c06e8493d8d7`) tuvo CI, Android staging y Security baseline correctos en su contexto anterior. Esos checks no validan la rama contra el `main` actual. La PR no debe fusionarse tal como está: hay que portar/rebasar la integración nativa, resolver los solapamientos de Gradle, workflows, configuración Android y pantallas, y repetir CI.

## Validación disponible y límites

| Comprobación | Estado |
|---|---|
| Checks CI de PR #44 y #45 | Correctos en sus HEAD previos a la fusión |
| Guard de firma de producción | Integrado; falta ejecutar Release candidate con secretos reales |
| APK/AAB staging | Android staging correcto en ambas PR; firma debug, no distribuible |
| Mapa online en dispositivo físico con el HEAD actual | Pendiente de nueva evidencia |
| Descarga y persistencia de región offline en el HEAD actual | Pendiente de validación reproducible |
| Reapertura en frío y mapa renderizado en modo avión | Pendiente en dispositivo físico |
| Cálculo de una ruta nueva con origen nativo `OFFLINE` | No integrado en `main`; PR #25 pendiente |
| Routing real con Valhalla en producción | Pendiente de comprobar endpoint y respuesta |
| Firma release y candidato de producción | Pendiente de secretos y ejecución manual del workflow |

Una prueba anterior de la región de Córdoba fue reportada como funcional sin conexión en un OPPO. Es evidencia histórica de una prueba de concepto; no acredita el APK actual, reapertura tras reinicio, cálculo offline de rutas ni cobertura nacional.

## Pendientes prioritarios

1. Portar la integración Mapbox Navigation offline de la PR #25 sobre el `main` actual, sin sobrescribir las mejoras de iconos, firma y catálogo ya integradas.
2. Ejecutar los tests y Android staging sobre la rama resultante; corregir cualquier regresión antes de fusionar.
3. Instalar el APK exacto en el OPPO y registrar mapa online, permisos, GPS y descarga de Córdoba.
4. Con la región descargada, forzar cierre, activar modo avión y comprobar renderizado, persistencia y cálculo de una ruta nueva con origen explícito `OFFLINE`; repetir tras reiniciar el dispositivo.
5. Verificar Valhalla y los servicios backend con endpoints HTTPS reales.
6. Configurar de forma segura los cinco secretos de firma Android y ejecutar manualmente el workflow Release candidate. No crear una clave nueva si ya existe una clave de subida registrada en Google Play.
7. Auditar autenticación móvil/web, perfil, backend Go, PostgreSQL y permisos antes de ampliar funcionalidades de comunidad.

## Criterio de seguridad

No incluir secretos en código, Git, artefactos públicos ni logs. Los APK/AAB de CI y staging firmados con debug son exclusivamente de prueba. Respetar licencias y condiciones de uso de la cartografía. No marcar funcionalidades como completadas sin evidencia reproducible en el entorno correspondiente.
