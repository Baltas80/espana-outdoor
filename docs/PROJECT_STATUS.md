# España Outdoor — estado técnico

Última revisión: **15/11/2026 17:42 CET**.

- Rama de producción: main
- HEAD observado de main: 2288290b3fb233fe5e0d124f0b38008a31b0cd25
- PR Android offline: [#61](https://github.com/Baltas80/espana-outdoor/pull/61), abierta y lista para revisión.
- Rama PR #61: feat/mapbox-offline-routing-final-20261114
- HEAD de la rama PR #61 en esta revisión: `ccf6f217bacdbba83f527849b2f5a012a8ea993c`.
- Últimos cambios: `7cca9e1` mueve la captura offline a ADB host-side; `8421e58` separa misses CACHE/TILE_STORE; `10fe733` captura PNG antes de cerrar el test; `a3a653d` añade validador PNG sin dependencias; `0f1b795` incorpora self-test/artefacto; `d1a9f09` corrige el guard estático; `23126c1` valida scripts shell; `4405332` alinea MapWidget.pixelRatio con densidad nativa; `cb2d545` añade guard de paridad; `ccf6f21` exige la paridad en CI.
- La rama se sincronizó con main mediante el merge commit `cd17eb3016878ec24c16b2f5fbe29b450d7df48a`, que incorpora la corrección de GitHub Pages `2288290`; la comparación posterior quedó en 134 commits por delante y 0 por detrás.

## Actualización de validación — 15/11/2026 17:18 CET

### Evidencia real inspeccionada: Android staging 43729815996 (HEAD 6f8df39)

- APK runtime-capable generado; artefacto `android-staging-apk` ID `14168162393`.
- Application ID `com.espanaoutdoors.espana_outdoors.iconspreview`, versionCode 5.
- SHA-256: `2fb9b04a14553fe80650ca78e2e79142bc7d891760e8916a468919f8a4aa6c4d`.
- Ruta online nueva: 767,757 m y 55 puntos.
- Región Córdoba: 33/33 recursos, 0 errores, 42.847.606 bytes; TileStore confirmó la región.
- Con modo avión y Wi-Fi deshabilitado, Navigation calculó una ruta nueva `source=offline`: 1.109,662 m y 66 puntos.
- El test falló después por `MissingPluginException` en `convertFlutterSurfaceToImage`; la ruta offline ya había sido devuelta correctamente. El fallo es del canal de captura de integration_test.
- La captura de la fase smoke correspondía a la UI release online, no al mapa offline. El viewport era incompleto (entropía 0,886 bits, color dominante 0,876) y no recibió map-loaded/full-frame/idle. No existe captura offline válida de esa ejecución.
- Los eventos `NOT_FOUND` desde DATABASE/CACHE/TILE_STORE eran misses de consulta local; no prueban por sí solos un fallo HTTP ni de teselas.

### Cambios para la siguiente ejecución

- El integration test emite `MAPBOX_OFFLINE_SCREENSHOT_READY`; el host captura la plataforma nativa con `adb exec-out screencap -p` antes de que terminen las aserciones.
- El nuevo `tool/verify_android_map_screenshot.py` valida PNG sin librerías externas y conserva métricas de viewport.
- La instrumentación distingue lookup misses de errores reales.
- El workflow ejecuta el self-test del decodificador y adjunta el PNG al artefacto de routing.

### CI del HEAD 6469d1 y corrección posterior

- [Android staging 43735239658](https://github.com/Baltas80/espana-outdoor/actions/runs/43735239658): falló en `verify_mobile_native.py` antes de compilar. El validador estático seguía buscando `MAPBOX_OFFLINE_MAP_RENDERED` en el Dart test, aunque el marcador pasó al validador PNG host-side. El self-test del decodificador sí pasó.
- [CI 43735239624](https://github.com/Baltas80/espana-outdoor/actions/runs/43735239624): Source Gateway y Rescue Link pasaron; Flutter falló en la misma comprobación estática; iOS seguía en curso al inspeccionar.
- [Security baseline 43735239630](https://github.com/Baltas80/espana-outdoor/actions/runs/43735239630): 8/8 trabajos superados.

El commit `d1a9f09` actualiza el verificador para buscar el marcador y las métricas en `tool/verify_android_map_screenshot.py`, exige captura ADB en el harness y verifica que el PNG se conserve como artefacto. El gate se versiona como v3 y limita la dimensión/píxeles para evitar PNG descomprimidos excesivos.

Nuevas ejecuciones del HEAD `d1a9f09`:
- [Android staging 43735433990](https://github.com/Baltas80/espana-outdoor/actions/runs/43735433990): en ejecución.
- [CI 43735433995](https://github.com/Baltas80/espana-outdoor/actions/runs/43735433995): en ejecución.
- [Security baseline 43735434081](https://github.com/Baltas80/espana-outdoor/actions/runs/43735434081): en ejecución.

La corrección del harness todavía no está validada en runtime. La PR #61 sigue abierta; el mapa offline no está aceptado y no se ha probado el APK candidato en OPPO en este ciclo.

## Actualización de validación — 15/11/2026 17:42 CET

### Evidencia anterior inspeccionada: Android staging 43729815996 (HEAD 6f8df39)

- APK runtime-capable generado; artefacto ID `14168162393`, application ID `com.espanaoutdoors.espana_outdoors.iconspreview`, versionCode 5.
- SHA-256: `2fb9b04a14553fe80650ca78e2e79142bc7d891760e8916a468919f8a4aa6c4d`.
- Ruta online: 767,757 m / 55 puntos.
- Descarga Córdoba: 33/33 recursos, 0 errores, 42.847.606 bytes.
- Con modo avión y Wi-Fi deshabilitado, Navigation calculó una ruta nueva `source=offline`: 1.109,662 m / 66 puntos.
- El test falló después en `convertFlutterSurfaceToImage` por `MissingPluginException`; no se obtuvo PNG offline. La ruta nativa sí se había devuelto.
- La captura del smoke UI release era online y mostraba un viewport incompleto; no emitió map-loaded/full-frame/idle. Los misses DATABASE/CACHE/TILE_STORE eran búsquedas locales, no errores HTTP demostrados.

### Cambios del harness y de cartografía en el HEAD actual

- La prueba ya no invoca el canal screenshot no registrado. Emite `MAPBOX_OFFLINE_SCREENSHOT_READY`; el host captura con `adb exec-out screencap -p` mientras el test app sigue vivo.
- `tool/verify_android_map_screenshot.py` decodifica PNG sin dependencias externas, aplica el gate de color/entropía/opacidad y conserva la captura como artefacto incluso si fallan las aserciones.
- La instrumentación distingue `MAPBOX_RESOURCE_LOOKUP_MISS` de `MAPBOX_RESOURCE_FAILURE`.
- Hallazgo de paridad: el descriptor Android usa `resources.displayMetrics.density`, mientras que Mapbox Flutter documenta `MapOptions.pixelRatio` con valor predeterminado 1.0. `MapWidget` ahora pasa `MediaQuery.devicePixelRatioOf(context)` y el mismo modo de rasterización de glyphs usado por el style pack. Es una causa plausible de que TileStore descargue una variante y MapView solicite otra; queda pendiente demostrarlo en el nuevo render.
- El test estático exige esa paridad y el workflow valida los cuatro scripts Bash con `bash -n`.

### CI del HEAD ccf6f21

- [Android staging 43736481727](https://github.com/Baltas80/espana-outdoor/actions/runs/43736481727): preflight Mapbox, guard TileStore, validador PNG, sintaxis shell, análisis y tests Flutter superados; compilación APK en curso al cierre de esta revisión.
- [CI 43736481670](https://github.com/Baltas80/espana-outdoor/actions/runs/43736481670): Source Gateway y Rescue Link superados; suite Flutter completa superada; Android release build e iOS tests en curso.
- [Security baseline 43736481662](https://github.com/Baltas80/espana-outdoor/actions/runs/43736481662): 8/8 trabajos superados.

### Limitaciones de validación física y producción

- La auditoría de `tool/verify_install_android_apk.ps1` encontró que `-OfflineSmoke` no descarga Córdoba en el TileStore de la instalación release antes de activar modo avión, no exige map-loaded/FULL/idle y no compara el SHA-256 del `base.apk` instalado. El procedimiento físico está incompleto; issue #63 registra los cambios necesarios.
- La prueba de integración debug y el APK release tienen application IDs/almacenamiento separados; no se debe asumir que comparten la región descargada.
- El paso `Check staging endpoints` solo valida que las variables existan y usen HTTPS; no ejecuta health checks ni confirma que Valhalla, Source Gateway, Rescue Link o Keycloak respondan.
- La disponibilidad HTTP independiente de los dominios de producción no se ha podido verificar desde este entorno.
- La PR #61 sigue abierta. No se ha aceptado renderizado offline ni se ha probado el APK candidato en el OPPO.

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

Último HEAD de la rama: `7462e07aeba1b942ca5494e082db88e9d422a973`.

#### Ejecución 43721600584 — evidencia descargada e inspeccionada

[Android staging 43721600584](https://github.com/Baltas80/espana-outdoor/actions/runs/43721600584) terminó con fallo en el paso `Android map and routing validation`; no fue una señal de apagado del runner. El APK release staging sí se compiló y verificó:

- Artefacto más reciente inspeccionado: `android-staging-apk` (ID 14166905123).
- `validation_scope=runtime-capable-artifact`; ambos tokens Mapbox disponibles durante compilación.
- Application ID `com.espanaoutdoors.espana_outdoors.iconspreview`, versionCode 5.
- Commit fuente `9ef418802ff48e5d5af26f002e3392da55e1b660`.
- SHA-256 verificado sobre el APK descargado: `56e6ad734787d96953ad9f7ce55efa23a912f5cf216b273c2169aea079e188ca`.

El artefacto de routing (ID 14166726097) contiene la salida completa del integration test:
- Ruta online nueva: 767,757 m, 546,18 s y 55 puntos.
- Descarga de región Córdoba: el test recibió confirmación `MAPBOX_OFFLINE_REGION_READY`.
- Después de activar modo avión y relanzar el test app, TileStore confirmó la región y Navigation devolvió una ruta nueva `source=offline`: 1.109,662 m, 721,761 s y 66 puntos.
- La prueba de renderizado del mapa offline falló al recibir nueve errores `IN_OFFLINE_MODE/NETWORK/TILE/other`. Por tanto, el routing peatonal offline sí quedó demostrado en ese test app y esa ejecución, pero la cartografía visible offline no.
- El test falló antes de llegar a la captura; el artefacto de mapa no se generó. No existe PNG válido de ese intento.

La conclusión es más precisa que el diagnóstico anterior: el test descarga una región, la vuelve a consultar tras relanzar el test app y calcula una ruta offline nueva; sin embargo, el Maps SDK solicita teselas que no encuentra en los tile packs mientras la red está deshabilitada. No se ha demostrado que todos los recursos del descriptor de mapas se hayan descargado ni que coincidan con la variante solicitada por MapView.

#### Corrección añadida al HEAD 7462e07

- `MapboxNavigationBridge.kt` incluye el pixel ratio del dispositivo en `TilesetDescriptorOptions`, siguiendo el patrón de los ejemplos oficiales del SDK.
- El tile-region download declara `NetworkRestriction.NONE`, recoge completed/required/errored resource counts y no marca la región como lista si el SDK reporta errores o recursos incompletos.
- `mapbox_android_live_route_test.dart` imprime el progreso de descarga y difiere las aserciones de recursos hasta después de intentar guardar la captura y métricas. Así se conserva evidencia visual en un fallo.
- `tool/test_mapbox_tile_store_mode.py` protege el pixel ratio y la restricción de red mediante una prueba estática.

Estos cambios son una corrección fundamentada y una mejora de diagnóstico; todavía no están validados en runtime.

#### Workflows del nuevo HEAD 7462e07

- [Android staging 43729733156](https://github.com/Baltas80/espana-outdoor/actions/runs/43729733156): en cola al actualizar este documento.
- [Security baseline 43729733143](https://github.com/Baltas80/espana-outdoor/actions/runs/43729733143): en cola.
- [CI 43729733176](https://github.com/Baltas80/espana-outdoor/actions/runs/43729733176): en cola.

Evidencia histórica, no aceptación del HEAD actual:
- La ejecución 43667786016 obtuvo una ruta nueva con origen OFFLINE en modo avión (1.109,662 m; 66 puntos), pero la captura visual no acreditó renderizado completo.

No existe todavía una ejecución que complete descarga, persistencia, ruta offline y mapa visual aceptado en el mismo HEAD. La prueba anterior acredita routing peatonal offline en el integration test app, no en la UI release ni en el OPPO físico.

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

1. Completar Android staging/CI del HEAD `7462e07` e inspeccionar progreso de descarga, respuestas Mapbox, logs y captura offline.
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
