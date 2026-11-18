import 'package:espana_outdoors/features/map/mapbox_map_viewport.dart';
import 'package:espana_outdoors/features/offline/offline_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Córdoba offline tileset descriptor', () {
    test('uses the shared Mapbox style, zoom range and device pixel ratio', () {
      final descriptor = cordobaOfflineTilesetDescriptorOptions(
        pixelRatio: 2.625,
      );

      expect(descriptor.styleURI, mapboxStyleUri);
      expect(descriptor.minZoom, 8);
      expect(descriptor.maxZoom, 15);
      expect(descriptor.pixelRatio, 2.625);
    });

    test('rejects invalid pixel ratios before starting a download', () {
      expect(
        () => cordobaOfflineTilesetDescriptorOptions(pixelRatio: 0),
        throwsArgumentError,
      );
      expect(
        () => cordobaOfflineTilesetDescriptorOptions(pixelRatio: -1),
        throwsArgumentError,
      );
      expect(
        () => cordobaOfflineTilesetDescriptorOptions(pixelRatio: double.nan),
        throwsArgumentError,
      );
      expect(
        () => cordobaOfflineTilesetDescriptorOptions(pixelRatio: double.infinity),
        throwsArgumentError,
      );
    });
  });
}
