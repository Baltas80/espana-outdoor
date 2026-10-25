# España Outdoor — estado técnico

Última auditoría estática: 2026-10-26 (véase `docs/AUDIT_2026-10-26.md`). Validación física Android pendiente.

## Objetivo MVP

Android primero. El criterio de aceptación principal es un APK instalable que abra el mapa sin cerrar la aplicación, renderice cartografía vectorial real y permita usar GPS, rutas y mapas offline.

## Arquitectura fijada

- Renderer cartográfico móvil actual: `maplibre_gl 0.27.1` (confirmado en `pubspec.yaml` y `lib/features/map/maplibre_map_page.dart`).
- Flutter/Riverpod/go_router.
- PMTiles se distribuye/valida como fuente cartográfica para el flujo offline de MapLibre; la apertura offline real requiere prueba en dispositivo.
- iOS queda fuera del MVP.
- Web/desktop quedan fuera del camino crítico del MVP.

## Auditoría ejecutada

- [x] Revisión de arquitectura Flutter: `app/`, `core/`, `domain/`, `features/`, `infrastructure/`.
- [x] Revisión estática de la integración MapLibre actual y su configuración en Dart.
- [ ] Smoke test Android que abra Mapa y compruebe que el proceso sigue vivo con el renderer actual.
- [ ] Verificación de cartografía real online y de PMTiles locales sin conexión.
- [ ] Confirmar que los workflows Android aplican al commit actual y guardan logcat cuando falle el renderer.
- [ ] Verificar configuración de estilo, fuentes, sprites, recursos remotos/locales y atribución en staging.
- [x] Foreground notification GPS configurada como ongoing + wake lock.
- [x] Tests de Home/widget alineados con la UI actual, eliminando expectativas obsoletas.
- [x] Documento de arquitectura de alta gama creado en `docs/ARCHITECTURE_HIGH_END.md`.

## Problemas detectados que siguen abiertos

### P0 — Crash al abrir Mapa

El código ya contiene defensas de lifecycle, pero el cierre físico de la aplicación no se considera resuelto hasta que el smoke test Android ejecute realmente `Mapa` y capture un resultado PASS. La última ejecución que falló no llegó al smoke test porque el análisis/tests fallaron antes.

### P0 — Cobertura cartográfica detallada

Debe verificarse que el estilo y el catálogo configurados ofrecen cobertura vectorial suficiente para España. La existencia del renderer no demuestra que haya datos regionales disponibles.

### P1 — SHA-256 de confianza externa

El cierre definitivo del requisito de integridad exige un manifiesto de producción con SHA-256 esperado por versión/archivo, preferiblemente firmado.

### P1 — Foreground service resiliente

`geolocator` proporciona foreground service y notificación persistente. Para sobrevivir al cierre explícito de la app/proceso y escenarios OEM extremos, el diseño objetivo es un service con engine dedicado y recuperación persistente.

### P1 — Caching predictivo 500 m

Pendiente integrar con el planificador de rutas y convertir el corredor de 500 m en una selección de regiones PMTiles a descargar de forma preventiva.

### P2 — Hillshading

Pendiente una fuente DEM, pipeline local e integración compatible con el estilo MapLibre. No se implementará un falso sombreado visual.

## Limpieza / conservación

- `assets/backgrounds/`: conservar hasta completar búsqueda de referencias; no borrar por suposición.
- `lib/app/outdoor_visuals.dart`: conservar mientras existan features que dependan de sus SVG.
- `LICENSE` y `LICENSE.md`: no eliminar sin revisar diferencias legales/licencia.
- PMTiles/R2: forman parte del flujo cartográfico previsto para MapLibre/offline. No declarar operativo el modo offline hasta verificar descarga, integridad, recursos de estilo y apertura local en dispositivo.
- `services/source-gateway` y `services/rescue-link`: conservar; forman parte de la arquitectura de producto.

## Lista de tareas

### Terminadas

- Auditoría inicial y clasificación de arquitectura.
- Limpieza de dependencias cartográficas antiguas.
- Protección CI contra regresión del renderer.
- Foreground notification GPS persistente.
- Implementación de la pantalla MapLibre y abstracciones cartográficas actuales (existencia de código; QA en dispositivo pendiente).
- Corrección de tests obsoletos de UI (según historial/documentación previa; confirmar CI en el commit actual).
- Sistema visual premium con fotografía propia.

### Pendientes — orden de ejecución

1. **Ejecutar CI de la rama actual y registrar análisis/tests reales.**
2. **APK staging + smoke test Android de Mapa con el renderer MapLibre actual.**
3. **Instalar y probar físicamente el APK; conservar logcat en caso de fallo.**
4. **Verificar estilo, fuentes, atribución y cobertura cartográfica de España.**
5. **Descargar un paquete PMTiles real, validar SHA-256 y abrir MapLibre en modo avión.**
6. **Validar recuperación de descargas interrumpidas/corruptas.**
7. **Auditar Rescue Link end-to-end con backend, OIDC y base de datos de staging.**
8. **Probar Valhalla real y su integración con navegación.**
9. **Pruebas de grabación GPS, recuperación tras interrupción y backtrack en dispositivo.**
10. **QA Android 14/15/16 y restricciones OEM/batería.**
11. **Auditoría final de recursos no utilizados.**
12. **Release candidate Android.**

## Criterio de cierre del incidente del mapa

No se considera resuelto porque compile. El incidente queda cerrado únicamente cuando el smoke test abre `Mapa`, el proceso Android permanece vivo, el renderer carga los recursos vectoriales sin error nativo y el APK resultante se instala y se comprueba físicamente sin cierre de la aplicación.


## Nota de auditoría 2026-10-26

La auditoría vigente está en `docs/AUDIT_2026-10-26.md`. Ningún smoke test físico ni funcionamiento offline se considera acreditado por esta actualización documental.
