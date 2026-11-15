# España Outdoor — estado técnico

Última revisión: **15/11/2026 06:20 CET**. Rama de referencia: `main`. HEAD funcional observado antes de la actualización documental: `8acb12a32cff5c557147045552683551f6eb58f6`; actualización documental posterior integrada en `179a961c345d3d5c5d6f409856ec255e5d697c6d`.

Este documento distingue código integrado, pruebas automatizadas, validación de emulador, validación física y configuración externa. Un workflow verde o un APK compilado no equivalen a aceptación de producción.

## Objetivo de entrega

Android Flutter es el producto prioritario. La web pública debe seguir funcionando y compartir identidad/perfil canónico con Android. Cartografía y routing offline son puertas de calidad: no se aceptan sin evidencia de mapa renderizado, ruta nueva calculada sin conectividad y persistencia tras cierre/reinicio.

## Estado de integración en main

- PR #44: protección de firma release Android integrada. El build de producción exige keystore dedicado y comprobación de huella; no se ha validado todavía un release firmado con los secretos reales.
- PR #47: perfiles de Senderismo, BTT y Cicloturismo integrados. La respuesta real del endpoint Valhalla para cada perfil sigue pendiente de verificación de producción.
- PR #50: staging de Dependabot integrado. Las compilaciones sin credenciales Maven Mapbox se identifican como análisis/tests sin APK nativo validado.
- PR #58: API canónica de perfiles integrada. Source Gateway incluye `GET /v1/me`, `PATCH /v1/me`, migración PostgreSQL y adaptador Flutter. El subject procede del token verificado y el UUID de perfil lo genera PostgreSQL. El servicio no se considera desplegado hasta verificar PostgreSQL y HTTPS reales.

HEAD de referencia: `8acb12a32cff5c557147045552683551f6eb58f6`.

## Cartografía y navegación offline

### Estado de main

- Mapbox es el motor cartográfico de Flutter.
- La página offline puede descargar una región de prueba de Córdoba usando Mapbox OfflineManager/TileStore.
- El routing de main continúa dependiendo de Valhalla online. No debe presentarse como cálculo offline.
- Una región de Córdoba no demuestra cobertura nacional.

### PR #61 — nueva implementación Mapbox Navigation

Rama: `feat/mapbox-offline-routing-final-20261114`  
HEAD observado: `5549aefb13072bf6e6c722dbd5025191a64aad00`  
[PR #61](https://github.com/Baltas80/espana-outdoor/pull/61)

La rama está 61 commits por delante y 0 por detrás de main según la comparación observada tras incorporar el commit documental 179a961. Incluye:

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
- Nueva ejecución **43680940651** sobre HEAD `5549aef`: Android staging estaba en el paso de compilación APK en la última consulta; Security baseline **43680940665** terminó correctamente.

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

El cliente web se ha ajustado para usar Authorization Code + PKCE y solicitar únicamente scopes de access token (`profile email`), sin pedir `openid` ni consumir un ID token que la SPA no valida. Usa `sessionStorage` y no guarda refresh token ni client secret.

Último commit conocido tras esta corrección: `7f39db5258e133852f97bd4013ee4fcf77cbaa80`. La CI de ese nuevo HEAD aún debe confirmarse.

### PR #65 — endurecimiento del token de API

[PR #65](https://github.com/Baltas80/espana-outdoor/pull/65), abierta y con CI en curso.

El backend exige el claim JWT `typ=Bearer` después de validar firma, issuer y audience. Rechaza ID tokens, refresh tokens y tokens sin tipo explícito. La configuración del proveedor debe incluir una audiencia dedicada al resource server/API en el access token; no debe depender solo del client ID público.

### Bloqueos externos de identidad

- Registrar redirect URIs exactos web y Android en el proveedor OIDC.
- Exigir PKCE S256; configurar registro/autoregistro solo si se desea ofrecer creación pública de cuentas.
- Configurar audience mapper de la API y comprobar que el access token contiene la audiencia esperada y `typ=Bearer`.
- Desplegar Source Gateway con PostgreSQL TLS, migración aplicada, issuer/audience/roles, credencial AEMET y CORS restringido.
- Verificar `GET/PATCH /v1/me` con la misma cuenta en web y Android.

Issue de seguimiento: [#55](https://github.com/Baltas80/espana-outdoor/issues/55).

## Dispositivo físico

Issue [#63](https://github.com/Baltas80/espana-outdoor/issues/63).

El script `tool/test_mapbox_oppo_routes.ps1` está en la rama de PR #61, no en main. Ejecuta `flutter test` y valida el test app de integración debug; no instala por sí mismo el APK release exacto de CI. Debe ampliarse para aceptar una ruta de APK, verificar SHA-256/package/versionCode, instalar ese artefacto y separar el smoke release de la prueba de integración debug.

No hay una nueva prueba física del OPPO acreditada en este estado.

## Backend, routing y despliegue

- Source Gateway: código de perfiles integrado; despliegue y PostgreSQL de producción no verificados.
- Valhalla: perfiles de routing integrados en el cliente; respuesta real de `https://routing.espanaoutdoor.es/status` y rutas BTT/cicloturismo no verificadas en este ciclo.
- Rescue Link: endpoint de producción no verificado.
- Cloudflare Pages: preview de PR #64 confirmado en comentarios del bot para el commit anterior; no confundir preview con publicación de identidad operativa.
- Release Android: firma dedicada protegida por configuración; falta ejecución con secretos reales y verificación de huella.

## Hoja de ruta priorizada

1. Cerrar la ejecución 43676480595 e inspeccionar artefactos de routing/renderizado de PR #61.
2. Corregir el smoke visual si no demuestra calles/etiquetas y recursos offline completos.
3. Implementar la instalación y validación del APK release exacto en OPPO (issue #63).
4. Ejecutar prueba física tras cierre forzado y reinicio; no cerrar offline sin ella.
5. Integrar PR #65 después de CI y revisión; actualizar la configuración de audiencia API en el proveedor.
6. Completar CI de PR #64 y verificar callback PKCE con el proveedor real.
7. Provisionar PostgreSQL y desplegar Source Gateway; verificar `/healthz` y `/v1/me` por HTTPS.
8. Probar la misma cuenta y perfil en web y Android.
9. Verificar Valhalla real para senderismo, BTT y cicloturismo.
10. Implementar routing offline de bicicleta y ampliar la cobertura regional.
11. Generar un release firmado, instalarlo y realizar regresión final.

## Criterio de seguridad

No incluir secretos en código, commits, artefactos públicos ni logs. Los APK de staging firmados con debug son solo para pruebas. No declarar producción por una compilación correcta, un preview de Pages o una prueba de routing aislada.
