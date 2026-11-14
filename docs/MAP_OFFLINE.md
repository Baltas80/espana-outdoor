# Cartografía y modo offline

## Arquitectura cartográfica

Mapbox Maps es el motor de representación cartográfica de la app. El estilo principal es Mapbox Outdoors y requiere `MAPBOX_ACCESS_TOKEN` inyectado en tiempo de compilación.

La integración nativa de routing descrita aquí está preparada en la rama `feat/mapbox-offline-routing-port-20261114`; todavía no está integrada ni validada por CI o en dispositivo físico.

## Almacén compartido

En Android, el puente nativo:

1. Configura `MapboxOptions.accessToken`.
2. Crea un `TileStore` persistente en `noBackupFilesDir/mapbox-tiles`.
3. Asigna esa misma instancia a `MapboxMapsOptions.tileStore`.
4. Configura `TileStoreUsageMode.READ_AND_UPDATE`.
5. Inyecta la misma instancia en `RoutingTilesOptions` de Mapbox Navigation.

El orden es obligatorio: el token debe configurarse antes de crear el TileStore y el TileStore debe quedar asignado antes de construir el primer `MapWidget`.

La metadata de finalización se escribe de forma síncrona en almacenamiento privado. La comprobación de una región exige que el ID exista en TileStore y que exista el marcador de finalización; el marcador por sí solo no basta.

## Región de prueba

La primera descarga cubre una región delimitada de Córdoba, con estilo Mapbox Outdoors y zoom 8–15. Se descargan:

- Style pack del mapa.
- Teselas visuales de la región.
- Descriptor de routing peatonal de Navigation SDK.

La descarga no representa cobertura nacional. No se deben anunciar mapas de toda España hasta definir, descargar y probar regiones y cuotas reales.

## Motores de routing

| Perfil | Motor | Estado offline |
|---|---|---|
| Senderismo / walking | Mapbox Navigation en Android | Preparado para usar routing tiles peatonales; pendiente de prueba |
| BTT | Valhalla | Online; offline no implementado |
| Cicloturismo | Valhalla | Online; offline no implementado |
| Ajuste de tracks GPX | Valhalla | Requiere endpoint online |

El adaptador Mapbox solo acepta perfiles peatonales. El servicio compuesto evita enviar perfiles de bicicleta al grafo peatonal. Los resultados incluyen `source`: `online`, `offline` o `valhalla`. La UI debe mostrar ese origen real.

La implementación actual calcula rutas y devuelve geometría e instrucciones. No acredita todavía navegación guiada completa con progreso GPS, detección de desvíos o recálculo.

## Credenciales

- `MAPBOX_ACCESS_TOKEN`: token público de runtime para el estilo y la API.
- `MAPBOX_DOWNLOADS_TOKEN`: token con permiso de lectura de Mapbox Downloads, usado por Gradle para resolver los SDK nativos desde Maven.

Ninguno debe incluirse en el repositorio. El token Maven no debe exponerse a PRs no confiables. Los builds de Dependabot sin ese secreto omiten Android nativo y se etiquetan como no validados; no son artefactos de prueba de mapas.

## Pruebas automatizadas y de emulador

La integración de Android ejecuta dos fases:

1. Con conexión: inicializa el TileStore, calcula una ruta fuera de Córdoba para exigir origen `ONLINE`, descarga el style pack y la región, y confirma que TileStore conserva el ID.
2. Sin conexión: fuerza el cierre, activa modo avión y desactiva Wi-Fi, comprueba que la región persiste, solicita una ruta nueva dentro de Córdoba y exige origen `OFFLINE`. Después monta un `MapWidget` y espera `onMapLoaded`, evento que confirma estilo y teselas visibles cargadas. También captura una imagen de evidencia.

Verificación de dependencias y script CI:

```bash
python3 tool/verify_mapbox_lock.py
bash tool/staging_android_route_integration.sh
```

El workflow de staging resuelve `pubspec.lock`, lo versiona en la rama de integración y después ejecuta `flutter pub get --enforce-lockfile`. Esta secuencia debe completarse correctamente antes de integrar el cambio.

La CI distingue la prueba de ruta del evento de mapa cargado. Un resultado `OFFLINE` sin mapa renderizado no basta para aceptar cartografía offline.

## Prueba física OPPO

Desde Windows, con Flutter, ADB y las credenciales necesarias:

```powershell
$env:MAPBOX_ACCESS_TOKEN = "pk.…"
$env:MAPBOX_DOWNLOADS_TOKEN = "…"
$env:ANDROID_SERIAL = "da09ac8c"
.	ool	est_mapbox_oppo_routes.ps1
```

El script valida el dispositivo OPPO esperado, registra el estado original de conectividad, prueba online y descarga, activa modo avión, desactiva Wi-Fi, fuerza el cierre y exige ruta nueva con origen `OFFLINE` y evidencia de mapa cargado. Al finalizar intenta restaurar el estado original de conectividad y guarda informe y logcat bajo `build/mapbox-oppo-validation/`.

La prueba debe repetirse después de reiniciar el dispositivo para acreditar persistencia real. No ejecutar el script con un dispositivo distinto sin ajustar explícitamente `ANDROID_SERIAL` y `EXPECTED_ANDROID_MODEL`.

## Protocolo de aceptación

La funcionalidad no se considera aceptada hasta cumplir todo lo siguiente en el APK construido desde el commit candidato:

1. Instalar y abrir la app con conectividad.
2. Descargar Córdoba y esperar la confirmación del SDK.
3. Forzar cierre y volver a abrir.
4. Activar modo avión y confirmar que Wi-Fi está desactivado.
5. Abrir el mapa, moverlo y cambiar zoom dentro de la región.
6. Confirmar que Mapbox emite el evento de mapa cargado y que las teselas visibles se renderizan.
7. Calcular una ruta nueva, no reutilizar una ruta guardada, y exigir origen nativo `OFFLINE`.
8. Reiniciar el dispositivo y repetir la comprobación de región, mapa y routing.
9. Restaurar conectividad y verificar recuperación sin duplicar ni corromper la región.

Registrar por separado tests unitarios, emulador y dispositivo físico. CI verde no sustituye la prueba en OPPO.

## Estado

- Mapas offline: integración nativa preparada en rama; sin aceptación todavía.
- Routing peatonal offline: integración nativa preparada en rama; sin aceptación todavía.
- Routing BTT/cicloturismo offline: no implementado.
- Navegación guiada completa: no acreditada.
- Cobertura nacional: no acreditada.
- Prueba física tras reinicio: pendiente.
