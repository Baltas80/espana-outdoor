import 'package:geolocator/geolocator.dart';

import '../domain/outdoor_models.dart';

/// Guidance derived from the recorded track, intended for returning along
/// the path already travelled. It does not require a network route service.
class BacktrackGuidance {
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

class BacktrackService {
  const BacktrackService();

  BacktrackGuidance? calculate({
    required Position current,
    required List<GeoPoint> recordedPoints,
  }) {
    if (recordedPoints.length < 2) return null;

    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var i = 0; i < recordedPoints.length; i++) {
      final point = recordedPoints[i];
      final distance = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    final targetIndex = nearestIndex > 0 ? nearestIndex - 1 : 0;
    final target = recordedPoints[targetIndex];
    final bearing = Geolocator.bearingBetween(
      current.latitude,
      current.longitude,
      target.latitude,
      target.longitude,
    );


    return BacktrackGuidance(
      distanceMeters: nearestDistance,
      bearingDegrees: (bearing + 360) % 360,
      remainingPoints: targetIndex + 1,
      target: target,
    );
  }
}
