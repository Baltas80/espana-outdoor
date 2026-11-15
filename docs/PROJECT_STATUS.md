# España Outdoor — estado técnico

Última revisión: **15/11/2026 13:24 CET**.

- Rama de producción: main
- HEAD observado de main: 2288290b3fb233fe5e0d124f0b38008a31b0cd25
- PR Android offline: [#61](https://github.com/Baltas80/espana-outdoor/pull/61)
- Rama PR #61: feat/mapbox-offline-routing-final-20261114
- HEAD observado de PR #61: 4cdc3335a5bfc177aeb8fb0fb4aa5bab0c9fd5c1
- Comparación de PR #61: 121 commits por delante y 1 por detrás de main.

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

### Corrección de configuración Mapbox en el HEAD actual

El diagnóstico de Android staging [43709265025](https://github.com/Baltas80/espana-outdoor/actions/runs/43709265025) mostró que la red del emulador estaba validada, pero el mapa no llegaba a emitir MAPBOX_MAP_LOADED, MAPBOX_MAP_FULL_FRAME ni MAPBOX_MAP_IDLE. Logcat registró misses NOT_FOUND en TileStore; la fase de routing terminó interrumpida por apagado del runner y no produjo evidencia offline en esa ejecución.

La causa de configuración localizada fue TileStoreUsageMode.READ_AND_UPDATE aplicado globalmente al mapa de exploración. La documentación oficial de Mapbox especifica que este modo convierte las solicitudes en solicitudes de tile packs y no es recomendable para mapas de exploración libre. READ_ONLY consulta los packs descargados y, si una tesela no está en un pack, permite el fallback a la solicitud online de tesela individual.

En el HEAD 4cdc3335:
- Maps usa explícitamente TileStoreUsageMode.READ_ONLY.
- Navigation conserva el mismo TileStore mediante RoutingTilesOptions.
- tool/test_mapbox_tile_store_mode.py impide reintroducir el modo global READ_AND_UPDATE.
- tool/verify_mobile_native.py exige el modo correcto.
- Android staging ejecuta el guard antes de compilar.
- docs/MAP_OFFLINE.md documenta el motivo y enlaza la documentación oficial.

Referencias:
- [Mapbox TileStoreUsageMode](https://docs.mapbox.com/android/maps/api/11.18.2/mapbox-maps-android/com.mapbox.maps/-tile-store-usage-mode/)
- [Mapbox offline concepts](https://docs.mapbox.com/android/maps/guides/offline/concepts/)

### Validación actual de PR #61

Ejecuciones del HEAD 4cdc3335:
- [Android staging 43713534618](https://github.com/Baltas80/espana-outdoor/actions/runs/43713534618): en curso; el guard de red, el nuevo guard de TileStore, la verificación del proyecto Android, NDK, dependencias y lockfile ya pasaron. Análisis/tests Flutter siguen ejecutándose.
- [CI 43713534747](https://github.com/Baltas80/espana-outdoor/actions/runs/43713534747): Source Gateway y Rescue Link pasaron; Flutter e iOS siguen ejecutándose.
- [Security baseline 43713534650](https://github.com/Baltas80/espana-outdoor/actions/runs/43713534650): todos los trabajos observados terminaron correctamente.

Evidencia histórica, no aceptación del HEAD actual:
- La ejecución 43667786016 obtuvo una ruta nueva con origen OFFLINE en modo avión (1.109,662 m; 66 puntos), pero la captura del mapa no acreditó renderizado completo.
- Las ejecuciones posteriores no completaron la combinación de descarga, persistencia, ruta y mapa visual en el mismo HEAD.

### Puertas obligatorias antes de aceptar la PR #61

1. CI, Security baseline, análisis Dart, tests y APK staging correctos en el HEAD final.
2. Emulador con red validada: ruta online y descarga de Córdoba con style pack, teselas y recursos peatonales persistidos.
3. Cierre forzado/reinicio del proceso; activar modo avión y deshabilitar Wi-Fi.
4. Ruta nueva con origen nativo OFFLINE, no una respuesta cacheada de la ruta online.
5. Mapa offline con style, full frame, idle, cero errores de carga y captura que supere el gate de píxeles.
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
