# España Outdoor — estado técnico

Última revisión del repositorio remoto: 28/10/2026. No se ha ejecutado Flutter/Android localmente durante esta intervención.

## Objetivo MVP

Android primero. El criterio de aceptación es un APK instalable que abra el mapa, renderice cartografía real, permita usar GPS y rutas, y gestione correctamente los errores y la pérdida de conectividad.

## Arquitectura cartográfica actual

- Motor cartográfico autorizado: MapLibre Flutter mediante `maplibre_gl: 0.27.1`.
- El estilo online se configura mediante `MAP_STYLE_URL` (HTTPS), `MAP_STYLE_JSON` o un asset controlado.
- El estilo predeterminado es Liberty de OpenFreeMap.
- El modo cartográfico offline está pendiente; no debe considerarse funcional ni anunciado como disponible.
- El routing se configura externamente mediante `VALHALLA_BASE_URL`.
- Android es la plataforma prioritaria del MVP.

## Estado del código revisado

- La carga del estilo ya no depende de un catálogo de paquetes cartográficos ni de un formato de archivo regional.
- Se han retirado el cargador específico anterior, los recursos de estilo ligados a ese flujo, el fixture de prueba y el pipeline de publicación asociado.
- La existencia de la pantalla MapLibre o la compilación de un APK no demuestra que el mapa funcione en un dispositivo ni que exista modo offline.
- La descarga genérica de datos, el almacenamiento de rutas y la cartografía son responsabilidades distintas. No se debe presentar una descarga como mapa utilizable sin verificar su integración con MapLibre.

## Validación disponible

| Comprobación | Estado de esta intervención |
|---|---|
| Inspección remota de código y configuración | Realizada parcialmente |
| Análisis estático Dart | No ejecutado |
| Pruebas automatizadas | No ejecutadas |
| Compilación APK | No ejecutada |
| Instalación en dispositivo Android | No ejecutada |
| Mapa online en OPPO | No verificado en esta intervención |
| Mapa con Wi-Fi y datos móviles desactivados | No verificado; modo offline pendiente |
| Routing real con Valhalla | No verificado |

## Pendientes prioritarios

1. Ejecutar análisis Dart y pruebas después de los cambios.
2. Compilar e instalar un único APK de staging.
3. Confirmar carga del estilo online y GPS en el OPPO.
4. Definir una nueva estrategia offline compatible con MapLibre y probar fuentes, glifos, sprites y teselas sin red antes de declararla operativa.
5. Mantener permisos, configuración Android, licencias y endpoints externos verificados.

## Criterio de seguridad

No usar servidores públicos de teselas de OpenStreetMap para descargas masivas. No inventar endpoints ni paquetes regionales. No marcar funciones como completadas sin evidencia reproducible.
