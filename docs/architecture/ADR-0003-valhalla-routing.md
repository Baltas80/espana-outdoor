# ADR-0003 — Valhalla (retirado del routing activo del MVP)

## Estado

Retirado del camino de producción del MVP Android a fecha 31/10/2026. Se conserva la infraestructura ops/valhalla como referencia técnica opcional, sin endpoint requerido por la aplicación.

## Motivo del cambio

Una instancia Valhalla propia exige alojamiento permanente, actualizaciones de datos y monitorización. No es razonable asumir ese coste antes de tener usuarios. El objetivo offline requiere además que el dispositivo pueda calcular rutas nuevas sin cobertura.

## Decisión actual

Mapbox Navigation SDK v3 es el motor de rutas Android. La decisión vigente queda registrada en ADR-0002-routing-engine.md. El contrato Dart RoutingService permanece para permitir cambios futuros del proveedor.

## Reglas

- No definir VALHALLA_BASE_URL como requisito en builds del MVP.
- No mantener ordenadores domésticos como servidor de routing.
- No desplegar ops/valhalla como requisito de producción.
- Solo reactivar Valhalla si existe una razón técnica/comercial y presupuesto de infraestructura.
