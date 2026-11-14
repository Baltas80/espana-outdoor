import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:espana_outdoors/core/contracts/routing_service.dart';
import 'package:espana_outdoors/infrastructure/routing/mapbox_navigation_routing_service.dart';

const _channel = MethodChannel('com.espanaoutdoors/navigation');

String _encodePolyline6(List<LatLng> points) {
  var lastLatitude = 0;
  var lastLongitude = 0;
  final output = StringBuffer();

  void writeValue(int value) {
    var encoded = value < 0 ? ~(value << 1) : (value << 1);
    while (encoded >= 0x20) {
      output.writeCharCode((0x20 | (encoded & 0x1f)) + 63);
      encoded >>= 5;
    }
    output.writeCharCode(encoded + 63);
  }

  for (final point in points) {
    final latitude = (point.latitude * 1000000).round();
    final longitude = (point.longitude * 1000000).round();
    writeValue(latitude - lastLatitude);
    writeValue(longitude - lastLongitude);
    lastLatitude = latitude;
    lastLongitude = longitude;
  }
  return output.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('returns a route marked as offline and decodes Mapbox polyline6', () async {
    const expectedPoints = [
      LatLng(37.8882, -4.7794),
      LatLng(37.8900, -4.7700),
    ];
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      if (call.method == 'configure') return null;
      if (call.method == 'requestRoute') {
        return <String, Object?>{
          'geometry': _encodePolyline6(expectedPoints),
          'distanceMeters': 1200.0,
          'durationSeconds': 900.0,
          'source': 'offline',
          'steps': [
            {
              'instruction': 'Continúa por el sendero',
              'distanceMeters': 1200.0,
              'durationSeconds': 900.0,
            },
          ],
        };
      }
      throw MissingPluginException(call.method);
    });

    final service = MapboxNavigationRoutingService(accessToken: 'pk.test');
    final result = await service.route(
      const RouteRequest(
        points: [
          LatLng(37.8882, -4.7794),
          LatLng(37.8900, -4.7700),
        ],
      ),
    );

    expect(calls, ['requestRoute']);
    expect(result.source, 'offline');
    expect(result.points, expectedPoints);
    expect(result.distanceMeters, 1200.0);
    expect(result.durationSeconds, 900.0);
    expect(result.steps.single.instruction, 'Continúa por el sendero');
  });


  test('rejects an unknown router source instead of labeling it online', () async {
    const points = [
      LatLng(37.8882, -4.7794),
      LatLng(37.8900, -4.7700),
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'requestRoute') {
        return <String, Object?>{
          'geometry': _encodePolyline6(points),
          'distanceMeters': 1200.0,
          'durationSeconds': 900.0,
          'source': 'custom-or-unknown',
          'steps': [
            {'instruction': 'Continúa', 'distanceMeters': 1200.0, 'durationSeconds': 900.0},
          ],
        };
      }
      throw MissingPluginException(call.method);
    });

    final service = MapboxNavigationRoutingService(accessToken: 'pk.test');
    await expectLater(
      service.route(const RouteRequest(points: points)),
      throwsFormatException,
    );
  });

  test('rejects a route request with fewer than two coordinates', () async {
    final service = MapboxNavigationRoutingService(accessToken: 'pk.test');
    await expectLater(
      service.route(
        const RouteRequest(points: [LatLng(37.8882, -4.7794)]),
      ),
      throwsArgumentError,
    );
  });
}
