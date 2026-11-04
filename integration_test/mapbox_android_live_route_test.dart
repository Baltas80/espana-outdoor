import 'package:flutter/services.dart';
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

void _expectUsableRoute(RouteResult route) {
  expect(route.points.length, greaterThan(1));
  expect(route.distanceMeters, isNotNull);
  expect(route.distanceMeters, greaterThan(0));
  expect(route.durationSeconds, isNotNull);
  expect(route.durationSeconds, greaterThan(0));
  expect(route.steps, isNotEmpty);
}
