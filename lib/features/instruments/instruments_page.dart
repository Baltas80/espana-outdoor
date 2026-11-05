import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/photo_atlas.dart';
import '../../app/outdoor_visuals.dart';
import '../../core/sensors/outdoor_sensor_models.dart';
import '../../core/sensors/outdoor_sensor_service.dart';

class InstrumentsPage extends ConsumerWidget {
  const InstrumentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensor = ref.watch(outdoorSensorProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Instrumentos de campo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const OutdoorPhotoHero(index: 8, title: 'Instrumentos', subtitle: 'Brújula, altímetro, barómetro y coordenadas.'),
          const SizedBox(height: 16),
          const _IntroCard(),
          const SizedBox(height: 16),
          _CompassCard(sensor: sensor),
          const SizedBox(height: 12),
          _MetricCard(icon: Icons.speed_outlined, title: 'Presión atmosférica', value: sensor.pressureHpa == null ? 'No disponible' : '${sensor.pressureHpa!.toStringAsFixed(1)} hPa', subtitle: sensor.barometerAvailable ? 'Sensor barométrico del dispositivo' : 'El dispositivo no expone un barómetro compatible'),
          const SizedBox(height: 12),
          _MetricCard(icon: Icons.terrain_outlined, visualIcon: const OutdoorAssetIcon(asset: 'assets/visuals/icons/library/premium/elevation.webp', size: 42), title: 'Altitud barométrica', value: sensor.sensorAltitudeMeters == null ? 'No disponible' : '${sensor.sensorAltitudeMeters!.toStringAsFixed(0)} m', subtitle: 'Estimación con presión estándar; calibra para mayor precisión'),
          const SizedBox(height: 12),
          _MetricCard(icon: Icons.gps_fixed, title: 'Altitud GPS', value: sensor.gpsAltitudeMeters == null ? 'No disponible' : '${sensor.gpsAltitudeMeters!.toStringAsFixed(0)} m', subtitle: 'Referencia independiente del barómetro', trailing: IconButton(tooltip: 'Actualizar GPS', onPressed: () => ref.read(outdoorSensorProvider.notifier).refreshGpsAltitude(), icon: const Icon(Icons.refresh))),
          const SizedBox(height: 12),
          _ToolCard(icon: Icons.nightlight_round, title: 'Astronomía de campo', subtitle: 'Sol, amanecer, puesta, posición solar y fase lunar sin conexión.', onTap: () => context.push('/astronomy')),
          const SizedBox(height: 10),
          _ToolCard(icon: Icons.thunderstorm_outlined, title: 'Distancia de tormenta', subtitle: 'Estima la distancia de un rayo con el intervalo entre destello y trueno.', onTap: () => context.push('/weather/lightning')),
          if (sensor.error != null) ...[
            const SizedBox(height: 12),
            Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(16), child: Text(sensor.error!))),
          ],
          const SizedBox(height: 16),
          Text('Integración de sensores', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Estas herramientas complementan la navegación y las rutas de España Outdoor. No sustituyen el GPS, los mapas offline ni las fuentes meteorológicas oficiales.'),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [const OutdoorAssetIcon(asset: 'assets/visuals/icons/library/premium/compass.webp', size: 52), const SizedBox(width: 14), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Herramientas de campo', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 4), Text('Brújula, presión y altitud usando los sensores del teléfono.')]))])));
}

class _CompassCard extends StatelessWidget {
  const _CompassCard({required this.sensor});
  final OutdoorSensorState sensor;
  @override
  Widget build(BuildContext context) {
    final heading = sensor.heading;
    final direction = heading == null ? '—' : _cardinalDirection(heading);
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Brújula', style: TextStyle(fontWeight: FontWeight.w800)), Text(sensor.compassAvailable ? 'Sensor OK' : 'No disponible', style: Theme.of(context).textTheme.labelMedium)]),
      const SizedBox(height: 18),
      SizedBox(width: 190, height: 190, child: Stack(alignment: Alignment.center, children: [
        Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.outline, width: 2))),
        if (heading != null) Transform.rotate(angle: -heading * math.pi / 180, child: const Icon(Icons.navigation, size: 108)),
        Positioned(top: 12, child: Text('N', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
        Positioned(bottom: 12, child: Text('S', style: Theme.of(context).textTheme.labelLarge)),
        Positioned(left: 12, child: Text('O', style: Theme.of(context).textTheme.labelLarge)),
        Positioned(right: 12, child: Text('E', style: Theme.of(context).textTheme.labelLarge)),
      ])),
      const SizedBox(height: 14),
      Text(heading == null ? 'Sin lectura' : '${heading.toStringAsFixed(0)}° · $direction', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      if (sensor.headingAccuracy != null) Text('Precisión estimada ±${sensor.headingAccuracy!.toStringAsFixed(0)}°'),
    ])));
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(icon), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap));
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.title, required this.value, required this.subtitle, this.trailing, this.visualIcon});
  final IconData icon;
  final Widget? visualIcon;
  final String title;
  final String value;
  final String subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [visualIcon ?? Icon(icon, size: 32), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(value, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 2), Text(subtitle, style: Theme.of(context).textTheme.bodySmall)])), if (trailing != null) trailing!])));
}

String _cardinalDirection(double heading) {
  const names = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
  final index = ((heading % 360 + 22.5) ~/ 45) % 8;
  return names[index];
}
