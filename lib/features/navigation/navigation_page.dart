import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/contracts/routing_service.dart';
import '../../core/domain/outdoor_models.dart';
import '../../core/location/location_controller.dart';
import '../../core/navigation/navigation_guidance.dart';
import '../../core/location/route_recorder.dart';

/// Live navigation surface built around the same location/recording pipeline
/// used by the map. It deliberately does not invent turn instructions: those
/// are shown only when a real route/step feed is available from the routing
/// provider.
class NavigationPage extends ConsumerStatefulWidget {
  const NavigationPage({super.key, this.route});

  final RouteResult? route;

  @override
  ConsumerState<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends ConsumerState<NavigationPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationControllerProvider);
    final recording = ref.watch(routeRecorderProvider);
    final position = location.position;
    final accuracy = position?.accuracy;
    final guidance = widget.route == null || position == null
        ? null
        : const NavigationGuidanceEngine().evaluate(
            route: widget.route!,
            position: GeoPoint(
              latitude: position.latitude,
              longitude: position.longitude,
            ),
            accuracyMeters: position.accuracy,
          );
    final elapsed = recording.startedAt == null
        ? Duration.zero
        : DateTime.now().difference(recording.startedAt!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Navegación GPS'),
        actions: [
          IconButton(
            tooltip: 'Volver sobre mis pasos',
            onPressed: () => context.push('/navigation/backtrack'),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Puntos guardados',
            onPressed: () => context.push('/navigation/waypoints'),
            icon: const Icon(Icons.location_on_outlined),
          ),
          IconButton(
            tooltip: 'Centrar en mi posición',
            onPressed: () => ref.read(locationControllerProvider.notifier).locate(),
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(recording.isRecording ? Icons.navigation : Icons.gps_fixed, size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(recording.isRecording ? 'Navegación activa' : 'GPS preparado', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 6),
                          if (position != null && location.isStale)
                            Text('Última posición conocida${accuracy == null ? '' : ' · precisión ±${accuracy.toStringAsFixed(0)} m'} · el seguimiento no está activo',
                                style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          if (!(position != null && location.isStale))
                            Text(position == null ? 'Obtén una posición para comenzar.' : 'Posición disponible${accuracy == null ? '' : ' · precisión ±${accuracy.toStringAsFixed(0)} m'}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _StatGrid(distanceKm: recording.distanceMeters / 1000, elapsed: elapsed, altitude: position?.altitude, speedKmh: position == null ? null : position.speed * 3.6),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Posición actual', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    Text(position == null ? 'Sin posición disponible.' : '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}'),
                    if (position != null) ...[
                      const SizedBox(height: 6),
                      Text('Altitud: ${position.altitude.toStringAsFixed(0)} m'),
                      Text('Rumbo: ${_heading(position)}'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (guidance != null) _GuidanceCard(guidance: guidance),
            if (widget.route != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ruta calculada', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('${((widget.route!.distanceMeters ?? 0) / 1000).toStringAsFixed(1)} km · ${((widget.route!.durationSeconds ?? 0) / 60).round()} min'),
                      const SizedBox(height: 6),
                      Text(
                        widget.route!.ascentMeters == null &&
                                widget.route!.descentMeters == null
                            ? 'Desnivel: no disponible en los datos de elevación.'
                            : 'Desnivel +${widget.route!.ascentMeters?.toStringAsFixed(0) ?? '—'} m'
                                ' · −${widget.route!.descentMeters?.toStringAsFixed(0) ?? '—'} m',
                      ),
                      if (widget.route!.steps.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        for (final step in widget.route!.steps.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.turn_right_outlined, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(step.instruction)),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Instrucciones de ruta', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(widget.route == null ? 'Las indicaciones giro a giro aparecerán cuando exista una ruta calculada con pasos reales. No se muestran instrucciones inventadas.' : 'La ruta usa pasos devueltos por el motor de routing configurado.'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final recorder = ref.read(routeRecorderProvider.notifier);
                  if (recording.isRecording) {
                    await recorder.stop();
                  } else {
                    await recorder.start();
                  }
                } on Object catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
                }
              },
              icon: Icon(recording.isRecording ? Icons.stop : Icons.play_arrow),
              label: Text(recording.isRecording ? 'Detener navegación' : 'Iniciar navegación GPS'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => ref.read(locationControllerProvider.notifier).locate(),
              icon: const Icon(Icons.gps_fixed),
              label: const Text('Actualizar ubicación'),
            ),
          ],
        ),
      ),
    );
  }

  String _heading(Position position) {
    if (position.heading < 0) return 'no disponible';
    return '${position.heading.toStringAsFixed(0)}°';
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.distanceKm, required this.elapsed, required this.altitude, required this.speedKmh});
  final double distanceKm;
  final Duration elapsed;
  final double? altitude;
  final double? speedKmh;

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.15,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _Stat(label: 'Distancia', value: '${distanceKm.toStringAsFixed(2)} km'),
          _Stat(label: 'Tiempo', value: _duration(elapsed)),
          _Stat(label: 'Altitud', value: altitude == null ? '—' : '${altitude!.toStringAsFixed(0)} m'),
          _Stat(label: 'Velocidad', value: speedKmh == null ? '—' : '${speedKmh!.toStringAsFixed(1)} km/h'),
        ],
      );

  String _duration(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 3),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard({required this.guidance});
  final NavigationGuidance guidance;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String message;
    final IconData icon;
    switch (guidance.status) {
      case NavigationGuidanceStatus.noRoute:
        title = 'Sin ruta'; message = 'No hay una ruta válida para ofrecer guía.'; icon = Icons.route_outlined; break;
      case NavigationGuidanceStatus.gpsPoor:
        title = 'GPS con precisión insuficiente'; message = 'La posición actual no permite decidir con seguridad si estás fuera de ruta.'; icon = Icons.gps_off_outlined; break;
      case NavigationGuidanceStatus.onRoute:
        title = 'En ruta'; message = 'Separación de la ruta: ${guidance.distanceFromRouteMeters.toStringAsFixed(0)} m.'; icon = Icons.navigation_outlined; break;
      case NavigationGuidanceStatus.approachingTurn:
        title = 'Próximo giro'; message = guidance.nextStep == null ? 'Se aproxima una maniobra de la ruta.' : '${guidance.nextStep!.instruction} · ${guidance.distanceToNextStepMeters?.toStringAsFixed(0) ?? '—'} m'; icon = Icons.turn_right_outlined; break;
      case NavigationGuidanceStatus.offRoute:
        title = 'Fuera de ruta'; message = 'La posición está a ${guidance.distanceFromRouteMeters.toStringAsFixed(0)} m de la ruta. La aplicación no inventa una nueva ruta.'; icon = Icons.warning_amber_rounded; break;
      case NavigationGuidanceStatus.arrived:
        title = 'Llegada'; message = 'Estás dentro de la zona de llegada de la ruta.'; icon = Icons.flag_outlined; break;
    }
    final color = guidance.status == NavigationGuidanceStatus.offRoute || guidance.status == NavigationGuidanceStatus.gpsPoor ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary;
    return Card(child: ListTile(leading: Icon(icon, color: color), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(message)));
  }
}
