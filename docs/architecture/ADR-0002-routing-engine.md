# ADR-0002: motor de routing para Android MVP

- Estado: aceptado para el MVP Android.
- Decisión: Mapbox Navigation SDK v3 detrás de RoutingService.
- Versión alineada: Mapbox Maps Flutter 3.34.1 / Maps Android 11.34.1 / Navigation Android 3.34.1. Android fija NDK r27d (27.3.13750724) y selecciona los artefactos -ndk27.
- Perfil inicial: peatonal, mapbox/walking.

## Contexto

España Outdoor requiere cálculo de rutas peatonales, incluido el uso en zonas sin cobertura. Un servicio alojado por el proyecto introduciría un coste y dependencia operativa antes de que exista tráfico.

## Decisión

Android utiliza Mapbox Navigation SDK v3. El motor puede resolver rutas online mediante Mapbox Directions y utilizar el router offline del dispositivo cuando se han descargado previamente los tilesets de routing de la región.

El código Dart mantiene el contrato RoutingService. El SDK nativo se conecta mediante un puente Kotlin/MethodChannel; el algoritmo de routing no se implementa en Dart.

## Datos offline

Maps SDK y Navigation SDK deben recibir el mismo objeto TileStore persistente. Android lo crea una sola vez por proceso, en el directorio privado no incluido en copias de seguridad, y lo configura antes de runApp y del primer MapWidget. Cada región descargada contiene el estilo y las teselas visuales de Mapbox junto con el tileset de routing peatonal. Descargar solo el mapa no permite solicitar rutas nuevas sin conexión. CI y el test físico deben exigir orígenes de ruta ONLINE/OFFLINE explícitos, no inferirlos.

## Alcance y límites

- Android es la plataforma prioritaria del MVP.
- La primera región es una prueba delimitada en Córdoba; no se declara cobertura nacional.
- Map matching de trazas GPX no forma parte de esta primera integración.
- El desnivel no se estima a partir de la geometría; solo se muestra con una fuente de elevación fiable.
- La integración nativa iOS se decidirá en una fase posterior.

## Consecuencias

Ventajas:
- Sin VPS ni servidor doméstico para routing.
- Descargas regionales y cálculo offline en el dispositivo.
- Menos infraestructura operativa para el MVP.

Costes y riesgos:
- Consumo de cuota Mapbox y aplicación de sus términos/tarifas.
- El SDK Android se descarga desde Maven privado mediante un token de compilación Downloads:Read.
- La cobertura offline depende de que el usuario descargue previamente la región adecuada.
- Se requiere prueba física de ruta nueva en modo avión.
