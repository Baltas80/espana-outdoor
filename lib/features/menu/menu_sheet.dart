import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/eo_components.dart';
import '../../app/design_system/eo_icon_library.dart';

class MenuSheet extends StatelessWidget {
  const MenuSheet({super.key});

  static const _items = <({Widget icon, String label, String route})>[
    (icon: EOIcon(EOIconName.route, size: 32), label: 'Mis rutas', route: '/routes'),
    (icon: EOIcon(EOIconName.offline, size: 32), label: 'Offline', route: '/offline'),
    (icon: EOIcon(EOIconName.weather, size: 32), label: 'Meteorología', route: '/weather/lightning'),
    (icon: EOIcon(EOIconName.compass, size: 32), label: 'Instrumentos', route: '/instruments'),
    (icon: EOIcon(EOIconName.nature, size: 32), label: 'Naturaleza', route: '/natura'),
    (icon: EOIcon(EOIconName.wildlife, size: 32), label: 'Fauna', route: '/wildlife'),
    (icon: EOIcon(EOIconName.profile, size: 32), label: 'Ajustes', route: '/profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(EOSpacing.lg, EOSpacing.sm, EOSpacing.lg, EOSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: EOColors.textSecondary.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: EOSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Menú', style: EOTextStyles.title),
            ),
            const SizedBox(height: EOSpacing.sm),
            ..._items.map(
              (item) => ListTile(
                leading: SizedBox(width: 40, height: 40, child: Center(child: item.icon)),
                title: Text(item.label, style: EOTextStyles.body),
                trailing: const Icon(Icons.chevron_right, color: EOColors.textSecondary),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(item.route);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
