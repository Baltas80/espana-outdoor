import 'package:geolocator/geolocator.dart';

import '../domain/outdoor_models.dart';

final class BacktrackGuidance {
  const BacktrackGuidance({
    required this.distanceMeters,
    required this.bearingDegrees,
    required this.remainingPoints,
    required this.target,
  });

  final double distanceMeters;
  final double bearingDegrees;
  final int remainingPoints;
  final GeoPoint target;
}

final class BacktrackService {
  BacktrackGuidance? calculate({
    required Position current,
    required List<GeoPoint> recordedPoints,
  }) {
    if (recordedPoints.length < 2) return null;

    var nearestDistance = double.infinity;
    var nearestIndex = -1;
    GeoPoint? target;
    GeoPoint? previous;

    for (var index = 0; index < recordedPoints.length; index++) {
      final point = recordedPoints[index];
      final distance = _distanceTo(current, point);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
        target = index > 0 ? previous : point;
      }
      previous = point;
    }

    if (nearestIndex < 0 || target == null) return null;
    return _guidance(current, target, nearestIndex > 0 ? nearestIndex : 1);
  }

  /// Calculates against a stream so long routes are processed in bounded
  /// memory and the event loop gets time to paint between storage batches.
  Future<BacktrackGuidance?> calculateFromStream({
    required Position current,
    required Stream<GeoPoint> recordedPoints,
  }) async {
    var nearestDistance = double.infinity;
    var nearestIndex = -1;
    var count = 0;
    GeoPoint? target;
    GeoPoint? previous;

    await for (final point in recordedPoints) {
      final distance = _distanceTo(current, point);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = count;
        target = count > 0 ? previous : point;
      }
      previous = point;
      count++;
    }

    if (count < 2 || nearestIndex < 0 || target == null) return null;
    return _guidance(current, target, nearestIndex > 0 ? nearestIndex : 1);
  }

  BacktrackGuidance _guidance(
    Position current,
    GeoPoint target,
    int remainingPoints,
  ) {
    final distance = Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      target.latitude,
      target.longitude,
    );
    final rawBearing = Geolocator.bearingBetween(
      current.latitude,
      current.longitude,
      target.latitude,
      target.longitude,
    );
    final bearing = (rawBearing + 360) % 360;
    return BacktrackGuidance(
      distanceMeters: distance,
      bearingDegrees: bearing,
      remainingPoints: remainingPoints,
      target: target,
    );
  }

  double _distanceTo(Position current, GeoPoint point) =>
      Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        point.latitude,
        point.longitude,
      );
}
