# España Outdoor — estado técnico

Revisión de la arquitectura de routing: 31/10/2026. Este documento separa integración de código de validación física en Android.

## Objetivo MVP

Android primero. El criterio de aceptación es un APK instalable con mapa Mapbox, GPS, planificación de rutas online/offline, descargas cartográficas y de routing, y funcionamiento demostrable sin cobertura.

## Arquitectura cartográfica y routing

- Mapbox Maps SDK (mapbox_maps_flutter 3.33.0) proporciona estilos y teselas cartográficas.
- Mapbox Navigation SDK v3.33.0 se integra en Android mediante Kotlin y MethodChannel.
- La app conserva el contrato Dart RoutingService; el adaptador Android invoca el motor nativo Mapbox Navigation.
- El routing peatonal usa el perfil mapbox/walking.
- La descarga offline incluye estilo, teselas de mapa y tileset de routing en un único TileStore compartido.
- No existe dependencia de un VPS ni de un ordenador doméstico para el cálculo de rutas.
- Valhalla queda fuera del camino activo del MVP. ops/valhalla se conserva como referencia opcional y no debe desplegarse como requisito de producción.

## Alcance de la descarga

La implementación inicial conserva una región de prueba delimitada en Córdoba (zoom 8–15). No representa mapas ni routing offline de toda España. La ampliación debe hacerse mediante regiones explícitas seleccionadas y descargadas por el usuario.

## Seguridad y configuración

- MAPBOX_ACCESS_TOKEN es el token público usado en runtime.
- MAPBOX_DOWNLOADS_TOKEN es un secreto de compilación de Maven con permiso Downloads:Read; no debe entrar en Git ni en el APK.
- CI necesita MAPBOX_DOWNLOADS_TOKEN para resolver Navigation SDK.
- No incluir tokens privilegiados en Dart, Kotlin ni configuración versionada.

## Validación pendiente

| Comprobación | Estado |
|---|---|
| Contrato Dart RoutingService | Integrado en rama de trabajo |
| Adaptador Android MethodChannel | Integrado; requiere compilación |
| Dependencia Navigation SDK 3.33.0 | Configurada; requiere resolver Maven con token |
| Repositorio Maven privado Mapbox | Configurado; requiere secreto de CI |
| Descarga compartida Maps + routing en TileStore | Código integrado; requiere compilación y comprobación |
| Cálculo online | Requiere prueba real con token y conectividad |
| Cálculo offline de ruta nueva en Córdoba | Pendiente de prueba física Android |
| Reapertura en frío / reinicio / modo avión | Pendiente de evidencia en dispositivo |
| Cobertura fuera de Córdoba | No implementada ni declarada |
| Integración equivalente iOS | Fuera del MVP Android actual |

## Siguientes verificaciones

1. Añadir el secreto GitHub Actions MAPBOX_DOWNLOADS_TOKEN con permiso Downloads:Read.
2. Ejecutar CI y corregir cualquier incompatibilidad real de las APIs Kotlin/Gradle.
3. Generar e instalar el APK staging en el dispositivo Android.
4. Descargar Córdoba y comprobar una ruta nueva en modo avión tras cierre forzado.
5. Solo después de validar esta región, diseñar descargas regionales ampliables por el usuario.

No se marca routing offline como completado hasta disponer de evidencia reproducible del dispositivo.
