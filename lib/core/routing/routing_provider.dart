import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/routing_service.dart';
import '../../infrastructure/routing/mapbox_navigation_routing_service.dart';

/// Android uses the native Mapbox Navigation SDK. The SDK selects its online
/// Directions router or the onboard router according to connectivity and the
/// offline routing tiles available on the device.
final routingServiceProvider = Provider<RoutingService?>((ref) {
  const accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  if (defaultTargetPlatform != TargetPlatform.android || accessToken.isEmpty) {
    return null;
  }
  return MapboxNavigationRoutingService(accessToken: accessToken);
});
