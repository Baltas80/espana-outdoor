# España Outdoor

Plataforma móvil premium para naturaleza, rutas, seguridad, mascotas, fauna, conservación y emergencias.

## Estado

**MVP 0.1 en construcción activa.** La base actual incluye arquitectura por capas, navegación, mapa, GPS, grabación de rutas, importación GPX, persistencia local de rutas, modo offline básico, privacidad y CI. El sistema visual premium de España Outdoor ya está incorporado en la app y documentado en `docs/brand_system.md`.

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
- Descargas offline regionales preparadas con `background_downloader`, incluyendo pausa/reanudación y persistencia de transferencias.
- El catálogo offline ya no contiene zonas ficticias: solo se muestran paquetes publicados por el backend configurado.
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
- MapLibre Flutter como motor cartográfico; el proveedor de estilos y teselas se configura mediante el entorno.
- geolocator para ubicación.
- connectivity_plus para estado de conectividad.
- shared_preferences para preferencias no críticas.
- flutter_secure_storage para secretos y credenciales locales.
- Hive CE para persistencia local de rutas.
- GPX para importación/exportación.
- Valhalla 3.9.0 para routing/map matching.
- background_downloader para transferencias offline móviles.
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

El estilo de MapLibre se configura mediante `MAP_STYLE_URL` (HTTPS) o `MAP_STYLE_JSON` para builds controladas. Por defecto se utiliza el estilo Liberty de OpenFreeMap. La disponibilidad online depende de la conectividad y de las condiciones del proveedor.

No se declara operativo el uso cartográfico offline: requiere una implementación y una prueba específicas de almacenamiento local.

## Identidad OIDC / Keycloak

La aplicación no implementa autenticación casera. La configuración se inyecta desde el entorno aprobado:

```bash
--dart-define=OIDC_ISSUER="$OIDC_ISSUER"
--dart-define=OIDC_CLIENT_ID="$OIDC_CLIENT_ID"
--dart-define=OIDC_REDIRECT_URI="$OIDC_REDIRECT_URI"
```

El flujo objetivo es Authorization Code + PKCE con almacenamiento seguro gestionado por el componente OIDC maduro. Los secretos de clientes confidenciales permanecen exclusivamente en backend/infraestructura.

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


## Estado verificable de Android y cartografía (26/10/2026)

La rama `main` contiene integración MapLibre, pero todavía no hay evidencia suficiente para afirmar que exista un APK de demostración validado en dispositivo o que la cartografía funcione sin conexión. La carga del estilo online se configura mediante `MAP_STYLE_URL`; el modo offline cartográfico queda pendiente de una implementación distinta y de pruebas reales.

La revisión técnica está registrada en `docs/PROJECT_STATUS.md`, `docs/MAP_OFFLINE.md` y `docs/OFFLINE_STRATEGY.md`. El identificador Android provisional y la firma de release debug deben resolverse antes de un release; los permisos de ubicación y los triggers de CI también necesitan corrección y comprobación.

El inventario de la carpeta cartográfica del ordenador es independiente del inventario Git. No se deben deducir faltantes locales a partir de los archivos versionados.
