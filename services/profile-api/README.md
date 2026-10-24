# Shared Profile API

The API stores one public profile per authenticated OpenID Connect subject. Passwords, email credentials and account recovery remain with the identity provider (Keycloak). The service never accepts a user-supplied subject ID; it derives the subject from the verified bearer token.

## Runtime configuration

Required:
- OIDC_ISSUER: HTTPS issuer URL for the shared España Outdoor realm.
- OIDC_AUDIENCE: audience value that must be present in the access token for this API.
- DATABASE_URL: PostgreSQL connection URL with a least-privilege role that can create/use schema outdoor and table outdoor.user_profiles.

Optional:
- PORT: HTTP listen port, default 8080.
- WEB_ORIGINS: comma-separated HTTPS browser origins, default https://espanaoutdoor.es,https://www.espanaoutdoor.es.

The API performs OIDC discovery at startup, verifies bearer tokens, checks the PostgreSQL connection and fails startup if the profile table is missing. Apply infra/postgres/migrations/002-user-profiles.sql using a migration/admin role before deploying the service. The runtime database account should have only USAGE on schema outdoor and SELECT, INSERT, UPDATE on outdoor.user_profiles; it should not own the schema or have DDL privileges. Deploy behind an HTTPS reverse proxy. Do not expose the service directly over public plaintext HTTP.

## Keycloak requirements

Use one realm for web and Android users so both clients address the same account directory. Configure the web and Android clients as public clients with Authorization Code + PKCE and exact redirect URIs; do not place a client secret in the website or Android app. Add an audience mapper so access tokens issued to both clients contain the exact OIDC_AUDIENCE configured for this service. Verify the resulting access token against the deployed issuer and audience before enabling registration publicly.

Enable user self-registration in the realm only after configuring email verification, password policy, brute-force protection, password-reset flow and the public client redirect URIs. The web uses the Keycloak registration action; the mobile flow uses the same realm's hosted login/registration page.

## API contract

- GET /healthz — returns status ok only when PostgreSQL is reachable.
- GET /v1/me/profile — returns the authenticated user's profile; 404 means a profile has not been created.
- PUT /v1/me/profile — creates or updates that user's profile. The alias is case-insensitive and globally unique; duplicate aliases return 409.

The browser may call the API from the origins listed in WEB_ORIGINS. Native Android requests do not depend on browser CORS. For a dedicated runtime database role, provision it separately and grant only the permissions listed above. Restrict access to the database network, use managed backups, configure edge rate limits, and monitor health checks without logging access tokens or profile contents.

## Deployment note

This code is a deployable service, not a live deployment. It needs a production runtime, HTTPS hostname, database credentials, OIDC issuer/client configuration and DNS/reverse-proxy routing. The existing ops/keycloak stack is marked for local development only. Do not point the production app at the local Keycloak URL.
