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
