import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const _styleUri = 'mapbox://styles/mapbox/outdoors-v12';
const _regionId = 'espana-outdoor-cordoba-poc';
const _accessToken = String.fromEnvironment('ACCESS_TOKEN');

final _cordobaCenter = Point(coordinates: Position(-4.7794, 37.8882));

// Rectángulo de prueba acotado alrededor de Córdoba; no es cobertura de España.
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken(_accessToken);
  runApp(const MapboxPocApp());
}

class MapboxPocApp extends StatelessWidget {
  const MapboxPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mapbox Offline POC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B4D)),
        useMaterial3: true,
      ),
      home: const MapboxPocPage(),
    );
  }
}

class MapboxPocPage extends StatefulWidget {
  const MapboxPocPage({super.key});

  @override
  State<MapboxPocPage> createState() => _MapboxPocPageState();
}

class _MapboxPocPageState extends State<MapboxPocPage> {
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
      _offlineManager = await OfflineManager.create();
      _tileStore = await TileStore.createDefault();
      final region = _tileStore!.tileRegion(_regionId);
      final stylePack = _offlineManager!.stylePack(_styleUri);
      if (!mounted) return;
      setState(() {
        _hasOfflineRegion = region != null && stylePack != null;
        _message = _hasOfflineRegion
            ? 'Región offline detectada en este dispositivo.'
            : 'Sin descarga offline confirmada en este dispositivo.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo inicializar el almacenamiento offline: $error');
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
      _message = 'Descargando estilo y región de Córdoba…';
      _error = null;
    });

    try {
      // La cuota predeterminada de TileStore se conserva. No se configura
      // una cuota ilimitada para esta prueba.
      final styleFuture = _offlineManager!.loadStylePack(
        _styleUri,
        StylePackLoadOptions(
          glyphsRasterizationMode:
              GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
          metadata: const {'purpose': 'offline-poc', 'region': 'cordoba'},
          acceptExpired: false,
        ),
        (progress) {
          final required = progress.requiredResourceCount;
          final value = required == 0
              ? 0.0
              : progress.completedResourceCount / required;
          if (mounted) setState(() => _styleProgress = value.clamp(0.0, 1.0));
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
          if (mounted) setState(() => _tileProgress = value.clamp(0.0, 1.0));
        },
      );

      await Future.wait([styleFuture, regionFuture]);
      final region = _tileStore!.tileRegion(_regionId);
      final stylePack = _offlineManager!.stylePack(_styleUri);
      if (!mounted) return;
      setState(() {
        _hasOfflineRegion = region != null && stylePack != null;
        _message = _hasOfflineRegion
            ? 'Descarga terminada. Activa modo avión y reinicia la app para validar.'
            : 'La descarga terminó, pero el SDK no confirma región y estilo guardados.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Error durante la descarga offline: $error';
        _message = 'La descarga no se ha podido confirmar.';
      });
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapbox · prueba offline'),
        actions: [
          IconButton(
            tooltip: 'Revisar almacenamiento',
            onPressed: _initializing ? null : _initializeOfflineStore,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey('mapbox-poc-map'),
            styleUri: _styleUri,
            cameraOptions: CameraOptions(center: _cordobaCenter, zoom: 12),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Card(
                margin: const EdgeInsets.all(12),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Prueba controlada · Córdoba',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Estilo Outdoors · zoom 8–15 · región delimitada. '
                        'No descarga España completa.',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (_accessToken.isEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Falta ACCESS_TOKEN. Ejecuta con --dart-define=ACCESS_TOKEN=…',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _ProgressRow(label: 'Estilo', value: _styleProgress),
                      const SizedBox(height: 6),
                      _ProgressRow(label: 'Región', value: _tileProgress),
                      const SizedBox(height: 8),
                      Text(
                        _initializing
                            ? 'Comprobando almacenamiento…'
                            : (_message ?? 'Listo para probar.'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (_hasOfflineRegion)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'El SDK detecta datos offline guardados; aún falta probar sin red.',
                            style: TextStyle(fontSize: 12, color: Colors.green),
                          ),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _error!,
                          style: const TextStyle(fontSize: 12, color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _initializing || _downloading || _accessToken.isEmpty
                            ? null
                            : _downloadRegion,
                        icon: _downloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download),
                        label: Text(_downloading ? 'Descargando…' : 'Descargar mapa offline'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
    final percent = (value * 100).round();
    return Row(
      children: [
        SizedBox(width: 54, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(child: LinearProgressIndicator(value: value)),
        const SizedBox(width: 8),
        SizedBox(
          width: 38,
          child: Text('$percent%', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
