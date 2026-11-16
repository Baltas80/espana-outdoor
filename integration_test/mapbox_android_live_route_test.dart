import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:espana_outdoors/core/contracts/routing_service.dart';
import 'package:espana_outdoors/infrastructure/routing/mapbox_navigation_routing_service.dart';
import 'package:espana_outdoors/features/map/mapbox_map_viewport.dart';

const _navigationChannel = MethodChannel('com.espanaoutdoors/navigation');
const _regionId = 'espana-outdoor-cordoba-poc';
const _styleUri = 'mapbox://styles/mapbox/outdoors-v12';
// The offline viewport requests z13 rows 3162–3164. The previous polygon
// clipped row 3164 at its northern edge (37.85°), leaving visible tiles
// outside the downloaded geometry. Keep a full-tile margin around the view.
const _regionRing = <List<double>>[
  [-4.84, 37.78],
  [-4.72, 37.78],
  [-4.72, 37.97],
  [-4.84, 37.97],
  [-4.84, 37.78],
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

String _safeTileIdFromResourceUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return 'unknown';
  final segments = uri.pathSegments;
  for (var index = segments.length - 3; index >= 0; index--) {
    final zoom = int.tryParse(segments[index]);
    final x = int.tryParse(segments[index + 1]);
    final yMatch = RegExp(r'^(\d+)').firstMatch(segments[index + 2]);
    final y = yMatch == null ? null : int.tryParse(yMatch.group(1)!);
    if (zoom == null || x == null || y == null || zoom < 0 || zoom > 22) {
      continue;
    }
    final limit = 1 << zoom;
    if (x >= 0 && x < limit && y >= 0 && y < limit) {
      return '$zoom/$x/$y';
    }
  }
  return 'unknown';
}

double _tileYToLatitude(int y, double scale) {
  return math.atan(math.sinh(math.pi * (1 - (2 * y / scale)))) *
      180 /
      math.pi;
}

bool _tileBoundsFullyCoveredByOfflineRegion(TileID tile) {
  final scale = math.pow(2, tile.z).toDouble();
  final west = tile.x / scale * 360 - 180;
  final east = (tile.x + 1) / scale * 360 - 180;
  final north = _tileYToLatitude(tile.y, scale);
  final south = _tileYToLatitude(tile.y + 1, scale);
  final longitudes = _regionRing.map((point) => point[0]);
  final latitudes = _regionRing.map((point) => point[1]);
  final minLongitude = longitudes.reduce((a, b) => a < b ? a : b);
  final maxLongitude = longitudes.reduce((a, b) => a > b ? a : b);
  final minLatitude = latitudes.reduce((a, b) => a < b ? a : b);
  final maxLatitude = latitudes.reduce((a, b) => a > b ? a : b);
  const epsilon = 1e-7;
  return west >= minLongitude - epsilon &&
      east <= maxLongitude + epsilon &&
      south >= minLatitude - epsilon &&
      north <= maxLatitude + epsilon;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
      expect(download?['routingTiles'], isTrue);
      expect(download?['routingProfile'], 'walking');
      final nativePixelRatio = (download?['mapPixelRatio'] as num?)?.toDouble();
      final flutterPixelRatio =
          WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      expect(nativePixelRatio, isNotNull);
      expect(
        (nativePixelRatio! - flutterPixelRatio).abs(),
        lessThan(0.01),
        reason: 'The Mapbox tileset descriptor and MapWidget must use the same pixel ratio.',
      );
      expect(
        download?['mapCompletedResourceCount'],
        greaterThan(0),
        reason: 'The Maps descriptor must store map tile resources independently.',
      );
      expect(
        download?['mapCompletedResourceSize'],
        greaterThan(0),
        reason: 'The map tile region must persist non-empty bytes.',
      );
      expect(download?['mapErroredResourceCount'], 0);
      expect(
        download?['routingCompletedResourceCount'],
        greaterThan(0),
        reason: 'The Navigation descriptor must store walking routing resources independently.',
      );
      expect(
        download?['routingCompletedResourceSize'],
        greaterThan(0),
        reason: 'The walking routing region must persist non-empty bytes.',
      );
      expect(download?['routingErroredResourceCount'], 0);
      expect(
        download?['completedResourceCount'],
        greaterThan(0),
        reason: 'The combined download must contain completed Mapbox resources.',
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
        'map_completed=${download?['mapCompletedResourceCount']} '
        'map_bytes=${download?['mapCompletedResourceSize']} '
        'map_errors=${download?['mapErroredResourceCount']} '
        'routing_completed=${download?['routingCompletedResourceCount']} '
        'routing_bytes=${download?['routingCompletedResourceSize']} '
        'routing_errors=${download?['routingErroredResourceCount']} '
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
          reason: 'All required map and routing resources across both regions must be downloaded.',
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
      final tileStoreVerification =
          await _navigationChannel.invokeMethod<Map<Object?, Object?>>(
        'verifyOfflineRegion',
        {'regionId': _regionId},
      );
      expect(tileStoreVerification?['mapTileStoreSameInstance'], isTrue);
      expect(tileStoreVerification?['mapDescriptorCheckCompleted'], isTrue);
      expect(tileStoreVerification?['mapDescriptorPresentInMapsStore'], isTrue);
      expect(tileStoreVerification?['mapRegionPresent'], isTrue);
      expect(tileStoreVerification?['routingRegionPresent'], isTrue);
      expect(tileStoreVerification?['tileStoreUsageModeReadOnly'], isTrue);
      // ignore: avoid_print
      print(
        'MAPBOX_TILESTORE_VERIFICATION '
        'same_instance=${tileStoreVerification?['mapTileStoreSameInstance']} '
        'descriptor_checked=${tileStoreVerification?['mapDescriptorCheckCompleted']} '
        'descriptor_present=${tileStoreVerification?['mapDescriptorPresentInMapsStore']} '
        'map_region=${tileStoreVerification?['mapRegionPresent']} '
        'routing_region=${tileStoreVerification?['routingRegionPresent']} '
        'read_only=${tileStoreVerification?['tileStoreUsageModeReadOnly']} '
        'pixel_ratio=${tileStoreVerification?['mapPixelRatio']}',
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
      final tileStoreVerification =
          await _navigationChannel.invokeMethod<Map<Object?, Object?>>(
        'verifyOfflineRegion',
        {'regionId': _regionId},
      );
      expect(tileStoreVerification?['mapTileStoreSameInstance'], isTrue);
      expect(tileStoreVerification?['mapDescriptorCheckCompleted'], isTrue);
      expect(tileStoreVerification?['mapDescriptorPresentInMapsStore'], isTrue);
      expect(tileStoreVerification?['mapRegionPresent'], isTrue);
      expect(tileStoreVerification?['routingRegionPresent'], isTrue);
      expect(tileStoreVerification?['tileStoreUsageModeReadOnly'], isTrue);
      // ignore: avoid_print
      print(
        'MAPBOX_TILESTORE_VERIFICATION '
        'same_instance=${tileStoreVerification?['mapTileStoreSameInstance']} '
        'descriptor_checked=${tileStoreVerification?['mapDescriptorCheckCompleted']} '
        'descriptor_present=${tileStoreVerification?['mapDescriptorPresentInMapsStore']} '
        'map_region=${tileStoreVerification?['mapRegionPresent']} '
        'routing_region=${tileStoreVerification?['routingRegionPresent']} '
        'read_only=${tileStoreVerification?['tileStoreUsageModeReadOnly']} '
        'pixel_ratio=${tileStoreVerification?['mapPixelRatio']}',
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
      await _expectOfflineMapRendered(tester);
      return;
    }

    fail('Unsupported ROUTE_TEST_MODE: $mode');
  });
}


Future<void> _expectOfflineMapRendered(WidgetTester tester) async {
  final styleLoaded = Completer<void>();
  final mapLoaded = Completer<void>();
  final fullFrameRendered = Completer<void>();
  final loadErrors = <String>[];
  final resourceFailures = <String>[];
  var idleSeen = false;
  var renderedFrames = 0;
  var sourceAddedCount = 0;
  var sourceDataEventCount = 0;
  final sourceDataCounts = <String, int>{};
  final observedZoom13Tiles = <String>{};
  final uncoveredZoom13Tiles = <String>{};

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MapWidget(
          styleUri: _styleUri,
          mapOptions: mapboxMapOptionsForPixelRatio(
            WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio,
          ),
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
            final tile = event.tileId;
            final tileId = tile == null ? 'none' : '${tile.z}/${tile.x}/${tile.y}';
            loadErrors.add(
              '${event.type.name}/${event.sourceId ?? 'unknown'}/${_safeMapboxFailureClass(event.message)}/tile=$tileId',
            );
          },
          onSourceAddedListener: (event) {
            sourceAddedCount++;
            if (sourceAddedCount <= 16) {
              // Source IDs are style identifiers; never log request URLs or tokens.
              // ignore: avoid_print
              print('MAPBOX_SOURCE_ADDED id=${event.id.replaceAll(RegExp(r'[^A-Za-z0-9_.:/-]'), '_')}');
            }
          },
          onSourceDataLoadedListener: (event) {
            sourceDataEventCount++;
            final safeId = event.id.replaceAll(RegExp(r'[^A-Za-z0-9_.:/-]'), '_');
            final key = '${safeId}:${event.type.name}:${event.loaded ?? false}';
            sourceDataCounts[key] = (sourceDataCounts[key] ?? 0) + 1;
            final tile = event.tileID;
            final tileId = tile == null ? 'none' : '${tile.z}/${tile.x}/${tile.y}';
            if (tile != null && tile.z == 13) {
              observedZoom13Tiles.add(tileId);
              if (!_tileBoundsFullyCoveredByOfflineRegion(tile)) {
                uncoveredZoom13Tiles.add(tileId);
              }
            }
            if (sourceDataEventCount <= 40) {
              // ignore: avoid_print
              print(
                'MAPBOX_SOURCE_DATA id=$safeId type=${event.type.name} '
                'loaded=${event.loaded ?? false} tile_id=$tileId',
              );
            }
          },
          onResourceRequestListener: (event) {
            if (event.cancelled) return;
            final response = event.response;
            final error = response?.error;
            if (error == null) return;
            final reason = error.reason.name;
            final source = response?.source.name ?? 'unknown';
            final dataSource = event.dataSource.name;
            // A database lookup miss is expected before Mapbox falls back to
            // an individual network tile (online) or reports a true offline
            // miss. Do not confuse it with a failed resource response.
            if (reason == 'NOT_FOUND' &&
                dataSource == 'DATABASE' &&
                (source == 'CACHE' || source == 'TILE_STORE')) {
              return;
            }
            // ResourceRequest.url can contain an access token. Extract only a
            // validated z/x/y path tuple; never log the URL or query string.
            final tileId = _safeTileIdFromResourceUrl(event.request.url);
            resourceFailures.add(
              '$reason/$source/${event.request.kind.name}/${_safeMapboxFailureClass(error.message)}/tile=$tileId',
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

  // Flutter's integration_test screenshot channel is not registered by this
  // flutter test runner. The host script captures the native platform view with
  // adb screencap while this test app is still alive.
  await tester.pump(const Duration(seconds: 2));
  // The host polls Android logcat because flutter test may buffer its
  // stdout until the integration test exits. This signal is emitted by the
  // app process while the native MapWidget is still mounted.
  await _navigationChannel.invokeMethod<void>('markOfflineScreenshotReady');
  // Keep the marker in the host test output as a secondary diagnostic.
  // ignore: avoid_print
  print('MAPBOX_OFFLINE_SCREENSHOT_READY');
  // Keep the native view alive long enough for the host-side ADB capture.
  await Future<void>.delayed(const Duration(seconds: 8));
  // ignore: avoid_print
  print(
    'MAPBOX_VIEWPORT_TILE_COVERAGE zoom=13 '
    'observed=${observedZoom13Tiles.length} '
    'uncovered=${uncoveredZoom13Tiles.length} '
    'tiles=${observedZoom13Tiles.toList()..sort()} '
    'uncovered_tiles=${uncoveredZoom13Tiles.toList()..sort()}',
  );
  // ignore: avoid_print
  print(
    'MAPBOX_OFFLINE_MAP_DIAGNOSTICS '
    'style_loaded=${styleLoaded.isCompleted} '
    'map_loaded=${mapLoaded.isCompleted} '
    'full_frame=${fullFrameRendered.isCompleted} '
    'rendered_frames=$renderedFrames idle=$idleSeen '
    'load_errors=${loadErrors.length} '
    'resource_failures=${resourceFailures.length} '
    'source_added=$sourceAddedCount source_data_events=$sourceDataEventCount '
    'source_summary=${sourceDataCounts.entries.take(8).map((entry) => '${entry.key}:${entry.value}').join(',')} '
    'resource_failure_details=${resourceFailures.join(',')} '
    'screenshot_source=adb',
  );

  expect(
    observedZoom13Tiles,
    isNotEmpty,
    reason: 'The offline map test must observe its z13 viewport tiles.',
  );
  expect(
    uncoveredZoom13Tiles,
    isEmpty,
    reason: 'Every requested z13 viewport tile must be fully inside the downloaded region: ${uncoveredZoom13Tiles.join(', ')}.',
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

}

void _expectUsableRoute(RouteResult route) {
  expect(route.points.length, greaterThan(1));
  expect(route.distanceMeters, isNotNull);
  expect(route.distanceMeters, greaterThan(0));
  expect(route.durationSeconds, isNotNull);
  expect(route.durationSeconds, greaterThan(0));
  expect(route.steps, isNotEmpty);
}
