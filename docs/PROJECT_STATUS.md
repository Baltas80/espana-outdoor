# España Outdoor — estado técnico

Última revisión: **14/11/2026**. Rama base: `main`. Último commit integrado confirmado antes de esta rama: `c878af97e12faf19e45cfa80335310a60ab70783` (PR #50).

Este documento diferencia el estado integrado de los cambios preparados en `feat/mapbox-offline-routing-port-20261114`. Los cambios de esa rama todavía no están integrados ni aceptados por CI.

## Estado integrado en main

- PR #43: corrección de iconos premium.
- PR #44: protección de firma Android. Los builds con `APP_ENV=production` exigen keystore dedicado; el release candidate verifica la huella SHA-256 del APK y del AAB.
- PR #45: búsqueda y filtros del catálogo de rutas.
- PR #47: perfiles Senderismo, BTT y Cicloturismo, con parámetros de Valhalla.
- PR #28: actualización de pgx.
- PR #38: actualización de CodeQL Action.
- PR #26 y #27: actualización de imágenes builder Go.
- PR #49: documentación técnica.
- PR #50: Android staging de Dependabot sin token Mapbox de runtime. No convierte un artefacto compile-only en prueba de mapas.

Las comprobaciones anteriores de esas PR corresponden a sus respectivos HEAD y no acreditan pruebas físicas del dispositivo ni un release firmado.

## Cambios preparados en la rama de integración offline

1. Puente nativo Android entre Flutter y Mapbox Navigation SDK 3.34.1.
2. Mapbox Maps SDK Android 11.34.1 y NDK r27d, alineados con `mapbox_maps_flutter 3.34.1`.
3. Un único `TileStore` persistente bajo `noBackupFilesDir/mapbox-tiles`, compartido por Maps y Navigation. El token global se configura antes de crear el almacén.
4. Descarga de estilo, teselas de mapa y routing peatonal de una región de prueba de Córdoba.
5. La respuesta nativa identifica el origen real del router: `online` o `offline`. La app no debe etiquetar como offline una ruta devuelta por otro motor.
6. Routing compuesto: Mapbox Navigation para senderismo/peatonal en Android; Valhalla para BTT, cicloturismo y ajuste de tracks GPX. En otras plataformas se mantiene Valhalla.
7. Pruebas unitarias del adaptador Mapbox y del selector de motor.
8. Prueba de integración que descarga Córdoba, fuerza el cierre, activa modo avión, solicita una ruta nueva y espera el evento Mapbox `onMapLoaded` para comprobar que se han renderizado las teselas visibles.
9. El proyecto Android nativo queda versionado y los workflows dejan de regenerarlo. Se conserva el guard de firma de producción y el identificador de paquete alternativo para staging.

## Límites funcionales

- El routing offline implementado en esta fase es **peatonal**. BTT y cicloturismo continúan usando Valhalla online. No se afirma routing offline para bicicletas.
- La integración actual calcula rutas y devuelve geometría e instrucciones. No debe describirse como navegación guiada completa con seguimiento de progreso, desvíos y recálculo hasta que esas funciones se implementen y prueben.
- Córdoba es una región de prueba delimitada. No demuestra cobertura de España.
- Una región presente en TileStore no demuestra por sí sola que el mapa se renderice, que el proceso sobreviva a un reinicio o que se calcule una ruta nueva sin conexión.

## Credenciales de compilación

- `MAPBOX_ACCESS_TOKEN`: token público de runtime, necesario para cargar el estilo y validar el mapa.
- `MAPBOX_DOWNLOADS_TOKEN`: token de Mapbox Downloads con permiso de lectura Maven, necesario para resolver los artefactos nativos privados.
- Secretos de firma Android: `ANDROID_RELEASE_KEYSTORE_BASE64`, `ANDROID_RELEASE_STORE_PASSWORD`, `ANDROID_RELEASE_KEY_ALIAS`, `ANDROID_RELEASE_KEY_PASSWORD` y `ANDROID_RELEASE_CERT_SHA256`.

No se deben incluir valores de estos secretos en Git, artefactos, informes ni logs. Dependabot no recibe secretos de Actions; cuando no dispone de `MAPBOX_DOWNLOADS_TOKEN`, el workflow omite expresamente la compilación Android y conserva análisis y pruebas Dart. Ese resultado no se considera validación Android.

## Validación pendiente

| Área | Estado |
|---|---|
| CI, análisis y pruebas de la rama de integración | Pendiente de ejecución |
| Resolución reproducible de dependencias y lockfile | Workflow preparado para resolver, versionar y verificar el lockfile; resultado pendiente |
| Compilación Android con Mapbox Maven | Pendiente de CI con `MAPBOX_DOWNLOADS_TOKEN` |
| Routing online y origen `ONLINE` | Pendiente de prueba integrada |
| Descarga y persistencia de Córdoba | Pendiente de prueba integrada |
| Routing nuevo con origen `OFFLINE` en emulador | Pendiente |
| Evento de mapa cargado y teselas visibles en modo avión | Pendiente |
| Cierre, reapertura y reinicio en OPPO físico | Pendiente |
| BTT/cicloturismo contra Valhalla real | Pendiente |
| Registro, login y perfil web/Android | Auditoría funcional pendiente |
| Release firmado y despliegue de producción | Pendiente |

## Siguiente secuencia

1. Ejecutar CI y Android staging en la rama de integración; corregir fallos de Kotlin, Gradle, Dart o dependencias.
2. Exportar y versionar el `pubspec.lock` resuelto por Flutter; exigir después que no cambie durante CI.
3. Validar en emulador ruta online, descarga, cierre forzado, modo avión, ruta nueva con origen `OFFLINE` y renderizado del mapa.
4. Ejecutar `tool/test_mapbox_oppo_routes.ps1` en el OPPO, con conectividad restaurada al finalizar. Repetir después de reiniciar el dispositivo.
5. Fusionar únicamente tras CI verde y revisión de los resultados; no marcar offline como aceptado hasta disponer de evidencia física reproducible.

## Seguridad

No publicar secretos. No usar artefactos firmados con debug como releases. No eliminar ni regenerar recursos de producción para hacer pasar una prueba. Mantener la atribución y las condiciones de uso de Mapbox y OpenStreetMap.
