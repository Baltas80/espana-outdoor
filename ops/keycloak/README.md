# Keycloak development stack

This stack is for local integration testing only. Production must run Keycloak behind TLS/reverse proxy, with a managed PostgreSQL database, backups, monitoring and a controlled realm configuration.

## Start

Set secrets in the shell or an untracked `.env` file:

```bash
export KEYCLOAK_DB_PASSWORD='change-me'
export KEYCLOAK_ADMIN_PASSWORD='change-me-too'
docker compose up -d
```

Keycloak is available on `http://127.0.0.1:8080`.

Create an OIDC realm/client in the admin console using the redirect URI appropriate for the target platform. Do not commit exported realm files containing users, secrets or environment-specific callback URLs.

The Flutter client consumes the standard discovery endpoint through `OIDC_ISSUER` and uses Authorization Code + PKCE.


## Mobile account registration

The Flutter app uses the existing `flutter_appauth` Authorization Code + PKCE flow. It does not collect or store account passwords. To allow new accounts:

1. In the Keycloak admin console, open the `espana-outdoor` realm and enable **User registration** under the realm's **Login** settings.
2. Configure the realm's password policy and email settings. Enable email verification when the deployment has working SMTP.
3. Keep the mobile client public (no client secret in the APK), enable the standard authorization-code flow, require PKCE with S256, and register the exact platform redirect URI.
4. Test both a new account and an existing account against the deployed issuer before releasing the app.

The in-app **Crear cuenta / iniciar sesión** button opens the hosted Keycloak authentication page. The Keycloak **Register** link is shown only when self-registration is enabled for that realm.

Los perfiles ya se han diseñado como datos centralizados en `services/user-profile`, almacenados en PostgreSQL y asociados al claim OIDC `sub`. Android y web consultan el mismo endpoint protegido; la app no guarda perfiles como fuente de verdad local.


## Cliente web y perfil compartido

La web estática `site/cuenta.html` utiliza el adaptador oficial `keycloak-js` en su versión fijada y el flujo Authorization Code + PKCE. Configura un cliente público independiente:

- **Client ID:** `espana-outdoors-web`
- **Valid redirect URIs:** `https://espanaoutdoor.es/cuenta.html` y únicamente las rutas adicionales que se vayan a utilizar.
- **Web origins:** `https://espanaoutdoor.es` (añade `https://www.espanaoutdoor.es` solo si ese origen sirve la web).
- **Standard Flow:** habilitado.
- **PKCE:** S256.
- **Client authentication:** desactivado; nunca se coloca un secreto de cliente en la web.

Android sigue usando el cliente público `espana-outdoors-mobile` y el mismo realm/issuer `espana-outdoor`. Habilita **User registration** en la configuración de Login del realm y prueba el alta, la verificación de email y el acceso con ambos clientes.

### Audience de la API

El servicio de perfiles valida tokens cuyo audience es `espana-outdoor-api`. Configura ese audience mediante el mapper/scope de audiencia para los clientes web y móvil. No sustituyas la validación del servidor por una comprobación del token en el navegador o en Flutter.

### API y datos compartidos

- `GET /v1/me/profile`: lee el perfil de la identidad autenticada.
- `PUT /v1/me/profile`: crea o actualiza el perfil asociado al mismo `sub`.
- API pública a través del proxy HTTPS: `https://api.espanaoutdoor.es/v1/me/profile`.
- Los cambios en web se ven al volver a abrir el perfil en Android y viceversa, porque ambos usan el mismo registro PostgreSQL.
- El servicio se desplegará desde `services/user-profile`; el puerto de contenedor no debe exponerse directamente a Internet.

Los tokens del navegador se mantienen en memoria a través del adaptador de Keycloak. Los campos de perfil son datos públicos: no introduzcas contraseñas, direcciones privadas ni otra información sensible.
