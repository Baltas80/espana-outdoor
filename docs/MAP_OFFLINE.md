## Standard + Hybrid Composition — 17/11/2026, run 44084139266

Run [44084139266](https://github.com/Baltas80/espana-outdoor/actions/runs/44084139266), source commit `e03aafcc1d1b271c961cc9493c8076e823675c79`. El APK principal compiló, se instaló y llegó a la pantalla Mapa con `mapbox://styles/mapbox/standard`, Impeller, Hybrid Composition + SurfaceView y TileStore `READ_ONLY`. El smoke falló únicamente en el gate visual.

- Estilo: `STYLE_LOADED=1`, 190 capas y 10 fuentes.
- Render: `MAP_LOADED=0`, `MAP_IDLE=0`, `RenderMode.FULL=0`, un `RenderMode.PARTIAL`, `MAP_LOAD_ERROR=0`.
- Recursos: 6 solicitudes `RequestType.TILE`, todas con miss de TileStore; 82 eventos `MODEL`, incluidos 50 recursos obtenidos de red y 32 misses de caché. La captura 1080×2400 fue rechazada (entropía 0,649 bits; color dominante 0,901).
- EGL emulado registró tiempos de frame anómalos, con una muestra de 63,8 s. Esto hace plausible una limitación del renderizador software del emulador, pero no demuestra que sea la causa.
- Artefactos: [APK y manifiesto 14328803228](https://github.com/Baltas80/espana-outdoor/actions/runs/44084139266/artifacts/14328803228), [captura y logcat 14329217699](https://github.com/Baltas80/espana-outdoor/actions/runs/44084139266/artifacts/14329217699).

La ausencia de teselas en TileStore no demuestra por sí sola un bloqueo de red: Mapbox documenta que `READ_ONLY` consulta los tile packs y, si falta una tesela, puede solicitarla individualmente y guardarla en disk cache ([conceptos de offline](https://docs.mapbox.com/android/maps/guides/offline/concepts/), [API TileStoreUsageMode](https://docs.mapbox.com/android/maps/api/11.8.1/mapbox-maps-android/com.mapbox.maps/-tile-store-usage-mode/)).

### Siguiente experimento: Virtual Display + TextureView

La matriz anterior solo probó Hybrid Composition + SurfaceView. La API Flutter de Mapbox admite también `textureView: true` con `AndroidPlatformViewHostingMode.VD` ([MapWidget](https://docs.mapbox.com/flutter/maps/api/latest/mapbox_maps_flutter/MapWidget-class.html), [AndroidPlatformViewHostingMode](https://docs.mapbox.com/flutter/maps/api/latest/mapbox_maps_flutter/AndroidPlatformViewHostingMode.html)). La PR #79 añade una variante staging `virtual-texture`; para su ejecución automática usa Standard + Virtual Display/TextureView, mientras el valor de producción sigue siendo Hybrid Composition + SurfaceView. Se exige que el manifiesto y el log runtime confirmen el mismo modo. No se acepta offline ni se cambia producción con este experimento.

# Cartografía y modo offline

## A/B Android aislado — 17/11/2026, run 44075481486

Run [44075481486](https://github.com/Baltas80/espana-outdoor/actions/runs/44075481486), source commit `b4b803e545ae008004d84da899091d224e21f720`, workflow merge commit `596dcc3af18173b414fd2dc95a96c7802d333b54`.

Se construyeron, verificaron por manifiesto/SHA-256, instalaron y ejecutaron los tres APK en el mismo emulador API 35. Los tres llegaron a la pantalla Mapa y confirmaron el modo de ejecución en runtime:

| Variante | SHA-256 del APK | Renderer runtime | TileStore runtime |
|---|---|---|---|
| Principal | `0c98f86775cd9af2f7a7a59e82787a3036ebc81a611809f4a4bffca739fda85c` | Impeller | `READ_ONLY` |
| Skia | `ec4ca35d6f962fba9813d95b8c938023847b091bdce6b6efc98667bcd72f08e6` | Skia | `READ_ONLY` |
| TileStore desactivado | `dd5174e9aef8846bb6723d6afa4ecf902f50d961aab928ffb21664af5fc5f913` | Impeller | `DISABLED` |

Los tres comparten Application ID `com.espanaoutdoors.espana_outdoors.iconspreview`, versionCode 5, Flutter 3.47.5, estilo Outdoors v12 y Snapshotter desactivado. Los artefactos APK/manifiesto son [primary 14326296755](https://github.com/Baltas80/espana-outdoor/actions/runs/44075481486/artifacts/14326296755), [Skia 14325633482](https://github.com/Baltas80/espana-outdoor/actions/runs/44075481486/artifacts/14325633482) y [TileStore-disabled 14324749796](https://github.com/Baltas80/espana-outdoor/actions/runs/44075481486/artifacts/14324749796). Las capturas y logcat están en [14327080907](https://github.com/Baltas80/espana-outdoor/actions/runs/44075481486/artifacts/14327080907).

Resultados comunes:
- `STYLE_LOADED=1`, 148 capas, una fuente compuesta y fondo declarado `hsl(60, 20%, 85%)`.
- `MAP_LOADED=0`, `MAP_IDLE=0`, `RenderMode.FULL=0`, `RenderMode.PARTIAL=1`, `MAP_LOAD_ERROR=0`.
- La fuente `composite` confirmó 3 teselas con `loaded=true` en cada variante; las restantes registraron `loaded=false` (53 Impeller, 85 Skia y 65 TileStore-disabled). Hubo 7 respuestas de red de teselas no vacías y sin error explícito por variante.
- Las tres capturas siguen mostrando el viewport casi negro. En el recorte central, primary y TileStore-disabled son idénticos; Skia solo difiere en 2.372 de 1.598.400 píxeles (diferencias de rasterización menores), sin mejora cartográfica utilizable.
- El job Android terminó fallando únicamente en el gate obligatorio `Require Android map native smoke`; los tres APK se construyeron, verificaron e instalaron. CI general [44075481399](https://github.com/Baltas80/espana-outdoor/actions/runs/44075481399) y Security [44075481432](https://github.com/Baltas80/espana-outdoor/actions/runs/44075481432) finalizaron correctamente; Security completó 8/8 controles.

**Conclusión:** el cambio de Impeller a Skia y el bypass de TileStore no resuelven el viewport Outdoors en SwiftShader. La matriz sí es válida: los manifiestos y los eventos runtime confirman las tres configuraciones. No se debe seguir presentando TileStore como causa principal ni aceptar el mapa por el hecho de que el estilo cargue.

**Siguiente experimento de staging:** en PR #79, el evento pull_request seleccionará automáticamente Mapbox Standard para el APK principal (un único experimento Impeller/TileStore predeterminado). Los builds Skia y TileStore-disabled se omiten en ese modo porque ya se compararon con Outdoors. El selector manual workflow_dispatch conserva Outdoors como predeterminado y permite Standard explícitamente. El valor predeterminado del código de producción sigue siendo Outdoors v12. Si Standard también queda en PARTIAL, detener nuevas variaciones del emulador y priorizar la validación del APK exacto en el OPPO físico.

## Resultado Android A/B — 17/11/2026, run 44055960774

El run [44055960774](https://github.com/Baltas80/espana-outdoor/actions/runs/44055960774) construyó, verificó e instaló los tres APK (Impeller/TileStore predeterminado, Skia/TileStore predeterminado y TileStore desactivado). Los tres llegaron a la pantalla cartográfica, pero ninguno alcanzó `MAP_LOADED`, `MAP_IDLE` ni `RenderMode.FULL`; todos quedaron en `RenderMode.PARTIAL` y el gate visual rechazó las capturas.

Hallazgos de los logcat y PNG publicados en el artefacto [14316659955](https://github.com/Baltas80/espana-outdoor/actions/runs/44055960774/artifacts/14316659955):
- El estilo Outdoors recibió respuestas de red sin error para style, sprites, teselas, glyphs y metadatos de `mapbox.mapbox-streets-v8` (TileJSON: 19.079 bytes).
- TileStore desactivado siguió descargando style/sprites/teselas/glyphs por red; no mejoró el viewport. La zona del mapa en las capturas Skia y TileStore-disabled es pixel-idéntica.
- Snapshotter baseline generó el PNG uniforme `#d9e6c7`; Snapshotter vectorial llegó a `vector_capture_started` y terminó en timeout de 60 s, sin PNG.
- El cambio de TileStore no explica por sí solo el mapa negro. La evidencia tampoco identifica todavía si el bloqueo está en la decodificación vectorial, el renderer nativo o el emulador SwiftShader.

**Corrección de metodología:** el Snapshotter se lanzaba automáticamente desde `STYLE_LOADED` mientras el MapWidget seguía renderizando. Esa carga diagnóstica concurrente podía contaminar la comparación del propio MapWidget. El siguiente A/B desactiva Snapshotter en los tres APK y lo registra en sus manifiestos; la captura Snapshotter queda como opt-in separado. Esto no es una corrección del mapa ni una aceptación: es un experimento para aislar el viewport.

Puerta siguiente: repetir Impeller/Skia/TileStore con Snapshotter desactivado y comparar los eventos/capturas. Si persiste `PARTIAL`, la siguiente validación debe ser el APK exacto en dispositivo físico, porque el emulador de CI utiliza renderizado software.

## Estado de validación — 17/11/2026 10:24 CET

El último intento Android [44047628989](https://github.com/Baltas80/espana-outdoor/actions/runs/44047628989) no ejecutó el smoke: tras compilar/publicar los APK, el runner rechazó el manifiesto principal porque el artefacto de ese commit antiguo (`4e7dc9c`) no declaraba `mapbox_tile_store_usage_mode=default`. El HEAD actual de PR #79 incorpora ese campo en el manifiesto y en el dart-define del APK principal.

Se corrigió además el pipeline:
- Eliminado un segundo paso duplicado de compilación Skia que reutilizaba el ID `build_skia_apk`.
- Una sola compilación Skia conserva ahora explícitamente el TileStore predeterminado.
- La matriz Impeller/Skia/TileStore-disabled tiene 65 minutos para el smoke y 105 minutos para el job completo; los límites internos por variante siguen acotados.
- Tests estáticos exigen IDs únicos y coherencia de manifiestos.

Ejecuciones sobre el HEAD `e9802648`: [Security 44055799482](https://github.com/Baltas80/espana-outdoor/actions/runs/44055799482), [CI 44055799401](https://github.com/Baltas80/espana-outdoor/actions/runs/44055799401), [Android staging 44055799615](https://github.com/Baltas80/espana-outdoor/actions/runs/44055799615). Aún no hay nueva evidencia de mapa en esta revisión.

**No aceptar mapa online/offline por estos cambios de CI.** El APK TileStore-disabled es una variante de diagnóstico online, no un candidato offline. La aceptación sigue exigiendo descarga, persistencia, modo avión, reapertura, reinicio y validación física del APK exacto.

## Motor cartográfico

Mapbox Maps SDK (`mapbox_maps_flutter`) es el motor elegido para la aplicación. El estilo principal es Mapbox Outdoors y requiere `MAPBOX_ACCESS_TOKEN` inyectado durante la compilación. No se debe mantener un catálogo cartográfico paralelo.

## Dos capacidades distintas

### Mapas y teselas offline

En `main`, la pantalla `OfflinePage` usa `OfflineManager` y `TileStore.createDefault()` para guardar el estilo y una región de prueba de Córdoba. Esta descarga permite validar almacenamiento cartográfico; por sí sola no demuestra que la aplicación sobreviva a una reapertura en frío, que el mapa se renderice en modo avión o que exista cobertura nacional.

La prueba anterior de Córdoba fue reportada como funcional sin conexión en un OPPO. Debe tratarse como evidencia histórica de una prueba de concepto, no como certificación del APK actual.

### Cálculo de rutas offline

En `main`, el proveedor de rutas utiliza `ValhallaRoutingService` con `VALHALLA_BASE_URL`; requiere conectividad. La disponibilidad de teselas offline no convierte ese servicio en un motor de rutas offline.

La integración nativa actual está en la [PR #61](https://github.com/Baltas80/espana-outdoor/pull/61), todavía abierta y en draft. Comparte un `TileStore` persistente entre Maps SDK y Navigation SDK, descarga recursos de routing peatonal y mantiene el origen de ruta informado por el SDK (`online` / `offline`). El routing compuesto conserva Valhalla para BTT, cicloturismo y map matching GPX.

La PR #61 está divergida respecto a `main` y no debe fusionarse hasta sincronizarla y repetir CI, staging y aceptación funcional sobre un único HEAD. La evidencia histórica de ruta peatonal offline en emulador no equivale a aceptar el mapa: el mismo run registró 43 eventos de tesela, solo 3 cargas y 14 fallos/misses. La implementación no habilita routing offline de bicicleta, cobertura nacional ni navegación turn-by-turn completa.

## Reglas

- Mantener Mapbox como único motor de representación cartográfica.
- Conservar GPS, grabación de recorridos, GPX, routing Valhalla y funciones de seguridad independientemente del proveedor del mapa.
- Mantener los datos críticos de ruta disponibles offline y mostrar su antigüedad cuando corresponda.
- No usar servidores públicos de teselas OSM para descargas masivas.
- Mostrar progreso, errores, reintentos y estado de la descarga de Mapbox.
- No declarar cobertura nacional ni producción completa por haber descargado la región de Córdoba.
- No mostrar cálculo offline disponible hasta recibir y validar una respuesta de routing con origen nativo `OFFLINE`.

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

Registrar por separado resultados de tests automatizados, emulador y dispositivo físico. La CI verde no sustituye esta prueba.

## Diagnóstico del renderizado Mapbox

El smoke Android [43909921940](https://github.com/Baltas80/espana-outdoor/actions/runs/43909921940) verificó conectividad validada y que la aplicación estaba en primer plano. El artefacto [14247954799](https://github.com/Baltas80/espana-outdoor/actions/runs/43909921940/artifacts/14247954799) contiene PNG, jerarquía UI y logcat.

Hallazgos del logcat:
- `STYLE_LOADED` se emitió a las 17:09:15.792; el source `composite` y sus metadatos se añadieron.
- Se registraron 118 eventos `SOURCE_DATA` para `composite`: 108 con `loaded=false`, 3 con `loaded=true` y 7 sin valor.
- `loaded=false` no equivale a un error HTTP ni significa por sí solo que una tesela haya fallado. El SDK define `loaded=true` como que todos los datos de la fuente necesarios para el viewport visible están cargados.
- El primer frame fue `RenderMode.PARTIAL`. En el intervalo capturado no aparecieron `MAP_LOADED`, `MAP_IDLE`, `RenderMode.FULL`, `MAP_LOAD_ERROR` ni `STYLE_IMAGE_MISSING`.
- No se encontró un error HTTP explícito en los logs nativos. La captura muestra el mapa casi negro, con algunos trazos cartográficos, y el gate visual la rechaza.

La primera instrumentación no registraba coordenadas z/x/y de `TileID` ni el resultado de las solicitudes de recursos. La [PR #79](https://github.com/Baltas80/espana-outdoor/pull/79) amplía ahora el diagnóstico:
- Cada evento de tesela incluye coordenadas `z/x/y`.
- Se registran hasta 100 resúmenes `RESOURCE` con tipo, host, origen de datos, origen de respuesta, tamaño, motivo de error y cancelación. No se registra la URL ni sus parámetros.
- El smoke espera hasta 60 segundos para obtener simultáneamente `MAP_LOADED`, `MAP_IDLE` y `RenderMode.FULL` antes de aceptar la captura.
- Si vence el plazo, conserva PNG, logcat y diagnóstico filtrado, pero falla explícitamente.

Esta instrumentación sigue siendo diagnóstica. No cambia el estilo `outdoors-v12` ni el TileStore y no acredita modo offline. La siguiente ejecución debe permitir distinguir entre fallos de red/servidor, recursos incompletos y problemas de renderizado.

### Evidencia de staging instrumentado — 16/11/2026

Ejecución [Android staging 43918396180](https://github.com/Baltas80/espana-outdoor/actions/runs/43918396180), source commit `35796d4599e00c9d88f8e25e23d9daa0b998ea22`, workflow merge commit `c1e1a50367aeb038e0ab53b7b7f073e7ef433855`.

- El APK runtime-capable se compiló, se verificó y se publicó. Application ID `com.espanaoutdoors.espana_outdoors.iconspreview`, versionCode 5, Flutter 3.47.5, 200.283.766 bytes.
- SHA-256 recalculado sobre el APK extraído: `dc2290d678e24932c1e80c2e56f00434f3055a852047bc16c3dd964811385a4e`; coincide con `android-staging-validation.txt`.
- CI general: success. Security baseline: success (8/8). Android staging: failure intencionado del gate cartográfico, no de compilación ni instalación.
- El preflight de conectividad validada pasó y la aplicación quedó en primer plano.
- Eventos Mapbox: `STYLE_LOADED=1`, `MAP_LOADED=0`, `MAP_IDLE=0`, `MAP_LOAD_ERROR=0`, `RENDER_FRAME=1` con `RenderMode.PARTIAL`.
- Se registraron 75 eventos `SOURCE_DATA`; 69 pertenecen a `composite`. De los 68 eventos de tesela `composite`, 65 indicaron `loaded=false` y 3 `loaded=true`.
- Se registraron 79 eventos `RESOURCE`. Para teselas hubo 12 misses no cancelados en `TILE_STORE`, 24 búsquedas/cancelaciones de fallback y 7 solicitudes de red con respuesta no vacía y sin error (cada respuesta aparece también en el nivel `RESOURCE_LOADER`). Los misses locales/cancelaciones no deben contabilizarse como errores HTTP.
- Estilo, sprite, glyphs y algunas teselas recibieron respuestas de red sin error. No se observó un `MAP_LOAD_ERROR` ni un fallo de autorización explícito. Esto descarta atribuir el resultado, con la evidencia disponible, a un simple 401/403, pero no demuestra que todos los datos de fuente se hayan decodificado o representado.
- La captura [android-map-smoke-43918396180](https://github.com/Baltas80/espana-outdoor/actions/runs/43918396180/artifacts/14253759170) tiene 1080×2400; el gate obtuvo 38 colores, entropía 0,650 bits y color dominante 0,901. Rechazada por entropía y color dominante. El viewport central es casi uniforme RGB 8/8/8, con trazos aislados.
- El smoke terminó con `MAPBOX_RENDER_NOT_READY deadline_seconds=60`: no aparecieron `MAP_LOADED`, `RenderMode.FULL` ni `MAP_IDLE`. El job conservó PNG, jerarquía, logcat y diagnóstico.

Interpretación: la carga del estilo y varias respuestas de recursos funcionan; la fuente vectorial no llega a confirmar el viewport completo. Los misses de TileStore son compatibles con un arranque online sin región previamente descargada y no explican por sí solos el fallo. Aún no se puede distinguir entre procesamiento/decodificación de teselas, comportamiento del estilo Outdoors, renderizador SwiftShader/Impeller del emulador o un problema del SDK. Se necesita una comparación A/B con Mapbox Standard y una ejecución en dispositivo físico antes de cambiar el estilo de producción.

### Experimento A/B de estilos (staging)

La PR #79 ejecuta una comparación A/B automática en Android staging:

- En el evento `pull_request` de la propia PR #79, si el estilo primario es Outdoors, el job compila un segundo APK con Mapbox Standard y ejecuta ambos APK en el mismo emulador.
- El resultado del estilo seleccionado por el workflow se guarda bajo `primary/`; el APK comparativo Standard y sus evidencias se guardan bajo `standard/`.
- El workflow `workflow_dispatch` también permite elegir `outdoors-v12` (predeterminado) o `standard` para ejecuciones manuales.

El workflow pasa el valor como `MAPBOX_STYLE_URI` al build Dart y lo registra en `android-staging-validation.txt`. La app emite `MAPBOX_DIAGNOSTIC event=STYLE_URI` para asociar cada captura al estilo exacto. CI compila el test de selección con el define Standard y comprueba que el valor se propaga.

Este control no cambia el estilo predeterminado de producción, no modifica los estilos de cuentas de Mapbox y no habilita Standard en una release. La comparación solo será válida si ambos APK se construyen desde el mismo commit y usan el mismo emulador/configuración. Los resultados deben revisarse junto con ambas capturas y los eventos de Mapbox; no basta con que los workflows compilen.

Artefactos:
- [APK y manifiesto](https://github.com/Baltas80/espana-outdoor/actions/runs/43918396180/artifacts/14255086327).
- [PNG, jerarquía y logs](https://github.com/Baltas80/espana-outdoor/actions/runs/43918396180/artifacts/14253759170).

## Estado y pendientes

- Estilo de producción: `mapbox://styles/mapbox/outdoors-v12`; no se ha cambiado por hipótesis.
- Mapa online: no aceptado; la captura de la PR #73 falla el gate visual.
- Mapa offline: no aceptado; falta acreditar renderizado real en modo avión.
- Routing peatonal offline: evidencia histórica positiva en emulador, pero no suficiente para certificar el mapa ni el APK actual.
- PR #61: abierta/draft, divergida de `main`; requiere sincronización y nueva ejecución del experimento de estilos/TileStore.
- PR #79: HEAD `aa8d7b5` (48 commits ahead, 0 behind). La evidencia runtime completada sigue siendo la del source commit `35796d4`, cuyo APK compiló/verificó pero falló correctamente el gate (sin `MAP_LOADED`, `FULL` ni `IDLE`). El workflow ahora compila un APK Standard comparativo solo para esta PR y ejecuta ambos estilos en el mismo emulador; el nuevo Android staging `43931402430` está pendiente. Security/CI sobre el HEAD final todavía no están certificados. Los fallos transitorios de los guards (condición de upload y marcador de resumen A/B) se corrigieron en commits posteriores; deben volver a pasar en la nueva ejecución.
- Reapertura en frío, reinicio físico y validación del APK exacto en OPPO: pendientes.
- Cobertura nacional y routing offline BTT/cicloturismo: no acreditados.
- Las pantallas de planificación y detalle usan el viewport Mapbox compartido; Valhalla sigue dependiendo del endpoint online.


### Regresión del experimento A/B — 16/11/2026

Ejecución [Android staging 43931517057](https://github.com/Baltas80/espana-outdoor/actions/runs/43931517057), source commit `2a4992ef11906dc169c0763937481ac1449efa92`:

- El APK Outdoors se compiló, verificó y publicó; el smoke se ejecutó en el emulador y volvió a fallar correctamente el gate visual (`MAP_LOADED=0`, `MAP_IDLE=0`, sin `RenderMode.FULL`; PNG rechazado por entropía y color dominante).
- El build comparativo Standard no llegó a ejecutarse: Flutter 3.47.5 rechazó explícitamente `flutter build apk --release --build-dir=build/standard` con `Could not find an option named "--build-dir"` (exit code 64).
- Debido a `continue-on-error: true`, el job conservó el APK primario y continuó, pero no existía un APK Standard; el paso final de requisito A/B falló. Por tanto, **no existe comparación A/B válida en este run**.
- Corrección preparada en la PR #79: copiar el APK/manifest Outdoors verificado fuera de `build/`, ejecutar `flutter clean` y `flutter pub get --enforce-lockfile`, construir Standard por la ruta Flutter predeterminada y copiar su APK/manifest a un directorio independiente. El emulador ejecutará ambos APK y el gate final verificará el SHA-256 del manifiesto Standard.
- Esta corrección resuelve el fallo del pipeline A/B, no el defecto de renderizado. El mapa Outdoors continúa sin aceptación; Standard todavía no se ha probado.

### Incidencia de orquestación A/B — 16/11/2026 21:17 CET

Ejecución [Android staging 43939379836](https://github.com/Baltas80/espana-outdoor/actions/runs/43939379836), source commit `3029c332a483a54df9547aab6faab7af67057750`:

- CI general [43939379797](https://github.com/Baltas80/espana-outdoor/actions/runs/43939379797): success.
- Security baseline [43939379759](https://github.com/Baltas80/espana-outdoor/actions/runs/43939379759): 8/8.
- Android staging: análisis/tests, APK Outdoors, verificación, APK Standard y publicación de artefactos pasaron. El job falló al iniciar el smoke del emulador.
- El artefacto [14263750648](https://github.com/Baltas80/espana-outdoor/actions/runs/43939379836/artifacts/14263750648) contiene ambos APK y manifiestos. SHA-256 recalculados desde los archivos descargados:
  - Outdoors: `ac25d20b2cf1a1eed3cd1d1bc143d68c14b7c9a185de3b6e9f7d00508c26b8f3`.
  - Standard: `fe0119624c81dcc47f3ed2c0e70dbe380328d2619e0788826f21c095cb48b1b2`.
  Ambos coinciden con sus manifiestos; source commit `3029c33`, workflow commit `3d3fbf4`, Flutter 3.47.5.
- Causa exacta del smoke fallido: el bloque multilínea `script: |` de `reactivecircus/android-emulator-runner` aparece en los logs ejecutando cada línea como una invocación independiente de `/usr/bin/sh -c`. Las asignaciones `primary_apk=...` y `standard_apk=...` no persistieron hasta la línea que invocó `smoke_android_map.sh`; el argumento llegó vacío y el script terminó con `APK path required`. El emulador había arrancado correctamente.
- Por tanto, los dos APK se compilaron, pero **ninguno de los dos estilos se ejecutó**. Este run no es una comparación A/B ni aporta evidencia cartográfica nueva.

Corrección aplicada en la PR #79:
- La acción del emulador invoca una sola línea: `bash tool/smoke_android_map_ab.sh "$RUNNER_TEMP" "$MAPBOX_STYLE_URI"`.
- Toda la gestión de variables, ejecución primaria/Standard, timeouts, directorios de evidencia y códigos de salida vive dentro del script Bash versionado.
- El runner ejecuta Standard incluso si falla el smoke primario, para conservar una comparación diagnóstica útil.
- Se añadió una prueba automatizada con un `timeout` simulado para cubrir éxito A/B, fallo primario sin omitir Standard y staging normal sin APK Standard.

La corrección elimina el fallo de orquestación; no resuelve el mapa negro. El gate cartográfico y la comparación A/B real siguen pendientes.

### Aislamiento de datos entre estilos A/B

El runner A/B verifica que ambos manifiestos comparten `application_id`, `source_commit` y `version_code`, y que el segundo APK declara exactamente `mapbox://styles/mapbox/standard`. Como ambos APK usan el mismo application ID, el runner fuerza la detención y ejecuta `pm clear` entre Outdoors y Standard, comprobando la respuesta `Success`. Así la caché TileStore y las preferencias del primer estilo no contaminan la comparación del segundo. El staging ordinario sin APK Standard no limpia datos.

### Conservación del APK primario si falla la compilación Standard

Se separaron los uploads: `android-staging-apk` contiene siempre el APK Outdoors ya verificado; `mapbox-standard-ab-apk` solo se publica si la compilación Standard terminó correctamente. Si Standard falla, el smoke primario todavía puede ejecutarse y conservar sus evidencias; el requisito final A/B hace fallar el job al cierre, sin perder el artefacto primario. Esto evita que `if-no-files-found: error` del upload combinado impida ejecutar el diagnóstico principal.

### Falso positivo del smoke A/B: ANR de Google SDK Setup — 16/11/2026

Ejecución [Android staging 43950050766](https://github.com/Baltas80/espana-outdoor/actions/runs/43950050766), HEAD `8b2215f5b307023f4a4d4980c96e779d55560fe9`:

- Los APK Outdoors y Standard se compilaron, verificaron y publicaron con manifiestos separados. El runner A/B llegó a ejecutar ambos; los dos smoke devolvieron código 1.
- El artefacto [14272151033](https://github.com/Baltas80/espana-outdoor/actions/runs/43950050766/artifacts/14272151033) contiene dos capturas prácticamente idénticas. Ambas muestran la pantalla de inicio de España Outdoor cubierta por el diálogo Android **“com.google.android.googlesdksetup isn't responding”**.
- La jerarquía `espana-window-post-map.xml` tiene como ventana superior el paquete `android`, no el paquete de España Outdoor. La app seguía apareciendo como actividad reanudada, pero el diálogo del sistema bloqueaba el toque sobre la navegación.
- El script había pulsado repetidamente “Wait” para ese paquete y después aceptaba la captura por diversidad/entropía. Las métricas del PNG (92 colores, entropía 3.150 bits, dominante 0.424) procedían de la pantalla de inicio y del diálogo, **no del mapa**.
- Los ficheros `espana-mapbox-diagnostics.txt` solo contienen el arranque de Impeller; no hay eventos `MAPBOX_DIAGNOSTIC`. Por tanto, en este run el widget Mapbox no llegó a montarse y no se puede extraer ninguna conclusión A/B sobre Outdoors frente a Standard ni sobre el renderizador cartográfico.

Corrección aplicada en esta PR:

- En el emulador CI desechable, detener y deshabilitar para el usuario 0 el paquete de primer arranque `com.google.android.googlesdksetup` si está instalado. Esta operación no se ejecuta en el dispositivo físico ni en producción.
- Si reaparece su diálogo ANR, cerrarlo explícitamente en lugar de seguir eligiendo “Wait”.
- Añadir `tool/verify_android_map_screen.py`: exige que la ventana superior pertenezca al paquete de la app y que la jerarquía contenga el marcador de accesibilidad `Mapa cartográfico`, expuesto explícitamente por el viewport Mapbox. Rechaza la pantalla de inicio y cualquier ventana de sistema.
- Ejecutar esta verificación después del toque y de nuevo justo antes de capturar el PNG. La entropía del screenshot ya no puede convertir la pantalla de inicio en una falsa prueba de mapa.
- Añadir un self-test con casos positivos de la página Mapa, pantalla de inicio y diálogo del sistema.

La ejecución 43950050766 **no es una comparación A/B válida** y no demuestra que ninguno de los dos estilos haya fallado al renderizar. La nueva ejecución debe confirmar primero que la página Mapa está realmente abierta; solo entonces se interpretarán los callbacks y el PNG.

## Diagnóstico A/B y paridad de pixel ratio — 17/11/2026

Ejecución Android staging [43969985170](https://github.com/Baltas80/espana-outdoor/actions/runs/43969985170), source commit `d49551168f747347581ba30d3b0ece1eb584fb06`. El artefacto [14279481897](https://github.com/Baltas80/espana-outdoor/actions/runs/43969985170/artifacts/14279481897) contiene capturas, jerarquías y logcat independientes para Outdoors y Standard.

Esta vez el verificador confirmó la página real `Mapa cartográfico` y que la ventana superior pertenece a España Outdoor. Por tanto, a diferencia de los intentos bloqueados por la pantalla Home/ANR, **ambos estilos sí llegaron a ejecutar el viewport Mapbox**.

Resultado observado en ambos:
- `STYLE_LOADED` presente.
- Solo `RenderMode.PARTIAL`; no aparece `MAP_LOADED`, `MAP_IDLE` ni `MAP_LOAD_ERROR`.
- Fuente `composite`: 3 eventos `loaded=true`; 92 `loaded=false`. No se completa el viewport.
- Siete respuestas de tesela únicas llegaron desde Network con tamaño no vacío y sin error. El listener refleja cada respuesta en las fases `NETWORK` y `RESOURCE_LOADER`; no deben contarse como 14 teselas distintas.
- Los `NOT_FOUND` de `TILE_STORE` son misses locales seguidos de fallback de red, no evidencia de HTTP 404 ni de rechazo del token.
- Las dos capturas 1080×2400 muestran el área cartográfica casi negra. Outdoors conserva algo de linework oscuro; Standard no ofrece una representación cartográfica utilizable. Ninguno supera el gate visual.

Esta comparación es válida como diagnóstico de los dos estilos en el mismo emulador/commit y con limpieza de datos entre APK, pero **no acepta ninguno**. Que ambos fallen de forma similar apunta a una variable compartida (configuración del MapView, renderer o carga de fuentes), no demuestra que el estilo Outdoors sea la causa.

### Hipótesis de configuración: pixel ratio distinto entre MapView y TileStore

La revisión cruzada de la rama de integración offline #61 encontró que el descriptor nativo de Mapbox se crea con `resources.displayMetrics.density`, mientras que el `MapWidget` de la rama principal no proporcionaba `MapOptions` y heredaba el valor predeterminado `pixelRatio=1.0`.

La API oficial de Flutter documenta ese valor predeterminado de `MapOptions.pixelRatio`; la guía Android de Mapbox construye los descriptors offline usando el pixel ratio de la pantalla. Referencias: [MapOptions](https://docs.mapbox.com/flutter/maps/api/latest/mapbox_maps_flutter/MapOptions-class.html), [gestión de datos offline](https://docs.mapbox.com/android/maps/guides/offline/manage-offline-data/).

Se ha portado a esta PR una configuración explícita:
- `MediaQuery.devicePixelRatioOf(context)` para el MapWidget.
- `MapOptions.pixelRatio` igual a esa densidad.
- `GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY` y fallback `sans-serif`, en paridad con el style pack nativo.
- Validación de valores finitos y positivos.
- Test Dart del helper y guard estático para impedir que el MapWidget deje de usarlo.

Esto corrige una discrepancia real entre la configuración de renderizado y la descarga offline, pero **todavía es una hipótesis respecto al mapa negro online**. Debe validarse con un nuevo APK del HEAD actualizado. El log debe incluir `MAPBOX_MAP_OPTIONS pixel_ratio=...`; la aceptación requiere `MAP_LOADED`, `RenderMode.FULL`, `MAP_IDLE` y PNG legible.

No cambiar el estilo predeterminado, no alterar TileStore ni fusionar PR #79 hasta completar esa validación.


## Paridad entre mapa online y TileStore (17/11/2026)

El viewport online y el descriptor de la región offline deben usar el mismo URI de estilo y el mismo pixel ratio del dispositivo:

- El URI compartido procede de `mapboxStyleUri` (`MAPBOX_STYLE_URI`, por defecto Outdoors v12).
- `MapWidget` recibe `MapOptions.pixelRatio = MediaQuery.devicePixelRatioOf(context)`.
- `TilesetDescriptorOptions.pixelRatio` recibe la misma densidad para los recursos raster del descriptor.
- Ambos usan `GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY` para mantener el tratamiento de glyphs del style pack.

El helper `cordobaOfflineTilesetDescriptorOptions` valida que el pixel ratio sea finito y positivo, conserva zoom 8–15 y permite probar la configuración sin iniciar una descarga.

Esta paridad corrige una diferencia de configuración detectada en la integración. No demuestra persistencia ni renderizado offline: la aceptación sigue requiriendo descarga real, confirmación de style pack y región en TileStore, modo avión, cierre forzado, reapertura y reinicio del dispositivo Android.


## Renderer A/B: evidencia real y diagnóstico de estilo — 17/11/2026

Ejecución [43995006900](https://github.com/Baltas80/espana-outdoor/actions/runs/43995006900), artefacto [14290666552](https://github.com/Baltas80/espana-outdoor/actions/runs/43995006900/artifacts/14290666552), source commit `e90ca71`.

Los dos APK llegaron a la pantalla real Mapa y cargaron `outdoors-v12`. El modo Hybrid Composition/SurfaceView mostró únicamente trazos oscuros sobre fondo negro; Virtual Display/TextureView dejó visible el fondo de la app, sin cartografía utilizable. Ambos smoke fallaron correctamente: no apareció `MAP_LOADED`, `MAP_IDLE` ni `RenderMode.FULL`.

La evidencia confirma:
- Hybrid (PID 3553): `STYLE_LOADED`, `RenderMode.PARTIAL`, 3 eventos de fuente `loaded=true`, 47 `loaded=false` y 7 `unknown`.
- Texture/VD (PID 4407): `STYLE_LOADED`, `RenderMode.PARTIAL`, 3 eventos `loaded=true`, 65 `loaded=false` y 7 `unknown`. El artefacto comparativo incluía también el PID 3553 del primer experimento; los recuentos anteriores se han separado por PID y no se han mezclado.
- Ambos manifiestos se han descargado y verificado de nuevo: mismo `application_id`, versionCode 5, commit fuente `e90ca718a78ce1253687232bd97519444ae525bc` y estilo Outdoors; solo cambia `mapbox_android_view_mode`. SHA-256 Hybrid: `9fb85b2c9f98799d31102303e0dfbcac2112497f61e18e9c819276937b0dfe52`. SHA-256 Texture/VD: `20f1dacd06c316f2912e2296a5116c6a4667ef42ded10ac650c8c3565b54d1bb`. Artefactos: [APK Hybrid](https://github.com/Baltas80/espana-outdoor/actions/runs/43995006900/artifacts/14290038306) y [APK Texture/VD](https://github.com/Baltas80/espana-outdoor/actions/runs/43995006900/artifacts/14289563594).
- Se recibieron teselas, sprites y glyphs desde Network con tamaños no vacíos y sin error explícito. Los misses de TileStore/Cache no equivalen a HTTP 404.
- La captura confirma que el viewport no es aceptable; el estilo y el hosting siguen sin quedar validados.

### Correcciones de observabilidad

Se ha añadido una inspección de estilo al evento `STYLE_LOADED` que registra, sin volcar URLs ni credenciales, el número de capas/fuentes, la capa de fondo y su `paint`, el tamaño del MapView, el centro/zoom y el resultado de `isStyleLoaded()`. El objetivo es distinguir un estilo cuyo fondo sea realmente oscuro de un problema de composición/renderizado.

Cada ejecución de `smoke_android_map.sh` limpia ahora logcat después de conectar con el emulador y antes de instalar el APK. Así el artefacto `texture-vd` deja de mezclar el proceso Hybrid anterior con el proceso comparativo.

La limpieza solo afecta al emulador efímero de CI; no se ejecuta en el OPPO ni en dispositivos de usuario.

La aceptación sigue bloqueada hasta obtener un PNG cartográfico legible, `MAP_LOADED`, `MAP_IDLE` y `RenderMode.FULL`, seguidos por las pruebas offline en Android.


## Diagnóstico Impeller frente a Skia — 17/11/2026

Ejecución [44003718478](https://github.com/Baltas80/espana-outdoor/actions/runs/44003718478), artefacto de diagnóstico [14294586740](https://github.com/Baltas80/espana-outdoor/actions/runs/44003718478/artifacts/14294586740), source commit `bfc618d`.

La captura y el logcat del APK Hybrid/SurfaceView confirman que el widget Mapbox sí llegó a montarse. El evento `MAPBOX_STYLE_INSPECTION` registró:

- `style_loaded=true`.
- 148 capas, 1 fuente y 1 capa de fondo.
- `background-color=hsl(60, 20%, 85%)` (color claro).
- MapView de aproximadamente 411 × 720 píxeles lógicos.
- Cámara centrada en Córdoba, zoom 12.
- El logcat identifica `Using the Impeller rendering backend (OpenGLES)`.

Sin embargo, la captura del viewport permanece casi negra y el SDK solo emite `RenderMode.PARTIAL`; no aparecen `MAP_LOADED` ni `MAP_IDLE`. El estilo JSON describe un fondo claro, por lo que la captura no coincide con el fondo declarado. Esto apunta a una diferencia en el camino de composición/renderizado o en el procesamiento de los recursos; **todavía no demuestra que Impeller sea la causa**.

Existe un antecedente público de Mapbox Flutter sobre mapas que no aparecen con Impeller habilitado ([issue #300](https://github.com/mapbox/mapbox-maps-flutter/issues/300), noviembre de 2023). Es una pista para una prueba controlada, no una confirmación de que el defecto histórico siga presente en las versiones actuales.

### Experimento siguiente: mismo MapView, Impeller frente a Skia

La comparación A/B se cambia para aislar el motor Flutter, manteniendo iguales:

- commit, application ID, versionCode y estilo Outdoors v12;
- Hybrid Composition + SurfaceView;
- pixel ratio, cámara, emulador y configuración de red;
- limpieza de datos TileStore entre instalaciones.

El APK principal conserva la configuración predeterminada de Flutter (Impeller). Solo el APK comparativo de staging recibe, en su manifiesto generado y no versionado, `io.flutter.embedding.android.EnableImpeller=false`. El helper `tool/prepare_android_skia_ab.py` valida XML y es idempotente.

El viewport registra el backend real mediante `ui.ImageFilter.isShaderFilterSupported` como `MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=impeller|skia`. El orquestador rechaza la comparación si los logs no prueban que los APK ejecutaron motores distintos.

**El opt-out de Impeller es únicamente diagnóstico. No se ha añadido al manifiesto de producción ni debe publicarse como solución permanente sin pruebas físicas.** Flutter documenta que esta opción de compatibilidad está deprecada y puede desaparecer: [Impeller — Flutter](https://docs.flutter.dev/perf/impeller).

La aceptación requiere, para el APK que se proponga como candidato:
- backend real identificado en logcat;
- `MAP_LOADED`, `MAP_IDLE` y `RenderMode.FULL`;
- PNG cartográfico legible y gate visual superado;
- validación posterior en dispositivo físico.

Si Skia supera el gate y el APK Impeller no, se preparará una compatibilidad temporal y un informe de limitación/deprecación; no se cambiará el predeterminado hasta validar el OPPO. Si ambos fallan, se investigarán el SDK nativo, la respuesta/decodificación de tiles y la composición Android antes de tocar el estilo.


## Diagnóstico Impeller/Skia y Snapshotter nativo — 17/11/2026

La ejecución Android staging [44011075469](https://github.com/Baltas80/espana-outdoor/actions/runs/44011075469), source commit `85d00dc`, construyó y publicó ambos APK. El smoke se ejecutó en los dos casos y falló únicamente porque el viewport no superó el gate cartográfico; las evidencias se conservaron en [14296859542](https://github.com/Baltas80/espana-outdoor/actions/runs/44011075469/artifacts/14296859542).

La identidad de los motores quedó demostrada en logcat, no inferida del manifiesto:

- APK principal: `MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=impeller`.
- APK comparativo: `MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=skia`.
- Ambos: `STYLE_LOADED`, `RenderMode.PARTIAL`, sin `MAP_LOADED`, `MAP_IDLE` ni `RenderMode.FULL`.
- Ambos declararon el mismo estilo, 148 capas, una fuente y fondo `hsl(60, 20%, 85%)`.
- PNG principal: entropía 0,650 y color dominante 0,901. PNG Skia: entropía 0,651 y color dominante 0,901. Las capturas muestran el mismo viewport muy oscuro, con algunos trazos de cartografía.
- El emulador Android x86_64 usa SwiftShader. El logcat contiene `GL2Encoder.cpp:s_glGetStringi ... GL error 0x501` en el proceso comparativo y tiempos `EGL_emulation app_time_stats` muy elevados.

**Conclusión limitada:** cambiar el backend Flutter de Impeller a Skia no corrigió el mapa en este emulador. Esto reduce la probabilidad de que Impeller sea la causa aislada. No demuestra que el SDK nativo de Mapbox o el dispositivo físico tengan el mismo fallo. Mapbox documenta que sus mapas móviles son renderizados por el SDK nativo y requieren soporte OpenGL ES 3: [requisitos del SDK Android](https://docs.mapbox.com/android/maps/guides/).

### Siguiente prueba: Snapshotter nativo independiente del MapWidget

Se añade una captura de diagnóstico con `Snapshotter`, usando el mismo estilo, tamaño lógico, pixel ratio y cámara del viewport. La imagen se emite en fragmentos Base64 con SHA-256 dentro de logcat y se reconstruye como artefacto PNG por `tool/extract_mapbox_snapshotter_png.py`.

La comparación separa dos hipótesis:

1. Si Snapshotter genera un mapa legible y `adb screencap` sigue oscuro, investigar la integración del PlatformView/SurfaceView y la composición Android.
2. Si Snapshotter y el viewport generan imágenes oscuras/incompletas, investigar el renderizador nativo de Mapbox, la decodificación de tiles y el backend gráfico del emulador.

La captura adicional es diagnóstica y no relaja el gate: el APK sigue necesitando `MAP_LOADED`, `RenderMode.FULL`, `MAP_IDLE` y PNG visible para aprobar. La ejecución no certifica dispositivo físico ni modo offline.


## Snapshotter: captura acotada y evidencia completa — 17/11/2026

La captura nativa Snapshotter se ejecuta de forma asíncrona tras `STYLE_LOADED`. Cada llamada nativa tiene un límite explícito: creación 30 s, selección del estilo 30 s, espera del evento de estilo 45 s, cámara 15 s, render PNG 45 s y liberación 10 s. El log registra etapas y tiempo transcurrido sin imprimir tokens ni URLs.

El smoke Android no vuelca el logcat final inmediatamente después del gate del MapWidget: espera hasta 210 s (configurable entre 15 y 240 s) a que Snapshotter emita `disposed`, `failed` o `dispose_failed`. Después guarda el logcat completo y reconstruye el PNG validando bytes, dimensiones y SHA-256. Si la captura diagnóstica no llega, se conserva el motivo y el gate principal de `MAP_LOADED`/`FULL`/`IDLE` permanece independiente; Snapshotter nunca sustituye ni relaja la aceptación cartográfica.


## Diagnóstico Android — 17/11/2026 07:18 CET

Ejecución [Android staging 44023914366](https://github.com/Baltas80/espana-outdoor/actions/runs/44023914366), artefacto de evidencias [14303301878](https://github.com/Baltas80/espana-outdoor/actions/runs/44023914366/artifacts/14303301878).

- Los APK principal (Impeller) y comparativo (Skia opt-out) se compilaron, verificaron y publicaron. Los dos smoke abrieron la pantalla Mapa.
- Ambos procesos permanecieron en `RenderMode.PARTIAL`; no emitieron `MAP_LOADED` ni `MAP_IDLE`. El gate cartográfico rechazó ambos.
- Las capturas muestran un viewport casi negro con algunos trazos cartográficos; no son evidencia de mapa utilizable.
- El estilo cargó en ambos casos: 148 capas, una fuente y fondo declarado `hsl(60, 20%, 85%)`. Hubo respuestas de teselas/glyphs no vacías; los misses de TileStore son fallos de caché local, no HTTP 404.
- En ambos procesos el Snapshotter cargó el estilo y aplicó la cámara, pero `Snapshotter.start()` agotó su timeout de 45 s. El extractor no encontró un PNG de Snapshotter.
- Se observó un `GL error 0x501` en `emuglGLESv2_enc` en ambos procesos, dentro del emulador Android con SwiftShader. Es una correlación del entorno de prueba, no una causa raíz demostrada.
- La suite CI general y Security baseline del HEAD `d308adcb` terminaron correctamente; Android staging falló únicamente en el gate funcional del mapa. Los dos APK y las evidencias se conservaron.

### Siguiente aislamiento

El Snapshotter de staging se ha cambiado para renderizar primero un estilo JSON local con una única capa de fondo y sin fuentes externas. Se registran además los errores de carga incluso si llegan después de `STYLE_LOADED`, los eventos de datos de estilo, imágenes ausentes y el inicio explícito de captura.

Interpretación:
- Si el PNG de fondo sólido se genera, el renderer nativo puede producir una imagen y la investigación debe centrarse en fuentes vectoriales/teselas/estilo Outdoors.
- Si también agota el timeout, el bloqueo está por debajo del estilo remoto (renderer nativo, GPU o emulador).

Este baseline no sustituye el gate del mapa real ni cambia el estilo de producción. La aceptación sigue exigiendo `MAP_LOADED`, `RenderMode.FULL`, `MAP_IDLE`, captura visual válida y pruebas offline/físicas.


## Evidencia Android — Snapshotter sin fuentes y siguiente aislamiento vectorial (17/11/2026)

Ejecución [Android staging 44030999939](https://github.com/Baltas80/espana-outdoor/actions/runs/44030999939), HEAD fuente `06ee1fa`. Artefacto de evidencias [14305199993](https://github.com/Baltas80/espana-outdoor/actions/runs/44030999939/artifacts/14305199993).

- Ambos APK (Impeller y Skia) se compilaron, verificaron y ejecutaron. UIAutomator confirmó la página `Mapa cartográfico` y el paquete de España Outdoor en primer plano.
- Ambos MapWidget quedaron en `RenderMode.PARTIAL`; no emitieron `MAP_LOADED` ni `MAP_IDLE`. Las capturas 1080×2400 fueron rechazadas: 34 colores cuantizados, entropía 0,651 bits y color dominante 0,901.
- El Snapshotter nativo sí generó una imagen independiente del estilo local sin fuentes en ambos procesos: 1079×1891, 12.325 bytes, SHA-256 `7aa0edd61f8e1fe4169435903461f79871287a8f6d5c2e0fdbc62623749668d5`. La imagen inspeccionada es un fondo uniforme `#d9e6c7`.
- Esto demuestra que el Snapshotter/renderer nativo puede producir una imagen simple sin fuentes externas. No demuestra que el MapWidget ni la fuente vectorial remota funcionen; tampoco identifica por sí solo un fallo de composición.

El siguiente experimento añade un segundo Snapshotter con una sola fuente vectorial Mapbox Streets v8 y una capa `road`, manteniendo el mismo centro/zoom. Se publican por separado los PNG `baseline` y `vector`, y el resumen del estilo registra tipos de fuente/capa y visibilidad del fondo sin imprimir URLs completas ni tokens.

Interpretación:
- Baseline correcto + vector correcto: la decodificación vectorial básica funciona; investigar la configuración/imports del estilo Outdoors y el MapWidget.
- Baseline correcto + vector fallido/vacío: investigar la fuente vectorial, acceso/tiles y decodificación antes de tocar composición Flutter.
- Ambos fallan: reabrir la investigación del renderer nativo/entorno, aunque el baseline anterior ya fue correcto.

El run Android terminó en fallo intencionado del gate cartográfico; CI general y Security (8/8) sí terminaron correctamente en ese HEAD. No se acepta online/offline ni se modifica el estilo de producción.

## Diagnóstico TileStore y fuente vectorial — 17/11/2026 09:29 CET

Ejecución [Android staging 44040272329](https://github.com/Baltas80/espana-outdoor/actions/runs/44040272329), commit probado `082f53ae1d7e77981110610d0cc15e7f353abbd9`.

- El Snapshotter baseline sin fuentes generó el PNG uniforme `#d9e6c7`: 1079×1891, 12.325 bytes, SHA-256 `7aa0edd61f8e1fe4169435903461f79871287a8f6d5c2e0fdbc62623749668d5`.
- El Snapshotter vectorial cargó el TileJSON de Mapbox Streets v8 desde Network (19.079 bytes), recibió el callback de estilo y aplicó la cámara. Después, las solicitudes de tiles observadas consultaron TileStore y devolvieron `NOT_FOUND`; algunas solicitudes del ResourceLoader fueron canceladas. No se observó una respuesta de red de tiles en ese Snapshotter antes de que `start()` agotara 60 s. No se generó PNG vectorial.
- En el MapWidget principal sí hubo respuestas de red de teselas y glyphs con contenido, pero la mayoría de los eventos `SOURCE_DATA loaded=false` persistieron; no se alcanzó `MAP_LOADED`, `RenderMode.FULL` ni `MAP_IDLE`. La captura 1080×2400 fue rechazada (34 colores, entropía 0,651 bits, color dominante 0,901).
- El gate Android falló por el resultado funcional, no por compilación: se conservaron los artefactos y la evidencia. CI general y Security del mismo HEAD terminaron correctamente.

### Hipótesis y siguiente experimento

Mapbox documenta que `TileStoreUsageMode.READ_ONLY` (predeterminado) consulta primero paquetes locales y, si faltan, vuelve a solicitar tiles individuales; `DISABLED` omite la consulta a TileStore ([API de TileStoreUsageMode](https://docs.mapbox.com/flutter/maps/api/latest/mapbox_maps_flutter/TileStoreUsageMode.html), [conceptos offline Android](https://docs.mapbox.com/android/maps/guides/offline/concepts/)).

Los registros no prueban que READ_ONLY suprima la descarga; solo justifican aislar esa variable. Se añade un APK diagnóstico Android staging con `MAPBOX_TILE_STORE_USAGE_MODE=disabled`, manteniendo estilo, cámara, renderer, hosting, commit y versión. La app registra el modo efectivo antes de crear mapas.

**Restricción:** este APK es solo diagnóstico online. Al desactivar TileStore no sirve para aceptar mapas offline ni debe desplegarse. El APK principal conserva el modo predeterminado READ_ONLY. Producción y su configuración no cambian.

Interpretación:
- Si aparecen solicitudes de tiles desde Network y el Snapshotter genera calles, investigar el camino TileStore/cache y el estado de los paquetes offline.
- Si las solicitudes siguen sin salir o el Snapshotter sigue agotando el timeout, investigar el motor nativo, la cobertura/cámara y el emulador; no atribuir el fallo al TileStore sin más evidencia.
- La aceptación sigue exigiendo MapWidget con `MAP_LOADED`, `FULL`, `IDLE`, captura visual válida y pruebas offline reales en dispositivo físico.


## Corrección de evidencia A/B y aislamiento de variantes — 17/11/2026 12:17 CET

Ejecución [Android staging 44065337090](https://github.com/Baltas80/espana-outdoor/actions/runs/44065337090), source HEAD 08ade9fa646e970985c1228f1f2c266935c2e4df, artefacto de evidencias [14321294721](https://github.com/Baltas80/espana-outdoor/actions/runs/44065337090/artifacts/14321294721).

La inspección del ZIP corrige una interpretación anterior de la matriz:

- **APK principal (Impeller):** compiló y superó la verificación del APK/manifiesto, pero el smoke no llegó a la página Mapa. La primera llamada de UIAutomator devolvió sin crear /sdcard/espana-outdoor-uiautomator.xml; el cat falló con “No such file or directory”. La captura conservada corresponde a Inicio y el log no contiene FLUTTER_RENDERER. No existe evidencia cartográfica válida del APK principal en este run.
- **APK Skia:** llegó a Mapa cartográfico, registró backend=skia y TileStore READ_ONLY; el gate rechazó la captura. Métricas: 34 colores cuantizados, entropía 0,651 bits, color dominante 0,901; RenderMode.PARTIAL, sin MAP_LOADED, MAP_IDLE ni RenderMode.FULL.
- **APK TileStore-disabled:** llegó a Mapa cartográfico y registró TileStore DISABLED, pero también backend=skia. Su captura fue rechazada con las mismas métricas agregadas (34 colores, 0,651 bits, 0,901 dominante), RenderMode.PARTIAL y sin eventos de carga completa.

**Defecto del experimento identificado:** tool/prepare_android_skia_ab.py modifica el android/app/src/main/AndroidManifest.xml versionado para añadir EnableImpeller=false. El workflow compilaba después el APK TileStore-disabled sin restaurar ese manifiesto; por eso heredó Skia pese a declarar flutter_renderer=impeller-default. La comparación TileStore-disabled no era independiente y no permite concluir que desactivar TileStore no tenga efecto.

### Correcciones publicadas en PR #79

- tool/smoke_android_map.sh: UIAutomator ahora elimina el XML remoto anterior, reintenta hasta cuatro veces, comprueba que el fichero remoto existe y no está vacío antes de leerlo y valida la jerarquía. El selector de Mapa exige un nodo semántico clicable y reconoce el label del botón inferior, no su icono decorativo.
- tool/test_android_map_smoke_render_gate.py: prueba con ADB simulado que recupera una jerarquía después de dos ausencias transitorias y falla de forma cerrada tras cuatro intentos.
- .github/workflows/staging-android.yml: antes de compilar TileStore-disabled restaura byte a byte el manifiesto ya configurado por configure_mobile_native.py, guardado antes de la mutación Skia; lo verifica con cmp y exige que el manifiesto de la variante declare Impeller predeterminado.
- tool/smoke_android_map_ab.sh: además de verificar TileStore desactivado, exige que el log runtime de esa variante confirme backend=impeller. Una variante que herede Skia queda rechazada.

### Interpretación y siguiente ejecución

La evidencia válida de este run solo confirma que **Skia + TileStore READ_ONLY** y **Skia + TileStore DISABLED** no superaron el gate visual en SwiftShader. No hubo una prueba válida del MapWidget Impeller y la comparación de TileStore quedó contaminada.

El siguiente staging debe demostrar tres identidades runtime independientes antes de comparar imágenes: principal Impeller + READ_ONLY, comparativo Skia + READ_ONLY y diagnóstico Impeller + DISABLED. Cada APK debe llegar a Mapa cartográfico; después se comparan callbacks, eventos de teselas y PNG. El gate sigue exigiendo MAP_LOADED, RenderMode.FULL, MAP_IDLE y captura visual válida.

CI general [44065339116](https://github.com/Baltas80/espana-outdoor/actions/runs/44065339116) y Security [44065336788](https://github.com/Baltas80/espana-outdoor/actions/runs/44065336788) terminaron correctamente sobre el HEAD 08ade9f; Android staging [44065337090](https://github.com/Baltas80/espana-outdoor/actions/runs/44065337090) terminó en fallo del smoke. La nueva corrección aún necesita CI y staging sobre su nuevo HEAD.

No se certifica mapa online/offline ni dispositivo físico. No se modifica la configuración cartográfica de producción.
