import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:espana_outdoors/core/domain/outdoor_models.dart';
import 'package:espana_outdoors/core/storage/route_recording_store.dart';

void main() {
  group('RouteRecordingStore', () {
    late Directory hiveDir;
    late Box<dynamic> box;
    late RouteRecordingStore store;

    setUpAll(() async {
      hiveDir = await Directory.systemTemp.createTemp('espana-outdoors-hive-');
      Hive.init(hiveDir.path);
    });

    setUp(() async {
      box = await Hive.openBox<dynamic>('route_tracking_test');
      await box.clear();
      store = RouteRecordingStore(box: box);
    });

    tearDown(() async {
      await box.close();
      await Hive.deleteBoxFromDisk('route_tracking_test');
    });

    tearDownAll(() async {
      await Hive.close();
      if (await hiveDir.exists()) await hiveDir.delete(recursive: true);
    });

    test('persists and recovers long active sessions in segments', () async {
      final startedAt = DateTime.utc(2026, 9, 23, 12);
      await store.begin(startedAt: startedAt);

      for (var i = 0; i < 125; i++) {
        await store.append(
          point: GeoPoint(
            latitude: 40 + i / 100000,
            longitude: -3 - i / 100000,
          ),
          distanceMeters: i * 5,
        );
      }

      final recovered = store.recover();

      expect(recovered, isNotNull);
      expect(recovered!.points, hasLength(125));
      expect(recovered.distanceMeters, 620);
      expect(recovered.startedAt, startedAt);
    });

    test('finish removes recoverable session', () async {
      await store.begin(startedAt: DateTime.utc(2026, 9, 23));
      await store.append(
        point: const GeoPoint(latitude: 40.4, longitude: -3.7),
        distanceMeters: 0,
      );

      await store.finish();

      expect(store.recover(), isNull);
    });
  });
}
