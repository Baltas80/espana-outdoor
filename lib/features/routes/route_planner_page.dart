import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide RoutingConfig;
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../core/contracts/routing_service.dart';
import '../../core/location/location_controller.dart';
import '../../core/routing/routing_config.dart';
import '../../infrastructure/routing/valhalla_routing_service.dart';
import '../map/maplibre_map_viewport.dart';

class RoutePlannerPage extends ConsumerStatefulWidget {
  const RoutePlannerPage({super.key});

  @override
  ConsumerState<RoutePlannerPage> createState() => _RoutePlannerPageState();
}

class _RoutePlannerPageState extends ConsumerState<RoutePlannerPage> {
  LatLng? _destination;
  RouteResult? _route;
  bool _busy = false;

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
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final lat = double.tryParse(latController.text.trim());
              final lon = double.tryParse(lonController.text.trim());
              if (lat == null ||
                  lon == null ||
                  lat.abs() > 90 ||
                  lon.abs() > 180)
                return;
              Navigator.pop(context, LatLng(lat, lon));
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
    });
  }

  Future<void> _calculate() async {
    final destination = _destination;
    if (destination == null) {
      _show('Selecciona primero un destino.');
      return;
    }

    var location = ref.read(locationControllerProvider).position;
    if (location == null) {
      await ref.read(locationControllerProvider.notifier).locate();
      location = ref.read(locationControllerProvider).position;
    }
    if (location == null) {
      _show('Necesitamos tu ubicación para calcular la ruta.');
      return;
    }

    final config = RoutingConfig.fromEnvironment();
    if (!config.isConfigured) {
      _show('Routing no está configurado en este APK.');
      return;
    }

    setState(() => _busy = true);
    try {
      final service = ValhallaRoutingService(baseUri: config.baseUri!);
      final result = await service.route(
        RouteRequest(
          points: [LatLng(location.latitude, location.longitude), destination],
          profile: 'hiking',
        ),
      );
      if (!mounted) return;
      setState(() => _route = result);
    } on Object catch (error) {
      if (mounted) _show(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceFirst('Exception: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationControllerProvider).position;
    final destination = _destination;
    final center =
        destination ??
        (location == null
            ? const LatLng(40.4168, -3.7038)
            : LatLng(location.latitude, location.longitude));

    final destinationLabel = destination == null
        ? 'Sin destino seleccionado.'
        : 'Destino: ${destination.latitude.toStringAsFixed(5)}, ${destination.longitude.toStringAsFixed(5)}';

    return Scaffold(
      appBar: AppBar(title: const Text('Planificar ruta')),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapLibreMapViewport(
              key: ValueKey(
                '${center.latitude}:${center.longitude}:${_route?.points.length ?? 0}',
              ),
              initialCenter: ml.LatLng(center.latitude, center.longitude),
              initialZoom: destination == null ? 12 : 14,
              routePoints: (_route?.points ?? const <LatLng>[])
                  .map((point) => ml.LatLng(point.latitude, point.longitude))
                  .toList(growable: false),
              currentPosition: location == null
                  ? null
                  : ml.LatLng(location.latitude, location.longitude),
              destination: destination == null
                  ? null
                  : ml.LatLng(destination.latitude, destination.longitude),
              onTap: _busy
                  ? null
                  : (point) => setState(() {
                      _destination = LatLng(point.latitude, point.longitude);
                      _route = null;
                    }),
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
                          'Toca un punto del mapa para colocar el destino.',
                        ),
                      ),
                    if (_route != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${((_route!.distanceMeters ?? 0) / 1000).toStringAsFixed(1)} km · ${((_route!.durationSeconds ?? 0) / 60).round()} min',
                      ),
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
                const SizedBox(height: 8),
                if (_route != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => context.push('/navigation', extra: _route),
                      icon: const Icon(Icons.navigation_outlined),
                      label: const Text('Iniciar navegación'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy || destination == null ? null : _calculate,
                    icon: const Icon(Icons.alt_route),
                    label: Text(_busy ? 'CALCULANDO…' : 'CALCULAR RUTA'),
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
