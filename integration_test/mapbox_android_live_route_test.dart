import 'dart:async';
import 'dart:math' as math;
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

String _safeMapboxFailureClass(String message) {
  final value = message.toLowerCase();
  final status = RegExp(
    r'\bhttp(?:\s+status\s+code)?\s*[:=]?\s*(\d{3})\b',
  ).firstMatch(value)?.group(1);
  if (status != null) return 'http_$status';
  if (RegExp(r'\b401\b|\b403\b|unauthori[sz]ed|forbidden').hasMatch(value)) {
    return 'authorization';
  }
  if (value.contains('certificate') || value.contains('ssl') || value.contains('tls')) {
    return 'tls';
  }
  if (value.contains('timeout') || value.contains('timed out')) return 'timeout';
  if (value.contains('unknownhost') || value.contains('dns') || value.contains('resolve host')) {
    return 'dns';
  }
  if (value.contains('connection') || value.contains('network')) return 'network';
  if (value.contains('not found')) return 'not_found';
  return 'other';
}

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

      final download = await _navigationChannel.invokeMethod<Map<Object?, Object?>>(
        'downloadOfflineRegion',
        {
          'regionId': _regionId,
          'styleUri': _styleUri,
          'coordinates': _regionRing,
          'minZoom': 8,
          'maxZoom': 15,
        },
      );
      expect(download, isNotNull);
      expect(download?['mapTiles'], isTrue);
      expect(download?['routingProfile'], 'walking');
      expect(
        download?['completedResourceCount'],
        greaterThan(0),
        reason: 'The downloaded region must contain completed Mapbox resources.',
      );
      expect(
        download?['completedResourceSize'],
        greaterThan(0),
        reason: 'The downloaded region must persist non-empty resource bytes.',
      );
      final completedResources = (download?['progressCompletedResourceCount'] as num?)?.toInt()
          ?? (download?['completedResourceCount'] as num?)?.toInt()
          ?? 0;
      final requiredResources = (download?['requiredResourceCount'] as num?)?.toInt() ?? 0;
      final erroredResources = (download?['erroredResourceCount'] as num?)?.toInt() ?? 0;
      // ignore: avoid_print
      print(
        'MAPBOX_OFFLINE_REGION_PROGRESS '
        'completed=$completedResources required=$requiredResources '
        'errored=$erroredResources '
        'bytes=${download?['completedResourceSize']} '
        'loaded_bytes=${download?['loadedResourceSize']}',
      );
      expect(
        erroredResources,
        0,
        reason: 'The Mapbox tile region must not report failed resources.',
      );
      if (requiredResources > 0) {
        expect(
          completedResources,
          greaterThanOrEqualTo(requiredResources),
          reason: 'All required Mapbox map and routing resources must be downloaded.',
        );
      }
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
      // Emit routing evidence before the independent map-rendering assertion.
      // ignore: avoid_print
      print(
        'MAPBOX_ROUTE_VALIDATION source=offline '
        'distance_m=${offlineRoute.distanceMeters} '
        'duration_s=${offlineRoute.durationSeconds} '
        'geometry_points=${offlineRoute.points.length}',
      );
      // ignore: avoid_print
      await _expectOfflineMapRendered(tester, binding);
      return;
    }

    fail('Unsupported ROUTE_TEST_MODE: $mode');
  });
}


Future<void> _expectOfflineMapRendered(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final styleLoaded = Completer<void>();
  final mapLoaded = Completer<void>();
  final fullFrameRendered = Completer<void>();
  final loadErrors = <String>[];
  final resourceFailures = <String>[];
  var idleSeen = false;
  var renderedFrames = 0;

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
          onStyleLoadedListener: (_) {
            if (!styleLoaded.isCompleted) styleLoaded.complete();
          },
          onMapLoadedListener: (_) {
            if (!mapLoaded.isCompleted) mapLoaded.complete();
          },
          onRenderFrameFinishedListener: (event) {
            renderedFrames++;
            if (event.renderMode == RenderMode.FULL &&
                !fullFrameRendered.isCompleted) {
              fullFrameRendered.complete();
            }
          },
          onMapIdleListener: (_) {
            idleSeen = true;
          },
          onMapLoadErrorListener: (event) {
            loadErrors.add(
              '${event.type.name}/${event.sourceId ?? 'unknown'}/${_safeMapboxFailureClass(event.message)}',
            );
          },
          onResourceRequestListener: (event) {
            if (event.cancelled) return;
            final response = event.response;
            final error = response?.error;
            if (error == null) return;
            final reason = error.reason.name;
            final source = response?.source.name ?? 'unknown';
            // Cache misses are expected before the resource loader checks the
            // network or the offline TileStore. A real offline miss is reported
            // as IN_OFFLINE_MODE/CONNECTION and must fail this acceptance test.
            if (reason == 'NOT_FOUND' &&
                (source == 'CACHE' || source == 'TILE_STORE')) {
              return;
            }
            resourceFailures.add(
              '$reason/$source/${event.request.kind.name}/${_safeMapboxFailureClass(error.message)}',
            );
          },
        ),
      ),
    ),
  );

  final styleDeadline = DateTime.now().add(const Duration(seconds: 45));
  while (!styleLoaded.isCompleted && DateTime.now().isBefore(styleDeadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (loadErrors.isNotEmpty || resourceFailures.isNotEmpty) {
      break;
    }
  }

  final frameDeadline = DateTime.now().add(const Duration(seconds: 20));
  while (styleLoaded.isCompleted &&
      (!mapLoaded.isCompleted || !fullFrameRendered.isCompleted || !idleSeen) &&
      DateTime.now().isBefore(frameDeadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (loadErrors.isNotEmpty || resourceFailures.isNotEmpty) {
      break;
    }
  }

  // Android embeds Mapbox in a native platform view. The integration-test
  // binding requires Flutter surface conversion before capturing that view.
  // Do this even on a failed render so the workflow retains diagnostic pixels.
  await binding.convertFlutterSurfaceToImage();
  await tester.pump(const Duration(seconds: 2));
  final screenshot = await binding.takeScreenshot('mapbox-offline-map-rendered');
  expect(screenshot, isNotEmpty);
  final metrics = await _inspectRenderedPixels(screenshot);
  // ignore: avoid_print
  print('MAPBOX_OFFLINE_RENDER_GATE version=2 entropy_min=1.2 dominant_max=0.85');
  // ignore: avoid_print
  print(
    'MAPBOX_OFFLINE_MAP_DIAGNOSTICS '
    'style_loaded=${styleLoaded.isCompleted} '
    'map_loaded=${mapLoaded.isCompleted} '
    'full_frame=${fullFrameRendered.isCompleted} '
    'rendered_frames=$renderedFrames idle=$idleSeen '
    'load_errors=${loadErrors.length} '
    'resource_failures=${resourceFailures.length} '
    'resource_failure_details=${resourceFailures.join(',')} '
    'screenshot_bytes=${screenshot.length} '
    'unique_colors=${metrics.$1} '
    'opaque_ratio=${metrics.$2.toStringAsFixed(3)} '
    'entropy_bits=${metrics.$3.toStringAsFixed(3)} '
    'dominant_ratio=${metrics.$4.toStringAsFixed(3)}',
  );

  expect(
    styleLoaded.isCompleted,
    isTrue,
    reason: 'Mapbox must load the offline style from the shared TileStore.',
  );
  expect(
    fullFrameRendered.isCompleted,
    isTrue,
    reason: 'Mapbox must finish at least one full render frame with offline resources.',
  );
  expect(
    mapLoaded.isCompleted,
    isTrue,
    reason: 'Mapbox must report that all visible map resources have loaded.',
  );
  expect(
    loadErrors,
    isEmpty,
    reason: 'The offline map must not report style, source, glyph, or tile load errors.',
  );
  expect(
    resourceFailures,
    isEmpty,
    reason: 'The offline map must not fail to load required resources.',
  );
  expect(
    idleSeen,
    isTrue,
    reason: 'The offline map must reach the idle state after rendering.',
  );
  expect(
    renderedFrames,
    greaterThan(0),
    reason: 'The offline map must produce at least one completed render frame.',
  );
  expect(
    metrics.$1,
    greaterThan(24),
    reason: 'The offline map screenshot must contain a diverse map viewport, not a nearly uniform canvas.',
  );
  expect(
    metrics.$2,
    greaterThan(0.95),
    reason: 'The offline map screenshot must be predominantly opaque.',
  );
  expect(
    metrics.$3,
    greaterThan(1.2),
    reason: 'The offline map must contain enough visual information to distinguish streets/labels from a flat background.',
  );
  expect(
    metrics.$4,
    lessThan(0.85),
    reason: 'No single background color may dominate the offline map viewport.',
  );
  // ignore: avoid_print
  print(
    'MAPBOX_OFFLINE_MAP_RENDERED screenshot_bytes=${screenshot.length} '
    'unique_colors=${metrics.$1} opaque_ratio=${metrics.$2.toStringAsFixed(3)} '
    'entropy_bits=${metrics.$3.toStringAsFixed(3)} '
    'dominant_ratio=${metrics.$4.toStringAsFixed(3)}',
  );
}

Future<(int, double, double, double)> _inspectRenderedPixels(List<int> screenshot) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(screenshot));
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
      final width = frame.image.width;
      final height = frame.image.height;
      if (width < 300 || height < 300) {
        throw const FormatException('Offline map screenshot viewport is too small.');
      }
      final minX = (width * 0.08).round();
      final maxX = (width * 0.92).round();
      final minY = (height * 0.12).round();
      final maxY = (height * 0.88).round();
      final colorCounts = <int, int>{};
      var sampledPixels = 0;
      var opaquePixels = 0;

      // Ignore system bars and inspect the central map viewport only.
      for (var y = minY; y < maxY; y += 16) {
        for (var x = minX; x < maxX; x += 16) {
          final offset = (y * width + x) * 4;
          if (offset + 3 >= pixels.length) continue;
          final red = pixels[offset];
          final green = pixels[offset + 1];
          final blue = pixels[offset + 2];
          final alpha = pixels[offset + 3];
          sampledPixels++;
          if (alpha >= 240) opaquePixels++;
          final color = ((red >> 4) << 12) |
              ((green >> 4) << 8) |
              ((blue >> 4) << 4) |
              (alpha >> 4);
          colorCounts.update(color, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      if (sampledPixels == 0) {
        throw const FormatException('Offline map screenshot contains no map viewport pixels.');
      }
      var entropyBits = 0.0;
      var dominantPixels = 0;
      for (final count in colorCounts.values) {
        final probability = count / sampledPixels;
        entropyBits -= probability * (math.log(probability) / math.ln2);
        dominantPixels = math.max(dominantPixels, count);
      }
      return (
        colorCounts.length,
        opaquePixels / sampledPixels,
        entropyBits,
        dominantPixels / sampledPixels,
      );
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
