# España Outdoor — arquitectura móvil

## Cartografía

- Motor único: Mapbox Maps SDK mediante `mapbox_maps_flutter`.
- Estilo principal: Mapbox Outdoors.
- Configuración de acceso: `MAPBOX_ACCESS_TOKEN`, inyectado durante la compilación.
- Las regiones sin conexión se gestionan mediante las capacidades offline nativas del SDK.
- La interfaz compartida debe gestionar carga, errores, permisos, falta de conexión y estado de descarga.
- El GPS, el dominio de rutas y la seguridad permanecen desacoplados de la presentación del mapa.

## Ciclo de vida

1. Validar la configuración Mapbox.
2. Crear la superficie cartográfica y esperar a que esté disponible.
3. Presentar el estilo y las anotaciones solicitadas.
4. Mostrar errores de configuración/carga sin cerrar la aplicación.
5. Liberar listeners y recursos al desmontar la pantalla.

Las llamadas al controlador deben respetar su ciclo de vida y no ejecutarse después de desmontar el widget.

## Regiones offline

La descarga offline debe registrar estado, progreso, errores y persistencia. Antes de declarar una región disponible, verificar la finalización de la descarga y la posibilidad de volver a abrirla después de cerrar la aplicación y activar el modo avión. La cobertura regional y el tamaño de descarga deben documentarse con pruebas reales.

## GPS y grabación

La grabación Android utiliza el stack GPS existente y debe respetar permisos, notificación foreground, persistencia incremental y recuperación tras interrupciones. El objetivo se valida en dispositivos Android compatibles.

## Elevación y sombreado

No simular hillshading con degradados visuales. La implementación requiere una fuente DEM compatible, licencia documentada y pruebas de rendimiento.

## Rendimiento

- Evitar polling de alta frecuencia.
- Evitar cargar grandes archivos completos en memoria cuando no sea necesario.
- Liberar streams y suscripciones al desmontar features.
- Mantener el procesamiento pesado fuera del isolate de UI.

## Gates de release Android

1. Análisis Dart y pruebas automatizadas.
2. Validación de configuración nativa.
3. Build APK y verificación del artefacto.
4. Instalación y apertura en dispositivo/emulador.
5. Interacción con el mapa y navegación entre pantallas.
6. Prueba offline con región descargada y conectividad desactivada.
7. GPS, grabación de recorridos y recuperación de estado.
