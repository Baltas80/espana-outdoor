import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const _styleUri = 'mapbox://styles/mapbox/outdoors-v12';
const _regionId = 'espana-outdoor-cordoba-poc';
const _accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

final _cordobaRegion = Polygon(
  coordinates: [
    [
      Position(-4.84, 37.85),
      Position(-4.72, 37.85),
      Position(-4.72, 37.93),
      Position(-4.84, 37.93),
      Position(-4.84, 37.85),
    ],
  ],
);

/// Downloads a deliberately small Córdoba region to validate Mapbox offline
/// rendering on Android before expanding coverage or promising all-Spain maps.
class OfflinePage extends StatefulWidget {
  const OfflinePage({super.key});

  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage> {
  OfflineManager? _offlineManager;
  TileStore? _tileStore;
  bool _initializing = true;
  bool _downloading = false;
  bool _hasOfflineRegion = false;
  double _styleProgress = 0;
  double _tileProgress = 0;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeOfflineStore();
  }

  Future<void> _initializeOfflineStore() async {
    try {
      _offlineManager ??= await OfflineManager.create();
      _tileStore ??= await TileStore.createDefault();
      final regions = await _tileStore!.allTileRegions();
      final stylePacks = await _offlineManager!.allStylePacks();
      if (!mounted) return;
      setState(() {
        _hasOfflineRegion =
            regions.any((region) => region.id == _regionId) &&
            stylePacks.any((pack) => pack.styleURI == _styleUri);
        _message = _hasOfflineRegion
            ? 'Mapbox detecta la región de Córdoba y el estilo guardados.'
            : 'Todavía no hay una descarga confirmada en este dispositivo.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo revisar el almacenamiento offline: $error');
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _downloadRegion() async {
    if (_downloading || _offlineManager == null || _tileStore == null) return;
    setState(() {
      _downloading = true;
      _styleProgress = 0;
      _tileProgress = 0;
      _message = 'Descargando estilo y mapa de Córdoba…';
      _error = null;
    });

    try {
      final styleFuture = _offlineManager!.loadStylePack(
        _styleUri,
        StylePackLoadOptions(
          glyphsRasterizationMode:
              GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
          metadata: const {'purpose': 'offline-validation', 'region': 'cordoba'},
          acceptExpired: false,
        ),
        (progress) {
          final required = progress.requiredResourceCount;
          final value = required == 0
              ? 0.0
              : progress.completedResourceCount / required;
          if (mounted) {
            setState(() => _styleProgress = value.clamp(0.0, 1.0).toDouble());
          }
        },
      );

      final regionFuture = _tileStore!.loadTileRegion(
        _regionId,
        TileRegionLoadOptions(
          geometry: _cordobaRegion.toJson(),
          descriptorsOptions: [
            TilesetDescriptorOptions(
              styleURI: _styleUri,
              minZoom: 8,
              maxZoom: 15,
            ),
          ],
          acceptExpired: true,
          networkRestriction: NetworkRestriction.NONE,
        ),
        (progress) {
          final required = progress.requiredResourceCount;
          final value = required == 0
              ? 0.0
              : progress.completedResourceCount / required;
          if (mounted) {
            setState(() => _tileProgress = value.clamp(0.0, 1.0).toDouble());
          }
        },
      );

      await Future.wait([styleFuture, regionFuture]);
      await _initializeOfflineStore();
      if (!mounted) return;
      setState(() {
        _message = _hasOfflineRegion
            ? 'Descarga terminada. Activa modo avión y abre el mapa para validar.'
            : 'La descarga acabó, pero no se ha confirmado el estilo y la región.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Error durante la descarga: $error';
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
          const Icon(Icons.map_outlined, size: 54),
          const SizedBox(height: 16),
          Text(
            'Descarga de prueba · Córdoba',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Mapbox Outdoors · zoom 8–15. Esta primera integración descarga '
            'una zona delimitada alrededor de Córdoba, no toda España.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_accessToken.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Falta MAPBOX_ACCESS_TOKEN. La compilación Android debe '
                  'inyectar el token público de Mapbox; no lo incluyas en Git.',
                ),
              ),
            ),
          _ProgressRow(label: 'Estilo', value: _styleProgress),
          const SizedBox(height: 8),
          _ProgressRow(label: 'Teselas', value: _tileProgress),
          const SizedBox(height: 12),
          if (_initializing)
            const LinearProgressIndicator()
          else
            Text(_message ?? 'Preparado para comprobar el almacenamiento.'),
          if (_hasOfflineRegion)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'El SDK detecta los recursos guardados. Esto no sustituye '
                'la prueba real con el teléfono sin conexión.',
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
            label: Text(_downloading ? 'Descargando…' : 'Descargar mapa de Córdoba'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _initializing ? null : _initializeOfflineStore,
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
            'Validación pendiente: activa el modo avión, fuerza el cierre de '
            'España Outdoor y vuelve a abrirla. Comprueba que el mapa se '
            'renderiza y permite moverse dentro de la zona descargada.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label)),
        Expanded(child: LinearProgressIndicator(value: value)),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          child: Text('${(value * 100).round()}%', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
