import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:background_downloader/background_downloader.dart';

import 'app/app.dart';
import 'core/observability/sentry_observability.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<Map<dynamic, dynamic>>('route_records');
  await Hive.openBox<Map<dynamic, dynamic>>('offline_regions');
  await Hive.openBox<String>('weather_cache');
  await Hive.openBox<dynamic>('route_tracking');
  await Hive.openBox<dynamic>('offline_sync');

  await FileDownloader().start(autoCleanDatabase: true);
  await SentryObservability.run(() async {
    runApp(const ProviderScope(child: EspanaOutdoorApp()));
  });
}