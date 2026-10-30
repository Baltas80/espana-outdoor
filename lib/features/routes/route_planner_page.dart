import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' show Position;

import '../../core/contracts/routing_service.dart';
import '../../core/location/location_controller.dart';
import '../../core/routing/routing_provider.dart';
import '../map/mapbox_map_viewport.dart';

class RoutePlannerPage extends ConsumerStatefulWidget {
  const RoutePlannerPage({super.key});

  @override
  ConsumerState<RoutePlannerPage> createState() => _RoutePlannerPageState();
}

class _RoutePlannerPageState extends ConsumerState<RoutePlannerPage> {
  LatLng? _destination;
  RouteResult? _route;
  bool _busy = false;
  String? _error;

  Future<void> _showDestinationDialog() async {
    final existing = _destination;
    final latController = TextEditingController(
      text: existing?.latitude.toString() ?? '',
    );
    final lonController = TextEditingController(
      text: existing?.longitude.toString() ?? '',
    );
    final result = await showDialog<LatLng>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Destino'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: latController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Latitud'),
            ),
            TextField(
              controller: lonController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Longitud'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final latitude = double.tryParse(latController.text.trim());
              final longitude = double.tryParse(lonController.text.trim());
              if (latitude == null ||
                  longitude == null ||
                  !latitude.isFinite ||
                  !longitude.isFinite ||
                  latitude.abs() > 90 ||
                  longitude.abs() > 180) {
                return;
              }
              Navigator.pop(
                dialogContext,
                LatLng(latitude, longitude),
              );
            },
            child: const Text('Usar destino'),
          ),
        ],
      ),
    );
    latController.dispose();
    lonController.dispose();

    if (result == null || !mounted) return;
    setState(() {
      _destination = result;
      _route = null;
      _error = null;
    });
  }

  Future<void> _calculate() async {
    final destination = _destination;
    if (destination == null) {
      _show('Selecciona primero un destino.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      var locationState = ref.read(locationControllerProvider);
      if (locationState.position == null || locationState.isStale) {
        await ref.read(locationControllerProvider.notifier).locate();
        locationState = ref.read(locationControllerProvider);
      }

      final location = locationState.position;
      if (location == null || locationState.isStale) {
        throw StateError(
          'No hay una posición GPS reciente. Comprueba el permiso y la señal GPS.',
        );
      }

      final service = ref.read(routingServiceProvider);
      if (service == null) {
        throw StateError(
          'Valhalla no está configurado en esta compilación. '
          'Falta VALHALLA_BASE_URL.',
        );
      }

      final result = await service.route(
        RouteRequest(
          points: [
            LatLng(location.latitude, location.longitude),
            destination,
          ],
          profile: 'hiking',
        ),
      );

      if (!mounted) return;
      setState(() => _route = result);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _route = null;
        _error = _friendlyError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.contains('SocketException') ||
        message.contains('Failed host lookup')) {
      return 'No se puede conectar con el servicio de rutas. Comprueba la conexión.';
    }
    if (message.contains('TimeoutException')) {
      return 'Valhalla ha tardado demasiado en responder. Inténtalo de nuevo.';
    }
    return message;
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _distanceLabel(double? distanceMeters) {
    if (distanceMeters == null) return '—';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String _durationLabel(double? durationSeconds) {
    if (durationSeconds == null) return '—';
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '$hours h'
        : '$hours h $remainingMinutes min';
  }

  String _elevationLabel(double? meters, {required bool ascent}) {
    if (meters == null) return '—';
    final prefix = ascent ? '+' : '−';
    return '$prefix${meters.toStringAsFixed(0)} m';
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(locationControllerProvider);
    final location = locationState.position;
    final destination = _destination;
    final center = destination ??
        (location == null
            ? const LatLng(40.4168, -3.7038)
            : LatLng(location.latitude, location.longitude));

    final destinationLabel = destination == null
        ? 'Sin destino seleccionado.'
        : 'Destino: ${destination.latitude.toStringAsFixed(5)}, '
            '${destination.longitude.toStringAsFixed(5)}';

    return Scaffold(
      appBar: AppBar(title: const Text('Planificar ruta')),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapboxMapViewport(
              key: ValueKey(
                '${center.latitude}:${center.longitude}:'
                '${_route?.points.length ?? 0}',
              ),
              initialCenter: Position(center.longitude, center.latitude),
              initialZoom: destination == null ? 12 : 14,
              routePoints: (_route?.points ?? const <LatLng>[])
                  .map(
                    (point) => Position(point.longitude, point.latitude),
                  )
                  .toList(growable: false),
              currentPosition: location == null
                  ? null
                  : Position(location.longitude, location.latitude),
              destination: destination == null
                  ? null
                  : Position(destination.longitude, destination.latitude),
              onTap: _busy
                  ? null
                  : (point) {
                      setState(() {
                        _destination = LatLng(
                          point.lat.toDouble(),
                          point.lng.toDouble(),
                        );
                        _route = null;
                        _error = null;
                      });
                    },
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ruta de senderismo',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(destinationLabel),
                    if (destination == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Toca el mapa para colocar el destino.',
                        ),
                      ),
                    if (_busy) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 4),
                      const Text('Calculando ruta a pie con Valhalla…'),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (_route != null) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 18,
                        runSpacing: 10,
                        children: [
                          _RouteMetric(
                            label: 'Distancia',
                            value: _distanceLabel(_route!.distanceMeters),
                            icon: Icons.route_outlined,
                          ),
                          _RouteMetric(
                            label: 'Tiempo estimado',
                            value: _durationLabel(_route!.durationSeconds),
                            icon: Icons.schedule_outlined,
                          ),
                          _RouteMetric(
                            label: 'Desnivel +',
                            value: _elevationLabel(
                              _route!.ascentMeters,
                              ascent: true,
                            ),
                            icon: Icons.trending_up,
                          ),
                          _RouteMetric(
                            label: 'Desnivel −',
                            value: _elevationLabel(
                              _route!.descentMeters,
                              ascent: false,
                            ),
                            icon: Icons.trending_down,
                          ),
                        ],
                      ),
                      if (_route!.ascentMeters == null &&
                          _route!.descentMeters == null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Desnivel no disponible: el servidor Valhalla no '
                          'ha devuelto datos de elevación para esta ruta.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (_route!.steps.isNotEmpty) ...[
                        const Divider(height: 20),
                        Text(
                          'Primeras indicaciones',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        for (final step in _route!.steps.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.turn_right_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: 7),
                                Expanded(child: Text(step.instruction)),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _showDestinationDialog,
                    icon: const Icon(Icons.place_outlined),
                    label: const Text('SELECCIONAR DESTINO'),
                  ),
                ),
                if (_route != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => context.push(
                                '/navigation',
                                extra: _route,
                              ),
                      icon: const Icon(Icons.navigation_outlined),
                      label: const Text('Iniciar navegación'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy || destination == null ? null : _calculate,
                    icon: const Icon(Icons.alt_route),
                    label: Text(
                      _busy ? 'CALCULANDO…' : 'CALCULAR RUTA A PIE',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteMetric extends StatelessWidget {
  const _RouteMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 135,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
