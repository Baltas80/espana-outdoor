# Identidad web compartida

## Implementación

La página estática `/cuenta.html` utiliza Authorization Code + PKCE (S256) como cliente público. No contiene un client secret ni usa cookies de terceros.

- Emisor: `https://auth.espanaoutdoor.es/realms/espana-outdoor`
- Cliente público compartido: `espana-outdoors-mobile`
- Callback web: `https://espanaoutdoor.es/cuenta.html` y `https://www.espanaoutdoor.es/cuenta.html`
- API de perfiles: `https://api.espanaoutdoor.es/v1/me`
- Sesión del navegador: `sessionStorage`, nunca `localStorage`; no se solicita ni almacena refresh token.
- El backend valida la firma, issuer y audiencia del access token. La web no envía un identificador de usuario.

El cliente elimina el código de autorización de la URL antes del intercambio, comprueba `state`, usa un verificador PKCE de alta entropía y restringe el discovery y el token endpoint al mismo origen HTTPS del issuer. El perfil se obtiene y actualiza exclusivamente a través de `GET/PATCH /v1/me`.

## Configuración necesaria en el proveedor OIDC

La interfaz no funcionará en producción hasta registrar el cliente público:

1. Habilitar Authorization Code Flow y exigir PKCE con método S256.
2. Mantener deshabilitados Implicit Flow y Direct Access Grants si no son necesarios para otros clientes.
3. Registrar exactamente los redirect URIs web anteriores y conservar el redirect URI Android `com.espanaoutdoors://oauth2redirect`.
4. Configurar Web Origins exactamente como `https://espanaoutdoor.es` y `https://www.espanaoutdoor.es`; no utilizar comodines.
5. Configurar el mapper de audiencia para que el access token incluya el valor esperado por `OIDC_AUDIENCE` en Source Gateway.
6. Confirmar que el cliente puede solicitar `openid profile email` y que el proveedor emite `email_verified=true` solo tras verificar el correo.

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
