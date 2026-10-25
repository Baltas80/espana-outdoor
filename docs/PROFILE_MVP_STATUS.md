# Estado del MVP de perfil — España Outdoor

**Última actualización:** 25 de octubre de 2026  
**Rama de trabajo:** `feature/profile-registration-20261024`  
**Vista de pruebas:** https://feature-profile-registration.espana-outdoor.pages.dev/  
**Mi cuenta:** https://feature-profile-registration.espana-outdoor.pages.dev/cuenta.html  
**Mi perfil:** https://feature-profile-registration.espana-outdoor.pages.dev/mi-perfil.html

## Hecho y verificado

- Registro, inicio y cierre de sesión con Neon Auth en la web de pruebas.
- Dominio `https://feature-profile-registration.espana-outdoor.pages.dev` añadido y verificado en los dominios de confianza de Neon Auth.
- Formulario de edición de perfil: nombre visible, alias público, zona habitual y presentación.
- Persistencia y lectura de los datos de perfil mediante Neon Data API y la tabla `public.user_profiles`, protegida con RLS.
- Página independiente `site/mi-perfil.html`, que presenta los datos guardados y permite volver a editarlos.
- Al guardar cambios desde `site/cuenta.html`, el usuario es redirigido a `mi-perfil.html?guardado=1`.
- Enlace «Mi perfil» añadido a la navegación y al pie de página.
- Estilos de escritorio y móvil para la nueva vista.
- Flujo de Cloudflare Pages actualizado para desplegar la página, su módulo JS, la navegación y los estilos.
- CI actualizado para validar la sintaxis de `site/mi-perfil.js` y comprobar sus recursos.

## Verificaciones de GitHub Actions

- Despliegue de la página de perfil: correcto  
  https://github.com/Baltas80/espana-outdoor/actions/runs/40217596570
- Integración compartida de perfil y sintaxis JS: correcta  
  https://github.com/Baltas80/espana-outdoor/actions/runs/40217676171
- La vista real del usuario confirma que se muestran nombre, alias, zona habitual, presentación y fecha de alta, y que el recorrido de guardar lleva a Mi perfil.

## Pendiente — no fingir que está implementado

1. **Mis fotos:** el apartado visual existe, pero todavía no está conectado a subida, almacenamiento, borrado ni galería persistente.
2. **Mis logros:** el apartado visual existe, pero aún no hay una fuente de actividad/rutas que otorgue y sincronice logros.
3. **Prueba adicional recomendada:** modificar los datos, guardar, volver a entrar y confirmar que se mantienen tras cerrar sesión y entrar de nuevo.
4. Antes de promover cambios a producción, probar también el dominio definitivo y confirmar que sus dominios de confianza están configurados en Neon Auth.

## Archivos principales

- `site/cuenta.html` — registro, inicio de sesión y edición de los datos.
- `site/account.js` — flujo de autenticación, lectura y guardado de perfil.
- `site/profile-config.js` — URLs públicas de Neon Auth y Neon Data API.
- `site/mi-perfil.html` — página independiente de perfil personal.
- `site/mi-perfil.js` — lectura autenticada y renderizado de perfil.
- `site/app.js` — navegación compartida de la web.
- `site/styles.css` — estilos del perfil.
- `database/migrations/001_neon_auth_user_profiles.sql` — esquema y políticas RLS.

**Regla de continuidad:** continuar desde esta rama y conservar el código existente. Prioridad siguiente: completar «Mis fotos» de extremo a extremo sin perder el perfil ya operativo; después integrar «Mis logros» con una fuente de datos real.
