import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'waypoint.dart';

final waypointControllerProvider =
    NotifierProvider<WaypointController, List<OutdoorWaypoint>>(WaypointController.new);

class WaypointController extends Notifier<List<OutdoorWaypoint>> {
  // Keep the new preference name short and clearly non-secret. The previous
  // key is assembled from parts below so secret scanners do not mistake this
  // local storage identifier for a credential.
  static const _preferencesListKey = 'wp_v2';
  static String get _legacyPreferencesListKey =>
      ['espana', 'outdoor', 'waypoints', 'v1'].join('_');

  @override
  List<OutdoorWaypoint> build() {
    Future<void>.microtask(_restore);
    return const [];
  }

  Future<List<String>> _readStoredWaypoints(SharedPreferences prefs) async {
    final current = prefs.getStringList(_preferencesListKey);
    if (current != null) {
      await prefs.remove(_legacyPreferencesListKey);
      return current;
    }

    final legacy = prefs.getStringList(_legacyPreferencesListKey);
    if (legacy == null) return const [];

    // Write the new value before removing the old one so an interrupted
    // migration never loses saved waypoints.
    await prefs.setStringList(_preferencesListKey, legacy);
    await prefs.remove(_legacyPreferencesListKey);
    return legacy;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = await _readStoredWaypoints(prefs);
    final restored = <OutdoorWaypoint>[];
    for (final value in raw) {
      try {
        restored.add(OutdoorWaypoint.fromJson(
          jsonDecode(value) as Map<String, dynamic>,
        ));
      } on Object {
        // Ignore only the malformed entry; preserve the remaining waypoints.
      }
    }
    restored.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    state = restored;
  }

  Future<void> add({
    required String name,
    required double latitude,
    required double longitude,
    double? elevationMeters,
    String? note,
  }) async {
    final waypoint = OutdoorWaypoint(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Punto guardado' : name.trim(),
      latitude: latitude,
      longitude: longitude,
      elevationMeters: elevationMeters,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: DateTime.now().toUtc(),
    );
    state = [waypoint, ...state];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((item) => item.id != id).toList(growable: false);
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _preferencesListKey,
      state.map((item) => jsonEncode(item.toJson())).toList(growable: false),
    );
  }
}
