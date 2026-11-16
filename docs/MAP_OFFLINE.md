# Cartografía y modo offline

## Motor cartográfico

Mapbox Maps SDK (`mapbox_maps_flutter`) es el motor elegido para la aplicación. El estilo principal es Mapbox Outdoors y requiere `MAPBOX_ACCESS_TOKEN` inyectado durante la compilación. No se debe mantener un catálogo cartográfico paralelo.

## Configuración compartida del TileStore

Android inicializa un único `TileStore` persistente y lo entrega tanto a
Navigation (`RoutingTilesOptions`) como a Maps (`MapboxMapsOptions.tileStore`).
Maps usa explícitamente `TileStoreUsageMode.READ_ONLY`: primero lee tile packs
descargados y, cuando el usuario se desplaza fuera de una región, permite la
solicitud online de teselas individuales.

No usar `READ_AND_UPDATE` como modo global del mapa de exploración. Ese modo
convierte las solicitudes en solicitudes de tile packs y está pensado para
viewports/recorridos predefinidos donde los packs ya están disponibles. En un
mapa de exploración libre puede impedir el fallback de teselas individuales
fuera de las regiones descargadas. La descarga offline explícita sigue usando
`OfflineManager.loadStylePack` y `TileStore.loadTileRegion`; `READ_ONLY`
permite leer esos recursos cuando no hay red.

Referencias oficiales:
- [TileStoreUsageMode](https://docs.mapbox.com/android/maps/api/11.18.2/mapbox-maps-android/com.mapbox.maps/-tile-store-usage-mode/)
- [Conceptos de mapas offline](https://docs.mapbox.com/android/maps/guides/offline/concepts/)

### Paridad del pixel ratio entre MapWidget y TileStore

El descriptor nativo de teselas usa `resources.displayMetrics.density`. El
`MapWidget` Flutter debe pedir la misma variante mediante
`mapOptions: MapOptions(pixelRatio: MediaQuery.devicePixelRatioOf(context))`.
En Mapbox Flutter 3.34.1, `MapOptions.pixelRatio` tiene valor predeterminado
1.0; dejarlo implícito puede hacer que el mapa solicite una variante distinta
de la descargada por el descriptor. El modo de rasterización de glyphs también
se fija explícitamente en `IDEOGRAPHS_RASTERIZED_LOCALLY`, con fallback
`sans-serif`, para mantener coherencia con el style pack.

Referencias:
- [MapOptions — Mapbox Maps Flutter](https://docs.mapbox.com/flutter/maps/api/latest/mapbox_maps_flutter/MapOptions-class.html)
- [MapWidget — Mapbox Maps Flutter](https://docs.mapbox.com/flutter/maps/api/latest/mapbox_maps_flutter/MapWidget-class.html)
- [GlyphsRasterizationOptions](https://docs.mapbox.com/flutter/maps/api/latest/mapbox_maps_flutter/GlyphsRasterizationOptions-class.html)

La paridad está protegida por `tool/test_mapbox_tile_store_mode.py` y
`tool/verify_mobile_native.py`; el renderizado debe seguir demostrarse con
callbacks nativos y captura offline, no solo con el guard estático.

## Dos capacidades distintas

### Mapas y teselas offline

En `main`, la pantalla `OfflinePage` usa `OfflineManager` y `TileStore.createDefault()` para guardar el estilo y una región de prueba de Córdoba. Esta descarga permite validar almacenamiento cartográfico; por sí sola no demuestra que la aplicación sobreviva a una reapertura en frío, que el mapa se renderice en modo avión o que exista cobertura nacional.

La prueba anterior de Córdoba fue reportada como funcional sin conexión en un OPPO. Debe tratarse como evidencia histórica de una prueba de concepto, no como certificación del APK actual.

The Maps tileset descriptor explicitly uses the Android display density
(`resources.displayMetrics.density`) so its tile variant matches the MapView
request. The tile-region download records completed/required/errored resource
counts and refuses to mark a region ready when the SDK reports failed or
incomplete resources. The CI integration test emits these counts and captures
the offline viewport before asserting resource failures, preserving useful
evidence on a failed render.


### Cálculo de rutas offline

En `main`, el proveedor de rutas utiliza `ValhallaRoutingService` con `VALHALLA_BASE_URL`; requiere conectividad. La disponibilidad de teselas offline no convierte ese servicio en un motor de rutas offline.

La integración nativa está en la [PR #61](https://github.com/Baltas80/espana-outdoor/pull/61). Comparte un `TileStore` persistente entre Maps SDK y Navigation SDK y descarga los recursos de routing peatonal junto con las teselas del mapa. El adaptador informa el origen devuelto por Mapbox (`online` / `offline`) y el routing compuesto conserva Valhalla para BTT, cicloturismo y map matching GPX. La versión Flutter `mapbox_maps_flutter 3.34.1` resuelve Maps Android 11.35.0; por eso Navigation se alinea con 3.35.0, Navigation Native 324.35.0 y Core Common 24.35.0 en la variante NDK27 (`com.mapbox.common:common-ndk27`). No añadir `com.mapbox.common:common:24.35.0` junto a los artefactos `-ndk27`: ambos incluyen `libc++_shared.so` y provocan un conflicto en `:app:mergeReleaseNativeLibs`. El APK anterior combinaba Navigation Native 324.34.1 con Common 24.35.0 y fallaba al inicializar por un símbolo nativo ausente. La corrección del símbolo JNI quedó validada en el código de la rama, pero la siguiente ejecución de Android staging detectó el conflicto de bibliotecas duplicadas `libc++_shared.so`. La rama ahora usa `common-ndk27`; la nueva compilación debe confirmar que el conflicto queda resuelto antes de integrar.

Las PR #25, #52, #53, #57 y #59 se cerraron como supersedidas. La PR #61 sigue pendiente de CI e integración; su código no forma parte de `main`. No debe mostrarse el cálculo offline como funcional hasta demostrar una solicitud nueva con origen nativo `OFFLINE` en modo avión.

La solicitud nativa de ruta tiene un timeout explícito de 45 segundos; el test puede reducirlo mediante el parámetro `routeTimeout` para probar que una respuesta nativa que no llega falla de forma acotada. Android staging limita el paso de integración del emulador a 30 minutos y el job completo a 60 minutos, evitando runners bloqueados indefinidamente.

La implementación propuesta no habilita routing offline de bicicleta, cobertura nacional ni navegación turn-by-turn completa.

## Preflight de credenciales y recursos Mapbox en CI

Antes de compilar y arrancar el emulador, Android staging ejecuta
`tool/verify_mapbox_runtime_access.py` cuando dispone del token público. El
preflight solicita el JSON del estilo Outdoors, el TileJSON del primer origen
vectorial y una tesela vectorial real centrada en Córdoba. Así distingue un
token que solo permite descargar dependencias Maven de otro que puede leer el
estilo y los datos cartográficos usados por la aplicación.

El resultado registra únicamente códigos HTTP, tamaño de la tesela y el
identificador del tileset. Nunca imprime la URL de petición, el cuerpo de
respuesta ni el token. Los tests `tool/test_mapbox_runtime_access.py` cubren
éxito, token no público, HTTP 401 sin filtrar credenciales y respuesta de tesela
vacía. Dependabot omite el preflight de runtime porque GitHub no entrega esos
secretos a sus workflows.

Este control comprueba permisos y disponibilidad HTTP desde el runner; no
sustituye el renderizado nativo, el test de TileStore ni la validación offline
en emulador/dispositivo físico.

## Preparación de red del emulador CI

Las fases online llaman a `tool/ensure_android_emulator_online.sh` antes
de descargar recursos o solicitar rutas. El preflight es exclusivo de
`ANDROID_EMULATOR_CI=true`: desactiva el modo avión, habilita Wi-Fi/datos y,
si la radio está activa pero no asociada, intenta conectar a las redes virtuales
conocidas `VirtWifi` y `AndroidWifi`. No considera conectada la red porque
`wifi_on=1`: exige que `cmd wifi status` indique conexión y que ConnectivityService
publique una red predeterminada validada con capacidades `INTERNET` y `VALIDATED`.
Si no aparece en 90 segundos, adjunta estado Wi-Fi, resultados de escaneo, rutas
IP y diagnóstico de ConnectivityService.

El workflow ejecuta el smoke visual y la integración online/offline en una
única instancia de emulador para evitar dos arranques en frío consecutivos.
El orquestador conserva ambos resultados: un fallo visual no omite la prueba
independiente de routing. El diálogo ANR del launcher puede ser clasificado por
el smoke UI y cerrado de forma acotada; un ANR de la aplicación bajo prueba sigue
siendo un fallo. La fase offline activa modo avión y deshabilita Wi-Fi. Ninguno
de estos scripts se ejecuta sobre el OPPO físico.

La prueba determinista `tool/test_android_emulator_network_guard.py` cubre el
modo no-CI, la asociación Wi-Fi virtual, el rechazo de una red no conectada y
el rechazo de una red predeterminada no validada.

## Reglas

- Mantener Mapbox como único motor de representación cartográfica.
- Conservar GPS, grabación de recorridos, GPX, routing Valhalla y funciones de seguridad independientemente del proveedor del mapa.
- Mantener los datos críticos de ruta disponibles offline y mostrar su antigüedad cuando corresponda.
- No usar servidores públicos de teselas OSM para descargas masivas.
- Mostrar progreso, errores, reintentos y estado de la descarga de Mapbox.
- No declarar cobertura nacional ni producción completa por haber descargado la región de Córdoba.
- No mostrar cálculo offline disponible hasta recibir y validar una respuesta de routing con origen nativo `OFFLINE`.

Android compila con NDK 28.2.13676358 para satisfacer los plugins Flutter nativos; los artefactos Mapbox usan el sufijo `-ndk27` para conservar la compatibilidad de páginas de 16 KB.

### Captura nativa de la prueba offline

El integration test no usa `convertFlutterSurfaceToImage()` ni
`takeScreenshot()`: en el runner actual de `flutter test` el canal
`plugins.flutter.io/integration_test` no está registrado y provocaba una
`MissingPluginException` después de que Navigation ya hubiera calculado una
ruta nueva con origen `OFFLINE`. El test emite
`MAPBOX_OFFLINE_SCREENSHOT_READY`; el script host captura la vista nativa con
`adb exec-out screencap -p` mientras el test app permanece abierto.

`tool/verify_android_map_screenshot.py` valida el PNG sin dependencias
externas, comprueba que no sea un viewport casi uniforme y emite
`MAPBOX_OFFLINE_MAP_RENDERED` solo cuando supera el gate de píxeles. La captura
se adjunta al artefacto de routing aunque fallen las aserciones de renderizado.

Los `NOT_FOUND` procedentes de `DATABASE` con origen `CACHE` o
`TILE_STORE` se clasifican como misses de búsqueda local, no como fallos de
recurso. Se mantienen separados de los errores reales de red/HTTP/offline.

## Protocolo de aceptación Android

La validación debe realizarse sobre el APK construido desde el commit exacto candidato a integrar:

1. Instalar el APK y abrir el mapa con conectividad.
2. Descargar el estilo y la región de prueba de Córdoba; esperar a que el SDK confirme la finalización.
3. Forzar el cierre de la aplicación y volver a abrirla para comprobar que la región sigue registrada.
4. Activar modo avión y confirmar que Wi-Fi, datos móviles y VPN no proporcionan conectividad.
5. Abrir el mapa, desplazarse y cambiar el zoom dentro de la región descargada; comprobar que las teselas se renderizan sin red.
6. Solicitar una ruta nueva. La prueba de navegación offline solo pasa si el SDK devuelve una ruta calculada con origen explícito `OFFLINE`; una ruta guardada localmente o una respuesta de Valhalla no cuentan.
7. Reiniciar el dispositivo y repetir la comprobación de persistencia, renderizado y routing offline.
8. Restablecer la conectividad y comprobar recuperación sin duplicar ni corromper la región.

Registrar por separado resultados de tests automatizados, emulador y dispositivo físico. La CI verde no sustituye esta prueba. El harness de emulador resuelve el package de la app de integración desde `namespace` de Gradle (distinto del application ID de staging), detiene ambos procesos antes de la fase offline, reutiliza las dependencias ya resueltas con `--no-pub` y limita cada fase a 8 minutos. El smoke de la pantalla de mapa y la integración offline exigen `MAPBOX_MAP_STYLE_LOADED`, `MAPBOX_MAP_LOADED`, `MAPBOX_MAP_FULL_FRAME` y `MAPBOX_MAP_IDLE`; la prueba offline también falla ante errores reales de recursos y ante una captura que no supere el gate de píxeles. Los errores Mapbox se clasifican por tipo (HTTP, autorización, TLS, DNS o red) sin imprimir mensajes ni URLs que puedan contener el token. La mera existencia de una vista nativa o del logo de Mapbox no basta para declarar que las teselas se han renderizado. Los logs de emulador y de Flutter se filtran antes de adjuntarse como artefactos: cualquier cadena con forma de token `pk.` o `sk.` se sustituye por `<REDACTED>`; no se deben volver a publicar volcados de logcat sin este saneamiento.

## Validación del APK exacto en OPPO

El workflow Android staging publica el APK y `android-staging-validation.txt` dentro del artefacto `android-staging-apk`. El manifiesto contiene SHA-256, application ID, versionCode, commit fuente y confirma que los dos tokens Mapbox estaban disponibles. No uses un APK sin `validation_scope=runtime-capable-artifact`.

1. Descarga ambos archivos del mismo run de Android staging.
2. Haz checkout del valor `source_commit` del manifiesto.
3. Define `MAPBOX_ACCESS_TOKEN`, `MAPBOX_DOWNLOADS_TOKEN`, `ANDROID_SERIAL` y `ANDROID_APPLICATION_ID` con los valores del dispositivo/artefacto.
4. Ejecuta `.	ool\test_mapbox_oppo_routes.ps1 -RebootAfterOffline`. Este script prepara dependencias con lockfile obligatorio, aplica el parche Mapbox y ejecuta la prueba de integración online/descarga y después offline. La ruta se ejecuta en el test app de integración (debug), no en el APK release.
5. Ejecuta `.	ool\verify_install_android_apk.ps1 -ReleaseApkPath .\app-release.apk -ValidationManifestPath .\android-staging-validation.txt -OfflineSmoke -RebootAfterInstall`. Verifica SHA-256, application ID, versionCode y commit; instala el APK exacto con `adb install -r` sin desinstalar ni borrar datos, abre Mapa sin conectividad y repite tras reiniciar. Guarda capturas e informe en `build\mapbox-oppo-validation`.
6. Si la actualización falla por incompatibilidad de firma, no desinstales la aplicación para forzarla: conserva los datos y registra el bloqueo.

**Alcance de la evidencia:** la prueba de routing nativo offline la ejecuta el integration test; el segundo script demuestra que el APK release exacto puede instalarse/reabrirse con el mismo TileStore y mostrar el mapa offline. El APK staging se firma con la configuración de staging; esto no sustituye la prueba del APK de producción firmado con la clave definitiva. No se afirma que el APK release calcule una ruta nueva desde su propia UI hasta que exista una prueba UI/instrumentation firmada con la misma clave.

## Estado y pendientes

- Mapa offline: descarga de una región de prueba presente en `main`; falta repetir la validación física sobre el HEAD actual.
- Navegación offline nativa: propuesta en PR #61, no integrada.
- Cobertura nacional: no acreditada.
- Reapertura en frío y tras reinicio: pendiente para el APK candidato.
- Las pantallas de planificación y detalle usan el viewport Mapbox compartido; la ruta Valhalla sigue dependiendo del endpoint online.


## Diagnóstico de arranque Android

La ejecución anterior de staging de la implementación en PR #53 instaló el APK y arrancó el emulador, pero no encontró el destino accesible `Mapa` después de la espera acotada. La jerarquía UI capturada estaba vacía y el artefacto no contenía logcat; por tanto, no hay evidencia suficiente para atribuir el bloqueo a una excepción concreta.

La PR #61 añade marcadores de arranque sin secretos, timeout para inicialización opcional de Mapbox Navigation y del servicio de descargas, y captura de logcat, screenshot y estado de Activity cuando falla el smoke. La siguiente ejecución debe aportar esa evidencia antes de concluir la causa. El timeout no equivale a validar routing offline.


En caso de fallo del smoke, el artefacto Android staging debe conservar `logcat`, `dumpsys activity`, captura de pantalla y jerarquía UI (`uiautomator dump`). La aceptación requiere que el log muestre `MAPBOX_OFFLINE_MAP_RENDERED` con una captura PNG decodificable, más de 24 colores cuantizados, más del 95 % de píxeles opacos, entropía superior a 1,2 bits y un color dominante inferior al 85 % de las muestras; además, la ruta de prueba debe devolver `OFFLINE`. Esto evita aceptar un canvas casi uniforme como mapa renderizado. La mera instalación del APK no cuenta como prueba de navegación offline.
## Mapbox resource expiry compatibility

The Mapbox Common SDK can represent an absent resource expiry with an int64 sentinel outside Dart's supported `DateTime` range. The current Mapbox Flutter platform-interface parser attempts to convert every non-null value and emits a `RangeError` for that sentinel during tile requests. The error is caught by the plugin event handler, but it floods logcat and prevents reliable resource-event diagnostics.

After `flutter pub get`, run:

```bash
python3 tool/patch_mapbox_resource_expiry.py
python3 tool/test_patch_mapbox_resource_expiry.py
```

All CI, Android staging, and release-candidate workflows apply the patch after dependency resolution. It is idempotent and fails closed if the upstream parser changes unexpectedly. It modifies only the resolved Pub cache copy; it does not alter the committed dependency source or lockfile. Remove this workaround when Mapbox ships a parser that maps out-of-range expiry sentinels to `null`.

## Prioridad y preservación de evidencia en CI (15/11/2026)

El orquestador `tool/staging_android_emulator_validation.sh` ejecuta primero
`staging_android_route_integration.sh`: ruta online, descarga de Córdoba,
desconexión real del emulador, nueva ruta peatonal offline y renderizado del
viewport offline con captura ADB. Después ejecuta el smoke online del APK
release. Ambas fases informan su resultado por separado; un fallo normal de
una fase no omite la otra.

Este orden prioriza la prueba que cubre descarga, TileStore y navegación offline.
El smoke del APK release sigue siendo independiente y no se considera sustituido
por la prueba de integración.

El workflow Android staging usa ahora `cancel-in-progress: false`: los nuevos
commits de la misma referencia esperan a que termine la ejecución activa, en
lugar de cancelar un emulador y perder sus artefactos de diagnóstico. Esta
política reduce cancelaciones por concurrencia, pero no evita fallos de
infraestructura del runner ni convierte una ejecución interrumpida en evidencia
válida.

La modificación está protegida por `tool/test_android_validation_order.py`.
No cambia los criterios de aceptación del mapa offline descritos arriba.


## Diagnóstico de fuentes Mapbox — 15/11/2026

La ejecución [43752643079](https://github.com/Baltas80/espana-outdoor/actions/runs/43752643079) aporta evidencia nueva:

- Ruta peatonal online: 767,757 m / 55 puntos.
- Descarga de Córdoba: 33/33 recursos, cero errores, 42.847.606 bytes.
- Ruta peatonal nueva en modo avión: origen nativo `offline`, 1.109,662 m / 66 puntos.
- El mapa offline no completó el renderizado: `style_loaded=true`, `map_loaded=false`, `full_frame=false`, `idle=false`; 14 fallos de recursos `IN_OFFLINE_MODE/NETWORK/TILE`.
- La captura del test offline no se aceptó porque el paquete bajo prueba ya no estaba en primer plano. El artefacto de smoke online sí contiene una captura de la pantalla real de Mapa: muestra el fondo del estilo y elementos de agua, pero faltan carreteras/etiquetas; por tanto, tampoco es una prueba de mapa completo.
- En el smoke online se recibieron respuestas de red para estilo, sprites, glyphs y teselas, pero solo dos frames parciales y ningún evento de mapa cargado/completo/inactivo. No se observaron `MAPBOX_RESOURCE_FAILURE` ni errores de carga de estilo en ese logcat.

Se añade instrumentación acotada de `sourceAdded` y `sourceDataLoaded` (ID de fuente, tipo, estado y presencia de tile; nunca URL ni token) tanto al viewport de producción como al integration test. La siguiente ejecución debe mostrar qué fuentes vectoriales notifican metadata/tiles y cuáles no llegan a cargar. No se cambia el modo TileStore ni se amplía la región a ciegas: primero se identifica si el problema es cobertura geométrica, descriptor/TileStore o carga de una fuente del estilo.


## Captura ADB: corrección de buffering de stdout — 15/11/2026

La revisión del run 43752643079 mostró que el host veía `MAPBOX_OFFLINE_SCREENSHOT_READY` cuando la actividad de integración ya había abandonado el primer plano. La tubería del test pasaba por `sed` antes de `tee`; GNU sed con salida redirigida puede retener el marcador en un búfer de bloque. Se reprodujo localmente con un proceso que imprimía el marcador y esperaba 5 segundos: con `sed -E`, el log seguía en 0 bytes tras 1 segundo; con `sed -u -E`, el log contenía los 32 bytes del marcador tras 1 segundo.

Se cambia la tubería del runner a `sed -u -E` para que el host capture el PNG mientras el integration app sigue en primer plano. El guard `tool/test_android_validation_order.py` exige que el modo no-buffered permanezca. Esta corrección resuelve el fallo de sincronización de la captura; **no** resuelve ni disimula los 14 fallos offline de teselas ni acredita el renderizado. La próxima ejecución debe producir una captura del paquete correcto y permitir distinguir visualmente el viewport aunque el test termine fallando.


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


## Diagnóstico Android reproducible — 15/11/2026

La ejecución [43763778048](https://github.com/Baltas80/espana-outdoor/actions/runs/43763778048), sobre el commit `4a443cff`, aporta esta evidencia:

- Ruta peatonal online: correcta (`767,757 m`, 55 puntos).
- Descarga separada: Maps 29 recursos / 32.892.088 bytes; Navigation 4 recursos / 9.955.518 bytes; cero errores comunicados por ambos descriptores.
- Ruta peatonal nueva con origen `OFFLINE`: correcta (`1.109,662 m`, 66 puntos).
- Renderizado offline: fallido. El estilo llegó a cargarse, pero se registraron 14 fallos `IN_OFFLINE_MODE/NETWORK/TILE`; no llegaron `map_loaded`, `full_frame` ni `idle`.
- La captura no se aceptó porque el host no detectó el marcador de Flutter en el filtro de Logcat. El marcador anterior se emitía desde Dart; ahora se envía mediante un método nativo limitado a builds debuggable.

Cambios de diagnóstico en el HEAD siguiente:

- Reaplicar y comprobar la instancia global de `MapboxMapsOptions.tileStore` después de inicializar Navigation y antes de crear `OfflineManager`, ya que Maps toma estas opciones durante la construcción de sus objetos.
- Registrar coordenadas z/x/y de las teselas solicitadas, sin registrar URLs ni tokens, para comparar el viewport con la cobertura del TileRegion.
- Capturar la señal desde el tag nativo `EspanaOfflineTest` y verificar la actividad de integración antes de guardar el PNG.

**Estado:** estas medidas mejoran la comprobación de identidad/configuración y la evidencia; no demuestran todavía que Maps esté leyendo los paquetes. La aceptación sigue exigiendo un PNG auténtico, carga completa del mapa y cero fallos de recursos en modo avión.


## Evidencia Android 16/11/2026 — run 43774889122

El HEAD probado fue `9b3b0fbe1e31942b39a3b9e68c3dbfdfca7e7692`. La CI general terminó 4/4 y Security baseline 8/8. Android staging compiló un APK runtime-capable; artefacto más reciente del run: [14188447528](https://github.com/Baltas80/espana-outdoor/actions/runs/43774889122/artifacts/14188447528), `source_commit=9b3b0fbe`, application ID `com.espanaoutdoors.espana_outdoors.iconspreview`, versionCode 5, SHA-256 verificado localmente contra el manifiesto: `7626c90c2a3aedee2c924dd52a5a560ef55ec289ebaef1832fd48529e2f922c9`.

La prueba del emulador confirmó por separado:

- Ruta online nueva: 767,757 m / 55 puntos.
- Región Maps: 29 recursos, 32.892.088 bytes, cero errores.
- Región Navigation walking: 4 recursos, 9.955.518 bytes, cero errores.
- Ruta nueva tras modo avión y Wi-Fi desactivado: origen nativo `offline`, 1.109,662 m / 66 puntos.

El mapa sigue sin renderizar offline: `style_loaded=true`, `map_loaded=false`, `full_frame=false`, `idle=false`, 14 errores `IN_OFFLINE_MODE/NETWORK/TILE`. Los eventos `sourceDataLoaded` muestran la fuente `composite` y solicitudes de tiles z13 en la zona descargada, pero la mayoría no se recuperan del TileStore. No se acepta la cartografía.

Se identificó además un defecto del harness de captura: Android `dumpsys` informa el componente como `applicationId/namespace.MainActivity`, pero el runner comparaba `namespace/` como si fuera el applicationId. El registro real era `com.espanaoutdoors.espana_outdoors.iconspreview/com.example.espana_outdoors.MainActivity`. El matcher ahora compara ambos segmentos exactamente. También se captura y sanea logcat desde el trap EXIT antes de restaurar la conectividad, para conservarlo aunque la aserción offline falle.

Commits de corrección del harness: `71e89b8`, `5c8579d`, `8cbeb25`, `9ab86a3`. La nueva versión aún necesita una ejecución Android para demostrar que el PNG del viewport de integración se captura y para conservar logcat de los fallos TileStore. El PNG del smoke release de este run muestra la app real, pero solo fondo/agua sin cartografía viaria suficiente; no es evidencia de mapa completo.

La ruta peatonal offline está demostrada en emulador; el renderizado offline no. Persistencia tras reinicio y OPPO físico siguen pendientes. No fusionar #61.


## Orden de inicialización Mapbox — 16/11/2026

La revisión de la API oficial de Mapbox confirma que `MapboxMapsOptions` se aplica durante la construcción de los objetos Maps y que los cambios posteriores no afectan a instancias ya creadas. Para eliminar cualquier ambigüedad con objetos Maps que pudiera inicializar Navigation, el puente Android configura ahora el TileStore compartido y `READ_ONLY` antes de `MapboxNavigationProvider.create`, y vuelve a aplicarlos/verificarlos después antes de construir `OfflineManager`. La configuración de la app se realiza antes de `runApp`, y la prueba de integración configura el puente antes de montar `MapWidget`.

La nueva guarda `tool/test_mapbox_tile_store_mode.py` exige el orden: asignación inicial del TileStore < Navigation bootstrap < reaplicación < OfflineManager. Esto es una corrección de orden documentada, no una causa raíz demostrada todavía. La siguiente ejecución debe comprobar si disminuyen los misses `DATABASE/TILE_STORE` y desaparecen los errores `IN_OFFLINE_MODE/NETWORK/TILE`.

Commits: `037b71a` (configuración nativa) y `94c6ce3` (guarda de orden). Las 12 comprobaciones estáticas cruzadas sobre los archivos actuales de la rama pasan en el entorno de revisión; no sustituyen la CI ni la ejecución Android.


## Verificación del descriptor de Maps en el TileStore compartido — 16/11/2026

La siguiente prueba no se limita a comprobar que existe un ID de TileRegion y que sus contadores son mayores que cero. Después de descargar la región, consulta `tileRegionContainsDescriptors` desde el TileStore expuesto por `MapboxMapsOptions`, reconstruyendo el descriptor con el mismo estilo, zoom y pixel ratio persistidos durante la descarga. También compara por identidad el TileStore global de Maps con el que usa Navigation y verifica que el modo sigue en `READ_ONLY`.

El test registra `MAPBOX_TILESTORE_VERIFICATION` antes de desconectar y después de reabrir la app. Si el descriptor no está presente en el TileStore que Maps recibe, la prueba falla antes de atribuir el problema a las teselas del viewport. El pixel ratio nativo del descriptor se compara con el del `MapWidget` de Flutter con tolerancia de 0,01.

Este diagnóstico separa cuatro condiciones: región persistida, descriptor incluido en la región, identidad del TileStore compartido y configuración de uso. No sustituye el renderizado: siguen siendo obligatorios `MAPBOX_MAP_LOADED`, `FULL_FRAME`, `IDLE`, cero fallos de recursos y una captura PNG válida en modo avión.

## Cobertura geométrica del viewport offline — run 43799514133

La ejecución del emulador sobre HEAD `470a194` aportó una señal nueva: Maps y Navigation compartían la misma instancia persistente, el descriptor Maps estaba presente en ese TileStore y ambos TileRegions existían. Sin embargo, Mapbox Maps solicitó tiles z13 `x=3986..3987`, `y=3162..3164`; 14 solicitudes fallaron con `NOT_FOUND/TILE_STORE` y el mapa no completó `FULL_FRAME` ni `IDLE`.

La geometría del fixture anterior tenía latitud `37.85..37.93`. La fila Web Mercator z13/y3164 ocupa aproximadamente `37.8228..37.8575`; el polígono solo cubría una franja de esa fila. Por tanto, la región de prueba no garantizaba cubrir por completo el tile que el viewport realmente solicitaba. Esto es un defecto geométrico reproducible del fixture y una hipótesis concreta para parte de los misses; todavía no demuestra que sea la única causa.

La región del test y la región que descarga `OfflinePage` en producción se amplían a latitud `37.78..37.97`, manteniendo la longitud `-4.84..-4.72`. El guard compara ambos polígonos y falla si divergen. Se añaden dos controles:

- El guard `tool/test_mapbox_offline_region_coverage.py` calcula los límites Web Mercator y exige que el polígono cubra por completo los seis tiles z13 observados en el viewport anterior.
- La integración registra únicamente coordenadas z/x/y extraídas de `SourceDataLoadedEventData` y de la ruta de URL de recurso. Nunca registra URLs, query strings ni tokens. Comprueba además que cada tile z13 observado queda completamente dentro del polígono descargado.

La nueva prueba debe confirmar si desaparecen los misses de TileStore tras ampliar la geometría. Si persisten en tiles totalmente cubiertos, el siguiente diagnóstico será comparar las coordenadas de los recursos fallidos y la resolución real del descriptor/tileset, no ampliar la región a ciegas.

**Estado:** corrección geométrica del fixture incorporada; pendiente de ejecución Android sobre el nuevo HEAD. No se acepta todavía el mapa offline. Siguen siendo obligatorios cero fallos de recursos, `MAP_LOADED`, `FULL_FRAME`, `IDLE`, PNG válido, reapertura/reinicio y prueba física OPPO.


## Experimento controlado de TileStoreUsageMode — 16/11/2026

La evidencia del run 43804464921 muestra que el descriptor y las dos regiones existen, pero el MapWidget en `READ_ONLY` solicita tiles individuales que terminan en `IN_OFFLINE_MODE/NETWORK/TILE`. La documentación oficial de Mapbox distingue:

- `READ_ONLY`: consulta tile packs ya cargados y, si falta un tile, recurre a una solicitud individual.
- `READ_AND_UPDATE`: convierte las solicitudes de mapa en solicitudes de tile packs; no usa solicitudes individuales.

Se añade un experimento aislado: la fase online/descarga sigue usando `READ_ONLY`; tras force-stop, la fase sin conectividad configura `READ_AND_UPDATE` antes de crear el MapWidget. El valor por defecto de producción sigue siendo `READ_ONLY`; no se cambia hasta demostrar que el experimento resuelve el renderizado y evaluar el comportamiento al desplazar el mapa fuera de una región descargada. La prueba registra el modo efectivo desde el puente nativo y mantiene los mismos criterios de aceptación: `MAP_LOADED`, `FULL_FRAME`, `IDLE`, cero fallos de recursos y PNG válido.
