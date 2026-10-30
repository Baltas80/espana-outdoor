import 'dart:convert';

import 'package:espana_outdoors/core/contracts/routing_service.dart';
import 'package:espana_outdoors/infrastructure/routing/valhalla_routing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.payload);

  final Map<String, dynamic> payload;
  String? lastRequestBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) lastRequestBody = request.body;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
  test('requests Valhalla elevation and calculates ascent and descent when present', () async {
    final client = _FakeClient({
      'trip': {
        'legs': [
          {
            'summary': {'length': 2.4, 'time': 900},
            'elevation': [100, 120, 115, 140],
            'maneuvers': [],
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
        profile: 'hiking',
      ),
    );

    final request = jsonDecode(client.lastRequestBody!) as Map<String, dynamic>;
    expect(request['costing'], 'pedestrian');
    expect(request['elevation_interval'], 30);
    expect(result.distanceMeters, 2400);
    expect(result.durationSeconds, 900);
    expect(result.ascentMeters, 45);
    expect(result.descentMeters, 5);
  });

  test('leaves elevation unavailable when Valhalla has no DEM samples', () async {
    final client = _FakeClient({
      'trip': {
        'legs': [
          {
            'summary': {'length': 1.0, 'time': 300},
            'maneuvers': [],
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

    expect(result.distanceMeters, 1000);
    expect(result.durationSeconds, 300);
    expect(result.ascentMeters, isNull);
    expect(result.descentMeters, isNull);
  });

  test('does not infer a climb across missing elevation samples', () async {
    final client = _FakeClient({
      'trip': {
        'legs': [
          {
            'summary': {'length': 1.0, 'time': 300},
            'elevation': [100, null, 150, 145],
            'maneuvers': [],
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

    // The pair 100 → 150 is not treated as a real slope because the DEM
    // sample between them is missing. The only measurable segment is 150 → 145.
    expect(result.ascentMeters, 0);
    expect(result.descentMeters, 5);
  });

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
}
