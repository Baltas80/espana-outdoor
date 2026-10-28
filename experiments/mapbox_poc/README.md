# Mapbox Maps SDK — prueba aislada Android

Esta aplicación es una prueba independiente: no modifica el motor cartográfico de España Outdoor ni sustituye MapLibre en la app principal.

## Requisitos

- Flutter 3.38.1 o posterior y Dart 3.10.0 o posterior.
- Android SDK configurado.
- Token público de Mapbox con acceso a Maps SDK. No lo guardes en Git ni lo pegues en el código.

## Preparar Android (una sola vez)

Desde esta carpeta:

```bash
flutter create --platforms=android --project-name mapbox_offline_poc .
flutter pub get
```

Si Flutter pregunta por archivos existentes, conserva `lib/main.dart` y este `pubspec.yaml`.

## Ejecutar en el dispositivo

```bash
flutter run --dart-define=ACCESS_TOKEN=TU_TOKEN_PUBLICO
```

Para generar un APK de depuración:

```bash
flutter build apk --debug --dart-define=ACCESS_TOKEN=TU_TOKEN_PUBLICO
```

El APK estará en `build/app/outputs/flutter-apk/app-debug.apk`.

## Protocolo de prueba offline

1. Instala y abre la app con Wi-Fi/datos activos.
2. Comprueba que aparece el mapa Outdoors centrado en Córdoba.
3. Pulsa **Descargar mapa offline** y espera a que terminen las barras de estilo y región.
4. Comprueba que la app confirma que el SDK detecta el estilo y la región guardados.
5. Activa modo avión y desactiva cualquier otra conexión.
6. Fuerza el cierre de la app desde Ajustes/Aplicaciones y vuelve a abrirla.
7. Mueve y amplía/reduce el mapa dentro y alrededor del rectángulo descargado.
8. Registra si el mapa se mantiene, qué niveles de zoom funcionan, cuánto tarda la descarga y cuánto almacenamiento consume.
9. Repite tras reiniciar el teléfono para comprobar persistencia.

La región es un rectángulo de prueba alrededor de Córdoba, con zoom 8–15; no descarga España completa. El estado que informa el SDK de que existen recursos guardados **no demuestra por sí solo** que el renderizado sin conexión funcione: la prueba en modo avión es obligatoria.

## Alcance y límites

- Usa el SDK oficial `mapbox_maps_flutter ^3.33.0` y el estilo Mapbox Outdoors.
- Descarga un style pack y una región de teselas mediante `OfflineManager` y `TileStore`.
- No cambia el código de producción de España Outdoor.
- El SDK exige respetar la atribución/wordmark de Mapbox y ofrecer la opción de exclusión de telemetría según sus condiciones. El control de atribución predeterminado se mantiene visible.
- La disponibilidad y el coste dependen de la cuenta, el uso y las condiciones vigentes de Mapbox. Revisa sus términos antes de adoptar esta solución en producción.
