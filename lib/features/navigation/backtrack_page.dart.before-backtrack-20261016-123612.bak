import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/location/location_controller.dart';
import '../../core/location/route_recorder.dart';
import '../../core/navigation/backtrack.dart';

class BacktrackPage extends ConsumerWidget {
  const BacktrackPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(routeRecorderProvider);
    final location = ref.watch(locationControllerProvider);
    final guidance = location.position == null
        ? null
        : const BacktrackService().calculate(
            current: location.position!,
            recordedPoints: recording.points,
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Volver sobre mis pasos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(Icons.undo, size: 40, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Backtrack offline', style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 4),
                        Text('Usa el recorrido grabado para regresar por el camino ya realizado, sin depender de una ruta online.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!recording.isRecording)
            FilledButton.icon(
              onPressed: () => ref.read(routeRecorderProvider.notifier).start(),
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Iniciar grabación'),
            )
          else
            OutlinedButton.icon(
              onPressed: () => ref.read(routeRecorderProvider.notifier).stop(),
              icon: const Icon(Icons.stop),
              label: const Text('Detener grabación'),
            ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => ref.read(locationControllerProvider.notifier).locate(),
            icon: const Icon(Icons.my_location),
            label: const Text('Actualizar ubicación'),
          ),
          const SizedBox(height: 18),
          _StatCard(
            title: 'Puntos registrados',
            value: '${recording.points.length}',
            subtitle: recording.isRecording ? 'Grabación activa' : 'Inicia una ruta para generar el track',
            icon: Icons.route,
          ),
          const SizedBox(height: 12),
          _StatCard(
            title: 'Distancia grabada',
            value: _distance(recording.distanceMeters),
            subtitle: recording.persistenceHealthy ? 'Persistencia local operativa' : 'Aviso: no se pudo guardar el último punto',
            icon: Icons.straighten,
          ),
          const SizedBox(height: 18),
          if (guidance == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  recording.points.length < 2
                      ? 'Necesitas al menos dos puntos GPS grabados para activar Backtrack.'
                      : 'Obteniendo ubicación para calcular la dirección de regreso.',
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    const Text('Dirección de regreso', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 18),
                    Transform.rotate(
                      angle: guidance.bearingDegrees * math.pi / 180,
                      child: const Icon(Icons.navigation, size: 96),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${guidance.bearingDegrees.toStringAsFixed(0)}°',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text('${guidance.distanceMeters.toStringAsFixed(0)} m hasta el siguiente punto del track'),
                    const SizedBox(height: 4),
                    Text('${guidance.remainingPoints} puntos restantes en el recorrido inverso'),
                  ],
                ),
              ),
            ),
          if (location.message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(location.message, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  static String _distance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, required this.subtitle, required this.icon});
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(subtitle),
          trailing: Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
      );
}
