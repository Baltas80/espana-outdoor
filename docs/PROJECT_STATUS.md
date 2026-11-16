# España Outdoor — estado técnico

Última revisión: **16/11/2026 07:49 CET**. Rama de referencia: `main`, HEAD verificado: `412b899d36b47040b8e36ba66c0cfa7eb7df01db`.

Este documento separa código integrado, pruebas automatizadas, validación de emulador, validación física y configuración externa. Un workflow verde o un APK compilado no equivalen a aceptación de producción.

## Snapshot operativo — 16/11/2026 07:49 CET

### Estado de ramas y CI

- `main` apunta a `412b899d36b47040b8e36ba66c0cfa7eb7df01db`. PR #70 (Keycloak/PostgreSQL) está integrada; no hay despliegue real de esos servicios.
- PR #71 ([Android Community API](https://github.com/Baltas80/espana-outdoor/pull/71)) está lista para revisión, HEAD `963ded931e8279dff60a15ebd068019987b8c3b0`, 12 commits por delante y 0 por detrás. CI general [43817492034](https://github.com/Baltas80/espana-outdoor/actions/runs/43817492034) terminó correctamente y Security [43817491984](https://github.com/Baltas80/espana-outdoor/actions/runs/43817491984) pasó 8/8. Android staging [43817492001](https://github.com/Baltas80/espana-outdoor/actions/runs/43817492001) superó análisis/tests, compilación APK, verificación del APK, publicación y KVM; el smoke online sigue en ejecución. Artefacto APK: `14203902599`. No aceptar el perfil compartido hasta validar endpoint real y login.
- El workflow de #71 generó `resolved-pubspec-lock` (artefacto `14203038525`). El lockfile extraído tiene Git blob SHA `c40c72f594ecf647fe39557dd913c2096333df55`, distinto del lockfile versionado `cd4572ff04c3d0c47f90be6b99afe390f3ddfc97`. El job temporal `refresh-pub-lockfile` debe incorporar ese cambio tras el éxito del staging. Después hay que retirar el job con `contents: write`, exigir `flutter pub get --enforce-lockfile` y verificar que no modifica el archivo.
- PR #61 ([Mapbox offline](https://github.com/Baltas80/espana-outdoor/pull/61)) continúa en draft. HEAD `5993228a901e095b6b38690059a5c72f98f22b67`, 258 commits por delante y 4 por detrás. CI [43818184098](https://github.com/Baltas80/espana-outdoor/actions/runs/43818184098) y Security [43818184042](https://github.com/Baltas80/espana-outdoor/actions/runs/43818184042) terminaron correctamente; Security 8/8. Android staging [43818184089](https://github.com/Baltas80/espana-outdoor/actions/runs/43818184089) sigue pendiente sin jobs iniciados. Los cambios nuevos exigen style pack persistido y contabilizan los misses `NOT_FOUND/TILE_STORE` como fallos.
- PR #73 ([smoke visual Android](https://github.com/Baltas80/espana-outdoor/pull/73)) sigue en draft. HEAD actual `d74797aa3ef51f46721c3ff31c60653c17942ab0`. El artefacto real `14202823106` de run [43816647416](https://github.com/Baltas80/espana-outdoor/actions/runs/43816647416) mostró un viewport casi negro. Se añadió un validador PNG y se detectó que el smoke online no ejecutaba el preflight de red validada del emulador. La PR ahora exige `ANDROID_EMULATOR_CI=true` y ejecuta `ensure_android_emulator_online.sh` antes del lanzamiento. Es una hipótesis diagnóstica aún no validada por una nueva ejecución.
- PR #64 sigue en draft; no hay login real con Keycloak ni lectura/escritura del mismo perfil desde web y Android.
- Issue #72 confirma que `main` no está protegida (`protected=false`, sin rulesets activos). La conexión GitHub disponible permite lectura, pero no expone escritura de branch protection/rulesets; se requiere aplicar el ruleset desde una conexión con permisos de administración y verificarlo después.

### Puertas funcionales aún abiertas

- La ruta peatonal offline tiene evidencia anterior positiva en emulador; el renderizado completo de Maps no.
- No se ha demostrado un mapa online completo en el APK release actual ni un mapa offline con `MAP_LOADED`, `FULL_FRAME`, `IDLE`, cero errores y PNG válido.
- Faltan force-stop/reapertura, reinicio y validación del APK exacto en el OPPO físico.
- Keycloak/PostgreSQL están configurados y probados en integración desechable, no desplegados en producción. Valhalla, TLS, DNS/HTTP de los dominios y el perfil compartido real siguen pendientes.
- No declarar producción ni fusionar #61/#73 hasta que sus puertas funcionales pasen en el mismo HEAD.



## Resumen ejecutivo

- Android Flutter sigue siendo la prioridad.
- La seguridad de Source Gateway y Rescue Link está integrada mediante PR #68. La configuración de hostname/issuer Keycloak y el bootstrap PostgreSQL se integraron mediante PR #70 (`25507ff`); el despliegue real sigue pendiente.
- El workflow de GitHub Pages está corregido en `2288290`; la ejecución de despliegue 43699356632 terminó correctamente. No se ha hecho una comprobación HTTP independiente del dominio en esta revisión.
- La navegación peatonal offline de Mapbox está en PR #61 y **no forma parte de `main`**. Ver snapshot operativo superior: HEAD `5993228a901e095b6b38690059a5c72f98f22b67`, 258 commits por delante y 4 por detrás.
- No se acepta todavía el renderizado de mapas offline: una ejecución anterior calculó una ruta offline nueva, pero falló el renderizado y una captura resultó ser del launcher, no del mapa.
- La identidad web PKCE está en PR #64 (draft); falta configurar el realm/cliente, desplegar Keycloak/PostgreSQL y verificar una cuenta real compartida entre web y Android.
- No se declara producción.

## Snapshot operativo — 16/11/2026 (ciclo de entrega actual)

### Integraciones y validación actual

- PR #70 está fusionada en `main` como `25507ff`. El bootstrap se probó contra PostGIS desechable: creación/rotación idempotente de rol y base, login TCP, ownership, `docker compose config`, `go test -race` y `go vet`. No se ha desplegado PostgreSQL ni Keycloak de producción.
- PR #61 sigue abierta y en draft. Su HEAD es `5892864cb509db09ffc3a05583a6559000c11220`; la comparación actual indica 237 commits por delante y 2 por detrás de `main` (PR #70 y la actualización documental posterior se fusionaron después de la base de esta rama).
- Android staging [43804191767](https://github.com/Baltas80/espana-outdoor/actions/runs/43804191767), sobre `3fd60f7`, falló en `flutter analyze` porque Dart no define `sinh`; el commit `5892864` corrigió la fórmula inversa de Web Mercator con `exp/atan`. En [Android staging 43804464921](https://github.com/Baltas80/espana-outdoor/actions/runs/43804464921) ya pasaron guards, cobertura geométrica, preflight, NDK/dependencias y `Analyze and test`; la compilación APK sigue en curso. [CI 43804464984](https://github.com/Baltas80/espana-outdoor/actions/runs/43804464984): Source Gateway, Rescue Link e iOS superados; Flutter/Android release sigue compilando. [Security 43804464891](https://github.com/Baltas80/espana-outdoor/actions/runs/43804464891): 8/8 superados.
- Android staging [43804363653](https://github.com/Baltas80/espana-outdoor/actions/runs/43804363653), sobre `6f79421`, terminó fallando en `flutter analyze` por el mismo uso de `math.sinh`; no aporta evidencia de mapa. El HEAD actual incluye el cálculo corregido y la geometría alineada en `OfflinePage`.
- El run [43799514133](https://github.com/Baltas80/espana-outdoor/actions/runs/43799514133), sobre `470a194`, demostró TileStore compartido, descriptor Maps presente, ambas regiones y ruta nueva con origen `OFFLINE`. El mapa falló con 14 misses `NOT_FOUND/TILE_STORE`; los tiles observados fueron z13 x3986–3987, y3162–3164.
- Se detectó que el polígono anterior `37.85..37.93` solo cubría una franja de la fila y=3164. El test y `OfflinePage` se ampliaron a latitud `37.78..37.97`, longitud `-4.84..-4.72`. `tool/test_mapbox_offline_region_coverage.py` comprueba que ambos polígonos sean idénticos y cubran por completo los seis tiles z13 observados. La lógica Python del guard se ejecutó localmente sobre fixtures equivalentes y pasó; la integración Android sigue pendiente.
- PR #64 sigue en draft. En HEAD `3d4a436` Web OIDC [43804969608](https://github.com/Baltas80/espana-outdoor/actions/runs/43804969608) y Security [43804969563](https://github.com/Baltas80/espana-outdoor/actions/runs/43804969563) (8/8) han pasado; CI general [43804969693](https://github.com/Baltas80/espana-outdoor/actions/runs/43804969693) sigue con Flutter/iOS en ejecución. El discovery ahora exige `code` y PKCE S256. La cuenta real compartida y la configuración del realm siguen pendientes.
- La configuración Android de `main` todavía pasa `SOURCE_GATEWAY_BASE_URL` pero no `COMMUNITY_API_BASE_URL`, mientras `CommunityIdentityApi` lee `COMMUNITY_API_BASE_URL`. PR #61 ya añade esa variable al entorno, preflight y `--dart-define`; hasta integrar ese cambio, los perfiles móviles pueden quedar sin API configurada en builds derivados de `main`.
- No hay todavía evidencia de mapa offline completo (`MAP_LOADED`, `FULL_FRAME`, `IDLE`, cero fallos de recursos y PNG válido), reinicio real ni validación del APK exacto en el OPPO.

### Criterio vigente

No fusionar PR #61 hasta que el mismo HEAD demuestre descarga Maps/Navigation, ruta nueva offline, renderizado completo sin fallos, PNG de la aplicación correcta, persistencia tras force-stop/reinicio y posteriormente instalación/validación del APK exacto en OPPO. No declarar producción hasta verificar además PKCE/perfil compartido, endpoints TLS, PostgreSQL, Valhalla y despliegue web.

---

## Estado de `main`

HEAD: `f2d41542ee524d72422f86c37625b0fd5c67059d`.

Integraciones relevantes:

- PR #58: API canónica de perfiles `GET/PATCH /v1/me`, migración PostgreSQL y adaptador Flutter.
- PR #68: validación de access tokens firmados, issuer, audiencia dedicada y `typ=Bearer`; audiencias separadas para Source Gateway y Rescue Link; TLS de PostgreSQL obligatorio fuera del modo local explícito. Commit squash: `b5ec47c4e4d1f8f7f3343f0b14fa47363a4f2a7f`.
- PR #70: hostname estricto de Keycloak, `OIDC_ISSUER` alineado con Compose y bootstrap idempotente de la base `keycloak`. Commit squash en `main`: `25507ff224ed3a9404b962737f7271dfda0f96fb`. CI/PostGIS de integración y Security 8/8 superados antes de fusionar; no equivale a despliegue.
- `2288290`: alinea las versiones del uploader de artefactos Pages y del cliente deploy para corregir la publicación.

La protección de `main` no está verificada: la consulta al endpoint de protección devolvió `403 Resource not accessible by integration`. No concluir que esté deshabilitada ni cambiar reglas sin evidencia.

## PR #61 — Mapbox Navigation peatonal offline (histórico; ver snapshot operativo superior)

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


## Actualización 15/11/2026 21:35 CET — estado verificado de PR #61

Main permanece sin la implementación de Navigation offline. PR #61 continúa en draft, rama `feat/mapbox-offline-routing-final-20261114`, último commit observado `d5afd38cace1411c16ec92265165beef5c19bd6f`. La comparación actual indica 179 commits por delante y 2 por detrás de `main`; la ascendencia de los dos commits documentales posteriores a `125932e` sigue pendiente de incorporar antes de la integración. La PR no está marcada mergeable en la consulta actual.

### Evidencia Android del run 43752643079

- Ruta online nueva: 767,757 m / 55 puntos.
- Descarga Córdoba: 33/33 recursos, 0 errores, 42.847.606 bytes.
- Modo avión + Wi-Fi deshabilitado: ruta peatonal nueva con origen nativo `offline`, 1.109,662 m / 66 puntos.
- Mapa offline no aceptado: `style_loaded=true`, `map_loaded=false`, `full_frame=false`, `idle=false`, 14 fallos `IN_OFFLINE_MODE/NETWORK/TILE`.
- El artefacto de smoke online muestra la app real, pero solo fondo/agua; no hay mapa completo ni callbacks de carga completa. La captura offline del test fue rechazada porque el host observó el launcher en primer plano.

### Correcciones de diagnóstico en PR #61

Se añadieron eventos `sourceAdded` y `sourceDataLoaded` al viewport de producción y al integration test, con IDs saneados, eventos acotados y sin URLs/tokens. Además se detectó y reprodujo un defecto del harness: GNU sed retenía el marcador de captura por buffering. Con `sed -E`, el archivo permaneció en 0 bytes tras 1 segundo; con `sed -u -E`, el marcador de 32 bytes llegó antes de 1 segundo. El runner usa ahora `sed -u -E` y el guard estático lo exige.

Commits recientes en la rama:
- `653bd89`, `b037c82`: instrumentación de fuentes.
- `df1fc3a`, `608e2e0`, `e799dab`: lint y guard estático.
- `437bfb2`, `36f5391`: documentación.
- `6df6281`, `1e4264d`: captura ADB sin buffering.
- `5753d0d`, `d5afd38`: documentación de la corrección.

### CI observado

- Security baseline [43758128131](https://github.com/Baltas80/espana-outdoor/actions/runs/43758128131): 8/8 trabajos superados.
- CI general [43758128192](https://github.com/Baltas80/espana-outdoor/actions/runs/43758128192): Source Gateway y Rescue Link superados; Flutter/iOS seguían en ejecución en la última consulta.
- Android staging [43758128107](https://github.com/Baltas80/espana-outdoor/actions/runs/43758128107): estado pending sin jobs publicados en la última consulta. No hay validación nueva del commit de captura `6df6281`.

No se fusiona #61 hasta que la siguiente ejecución capture el viewport de la app correcta y demuestre fuentes/teselas, full-frame, idle y cero fallos reales offline. Después se requieren force-stop/reinicio y validación del APK exacto en OPPO. La ruta peatonal offline sí está demostrada en emulador; el mapa offline no.


## Corrección de aceptación de TileStore — 15/11/2026

La revisión del puente nativo de PR #61 detectó un falso positivo en el diagnóstico anterior: Maps y Navigation se descargaban en un único TileRegion y el resultado devolvía `mapTiles=true` incondicionalmente. El resultado 33/33 recursos / 42.847.606 bytes del run 43752643079 era agregado; no demostraba que el descriptor de Maps hubiera almacenado teselas vectoriales. La ruta peatonal offline sí estaba demostrada por separado.

La rama PR #61 (último HEAD observado `8489728d450b374f6af0b357b62ea285a51b7939`) separa ahora:
- `<regionId>-maps`: solo descriptor de Maps.
- `<regionId>-routing-walking`: solo descriptor de Navigation.

Cada TileRegion debe tener recursos y bytes mayores que cero, cero errores y completar el total requerido cuando esté disponible. Los marcadores se escriben solo cuando ambas regiones pasan; `hasOfflineRegion` verifica ambos IDs y marcadores. UI y integration test exigen contadores/bytes independientes. Las regiones legacy no se borran ni se consideran verificadas hasta redescargar.

La modificación está en PR #61, no en `main`. No existe todavía un workflow nuevo asociado a estos commits; el último CI general observado (run 43758128192) había superado análisis y suite Flutter, con Android release/iOS aún ejecutándose. Security baseline 43758128131: 8/8. Android staging 43758128107 seguía pending sin jobs publicados. La compilación nativa y la descarga separada requieren CI nuevo antes de aceptar esta corrección.

La PR sigue en draft y no mergeable: 193 commits por delante, 3 por detrás; merge base `125932eacad78cefa838a2333a0a018d3451a6be`. No se fusiona hasta validar los dos TileRegions, ruta offline, renderizado PNG correcto y reinicio; después se requiere validación del APK exacto en OPPO.


## Actualización 15/11/2026 22:19 CET — evidencia Android revisada

Se descargaron y revisaron los artefactos del run [43758128107](https://github.com/Baltas80/espana-outdoor/actions/runs/43758128107), ejecutado sobre el HEAD anterior de PR #61 (`e799dab1f2ab03fb018bf627f9ac7642dcf0cb7c`):

- Ruta online nueva: 767,757 m / 55 puntos.
- Descarga legacy agregada: 33/33 recursos, cero errores, 42.847.606 bytes. Este total no separa Maps y Navigation y no demuestra teselas Maps independientes.
- Modo avión + Wi-Fi desactivado: ruta peatonal nueva con origen nativo `offline`, 1.109,662 m / 66 puntos.
- Mapa offline: `style_loaded=true`, `map_loaded=false`, `full_frame=false`, `idle=false`; 14 fallos `IN_OFFLINE_MODE/NETWORK/TILE`.
- El PNG del smoke release muestra la app real, pero solo fondo/agua sin cartografía viaria suficiente. La captura del integration test no se obtuvo porque el launcher estaba en primer plano al leer el marcador.

La rama de PR #61 separa ahora las TileRegions de Maps y Navigation y ha cambiado el disparador de captura a un marcador `debugPrint` observado desde Android logcat; el host exige que el paquete de integración esté en primer plano. Commits de captura: `6191113`, `71a5f71`, `9e3a768`.

La rama quedó sincronizada con main mediante [e6153d1](https://github.com/Baltas80/espana-outdoor/commit/e6153d18941baa5f3dd4d23c55a710a3b6a14b5b): 201 commits por delante y 0 por detrás. PR #61 sigue abierta y en draft. No hay todavía una ejecución Actions asociada al HEAD e6153d1; el CI general y Security baseline del run anterior no validan los cambios de TileRegion independiente ni el nuevo capturador logcat.

No fusionar #61 hasta que un mismo HEAD supere CI, descarga separada de Maps/Navigation, ruta nueva offline, renderizado completo (style/map/full-frame/idle), cero fallos reales, PNG de la app de integración, reapertura/reinicio y posterior validación del APK exacto en OPPO. La ruta peatonal offline está demostrada en emulador; el mapa offline y la aceptación física no.


## Actualización 16/11/2026 01:20 CET — APK staging del HEAD 9b3b0fbe

La ejecución [Android staging 43774889122](https://github.com/Baltas80/espana-outdoor/actions/runs/43774889122), asociada a la rama `feat/mapbox-offline-routing-final-20261114` y al commit fuente `9b3b0fbe1e31942b39a3b9e68c3dbfdfca7e7692`, completó correctamente:

- Guards de Mapbox, TileStore y captura.
- Verificador del proyecto Android nativo.
- Instalación de Java 21, Flutter y NDK 28.2.
- Resolución de dependencias con lockfile.
- `flutter analyze --no-fatal-infos` y `flutter test --coverage`.
- Compilación del APK release de staging.
- Verificación del APK y generación del manifiesto.
- Preparación KVM.

Artefacto `android-staging-apk`: ID `14186202284`. El APK extraído es un paquete Android válido; su SHA-256 recalculado coincide con el campo `apk_sha256` del manifiesto:

`5f73c4998e30f41543379f5fe0dce1b2dd5f7165d40ccd4275d85608ca1b1c37`

Application ID: `com.espanaoutdoors.espana_outdoors.iconspreview`; versionCode 5; `validation_scope=runtime-capable-artifact`; tokens de runtime y descarga Mapbox disponibles durante la compilación.

**La fase funcional del emulador no había terminado en la última consulta.** El job `Android map and routing validation` seguía `in_progress`; GitHub aún no publicaba los artefactos de routing/captura y la descarga de logs devolvía `BlobNotFound` mientras el job seguía activo. No hay evidencia nueva de descarga de regiones independientes, ruta offline, renderizado PNG ni reinicio para este HEAD.

CI general [43774889115](https://github.com/Baltas80/espana-outdoor/actions/runs/43774889115): 4/4 jobs correctos (Flutter, Source Gateway, Rescue Link e iOS). Security baseline [43774889184](https://github.com/Baltas80/espana-outdoor/actions/runs/43774889184): 8/8 trabajos correctos.

PR #61 permanece en draft. No integrar hasta que el mismo HEAD supere descarga separada Maps/Navigation, ruta nueva con conectividad desactivada, renderizado completo (`style_loaded`, `map_loaded`, `full_frame`, `idle`), cero fallos reales, PNG de la aplicación de integración, reapertura/reinicio y posterior validación del APK exacto en OPPO.


## Actualización 16/11/2026 01:24 CET — runner Android sin evidencias y reintento

El primer intento del job Android de [run 43774889122](https://github.com/Baltas80/espana-outdoor/actions/runs/43774889122) terminó con estado de job `completed/failure`, pero GitHub dejó el paso `Android map and routing validation` como `in_progress`. Los pasos de subida de artefactos de routing y captura quedaron pendientes; el endpoint de logs devolvió `BlobNotFound`. No existe evidencia de que la fase funcional llegara a completar ni base para atribuirlo a un fallo de Mapbox. La causa de la terminación anómala del runner no está demostrada.

El APK y su manifiesto sí se conservaron y verificaron en el apartado anterior. Se solicitó repetir exclusivamente el job fallido mediante GitHub Actions; GitHub aceptó la operación y la nueva tentativa comenzó desde `Set up job`. El estado de esta nueva tentativa queda pendiente.

No aceptar el modo offline, no fusionar PR #61 y no clasificar el fallo como funcional hasta disponer de logs y artefactos del reintento.


## Actualización 16/11/2026 03:25 CET — revisión de Keycloak y evidencia visual del smoke Android

### PR #61 — Mapbox offline

HEAD actual: `82da1995ce545af4c28e27e46b9afe4159b1ce51` (`test(android): guard persistent offline TileStore lifecycle`). Comparación observada con `main`: 217 commits por delante y 3 por detrás. PR abierta, draft; no fusionada.

Se ha añadido una guarda estática para exigir que el TileStore:
- Fije `TileStore.setRootPath(path)` antes de `TileStore.create()`.
- Use `noBackupFilesDir/mapbox-tiles`, no un directorio de caché evictable.
- Compruebe la creación del directorio y el resultado de `setRootPath`.
- No se elimine al destruir el puente de navegación.

La última evidencia funcional completa sigue siendo del APK construido desde el commit `9b3b0fbe`: descarga Maps (29 recursos / 32.892.088 bytes), Navigation walking (4 recursos / 9.955.518 bytes) y ruta peatonal nueva con origen `OFFLINE` correctas; el renderizado no se completó (`map_loaded=false`, `full_frame=false`, `idle=false`, 14 fallos `IN_OFFLINE_MODE/NETWORK/TILE`). Las correcciones posteriores del puente y del harness no cuentan como validadas funcionalmente hasta que Android staging ejecute ese HEAD.

### Evidencia de falso positivo en el smoke de main

En el run [43786917459](https://github.com/Baltas80/espana-outdoor/actions/runs/43786917459), el job `Android map native smoke` terminó correctamente y publicó el artefacto [14191885065](https://github.com/Baltas80/espana-outdoor/actions/runs/43786917459/artifacts/14191885065). Se descargó y abrió `espana-outdoor-map.png`: la aplicación estaba en primer plano, pero el viewport cartográfico aparecía prácticamente negro y sin cartografía visible suficiente.

Métricas calculadas sobre la zona central del PNG de 1080×2400: 38 colores cuantizados, opacidad 1.000, entropía 0.650 bits y color dominante 0.901. El validador de captura de PR #61 exige entropía >1.2 y color dominante <0.85; por tanto, rechazaría esa imagen. El smoke de `main` no debe contarse como prueba de renderizado: su script solo comprobaba que la app siguiera viva y que no apareciera el estado textual de error, no los callbacks completos del motor cartográfico.

### PR #70 — hostname público de Keycloak (snapshot anterior a la fusión; ahora integrada en `main`)

[PR #70](https://github.com/Baltas80/espana-outdoor/pull/70), rama `fix/keycloak-public-hostname-20261116`, HEAD `2a2d1c65e9224a65cca2ed1074bd6cf8da0c24f0`, 7 commits por delante y 0 por detrás de `main`. Sigue en draft.

Durante una revisión adicional se detectó que Compose consume `OIDC_ISSUER`, mientras que `PRODUCTION_ENDPOINTS.template.env` declaraba `OIDC_ISSUER_URL`. La plantilla podía dejar el issuer de Source Gateway sin configurar. Se corrigió la plantilla para usar `OIDC_ISSUER=https://auth.espanaoutdoor.es/realms/espana-outdoor` y se amplió `tool/test_rescue_link_compose.py` para exigir que los issuers local y de producción coincidan con sus hostnames y con el nombre de variable consumido por Compose.

Ejecuciones sobre el HEAD `2a2d1c65`:
- Security baseline [43792308634](https://github.com/Baltas80/espana-outdoor/actions/runs/43792308634): 8/8 trabajos correctos.
- CI [43792308624](https://github.com/Baltas80/espana-outdoor/actions/runs/43792308624): Source Gateway y Rescue Link correctos; Flutter e iOS seguían en ejecución en la última consulta.
- Android staging [43792308581](https://github.com/Baltas80/espana-outdoor/actions/runs/43792308581): análisis y tests seguían en ejecución; compilación y emulador pendientes.

Los resultados del run anterior [43786917459](https://github.com/Baltas80/espana-outdoor/actions/runs/43786917459) fueron 8/8 en Security y 4/4 en CI, pero su smoke Android no demuestra renderizado cartográfico (véase la evidencia anterior).

### Estado de aceptación

- Ruta peatonal online: demostrada en emulador.
- Ruta peatonal nueva offline: demostrada en emulador.
- Descarga independiente Maps/Navigation: demostrada en el APK histórico `9b3b0fbe`.
- Mapa offline renderizado y captura válida: no aceptados.
- Persistencia tras force-stop y reinicio: guard estática añadida; prueba funcional pendiente.
- APK candidato instalado y validado en OPPO físico: pendiente.
- Keycloak discovery público y flujo de cuenta real web/Android: pendiente.
- PostgreSQL TLS, Valhalla y endpoints de producción: pendientes de verificación externa.
- PR #61 y PR #70: abiertas, draft; no fusionadas.

No desplegar ni declarar producción hasta que se completen las pruebas funcionales y externas indicadas.
