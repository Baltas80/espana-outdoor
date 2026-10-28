# España Outdoor — arquitectura móvil de alta gama

## 1. Cartografía móvil

- Renderer: MapLibre Flutter mediante la dependencia `maplibre_gl`.
- Estilo online de MapLibre configurado por entorno; la cartografía offline está pendiente de una implementación validada.
- Los datos offline descargados deben verificarse antes de activarse y conservar atribución/licencia.
- La pantalla cartográfica activa es `lib/features/map/maplibre_map_page.dart`; la carga de estilos y fuentes está en `lib/core/maps/`.
- La lógica de rutas, seguridad y estado offline debe permanecer desacoplada de la implementación concreta del renderer.

La configuración de producción debe proporcionar un estilo MapLibre HTTPS aprobado. No se permite fallback silencioso a un servicio público de teselas para producción.

## 2. Lifecycle del mapa

1. Resolver configuración de estilo y fuente cartográfica.
2. Preferir un paquete offline local previamente verificado cuando exista.
3. Crear la superficie MapLibre y esperar a que esté disponible.
4. Cargar el estilo y la fuente cartográfica configurados.
5. Presentar errores de configuración/carga sin cerrar la aplicación.
6. Liberar listeners y recursos al desmontar la pantalla.

Las llamadas al controlador del mapa deben respetar su lifecycle y no ejecutarse después de desmontar el widget.

## 3. Integridad offline

Los paquetes descargados deben seguir una máquina de estados explícita: descarga parcial, descarga completa, validación de metadatos y tamaño, verificación SHA-256 y promoción atómica a paquete activo. Un archivo parcial nunca debe considerarse disponible.

El catálogo debe proporcionar procedencia, URL HTTPS, licencia/atribución, tamaño esperado, fecha de actualización y digest de integridad. Si la validación falla, el paquete no se activa y debe recuperarse de la fuente aprobada.

## 4. Foreground tracking

La grabación Android usa `geolocator` con notificación foreground, wake lock y persistencia incremental. La aplicación debe poder recuperar una sesión tras una interrupción.

No se afirma que Android permita un proceso literalmente inmune a destrucción. El objetivo profesional es un servicio foreground de ubicación, notificación persistente, permisos correctos, recuperación de sesión y pruebas Android 14/15/16 en dispositivos objetivo.

## 5. Caching predictivo

El caching predictivo se debe diseñar sobre regiones offline publicadas por el catálogo:

- analizar una ruta guardada o planificada;
- seleccionar regiones que intersecten la ruta y un corredor configurable;
- priorizar la región actual y las siguientes;
- descargar solo con conectividad y batería adecuadas;
- validar integridad antes de activar cada región;
- evitar duplicar descargas que ya estén presentes.

No se descargará automáticamente toda España cuando una ruta solo atraviese una pequeña zona.

## 6. Elevación y sombreado

No se debe simular hillshading con degradados visuales. La implementación profesional requiere una fuente DEM compatible y con licencia documentada, almacenamiento local, validación, cálculo de sombreado y pruebas de rendimiento. La integración se mantiene desacoplada hasta que exista un camino técnicamente soportado.

## 7. Rendimiento

- Evitar polling de alta frecuencia.
- Evitar cargar grandes archivos completos en memoria cuando no sea necesario.
- No recalcular elevación mientras el mapa está estático.
- Invalidar cachés solo cuando cambie el bloque relevante.
- Mantener procesamiento pesado fuera del isolate de UI.
- Liberar streams y suscripciones al desmontar features.
- No usar imágenes gigantes cuando una resolución menor sea suficiente.

## 8. Gates de release Android

Un release candidate no puede avanzar si falla cualquiera de estos gates:

1. `flutter analyze`.
2. Tests unitarios/widget.
3. Validación de la integración cartográfica y ausencia de fallback de teselas públicas.
4. Validación de configuración nativa.
5. Build APK.
6. Instalación en dispositivo/emulador.
7. Apertura de `Mapa` sin crash.
8. Navegación fuera de `Mapa` y regreso sin crash.
9. Carga de la fuente cartográfica sin error nativo.
10. Validación offline.
11. GPS/foreground tracking.
