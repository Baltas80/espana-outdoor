# Cartografía y modo offline

## Motor cartográfico

Mapbox Maps SDK (`mapbox_maps_flutter`) es el motor elegido para la aplicación. El estilo principal es Mapbox Outdoors y requiere `MAPBOX_ACCESS_TOKEN` inyectado durante la compilación. No se debe mantener un catálogo cartográfico paralelo.

## Modo offline

La integración usa `OfflineManager` y `TileStore` para guardar el estilo y una región de prueba de Córdoba, zoom 8–15. El usuario ha confirmado que el mapa integrado aparece sin conexión en el OPPO. Esta evidencia manual cubre esa región de prueba, no España completa; la extensión exacta, reapertura en frío y recuperación tras perder conexión deben quedar documentadas.

## Reglas

- Mantener Mapbox como único motor de representación cartográfica.
- Conservar GPS, grabación de recorridos, GPX, routing Valhalla y funciones de seguridad independientemente del proveedor del mapa.
- Mantener los datos críticos de ruta disponibles offline y mostrar su antigüedad cuando corresponda.
- No usar servidores públicos de teselas OSM para descargas masivas.
- Mostrar progreso, errores, reintentos y estado de la descarga de Mapbox.
- No declarar cobertura nacional ni producción completa por haber descargado la región de Córdoba.

## Migración y validación pendientes

Las pantallas secundarias de planificación y detalle se han migrado al viewport Mapbox compartido, con selección de destino y anotaciones de ruta/GPX. Esta migración aún necesita análisis, pruebas y APK Android; instalar en dispositivo y comprobar mapa online, descarga, modo avión y reapertura en frío. La CI verde por sí sola no demuestra toda esa validación.
