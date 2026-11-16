import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/outdoor_visuals.dart';
import '../map/mapbox_map_viewport.dart';

const _navigationChannel = MethodChannel('com.espanaoutdoors/navigation');
const _regionId = 'espana-outdoor-cordoba-poc';
const _accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

// Include complete z13 tile bounds around the portrait map viewport.
// A 37.85° southern edge clipped most of the y=3164 row in the emulator.
const _cordobaRing = <List<double>>[
  [-4.84, 37.78],
  [-4.72, 37.78],
  [-4.72, 37.97],
  [-4.84, 37.97],
  [-4.84, 37.78],
];

/// Downloads map and pedestrian routing resources through the native bridge.
/// Maps and Navigation therefore use the same persistent Android TileStore.
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
    _refreshStatus();
  }

  Future<bool> _queryOfflineRegion() async {
    final result = await _navigationChannel.invokeMethod<bool>(
      'hasOfflineRegion',
      {'regionId': _regionId},
    );
    return result == true;
  }

  Future<void> _refreshStatus() async {
    if (!_initializing && mounted) {
      setState(() => _initializing = true);
    }
    try {
      final exists = await _queryOfflineRegion();
      if (!mounted) return;
      setState(() {
        _hasOfflineRegion = exists;
        _message = exists
            ? 'Mapbox confirma la región de Córdoba y sus datos de routing peatonal.'
            : 'Todavía no hay una descarga confirmada en este dispositivo.';
        _error = null;
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _hasOfflineRegion = false;
        _error = 'El motor nativo offline solo está disponible en Android.';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _hasOfflineRegion = false;
        _error = 'No se pudo consultar el almacén offline (' + error.code + ').';
      });
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _downloadRegion() async {
    if (_downloading || _accessToken.isEmpty) return;
    setState(() {
      _downloading = true;
      _message = 'Descargando estilo, teselas y routing peatonal de Córdoba…';
      _error = null;
    });

    try {
      final result = await _navigationChannel.invokeMapMethod<String, dynamic>(
        'downloadOfflineRegion',
        {
          'regionId': _regionId,
          'styleUri': mapboxStyleUri,
          'coordinates': _cordobaRing,
          'minZoom': 8,
          'maxZoom': 15,
        },
      );
      final mapResources =
          (result?['mapCompletedResourceCount'] as num?)?.toInt() ?? 0;
      final mapBytes =
          (result?['mapCompletedResourceSize'] as num?)?.toInt() ?? 0;
      final routingResources =
          (result?['routingCompletedResourceCount'] as num?)?.toInt() ?? 0;
      final routingBytes =
          (result?['routingCompletedResourceSize'] as num?)?.toInt() ?? 0;
      if (result == null ||
          result['regionId'] != _regionId ||
          result['mapTiles'] != true ||
          result['routingTiles'] != true ||
          result['routingProfile'] != 'walking' ||
          mapResources <= 0 ||
          mapBytes <= 0 ||
          routingResources <= 0 ||
          routingBytes <= 0) {
        throw const FormatException(
          'El motor nativo no confirmó por separado las teselas de mapa y routing.',
        );
      }

      final exists = await _queryOfflineRegion();
      if (!mounted) return;
      setState(() {
        _hasOfflineRegion = exists;
        _message = exists
            ? 'Descarga confirmada. Mapa: $mapResources recursos / $mapBytes bytes; routing peatonal: $routingResources recursos / $routingBytes bytes. Valida ambos en modo avión.'
            : 'La descarga terminó, pero TileStore no confirmó ambas regiones.';
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _error = 'El puente nativo Mapbox Navigation no está disponible.';
        _message = 'No se ha podido iniciar la descarga.';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Error del motor offline (' + error.code + ').';
        _message = 'No se ha podido confirmar la descarga.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
        _message = 'No se ha podido confirmar la descarga.';
      });
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mapas offline')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const OutdoorAssetIcon(
            asset: 'assets/visuals/icons/library/premium/offline.webp',
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'Descarga de prueba · Córdoba',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Mapbox Outdoors · zoom 8–15. La descarga guarda por separado '
            'teselas de mapa y routing peatonal; ambos paquetes deben persistir. '
            'No representa cobertura de toda España.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_accessToken.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Falta MAPBOX_ACCESS_TOKEN. Inyecta el token público durante '
                  'la compilación; nunca lo incluyas en Git.',
                ),
              ),
            ),
          if (_initializing || _downloading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          Text(_message ?? 'Preparado para comprobar el almacenamiento.'),
          if (_hasOfflineRegion)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'TileStore confirma la región y los datos peatonales. '
                'Esto todavía no sustituye la prueba sin conectividad.',
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
            label: Text(
              _downloading ? 'Descargando…' : 'Descargar mapa de Córdoba',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _initializing || _downloading ? null : _refreshStatus,
            icon: const Icon(Icons.refresh),
            label: const Text('Comprobar descargas guardadas'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: () => context.go('/map'),
            child: const Text('Volver al mapa'),
          ),
          const SizedBox(height: 16),
          Text(
            'Validación pendiente: activa modo avión, fuerza el cierre de '
            'España Outdoor y vuelve a abrirla. Comprueba que el mapa se '
            'renderiza y que una ruta peatonal nueva se calcula sin red.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
