import 'dart:convert';

import 'package:http/http.dart' as http;

import 'offline_region.dart';

class OfflineRegionCatalog {
  OfflineRegionCatalog({
    required Uri endpoint,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _endpoint = _validateEndpoint(endpoint),
        _client = client ?? http.Client(),
        _requestTimeout = requestTimeout {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'Must be positive.',
      );
    }
  }

  final Uri _endpoint;
  final http.Client _client;
  final Duration _requestTimeout;

  Future<List<OfflineRegion>> fetch() async {
    final response =
        await _client.get(_endpoint).timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Offline region catalog failed: HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body);

    if (decoded is Map) {
      return [
        OfflineRegion.fromJson(Map<String, Object?>.from(decoded)),
      ];
    }

    if (decoded is List) {
      if (decoded.isEmpty) {
        throw const FormatException('Offline region catalog must not be empty.');
      }
      final entries = <OfflineRegion>[];
      final identifiers = <String>{};
      for (final item in decoded) {
        if (item is! Map) {
          throw const FormatException(
            'Every offline catalog entry must be a JSON object.',
          );
        }
        final entry = OfflineRegion.fromJson(Map<String, Object?>.from(item));
        if (!identifiers.add(entry.id)) {
          throw FormatException(
            'Offline region catalog contains duplicate id: ${entry.id}.',
          );
        }
        entries.add(entry);
      }
      return entries;
    }

    throw const FormatException(
      'Offline region catalog must be a JSON object or array.',
    );
  }

  static Uri? fromEnvironment() {
    const raw = String.fromEnvironment('OFFLINE_CATALOG_URL');
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }

  static Uri _validateEndpoint(Uri endpoint) {
    if (endpoint.scheme != 'https' || endpoint.host.isEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Offline catalog endpoints must use HTTPS.',
      );
    }
    return endpoint;
  }
}
