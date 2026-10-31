import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../core/contracts/routing_service.dart';

/// Flutter adapter for the native Android Mapbox Navigation SDK.
///
/// Navigation SDK v3 has no official Flutter plugin. Android integration is
/// isolated behind this MethodChannel so application/domain code remains Dart.
class MapboxNavigationRoutingService implements RoutingService {
  MapboxNavigationRoutingService({required String accessToken})
      : _accessToken = accessToken;

  static const MethodChannel _channel =
      MethodChannel('com.espanaoutdoors/navigation');

  final String _accessToken;

  @override
  Future<RouteResult> route(RouteRequest request) async {
    if (request.points.length < 2) {
      throw ArgumentError('At least two route points are required.');
    }
    if (_accessToken.isEmpty) {
      throw StateError('MAPBOX_ACCESS_TOKEN is not configured.');
    }
    final profile = request.profile.toLowerCase();
    if (profile != 'hiking' && profile != 'walking') {
      throw UnsupportedError(
        'Offline routing is currently configured for walking and hiking.',
      );
    }

    await _channel.invokeMethod<void>('configure', {
      'accessToken': _accessToken,
    });
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'requestRoute',
      {
        'points': [
          for (final point in request.points)
            [point.longitude, point.latitude],
        ],
      },
    );
    if (response == null) {
      throw const FormatException('Mapbox Navigation returned no route.');
    }
    final geometry = response['geometry'];
    if (geometry is! String || geometry.isEmpty) {
      throw const FormatException('Mapbox Navigation returned no geometry.');
    }
    final points = _decodePolyline6(geometry).toList(growable: false);
    if (points.length < 2) {
      throw const FormatException('Mapbox route geometry is incomplete.');
    }

    final steps = <RouteStep>[];
    final rawSteps = response['steps'];
    if (rawSteps is List) {
      for (final rawStep in rawSteps) {
        if (rawStep is! Map) continue;
        final instruction = rawStep['instruction'];
        if (instruction is! String || instruction.trim().isEmpty) continue;
        steps.add(
          RouteStep(
            instruction: instruction,
            distanceMeters: _asDouble(rawStep['distanceMeters']),
            durationSeconds: _asDouble(rawStep['durationSeconds']),
          ),
        );
      }
    }

    return RouteResult(
      points: points,
      distanceMeters: _asDouble(response['distanceMeters']),
      durationSeconds: _asDouble(response['durationSeconds']),
      steps: List.unmodifiable(steps),
      source: response['source'] == 'offline' ? 'offline' : 'online',
    );
  }

  @override
  Future<RouteResult> match(List<LatLng> track) {
    throw UnsupportedError(
      'Map matching for imported GPX tracks is not part of the Android MVP routing adapter yet.',
    );
  }

  static double? _asDouble(Object? value) =>
      value is num ? value.toDouble() : null;

  static Iterable<LatLng> _decodePolyline6(String encoded) sync* {
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
          throw const FormatException('Invalid Mapbox polyline6 geometry.');
        }
      }
      return (result & 1) == 0 ? result >> 1 : ~(result >> 1);
    }

    while (index < encoded.length) {
      latitude += readValue();
      longitude += readValue();
      yield LatLng(latitude / 1000000.0, longitude / 1000000.0);
    }
  }
}
