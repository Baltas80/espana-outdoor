# España Outdoor — arquitectura móvil de alta gama

## 1. Renderer cartográfico Android

La aplicación Flutter utiliza exclusivamente MapLibre mediante `maplibre_gl` (versión declarada en `pubspec.yaml`). MapLibre es el motor de renderizado; PMTiles es un formato de distribución de datos vectoriales y no un renderer.

La pantalla de mapa debe gestionar estados de carga, error, permisos, falta de conectividad y ausencia de recursos. Los estilos, fuentes, sprites y recursos asociados deben ser compatibles con MapLibre. No se declara operativo el mapa offline hasta comprobar la descarga, la integridad, la disponibilidad local de recursos y la apertura del mapa sin red en Android.

## 2. Lifecycle del mapa

- Crear el controlador MapLibre cuando el widget esté listo.
- Evitar invocar el controlador después de desmontar el widget.
- Liberar listeners y streams al abandonar la pantalla.
- Mantener el viewport inicial estable durante la creación de la superficie nativa.
- Registrar y diagnosticar errores de estilo, recursos y lifecycle sin incluir secretos ni coordenadas sensibles en logs.

## 3. Integridad offline

Un paquete offline no se considera disponible hasta que termina la descarga y supera la validación de integridad.

Flujo esperado:

`NO_EXISTE -> DESCARGANDO -> DESCARGADO -> SHA256_VALIDADO -> REGISTRADO -> DISPONIBLE`

Los archivos parciales no se deben exponer como paquetes listos para usar. Debe verificarse el hash esperado publicado por el catálogo/manifiesto, conservar metadata de versión y procedencia y volver a validar los paquetes cuando corresponda. La existencia de una suma calculada localmente, sin valor esperado confiable, no acredita por sí sola la integridad de origen.

## 4. Foreground tracking

La grabación Android usa `geolocator` con notificación foreground y persistencia incremental para recuperar una sesión si el proceso se interrumpe. No se afirma que Android permita un proceso inmune a destrucción: el sistema operativo y las restricciones del fabricante pueden finalizar procesos.

La aceptación requiere permisos correctos, notificación persistente, recuperación de sesión y pruebas en Android 14/15/16. Si se requiere sobrevivir a escenarios no cubiertos por el plugin actual, evaluar un servicio de ubicación con engine dedicado sin sustituir la store de recuperación existente.

## 5. Caché predictiva

El caching predictivo debe operar sobre regiones o paquetes publicados en el catálogo compatible con el flujo PMTiles:

- analizar una ruta guardada o planificada;
- determinar los paquetes que intersectan la ruta y su corredor de seguridad;
- priorizar región actual y siguientes regiones;
- descargar solo con conectividad y batería adecuadas;
- validar integridad antes de activar cada paquete;
- evitar descargas duplicadas y no descargar toda España por una ruta local.

## 6. Elevación y hillshading

La implementación requiere una fuente DEM compatible y con licencia documentada, almacenamiento local, validación, cálculo/caché de sombreado e integración compatible con MapLibre. No se debe simular hillshading con degradados visuales ni asumir que el estilo contiene datos de elevación.

## 7. Rendimiento

- Evitar polling de alta frecuencia.
- Evitar cargar conjuntos de datos completos en RAM cuando se puedan leer por demanda.
- No recalcular elevación mientras el mapa está estático.
- Invalidar cachés solo cuando cambien los recursos relevantes.
- Mantener procesamiento pesado fuera del isolate de UI.
- Liberar streams y suscripciones al desmontar features.
- No usar imágenes gigantes cuando una resolución menor sea suficiente.

## 8. Gates de release Android

Un release candidate no puede avanzar si falla cualquiera de estos gates:

1. `flutter analyze`.
2. Tests unitarios/widget.
3. Comprobación anti-regresión del proveedor cartográfico.
4. Build APK.
5. Instalación en dispositivo/emulador.
6. Apertura de `Mapa` sin crash.
7. Navegación fuera de `Mapa` y regreso sin crash.
8. Estilo, fuentes, sprites y recursos cargados sin errores.
9. Descarga y verificación de un paquete offline real.
10. Apertura del mapa en modo avión.
11. GPS y foreground tracking comprobados.
