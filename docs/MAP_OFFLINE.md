# Cartografía y modo offline

## Estado actual

MapLibre Flutter mediante `maplibre_gl` es el único motor cartográfico autorizado del proyecto. El estilo se carga desde `MAP_STYLE_URL` (HTTPS), desde `MAP_STYLE_JSON` en builds controladas o desde un asset de la aplicación mediante `asset://`.

La configuración predeterminada usa el estilo Liberty de OpenFreeMap. El renderizado online depende de la conexión y de los recursos remotos del estilo.

## Modo offline

El modo offline cartográfico no se considera implementado ni validado actualmente. No debe presentarse como funcional hasta que exista una estrategia de almacenamiento local compatible con MapLibre, se compruebe la disponibilidad de fuentes, glifos y sprites, y se valide en Android con Wi-Fi y datos móviles desactivados.

Las funciones críticas independientes de la cartografía, como la geometría de una ruta activa y los datos de seguridad que estén guardados localmente, deben mantener su propio estado y fecha de actualización.

## Requisitos para una implementación futura

- Mantener MapLibre como único motor.
- Elegir un mecanismo de descarga y almacenamiento que sea compatible con la versión de `maplibre_gl` instalada.
- No usar servidores públicos de teselas de OpenStreetMap para descargas masivas.
- Mostrar progreso, errores, espacio necesario, reintentos y estado de integridad.
- Verificar que estilo, fuentes, sprites y teselas funcionan sin red.
- Probar apertura, navegación por el mapa y recuperación tras perder conexión en un dispositivo Android real.
- No marcar la funcionalidad como terminada solo porque el APK compile.

## Evidencia

La revisión documental remota no acredita una prueba completa de cartografía offline en dispositivo. Hasta que se aporte esa evidencia, el estado correcto es: **mapa online configurado; modo cartográfico offline pendiente**.
