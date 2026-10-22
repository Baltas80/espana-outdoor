import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/outdoor_visuals.dart';
import '../../core/map/map_service.dart';
import '../../core/maps/pmtiles_local_source.dart';
import '../../core/offline/offline_region.dart';
import '../../core/offline/offline_package_verifier.dart';
import '../../core/offline/offline_region_catalog.dart';
import '../../core/offline/offline_region_downloader.dart';
import '../../core/offline/offline_region_store.dart';

const _catalogUrl = String.fromEnvironment('OFFLINE_CATALOG_URL');

class OfflinePage extends StatefulWidget {
  const OfflinePage({super.key});
  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage> {
  late Future<List<OfflineRegion>> _catalogFuture;
  final Set<String> _readyIds = <String>{};
  bool _downloading = false;
  String _status = 'Preparando catálogo PMTiles…';

  @override
  void initState() {
    super.initState();
    _catalogFuture = _loadCatalog();
  }

  Future<List<OfflineRegion>> _loadCatalog() async {
    try {
      if (_catalogUrl.isEmpty) {
        throw StateError('OFFLINE_CATALOG_URL no está configurado.');
      }

      final regions = await OfflineRegionCatalog(
        endpoint: Uri.parse(_catalogUrl),
      ).fetch();

      await _refreshReady(regions);
      return regions;
    } on Object {
      // The catalog is remote metadata. A verified local package is sufficient
      // to keep the offline screen useful when the device has no connectivity.
      final localReady = await _hasVerifiedLocalSpain();
      if (!localReady) rethrow;

      if (mounted) {
        setState(() {
          _readyIds.add('spain');
          _status = 'España disponible sin conexión. Catálogo remoto no disponible.';
        });
      }
      return const <OfflineRegion>[];
    }
  }

  Future<bool> _hasVerifiedLocalSpain() async {
    final record = OfflineRegionStore().get('spain');
    if (record == null || !record.hasValidArtifact) return false;

    final path = record.localPath?.trim();
    final sha256 = record.sha256?.trim().toLowerCase();
    if (path == null || path.isEmpty || sha256 == null || sha256.length != 64) {
      return false;
    }

    final file = File(path);
    if (!await file.exists()) return false;
    final stat = await file.stat();
    if (stat.size != record.bytesDownloaded) return false;

    final recordedModified = record.fileModifiedAt;
    if (recordedModified == null) {
      await OfflineRegionStore().put(record.copyWith(fileModifiedAt: stat.modified));
      return true;
    }
    if (recordedModified.millisecondsSinceEpoch == stat.modified.millisecondsSinceEpoch) {
      return true;
    }

    try {
      await const OfflinePackageVerifier().verifyFile(file, expectedSha256: sha256);
      await OfflineRegionStore().put(record.copyWith(fileModifiedAt: stat.modified));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasUsableStoredArtifact(OfflineRegionRecord record) async {
    if (!record.hasValidArtifact) return false;
    final path = record.localPath?.trim();
    if (path == null || path.isEmpty) return false;

    final file = File(path);
    if (!await file.exists()) return false;
    final stat = await file.stat();
    if (stat.size != record.bytesDownloaded) return false;

    final modified = record.fileModifiedAt;
    if (modified == null) {
      await OfflineRegionStore().put(record.copyWith(fileModifiedAt: stat.modified));
      return true;
    }
    if (modified.millisecondsSinceEpoch == stat.modified.millisecondsSinceEpoch) {
      return true;
    }

    try {
      await const OfflinePackageVerifier().verifyFile(
        file,
        expectedSha256: record.sha256,
      );
      await OfflineRegionStore().put(record.copyWith(fileModifiedAt: stat.modified));
      return true;
    } catch (_) {
      return false;
    }
  }
  Future<void> _refreshReady(List<OfflineRegion> regions) async {
    final ready = <String>{};
    for (final region in regions) {
      final stored = OfflineRegionStore().get(region.id);
      if (stored != null && await _hasUsableStoredArtifact(stored)) {
        ready.add(region.id);
        continue;
      }

      final fileName =
          '${region.id}-${region.sha256.substring(0, 12)}.pmtiles';
      final path = await findValidLocalPmTiles(
        expectedFileName: fileName,
        expectedSha256: region.sha256,
      );
      if (path != null) ready.add(region.id);
    }
    if (mounted) {
      setState(() {
        _readyIds
          ..clear()
          ..addAll(ready);
      });
    }
  }

  Future<void> _persistVerifiedDownload(
    OfflineRegion region,
    File file,
  ) async {
    final bytes = await file.length();
    final record = OfflineRegionRecord(
      region: OfflineMapRegion(
        id: region.id,
        name: region.name,
        bounds: const MapBounds(
          west: -18.2,
          south: 27.5,
          east: 4.6,
          north: 43.9,
        ),
        minZoom: 3,
        maxZoom: 18,
        providerId: region.providerId,
        styleVersion: region.updatedAt.toIso8601String(),
      ),
      status: OfflineRegionStatus.ready,
      progress: 1,
      bytesDownloaded: bytes,
      bytesTotal: bytes,
      localPath: file.path,
      sha256: region.sha256,
      artifactVersion: region.updatedAt.toIso8601String(),
      fileModifiedAt: (await file.stat()).modified,
      updatedAt: DateTime.now().toUtc(),
    );
    await OfflineRegionStore().put(record);
  }

  Future<void> _downloadRegion(OfflineRegion region) async {
    if (_downloading) return;

    setState(() {
      _downloading = true;
      _status = 'Descargando ${region.name}…';
    });

    try {
      final file = await const OfflineRegionDownloader().startAndVerify(region);
      await _persistVerifiedDownload(region, file);
      await _refreshReady([region]);
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = '${region.name} descargada, verificada y registrada para uso offline.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = 'Error: $error';
      });
    }
  }

  String _size(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mapas offline')),
        body: SafeArea(
          child: FutureBuilder<List<OfflineRegion>>(
            future: _catalogFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _MapCatalogError(
                  message: snapshot.error.toString(),
                  onRetry: () =>
                      setState(() => _catalogFuture = _loadCatalog()),
                );
              }

              final regions = snapshot.data;
              if (regions == null) {
                return const Center(child: CircularProgressIndicator());
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  const OutdoorVisualHero(
                    asset: 'assets/visuals/hero_map.svg',
                    title: 'Mapas offline',
                    subtitle: 'Mapas PMTiles sin conexión y gestión de descargas.',
                  ),
                  const SizedBox(height: 16),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.map_outlined, size: 46),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'España Outdoor utiliza PMTiles como fuente cartográfica. Las descargas offline se almacenan localmente y se verifican mediante SHA-256 antes de considerarse válidas.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (regions.isEmpty && _readyIds.contains('spain')) ...[
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, size: 42),
                            SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'España está descargada, verificada y disponible sin conexión. No se necesita el catálogo remoto para utilizar el mapa local.',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final region in regions) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              region.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(region.description),
                            const SizedBox(height: 4),
                            Text(
                              '${_size(region.sizeBytes)} · ${region.updatedAt.toLocal()}',
                            ),
                            const SizedBox(height: 4),
                            Text('SHA-256: ${region.sha256}'),
                            const SizedBox(height: 12),
                            if (_downloading) const LinearProgressIndicator(),
                            const SizedBox(height: 8),
                            Builder(
                              builder: (context) {
                                final ready = _readyIds.contains(region.id);
                                return FilledButton.icon(
                                  onPressed: _downloading || ready
                                      ? null
                                      : () => _downloadRegion(region),
                                  icon: Icon(
                                    ready
                                        ? Icons.check_circle_outline
                                        : Icons.download_outlined,
                                  ),
                                  label: Text(
                                    ready
                                        ? 'España disponible sin conexión'
                                        : 'Descargar ${region.name}',
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.storage_outlined),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_status)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Motor cartográfico',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'El mapa principal abre paquetes PMTiles verificados con MapLibre.',
                  ),
                ],
              );
            },
          ),
        ),
      );
}

class _MapCatalogError extends StatelessWidget {
  const _MapCatalogError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 52),
              const SizedBox(height: 14),
              const Text(
                'No se pudo obtener el catálogo de mapas',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
}
