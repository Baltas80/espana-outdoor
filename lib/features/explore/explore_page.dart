import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/design_system/eo_icon_library.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  static const _areas = <
      ({String title, EOIconName icon, String description})>[
    (title: 'Rutas', icon: EOIconName.route, description: 'Senderismo, trail y bicicleta'),
    (title: 'Mascotas', icon: EOIconName.pets, description: 'Rutas compatibles y riesgos'),
    (title: 'Fauna', icon: EOIconName.wildlife, description: 'Encuentros y conservación'),
    (title: 'Meteorología', icon: EOIconName.weather, description: 'Condiciones para tu salida'),
    (title: 'Incendios', icon: EOIconName.wildfire, description: 'Situación y avisos'),
    (title: 'Offline', icon: EOIconName.offline, description: 'Prepara zonas sin conexión'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Explorar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Elige cómo quieres salir', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('No solo buscamos rutas: te ayudamos a entender el entorno antes y durante la aventura.'),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _areas.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260, mainAxisExtent: 132, crossAxisSpacing: 12, mainAxisSpacing: 12),
            itemBuilder: (context, index) {
              final item = _areas[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    switch (item.title) {
                      case 'Rutas':
                        context.go('/routes');
                      case 'Mascotas':
                        context.go('/pets');
                      case 'Fauna':
                        context.go('/wildlife');
                      case 'Offline':
                        context.go('/offline');
                      default:
                        break;
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      EOIcon(item.icon, size: 48),
                      const Spacer(),
                      Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const EOIcon(EOIconName.map, size: 40),
              title: const Text('Abrir mapa'),
              subtitle: const Text('Explora el territorio y prepara tu recorrido.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/map'),
            ),
          ),
        ],
      ),
    );
  }
}
