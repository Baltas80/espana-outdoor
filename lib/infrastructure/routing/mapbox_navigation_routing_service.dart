import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../core/contracts/routing_service.dart';

class MapboxNavigationRoutingService implements RoutingService {
  MapboxNavigationRoutingService()
      : _channel = const MethodChannel('com.espanaoutdoors/navigation');

  final MethodChannel _channel;

  Future<void> configure(String accessToken) => _channel.invokeMethod<void>(
        'configure',
        {'accessToken': accessToken},
      );

  @override
  Future<RouteResult> route(RouteRequest request) async {
    if (request.points.length < 2) {
      throw ArgumentError('At least two route points are required.');
    }
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
      throw const FormatException('Mapbox Navigation returned an empty response.');
    }
    final geometry = response['geometry'] as String?;
    if (geometry == null || geometry.isEmpty) {
      throw const FormatException('Mapbox Navigation returned no route geometry.');
    }
    final points = _decodePolyline6(geometry).toList(growable: false);
    if (points.length < 2) {
      throw const FormatException('Mapbox Navigation returned an invalid route shape.');
    }
    final rawSteps = response['steps'] as List<dynamic>? ?? const [];
    return RouteResult(
      points: points,
      distanceMeters: (response['distanceMeters'] as num?)?.toDouble(),
      durationSeconds: (response['durationSeconds'] as num?)?.toDouble(),
      source: response['source'] as String?,
      steps: [
        for (final item in rawSteps)
          if (item is Map)
            RouteStep(
              instruction: item['instruction'] as String? ?? '',
              distanceMeters: (item['distanceMeters'] as num?)?.toDouble(),
              durationSeconds: (item['durationSeconds'] as num?)?.toDouble(),
            ),
      ],
    );
  }

  @override
  Future<RouteResult> match(List<LatLng> track) {
    throw UnsupportedError('Mapbox Navigation bridge does not provide map matching.');
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
      }
      return (result & 1) == 0 ? result >> 1 : ~(result >> 1);
    }

    while (index < encoded.length) {
      latitude += readValue();
      longitude += readValue();
      yield LatLng(latitude / 1000000, longitude / 1000000);
    }
  }
}
