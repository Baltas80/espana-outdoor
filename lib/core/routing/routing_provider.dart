import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/routing_service.dart';
import '../../infrastructure/routing/mapbox_navigation_routing_service.dart';
import '../../infrastructure/routing/valhalla_routing_service.dart';
import 'routing_config.dart';

final routingConfigProvider = Provider<RoutingConfig>((ref) {
  return RoutingConfig.fromEnvironment();
});

final routingServiceProvider = Provider<RoutingService?>((ref) {
  final config = ref.watch(routingConfigProvider);
  final valhalla = config.baseUri == null
      ? null
      : ValhallaRoutingService(baseUri: config.baseUri!);
  const mapboxToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  final mapbox = mapboxToken.isEmpty ? null : MapboxNavigationRoutingService();

  if (valhalla == null && mapbox == null) return null;
  if (valhalla != null) ref.onDispose(valhalla.dispose);
  return _OutdoorRoutingService(mapbox: mapbox, valhalla: valhalla);
});

class _OutdoorRoutingService implements RoutingService {
  const _OutdoorRoutingService({required this.mapbox, required this.valhalla});

  final MapboxNavigationRoutingService? mapbox;
  final ValhallaRoutingService? valhalla;

  @override
  Future<RouteResult> route(RouteRequest request) {
    final profile = request.profile.toLowerCase();
    final isCycling = const {
      'cycling', 'bike', 'mtb', 'btt', 'mountain',
      'mountain_bike', 'road',
    }.contains(profile);
    if (isCycling || mapbox == null) {
      final engine = valhalla;
      if (engine == null) {
        throw StateError('Valhalla is required for this routing profile.');
      }
      return engine.route(request);
    }
    return mapbox!.route(request);
  }

  @override
  Future<RouteResult> match(List points) {
    final engine = valhalla;
    if (engine == null) {
      throw StateError('Valhalla is required for track map matching.');
    }
    return engine.match(points.cast());
  }
}
