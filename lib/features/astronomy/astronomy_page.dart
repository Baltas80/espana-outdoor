import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/photo_atlas.dart';
import '../../app/design_system/eo_icon_library.dart';
import '../../core/astronomy/outdoor_astronomy_service.dart';

class AstronomyPage extends StatefulWidget {
  const AstronomyPage({super.key});

  @override
  State<AstronomyPage> createState() => _AstronomyPageState();
}

class _AstronomyPageState extends State<AstronomyPage> {
  Position? _position;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() => _error = null);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _error = 'Activa la ubicación para calcular el cielo desde tu posición.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _error = 'Permiso de ubicación no disponible.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      if (mounted) setState(() => _position = position);
    } catch (error) {
      if (mounted) setState(() => _error = 'No se pudo obtener la posición: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    final now = DateTime.now();
    final moon = OutdoorAstronomyService.moonPhase(now);
    final solar = position == null ? null : OutdoorAstronomyService.solarPosition(time: now, latitude: position.latitude, longitude: position.longitude);
    final times = position == null ? null : OutdoorAstronomyService.solarTimes(date: now, latitude: position.latitude, longitude: position.longitude);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Astronomía de campo'),
        actions: [IconButton(onPressed: _locate, icon: const Icon(Icons.my_location), tooltip: 'Actualizar posición')],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const OutdoorPhotoHero(index: 9, title: 'Astronomía', subtitle: 'Cielo nocturno, observación y planificación.'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                const EOIcon(EOIconName.astronomy, size: 54),
                const SizedBox(width: 14),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Cielo sin conexión', style: TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text('Cálculos locales para orientación, planificación y observación.'),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!))),
          if (position != null) ...[
            _MetricCard(title: 'Sol ahora', value: solar == null ? '—' : '${solar.elevation.toStringAsFixed(1)}° de elevación · ${solar.azimuth.toStringAsFixed(0)}°', icon: Icons.wb_sunny_outlined),
            const SizedBox(height: 10),
            _MetricCard(title: 'Salida del Sol', value: _formatTime(times?.sunrise), icon: Icons.wb_twilight),
            const SizedBox(height: 10),
            _MetricCard(title: 'Puesta del Sol', value: _formatTime(times?.sunset), icon: Icons.wb_twilight),
            const SizedBox(height: 10),
            _MetricCard(title: 'Mediodía solar', value: _formatTime(times?.solarNoon), icon: Icons.light_mode_outlined),
            const SizedBox(height: 16),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(moon.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('${(moon.illumination * 100).round()} % iluminada · ${moon.ageDays.toStringAsFixed(1)} días de ciclo'),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: moon.illumination),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Los cálculos son aproximados y no sustituyen instrumentos profesionales ni avisos oficiales.'),
        ],
      ),
    );
  }

  String _formatTime(DateTime? value) {
    if (value == null) return 'No calculable en esta fecha/latitud';
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(value),
        ),
      );
}
