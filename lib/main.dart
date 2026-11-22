import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app/app.dart';
import 'core/observability/sentry_observability.dart';
import 'infrastructure/routing/mapbox_navigation_routing_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const mapboxToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  MapboxOptions.setAccessToken(mapboxToken);
  if (mapboxToken.isNotEmpty) {
    await MapboxNavigationRoutingService().configure(mapboxToken);
  }
  await Hive.initFlutter();
  await Hive.openBox<Map<dynamic, dynamic>>('route_records');
  await Hive.openBox<String>('weather_cache');
  await Hive.openBox<dynamic>('route_tracking');
  await Hive.openBox<dynamic>('offline_sync');

  await FileDownloader().start(autoCleanDatabase: true);
  await SentryObservability.run(() async {
    runApp(const ProviderScope(child: EspanaOutdoorApp()));
  });
}