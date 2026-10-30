import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/contracts/routing_service.dart';

/// Thin provider adapter around the mature Valhalla HTTP engine.
/// Routing algorithms remain outside the application.
class ValhallaRoutingService implements RoutingService {
  ValhallaRoutingService({required Uri baseUri, http.Client? client})
      : _baseUri = _normalizeBaseUri(baseUri),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  @override
  Future<RouteResult> route(RouteRequest request) async {
    if (request.points.length < 2) {
      throw ArgumentError('At least two route points are required.');
    }
    final response = await _post('route', {
      'locations': [
        for (final p in request.points)
        {
          'lat': p.latitude,
          'lon': p.longitude,
          'type': 'break',
        }
      ],
      'costing': _costing(request.profile),
      'units': 'kilometers',
      'shape_format': 'geojson',
      // Valhalla only returns these samples when its graph was built with DEM data.
      // Keeping this optional means distance/time still work on deployments
      // without elevation coverage.
      'elevation_interval': 30,
      'directions_options': {'units': 'kilometers', 'language': 'es-ES'},
    });
    return _parseTrip(response);
  }

  @override
  Future<RouteResult> match(List<LatLng> track) async {
    if (track.length < 2) {
      throw ArgumentError('At least two track points are required.');
    }
    final response = await _post('trace_route', {
      'shape': [
        for (final p in track) {'lat': p.latitude, 'lon': p.longitude}
      ],
      'costing': 'pedestrian',
      'shape_match': 'map_snap',
      'units': 'kilometers',
      'shape_format': 'geojson',
    });
    return _parseTrip(response);
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, Object?> body,
  ) async {
    final uri = _baseUri.resolve(endpoint);
    final response = await _client
        .post(
          uri,
          headers: const {
          'content-type': 'application/json',
          'user-agent': 'EspanaOutdoor/0.1',
        },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = response.body.trim();
      final suffix = detail.isEmpty
          ? ''
          : ': ${detail.length > 240 ? '${detail.substring(0, 240)}…' : detail}';
      throw StateError(
        'Valhalla $endpoint failed: HTTP ${response.statusCode}$suffix',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Invalid Valhalla response.');
    }
    return decoded;
  }

  RouteResult _parseTrip(Map<String, dynamic> json) {
    final trip = json['trip'];
    if (trip is! Map<String, dynamic>) {
      throw FormatException('Valhalla response does not contain a trip.');
    }
    final legs = trip['legs'];
    if (legs is! List) {
      throw FormatException('Valhalla trip does not contain legs.');
    }

    final points = <LatLng>[];
    final steps = <RouteStep>[];
    var distanceKm = 0.0;
    var durationSeconds = 0.0;
    var ascentMeters = 0.0;
    var descentMeters = 0.0;
    var elevationComparisons = 0;
    double? previousElevation;

    for (final item in legs) {
      if (item is! Map<String, dynamic>) continue;
      final summary = item['summary'];
      if (summary is Map<String, dynamic>) {
        distanceKm += (summary['length'] as num?)?.toDouble() ?? 0;
        durationSeconds += (summary['time'] as num?)?.toDouble() ?? 0;
      }

      final elevation = item['elevation'];
      if (elevation is List) {
        for (final sample in elevation) {
          if (sample is! num || !sample.toDouble().isFinite) {
            // Do not bridge a missing DEM sample and invent a slope across it.
            previousElevation = null;
            continue;
          }
          final currentElevation = sample.toDouble();
          final previous = previousElevation;
          if (previous != null) {
            final delta = currentElevation - previous;
            if (delta > 0) {
              ascentMeters += delta;
            } else if (delta < 0) {
              descentMeters += -delta;
            }
            elevationComparisons++;
          }
          previousElevation = currentElevation;
        }
      } else {
        previousElevation = null;
      }

      final shapePoints = _decodeShape(item['shape']).toList();
      final shapeOffset = points.length;

      final maneuvers = item['maneuvers'];
      if (maneuvers is List) {
        for (final maneuver in maneuvers) {
          if (maneuver is! Map<String, dynamic>) continue;
          final instruction = maneuver['instruction'];
          if (instruction is! String || instruction.trim().isEmpty) continue;
          steps.add(
            RouteStep(
              instruction: instruction,
              distanceMeters: _number(maneuver['length'], multiplier: 1000),
              durationSeconds: _number(maneuver['time']),
              beginShapeIndex: _globalShapeIndex(
                maneuver['begin_shape_index'],
                shapeOffset,
                shapePoints.length,
              ),
              endShapeIndex: _globalShapeIndex(
                maneuver['end_shape_index'],
                shapeOffset,
                shapePoints.length,
              ),
            ),
          );
        }
      }

      points.addAll(shapePoints);
    }

    if (points.length < 2) {
      throw FormatException('Valhalla route did not contain a usable shape.');
    }

    return RouteResult(
      points: points,
      distanceMeters: distanceKm * 1000,
      durationSeconds: durationSeconds,
      ascentMeters: elevationComparisons == 0 ? null : ascentMeters,
      descentMeters: elevationComparisons == 0 ? null : descentMeters,
      steps: List.unmodifiable(steps),
    );
  }

  int? _globalShapeIndex(Object? value, int offset, int shapeLength) {
    final localIndex = (value as num?)?.toInt();
    if (localIndex == null || localIndex < 0 || localIndex >= shapeLength) {
      return null;
    }
    return offset + localIndex;
  }

  Iterable<LatLng> _decodeShape(Object? shape) {
    if (shape is String) {
      return _decodePolyline6(shape);
    }

    if (shape is! Map<String, dynamic>) return const <LatLng>[];

    Object? coordinates = shape['coordinates'];
    if (coordinates is Map<String, dynamic>) {
      coordinates = coordinates['coordinates'];
    }
    if (coordinates is! List) return const <LatLng>[];

    return [
      for (final coordinate in coordinates)
        if (coordinate is List &&
            coordinate.length >= 2 &&
            coordinate[0] is num &&
            coordinate[1] is num)
          LatLng(
            (coordinate[1] as num).toDouble(),
            (coordinate[0] as num).toDouble(),
          ),
    ];
  }

  Iterable<LatLng> _decodePolyline6(String encoded) sync* {
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    int readValue() {
      var result = 0;
      var shift = 0;
      while (index < encoded.length) {
        final byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        if (byte < 0x20) break;
        shift += 5;
        if (shift > 60) {
          throw FormatException('Invalid Valhalla polyline6 shape.');
        }
      }
      final delta = (result & 1) == 0
          ? (result >> 1)
          : ~(result >> 1);
      return delta;
    }

    while (index < encoded.length) {
      latitude += readValue();
      longitude += readValue();
      yield LatLng(latitude / 1000000.0, longitude / 1000000.0);
    }
  }
  static double? _number(Object? value, {double multiplier = 1}) {
    final number = value as num?;
    return number == null ? null : number.toDouble() * multiplier;
  }

  String _costing(String profile) {
    switch (profile.toLowerCase()) {
      case 'cycling':
      case 'bike':
        return 'bicycle';
      case 'driving':
      case 'car':
        return 'auto';
      case 'hiking':
      case 'walking':
      default:
        return 'pedestrian';
    }
  }

  /// Releases the underlying HTTP connection pool when the provider is disposed.
  void dispose() => _client.close();

  static Uri _normalizeBaseUri(Uri uri) {
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: path);
  }
}
