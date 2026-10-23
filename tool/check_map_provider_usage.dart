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
    final path = entity.path.replaceAll('\\', '/');
    final content = entity.readAsStringSync();

    if (content.contains(forbiddenTileHost)) {
      violations.add('$path: direct OSM tile host');
    }
  }

  final mapPage = File('lib/features/map/maplibre_map_page.dart');
  if (!mapPage.existsSync()) {
    violations.add('MapLibre map page is missing.');
  } else {
    final mapContent = mapPage.readAsStringSync();
    if (!mapContent.contains("package:maplibre_gl/") ||
        !mapContent.contains('MapLibreMapViewport(')) {
      violations.add(
        'Map page must use the existing MapLibre Flutter integration.',
      );
    }
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
    'Map provider validation passed: MapLibre Flutter integration found.',
  );
}
