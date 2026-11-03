import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

const _regionId = 'espana-outdoor-cordoba-poc';
const _styleUri = 'mapbox://styles/mapbox/outdoors-v12';
const _accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
const _navigationChannel = MethodChannel('com.espanaoutdoors/navigation');

const _cordobaRing = <List<double>>[
  [-4.84, 37.85],
  [-4.72, 37.85],
  [-4.72, 37.93],
  [-4.84, 37.93],
  [-4.84, 37.85],
];

/// Downloads Mapbox style resources, visual tiles, and walking routing tiles
/// into the same native TileStore on Android.
class OfflinePage extends StatefulWidget {
  const OfflinePage({super.key});

  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage> {
  bool _initializing = true;
  bool _downloading = false;
  bool _hasOfflineRegion = false;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeOfflineStore();
  }

  Future<void> _initializeOfflineStore() async {
    try {
      if (defaultTargetPlatform != TargetPlatform.android) {
        throw UnsupportedError(
          'El cálculo de rutas offline con Navigation SDK está integrado primero en Android.',
        );
      }
      if (_accessToken.isEmpty) {
        throw StateError('Falta MAPBOX_ACCESS_TOKEN en esta compilación.');
      }
      final available = await _navigationChannel.invokeMethod<bool>(
        'hasOfflineRegion',
        {'regionId': _regionId},
      );
      if (!mounted) return;
      setState(() {
        _hasOfflineRegion = available ?? false;
        _message = _hasOfflineRegion
            ? 'Córdoba dispone de cartografía y datos de rutas a pie guardados.'
            : 'Todavía no hay una descarga offline completa confirmada.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hasOfflineRegion = false;
        _error = 'No se pudo comprobar la descarga offline: $error';
      });
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _downloadRegion() async {
    if (_downloading || _initializing) return;
    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _error = 'La descarga de routing offline está disponible primero en Android.');
      return;
    }
    setState(() {
      _downloading = true;
      _error = null;
      _message = 'Descargando estilo, teselas del mapa y grafo peatonal de Córdoba…';
    });

    try {
      await _navigationChannel.invokeMethod<void>('downloadOfflineRegion', {
        'regionId': _regionId,
        'styleUri': _styleUri,
        'coordinates': _cordobaRing,
        'minZoom': 8,
        'maxZoom': 15,
      });
      if (!mounted) return;
      await _initializeOfflineStore();
      if (!mounted) return;
      if (_hasOfflineRegion) {
        setState(() {
          _message = 'Descarga completa: mapas y routing peatonal disponibles para prueba offline.';
        });
      } else {
        setState(() => _error = 'La descarga terminó, pero no se ha podido confirmar la región.');
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Mapbox no pudo descargar los datos: ${error.message ?? error.code}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Error al descargar la región: $error');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mapas y rutas offline')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.map_outlined, size: 54),
          const SizedBox(height: 16),
          Text(
            'Descarga de prueba · Córdoba',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Mapbox Outdoors y datos de routing peatonal · zoom 8–15. '
            'Esta prueba descarga una zona delimitada de Córdoba, no toda España.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_accessToken.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Falta MAPBOX_ACCESS_TOKEN. Inyecta el token público de Mapbox en la compilación; no lo incluyas en Git.',
                ),
              ),
            ),
          if (_initializing || _downloading) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(_message ?? 'Preparado para comprobar las descargas.'),
          if (_hasOfflineRegion)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Mapbox confirma la región guardada. Falta validar una ruta nueva con el teléfono sin conexión.',
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _initializing || _downloading || _accessToken.isEmpty
                ? null
                : _downloadRegion,
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(_downloading ? 'Descargando…' : 'Descargar mapas y rutas de Córdoba'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _initializing || _downloading ? null : _initializeOfflineStore,
            icon: const Icon(Icons.refresh),
            label: const Text('Comprobar descarga guardada'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: () => context.go('/map'),
            child: const Text('Volver al mapa'),
          ),
          const SizedBox(height: 16),
          Text(
            'Prueba obligatoria: descarga la región, fuerza el cierre de España Outdoor, activa el modo avión, vuelve a abrir la app y calcula una ruta nueva entre dos puntos dentro de Córdoba.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
