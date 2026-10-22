import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/outdoor_visuals.dart';

import 'wildlife_guidance.dart';

/// Selected species, held in Riverpod per the app's declared state stack.
final wildlifeSpeciesProvider =
    NotifierProvider.autoDispose<WildlifeSpeciesController, String>(
  WildlifeSpeciesController.new,
);

class WildlifeSpeciesController extends Notifier<String> {
  @override
  String build() => 'Jabalí';

  void select(String species) => state = species;
}

class WildlifePage extends ConsumerWidget {
  const WildlifePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _catalog = const WildlifeGuidanceCatalog();
    final species = ref.watch(wildlifeSpeciesProvider);
    final guidance = _catalog.forSpecies(species);

    return Scaffold(
      appBar: AppBar(title: const Text('Fauna')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const OutdoorVisualHero(asset: 'assets/visuals/hero_wildlife.svg', title: 'Fauna', subtitle: 'Guía y prevención para encuentros con especies.'),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [OutdoorAssetIcon(asset: 'assets/visuals/icons/wildlife.svg', size: 64)]),
          const SizedBox(height: 16),
          Text(
            'Encuentros con fauna',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Orientación preventiva. La identificación no debe hacerse acercándose al animal.',
          ),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Jabalí', label: Text('Jabalí')),
              ButtonSegment(value: 'Serpiente', label: Text('Serpiente')),
              ButtonSegment(value: 'Otro', label: Text('Otro')),
            ],
            selected: {species},
            onSelectionChanged: (selection) => ref
                .read(wildlifeSpeciesProvider.notifier)
                .select(selection.first),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    guidance.species,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Qué hacer',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  for (final action in guidance.actions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_forward, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(action)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Evita',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  for (final item in guidance.avoid)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.block_outlined, size: 20),
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
}
