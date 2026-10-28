import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const _styleUrl = String.fromEnvironment(
  'MAP_STYLE_URL',
  defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
);
const _inlineStyleJson = String.fromEnvironment('MAP_STYLE_JSON');

/// Loads the configured MapLibre style without requiring a particular tile
/// archive format or an offline package catalog.
Future<String> loadMapLibreStyle() async {
  if (_inlineStyleJson.trim().isNotEmpty) {
    return _inlineStyleJson;
  }

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
