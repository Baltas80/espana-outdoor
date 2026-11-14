import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:espana_outdoors/core/contracts/routing_service.dart';
import 'package:espana_outdoors/infrastructure/routing/mapbox_navigation_routing_service.dart';

const _navigationChannel = MethodChannel('com.espanaoutdoors/navigation');
const _regionId = 'espana-outdoor-cordoba-poc';
const _styleUri = 'mapbox://styles/mapbox/outdoors-v12';
const _regionRing = <List<double>>[
  [-4.84, 37.85],
  [-4.72, 37.85],
  [-4.72, 37.93],
  [-4.84, 37.93],
  [-4.84, 37.85],
];
// Keep the connected proof away from the Córdoba offline download polygon.
const _onlineRoutePoints = [
  LatLng(37.3880, -5.9850),
  LatLng(37.3920, -5.9900),
];
const _offlineRoutePoints = [
  LatLng(37.8882, -4.7794),
  LatLng(37.8900, -4.7700),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  const mode = String.fromEnvironment(
    'ROUTE_TEST_MODE',
    defaultValue: 'online_and_download',
  );

  testWidgets('Mapbox real route validation ($mode)', (tester) async {
    expect(
      accessToken,
      startsWith('pk.'),
      reason: 'The test requires a valid public Mapbox access token.',
    );

    // Match production startup ordering: configure the persistent native
    // TileStore before any route request or MapWidget exists in this test.
    MapboxOptions.setAccessToken(accessToken);
    await _navigationChannel.invokeMethod<void>('configure', {
      'accessToken': accessToken,
    });
    final service = MapboxNavigationRoutingService(accessToken: accessToken);

    if (mode == 'online_and_download') {
      final onlineRoute = await service.route(
        const RouteRequest(profile: 'walking', points: _onlineRoutePoints),
      );
      _expectUsableRoute(onlineRoute);
      expect(
        onlineRoute.source,
        'online',
        reason: 'The connected route outside the Córdoba region must come from the online router.',
      );
      // ignore: avoid_print
      print(
        'MAPBOX_ROUTE_VALIDATION source=online '
        'distance_m=${onlineRoute.distanceMeters} '
        'duration_s=${onlineRoute.durationSeconds} '
        'geometry_points=${onlineRoute.points.length}',
      );

      await _navigationChannel.invokeMethod<void>(
        'downloadOfflineRegion',
        {
          'regionId': _regionId,
          'styleUri': _styleUri,
          'coordinates': _regionRing,
          'minZoom': 8,
          'maxZoom': 15,
        },
      );
      // Native downloadOfflineRegion completes only after the TileStore
      // callback succeeds and the persistent completion marker is committed.
      // Query TileStore itself afterward so an ID/marker alone cannot pass.
      final downloaded = await _navigationChannel.invokeMethod<bool>(
        'hasOfflineRegion',
        {'regionId': _regionId},
      );
      expect(
        downloaded,
        isTrue,
        reason: 'Map and walking-routing tiles must be stored before disconnecting.',
      );
      // ignore: avoid_print
      print('MAPBOX_OFFLINE_REGION_READY id=$_regionId');
      return;
    }

    if (mode == 'offline') {
      final downloaded = await _navigationChannel.invokeMethod<bool>(
        'hasOfflineRegion',
        {'regionId': _regionId},
      );
      expect(
        downloaded,
        isTrue,
        reason: 'The same persistent TileStore must survive force-stop and app restart.',
      );

      // This is a new request, not a cached copy of the connected route.
      final offlineRoute = await service.route(
        const RouteRequest(profile: 'walking', points: _offlineRoutePoints),
      );
      _expectUsableRoute(offlineRoute);
      expect(
        offlineRoute.source,
        'offline',
        reason: 'In airplane mode, the new route must come from RouterOrigin.OFFLINE.',
      );
      // ignore: avoid_print
      await _expectOfflineMapRendered(tester, binding);
      // ignore: avoid_print
      print(
        'MAPBOX_ROUTE_VALIDATION source=offline '
        'distance_m=${offlineRoute.distanceMeters} '
        'duration_s=${offlineRoute.durationSeconds} '
        'geometry_points=${offlineRoute.points.length}',
      );
      return;
    }

    fail('Unsupported ROUTE_TEST_MODE: $mode');
  });
}


Future<void> _expectOfflineMapRendered(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final loaded = Completer<void>();
  final loadError = Completer<String>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MapWidget(
          styleUri: _styleUri,
          viewport: CameraViewportState(
            center: Point(coordinates: Position(-4.7794, 37.8882)),
            zoom: 13,
            bearing: 0,
            pitch: 0,
          ),
          onMapLoadedListener: (_) {
            if (!loaded.isCompleted) loaded.complete();
          },
          onMapLoadErrorListener: (event) {
            if (!loadError.isCompleted) loadError.complete(event.toString());
          },
        ),
      ),
    ),
  );

  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!loaded.isCompleted && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (loadError.isCompleted) {
      fail('Mapbox offline map failed to load: ${await loadError.future}');
    }
  }
  expect(
    loaded.isCompleted,
    isTrue,
    reason: 'Mapbox must render the style and all visible tiles from the shared offline TileStore.',
  );
  final screenshot = await binding.takeScreenshot('mapbox-offline-map-rendered');
  expect(screenshot, isNotEmpty);
  final metrics = await _inspectRenderedPixels(screenshot);
  expect(
    metrics.$1,
    greaterThan(8),
    reason: 'The offline map screenshot must contain varied map pixels, not a blank canvas.',
  );
  expect(
    metrics.$2,
    greaterThan(0.95),
    reason: 'The offline map screenshot must be predominantly opaque.',
  );
  // ignore: avoid_print
  print(
    'MAPBOX_OFFLINE_MAP_RENDERED screenshot_bytes=${screenshot.length} '
    'unique_colors=${metrics.$1} opaque_ratio=${metrics.$2.toStringAsFixed(3)}',
  );
}

Future<(int, double)> _inspectRenderedPixels(Uint8List screenshot) async {
  final codec = await ui.instantiateImageCodec(screenshot);
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) {
        throw const FormatException('Could not decode the offline map screenshot.');
      }
      final pixels = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      const bytesPerSample = 4 * 16;
      final colors = <int>{};
      var sampledPixels = 0;
      var opaquePixels = 0;
      for (var offset = 0; offset + 3 < pixels.length; offset += bytesPerSample) {
        final red = pixels[offset];
        final green = pixels[offset + 1];
        final blue = pixels[offset + 2];
        final alpha = pixels[offset + 3];
        sampledPixels++;
        if (alpha >= 240) opaquePixels++;
        colors.add(
          ((red >> 4) << 12) |
              ((green >> 4) << 8) |
              ((blue >> 4) << 4) |
              (alpha >> 4),
        );
      }
      if (sampledPixels == 0) {
        throw const FormatException('Offline map screenshot contains no pixels.');
      }
      return (colors.length, opaquePixels / sampledPixels);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

void _expectUsableRoute(RouteResult route) {
  expect(route.points.length, greaterThan(1));
  expect(route.distanceMeters, isNotNull);
  expect(route.distanceMeters, greaterThan(0));
  expect(route.durationSeconds, isNotNull);
  expect(route.durationSeconds, greaterThan(0));
  expect(route.steps, isNotEmpty);
}
