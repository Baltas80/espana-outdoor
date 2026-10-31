import 'package:latlong2/latlong.dart';

class RouteRequest {
  const RouteRequest({required this.points, this.profile = 'hiking'});

  final List<LatLng> points;
  final String profile;
}

class RouteStep {
  const RouteStep({
    required this.instruction,
    this.distanceMeters,
    this.durationSeconds,
    this.beginShapeIndex,
    this.endShapeIndex,
  });

  final String instruction;
  final double? distanceMeters;
  final double? durationSeconds;
  final int? beginShapeIndex;
  final int? endShapeIndex;
}

class RouteResult {
  const RouteResult({
    required this.points,
    this.distanceMeters,
    this.durationSeconds,
    this.ascentMeters,
    this.descentMeters,
    this.steps = const [],
    this.source,
  });

  final List<LatLng> points;
  final double? distanceMeters;
  final double? durationSeconds;
  final double? ascentMeters;
  final double? descentMeters;
  final List<RouteStep> steps;

  /// Router that produced this result: online, offline, or another provider.
  final String? source;
}

abstract interface class RoutingService {
  Future<RouteResult> route(RouteRequest request);
  Future<RouteResult> match(List<LatLng> track);
}
