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

The profile form currently stores its public profile fields on the device through the app's existing `shared_preferences` dependency. This is separate from Keycloak identity: cross-device profile synchronisation requires a protected profile API and persistent server-side storage, neither of which is provided by the current source-gateway API.
