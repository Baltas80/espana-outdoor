import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../domain/outdoor_models.dart';

final class RouteRecordingSession {
  const RouteRecordingSession({
    required this.startedAt,
    required this.points,
    required this.distanceMeters,
    this.id = 'active',
    this.completedAt,
  });

  final String id;
  final DateTime startedAt;
  final List<GeoPoint> points;
  final double distanceMeters;
  final DateTime? completedAt;
}

final class RouteRecordingStore {
  RouteRecordingStore({Box<dynamic>? box})
      : _box = box ?? Hive.box<dynamic>(_boxName);

  static const _boxName = 'route_tracking';
  static const _metadataKey = '__active_session__';
  static const _segmentPrefix = '__segment__';
  static const _routeMetadataPrefix = '__route__';
  static const _routeSegmentPrefix = '__route_segment__';
  static const _segmentSize = 50;

  final Box<dynamic> _box;

  /// Starts a session without deleting completed routes or an interrupted
  /// active session.
  Future<void> begin({required DateTime startedAt}) async {
    if (hasActiveSession) {
      throw StateError(
        'An active route session already exists. Resume or explicitly clear '
        'that session before starting another route.',
      );
    }
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

  /// Recovers an interrupted session. [maxPoints] bounds the returned in-memory
  /// window only; all persisted segments remain intact.
  RouteRecordingSession? recover({int? maxPoints}) {
    if (maxPoints != null && maxPoints < 1) {
      throw ArgumentError.value(maxPoints, 'maxPoints', 'Must be positive.');
    }
    final metadata = _metadata;
    if (metadata == null || metadata['active'] != true) return null;
    return _readSession(
      metadata: metadata,
      id: 'active',
      segmentKey: _segmentKey,
      maxPoints: maxPoints,
    );
  }

  /// Lists completed routes, newest first. Intended for the route-history UI.
  List<RouteRecordingSession> getRoutes() {
    final routes = <RouteRecordingSession>[];
    for (final key in _box.keys) {
      final keyText = key.toString();
      if (!keyText.startsWith(_routeMetadataPrefix)) continue;
      final value = _box.get(key);
      if (value is! Map || value['active'] == true) continue;
      final id = keyText.substring(_routeMetadataPrefix.length);
      final session = _readSession(
        metadata: value,
        id: id,
        segmentKey: (index) => _routeSegmentKey(id, index),
      );
      if (session != null) routes.add(session);
    }
    routes.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List.unmodifiable(routes);
  }

  /// Returns the newest archived route ID without loading its point history.
  String? get latestRouteId {
    String? latestId;
    DateTime? latestStartedAt;
    for (final key in _box.keys) {
      final keyText = key.toString();
      if (!keyText.startsWith(_routeMetadataPrefix)) continue;
      final metadata = _box.get(key);
      if (metadata is! Map || metadata['active'] == true) continue;
      final startedAt =
          DateTime.tryParse(metadata['startedAt']?.toString() ?? '');
      if (startedAt == null) continue;
      if (latestStartedAt == null || startedAt.isAfter(latestStartedAt)) {
        latestStartedAt = startedAt;
        latestId = keyText.substring(_routeMetadataPrefix.length);
      }
    }
    return latestId;
  }

  RouteRecordingSession? loadRoute(String routeId) {
    final metadata = _box.get('$_routeMetadataPrefix$routeId');
    if (metadata is! Map || metadata['active'] == true) return null;
    return _readSession(
      metadata: metadata,
      id: routeId,
      segmentKey: (index) => _routeSegmentKey(routeId, index),
    );
  }

  /// Streams active points in persisted order without assembling a full route
  /// list in memory. Yields to the event loop periodically for long tracks.
  Stream<GeoPoint> streamActivePoints() async* {
    final metadata = _metadata;
    if (metadata == null || metadata['active'] != true) return;
    final segmentCount = (metadata['segmentCount'] as num?)?.toInt() ?? 0;
    var emitted = 0;
    for (var index = 0; index < segmentCount; index++) {
      final raw = _box.get(_segmentKey(index));
      if (raw is! List) continue;
      for (final item in raw) {
        final point = _decodePoint(item);
        if (point == null) continue;
        yield point;
        emitted++;
        if (emitted % 500 == 0) await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// Streams one archived route in persisted order.
  Stream<GeoPoint> streamRoutePoints(String routeId) async* {
    final metadata = _box.get('$_routeMetadataPrefix$routeId');
    if (metadata is! Map || metadata['active'] == true) return;
    final segmentCount = (metadata['segmentCount'] as num?)?.toInt() ?? 0;
    var emitted = 0;
    for (var index = 0; index < segmentCount; index++) {
      final raw = _box.get(_routeSegmentKey(routeId, index));
      if (raw is! List) continue;
      for (final item in raw) {
        final point = _decodePoint(item);
        if (point == null) continue;
        yield point;
        emitted++;
        if (emitted % 500 == 0) await Future<void>.delayed(Duration.zero);
      }
    }
  }

  bool get hasActiveSession => _metadata?['active'] == true;

  /// Archives first, then clears the active keys. A stable archive ID stored
  /// in active metadata makes retries safe if a write fails partway through.
  Future<void> finish() async {
    final metadata = _metadata;
    if (metadata == null || metadata['active'] != true) return;

    final startedAt =
        DateTime.tryParse(metadata['startedAt']?.toString() ?? '');
    if (startedAt == null) {
      throw StateError('Cannot archive route: invalid start timestamp.');
    }
    final segmentCount = (metadata['segmentCount'] as num?)?.toInt() ?? 0;
    if (segmentCount <= 0) {
      throw StateError('Cannot archive route: invalid segment count.');
    }

    var routeId = metadata['archivedRouteId']?.toString();
    if (routeId == null || routeId.isEmpty) {
      final baseId = startedAt.toUtc().microsecondsSinceEpoch.toString();
      routeId = baseId;
      var suffix = 1;
      while (_box.containsKey('$_routeMetadataPrefix$routeId')) {
        routeId = '${baseId}_$suffix';
        suffix++;
      }
      await _box.put(_metadataKey, <String, Object?>{
        ...metadata,
        'archivedRouteId': routeId,
      });
    }

    for (var index = 0; index < segmentCount; index++) {
      final raw = _box.get(_segmentKey(index));
      await _box.put(
        _routeSegmentKey(routeId!, index),
        raw is List ? List<Object?>.from(raw) : <Object?>[],
      );
    }

    await _box.put('$_routeMetadataPrefix$routeId', <String, Object?>{
      ..._metadata!,
      'active': false,
      'routeId': routeId,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
      'segmentCount': segmentCount,
    });

    await clear();
  }

  /// Clears only active/interrupted session data. Archived routes are retained.
  Future<void> clear() async {
    final keys = _box.keys
        .where((key) {
          final text = key.toString();
          return text == _metadataKey || text.startsWith(_segmentPrefix);
        })
        .toList(growable: false);
    for (final key in keys) {
      await _box.delete(key);
    }
  }

  /// Explicit operation for a future user-confirmed delete-history feature.
  Future<void> clearHistory() async {
    final keys = _box.keys
        .where((key) {
          final text = key.toString();
          return text.startsWith(_routeMetadataPrefix) ||
              text.startsWith(_routeSegmentPrefix);
        })
        .toList(growable: false);
    for (final key in keys) {
      await _box.delete(key);
    }
  }

  RouteRecordingSession? _readSession({
    required Map<dynamic, dynamic> metadata,
    required String id,
    required String Function(int index) segmentKey,
    int? maxPoints,
  }) {
    final startedAt =
        DateTime.tryParse(metadata['startedAt']?.toString() ?? '');
    if (startedAt == null) return null;
    final segmentCount = (metadata['segmentCount'] as num?)?.toInt() ?? 0;
    if (segmentCount <= 0) return null;

    final points = <GeoPoint>[];
    for (var index = 0; index < segmentCount; index++) {
      final raw = _box.get(segmentKey(index));
      if (raw is! List) continue;
      for (final item in raw) {
        final point = _decodePoint(item);
        if (point == null) continue;
        points.add(point);
      }
      if (maxPoints != null && points.length > maxPoints) {
        points.removeRange(0, points.length - maxPoints);
      }
    }

    if (points.isEmpty) return null;
    final completedAt =
        DateTime.tryParse(metadata['completedAt']?.toString() ?? '');
    return RouteRecordingSession(
      id: id,
      startedAt: startedAt.toUtc(),
      points: List.unmodifiable(points),
      distanceMeters: _asDouble(metadata['distanceMeters']) ?? 0,
      completedAt: completedAt?.toUtc(),
    );
  }

  GeoPoint? _decodePoint(Object? item) {
    if (item is! Map) return null;
    final latitude = _asDouble(item['latitude']);
    final longitude = _asDouble(item['longitude']);
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return GeoPoint(latitude: latitude, longitude: longitude);
  }

  Map<dynamic, dynamic>? get _metadata {
    final value = _box.get(_metadataKey);
    return value is Map ? value : null;
  }

  String _segmentKey(int index) => '$_segmentPrefix$index';

  String _routeSegmentKey(String routeId, int index) =>
      '$_routeSegmentPrefix${routeId}__$index';

  double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
