# España Outdoor — estado técnico

Última revisión: **15/11/2026 07:25 CET**. Rama de referencia: `main`. HEAD de `main`: `179a961c345d3d5c5d6f409856ec255e5d697c6d`.

Este documento distingue código integrado, pruebas automatizadas, validación de emulador, validación física y configuración externa. Un workflow verde o un APK compilado no equivalen a aceptación de producción.

## Objetivo de entrega

Android Flutter es el producto prioritario. La web pública debe seguir funcionando y compartir identidad/perfil canónico con Android. Cartografía y routing offline son puertas de calidad: no se aceptan sin evidencia de mapa renderizado, ruta nueva calculada sin conectividad y persistencia tras cierre/reinicio.

## Estado de integración en main

- PR #44: protección de firma release Android integrada. El build de producción exige keystore dedicado y comprobación de huella; no se ha validado todavía un release firmado con los secretos reales.
- PR #47: perfiles de Senderismo, BTT y Cicloturismo integrados. La respuesta real del endpoint Valhalla para cada perfil sigue pendiente de verificación de producción.
- PR #50: staging de Dependabot integrado. Las compilaciones sin credenciales Maven Mapbox se identifican como análisis/tests sin APK nativo validado.
- PR #58: API canónica de perfiles integrada. Source Gateway incluye `GET /v1/me`, `PATCH /v1/me`, migración PostgreSQL y adaptador Flutter. El subject procede del token verificado y el UUID de perfil lo genera PostgreSQL. El servicio no se considera desplegado hasta verificar PostgreSQL y HTTPS reales.

HEAD de referencia: `179a961c345d3d5c5d6f409856ec255e5d697c6d`.

## Cartografía y navegación offline

### Estado de main

- Mapbox es el motor cartográfico de Flutter.
- La página offline puede descargar una región de prueba de Córdoba usando Mapbox OfflineManager/TileStore.
- El routing de main continúa dependiendo de Valhalla online. No debe presentarse como cálculo offline.
- Una región de Córdoba no demuestra cobertura nacional.

### PR #61 — nueva implementación Mapbox Navigation

Rama: `feat/mapbox-offline-routing-final-20261114`  
HEAD observado: `b1878f7c65e16cd1fd88e79c2cb895fea65c8f56`  
[PR #61](https://github.com/Baltas80/espana-outdoor/pull/61)

La rama está 86 commits por delante y 0 por detrás de main según la comparación del 15/11/2026 07:25 CET. Incluye:

- Mapbox Navigation Android 3.35.0 / Native 324.35.0, Maps 11.35.0 y Common 24.35.0 en variante `common-ndk27`.
- TileStore persistente compartido entre Maps y Navigation.
- Descarga de style pack, teselas visibles y recursos de routing peatonal para Córdoba.
- Routing nativo peatonal con origen explícito `online` o `offline`.
- Valhalla conservado para BTT, cicloturismo y map matching GPX online.
- Verificadores de Gradle/Mapbox, prueba del parche de expiración, controles de captura Android y timeout nativo de 45 s para las solicitudes de ruta.
- Workflows de solo lectura; no deben persistir credenciales Git.

### Evidencia automatizada observada

Ejecución Android staging **43667786016**:
- APK staging compilado y verificado.
- Las bibliotecas Mapbox requeridas están empaquetadas.
- Se encontró una sola `libc++_shared.so` por ABI inspeccionado.
- Los símbolos JNI requeridos por Navigation están presentes en Common.
- El smoke nativo inicial arrancó la aplicación, pero su captura visual era casi uniforme y no demuestra cartografía completa.
- La integración obtuvo una ruta online y una ruta nueva con `source=offline` en modo avión (1.109,662 m; 66 puntos).
- La prueba falló al capturar el platform view porque faltaba `convertFlutterSurfaceToImage()`. La ruta offline quedó registrada antes del fallo visual.

Ejecución de revalidación **43676480595**:
- APK staging y verificación completados.
- Smoke nativo del mapa completado.
- El paso de integración de rutas permaneció en ejecución durante una espera anormalmente larga y el endpoint de logs no proporcionó un log descargable; la ejecución fue cancelada al actualizar el código.
- Se añadió timeout de 45 s a la solicitud nativa, prueba unitaria de timeout, límite de 30 min al paso de emulador y 60 min al job Android.
- Ejecución **43682026291** sobre HEAD `8af3b035` generó y verificó el APK; el smoke nativo arrancó y la fase online calculó una ruta de 767,757 m y descargó la región. La fase offline terminó fallando antes de emitir `source=offline`. El artefacto de evidencia confirma que la segunda instalación/debug build comenzó, pero no contiene salida de test offline; además Flutter registró `adb uninstall failed: DELETE_FAILED_INTERNAL_ERROR` para `com.example.espana_outdoors`. El harness se corrigió en commits posteriores para resolver el package de integración desde el `namespace`, detenerlo antes de relanzar, evitar `pub get` entre fases y acotar cada fase a 8 minutos. El smoke ahora espera `MAPBOX_MAP_STYLE_LOADED`, `MAPBOX_MAP_FULL_FRAME` y `MAPBOX_MAP_IDLE`. Estas correcciones aún necesitan una ejecución nueva sobre el HEAD final `b1878f7c`.

Por tanto, existe evidencia de routing offline en emulador, pero la aceptación visual está pendiente. La captura anterior no debe usarse como prueba de mapa renderizado.

### Puertas pendientes de PR #61

1. Terminar el job `Android online and offline route integration` de la ejecución 43676480595.
2. Inspeccionar la captura PNG del viewport real y exigir diversidad/entropía de píxeles, no solo que el archivo exista.
3. Confirmar carga offline del style pack, glyphs/sprites y teselas sin errores.
4. Instalar el APK release exacto en OPPO físico.
5. Repetir descarga, cierre forzado, modo avión, ruta nueva `OFFLINE`, renderizado y reinicio.
6. Fusionar solo después de CI completo y revisión de la evidencia. La validación física seguirá siendo necesaria antes de cerrar la aceptación offline.

### Alcance que no cubre PR #61

- Routing offline BTT/cicloturismo: issue #62.
- Cobertura cartográfica nacional.
- Validación física del APK release.
- Navegación turn-by-turn completa en todos los perfiles.

## Identidad y perfiles web/Android

### Backend integrado

La PR #58 incorpora la API de perfil en Source Gateway:
- `GET /v1/me` crea/recupera el perfil asociado al subject OIDC verificado.
- `PATCH /v1/me` actualiza únicamente `displayName`.
- Email solo se importa si `email_verified=true`.
- El cliente no puede elegir subject, UUID ni email.
- PostgreSQL genera el UUID canónico.

El código está integrado, pero no hay evidencia de despliegue operativo con PostgreSQL real.

### PR #64 — cliente web

[PR #64](https://github.com/Baltas80/espana-outdoor/pull/64), todavía draft.

Incluye `/cuenta.html`, cliente web PKCE, callback, llamadas a `/v1/me`, CSP/CORS y pruebas Node. El preview de Cloudflare Pages se desplegó correctamente en un commit anterior, pero no equivale a producción ni valida el realm OIDC.

El cliente web usa Authorization Code + PKCE y solicita scopes de access token (`profile email`), sin pedir `openid` ni consumir un ID token que la SPA no valida. Usa `sessionStorage` y no guarda refresh token ni client secret.

Último HEAD conocido: `6c6738946f42ce5a904628c45b9a43ea458a0888`. El workflow Web OIDC de un commit anterior pasó; CI general del HEAD actual sigue pendiente de confirmación.

### PR #68 — endurecimiento OIDC de Source Gateway y Rescue Link

[PR #68](https://github.com/Baltas80/espana-outdoor/pull/68), draft y con CI general en curso.

Incluye la implementación de #65 y añade validación de audiencia dedicada y `typ=Bearer` en Rescue Link. Los roles Rescue Link se limitan a `resource_access[RESCUE_LINK_OIDC_AUDIENCE].roles`; se rechazan roles de realm y de otros clientes. Compose comparte el `DATABASE_URL` TLS-aware con Source Gateway. En la ejecución 43685272980, Source Gateway y Rescue Link (`go test -race`, `go vet`) pasaron; Flutter y iOS seguían construyendo. Security baseline 43685272998 pasó. Falta terminar CI y configurar los audience mappers/client roles en Keycloak antes del despliegue.

### Bloqueos externos de identidad

- Registrar redirect URIs exactos web y Android en el proveedor OIDC.
- Configurar los audience mappers dedicados de Source Gateway y Rescue Link, y asignar roles de Rescue Link al cliente resource server correspondiente.
- Exigir PKCE S256; configurar registro/autoregistro solo si se desea ofrecer creación pública de cuentas.
- Configurar audience mapper de la API y comprobar que el access token contiene la audiencia esperada y `typ=Bearer`.
- Desplegar Source Gateway con PostgreSQL TLS, migración aplicada, issuer/audience/roles, credencial AEMET y CORS restringido.
- Verificar `GET/PATCH /v1/me` con la misma cuenta en web y Android.

Issue de seguimiento: [#55](https://github.com/Baltas80/espana-outdoor/issues/55).

## Dispositivo físico

Issue [#63](https://github.com/Baltas80/espana-outdoor/issues/63).

El script `tool/test_mapbox_oppo_routes.ps1` está en la rama de PR #61, no en main. Ejecuta `flutter test` y valida el test app de integración debug; no instala por sí mismo el APK release exacto de CI. Debe ampliarse para aceptar una ruta de APK, verificar SHA-256/package/versionCode, instalar ese artefacto y separar el smoke release de la prueba de integración debug.

El procedimiento físico está documentado en `docs/MAP_OFFLINE.md` y issue #63, pero no hay una nueva prueba del OPPO acreditada en este estado.

## Backend, routing y despliegue

- Source Gateway: código de perfiles integrado; despliegue y PostgreSQL de producción no verificados.
- Valhalla: perfiles de routing integrados en el cliente; respuesta real de `https://routing.espanaoutdoor.es/status` y rutas BTT/cicloturismo no verificadas en este ciclo.
- Rescue Link: endpoint de producción no verificado.
- Cloudflare Pages: preview de PR #64 confirmado en comentarios del bot para el commit anterior; no confundir preview con publicación de identidad operativa.
- Release Android: firma dedicada protegida por configuración; falta ejecución con secretos reales y verificación de huella.

## Hoja de ruta priorizada

1. Ejecutar Android staging sobre el HEAD final de PR #61 y revisar el nuevo artefacto visual y la fase offline.
2. Corregir el smoke visual si no demuestra calles/etiquetas y recursos offline completos.
3. Implementar la instalación y validación del APK release exacto en OPPO (issue #63).
4. Ejecutar prueba física tras cierre forzado y reinicio; no cerrar offline sin ella.
5. Terminar CI y revisar PR #68; actualizar la configuración de audiencias/roles en Keycloak antes de desplegar.
6. Completar CI de PR #64 y verificar callback PKCE con el proveedor real.
7. Provisionar PostgreSQL y desplegar Source Gateway; verificar `/healthz` y `/v1/me` por HTTPS.
8. Probar la misma cuenta y perfil en web y Android.
9. Verificar Valhalla real para senderismo, BTT y cicloturismo.
10. Implementar routing offline de bicicleta y ampliar la cobertura regional.
11. Generar un release firmado, instalarlo y realizar regresión final.

## Criterio de seguridad

No incluir secretos en código, commits, artefactos públicos ni logs. Los APK de staging firmados con debug son solo para pruebas. No declarar producción por una compilación correcta, un preview de Pages o una prueba de routing aislada.
