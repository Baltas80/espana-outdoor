import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:espana_outdoors/core/contracts/routing_service.dart';
import 'package:espana_outdoors/infrastructure/routing/composite_routing_service.dart';

const _points = <LatLng>[
  LatLng(37.8882, -4.7794),
  LatLng(37.8900, -4.7700),
];

class _FakeRoutingService implements RoutingService {
  _FakeRoutingService(this.source);

  final String source;
  int routeCalls = 0;
  int matchCalls = 0;

  @override
  Future<RouteResult> route(RouteRequest request) async {
    routeCalls++;
    return RouteResult(points: request.points, source: source);
  }

  @override
  Future<RouteResult> match(List<LatLng> track) async {
    matchCalls++;
    return RouteResult(points: track, source: source);
  }
}

void main() {
  test('hiking uses Mapbox when the Android adapter is available', () async {
    final mapbox = _FakeRoutingService('offline');
    final valhalla = _FakeRoutingService('valhalla');
    final service = CompositeRoutingService(mapbox: mapbox, valhalla: valhalla);

    final result = await service.route(
      const RouteRequest(points: _points, profile: 'hiking'),
    );

    expect(result.source, 'offline');
    expect(mapbox.routeCalls, 1);
    expect(valhalla.routeCalls, 0);
  });

  test('BTT and cycle touring always use Valhalla', () async {
    final mapbox = _FakeRoutingService('offline');
    final valhalla = _FakeRoutingService('valhalla');
    final service = CompositeRoutingService(mapbox: mapbox, valhalla: valhalla);

    final mtb = await service.route(
      const RouteRequest(points: _points, profile: 'mtb'),
    );
    final cycling = await service.route(
      const RouteRequest(points: _points, profile: 'cycling'),
    );

    expect(mtb.source, 'valhalla');
    expect(cycling.source, 'valhalla');
    expect(mapbox.routeCalls, 0);
    expect(valhalla.routeCalls, 2);
  });

  test('GPX matching remains delegated to Valhalla', () async {
    final mapbox = _FakeRoutingService('offline');
    final valhalla = _FakeRoutingService('valhalla');
    final service = CompositeRoutingService(mapbox: mapbox, valhalla: valhalla);

    final result = await service.match(_points);

    expect(result.source, 'valhalla');
    expect(valhalla.matchCalls, 1);
    expect(mapbox.matchCalls, 0);
  });

  test('hiking falls back to Valhalla when native Mapbox is unavailable', () async {
    final valhalla = _FakeRoutingService('valhalla');
    final service = CompositeRoutingService(mapbox: null, valhalla: valhalla);

    final result = await service.route(
      const RouteRequest(points: _points, profile: 'hiking'),
    );

    expect(result.source, 'valhalla');
    expect(valhalla.routeCalls, 1);
  });

  test('cycling fails explicitly when Valhalla is not configured', () async {
    final service = CompositeRoutingService(
      mapbox: _FakeRoutingService('offline'),
      valhalla: null,
    );

    await expectLater(
      service.route(const RouteRequest(points: _points, profile: 'mtb')),
      throwsA(isA<StateError>()),
    );
  });
}
