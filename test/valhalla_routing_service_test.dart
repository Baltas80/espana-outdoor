import 'dart:async';
import 'dart:convert';

import 'package:espana_outdoors/core/contracts/routing_service.dart';
import 'package:espana_outdoors/infrastructure/routing/valhalla_routing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(
    this.payload, {
    this.statusCode = 200,
    this.delay = Duration.zero,
  });

  final Map<String, dynamic> payload;
  final int statusCode;
  final Duration delay;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      statusCode,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
}

void main() {
  test('Valhalla route preserves seconds and exposes maneuvers', () async {
    final client = _FakeClient({
      'trip': {
        'legs': [
          {
            'summary': {'length': 1.25, 'time': 120},
            'maneuvers': [
              {
                'instruction': 'Gira a la derecha',
                'length': 0.5,
                'time': 45,
                'begin_shape_index': 0,
                'end_shape_index': 1,
              },
            ],
            'shape': {
              'type': 'LineString',
              'coordinates': [
                [-3.70, 40.41],
                [-3.69, 40.42],
              ],
            },
          },
        ],
      },
    });

    final service = ValhallaRoutingService(
      baseUri: Uri.parse('https://routing.example.com/'),
      client: client,
    );
    final result = await service.route(
      const RouteRequest(
        points: [LatLng(40.41, -3.70), LatLng(40.42, -3.69)],
      ),
    );

    expect(result.distanceMeters, 1250);
    expect(result.durationSeconds, 120);
    expect(result.points, hasLength(2));
    expect(result.steps, hasLength(1));
    expect(result.steps.single.instruction, 'Gira a la derecha');
    expect(result.steps.single.distanceMeters, 500);
  });

  test('normalizes maneuver shape indexes across multiple legs', () async {
    final client = _FakeClient({
      'trip': {
        'legs': [
          {
            'summary': {'length': 1.0, 'time': 60},
            'maneuvers': [
              {
                'instruction': 'Continúa',
                'length': 0.4,
                'time': 20,
                'begin_shape_index': 0,
                'end_shape_index': 1,
              },
            ],
            'shape': {
              'type': 'LineString',
              'coordinates': [
                [-3.70, 40.41],
                [-3.69, 40.42],
              ],
            },
          },
          {
            'summary': {'length': 2.0, 'time': 120},
            'maneuvers': [
              {
                'instruction': 'Gira a la izquierda',
                'length': 1.1,
                'time': 70,
                'begin_shape_index': 0,
                'end_shape_index': 2,
              },
            ],
            'shape': {
              'type': 'LineString',
              'coordinates': [
                [-3.69, 40.42],
                [-3.68, 40.43],
                [-3.67, 40.44],
              ],
            },
          },
        ],
      },
    });

    final service = ValhallaRoutingService(
      baseUri: Uri.parse('https://routing.example.com/'),
      client: client,
    );
    final result = await service.route(
      const RouteRequest(
        points: [LatLng(40.41, -3.70), LatLng(40.44, -3.67)],
      ),
    );

    expect(result.points, hasLength(5));
    expect(result.steps, hasLength(2));
    expect(result.steps.first.beginShapeIndex, 0);
    expect(result.steps.first.endShapeIndex, 1);
    expect(result.steps.last.beginShapeIndex, 2);
    expect(result.steps.last.endShapeIndex, 4);
    expect(result.distanceMeters, 3000);
    expect(result.durationSeconds, 180);
  });

  test('Valhalla route decodes polyline6 shapes', () async {
    final client = _FakeClient({
      'trip': {
        'legs': [
          {
            'summary': {'length': 1.0, 'time': 60},
            'maneuvers': [],
            // Polyline6 for: (40.410000,-3.700000) -> (40.420000,-3.690000).
            'shape': '_xlalA~py`F_pR_pR',
          },
        ],
      },
    });

    final service = ValhallaRoutingService(
      baseUri: Uri.parse('https://routing.example.com/'),
      client: client,
    );
    final result = await service.route(
      const RouteRequest(
        points: [LatLng(40.41, -3.70), LatLng(40.42, -3.69)],
      ),
    );

    expect(result.points, hasLength(2));
    expect(result.points.first.latitude, closeTo(40.41, 0.000001));
    expect(result.points.first.longitude, closeTo(-3.70, 0.000001));
    expect(result.points.last.latitude, closeTo(40.42, 0.000001));
    expect(result.points.last.longitude, closeTo(-3.69, 0.000001));
  });

  test('rejects HTTP error responses without treating them as routes', () async {
    final client = _FakeClient(
      {'error': 'No suitable edges near location'},
      statusCode: 400,
    );
    final service = ValhallaRoutingService(
      baseUri: Uri.parse('https://routing.example.com/'),
      client: client,
    );

    await expectLater(
      service.route(
        const RouteRequest(
          points: [LatLng(40.41, -3.70), LatLng(40.42, -3.69)],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('HTTP 400'),
        ),
      ),
    );
  });

  test('times out a slow Valhalla response using configured request timeout', () async {
    final client = _FakeClient(
      {'trip': {'legs': []}},
      delay: const Duration(milliseconds: 100),
    );
    final service = ValhallaRoutingService(
      baseUri: Uri.parse('https://routing.example.com/'),
      client: client,
      requestTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(
      service.route(
        const RouteRequest(
          points: [LatLng(40.41, -3.70), LatLng(40.42, -3.69)],
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('rejects out-of-range coordinates before making a request', () async {
    final service = ValhallaRoutingService(
      baseUri: Uri.parse('https://routing.example.com/'),
      client: _FakeClient({}),
    );

    await expectLater(
      service.route(
        const RouteRequest(
          points: [LatLng(95, -3.70), LatLng(40.42, -3.69)],
        ),
      ),
      throwsArgumentError,
    );
  });

  test('rejects responses without usable route geometry', () async {
    final service = ValhallaRoutingService(
      baseUri: Uri.parse('https://routing.example.com/'),
      client: _FakeClient({'trip': {'legs': []}}),
    );

    await expectLater(
      service.route(
        const RouteRequest(
          points: [LatLng(40.41, -3.70), LatLng(40.42, -3.69)],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

}
