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

- `cuenta.html` es la pantalla de cuenta y perfil de la web.
- `account.js` usa Neon Auth para iniciar sesión y Neon Data API para consultar y guardar perfiles.
- `profile-config.js` contiene la URL pública de Neon Auth y la URL pública de Neon Data API. No se deben guardar claves administrativas en el navegador.
- Los perfiles se guardan en `public.user_profiles`. La migración `database/migrations/001_neon_auth_user_profiles.sql` instala la tabla, los permisos mínimos y las políticas RLS para que cada usuario solo pueda leer y modificar su propia fila.
- Antes de publicar esta versión, habilita Neon Data API con proveedor `neon_auth` en la rama de producción; ejecuta la migración en Neon SQL Editor y copia la URL exacta de Data API en `dataApiUrl` de `site/profile-config.js`.
- No se debe fusionar la rama de desarrollo completa con `main` sin revisar sus commits. Publica únicamente los cambios necesarios tras verificar el despliegue y las pruebas.
