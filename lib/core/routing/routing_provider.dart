import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/routing_service.dart';
import '../../infrastructure/routing/valhalla_routing_service.dart';
import 'routing_config.dart';

final routingConfigProvider = Provider<RoutingConfig>((ref) {
  return RoutingConfig.fromEnvironment();
});

/// Provider for the mature Valhalla engine adapter.
///
/// No routing algorithm lives in the application. If the production endpoint
/// is not configured, consumers must keep routing unavailable rather than
/// silently falling back to an unverified provider.
final routingServiceProvider = Provider<RoutingService?>((ref) {
  final config = ref.watch(routingConfigProvider);
  final baseUri = config.baseUri;
  if (baseUri == null) return null;
  final service = ValhallaRoutingService(baseUri: baseUri);
  ref.onDispose(service.dispose);
  return service;
});
