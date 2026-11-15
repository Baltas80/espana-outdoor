import 'package:latlong2/latlong.dart';

import '../../core/contracts/routing_service.dart';

/// Selects the native offline-capable Mapbox router for walking and Valhalla
/// for cycling profiles and GPX map matching.
///
/// This keeps the offline graph honest: the current downloaded Mapbox graph is
/// pedestrian-only, so bicycle requests must never be sent to it.
class CompositeRoutingService implements RoutingService {
  const CompositeRoutingService({
    required this.mapbox,
    required this.valhalla,
  });

  final RoutingService? mapbox;
  final RoutingService? valhalla;

  static bool _isWalking(String profile) {
    return switch (profile.trim().toLowerCase()) {
      'hiking' || 'walking' || 'pedestrian' => true,
      _ => false,
    };
  }

  @override
  Future<RouteResult> route(RouteRequest request) async {
    final walking = _isWalking(request.profile);
    final selected = walking ? (mapbox ?? valhalla) : valhalla;
    if (selected == null) {
      if (walking) {
        throw StateError(
          'No hay un motor de rutas peatonales configurado. '
          'Configura Mapbox en Android o VALHALLA_BASE_URL.',
        );
      }
      throw StateError(
        'BTT y cicloturismo requieren un endpoint Valhalla HTTPS '
        'configurado mediante VALHALLA_BASE_URL.',
      );
    }
    return selected.route(request);
  }

  @override
  Future<RouteResult> match(List<LatLng> track) async {
    final service = valhalla;
    if (service == null) {
      throw StateError(
        'El ajuste de tracks GPX requiere VALHALLA_BASE_URL.',
      );
    }
    return service.match(track);
  }
}
