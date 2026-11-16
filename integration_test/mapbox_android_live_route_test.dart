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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  const mode = String.fromEnvironment(
    'ROUTE_TEST_MODE',
    defaultValue: 'online_and_download',
  );
  const tileStoreUsageMode = String.fromEnvironment(
    'MAPBOX_TILESTORE_USAGE_MODE',
    defaultValue: 'READ_ONLY',
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
    expect(
      <String>{'READ_ONLY', 'READ_AND_UPDATE'},
      contains(tileStoreUsageMode),
      reason: 'The integration test only supports explicit Mapbox TileStore modes.',
    );
    // ignore: avoid_print
    print('MAPBOX_OFFLINE_STYLE_URI uri=$mapboxStyleUri');
    await _navigationChannel.invokeMethod<void>('configure', {
      'accessToken': accessToken,
      'tileStoreUsageMode': tileStoreUsageMode,
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
          'styleUri': mapboxStyleUri,
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
      expect(tileStoreVerification?['stylePackPresent'], isTrue);
      expect(tileStoreVerification?['tileStoreUsageMode'], tileStoreUsageMode);
      // ignore: avoid_print
      print(
        'MAPBOX_TILESTORE_VERIFICATION '
        'same_instance=${tileStoreVerification?['mapTileStoreSameInstance']} '
        'descriptor_checked=${tileStoreVerification?['mapDescriptorCheckCompleted']} '
        'descriptor_present=${tileStoreVerification?['mapDescriptorPresentInMapsStore']} '
        'map_region=${tileStoreVerification?['mapRegionPresent']} '
        'routing_region=${tileStoreVerification?['routingRegionPresent']} '
        'style_pack=${tileStoreVerification?['stylePackPresent']} '
        'style_pack_resources=${tileStoreVerification?['stylePackCompletedResourceCount']} '
        'style_pack_bytes=${tileStoreVerification?['stylePackCompletedResourceSize']} '
        'usage_mode=${tileStoreVerification?['tileStoreUsageMode']} '
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
      expect(tileStoreVerification?['stylePackPresent'], isTrue);
      expect(tileStoreVerification?['tileStoreUsageMode'], tileStoreUsageMode);
      // ignore: avoid_print
      print(
        'MAPBOX_TILESTORE_VERIFICATION '
        'same_instance=${tileStoreVerification?['mapTileStoreSameInstance']} '
        'descriptor_checked=${tileStoreVerification?['mapDescriptorCheckCompleted']} '
        'descriptor_present=${tileStoreVerification?['mapDescriptorPresentInMapsStore']} '
        'map_region=${tileStoreVerification?['mapRegionPresent']} '
        'routing_region=${tileStoreVerification?['routingRegionPresent']} '
        'usage_mode=${tileStoreVerification?['tileStoreUsageMode']} '
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
      await _expectOfflineMapRendered(tester, tileStoreUsageMode);
      return;
    }

    fail('Unsupported ROUTE_TEST_MODE: $mode');
  });
}


Future<void> _expectOfflineMapRendered(
  WidgetTester tester,
  String tileStoreUsageMode,
) async {
  expect(
    tileStoreUsageMode,
    'READ_AND_UPDATE',
    reason: 'The offline map proof must use Mapbox tile packs, not online tile fallback.',
  );

  // Keep the application's real root and navigate through its production
  // bottom navigation. Pumping a second standalone MapWidget left the
  // original Android PlatformView alive and made the test observe a different
  // map instance from the one displayed by the app.
  final mapDestination = find.byTooltip('Mapa');
  final navigationDeadline = DateTime.now().add(const Duration(seconds: 30));
  while (mapDestination.evaluate().isEmpty &&
      DateTime.now().isBefore(navigationDeadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(
    mapDestination,
    findsOneWidget,
    reason: 'The production app shell must expose its Mapa destination.',
  );
  await tester.tap(mapDestination);
  await tester.pump();
  await tester.pump(const Duration(seconds: 12));

  expect(
    find.text('© Mapbox · © OpenStreetMap contributors'),
    findsOneWidget,
    reason: 'The real MapboxMapPage must be mounted before capturing offline evidence.',
  );

  // Re-check the exact persistent store after the production MapWidget has
  // been created. The host verifier then inspects that widget's native
  // MapboxMapViewport events from logcat.
  final postMapWidgetVerification =
      await _navigationChannel.invokeMethod<Map<Object?, Object?>>(
    'verifyOfflineRegion',
    {'regionId': _regionId},
  );
  expect(postMapWidgetVerification?['mapTileStoreSameInstance'], isTrue);
  expect(postMapWidgetVerification?['mapDescriptorPresentInMapsStore'], isTrue);
  expect(postMapWidgetVerification?['stylePackPresent'], isTrue);
  expect(postMapWidgetVerification?['tileStoreUsageMode'], tileStoreUsageMode);

  // The host polls this debug-only native marker and captures the actual
  // application screen while its production MapboxMapPage is foregrounded.
  await _navigationChannel.invokeMethod<void>('markOfflineScreenshotReady');
  // ignore: avoid_print
  print('MAPBOX_OFFLINE_MAP_VIEWPORT_READY style_uri=$mapboxStyleUri');
  await Future<void>.delayed(const Duration(seconds: 8));
}
