# QA Android físico — cierre A

Usar exclusivamente en un dispositivo de prueba. No declarar el gate verde sin evidencia.

## Navegación
- [ ] Back desde Mapa vuelve a Inicio y no cierra la app.
- [ ] Back desde Rutas vuelve a Inicio.
- [ ] Back desde detalle/planner vuelve a Rutas.
- [ ] Back desde Seguridad vuelve a Inicio.
- [ ] Back desde Contactos vuelve a Seguridad.
- [ ] Back desde Perfil vuelve a Inicio.
- [ ] Back desde Planes vuelve a Perfil.

## Mapa
- [ ] `MAPBOX_ACCESS_TOKEN` configurado como secreto de compilación; no guardarlo en Git.
- [ ] Mapa base carga sin error de configuración.
- [ ] Posición GPS visible.
- [ ] Zoom/pan estable.
- [ ] Descargar Córdoba, cerrar la app en frío, activar modo avión y verificar que el mapa se representa y permite pan/zoom.

## Routing / navegación
- [ ] Ruta peatonal calculada por Valhalla productivo.
- [ ] Guidance muestra siguiente maniobra.
- [ ] Desviación detectada.
- [ ] Recalculado correcto.
- [ ] Llegada detectada.

## Seguridad
- [ ] Permiso de ubicación.
- [ ] SOS abre el flujo correcto.
- [ ] 112 abre el handoff telefónico sin ejecutar llamadas automáticas durante QA.
- [ ] Rescue Link funciona con endpoint productivo.
- [ ] Estado sin conectividad tratado correctamente.

## Identidad compartida web / Android
- [ ] Build de prueba configurado con OIDC_ISSUER HTTPS del realm compartido.
- [ ] OIDC_CLIENT_ID registrado como espana-outdoors-mobile.
- [ ] OIDC_REDIRECT_URI registrado como com.espanaoutdoors://oauth2redirect.
- [ ] COMMUNITY_API_BASE_URL apunta a la API HTTPS real; no usar una URL de ejemplo.
- [ ] Registro de una cuenta nueva desde el flujo OIDC del móvil.
- [ ] GET /v1/me devuelve el perfil canónico y un UUID estable.
- [ ] Iniciar sesión con esa misma cuenta en web devuelve exactamente el mismo UUID.
- [ ] Token ausente/caducado rechazado sin mostrar un perfil falso.
- [ ] La prueba se realiza contra un entorno de test, no con cuentas reales de producción.

## Cierre
Registrar modelo Android, versión del SO, versión/build de la app, fecha, y evidencia de cada fallo antes de marcar el gate como PASS.
