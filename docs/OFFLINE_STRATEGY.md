# España Outdoor — Estrategia offline

## Principio

La aplicación debe conservar utilidad cuando se pierde la conexión. Mapbox es el único motor cartográfico y `OfflineManager`/`TileStore` son el mecanismo de almacenamiento cartográfico offline. No se utilizará PMTiles ni un catálogo paralelo.

## Datos críticos

- Región cartográfica de Mapbox descargada y validada para la zona seleccionada.
- Geometría y metadatos básicos de la ruta activa.
- Instrucciones de emergencia y contactos de confianza disponibles localmente.
- Datos de seguridad descargados, indicando su fecha de actualización.

## Datos recomendados

- Puntos de interés cercanos.
- Última instantánea meteorológica disponible.
- Orientación sobre fauna, mascotas y restricciones de conservación, con procedencia y antigüedad.

## Ciclo de vida de la descarga

La interfaz debe mostrar región, progreso, tamaño si el SDK lo permite, resultado, errores y reintentos. La aplicación debe identificar los recursos de estilo y región que están guardados, distinguir una descarga incompleta de una válida y permitir gestionar el almacenamiento con las capacidades disponibles en Mapbox.

## Modo degradado

Si no se pueden actualizar datos online, mostrar el último estado guardado con su marca temporal. La navegación calculada mediante Valhalla requiere conexión con el endpoint configurado; no debe presentarse como disponible offline salvo que exista un mecanismo offline comprobado. La geometría de una ruta ya guardada debe seguir disponible localmente.

## Estado conocido

El usuario ha confirmado que la región de prueba de Córdoba funciona sin conexión en el OPPO. Esto no acredita cobertura nacional, reapertura en frío documentada ni funcionamiento offline de servicios externos. La validación final requiere pruebas en Android con todas las redes desactivadas.

## Funciones independientes del mapa

La limpieza de cartografía no debe eliminar GPS, grabación y persistencia de recorridos, importación/exportación GPX, Valhalla, SOS, contactos de confianza ni sincronización offline genérica.
