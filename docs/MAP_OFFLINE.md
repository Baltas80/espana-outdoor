# Cartografía y modo offline

## Motor cartográfico

Mapbox Maps SDK (`mapbox_maps_flutter`) es el motor elegido para la aplicación. El estilo principal es Mapbox Outdoors y requiere `MAPBOX_ACCESS_TOKEN` inyectado durante la compilación. No se debe mantener un catálogo cartográfico paralelo.

## Dos capacidades distintas

### Mapas y teselas offline

En `main`, la pantalla `OfflinePage` usa `OfflineManager` y `TileStore.createDefault()` para guardar el estilo y una región de prueba de Córdoba. Esta descarga permite validar almacenamiento cartográfico; por sí sola no demuestra que la aplicación sobreviva a una reapertura en frío, que el mapa se renderice en modo avión o que exista cobertura nacional.

La prueba anterior de Córdoba fue reportada como funcional sin conexión en un OPPO. Debe tratarse como evidencia histórica de una prueba de concepto, no como certificación del APK actual.

### Cálculo de rutas offline

En `main`, el proveedor de rutas utiliza `ValhallaRoutingService` con `VALHALLA_BASE_URL`; requiere conectividad. La disponibilidad de teselas offline no convierte ese servicio en un motor de rutas offline.

La integración nativa está en la [PR #61](https://github.com/Baltas80/espana-outdoor/pull/61). Comparte un `TileStore` persistente entre Maps SDK y Navigation SDK y descarga los recursos de routing peatonal junto con las teselas del mapa. El adaptador informa el origen devuelto por Mapbox (`online` / `offline`) y el routing compuesto conserva Valhalla para BTT, cicloturismo y map matching GPX. La versión Flutter `mapbox_maps_flutter 3.34.1` resuelve Maps Android 11.35.0; por eso Navigation se alinea con 3.35.0, Navigation Native 324.35.0 y Core Common 24.35.0 en la variante NDK27 (`com.mapbox.common:common-ndk27`). No añadir `com.mapbox.common:common:24.35.0` junto a los artefactos `-ndk27`: ambos incluyen `libc++_shared.so` y provocan un conflicto en `:app:mergeReleaseNativeLibs`. El APK anterior combinaba Navigation Native 324.34.1 con Common 24.35.0 y fallaba al inicializar por un símbolo nativo ausente. La corrección del símbolo JNI quedó validada en el código de la rama, pero la siguiente ejecución de Android staging detectó el conflicto de bibliotecas duplicadas `libc++_shared.so`. La rama ahora usa `common-ndk27`; la nueva compilación debe confirmar que el conflicto queda resuelto antes de integrar.

Las PR #25, #52, #53, #57 y #59 se cerraron como supersedidas. La PR #61 sigue pendiente de CI e integración; su código no forma parte de `main`. No debe mostrarse el cálculo offline como funcional hasta demostrar una solicitud nueva con origen nativo `OFFLINE` en modo avión.

La solicitud nativa de ruta tiene un timeout explícito de 45 segundos; el test puede reducirlo mediante el parámetro `routeTimeout` para probar que una respuesta nativa que no llega falla de forma acotada. Android staging limita el paso de integración del emulador a 30 minutos y el job completo a 60 minutos, evitando runners bloqueados indefinidamente.

La implementación propuesta no habilita routing offline de bicicleta, cobertura nacional ni navegación turn-by-turn completa.

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

Registrar por separado resultados de tests automatizados, emulador y dispositivo físico. La CI verde no sustituye esta prueba. El harness de emulador resuelve el package de la app de integración desde `namespace` de Gradle (distinto del application ID de staging), detiene ambos procesos antes de la fase offline, reutiliza las dependencias ya resueltas con `--no-pub` y limita cada fase a 8 minutos. El smoke de la pantalla de mapa espera `MAPBOX_MAP_STYLE_LOADED`, `MAPBOX_MAP_FULL_FRAME` y `MAPBOX_MAP_IDLE`; la existencia de una vista nativa o del logo de Mapbox no basta para declarar que las teselas se han renderizado. Los logs de emulador y de Flutter se filtran antes de adjuntarse como artefactos: cualquier cadena con forma de token `pk.` o `sk.` se sustituye por `<REDACTED>`; no se deben volver a publicar volcados de logcat sin este saneamiento.

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
