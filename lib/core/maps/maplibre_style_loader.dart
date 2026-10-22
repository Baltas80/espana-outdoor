import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../offline/offline_package_verifier.dart';
import '../offline/offline_region.dart';
import '../offline/offline_region_store.dart';
import 'pmtiles_local_source.dart';

const _catalogUrl = String.fromEnvironment('OFFLINE_CATALOG_URL');
const _directPmTilesUrl = String.fromEnvironment('MAP_PMTILES_URL');
const _styleUrl = String.fromEnvironment(
  'MAP_STYLE_URL',
  defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
);
const _inlineStyleJson = String.fromEnvironment('MAP_STYLE_JSON');
const _defaultAttribution = String.fromEnvironment(
  'MAP_ATTRIBUTION',
  defaultValue: '© OpenStreetMap contributors',
);
const _offlineStyleAsset = 'assets/maps/offline_style.json';

/// Builds a MapLibre style backed by the newest verified local PMTiles package
/// when one exists. Otherwise it uses the configured HTTPS PMTiles archive or
/// the validated catalog entry.
Future<String> loadMapLibreStyle() async {
  final localPath = await _findStoredVerifiedPmTiles();
  if (localPath != null) {
    final sourceUrl = 'pmtiles://${Uri.file(localPath)}';
    debugPrint('EO_MAPLIBRE_PM TILES local source: $sourceUrl');
    return _styleForSource(
      sourceUrl: sourceUrl,
      attribution: _defaultAttribution,
      styleJson: await rootBundle.loadString(_offlineStyleAsset),
    );
  }

  late final String sourceUrl;
  var attribution = _defaultAttribution;
  if (_directPmTilesUrl.isNotEmpty) {
    sourceUrl = _directPmTilesUrl;
  } else {
    final region = await _loadCatalogRegion();
    final expectedFileName =
        '${region.id}-${region.sha256.substring(0, 12)}.pmtiles';
    final verifiedPath = await findValidLocalPmTiles(
      expectedFileName: expectedFileName,
      expectedSha256: region.sha256,
    );
    if (verifiedPath != null) {
      final sourceUrl = 'pmtiles://${Uri.file(verifiedPath)}';
      debugPrint('EO_MAPLIBRE_PM TILES catalog-local source: $sourceUrl');
      return _styleForSource(
        sourceUrl: sourceUrl,
        attribution: region.attribution,
        styleJson: await rootBundle.loadString(_offlineStyleAsset),
      );
    }
    sourceUrl = region.downloadUrl.toString();
    attribution = region.attribution;
  }

  final uri = Uri.tryParse(sourceUrl);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw StateError('La fuente PMTiles remota debe usar HTTPS.');
  }

  return _styleForSource(
    sourceUrl: 'pmtiles://$uri',
    attribution: attribution,
    styleJson: await _loadConfiguredStyle(),
  );
}

Future<String> _loadConfiguredStyle() async {
  if (_inlineStyleJson.isNotEmpty) return _inlineStyleJson;

  if (_styleUrl.startsWith('asset://')) {
    return rootBundle.loadString(_styleUrl.substring('asset://'.length));
  }

  final uri = Uri.tryParse(_styleUrl);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw StateError('El estilo cartográfico remoto debe usar HTTPS.');
  }

  final response = await http.get(uri).timeout(const Duration(seconds: 12));
  if (response.statusCode != 200) {
    throw StateError(
      'No se pudo cargar el estilo cartográfico (${response.statusCode}).',
    );
  }
  return response.body;
}

@visibleForTesting
String styleWithPmTilesSource({
  required String styleJson,
  required String sourceUrl,
  required String attribution,
}) {
  final decoded = jsonDecode(styleJson);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException(
      'El estilo cartográfico debe ser un objeto JSON.',
    );
  }

  final sources = decoded['sources'];
  if (sources is! Map<String, dynamic>) {
    throw const FormatException('El estilo cartográfico no contiene fuentes.');
  }

  final source = sources['openmaptiles'];
  if (source is! Map<String, dynamic> || source['type'] != 'vector') {
    throw const FormatException(
      'El estilo debe declarar la fuente vectorial openmaptiles.',
    );
  }

  source
    ..remove('tiles')
    ..['url'] = sourceUrl
    ..['attribution'] = attribution;
  return jsonEncode(decoded);
}

String _styleForSource({
  required String sourceUrl,
  required String attribution,
  required String styleJson,
}) => styleWithPmTilesSource(
  styleJson: styleJson,
  sourceUrl: sourceUrl,
  attribution: attribution,
);

Future<String?> _findStoredVerifiedPmTiles() async {
  final record = OfflineRegionStore().get('spain');
  if (record == null || !record.hasValidArtifact) return null;

  final path = record.localPath?.trim();
  final sha256 = record.sha256?.trim().toLowerCase();
  if (path == null ||
      path.isEmpty ||
      sha256 == null ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
    return null;
  }

  final file = File(path);
  if (!await file.exists()) return null;

  final stat = await file.stat();
  if (stat.size != record.bytesDownloaded) return null;

  final recordedModified = record.fileModifiedAt;
  if (recordedModified != null &&
      stat.modified.millisecondsSinceEpoch ==
          recordedModified.millisecondsSinceEpoch) {
    return file.path;
  }

  if (recordedModified == null) {
    await OfflineRegionStore().put(
      record.copyWith(fileModifiedAt: stat.modified),
    );
    return file.path;
  }

  try {
    await const OfflinePackageVerifier().verifyFile(
      file,
      expectedSha256: sha256,
    );
    await OfflineRegionStore().put(
      record.copyWith(fileModifiedAt: stat.modified),
    );
    return file.path;
  } on Object {
    return null;
  }
}

Future<OfflineRegion> _loadCatalogRegion() async {
  if (_catalogUrl.isEmpty) {
    throw StateError(
      'No hay PMTiles configurado: falta MAP_PMTILES_URL y OFFLINE_CATALOG_URL.',
    );
  }

  final response = await http
      .get(Uri.parse(_catalogUrl))
      .timeout(const Duration(seconds: 12));
  if (response.statusCode != 200) {
    throw StateError(
      'No se pudo cargar el catálogo cartográfico (${response.statusCode}).',
    );
  }

  final decoded = jsonDecode(response.body);
  Map<String, Object?>? raw;
  if (decoded is Map) {
    raw = Map<String, Object?>.from(decoded);
  } else if (decoded is List) {
    final entries = decoded
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
    for (final entry in entries) {
      if (entry['id']?.toString().toLowerCase() == 'spain') {
        raw = entry;
        break;
      }
    }
    raw ??= entries.isEmpty ? null : entries.first;
  }

  if (raw == null) {
    throw StateError('El catálogo cartográfico no tiene un formato válido.');
  }
  return OfflineRegion.fromJson(raw);
}
