# España Outdoor

Plataforma móvil premium para naturaleza, rutas, seguridad, mascotas, fauna, conservación y emergencias.

## Estado

**MVP 0.1 en construcción activa.** La base actual incluye arquitectura por capas, navegación, mapa online, GPS, grabación de rutas, importación GPX, persistencia local de rutas, privacidad y CI. El sistema visual premium de España Outdoor ya está incorporado en la app y documentado en `docs/brand_system.md`.

## Prioridad de plataformas

España Outdoor se concentra en **Android para el MVP**. Android recibe primero la inversión de UX, GPS, navegación, mapas offline, SOS, Rescue Link, rendimiento y QA.

iOS/iPadOS queda preparado a nivel arquitectónico para una fase posterior. Web/PWA, Windows, macOS y Linux quedan fuera del alcance del MVP.

La arquitectura conserva interfaces abstractas para permitir en el futuro integraciones con wearables, Garmin, GPS externos, Bluetooth y sensores sin comprometer el foco móvil actual.

## Trabajo reciente

- Design System premium: tokens de marca, estados semánticos, light/dark/high-contrast y componentes base.
- Marca vectorial reutilizable en `assets/brand/espana_outdoor_mark.svg`.
- Integración del símbolo de marca en la experiencia principal.
- Atribución visible de OpenStreetMap en el mapa.
- ADR de cartografía/offline con decisión de no usar los servidores públicos de teselas OSM para descargas offline.
- Licencia propietaria incorporada para el código y activos propios; las dependencias de terceros conservan sus licencias.
- Registro inicial de dependencias y alternativas maduras en `docs/THIRD_PARTY_LICENSES.md`.
- Valhalla integrado mediante una interfaz `RoutingService`, con endpoint de producción externo al código.
- Infraestructura reproducible para generar y servir tiles de Valhalla para España.
- La integración de Mapbox incluye una región offline de prueba delimitada en Córdoba (zoom 8–15); la validación de reapertura en frío y la cobertura nacional siguen pendientes.
- RevenueCat conectado a la frontera de producto mediante entitlements Free/Premium/Professional.
- OpenID Connect integrado mediante un adaptador provider-neutral preparado para Keycloak.
- Sentry integrado con PII desactivada y DSN inyectado en runtime.
- Risk Engine corregido para que la confianza represente realmente la completitud de los datos verificados.
- CI de seguridad reforzado con Dependabot, Gitleaks, Trivy y CodeQL para GitHub Actions.

## Alcance MVP

- Android.
- Offline-first para las funciones críticas.
- Mapas y GIS desacoplados del proveedor.
- Datos con procedencia, fecha de actualización y nivel de confianza.
- Seguridad y privacidad desde el diseño.
- Importación y análisis GPX con persistencia local.
- Grabación GPS de rutas directamente sobre el mapa.
- SOS, contactos de confianza y Rescue Link como módulos aislados y auditables.
- Reutilización de SDKs, APIs y software maduro en lugar de reinventar componentes.

## Stack inicial

- Flutter / Dart.
- Riverpod para estado.
- go_router para navegación.
- Mapbox Maps SDK (`mapbox_maps_flutter`) como único motor cartográfico, con regiones offline nativas mediante `OfflineManager` y `TileStore`.
- geolocator para ubicación.
- connectivity_plus para estado de conectividad.
- shared_preferences para preferencias no críticas.
- flutter_secure_storage para secretos y credenciales locales.
- Hive CE para persistencia local de rutas.
- GPX para importación/exportación.
- Valhalla 3.9.0 para routing/map matching.
- `background_downloader` como infraestructura de transferencias en segundo plano; no habilita por sí solo mapas sin conexión.
- RevenueCat para billing/entitlements.
- OpenID Connect para identidad; Keycloak es el proveedor de infraestructura objetivo.
- Sentry para errores/crashes.

Las versiones se mantienen deliberadamente en rangos compatibles y deben revisarse periódicamente antes de releases.

## Configuración de routing

El cliente no contiene una URL de routing fija. En desarrollo o release se inyecta mediante la variable segura/configurada por entorno:

```bash
flutter run --dart-define=VALHALLA_BASE_URL="$VALHALLA_BASE_URL"
```

Si no se configura, el routing permanece deshabilitado de forma explícita en lugar de utilizar un proveedor no verificado.

## Configuración cartográfica

Todas las vistas cartográficas usan el estilo Mapbox Outdoors y requieren `MAPBOX_ACCESS_TOKEN` inyectado durante la compilación. Las descargas offline usan `OfflineManager` y `TileStore`; su disponibilidad, cuota y coste dependen de la cuenta y de las condiciones de Mapbox.

La región de prueba de Córdoba fue reportada históricamente como funcional sin conexión en un OPPO. Esa prueba de concepto no acredita el APK actual, la reapertura en frío, el cálculo de rutas offline ni la cobertura nacional; esos criterios requieren una validación específica.

## Identidad OIDC / Keycloak

La aplicación no implementa autenticación casera. La configuración se inyecta desde el entorno aprobado:

```bash
--dart-define=OIDC_ISSUER="$OIDC_ISSUER"
--dart-define=OIDC_CLIENT_ID="$OIDC_CLIENT_ID"
--dart-define=OIDC_REDIRECT_URI="$OIDC_REDIRECT_URI"
```

El flujo objetivo es Authorization Code + PKCE con almacenamiento seguro gestionado por el componente OIDC maduro. Los secretos de clientes confidenciales permanecen exclusivamente en backend/infraestructura.

La app Flutter también puede consultar el perfil canónico de la API de comunidad con el access token OIDC:

```bash
--dart-define=COMMUNITY_API_BASE_URL="$COMMUNITY_API_BASE_URL"
```

La API debe usar el mismo issuer/realm que la app y aceptar la audiencia `espana-outdoor-api`. El cliente móvil registrado en el realm de desarrollo se llama `espana-outdoors-mobile` y utiliza el redirect URI `com.espanaoutdoors://oauth2redirect`. No configures una URL de API de producción hasta que exista y se haya validado el despliegue real. Sin `COMMUNITY_API_BASE_URL`, el inicio de sesión OIDC puede funcionar, pero el perfil compartido se mostrará como no disponible.

## Billing / Free / Premium / Professional

RevenueCat proporciona la capa de billing y España Outdoor consume solamente estos entitlements:

- `free`
- `premium`
- `professional`

El código de producto de las tiendas, precios y promociones no se reparte por la aplicación. La frontera de producto se mantiene en `OutdoorEntitlement` y `EntitlementGate`.

## Observabilidad

Sentry se habilita únicamente cuando se inyecta `SENTRY_DSN`:

```bash
--dart-define=APP_ENV=production \
--dart-define=SENTRY_DSN="$SENTRY_DSN"
```

`sendDefaultPii` permanece desactivado. No se deben registrar coordenadas de emergencia, ubicaciones sensibles de fauna, tokens ni secretos en eventos de observabilidad.

## Infraestructura Valhalla

`ops/valhalla/` contiene la infraestructura reproducible. Los datos PBF, tiles, extracts y el JSON generado de configuración quedan fuera de Git.

```bash
cd ops/valhalla
./build-config.sh
./build-spain.sh
docker compose up -d
```

El extracto de España procede de Geofabrik/OSM y debe gestionarse con las obligaciones de licencia y atribución correspondientes. La versión de Valhalla está fijada a `3.9.0` para reproducibilidad.

## Estructura

```text
lib/
  app/          aplicación, tema, marca y routing
  core/         modelos y servicios transversales
  domain/       entidades y reglas de dominio
  features/     funcionalidades de producto
  infrastructure/ adaptadores externos: routing, auth, billing y fuentes
  main.dart
```

## Web pública

La carpeta `site/` contiene la web pública de España Outdoor, independiente de la aplicación Flutter. Está preparada para hosting estático y para `espanaoutdoor.es`. El sitio reutiliza la identidad visual del proyecto, mantiene sus recursos dentro de `site/assets` y puede desplegarse con Cloudflare Pages u otro proveedor estático.


## Estado verificable de Android y cartografía (14/11/2026)

La rama `main` incorpora Mapbox y la descarga de una región de prueba de Córdoba. La descarga de teselas y el cálculo de rutas offline son capacidades distintas: el proveedor de routing actualmente integrado usa Valhalla mediante un endpoint online. La integración nativa de Mapbox Navigation offline sigue pendiente de portar desde la PR #25, cuya rama está divergida de `main` y no debe fusionarse sin actualizar y validar sus cambios.

La firma de producción Android ahora falla de forma segura si no se configura una clave release dedicada. El workflow Release candidate comprueba la huella SHA-256 del APK y del AAB; requiere los secretos documentados en `docs/ANDROID_RELEASE_SIGNING.md`. Los artefactos CI/staging firmados con debug son exclusivamente de prueba y no deben distribuirse.

Las PR #43, #44 y #45 están integradas, junto con las actualizaciones de seguridad de pgx, CodeQL y las imágenes builder Go. Los checks de CI, Android staging y seguridad pasaron en las ramas de las PR #44 y #45 antes de fusionarlas. La PR #47, integrada en `c7b73ba`, añade perfiles de Senderismo, BTT y Cicloturismo. CI, Android staging y Security baseline pasaron en su rama antes de la fusión; la validación contra un endpoint Valhalla real sigue pendiente.

La revisión detallada, los límites de evidencia y los siguientes criterios de aceptación están en `docs/PROJECT_STATUS.md` y `docs/MAP_OFFLINE.md`. El inventario de la carpeta cartográfica del ordenador es independiente del inventario Git; no se deben deducir faltantes locales a partir de los archivos versionados.
