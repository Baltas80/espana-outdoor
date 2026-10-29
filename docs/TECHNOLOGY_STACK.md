# España Outdoor — Technology Stack

## Base vigente

- Flutter/Dart para la aplicación móvil.
- Riverpod para estado.
- go_router para navegación.
- Mapbox Maps SDK (`mapbox_maps_flutter`) como único motor cartográfico.
- geolocator para ubicación y GPS.
- file_picker y gpx para importar/exportar recorridos.
- path_provider, Hive CE y flutter_secure_storage para persistencia.
- connectivity_plus para conectividad.
- background_downloader para las descargas que lo requieran.
- Valhalla mediante el adaptador existente para calcular rutas.

## Cartografía y modo offline

La pantalla cartográfica compartida usa el estilo Mapbox Outdoors. La clave pública de acceso se inyecta mediante `MAPBOX_ACCESS_TOKEN` durante la compilación; no se escribe en el código fuente.

Las regiones offline se administran mediante las capacidades nativas del SDK Mapbox. La implementación debe comprobar descarga, progreso, errores, persistencia, integridad disponible en el SDK, reapertura en frío y representación con el dispositivo en modo avión. No existe un catálogo cartográfico paralelo.

No utilizar servidores públicos de teselas de OSM para descargas masivas. La cobertura offline no se considera validada por el mero hecho de que compile la app o se vea el mapa online.

## Routing

Conservar el puerto de routing y el adaptador Valhalla. El endpoint se configura mediante `VALHALLA_BASE_URL`. No generar rutas ficticias ni confundir una geometría GPX con una ruta calculada o navegación activa.

## Persistencia y trabajo en segundo plano

Hive CE se mantiene para persistencia ligera. Evaluar almacenamiento relacional solo si el crecimiento real del modelo lo requiere. La grabación GPS continua debe respetar permisos nativos, restricciones de segundo plano y batería; un planificador periódico no la sustituye.

## Datos oficiales y seguridad

AEMET OpenData es la fuente preferida para meteorología mediante el adaptador previsto. Las credenciales privilegiadas deben residir en infraestructura controlada, no en el cliente público. Los datos dinámicos deben conservar procedencia, hora de consulta y vigencia cuando aplique.

## Regla para dependencias nuevas

Antes de añadir una dependencia, comprobar mantenimiento, compatibilidad, licencia, plataformas, necesidad y pruebas. No introducir un segundo motor cartográfico ni otro mecanismo de distribución de mapas.
