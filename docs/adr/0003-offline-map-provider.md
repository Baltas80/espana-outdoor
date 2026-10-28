# ADR 0003 — Cartografía con MapLibre y estado offline pendiente

## Estado

Retirada. La decisión anterior sobre el formato de distribución cartográfica queda sustituida porque no ha producido una experiencia offline validada en Android.

## Contexto

España Outdoor utiliza MapLibre Flutter como único motor cartográfico. El mapa online debe poder cargarse desde un estilo HTTPS aprobado y mantener la atribución y licencias correspondientes.

## Decisión actual

- Mantener MapLibre Flutter como motor cartográfico.
- Cargar el estilo online mediante `MAP_STYLE_URL`, `MAP_STYLE_JSON` o un asset controlado.
- No tratar el modo offline cartográfico como una función operativa.
- Elegir y validar por separado una futura estrategia offline que sea compatible con la versión instalada de MapLibre Flutter.
- No utilizar los servidores públicos de teselas de OpenStreetMap para descargas masivas.

## Consecuencias

La carga del estilo online deja de depender de un formato de archivo cartográfico ni de un catálogo de paquetes regionales. El modo offline cartográfico queda pendiente hasta comprobar el estilo, las fuentes, los glifos y los sprites sin conexión en un dispositivo Android real.

Compilar el APK no constituye evidencia suficiente de que el mapa offline funcione.
