import 'dart:async';

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

Future<void> _configureMapboxNavigation(String accessToken) async {
  if (accessToken.isEmpty) {
    debugPrint('APP_BOOTSTRAP mapbox_navigation=skipped reason=missing_token');
    return;
  }

  MapboxOptions.setAccessToken(accessToken);
  if (defaultTargetPlatform != TargetPlatform.android) return;

  try {
    await _navigationChannel
        .invokeMethod<void>('configure', {'accessToken': accessToken})
        .timeout(const Duration(seconds: 20));
    debugPrint('APP_BOOTSTRAP mapbox_navigation=ready');
  } on TimeoutException {
    // Navigation is optional for rendering the rest of the app. Route
    // requests still fail closed in the native adapter until it is ready.
    debugPrint('APP_BOOTSTRAP mapbox_navigation=timeout');
  } on PlatformException catch (error) {
    // Do not print native exception messages: SDK errors can contain URLs.
    debugPrint('APP_BOOTSTRAP mapbox_navigation=unavailable code=${error.code}');
  } on Object catch (error) {
    debugPrint('APP_BOOTSTRAP mapbox_navigation=unavailable type=${error.runtimeType}');
  }
}

Future<void> _startBackgroundDownloader() async {
  try {
    await FileDownloader()
        .start(autoCleanDatabase: true)
        .timeout(const Duration(seconds: 20));
    debugPrint('APP_BOOTSTRAP background_downloader=ready');
  } on TimeoutException {
    // Keep the main UI available if the optional background service stalls.
    debugPrint('APP_BOOTSTRAP background_downloader=timeout');
  } on Object catch (error) {
    debugPrint('APP_BOOTSTRAP background_downloader=unavailable type=${error.runtimeType}');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('APP_BOOTSTRAP stage=begin');

  const accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  await _configureMapboxNavigation(accessToken);

  debugPrint('APP_BOOTSTRAP stage=hive_init');
  await Hive.initFlutter();
  await Hive.openBox<Map<dynamic, dynamic>>('route_records');
  await Hive.openBox<String>('weather_cache');
  await Hive.openBox<dynamic>('route_tracking');
  await Hive.openBox<dynamic>('offline_sync');

  await _startBackgroundDownloader();

  debugPrint('APP_BOOTSTRAP stage=run_app');
  await SentryObservability.run(() async {
    runApp(const ProviderScope(child: EspanaOutdoorApp()));
  });
}
