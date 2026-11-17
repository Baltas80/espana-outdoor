import 'dart:convert';
import 'package:espana_outdoors/features/map/mapbox_map_viewport.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

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
