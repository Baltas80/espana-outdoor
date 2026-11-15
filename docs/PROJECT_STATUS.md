# España Outdoor — estado técnico

Última revisión: **15/11/2026 19:24 CET**. Rama de referencia: `main`, HEAD observado: `125932eacad78cefa838a2333a0a018d3451a6be`.

Este documento separa código integrado, pruebas automatizadas, validación de emulador, validación física y configuración externa. Un workflow verde o un APK compilado no equivalen a aceptación de producción.

## Resumen ejecutivo

- Android Flutter sigue siendo la prioridad.
- La seguridad de Source Gateway y Rescue Link está integrada en `main` mediante PR #68.
- El workflow de GitHub Pages está corregido en `2288290`; la ejecución de despliegue 43699356632 terminó correctamente. No se ha hecho una comprobación HTTP independiente del dominio en esta revisión.
- La navegación peatonal offline de Mapbox está en PR #61 y **no forma parte de `main`**. PR #61 sigue en draft, con HEAD `97aaa316efb878dc3e70c07c1288a2c175a3d003`, 166 commits por delante y 0 por detrás de `main`.
- No se acepta todavía el renderizado de mapas offline: una ejecución anterior calculó una ruta offline nueva, pero falló el renderizado y una captura resultó ser del launcher, no del mapa.
- La identidad web PKCE está en PR #64 (draft); falta configurar Keycloak y verificar una cuenta real contra backend/PostgreSQL desplegados.
- No se declara producción.

## Estado de `main`

HEAD: `2288290b3fb233fe5e0d124f0b38008a31b0cd25`.

Integraciones relevantes:

- PR #58: API canónica de perfiles `GET/PATCH /v1/me`, migración PostgreSQL y adaptador Flutter.
- PR #68: validación de access tokens firmados, issuer, audiencia dedicada y `typ=Bearer`; audiencias separadas para Source Gateway y Rescue Link; TLS de PostgreSQL obligatorio fuera del modo local explícito. Commit squash: `b5ec47c4e4d1f8f7f3343f0b14fa47363a4f2a7f`.
- `2288290`: alinea las versiones del uploader de artefactos Pages y del cliente deploy para corregir la publicación.

La rama `main` no tiene protección de rama habilitada en la última consulta a GitHub. Es un riesgo de proceso: conviene exigir CI y revisión antes de futuras integraciones.

## PR #61 — Mapbox Navigation peatonal offline

[PR #61](https://github.com/Baltas80/espana-outdoor/pull/61)  
Rama: `feat/mapbox-offline-routing-final-20261114`  
HEAD: `97aaa316efb878dc3e70c07c1288a2c175a3d003`  
Comparación con `main`: 166 commits por delante, 0 por detrás. PR abierta, draft y mergeable; no hay revisiones registradas.

La rama implementa:

- Un TileStore persistente en almacenamiento privado/no-backup.
- TileStore compartido por Maps y Navigation.
- Maps en `TileStoreUsageMode.READ_ONLY` para leer tile packs y mantener fallback a teselas individuales online fuera de la región.
- Descarga de style pack, teselas de Córdoba y recursos de routing peatonal.
- Origen nativo de ruta `online` / `offline`.
- Valhalla se mantiene para BTT/cicloturismo y map matching GPX online; esta PR no implementa routing offline de bicicleta ni cobertura nacional.
- Instrumentación de callbacks, errores de recursos y captura PNG host-side mediante ADB.
- Paridad de pixel ratio y rasterización de glyphs entre el descriptor nativo, el MapWidget de producción y el MapWidget del integration test.
- Captura host-side condicionada a que la app de prueba esté en primer plano; el validador ya no acepta una captura del launcher como prueba del mapa.

### CI del HEAD actual 97aaa316

- [CI 43741045698](https://github.com/Baltas80/espana-outdoor/actions/runs/43741045698): terminó correctamente.
- [Security baseline 43741045701](https://github.com/Baltas80/espana-outdoor/actions/runs/43741045701): terminó correctamente; 8/8 trabajos.
- [Android staging 43741045704](https://github.com/Baltas80/espana-outdoor/actions/runs/43741045704): análisis/tests, compilación APK, manifiesto y KVM superados en el primer intento. El job de emulador terminó con estado `failure`, pero el resumen del job y el estado del paso `Android map and routing validation` fueron inconsistentes; los logs devolvieron `BlobNotFound` y no se publicó evidencia de routing ni PNG. Se lanzó un reintento del job; al cierre de esta revisión sigue en ejecución.

Artefacto del primer intento, válido como build pero no como aceptación funcional:

- ID: `14172761851`.
- Application ID: `com.espanaoutdoors.espana_outdoors.iconspreview`.
- VersionCode: `5`.
- SHA-256 recalculado y coincidente con el manifiesto: `a7244146c6c739cc36d47db002bdcbaa71984c24c57ed037097148106b795fc3`.
- `source_commit=97aaa316efb878dc3e70c07c1288a2c175a3d003`.
- `validation_scope=runtime-capable-artifact`; ambos tokens Mapbox estaban disponibles durante la compilación.

### Evidencia runtime anterior, no equivalente a aceptación

La ejecución [43736972241](https://github.com/Baltas80/espana-outdoor/actions/runs/43736972241) registró:

- Ruta online nueva: 767,757 m / 55 puntos.
- Descarga Córdoba: 33/33 recursos, 0 errores, 42.847.606 bytes.
- Ruta peatonal nueva con origen nativo `OFFLINE` tras activar modo avión: 1.109,662 m / 66 puntos.
- El mapa no alcanzó `map_loaded`, `full_frame` ni `idle`; se registraron errores `IN_OFFLINE_MODE/NETWORK/TILE`.
- El PNG adjunto era el launcher Android, no el viewport de España Outdoor. Esa captura está invalidada.

Por tanto, el cálculo peatonal offline se ha demostrado en el integration test de emulador, pero el renderizado cartográfico offline no.

### Puertas obligatorias antes de fusionar #61

1. CI y Security baseline verdes en el HEAD final.
2. APK runtime-capable exacto con manifiesto y SHA-256.
3. Smoke online con callbacks style-loaded, map-loaded, full-frame e idle y PNG de la app correcta.
4. Descarga de Córdoba con recursos completos, cero errores y persistencia confirmada en TileStore.
5. Cierre forzado, modo avión y Wi-Fi desactivado.
6. Ruta nueva con origen nativo `OFFLINE`.
7. Mapa offline visible, callbacks completos, cero errores reales y PNG cuyo foreground sea la aplicación bajo prueba.
8. Reapertura y repetición después de reiniciar el emulador.
9. Validación posterior del APK candidato exacto en el OPPO físico.

No fusionar #61 hasta que las pruebas de emulador anteriores pasen en el mismo HEAD. La aceptación de producción sigue requiriendo el dispositivo físico.

## PR #64 — identidad web compartida

[PR #64](https://github.com/Baltas80/espana-outdoor/pull/64), estado draft.

Incluye `/cuenta.html`, Authorization Code + PKCE S256, cliente público web independiente y uso de `/v1/me`. La SPA usa `sessionStorage`, no almacena client secret ni refresh token y envía access tokens Bearer a la API.

Los tests de PKCE/contrato de seguridad y el preview de Cloudflare Pages pasaron en la ejecución anterior. Esto no demuestra login real ni perfil compartido.

Bloqueos externos:

- Configurar el cliente público Keycloak `espana-outdoors-web`, callbacks y Web Origins exactos para dominio raíz y www.
- Mantener el cliente Android `espana-outdoors-mobile`.
- Añadir la audiencia `espana-outdoors-api` al access token y comprobar `typ=Bearer`.
- Desplegar Source Gateway con PostgreSQL TLS, migración aplicada, issuer/audiencia/roles y CORS restringido.
- Probar login, GET/PATCH del mismo perfil desde web y Android; comprobar 401 con tokens incorrectos.

Seguimiento: [issue #55](https://github.com/Baltas80/espana-outdoor/issues/55).

## Dispositivo físico

[Issue #63](https://github.com/Baltas80/espana-outdoor/issues/63).

No hay evidencia nueva de instalación del APK candidato en el OPPO, modo avión físico ni persistencia tras reinicio. El procedimiento debe usar el APK y manifiesto del mismo run, verificar SHA-256 del `base.apk` instalado y conservar TileStore sin desinstalar la aplicación.

## Backend, routing y publicación

- Source Gateway y Rescue Link: pruebas Go, race/vet y controles de seguridad superados; despliegue de producción y PostgreSQL TLS no verificados.
- Valhalla: perfiles senderismo/BTT/cicloturismo en el cliente; endpoint y rutas reales de producción sin verificar en esta revisión.
- Keycloak: configuración real pendiente.
- GitHub Pages: workflow corregido y ejecución de despliegue correcta; dominio no verificado mediante HTTP independiente.
- Catálogo MITECO: sigue pendiente corregir los fallos TLS observados en la generación del catálogo; no desactivar la validación de certificados.
- Release Android: la configuración exige keystore dedicado para `APP_ENV=production`; falta una compilación firmada con secretos definitivos y verificación de huella.

## Incidencias abiertas prioritarias

- #55 — identidad OIDC y perfil compartido web/Android.
- #62 — routing offline BTT/cicloturismo.
- #63 — validar APK exacto en dispositivo físico.

Hay PRs de Dependabot y una PR inicial de comunidad abiertas; deben revisarse individualmente, sin mezclar su alcance con las puertas P0 de Android/offline/identidad.

## Hoja de ruta

1. Cerrar la ejecución 43739155167 e inspeccionar el PNG y logs del viewport offline.
2. Corregir la causa real del fallo de teselas; no aceptar capturas del launcher ni falsos positivos del gate visual.
3. Repetir descarga, ruta offline, renderizado, force-stop y reinicio en el mismo APK/HEAD.
4. Fusionar #61 solo al superar sus controles automatizados y de emulador.
5. Ejecutar el protocolo físico del issue #63 con el APK candidato exacto.
6. Provisionar PostgreSQL TLS, configurar Keycloak y desplegar Source Gateway/Rescue Link.
7. Probar la misma cuenta y perfil desde web y Android; completar #64 después de esa evidencia.
8. Verificar Valhalla real para senderismo, BTT y cicloturismo.
9. Abordar routing offline de bicicleta y ampliar cobertura regional.
10. Generar release firmado con keystore definitivo y realizar regresión final.

## Regla de aceptación

No declarar producción por una compilación, un preview, un workflow verde ni una ruta offline aislada. Se requiere evidencia reproducible de renderizado y routing sin red, validación física, identidad real compartida, servicios desplegados y release firmado.

## Actualización 15/11/2026 20:25 CET — diagnóstico Android staging

La revisión del job `android-staging` de [run 43741045704](https://github.com/Baltas80/espana-outdoor/actions/runs/43741045704) permite precisar el fallo que antes no tenía logs disponibles:

- Análisis/tests Flutter, APK staging, manifiesto y preparación KVM terminaron correctamente.
- El emulador arrancó y obtuvo una red Wi-Fi validada.
- El smoke online del APK release agotó 45 segundos: se recibió `MAPBOX_MAP_STYLE_LOADED`, pero no `MAPBOX_MAP_LOADED`, `MAPBOX_MAP_FULL_FRAME` ni `MAPBOX_MAP_IDLE`. Solo se registraron tres frames parciales.
- Se observaron respuestas de red correctas para algunos recursos sprite, glyph y vector tiles. Los `NOT_FOUND` de `DATABASE/CACHE` y `DATABASE/TILE_STORE` son misses de almacenamiento local y no deben contarse automáticamente como fallos HTTP.
- La fase `online_offline_routing` comenzó después del smoke. El runner recibió una señal de apagado a las 18:42:29Z antes de completar esa fase. No hay resultado de ruta ni artefacto de captura válido de esta ejecución.

Por tanto, este run **no** demuestra el renderizado del mapa online ni offline, y tampoco permite concluir el resultado de routing. No se atribuye el apagado del runner a una causa concreta sin evidencia adicional.

### Mejora del harness en PR #61

La rama `feat/mapbox-offline-routing-final-20261114` incorpora ahora:

- `tool/test_android_validation_order.py`, que protege el orden y la política de evidencias.
- Ejecución prioritaria de ruta online, descarga Córdoba y prueba offline antes del smoke independiente del APK release.
- `cancel-in-progress: false` en Android staging para que commits posteriores esperen y no cancelen una validación activa de la misma referencia.
- Documentación de este orden en `docs/MAP_OFFLINE.md`.

Commits de este incremento: `510423a`, `bf8a718`, `41cbbc6` y `10fd7b5`. Las pruebas locales del guard y `bash -n` pasaron. Todavía no existe una ejecución CI asociada al nuevo HEAD `10fd7b55ce995727b4d67d8de6092f0341a22569`; sus resultados quedan pendientes.

PR #61 continúa en draft. No se fusiona hasta que el mismo APK/HEAD supere descarga, ruta offline, renderizado PNG validado, reapertura y reinicio. La prueba física OPPO sigue siendo obligatoria para la aceptación de producción.


## Actualización 15/11/2026 21:22 CET — evidencia de fuentes Mapbox

La ejecución [43752643079](https://github.com/Baltas80/espana-outdoor/actions/runs/43752643079) terminó con fallo funcional, pero publicó evidencia suficiente para separar routing y cartografía:

- La ruta online se calculó: 767,757 m / 55 puntos.
- Córdoba se descargó con 33/33 recursos, 0 errores y 42.847.606 bytes.
- Tras activar modo avión y deshabilitar Wi-Fi, Mapbox Navigation devolvió una ruta nueva con origen nativo `offline`: 1.109,662 m / 66 puntos.
- El mapa offline no renderizó el viewport: `style_loaded=true`, `map_loaded=false`, `full_frame=false`, `idle=false`, 14 fallos `IN_OFFLINE_MODE/NETWORK/TILE`.
- La captura del integration test no se aceptó porque el paquete de prueba no estaba en primer plano. El artefacto separado del smoke online sí contiene una captura de la pantalla real de Mapa, con fondo y elementos de agua, pero sin cartografía viaria/etiquetas suficiente para aceptación.
- En el smoke online el estilo, sprites, glyphs y algunas teselas respondieron desde red; solo hubo dos frames parciales y no aparecieron errores de recurso ni callbacks de mapa completo.

No se cambia todavía el descriptor ni se amplía la región por conjetura. La rama añade instrumentación `sourceAdded`/`sourceDataLoaded` en producción y en el integration test para identificar qué fuentes vectoriales cargan metadata/tiles. Los IDs se saneen y se limitan los eventos; no se registran URLs, mensajes originales ni tokens.

Commits de instrumentación:
- `653bd89`: eventos de fuentes en el viewport de producción.
- `b037c82`: eventos de fuentes en la prueba offline.
- `df1fc3a`: mantener los logs del test compatibles con lint.
- `608e2e0` y `e799dab`: exigir los diagnósticos mediante el guard estático.
- `437bfb2`: documentar la evidencia y el diagnóstico.

La ruta offline peatonal queda demostrada en emulador; el mapa offline no. No fusionar #61 hasta que el mismo APK/HEAD produzca metadata/tiles de las fuentes necesarias, full frame, idle y PNG verificado; después debe repetirse persistencia y reinicio y validarse el APK exacto en OPPO.


## Captura ADB: corrección de buffering de stdout — 15/11/2026

La revisión del run 43752643079 mostró que el host veía `MAPBOX_OFFLINE_SCREENSHOT_READY` cuando la actividad de integración ya había abandonado el primer plano. La tubería del test pasaba por `sed` antes de `tee`; GNU sed con salida redirigida puede retener el marcador en un búfer de bloque. Se reprodujo localmente con un proceso que imprimía el marcador y esperaba 5 segundos: con `sed -E`, el log seguía en 0 bytes tras 1 segundo; con `sed -u -E`, el log contenía los 32 bytes del marcador tras 1 segundo.

Se cambia la tubería del runner a `sed -u -E` para que el host capture el PNG mientras el integration app sigue en primer plano. El guard `tool/test_android_validation_order.py` exige que el modo no-buffered permanezca. Esta corrección resuelve el fallo de sincronización de la captura; **no** resuelve ni disimula los 14 fallos offline de teselas ni acredita el renderizado. La próxima ejecución debe producir una captura del paquete correcto y permitir distinguir visualmente el viewport aunque el test termine fallando.


## Actualización CI 15/11/2026 — Flutter completo

En [CI 43758128192](https://github.com/Baltas80/espana-outdoor/actions/runs/43758128192), el job Flutter completó análisis, tests focalizados y suite completa correctamente; Source Gateway y Rescue Link también pasaron. Android release build e iOS seguían en ejecución en la última consulta.

[Security baseline 43758128131](https://github.com/Baltas80/espana-outdoor/actions/runs/43758128131): 8/8 trabajos superados.

[Android staging 43758128107](https://github.com/Baltas80/espana-outdoor/actions/runs/43758128107): pending sin jobs publicados. No se ha ejecutado todavía el nuevo cambio de captura `sed -u` en emulador.


## Corrección de falso positivo: TileRegion separados — 15/11/2026

La inspección de `MapboxNavigationBridge.kt` encontró un defecto de validación en la implementación anterior: Maps y Navigation se descargaban en un único `TileRegion`, se sumaban sus recursos y el puente devolvía `mapTiles=true` incondicionalmente. Por tanto, el resultado anterior `33/33`, 42.847.606 bytes demostraba recursos combinados persistidos, pero **no demostraba que el descriptor de Maps hubiera almacenado teselas vectoriales**. La ruta offline sí estaba demostrada por separado.

La rama cambia a dos regiones persistentes dentro del mismo TileStore:
- `<regionId>-maps`: solo `mapsDescriptor`.
- `<regionId>-routing-walking`: solo `navigationDescriptor`.

Cada región debe informar recursos completados y bytes mayores que cero, cero errores y, cuando Mapbox comunica el total requerido, completarlo. Los marcadores de persistencia se escriben con `commit()` solo después de que ambas regiones pasen. `hasOfflineRegion` comprueba ambos IDs, sus recursos y sus marcadores. El resultado nativo expone contadores/bytes separados y `mapTiles`/`routingTiles` ya no se asignan por un agregado.

La UI y el integration test exigen recursos no vacíos para Maps y Navigation por separado. Las regiones legacy con ID combinado no se eliminan ni se consideran verificadas; el usuario deberá repetir la descarga para generar los dos IDs nuevos. Esto evita aceptar falsos positivos y no destruye datos existentes.

La siguiente ejecución dará una respuesta concluyente:
- Si `OFFLINE_MAP_REGION_EMPTY/INCOMPLETE` ocurre, el descriptor de Maps no está almacenando el paquete esperado.
- Si ambas regiones contienen recursos pero los eventos `sourceDataLoaded` siguen fallando en modo avión, el problema estará en el matching entre tileset/viewport/TileStore, no en la descarga de routing.


## Actualización 15/11/2026 22:19 CET — captura offline basada en logcat

### Evidencia revisada del run 43758128107 (HEAD `e799dab1f2ab03fb018bf627f9ac7642dcf0cb7c`)

Se descargaron y revisaron los artefactos de Android staging:

- Ruta online nueva: 767,757 m / 55 puntos.
- Descarga legacy combinada: 33/33 recursos, cero errores, 42.847.606 bytes.
- Modo avión + Wi-Fi desactivado: ruta nueva con origen nativo `offline`, 1.109,662 m / 66 puntos.
- El mapa offline no renderizó: `style_loaded=true`, `map_loaded=false`, `full_frame=false`, `idle=false`; 14 fallos `IN_OFFLINE_MODE/NETWORK/TILE`.
- La captura del test de integración no se obtuvo porque, al leer el marcador de stdout, el launcher ya estaba en primer plano. El PNG del smoke release muestra la app real, pero solo fondo/agua sin cartografía viaria suficiente.

La descarga 33/33 pertenece al código anterior a la separación de TileRegions y no demuestra recursos Maps independientes. El nuevo código con `<regionId>-maps` y `<regionId>-routing-walking` todavía no tiene ejecución de emulador.

### Corrección del disparador de captura

Se detectó que `sed -u` no garantiza que el propio proceso `flutter test` vacíe stdout antes de terminar. El nuevo procedimiento:

1. Limpia logcat justo antes de la fase offline.
2. La app emite `MAPBOX_OFFLINE_SCREENSHOT_READY` con `debugPrint` desde el proceso Android.
3. El host observa `adb logcat -d -s flutter:I`, no usa stdout de Flutter como disparador.
4. La captura solo se acepta si el paquete derivado del namespace de integración está en primer plano.
5. El marcador stdout se conserva como diagnóstico secundario.

Commits: `6191113f0cdcf5b3c2a79a5b1242fced39d65e1e`, `71a5f7110ce66ae4e0d89178d2bf87042cf32752`, `9e3a768fcea431f784cc562e293ee025f9b5a2e0`.

El HEAD actual es `9e3a768fcea431f784cc562e293ee025f9b5a2e0`; comparación con `main`: 197 commits por delante y 4 por detrás. No hay ejecuciones Actions asociadas a este HEAD en la última consulta. La validación local/CI del nuevo mecanismo y de las dos TileRegions queda pendiente.

La PR #61 permanece en draft. No fusionar hasta obtener en un mismo HEAD: contadores Maps/Navigation independientes, ruta nueva offline, full frame, idle, cero fallos reales, PNG verificado, reapertura/reinicio y validación del APK exacto en OPPO.
