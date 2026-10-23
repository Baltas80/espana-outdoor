# ESPAÑA OUTDOOR — THIRD-PARTY SOFTWARE & LICENCE REGISTER

Estado: registro reconciliado con `pubspec.yaml`, `pubspec.lock` y los módulos Go presentes en `main`.
Fecha de revisión: 2026-10-23.
Alcance: dependencias de ejecución declaradas directamente por la aplicación y módulos Go declarados directamente por los servicios backend.

> Este documento es un registro de licencias de dependencias directas. No sustituye el inventario completo de dependencias transitivas que se debe generar para cada release.
> El repositorio contiene `pubspec.lock`, que fija las versiones resueltas de Dart. Este registro enumera dependencias directas; el lockfile no sustituye el inventario de licencias transitivas que debe generarse para cada release.
> Para una release, el inventario final debe incluir las dependencias transitivas realmente empaquetadas y sus notices/licencias.

## Criterio de registro

Para cada dependencia se conserva:
- nombre exacto del paquete/módulo;
- versión o constraint declarado en el repositorio;
- uso;
- licencia identificada;
- origen para verificación;
- obligación principal de distribución.

Las licencias permisivas indicadas aquí no eliminan la obligación de conservar avisos de copyright y texto de licencia cuando corresponda.

## SDK

| Componente | Constraint actual | Licencia | Verificación | Obligación |
|---|---|---|---|---|
| Flutter framework | Flutter >=3.38.1 | BSD-3-Clause | https://docs.flutter.dev/resources/faq | Conservar notices aplicables |
| Dart SDK | Dart >=3.10.0 <4.0.0 | BSD-3-Clause | https://github.com/dart-lang/sdk | Conservar notices aplicables |

## Dependencias directas de la aplicación Flutter

| Paquete | Constraint actual | Uso | Licencia | Verificación |
|---|---|---|---|---|
| flutter_svg | ^2.3.0 | Renderizado SVG | MIT | https://pub.dev/packages/flutter_svg/license |
| cupertino_icons | ^2.0.0 | Recursos de iconos Cupertino | MIT | https://pub.dev/packages/cupertino_icons |
| maplibre_gl | 0.27.1 | Renderizado cartográfico vectorial y fuentes PMTiles | BSD-3-Clause | https://pub.dev/packages/maplibre_gl/license |
| latlong2 | ^0.10.1 | Cálculos geográficos | Apache-2.0 | https://pub.dev/packages/latlong2 |
| flutter_riverpod | ^3.4.3 | Estado/inyección | MIT | https://pub.dev/packages/flutter_riverpod/license |
| go_router | ^18.0.2 | Navegación/deep links | BSD-3-Clause | https://pub.dev/packages/go_router/license |
| geolocator | ^14.1.1 | Localización GPS | MIT | https://pub.dev/packages/geolocator/license |
| connectivity_plus | ^7.3.1 | Estado de conectividad | BSD-3-Clause | https://pub.dev/packages/connectivity_plus/license |
| shared_preferences | ^2.5.5 | Preferencias no críticas | BSD-3-Clause | https://pub.dev/packages/shared_preferences/license |
| flutter_secure_storage | ^11.2.0 | Almacenamiento seguro local | BSD-3-Clause | https://pub.dev/packages/flutter_secure_storage/license |
| file_picker | ^13.1.0 | Selección de archivos | MIT | https://pub.dev/packages/file_picker/license |
| path_provider | ^2.1.6 | Rutas de almacenamiento | BSD-3-Clause | https://pub.dev/packages/path_provider/license |
| gpx | ^2.3.0 | Lectura/escritura GPX | Apache-2.0 | https://pub.dev/packages/gpx |
| hive_ce_flutter | ^2.4.0 | Persistencia local | Apache-2.0 + BSD-3-Clause | https://pub.dev/packages/hive_ce_flutter |
| url_launcher | ^6.3.2 | Apertura de URLs/acciones SO | BSD-3-Clause | https://pub.dev/packages/url_launcher/versions/6.3.2 |
| http | ^1.6.0 | Cliente HTTP | BSD-3-Clause | https://pub.dev/packages/http/license |
| crypto | ^3.0.7 | Hash/HMAC | BSD-3-Clause | https://pub.dev/packages/crypto/license |
| purchases_flutter | ^10.14.0 | Compras/entitlements RevenueCat | MIT | https://pub.dev/packages/purchases_flutter |
| purchases_ui_flutter | ^10.14.0 | UI de paywalls RevenueCat | MIT | https://pub.dev/packages/purchases_ui_flutter |
| background_downloader | ^9.6.3 | Descargas en segundo plano | BSD-3-Clause + MIT | https://pub.dev/packages/background_downloader |
| flutter_appauth | ^12.1.0 | OIDC/OAuth 2.0 mediante AppAuth | BSD-3-Clause | https://pub.dev/packages/flutter_appauth/license |
| sentry_flutter | ^9.30.1 | Telemetría de errores | MIT | https://pub.dev/packages/sentry_flutter/license |
| battery_plus | ^7.1.1 | Estado de batería | BSD-3-Clause | https://pub.dev/packages/battery_plus/versions/7.1.1 |
| sensors_plus | ^7.1.0 | Sensores de dispositivo | BSD-3-Clause | https://pub.dev/packages/sensors_plus/license |
| flutter_device_compass | ^2.2.0 | Brújula/heading | MIT | https://pub.dev/packages/flutter_device_compass |

### Nota de licencia relevante

`flutter_device_compass 2.2.0` se registra como MIT-only. La versión 2.1.2 tuvo temporalmente componentes Android bajo GPLv3, pero la documentación/changelog de 2.2.0 indica la reescritura clean-room y vuelta a MIT-only. El registro por tanto se basa específicamente en la versión actualmente declarada, 2.2.0.

`hive_ce_flutter 2.4.0` declara en pub.dev una combinación Apache-2.0 y BSD-3-Clause; no se reduce a una única licencia por simplificación.

`background_downloader 9.6.3` declara BSD-3-Clause y MIT en el metadata de pub.dev; se conserva la combinación en este registro.

## Dependencias directas del backend

### Source Gateway

| Módulo | Versión | Uso | Licencia | Verificación |
|---|---:|---|---|---|
| github.com/coreos/go-oidc/v3 | v3.21.0 | Verificación OIDC | Apache-2.0 | https://github.com/coreos/go-oidc |
| golang.org/x/time | v0.16.0 | Rate limiting | BSD-3-Clause | https://pkg.go.dev/golang.org/x/time/rate |

### Rescue Link

| Módulo | Versión | Uso | Licencia | Verificación |
|---|---:|---|---|---|
| github.com/coreos/go-oidc/v3 | v3.21.0 | Verificación OIDC | Apache-2.0 | https://github.com/coreos/go-oidc |
| github.com/jackc/pgx/v5 | v5.11.0 | Cliente PostgreSQL | MIT | https://github.com/jackc/pgx/blob/master/LICENSE |
| golang.org/x/time | v0.16.0 | Rate limiting | BSD-3-Clause | https://pkg.go.dev/golang.org/x/time/rate |

Los módulos indirectos registrados en `go.mod/go.sum` no se presentan aquí como si fueran dependencias directas. Deben quedar incluidos en el inventario transitive/SBOM de cada release.

## No incorporado / no distribuido como dependencia actual

Los siguientes elementos se eliminan del inventario de dependencias actuales porque no aparecen como dependencias directas en el `pubspec.yaml` o en los módulos Go actuales:

- pmtiles
- firebase_messaging
- Drift
- Martin
- H3
- Tippecanoe
- PowerSync

Pueden mantenerse en documentación arquitectónica como candidatos tecnológicos, pero no deben figurar como componentes licenciados del MVP actual mientras no formen parte de la dependencia efectiva.

## Política de release

Antes de distribuir una release:

1. reconciliar este registro con el estado de `pubspec.yaml`, `go.mod` y los artefactos realmente construidos;
2. generar inventario de dependencias transitivas y SBOM;
3. identificar licencias de todos los componentes redistribuidos, no solo de los directos;
4. conservar los notices requeridos por MIT, BSD-3-Clause, Apache-2.0 y cualquier otra licencia detectada;
5. bloquear la release ante una dependencia con licencia no verificada, desconocida o incompatible con la distribución prevista.

Este archivo es un registro técnico; no constituye asesoramiento jurídico.
