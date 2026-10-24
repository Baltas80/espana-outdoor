# España Outdoor — User Profile API

API de primera parte para mantener el mismo perfil público en la app Android y en la web. La identidad vive en Keycloak; el perfil editable vive en PostgreSQL y está asociado al claim OIDC `sub`. El cliente nunca puede elegir ni enviar el identificador de otro usuario.

## Endpoints

- `GET /healthz` — estado del proceso y conexión a la base de datos.
- `GET /v1/me/profile` — devuelve el perfil de la identidad autenticada; responde 404 si aún no existe.
- `PUT /v1/me/profile` — crea o actualiza el perfil del usuario autenticado.

El API requiere `Authorization: Bearer <access_token>`, valida el token con el issuer OIDC y el audience de API configurado. Los campos admitidos son `displayName`, `username`, `homeArea` y `bio`. Los nombres públicos son únicos. Los campos de identidad, creación y actualización los gestiona el servidor.

## Configuración

Variables obligatorias:

- `DATABASE_URL`: PostgreSQL de España Outdoor.
- `OIDC_ISSUER`: mismo issuer que utilizan la app y la web.
- `OIDC_AUDIENCE`: audience API, por ejemplo `espana-outdoor-api`. Los clientes OIDC móvil y web deben emitir access tokens con este audience mediante un mapper/scope de audiencia configurado en Keycloak.
- `CORS_ALLOWED_ORIGINS`: orígenes web permitidos, separados por comas y sin rutas; por ejemplo `https://espanaoutdoor.es,https://www.espanaoutdoor.es`.
- `PORT`: opcional, por defecto 8080.
- `ALLOW_HTTP_DEV=true`: solo para entornos locales de desarrollo sin TLS. Nunca activarlo en producción.
- `PROFILE_MIGRATION_PATH`: opcional, ruta SQL; por defecto `migrations/001_user_profiles.sql`.

## Keycloak

1. Crea un cliente público `espana-outdoors-mobile` para Android y conserva el flujo Authorization Code + PKCE del adaptador `flutter_appauth`.
2. Crea un cliente público `espana-outdoors-web`, con Standard Flow y PKCE S256, callbacks y Web Origins limitados a `https://espanaoutdoor.es` y el host web realmente desplegado.
3. Crea/configura el recurso de API `espana-outdoor-api` y agrega un audience mapper a los access tokens de ambos clientes.
4. Habilita el registro de usuarios en Login settings y configura política de contraseñas y correo de verificación/SMTP.
5. Mantén las credenciales de cliente confidencial fuera del navegador y del APK. Los clientes públicos no tienen client secret.

La app y la web deben usar el mismo realm/issuer. Un inicio de sesión crea/selecciona la misma identidad, pero una sesión de navegador y una sesión de app son sesiones distintas; Keycloak puede ofrecer SSO cuando la sesión del navegador está disponible.

## Despliegue

El servicio se ejecuta como contenedor y se publica detrás del proxy HTTPS bajo `https://api.espanaoutdoor.es/v1/me/profile`. En el proxy, enruta `/v1/me/profile` a este servicio y conserva `/v1/sources/*` para el source-gateway. No expongas el puerto del servicio directamente a Internet.

El servicio aplica validación de entrada, limitación de peticiones por sujeto, CORS de lista permitida, cabeceras de seguridad y consultas parametrizadas. Los perfiles se almacenan como datos no sensibles; no registra tokens, correos ni cuerpos de perfil. Elimina/exporta perfiles mediante un proceso de privacidad/soporte que deberá añadirse antes de la publicación pública.
