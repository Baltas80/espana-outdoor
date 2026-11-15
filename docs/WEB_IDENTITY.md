# Identidad web compartida

## Implementación

La página estática `/cuenta.html` utiliza OAuth 2.0 Authorization Code + PKCE (S256) como cliente público. Consulta el discovery OIDC del emisor, pero no solicita el scope `openid` ni consume un ID token: solo utiliza el access token destinado a la API. No contiene un client secret ni usa cookies de terceros.

- Emisor: `https://auth.espanaoutdoor.es/realms/espana-outdoor`
- Cliente público web dedicado: `espana-outdoors-web` (Android conserva `espana-outdoors-mobile`; ambos comparten el mismo realm y perfil canónico)
- Callback web: `https://espanaoutdoor.es/cuenta.html` y `https://www.espanaoutdoor.es/cuenta.html`
- API de perfiles: `https://api.espanaoutdoor.es/v1/me`
- Sesión del navegador: `sessionStorage`, nunca `localStorage`; no se solicita ni almacena refresh token.
- El backend valida firma, issuer, audiencia API y el claim `typ=Bearer` del access token. Los ID tokens (`typ=ID`) y refresh tokens no son credenciales válidas para la API; la exigencia de tipo y audiencia API se integra en la PR #68 (que sustituye a #65). La web no envía un identificador de usuario.

El cliente elimina el código de autorización de la URL antes del intercambio, comprueba `state`, usa un verificador PKCE de alta entropía y restringe el discovery y el token endpoint al mismo origen HTTPS del issuer. Al no solicitar `openid`, no recibe ni ignora un ID token que tendría que validar como relying party; el API recibe exclusivamente el access token. El perfil se obtiene y actualiza exclusivamente a través de `GET/PATCH /v1/me`.

## Configuración necesaria en el proveedor OIDC

La interfaz no funcionará en producción hasta registrar el cliente público:

1. Habilitar Authorization Code Flow y exigir PKCE con método S256.
2. Mantener deshabilitados Implicit Flow y Direct Access Grants si no son necesarios para otros clientes.
3. Crear un cliente público independiente `espana-outdoors-web` y registrar exactamente los redirect URIs web anteriores. Mantener el cliente Android `espana-outdoors-mobile` con su redirect URI `com.espanaoutdoors://oauth2redirect`; no mezclar los redirect URIs de ambos clientes.
4. Configurar Web Origins del cliente web exactamente como `https://espanaoutdoor.es` y `https://www.espanaoutdoor.es`; no utilizar comodines.
5. Configurar el mapper de audiencia para que el access token incluya el valor esperado por `OIDC_AUDIENCE` en Source Gateway.
6. Habilitar el registro/autoregistro del realm si se ofrece creación de cuentas desde la pantalla web; configurar verificación de correo y los campos obligatorios del perfil. Si el registro público no se habilita, cambiar el texto de la interfaz para no prometer creación de cuentas.
7. Confirmar que el cliente puede solicitar los scopes `profile email`, que el access token incluye `sub`, `name`/`preferred_username`, `email` y `email_verified`, y que `email_verified=true` solo se emite tras verificar el correo.

No crear un client secret para la web ni copiar credenciales privadas a los archivos estáticos.

## Configuración del servicio de perfiles

El servicio Source Gateway debe desplegarse con:

- `OIDC_ISSUER` igual al issuer anterior.
- `OIDC_AUDIENCE` igual a la audiencia incluida en el access token.
- `DATABASE_URL` PostgreSQL con `sslmode=require` o `verify-full`.
- `COMMUNITY_ALLOWED_ORIGINS=https://espanaoutdoor.es,https://www.espanaoutdoor.es`.
- La migración `services/source-gateway/migrations/001_community_profiles.sql` aplicada.

El primer `GET /v1/me` crea el perfil canónico a partir del subject verificado. Si la API devuelve HTTP 503, el servicio o PostgreSQL no está provisionado y la página lo informa sin inventar datos.

## Verificación

Ejecutar:

```sh
node --test site/oidc-pkce.test.mjs
```

Las pruebas cubren generación PKCE, state, parámetros de autorización, issuer/discovery, HTTPS, intercambio de código y rechazo de respuestas de token inválidas.

La CI no puede verificar la configuración privada del realm ni el despliegue de PostgreSQL. La activación final requiere probar el callback real y `GET/PATCH /v1/me` con una cuenta de prueba en el dominio de producción.
