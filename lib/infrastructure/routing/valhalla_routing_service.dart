import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/contracts/routing_service.dart';

/// Thin provider adapter around the mature Valhalla HTTP engine.
/// Routing algorithms remain outside the application.
class ValhallaRoutingService implements RoutingService {
  ValhallaRoutingService({
    required Uri baseUri,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 20),
  })  : _baseUri = _normalizeBaseUri(baseUri),
        _client = client ?? http.Client(),
        _requestTimeout = requestTimeout {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout', 'Must be positive.');
    }
  }

  final Uri _baseUri;
  final http.Client _client;
  final Duration _requestTimeout;

  @override
  Future<RouteResult> route(RouteRequest request) async {
    _validatePoints(request.points, 'route');
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
      'directions_options': {'units': 'kilometers', 'language': 'es-ES'},
    });
    return _parseTrip(response);
  }

  @override
  Future<RouteResult> match(List<LatLng> track) async {
    _validatePoints(track, 'track');
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
        .timeout(_requestTimeout);
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

    for (final item in legs) {
      if (item is! Map<String, dynamic>) continue;
      final summary = item['summary'];
      if (summary is Map<String, dynamic>) {
        distanceKm += (summary['length'] as num?)?.toDouble() ?? 0;
        durationSeconds += (summary['time'] as num?)?.toDouble() ?? 0;
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

  void _validatePoints(List<LatLng> points, String label) {
    if (points.length < 2) {
      throw ArgumentError('At least two $label points are required.');
    }
    for (final point in points) {
      if (!point.latitude.isFinite ||
          !point.longitude.isFinite ||
          point.latitude < -90 ||
          point.latitude > 90 ||
          point.longitude < -180 ||
          point.longitude > 180) {
        throw ArgumentError('Invalid coordinate in $label.');
      }
    }
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

  static Uri _normalizeBaseUri(Uri uri) {
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: path);
  }
}
