import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Offline cartography is intentionally unavailable until a MapLibre-native
/// solution has been implemented and verified on Android without connectivity.
class OfflinePage extends StatelessWidget {
  const OfflinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mapas offline')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 56),
                const SizedBox(height: 20),
                Text(
                  'Cartografía offline no disponible',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'El mapa requiere conexión. La descarga de mapas sin conexión volverá a habilitarse cuando esté implementada y validada en Android.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/map'),
                  child: const Text('Volver al mapa'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
