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
- [ ] `MAPBOX_ACCESS_TOKEN` configurado para la compilación.
- [ ] Mapa base carga sin error de configuración.
- [ ] Posición GPS visible.
- [ ] Zoom/pan estable.
- [ ] Región offline descargada, reabierta en frío y reutilizable en modo avión.

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

## Cierre
Registrar modelo Android, versión del SO, versión/build de la app, fecha, y evidencia de cada fallo antes de marcar el gate como PASS.
