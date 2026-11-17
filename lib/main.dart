import 'package:flutter/foundation.dart' show defaultTargetPlatform, debugPrint, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app/app.dart';
import 'core/observability/sentry_observability.dart';

const _appEnvironment = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'production',
);
const _mapboxTileStoreUsageMode = String.fromEnvironment(
  'MAPBOX_TILE_STORE_USAGE_MODE',
  defaultValue: 'default',
);

Future<void> _configureMapboxTileStoreUsage() async {
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final isStagingAndroid = _appEnvironment == 'staging' && isAndroid;

  if (_mapboxTileStoreUsageMode != 'default' && !isStagingAndroid) {
    throw StateError(
      'MAPBOX_TILE_STORE_USAGE_MODE overrides are restricted to Android staging.',
    );
  }
  if (!isStagingAndroid) return;

  switch (_mapboxTileStoreUsageMode) {
    case 'default':
      break;
    case 'disabled':
      MapboxMapsOptions.setTileStoreUsageMode(TileStoreUsageMode.DISABLED);
      break;
    default:
      throw ArgumentError.value(
        _mapboxTileStoreUsageMode,
        'MAPBOX_TILE_STORE_USAGE_MODE',
        'must be default or disabled',
      );
  }

  final effectiveMode = await MapboxMapsOptions.getTileStoreUsageMode();
  debugPrint(
    'MAPBOX_TILE_STORE_USAGE requested=$_mapboxTileStoreUsageMode '
    'effective=${effectiveMode.name.toLowerCase()}',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureMapboxTileStoreUsage();
  MapboxOptions.setAccessToken(
    const String.fromEnvironment('MAPBOX_ACCESS_TOKEN'),
  );
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