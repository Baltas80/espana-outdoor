import 'package:flutter/material.dart';
import '../../app/outdoor_visuals.dart';

import '../../core/domain/outdoor_models.dart';
import 'pet_safety.dart';

class PetsPage extends StatefulWidget {
  const PetsPage({super.key});

  @override
  State<PetsPage> createState() => _PetsPageState();
}

class _PetsPageState extends State<PetsPage> {
  final _engine = const PetSafetyEngine();
  double _temperature = 24;
  bool _water = true;
  bool _shade = true;

  @override
  Widget build(BuildContext context) {
    const pet = PetProfile(
      id: 'demo-pet',
      name: 'Mi mascota',
      size: 'mediano',
    );
    final assessment = _engine.assess(
      pet: pet,
      distanceKm: 8.4,
      elevationGainMeters: 510,
      temperatureC: _temperature,
      hasReliableWater: _water,
      hasShade: _shade,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Mascotas')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const OutdoorVisualHero(asset: 'assets/visuals/hero_pets.svg', title: 'Mascotas', subtitle: 'Rutas pet-friendly y preparación antes de salir.'),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [OutdoorAssetIcon(asset: 'assets/visuals/icons/library/premium/pets.webp', size: 72)]),
          const SizedBox(height: 16),
          Text(
            'Preparación para mascotas',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Evalúa las condiciones de una salida antes de poner a tu mascota en ruta.',
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.thermostat_outlined),
                    title: const Text('Temperatura estimada'),
                    subtitle: Text(
                      '${_temperature.toStringAsFixed(0)} °C',
                    ),
                  ),
                  Slider(
                    value: _temperature,
                    min: 10,
                    max: 40,
                    divisions: 30,
                    label: '${_temperature.toStringAsFixed(0)} °C',
                    onChanged: (value) => setState(() => _temperature = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hay agua fiable'),
                    value: _water,
                    onChanged: (value) => setState(() => _water = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hay sombra'),
                    value: _shade,
                    onChanged: (value) => setState(() => _shade = value),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(_iconFor(assessment.level)),
              title: Text(
                _labelFor(assessment.level),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                assessment.reasons.isEmpty
                    ? 'Condiciones base dentro de parámetros de precaución.'
                    : assessment.reasons.join(' '),
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
                  const Text(
                    'Checklist',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  for (final item in assessment.checklist)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(item)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _labelFor(OutdoorRiskLevel level) {
    switch (level) {
      case OutdoorRiskLevel.low:
        return 'Riesgo bajo';
      case OutdoorRiskLevel.caution:
        return 'Precaución';
      case OutdoorRiskLevel.high:
        return 'Riesgo alto';
      case OutdoorRiskLevel.extreme:
        return 'Riesgo extremo';
      case OutdoorRiskLevel.unknown:
        return 'Datos insuficientes';
    }
  }

  IconData _iconFor(OutdoorRiskLevel level) {
    switch (level) {
      case OutdoorRiskLevel.low:
        return Icons.check_circle_outline;
      case OutdoorRiskLevel.caution:
        return Icons.warning_amber_outlined;
      case OutdoorRiskLevel.high:
      case OutdoorRiskLevel.extreme:
        return Icons.error_outline;
      case OutdoorRiskLevel.unknown:
        return Icons.help_outline;
    }
  }
}
