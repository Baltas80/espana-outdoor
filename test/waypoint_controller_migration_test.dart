import 'dart:convert';

import 'package:espana_outdoors/core/navigation/waypoint_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const currentKey = 'wp_v2';
  final legacyKey = ['espana', 'outdoor', 'waypoints', 'v1'].join('_');

  Map<String, Object?> waypoint(String id) => {
        'id': id,
        'name': 'Punto $id',
        'latitude': 40.0,
        'longitude': -3.0,
        'elevationMeters': null,
        'note': null,
        'createdAt': '2026-11-16T12:00:00.000Z',
      };

  test('migrates saved waypoints to the v2 key without data loss', () async {
    final encoded = jsonEncode(waypoint('legacy-1'));
    SharedPreferences.setMockInitialValues({legacyKey: [encoded]});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(waypointControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final prefs = await SharedPreferences.getInstance();
    expect(container.read(waypointControllerProvider).map((item) => item.id), ['legacy-1']);
    expect(prefs.getStringList(currentKey), [encoded]);
    expect(prefs.getStringList(legacyKey), isNull);
  });

  test('prefers an existing v2 list and removes stale legacy data', () async {
    final current = jsonEncode(waypoint('current-2'));
    final legacy = jsonEncode(waypoint('stale-1'));
    SharedPreferences.setMockInitialValues({
      currentKey: [current],
      legacyKey: [legacy],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(waypointControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final prefs = await SharedPreferences.getInstance();
    expect(container.read(waypointControllerProvider).map((item) => item.id), ['current-2']);
    expect(prefs.getStringList(currentKey), [current]);
    expect(prefs.getStringList(legacyKey), isNull);
  });
}
