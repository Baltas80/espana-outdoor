import 'package:flutter/material.dart';

import '../../app/outdoor_visuals.dart';
import '../../app/design_system/eo_icon_library.dart';

class NaturaProtectPage extends StatelessWidget {
  const NaturaProtectPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <({Widget icon, String title, String body})>[
      (
        icon: const EOIcon(EOIconName.nature, size: 32),
        title: 'Impacto responsable',
        body: 'Reduce la presión sobre hábitats sensibles y prioriza senderos y zonas autorizadas.',
      ),
      (
        icon: const EOIcon(EOIconName.wildlife, size: 32),
        title: 'Fauna sensible',
        body: 'Las ubicaciones sensibles no se muestran con precisión cuando existe riesgo de perturbación.',
      ),
      (
        icon: const EOIcon(EOIconName.nature, size: 32),
        title: 'No dejar huella',
        body: 'Evita residuos, ruidos, atajos y cualquier conducta que degrade el entorno.',
      ),
      (
        icon: const Icon(Icons.info_outline),
        title: 'Datos con procedencia',
        body: 'La información ambiental debe conservar fuente, fecha y nivel de confianza.',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('NATURA PROTECT')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const OutdoorVisualHero(asset: 'assets/visuals/hero_natura.svg', title: 'NATURA 2000', subtitle: 'Espacios protegidos y navegación responsable.'),
          const SizedBox(height: 18),
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const OutdoorAssetIcon(
                    asset: 'assets/visuals/icons/library/premium/nature.webp',
                    size: 56,
                  ),
                  const SizedBox(height: 12),
                  Text('Descubre. Respeta. Conserva.',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onPrimaryContainer,
                      )),
                  const SizedBox(height: 8),
                  Text(
                    'La naturaleza forma parte de la ruta. La aplicación debe ayudarte a disfrutarla sin aumentar su impacto.',
                    style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (final item in items) ...[
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                leading: SizedBox(width: 36, height: 36, child: Center(child: item.icon)),
                title: Text(item.title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(item.body),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          Text(
            'NATURA PROTECT no sustituye las normas del espacio protegido ni las indicaciones de sus gestores.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
