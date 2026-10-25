import 'dart:io';

const forbiddenTileHost = 'tile.openstreetmap.org';
const forbiddenImports = <String>{
  'package:agus_maps_flutter/',
};
const forbiddenTerms = <String>{
  'Agus Maps',
  'agus_maps',
  'CoMaps',
  'comaps_data',
  'AGUS_MAPS_HOME',
};

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
    for (final importPrefix in forbiddenImports) {
      if (content.contains("'$importPrefix")) {
        violations.add('$path: forbidden map import $importPrefix');
      }
    }
    for (final term in forbiddenTerms) {
      if (content.contains(term)) {
        violations.add('$path: forbidden legacy map term $term');
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Forbidden legacy/direct map provider usage detected:');
    for (final violation in violations) {
      stderr.writeln(' - $violation');
    }
    stderr.writeln(
      'España Outdoor uses MapLibre as the renderer and PMTiles/R2 '
      'as the configured vector-data distribution path. Legacy map providers '
      'and direct public OSM tile downloads are forbidden.',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Map provider usage guard passed: MapLibre + PMTiles architecture.',
  );
}
