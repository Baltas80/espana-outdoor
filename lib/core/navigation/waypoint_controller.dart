import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'waypoint.dart';

final waypointControllerProvider =
    NotifierProvider<WaypointController, List<OutdoorWaypoint>>(WaypointController.new);

class WaypointController extends Notifier<List<OutdoorWaypoint>> {
  static const _preferencesListKey = 'espana_outdoor_waypoints_v1';

  @override
  List<OutdoorWaypoint> build() {
    Future<void>.microtask(_restore);
    return const [];
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_preferencesListKey) ?? const [];
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
