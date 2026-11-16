# Cartografía y modo offline

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

El smoke Android debe distinguir entre proceso vivo, estilo cargado y viewport realmente renderizado. La captura de la PR #73 (run [43877738921](https://github.com/Baltas80/espana-outdoor/actions/runs/43877738921)) se tomó con conectividad validada y la aplicación en primer plano, pero el viewport quedó casi negro y el gate visual la rechazó (entropía 0,650 bits; color dominante 0,901). El logcat solo confirmó la inicialización de Mapbox Common/Maps Core; no contenía eventos de estilo/fuente ni un error Mapbox que permitiera atribuir la causa.

La [PR #79](https://github.com/Baltas80/espana-outdoor/pull/79) añade instrumentación temporal y acotada al `MapboxMapViewport`. Los registros usan el prefijo `MAPBOX_DIAGNOSTIC` y distinguen `STYLE_LOADED`, `MAP_LOADED`, `MAP_IDLE`, `MAP_LOAD_ERROR`, `STYLE_DATA`, `SOURCE_ADDED`, `SOURCE_DATA`, `STYLE_IMAGE_MISSING` y cambios de `RENDER_FRAME`. No se registran URLs de solicitudes y se redactan access tokens/Bearer si aparecen en mensajes de error. El límite es de 250 eventos de datos de fuente por instancia. La instrumentación todavía requiere CI y un APK staging; no es una solución funcional por sí misma.

## Estado y pendientes

- Estilo de producción: `mapbox://styles/mapbox/outdoors-v12`; no se ha cambiado por hipótesis.
- Mapa online: no aceptado; la captura de la PR #73 falla el gate visual.
- Mapa offline: no aceptado; falta acreditar renderizado real en modo avión.
- Routing peatonal offline: evidencia histórica positiva en emulador, pero no suficiente para certificar el mapa ni el APK actual.
- PR #61: abierta/draft, divergida de `main`; requiere sincronización y nueva ejecución del experimento de estilos/TileStore.
- PR #79: instrumentación diagnóstica abierta; falta CI/Security y Android staging con logcat nuevo.
- Reapertura en frío, reinicio físico y validación del APK exacto en OPPO: pendientes.
- Cobertura nacional y routing offline BTT/cicloturismo: no acreditados.
- Las pantallas de planificación y detalle usan el viewport Mapbox compartido; Valhalla sigue dependiendo del endpoint online.
