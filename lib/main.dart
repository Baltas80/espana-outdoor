import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app/app.dart';
import 'core/observability/sentry_observability.dart';

const _navigationChannel = MethodChannel('com.espanaoutdoors/navigation');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  if (accessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(accessToken);

    // MainActivity has installed this channel before Dart main() runs.
    // Configure the shared persistent TileStore before runApp can construct
    // the first MapWidget. An initialization error intentionally fails closed.
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _navigationChannel.invokeMethod<void>('configure', {
        'accessToken': accessToken,
      });
    }
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
