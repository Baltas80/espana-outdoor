# España Outdoor — estado técnico

Última revisión del repositorio remoto: 29/10/2026. Este documento distingue inspección del repositorio de validaciones ejecutadas en dispositivos.

## Objetivo MVP

Android primero. El criterio de aceptación es un APK instalable que abra el mapa, renderice cartografía real, permita usar GPS y rutas, y gestione correctamente errores y pérdida de conectividad.

## Arquitectura cartográfica actual

- Motor cartográfico en la rama principal tras esta migración: **Mapbox**, mediante `mapbox_maps_flutter`.
- El estilo y la clave de acceso deben configurarse mediante los mecanismos de compilación previstos; no incluir credenciales privilegiadas en el repositorio.
- La experiencia offline se apoya en las capacidades offline nativas de Mapbox. Deben comprobarse descarga, persistencia, reapertura en frío y funcionamiento en modo avión por separado.
- Que se descargue una región o se compile el APK no demuestra por sí solo cobertura nacional ni funcionamiento offline correcto.
- El routing se configura externamente mediante `VALHALLA_BASE_URL`; la integración y las respuestas reales deben validarse.
- Android es la plataforma prioritaria del MVP.

## Estado del código revisado

- La aplicación utiliza una superficie Mapbox compartida para mapa, planificación y detalle de rutas.
- Se conservan los modelos y capacidades de GPS, grabación de recorridos, GPX, Valhalla y los módulos de seguridad.
- La infraestructura de distribución cartográfica anterior y las abstracciones que no forman parte de la solución activa se retiran en esta rama.
- La existencia de una pantalla cartográfica o la compilación de un APK no demuestra por sí sola que el mapa funcione en un dispositivo, que una descarga se pueda volver a abrir offline ni que exista cobertura nacional.
- La comunidad social es una propuesta de producto; sus fases no deben considerarse implementadas hasta pasar sus criterios y pruebas.

## Validación disponible

| Comprobación | Estado |
|---|---|
| Inspección remota de código y configuración | Parcial; véase la rama de consolidación y sus cambios |
| Análisis estático Dart | Consultar el estado de CI del commit vigente |
| Pruebas automatizadas | Consultar el estado de CI del commit vigente |
| Compilación APK | Consultar el estado del workflow Android staging del commit vigente |
| Instalación en dispositivo Android | No declarada hasta disponer de evidencia |
| Mapa online en OPPO | No declarado hasta comprobarlo en el dispositivo |
| Mapa descargado, reapertura en frío y modo avión | Prueba física pendiente para el commit vigente |
| Routing real con Valhalla | No declarado hasta comprobar endpoint y respuesta |

## Pendientes prioritarios

1. Confirmar que CI, análisis, pruebas y APK de staging corresponden al HEAD vigente de la rama.
2. Instalar el APK resultante en Android y comprobar el mapa online, permisos y GPS.
3. Descargar un área de prueba, cerrar por completo la aplicación, reabrir sin conexión y comprobar la cartografía en modo avión.
4. Confirmar el alcance real de las regiones offline; no inferir cobertura nacional a partir de una zona de prueba.
5. Verificar routing con un endpoint real de Valhalla configurado.
6. Auditar autenticación móvil/web, perfil, backend Go, PostgreSQL y permisos antes de iniciar la comunidad descrita en la issue #11.

## Criterio de seguridad

No incluir secretos en código o Git. Respetar licencias y condiciones de uso de la cartografía. No marcar funcionalidades como completadas sin evidencia reproducible. Las contribuciones comunitarias deben distinguirse de la información oficial y verificada.
