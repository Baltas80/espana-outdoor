# España Outdoor — Platform Foundation

## Estado y decisiones vigentes

La aplicación móvil usa infraestructura madura y mantiene la lógica de producto y seguridad separada de los proveedores externos.

| Capacidad | Base seleccionada | Responsabilidad de España Outdoor |
|---|---|---|
| Aplicación móvil | Flutter/Dart | UX, dominio y coordinación de funciones |
| Estado | Riverpod | Estado de las pantallas y controladores |
| Navegación | go_router | Navegación de la aplicación |
| Cartografía | Mapbox Maps SDK (`mapbox_maps_flutter`) | Integración de UI y comportamiento outdoor |
| Mapas sin conexión | Capacidades offline nativas de Mapbox | Descarga, progreso, persistencia y estado de regiones |
| GPS | geolocator y adaptadores existentes | Permisos, posición y grabación |
| Routing | Valhalla | Perfiles outdoor y reglas de producto |
| GIS backend | PostGIS cuando se requiera | Esquema de dominio y políticas |
| Identidad | Keycloak/OIDC | Adaptador de autenticación y roles |
| Billing | RevenueCat | Entitlements y planes |
| Meteorología | AEMET OpenData | Procedencia, frescura y adaptador |
| Datos ambientales | MITECO/OGC | Procedencia y adaptación de fuentes |
| Telemetría | OpenTelemetry/Sentry | Integración y política de privacidad |
| Métricas | Prometheus/Grafana | Dashboards y SLOs |

## Configuración cartográfica

El estilo principal es Mapbox Outdoors. La compilación recibe `MAPBOX_ACCESS_TOKEN` desde la configuración protegida del entorno. No se debe mantener un segundo motor cartográfico ni un catálogo paralelo de descargas.

La validación offline requiere evidencia Android de descarga completada, persistencia, reapertura en frío y representación en modo avión. La compilación y la carga online no son pruebas suficientes.

## Entitlements

El catálogo de entitlements debe seguir siendo único para Free, Premium y Professional. Los productos de tienda se mapean a entitlements y la UI consume entitlements, no IDs de producto o precios.

## Límite de seguridad

El Risk Engine es determinista y conservador. La ausencia de datos o la presencia de datos caducados nunca deben convertirse en una aprobación. Los servicios oficiales de emergencia tienen prioridad. Rescue Link sigue siendo un flujo autorizado, temporal y revocable.

## Regla de producción

El entorno local de desarrollo debe ser reproducible. Producción requiere imágenes fijadas por digest, secretos gestionados, TLS, copias de seguridad, políticas de red, observabilidad y recuperación ante desastres. La configuración de desarrollo de Keycloak no se permite en producción.
