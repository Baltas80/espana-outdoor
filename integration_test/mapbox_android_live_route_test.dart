import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:espana_outdoors/core/contracts/routing_service.dart';
import 'package:espana_outdoors/infrastructure/routing/mapbox_navigation_routing_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Mapbox Navigation calculates a real online walking route', (tester) async {
    const accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
    expect(
      accessToken,
      startsWith('pk.'),
      reason: 'The staging workflow must inject its public Mapbox token.',
    );

    final service = MapboxNavigationRoutingService(accessToken: accessToken);
    final route = await service.route(
      const RouteRequest(
        profile: 'walking',
        points: [
          LatLng(37.8882, -4.7794),
          LatLng(37.8900, -4.7700),
        ],
      ),
    );

    expect(route.points.length, greaterThan(1));
    expect(route.distanceMeters, isNotNull);
    expect(route.distanceMeters, greaterThan(0));
    expect(route.durationSeconds, isNotNull);
    expect(route.durationSeconds, greaterThan(0));
    expect(route.source, 'online');
  });
}
