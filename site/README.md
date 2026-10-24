# España Outdoor — Web

Sitio web público independiente de la aplicación Flutter.

## Objetivo

Presentación pública de España Outdoor, contenidos de producto, cartografía, rutas, naturaleza y seguridad. La web no modifica la arquitectura de la app móvil.

## Despliegue

La carpeta `site/` está pensada para un hosting estático (Cloudflare Pages, GitHub Pages u otro equivalente).

- Directorio de salida/publicación: `site`
- Sin build step obligatorio.
- Dominio previsto: `https://espanaoutdoor.es`

## Recursos

Los recursos visuales se mantienen dentro de `site/assets` para que la web no dependa de un CDN externo para su identidad visual.

## Siguiente fase

1. Conectar navegación real a mapas/servicios públicos cuando estén publicados.
2. Añadir contenidos territoriales indexables.
3. Integrar métricas respetuosas con privacidad, solo si se decide producto.
4. Conectar enlaces oficiales de descarga de la aplicación cuando las publicaciones sean definitivas.

<!-- Deployment trigger: GitHub Pages deployment verification. -->

- Sección pública: `flora-fauna.html` con catálogo inicial de biodiversidad.


## Cuenta compartida web + Android

- `cuenta.html` is the browser account/profile screen.
- `account.js` uses the official `keycloak-js` adapter pinned to version 26.2.4 and Authorization Code + PKCE. Access and refresh tokens are kept in memory by the adapter, not in localStorage.
- `profile-config.js` contains public issuer/client/API URLs only; never place credentials or client secrets there.
- Both clients use the `espana-outdoor` Keycloak realm. The browser client is `espana-outdoors-web`; Android uses `espana-outdoors-mobile`.
- Profile reads/writes use `https://api.espanaoutdoor.es/v1/me/profile`. The API must be deployed, configured with the API audience mapper, and allow this site's exact CORS origin before the UI can save profiles.
- New accounts are created in the hosted Keycloak registration screen. Enable self-registration and configure email verification/password policy in the realm before enabling the public link.
