# ESPAÑA OUTDOOR — TECHNOLOGY SELECTION

**Estado:** decisiones vigentes de la aplicación móvil.

## Decisiones adoptadas

| Área | Tecnología vigente | Responsabilidad |
|---|---|---|
| Cliente móvil | Flutter / Dart | Aplicación Android MVP; iOS en fase posterior |
| Estado | Riverpod | Estado y coordinación de funciones |
| Navegación de pantallas | go_router | Rutas y navegación de la interfaz |
| Cartografía | Mapbox Maps SDK mediante `mapbox_maps_flutter` | Renderizado, estilo y regiones offline |
| GPS | geolocator y adaptadores existentes | Posición y permisos |
| Routing | Valhalla mediante `VALHALLA_BASE_URL` | Cálculo de rutas verificables |
| GPX | `gpx` | Importación y exportación de recorridos |
| Persistencia local | Hive CE y almacenamiento existente | Datos locales y recuperación |
| Descargas | background_downloader | Descargas reanudables donde se utilice |
| Identidad | OIDC / Keycloak mediante adaptadores | Autenticación |
| API | servicios propios y gateways | Integración de fuentes |
| CI/CD | GitHub Actions | Análisis, pruebas y artefactos Android |

## Datos y procesamiento

- OSM puede ser una fuente de datos cuando se respeten su licencia, atribución y condiciones de uso.
- IGN/CNIG y las administraciones públicas son fuentes prioritarias para datos oficiales españoles.
- MITECO y organismos autonómicos aportan datos ambientales y de conservación.
- AEMET y organismos oficiales son las fuentes preferidas para meteorología y avisos.
- PostgreSQL + PostGIS y GDAL + PROJ son opciones para infraestructura GIS de backend cuando una necesidad concreta lo justifique.

## Cartografía offline

Mapbox es el único motor cartográfico. Las regiones sin conexión se gestionan mediante las capacidades offline nativas del SDK, con estados de descarga, almacenamiento local y validación en Android. No se mantendrá un catálogo cartográfico paralelo. Las licencias, la cobertura regional, el tamaño de descarga y el comportamiento en modo avión deben verificarse antes de considerar operativa una región.

No utilizar servidores públicos de teselas de OSM para descargas masivas.

## Routing

El proveedor previsto es Valhalla, configurado externamente mediante `VALHALLA_BASE_URL`. No se presentan líneas rectas como rutas calculadas. Si el endpoint no está configurado o falla, la interfaz debe comunicar el estado real. Mostrar GPX, calcular una ruta y ofrecer navegación activa son capacidades distintas.

## Código propio con valor diferencial

1. Evaluación explicable del riesgo de ruta y de las condiciones del día.
2. Compatibilidad y riesgo para mascotas.
3. Conservación y protección de localizaciones sensibles.
4. Rescue Link y control de acceso temporal a ubicación.
5. Integración de fuentes oficiales con procedencia y vigencia.
6. Sincronización local/remota y diseño de experiencia outdoor.

## Criterios para incorporar dependencias

Antes de añadir un paquete, verificar mantenimiento, compatibilidad Flutter/Dart, licencia, plataformas soportadas, necesidad real y cobertura de pruebas. No añadir otro motor cartográfico ni una segunda infraestructura de mapas offline.
