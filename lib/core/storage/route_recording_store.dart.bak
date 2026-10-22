import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../domain/outdoor_models.dart';

final class RouteRecordingSession {
  const RouteRecordingSession({
    required this.startedAt,
    required this.points,
    required this.distanceMeters,
  });

  final DateTime startedAt;
  final List<GeoPoint> points;
  final double distanceMeters;
}

final class RouteRecordingStore {
  RouteRecordingStore({Box<dynamic>? box})
      : _box = box ?? Hive.box<dynamic>(_boxName);

  static const _boxName = 'route_tracking';
  static const _metadataKey = '__active_session__';
  static const _segmentPrefix = '__segment__';
  static const _segmentSize = 50;

  final Box<dynamic> _box;

  Future<void> begin({required DateTime startedAt}) async {
    await clear();
    await _box.put(_metadataKey, <String, Object?>{
      'active': true,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'distanceMeters': 0.0,
      'segmentCount': 1,
      'pointCount': 0,
    });
    await _box.put(_segmentKey(0), <Object?>[]);
  }

  Future<void> append({
    required GeoPoint point,
    required double distanceMeters,
  }) async {
    final metadata = _metadata;
    if (metadata == null || metadata['active'] != true) {
      throw StateError('No active route recording session.');
    }

    var segmentCount = (metadata['segmentCount'] as num?)?.toInt() ?? 1;
    if (segmentCount <= 0) segmentCount = 1;

    var segmentIndex = segmentCount - 1;
    var key = _segmentKey(segmentIndex);
    final raw = _box.get(key);
    final segment = raw is List ? List<Object?>.from(raw) : <Object?>[];

    if (segment.length >= _segmentSize) {
      segmentIndex += 1;
      segment.clear();
      segmentCount = segmentIndex + 1;
      key = _segmentKey(segmentIndex);
    }

    segment.add(<String, Object?>{
      'latitude': point.latitude,
      'longitude': point.longitude,
    });
    await _box.put(key, segment);

    await _box.put(_metadataKey, <String, Object?>{
      ...metadata,
      'distanceMeters': distanceMeters,
      'segmentCount': segmentCount,
      'pointCount': ((metadata['pointCount'] as num?)?.toInt() ?? 0) + 1,
    });
  }

  RouteRecordingSession? recover() {
    final metadata = _metadata;
    if (metadata == null || metadata['active'] != true) return null;

    final startedAt = DateTime.tryParse(
      metadata['startedAt']?.toString() ?? '',
    );
    if (startedAt == null) return null;

    final segmentCount = (metadata['segmentCount'] as num?)?.toInt() ?? 0;
    if (segmentCount <= 0) return null;

    final points = <GeoPoint>[];
    for (var index = 0; index < segmentCount; index++) {
      final raw = _box.get(_segmentKey(index));
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is! Map) continue;
        final latitude = _asDouble(item['latitude']);
        final longitude = _asDouble(item['longitude']);
        if (latitude == null ||
            longitude == null ||
            latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180) {
          continue;
        }
        points.add(GeoPoint(latitude: latitude, longitude: longitude));
      }
    }

    if (points.isEmpty) return null;

    return RouteRecordingSession(
      startedAt: startedAt.toUtc(),
      points: List.unmodifiable(points),
      distanceMeters: _asDouble(metadata['distanceMeters']) ?? 0,
    );
  }

  bool get hasActiveSession => _metadata?['active'] == true;

  Future<void> finish() => clear();

  Future<void> clear() async {
    final keys = _box.keys
        .where(
          (key) =>
              key.toString() == _metadataKey ||
              key.toString().startsWith(_segmentPrefix),
        )
        .toList(growable: false);

    for (final key in keys) {
      await _box.delete(key);
    }
  }

  Map<dynamic, dynamic>? get _metadata {
    final value = _box.get(_metadataKey);
    return value is Map ? value : null;
  }

  String _segmentKey(int index) => '$_segmentPrefix$index';

  double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
