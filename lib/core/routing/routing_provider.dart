import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/routing_service.dart';
import '../../infrastructure/routing/composite_routing_service.dart';
import '../../infrastructure/routing/mapbox_navigation_routing_service.dart';
import '../../infrastructure/routing/valhalla_routing_service.dart';
import 'routing_config.dart';

final routingConfigProvider = Provider<RoutingConfig>((ref) {
  return RoutingConfig.fromEnvironment();
});

/// Android uses Mapbox Navigation for hiking/walking, including its local
/// routing graph. Valhalla remains the provider for BTT, cycle touring and
/// GPX map matching. Other platforms continue to use Valhalla.
final routingServiceProvider = Provider<RoutingService?>((ref) {
  final config = ref.watch(routingConfigProvider);
  final baseUri = config.baseUri;
  final valhalla = baseUri == null
      ? null
      : ValhallaRoutingService(baseUri: baseUri);
  if (valhalla != null) ref.onDispose(valhalla.dispose);

  const accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  final mapbox = defaultTargetPlatform == TargetPlatform.android &&
          accessToken.startsWith('pk.')
      ? MapboxNavigationRoutingService(accessToken: accessToken)
      : null;

  if (mapbox == null && valhalla == null) return null;
  return CompositeRoutingService(mapbox: mapbox, valhalla: valhalla);
});
