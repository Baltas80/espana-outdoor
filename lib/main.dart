import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app/app.dart';
import 'core/observability/sentry_observability.dart';

const _mapboxNavigationChannel = MethodChannel('com.espanaoutdoors/navigation');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  MapboxOptions.setAccessToken(mapboxAccessToken);

  if (defaultTargetPlatform == TargetPlatform.android &&
      mapboxAccessToken.isNotEmpty) {
    try {
      await _mapboxNavigationChannel.invokeMethod<void>('configure', {
        'accessToken': mapboxAccessToken,
      });
    } on PlatformException catch (error) {
      debugPrint('Mapbox Navigation initialization failed: ${error.code}');
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
