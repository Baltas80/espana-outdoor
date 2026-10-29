import 'dart:io';

const forbiddenTileHost = 'tile.openstreetmap.org';

void main() {
  final violations = <String>[];
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    stderr.writeln('lib/ directory not found.');
    exitCode = 2;
    return;
  }

  for (final entity in lib.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\\\', '/');
    final source = entity.readAsStringSync();

    if (source.contains(forbiddenTileHost)) {
      violations.add('$path: direct OSM tile host');
    }
  }

  for (final entity in lib.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\\\', '/');
    final source = entity.readAsStringSync();
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync() ||
      !pubspec.readAsStringSync().contains('mapbox_maps_flutter:')) {
    violations.add('pubspec.yaml must declare mapbox_maps_flutter.');
  }

  final mapPage = File('lib/features/map/mapbox_map_page.dart');
  if (!mapPage.existsSync()) {
    violations.add('Mapbox primary map page is missing.');
  } else {
    final mapContent = mapPage.readAsStringSync();
    if (!mapContent.contains("package:mapbox_maps_flutter/") ||
        !mapContent.contains('MapboxMapViewport(')) {
      violations.add(
        'Primary map page must use the configured Mapbox Flutter integration.',
      );
    }
  }

  final viewport = File('lib/features/map/mapbox_map_viewport.dart');
  if (!viewport.existsSync() ||
      !viewport.readAsStringSync().contains('mapbox://styles/mapbox/outdoors-v12')) {
    violations.add('Mapbox Outdoors style configuration is missing.');
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Map provider validation failed:');
    for (final violation in violations) {
      stderr.writeln(' - $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Map provider validation passed: Mapbox primary map and approved style found.',
  );
}
