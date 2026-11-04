# España Outdoor — Estrategia offline

## Principio

La app Android debe seguir siendo útil en zonas sin cobertura. Mapbox Maps SDK proporciona la cartografía y Mapbox Navigation SDK v3 aporta el motor de cálculo online/offline. No se utiliza un servidor doméstico ni se necesita un VPS para routing del MVP.

## Datos descargables por región

- Paquete de estilo Mapbox Outdoors.
- Teselas cartográficas de la zona seleccionada.
- Tileset de routing peatonal de Navigation SDK.
- Geometría y metadatos de rutas guardadas.
- Información local de seguridad, emergencia y contactos de confianza.

Los datos visuales y de routing se descargan con un identificador de región común y el mismo TileStore nativo compartido entre Maps y Navigation.

## Cálculo de rutas

El adaptador Flutter mantiene el contrato RoutingService. El adaptador Android invoca Mapbox Navigation SDK v3 por MethodChannel.

- Con Internet disponible, Navigation SDK puede utilizar Mapbox Directions.
- Sin Internet, el SDK puede generar rutas localmente cuando el tileset peatonal de la región está almacenado en el dispositivo.
- Si no hay recursos offline para la zona, la app no debe fingir que el cálculo offline está disponible.
- El resultado expone el origen online u offline.
- El cálculo offline integrado se limita por ahora a Android.

## Descarga y mantenimiento

La primera región de validación es Córdoba, zoom 8–15. Debe ampliarse mediante regiones explícitas elegidas por el usuario, con estimación de almacenamiento, progreso, cancelación, reintento, actualización y eliminación.

Los recursos descargados deben mostrar región, fecha de actualización, estado de integridad y tamaño cuando el SDK lo exponga. No se debe afirmar cobertura nacional por descargar una sola región.

## Prueba de aceptación

Para cada región:
1. Descargar el paquete de estilo, teselas y routing graph.
2. Forzar cierre y reapertura en frío.
3. Activar modo avión.
4. Solicitar una ruta nueva, no solo visualizar una guardada.
5. Comprobar que el origen del cálculo es offline.
6. Probar un nuevo destino y el recálculo al desviarse sin conexión.
7. Comprobar la persistencia tras reiniciar el dispositivo.

## Límites de conectividad

Meteorología, cierres, alertas y sincronización necesitan conectividad para actualizarse. La app debe mostrar la antigüedad de esos datos y no presentarlos como actuales cuando esté offline.
