# Cartografía y modo offline

## Motor cartográfico

Mapbox Maps SDK (`mapbox_maps_flutter`) es el motor elegido para la aplicación. El estilo principal es Mapbox Outdoors y requiere `MAPBOX_ACCESS_TOKEN` inyectado durante la compilación. No se debe mantener un catálogo cartográfico paralelo.

## Dos capacidades distintas

### Mapas y teselas offline

En `main`, la pantalla `OfflinePage` usa `OfflineManager` y `TileStore.createDefault()` para guardar el estilo y una región de prueba de Córdoba. Esta descarga permite validar almacenamiento cartográfico; por sí sola no demuestra que la aplicación sobreviva a una reapertura en frío, que el mapa se renderice en modo avión o que exista cobertura nacional.

La prueba anterior de Córdoba fue reportada como funcional sin conexión en un OPPO. Debe tratarse como evidencia histórica de una prueba de concepto, no como certificación del APK actual.

### Cálculo de rutas offline

En `main`, el proveedor de rutas utiliza `ValhallaRoutingService` con `VALHALLA_BASE_URL`; requiere conectividad. La disponibilidad de teselas offline no convierte ese servicio en un motor de rutas offline.

La integración nativa propuesta está en la [PR #61](https://github.com/Baltas80/espana-outdoor/pull/61). Comparte un `TileStore` persistente entre Maps SDK y Navigation SDK y descarga los recursos de routing peatonal junto con las teselas del mapa. El adaptador informa el origen devuelto por Mapbox (`online` / `offline`) y el routing compuesto conserva Valhalla para BTT, cicloturismo y map matching GPX.

Las PR #25, #52, #53, #57 y #59 se cerraron como supersedidas. La PR #61 sigue pendiente de CI e integración; su código no forma parte de `main`. No debe mostrarse el cálculo offline como funcional hasta demostrar una solicitud nueva con origen nativo `OFFLINE` en modo avión.

La implementación propuesta no habilita routing offline de bicicleta, cobertura nacional ni navegación turn-by-turn completa.

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

## Estado y pendientes

- Mapa offline: descarga de una región de prueba presente en `main`; falta repetir la validación física sobre el HEAD actual.
- Navegación offline nativa: propuesta en PR #61, no integrada.
- Cobertura nacional: no acreditada.
- Reapertura en frío y tras reinicio: pendiente para el APK candidato.
- Las pantallas de planificación y detalle usan el viewport Mapbox compartido; la ruta Valhalla sigue dependiendo del endpoint online.


## Diagnóstico de arranque Android

La ejecución anterior de staging de la implementación en PR #53 instaló el APK y arrancó el emulador, pero no encontró el destino accesible `Mapa` después de la espera acotada. La jerarquía UI capturada estaba vacía y el artefacto no contenía logcat; por tanto, no hay evidencia suficiente para atribuir el bloqueo a una excepción concreta.

La PR #61 añade marcadores de arranque sin secretos, timeout para inicialización opcional de Mapbox Navigation y del servicio de descargas, y captura de logcat, screenshot y estado de Activity cuando falla el smoke. La siguiente ejecución debe aportar esa evidencia antes de concluir la causa. El timeout no equivale a validar routing offline.


En caso de fallo del smoke, el artefacto Android staging debe conservar `logcat`, `dumpsys activity`, captura de pantalla y jerarquía UI (`uiautomator dump`). La aceptación requiere que el log muestre `MAPBOX_OFFLINE_MAP_RENDERED` y que la ruta de prueba devuelva `OFFLINE`; la mera instalación del APK no cuenta como prueba de navegación offline.
