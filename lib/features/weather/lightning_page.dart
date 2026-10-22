import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lightning_providers.dart';

class LightningPage extends ConsumerStatefulWidget {
  const LightningPage({super.key});

  @override
  ConsumerState<LightningPage> createState() => _LightningPageState();
}

class _LightningPageState extends ConsumerState<LightningPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _calculate() {
    ref.read(lightningDelayProvider.notifier).submit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(lightningDistanceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Distancia de tormenta')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Calcula la distancia de un rayo', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Cuenta los segundos entre el destello y el trueno e introdúcelos aquí.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Segundos', suffixText: 's', border: OutlineInputBorder()),
                  onSubmitted: (_) => _calculate(),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _calculate, icon: const Icon(Icons.bolt), label: const Text('Calcular')), 
              ]),
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${result!.distanceKm.toStringAsFixed(2)} km', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${result!.distanceMeters.round()} m aproximadamente'),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text('Estimación basada en una velocidad del sonido aproximada de 343 m/s. El viento, la temperatura y la topografía pueden alterar el resultado. No sustituye las alertas meteorológicas oficiales.'),
        ],
      ),
    );
  }
}
