# Cartografía y modo offline

## Motor cartográfico

Mapbox Maps SDK (`mapbox_maps_flutter`) es el motor elegido para la aplicación. El estilo principal es Mapbox Outdoors y requiere `MAPBOX_ACCESS_TOKEN` inyectado durante la compilación. No se debe mantener un catálogo cartográfico paralelo.

## Modo offline

La integración usa `OfflineManager` y `TileStore` para guardar el estilo y una región de prueba de Córdoba, zoom 8–15. La prueba de concepto previa de la región de Córdoba fue reportada como funcional sin conexión en el OPPO. Esa evidencia se limita a esa región y no demuestra por sí sola que el APK integrado soporte reapertura en frío offline; hay que validar el APK exacto, el área, la navegación por el mapa y la recuperación al restablecer la conexión.

## Reglas

- Mantener Mapbox como único motor de representación cartográfica.
- Conservar GPS, grabación de recorridos, GPX, routing Valhalla y funciones de seguridad independientemente del proveedor del mapa.
- Mantener los datos críticos de ruta disponibles offline y mostrar su antigüedad cuando corresponda.
- No usar servidores públicos de teselas OSM para descargas masivas.
- Mostrar progreso, errores, reintentos y estado de la descarga de Mapbox.
- No declarar cobertura nacional ni producción completa por haber descargado la región de Córdoba.

## Migración y validación pendientes

Las pantallas secundarias de planificación y detalle se han migrado al viewport Mapbox compartido, con selección de destino y anotaciones de ruta/GPX. El APK integrado aún requiere validación en dispositivo para visualizar el mapa online, descargar la región, usar modo avión y reabrir en frío. La CI verde por sí sola no demuestra toda esa validación.
