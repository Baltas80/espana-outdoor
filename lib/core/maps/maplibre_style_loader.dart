import 'package:flutter/services.dart';

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
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty) {
    throw StateError('El estilo cartográfico remoto debe usar HTTPS.');
  }

  // MapLibre Native accepts a style URL directly. Keeping it as a URL lets
  // MapLibre resolve sprite, glyph and source resources relative to that style.
  return uri.toString();
}
