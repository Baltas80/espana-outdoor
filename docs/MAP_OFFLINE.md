# Cartografía, routing y modo offline

## Cartografía

Mapbox Maps SDK (mapbox_maps_flutter 3.33.0) es el motor cartográfico de Android. El estilo de producto es Mapbox Outdoors (mapbox://styles/mapbox/outdoors-v12). Mapbox proporciona estilos, teselas vectoriales, fuentes, etiquetas y recursos cartográficos. El MVP no necesita un servidor propio de teselas.

## Routing

Android utiliza Mapbox Navigation SDK v3.33.0 mediante un puente nativo Kotlin (MapboxNavigationBridge) y un adaptador Flutter (MapboxNavigationRoutingService). El contrato de dominio RoutingService se mantiene. No se requiere VPS ni endpoint Valhalla para el MVP.

- Con conexión, Navigation SDK puede solicitar rutas a Mapbox Directions.
- Sin conexión, puede calcular rutas localmente si la región de routing correspondiente se ha descargado previamente.
- El perfil inicial es peatonal (mapbox/walking).
- La respuesta identifica si el cálculo fue online u offline.
- Navigation SDK no tiene plugin Flutter oficial; el puente MethodChannel limita el código nativo a Android.

## Descargas offline

La pantalla de mapas offline descarga en una misma región y en un único TileStore:
1. El paquete del estilo Mapbox Outdoors.
2. Las teselas visuales del mapa para zoom 8–15.
3. El tileset de routing peatonal de Mapbox Navigation SDK.

Es obligatorio compartir el mismo objeto TileStore entre Maps SDK y Navigation SDK. El puente nativo configura ese almacenamiento antes de crear el primer MapWidget.

La primera región sigue siendo una prueba delimitada en Córdoba. No representa cobertura de España completa ni debe presentarse como tal.

## Validación obligatoria en Android

La descarga se considera completa solo cuando la región contiene recursos de mapa y routing. Para validar:
1. Descargar la región de Córdoba con conectividad.
2. Forzar el cierre de España Outdoor.
3. Activar el modo avión.
4. Abrir de nuevo la aplicación.
5. Calcular una ruta nueva entre dos puntos dentro de la región.
6. Confirmar que el resultado procede del router offline y que la geometría aparece en el mapa.
7. Repetir tras reiniciar el dispositivo.

La compilación correcta o la mera visualización del mapa en modo avión no demuestra routing offline.

## Alcance y límites

- Android primero. La integración Navigation SDK nativa equivalente para iOS queda pendiente.
- GPS, grabación de recorridos, GPX, persistencia local y funciones de seguridad siguen siendo independientes del proveedor de routing.
- El relieve visual no equivale a un perfil de elevación; la app no debe mostrar desniveles sin una fuente de elevación fiable.
- Mapbox Navigation SDK se distribuye bajo los términos de Mapbox; verificar tarifas y condiciones antes de publicar.
