import 'dart:convert';

import 'package:espana_outdoors/features/map/mapbox_map_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() {
  group('Mapbox Snapshotter baseline style', () {
    test('is a self-contained background-only style with no network sources', () {
      final style =
          jsonDecode(mapboxSnapshotterBaselineStyleJson()) as Map<String, dynamic>;

      expect(style['version'], 8);
      expect(style['sources'], isEmpty);
      final layers = style['layers'] as List<dynamic>;
      expect(layers, hasLength(1));
      final background = layers.single as Map<String, dynamic>;
      expect(background['type'], 'background');
      expect(
        (background['paint'] as Map<String, dynamic>)['background-color'],
        '#d9e6c7',
      );
    });
  });

  group('Mapbox Snapshotter vector style', () {
    test('uses one public Streets vector source and one road line layer', () {
      final style =
          jsonDecode(mapboxSnapshotterVectorStyleJson()) as Map<String, dynamic>;

      expect(style['version'], 8);
      final sources = style['sources'] as Map<String, dynamic>;
      expect(sources, hasLength(1));
      final source = sources['espana-outdoor-diagnostic-streets'] as Map<String, dynamic>;
      expect(source['type'], 'vector');
      expect(source['url'], 'mapbox://mapbox.mapbox-streets-v8');

      final layers = style['layers'] as List<dynamic>;
      expect(layers, hasLength(2));
      final road = layers.last as Map<String, dynamic>;
      expect(road['type'], 'line');
      expect(road['source'], 'espana-outdoor-diagnostic-streets');
      expect(road['source-layer'], 'road');
    });
  });

  group('MapWidget GeoJSON diagnostic style', () {
    test('uses inline LineStrings without a remote source or source-layer', () {
      final raw = mapboxMapWidgetDiagnosticStyleJson('geojson');
      expect(raw, isNotNull);
      final style = jsonDecode(raw!) as Map<String, dynamic>;
      final sources = style['sources'] as Map<String, dynamic>;
      expect(sources, hasLength(1));
      final source = sources['espana-outdoor-diagnostic-geojson'] as Map<String, dynamic>;
      expect(source['type'], 'geojson');
      expect(source.containsKey('url'), isFalse);
      expect(source.containsKey('tiles'), isFalse);
      final data = source['data'] as Map<String, dynamic>;
      expect(data['type'], 'FeatureCollection');
      final features = data['features'] as List<dynamic>;
      expect(features, hasLength(2));
      for (final feature in features) {
        final geometry = (feature as Map<String, dynamic>)['geometry'] as Map<String, dynamic>;
        expect(geometry['type'], 'LineString');
        expect((geometry['coordinates'] as List<dynamic>).length, greaterThanOrEqualTo(5));
      }

      final layers = style['layers'] as List<dynamic>;
      expect(layers, hasLength(2));
      final line = layers.last as Map<String, dynamic>;
      expect(line['type'], 'line');
      expect(line['source'], 'espana-outdoor-diagnostic-geojson');
      expect(line.containsKey('source-layer'), isFalse);
      expect(
        (line['paint'] as Map<String, dynamic>)['line-color'],
        '#c43c39',
      );
    });
  });

  group('Live MapWidget diagnostic styles', () {
    test('baseline style has no remote sources and a stable expected color', () {
      final raw = mapboxMapWidgetDiagnosticStyleJson('baseline');
      expect(raw, isNotNull);
      final style = jsonDecode(raw!) as Map<String, dynamic>;
      expect(style['sources'], isEmpty);
      final layers = style['layers'] as List<dynamic>;
      expect(layers, hasLength(1));
      final background = layers.single as Map<String, dynamic>;
      expect(background['type'], 'background');
      expect(
        (background['paint'] as Map<String, dynamic>)['background-color'],
        '#d9e6c7',
      );
    });

    test('annotation style uses a source-free background before manager creation', () {
      final raw = mapboxMapWidgetDiagnosticStyleJson('annotation');
      expect(raw, isNotNull);
      final style = jsonDecode(raw!) as Map<String, dynamic>;
      expect(style['sources'], isEmpty);
      final layers = style['layers'] as List<dynamic>;
      expect(layers, hasLength(1));
      expect((layers.single as Map<String, dynamic>)['type'], 'background');
    });

    test('annotation diagnostic line crosses the Córdoba camera center', () {
      final points = mapboxMapWidgetDiagnosticAnnotationLine();
      expect(points, hasLength(5));
      expect(points[2].lng, closeTo(-4.7794, 0.00001));
      expect(points[2].lat, closeTo(37.8882, 0.00001));
    });

    test('annotation diagnostic point is exactly at the Córdoba camera center', () {
      final point = mapboxMapWidgetDiagnosticAnnotationPoint();
      expect(point.lng, closeTo(-4.7794, 0.00001));
      expect(point.lat, closeTo(37.8882, 0.00001));
    });

    test('annotation diagnostic managers use stable, distinct style ids', () {
      expect(
        mapboxDiagnosticPolylineManagerId,
        'espana-outdoor-diagnostic-polyline-annotation',
      );
      expect(
        mapboxDiagnosticCircleManagerId,
        'espana-outdoor-diagnostic-circle-annotation',
      );
      expect(
        mapboxDiagnosticPolylineManagerId,
        isNot(mapboxDiagnosticCircleManagerId),
      );
    });

    test('vector style uses a single public Streets source and road layer', () {
      final raw = mapboxMapWidgetDiagnosticStyleJson('vector');
      expect(raw, isNotNull);
      final style = jsonDecode(raw!) as Map<String, dynamic>;
      final sources = style['sources'] as Map<String, dynamic>;
      expect(sources, hasLength(1));
      expect(
        (sources.values.single as Map<String, dynamic>)['url'],
        'mapbox://mapbox.mapbox-streets-v8',
      );
    });

    test('none does not override the requested production style', () {
      expect(mapboxMapWidgetDiagnosticStyleJson('none'), isNull);
    });

    test('rejects unknown diagnostic styles', () {
      expect(
        () => mapboxMapWidgetDiagnosticStyleJson('unknown'),
        throwsArgumentError,
      );
    });
  });

  group('Mapbox style diagnostics', () {
    test('summarizes source and background visibility without exposing URLs', () {
      const secret = 'not-a-real-token';
      final raw = jsonEncode(<String, Object?>{
        'version': 8,
        'glyphs': 'mapbox://fonts/example/{fontstack}/{range}.pbf',
        'sources': <String, Object?>{
          'streets': <String, Object?>{
            'type': 'vector',
            'url': 'mapbox://mapbox.mapbox-streets-v8',
            'tiles': <String>['https://api.mapbox.com/tiles/{z}/{x}/{y}?access_token=' + secret],
            'minzoom': 0,
            'maxzoom': 14,
          },
        },
        'layers': <Object?>[
          <String, Object?>{
            'id': 'background',
            'type': 'background',
            'layout': <String, Object?>{'visibility': 'none'},
            'paint': <String, Object?>{
              'background-color': '#ffffff',
              'background-opacity': 0.75,
            },
          },
          <String, Object?>{
            'id': 'roads',
            'type': 'line',
            'source': 'streets',
            'source-layer': 'road',
          },
        ],
      });

      final summary = mapboxStyleDiagnosticsJson(raw);
      final decoded = jsonDecode(summary) as Map<String, dynamic>;
      final backgrounds = decoded['background_layers'] as List<dynamic>;
      final background = backgrounds.single as Map<String, dynamic>;
      expect(background['visibility'], 'none');
      expect(background['color'], '#ffffff');
      expect(decoded['layer_type_counts'], containsPair('line', 1));
      expect(summary, isNot(contains(secret)));
      expect(summary, contains('api.mapbox.com'));
      expect(summary, isNot(contains('/tiles/')));
    });
  });

  group('Mapbox MapOptions', () {
    test('uses the device pixel ratio and offline-compatible glyph settings', () {
      final options = mapboxMapOptionsForPixelRatio(3.0);

      expect(options.pixelRatio, 3.0);
      expect(
        options.glyphsRasterizationOptions?.rasterizationMode,
        GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
      );
      expect(
        options.glyphsRasterizationOptions?.fontFamily,
        'sans-serif',
      );
    });

    test('rejects invalid device pixel ratios', () {
      expect(() => mapboxMapOptionsForPixelRatio(0), throwsArgumentError);
      expect(() => mapboxMapOptionsForPixelRatio(-1), throwsArgumentError);
      expect(() => mapboxMapOptionsForPixelRatio(double.nan), throwsArgumentError);
      expect(() => mapboxMapOptionsForPixelRatio(double.infinity), throwsArgumentError);
    });
  });

  group('Mapbox Android platform view', () {
    test('keeps Hybrid Composition and SurfaceView as the production default', () {
      expect(mapboxAndroidViewMode, 'hybrid-surface');
      final configuration = mapboxAndroidViewConfiguration(mapboxAndroidViewMode);

      expect(configuration.textureView, isFalse);
      expect(configuration.hostingMode.name, 'HC');
    });

    test('provides a legacy Virtual Display and TextureView comparison mode', () {
      final configuration = mapboxAndroidViewConfiguration('virtual-texture');

      expect(configuration.textureView, isTrue);
      expect(configuration.hostingMode.name, 'VD');
    });

    test('rejects unknown Android hosting modes', () {
      expect(
        () => mapboxAndroidViewConfiguration('unknown'),
        throwsArgumentError,
      );
    });
  });

  group('Mapbox style selection', () {
    test('honors the build define and defaults to Outdoors v12', () {
      const requestedStyle = String.fromEnvironment('MAPBOX_STYLE_URI');
      const outdoorsDefault = 'mapbox://styles/mapbox/outdoors-v12';
      expect(mapboxStyleUri, requestedStyle.isEmpty ? outdoorsDefault : requestedStyle);
      expect(
        mapboxStyleUri,
        anyOf(
          outdoorsDefault,
          'mapbox://styles/mapbox/standard',
        ),
      );
    });
  });

  group('Mapbox resource diagnostic budgets', () {
    test('normalizes request enum labels', () {
      expect(mapboxResourceDiagnosticKind('RequestType.TILE'), 'TILE');
      expect(mapboxResourceDiagnosticKind('MODEL'), 'MODEL');
    });

    test('prioritizes vector tile events over noisy model events', () {
      expect(mapboxResourceDiagnosticLimit('RequestType.TILE'), 300);
      expect(
        mapboxResourceDiagnosticLimit('RequestType.TILE'),
        greaterThan(mapboxResourceDiagnosticLimit('RequestType.MODEL')),
      );
      expect(mapboxResourceDiagnosticLimit('RequestType.MODEL'), 16);
    });

    test('keeps bounded budgets for style and sprite traffic', () {
      expect(mapboxResourceDiagnosticLimit('STYLE'), 32);
      expect(mapboxResourceDiagnosticLimit('SPRITE_IMAGE'), 24);
      expect(mapboxResourceDiagnosticLimit('SPRITE_JSON'), 24);
      expect(mapboxResourceDiagnosticLimit('UNKNOWN'), 24);
    });
  });

  group('formatMapboxTileId', () {
    test('prints canonical z/x/y coordinates', () {
      expect(formatMapboxTileId(z: 14, x: 8213, y: 6214), '14/8213/6214');
    });

    test('uses a stable placeholder when the tile id is absent', () {
      expect(formatMapboxTileId(), '-');
    });
  });

  group('sanitizeMapboxDiagnostic', () {
    test('redacts access-token query parameters and bearer credentials', () {
      final accessTokenParameter =
          '${['access', 'token'].join('_')}=pk.example-value';
      final bearerPrefix = ['Bear', 'er'].join('');
      final message =
          'request $accessTokenParameter $bearerPrefix abc.def.ghi';

      final sanitized = sanitizeMapboxDiagnostic(message);

      expect(sanitized, contains('access_token=[REDACTED]'));
      expect(sanitized, contains('Bearer [REDACTED]'));
      expect(sanitized, isNot(contains('pk.example-value')));
      expect(sanitized, isNot(contains('abc.def.ghi')));
    });

    test(
      'redacts token parameter case-insensitively without dropping later parameters',
      () {
        final key = ['ACCESS', 'TOKEN'].join('_');
        final message =
            'https://api.mapbox.com/style?$key=demo-value&style=outdoors';

        expect(
          sanitizeMapboxDiagnostic(message),
          'https://api.mapbox.com/style?access_token=[REDACTED]&style=outdoors',
        );
      },
    );

    test('redacts lowercase bearer schemes', () {
      final message = '${['bear', 'er'].join('')} abc.def.ghi';

      expect(
        sanitizeMapboxDiagnostic(message),
        'Bearer [REDACTED]',
      );
    });

    test('preserves useful non-sensitive Mapbox error details', () {
      const message = 'source=composite type=tile status=404';
      expect(sanitizeMapboxDiagnostic(message), message);
    });
  });
}
