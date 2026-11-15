# España Outdoor — estado técnico

Última revisión: **15/11/2026 14:23 CET**.

- Rama de producción: main
- HEAD observado de main: 2288290b3fb233fe5e0d124f0b38008a31b0cd25
- PR Android offline: [#61](https://github.com/Baltas80/espana-outdoor/pull/61), abierta y lista para revisión.
- Rama PR #61: feat/mapbox-offline-routing-final-20261114
- HEAD de código examinado antes de esta actualización: 4664692c9406222cd3a191455824712196ef27dc.
- HEAD de la rama al inicio de esta actualización documental: cfb3ec6c7583790be32ad6fdf723f767aa4c3192.
- La rama está 132 commits por delante y 1 por detrás de main; el único commit pendiente de sincronización es el despliegue de Pages de main.

Este documento separa código integrado, pruebas automatizadas, emulador, dispositivo físico y servicios externos. Un workflow verde o un APK compilado no equivalen a aceptación de producción.

## Estado integrado en main

- PR #44: protección de firma release Android integrada. Falta validar una distribución firmada con el keystore real de producción.
- PR #47: perfiles Senderismo, BTT y Cicloturismo integrados. Falta comprobar rutas reales de Valhalla para cada perfil.
- PR #50: staging de Dependabot integrado; sin credenciales Maven Mapbox se identifica como análisis/tests sin APK nativo validado.
- PR #58: API canónica de perfiles integrada en Source Gateway: GET /v1/me, PATCH /v1/me, migración PostgreSQL y adaptador Flutter.
- PR #68: seguridad de Source Gateway y Rescue Link integrada mediante squash en b5ec47c4e4d1f8f7f3343f0b14fa47363a4f2a7f. Ambos servicios validan access tokens firmados, issuer, audiencia dedicada y typ=Bearer; Rescue Link usa roles de su propio resource server y PostgreSQL exige TLS fuera del desarrollo local explícito.
- PR #65: cerrada como sustituida por #68.
- Commit 2288290: corregida la compatibilidad del artefacto de GitHub Pages con deploy-pages@v5.0.1. La ejecución [43699356632](https://github.com/Baltas80/espana-outdoor/actions/runs/43699356632) terminó correctamente, incluido el despliegue de Pages. La URL pública no se pudo comprobar mediante una petición HTTP independiente desde este entorno.

## Cartografía y navegación offline

### Estado de main

- Mapbox es el motor cartográfico de Flutter.
- La página offline existente puede solicitar una región de prueba, pero el routing de main continúa usando Valhalla online.
- No presentar el routing de main como offline.
- Una región de Córdoba no demuestra cobertura nacional.

### PR #61 — Mapbox Navigation peatonal

La PR añade un TileStore persistente compartido por Maps y Navigation, descarga de style pack/teselas/recursos de routing peatonal para Córdoba, origen nativo de ruta online/offline, y conserva Valhalla para BTT, cicloturismo y map matching GPX online.

Versiones fijadas:
- Flutter Maps: mapbox_maps_flutter 3.34.1
- Maps Android: 11.35.0-ndk27
- Navigation Android: 3.35.0-ndk27
- Navigation Native: 324.35.0
- Common: 24.35.0-ndk27
- Android NDK: 28.2.13676358

### Corrección de configuración Mapbox y diagnóstico del último smoke

La ejecución Android staging [43713796013](https://github.com/Baltas80/espana-outdoor/actions/runs/43713796013) utilizó el APK release staging construido desde el commit `6a35844a670d51530661f77745aba22758dee871`. El artefacto `android-staging-apk` se generó con `validation_scope=runtime-capable-artifact`, application ID `com.espanaoutdoors.espana_outdoors.iconspreview`, versionCode 5 y SHA-256 `b3caa9a2534cd67d4da57aae8561ff24d96c19243cfdc26e8ebd01fe4c481398`. Los dos secretos Mapbox estaban disponibles.

La red del emulador quedó validada. La aplicación arrancó y emitió `MAPBOX_MAP_STYLE_LOADED`, pero no emitió `MAPBOX_MAP_LOADED`, `MAPBOX_MAP_FULL_FRAME` ni `MAPBOX_MAP_IDLE` dentro de 45 segundos. Logcat registró misses `NOT_FOUND` en cache/TileStore y solicitudes posteriores canceladas. La instrumentación anterior no imprimía la clase segura del mensaje de error, por lo que todavía no se podía distinguir una denegación HTTP de un problema de carga/renderizado.

La fase independiente de routing llegó a iniciarse, pero el runner recibió una señal de apagado durante esa fase. Esa ejecución no produjo evidencia nueva de ruta online/offline.

La corrección de configuración aplicada en la rama PR #61 mantiene un único TileStore persistente compartido por Maps y Navigation. Maps usa `TileStoreUsageMode.READ_ONLY`; Navigation conserva el mismo store mediante `RoutingTilesOptions`. La documentación oficial indica que READ_ONLY consulta primero los tile packs y permite fallback a solicitudes individuales online, mientras que READ_AND_UPDATE convierte las solicitudes en tile-pack requests y no es apropiado para un mapa de exploración libre.

En los commits posteriores al APK anterior se han incorporado:
- `tool/verify_mapbox_runtime_access.py`: preflight de estilo Outdoors, TileJSON y una tesela vectorial real de Córdoba; solo registra códigos HTTP y bytes, nunca URL/token.
- `tool/test_mapbox_runtime_access.py`: pruebas de éxito, token no público, HTTP 401 sin filtrar el token y respuesta de tesela vacía.
- `staging-android.yml`: ejecuta el preflight cuando el secreto runtime está disponible; Dependabot lo omite porque no recibe secretos.
- `mapbox_map_viewport.dart`: clasifica errores Mapbox por HTTP/autorización/TLS/DNS/red sin imprimir mensajes ni URLs.
- `mapbox_android_live_route_test.dart`: exige map-loaded, full frame, idle, ausencia de errores reales de recursos y el gate de píxeles.

Estos cambios están en el HEAD posterior al APK anterior y requieren una nueva ejecución. No se consideran validados hasta que terminen los workflows disparados por el nuevo HEAD.

Referencias oficiales:
- [Mapbox TileStoreUsageMode](https://docs.mapbox.com/android/maps/api/11.18.2/mapbox-maps-android/com.mapbox.maps/-tile-store-usage-mode/)
- [Mapbox offline concepts](https://docs.mapbox.com/android/maps/guides/offline/concepts/)

### Validación actual de PR #61

Ejecuciones del commit anterior `6a35844`:
- [Android staging 43713796013](https://github.com/Baltas80/espana-outdoor/actions/runs/43713796013): análisis/tests y APK release staging completados; el smoke falló al no recibir map-loaded/full-frame/idle. El routing independiente comenzó, pero el runner se apagó antes de producir evidencia.
- [CI 43713796035](https://github.com/Baltas80/espana-outdoor/actions/runs/43713796035): Flutter, iOS, Rescue Link y Source Gateway terminaron correctamente.
- [Security baseline 43713796155](https://github.com/Baltas80/espana-outdoor/actions/runs/43713796155): todos los trabajos terminaron correctamente.

Workflows disparados por el HEAD con preflight e instrumentación nuevos:
- [Android staging 43719251447](https://github.com/Baltas80/espana-outdoor/actions/runs/43719251447): pendiente en la última consulta.
- [CI 43719251310](https://github.com/Baltas80/espana-outdoor/actions/runs/43719251310): en ejecución.
- [Security baseline 43719251313](https://github.com/Baltas80/espana-outdoor/actions/runs/43719251313): en ejecución.

Evidencia histórica, no aceptación del HEAD actual:
- La ejecución 43667786016 obtuvo una ruta nueva con origen OFFLINE en modo avión (1.109,662 m; 66 puntos), pero la captura del mapa no acreditó renderizado completo.
- No existe todavía una ejecución que complete descarga, persistencia, ruta offline y mapa visual aceptado en el mismo HEAD.

### Puertas obligatorias antes de aceptar la PR #61

1. CI, Security baseline, análisis Dart, tests y APK staging correctos en el HEAD final.
2. Emulador con red validada: ruta online y descarga de Córdoba con style pack, teselas y recursos peatonales persistidos.
3. Cierre forzado/reinicio del proceso; activar modo avión y deshabilitar Wi-Fi.
4. Ruta nueva con origen nativo OFFLINE, no una respuesta cacheada de la ruta online.
5. Preflight HTTP del estilo, TileJSON y tesela vectorial correcto; mapa offline con style-loaded, map-loaded, full frame e idle, cero errores reales de recursos y captura que supere el gate de píxeles.
6. Inspeccionar y conservar PNG, Logcat redactado, manifiesto y hash del APK.
7. Instalar el APK candidato exacto en el OPPO físico y repetir la persistencia tras reinicio.

No fusionar hasta que CI, smoke visual y routing offline pasen en el HEAD final. La aceptación de producción sigue requiriendo prueba física.

### Alcance no cubierto

- Routing offline BTT/cicloturismo: [issue #62](https://github.com/Baltas80/espana-outdoor/issues/62).
- Cobertura cartográfica nacional.
- Validación física del APK candidato.
- Navegación turn-by-turn completa en todos los perfiles.

## Identidad y perfiles web/Android

### Backend integrado

La API de perfiles de Source Gateway está integrada:
- GET /v1/me crea/recupera el perfil asociado al subject OIDC verificado.
- PATCH /v1/me actualiza únicamente displayName.
- Email solo se importa cuando email_verified=true.
- El cliente no elige subject, UUID ni email; PostgreSQL genera el UUID canónico.

La seguridad backend de #68 está integrada, pero no hay evidencia de despliegue real con PostgreSQL TLS ni de login compartido con una cuenta real.

### PR #64 — cliente web

[PR #64](https://github.com/Baltas80/espana-outdoor/pull/64) continúa en draft. Incluye página /cuenta.html, Authorization Code + PKCE S256, callback, validación de state/discovery HTTPS y llamadas a /v1/me. Las pruebas específicas Web OIDC y Security baseline del HEAD conocido 87e2feb4 pasaron; el CI general también terminó correctamente en esa revisión.

Bloqueos externos:
- Registrar el cliente público web espana-outdoors-web y redirect URIs exactos.
- Mantener el cliente Android espana-outdoors-mobile.
- Configurar audience mappers separados para Source Gateway y Rescue Link, más roles del resource server.
- Desplegar Source Gateway y Rescue Link con PostgreSQL TLS, migraciones, issuer/audiencias/roles, credencial AEMET y expiración real.
- Probar con una misma cuenta web y Android que GET/PATCH /v1/me opera sobre el mismo perfil.

Seguimiento: [issue #55](https://github.com/Baltas80/espana-outdoor/issues/55).

## Dispositivo físico

Seguimiento: [issue #63](https://github.com/Baltas80/espana-outdoor/issues/63).

El procedimiento preparado verifica el hash/package/versionCode/commit del APK candidato, instala el artefacto exacto, ejecuta smoke, y permite repetir tras reinicio. La prueba de routing offline usa el test app de integración; debe mantenerse explícita la distinción entre ese test app y la UI release. No hay una nueva prueba física OPPO acreditada.

## Backend, routing y despliegue

- Source Gateway: código de perfiles y seguridad integrados; PostgreSQL/TLS y endpoint real no verificados.
- Rescue Link: código y seguridad integrados; base de datos y endpoint real no verificados.
- Valhalla: configuración y perfiles de cliente integrados; endpoint y rutas reales para senderismo/BTT/cicloturismo no verificados en producción.
- GitHub Pages: workflow de despliegue terminó correctamente en 43699356632; verificación HTTP externa del dominio pendiente.
- Keycloak: realm, clientes, audience mappers y redirects de producción pendientes de comprobación.
- Release Android: la firma está protegida por configuración; falta un release firmado con secretos reales y verificación de huella.

## Hoja de ruta priorizada

1. Completar Android staging/CI del HEAD 4cdc3335 e inspeccionar logs y capturas reales.
2. Corregir cualquier fallo del smoke online/offline; exigir también idle en la prueba offline.
3. Obtener ruta nueva OFFLINE y mapa visible después de descarga/cierre/avión.
4. Revisar la PR #61 y fusionarla solo cuando los controles de emulador y CI pasen.
5. Ejecutar issue #63 en OPPO con el APK exacto y persistencia tras reinicio.
6. Sincronizar y completar PR #64; configurar Keycloak y probar identidad compartida.
7. Desplegar PostgreSQL/Source Gateway/Rescue Link con TLS y verificar endpoints reales.
8. Verificar Valhalla para los perfiles de actividad.
9. Implementar routing offline BTT/cicloturismo y planificar cobertura regional/nacional.
10. Generar release firmado, instalarlo y realizar regresión final.

## Seguridad y criterio de cierre

No incluir secretos en código, commits, artefactos públicos ni logs. Los APK de staging no equivalen a un release firmado con la clave de producción. No declarar producción por una compilación, preview de Pages o una ruta aislada.

España Outdoor no se considera terminado hasta que Android compile, instale y funcione en dispositivo físico; mapas y routing offline se reproduzcan sin red y tras reinicio; web/Android compartan una cuenta real; servicios backend estén desplegados y protegidos; CI relevante esté verde; y documentación y procedimientos estén actualizados.
