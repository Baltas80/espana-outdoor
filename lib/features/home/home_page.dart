import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand.dart';
import '../../app/outdoor_visuals.dart';
import '../shop/shop_entry_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              centerTitle: false,
              title: Row(
                children: [
                  OutdoorBrandMark(size: 46, dark: dark),
                  const SizedBox(width: 10),
                  const Text('ESPAÑA OUTDOOR'),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Perfil',
                  onPressed: () => context.go('/profile'),
                  icon: const Icon(Icons.person_outline),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    const OutdoorVisualHero(
                      asset: 'assets/visuals/outdoor_photo_atlas.jpg',
                      title: 'Explora España',
                      subtitle: 'Rutas, naturaleza y seguridad en una sola experiencia.',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Todo lo que necesitas para salir preparado',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 14),
                    _FeatureGrid(
                      items: [
                        _HomeFeature(
                          asset: 'assets/visuals/icons/library/premium/route.webp',
                          label: 'Rutas',
                          onTap: () => context.go('/routes'),
                        ),
                        _HomeFeature(
                          asset: 'assets/visuals/icons/library/premium/map.webp',
                          label: 'Mapa',
                          onTap: () => context.go('/map'),
                        ),
                        _HomeFeature(
                          asset: 'assets/visuals/icons/library/premium/offline.webp',
                          label: 'Offline',
                          onTap: () => context.go('/offline'),
                        ),
                        _HomeFeature(
                          asset: 'assets/visuals/icons/library/premium/pets.webp',
                          label: 'Mascotas',
                          onTap: () => context.go('/pets'),
                        ),
                        _HomeFeature(
                          asset: 'assets/visuals/icons/library/premium/wildlife.webp',
                          label: 'Fauna',
                          onTap: () => context.go('/wildlife'),
                        ),
                        _HomeFeature(
                          asset: 'assets/visuals/icons/library/premium/nature.webp',
                          label: 'Natura 2000',
                          onTap: () => context.go('/natura'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.go('/safety'),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .errorContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const OutdoorAssetIcon(
                                  asset: 'assets/visuals/icons/library/premium/safety.webp',
                                  size: 44,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Centro de seguridad',
                                      style: TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                    SizedBox(height: 4),
                                    Text('SOS, ubicación, contactos y preparación.'),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const ShopEntryCard(),
                    const SizedBox(height: 20),
                    Text(
                      'Antes de salir',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    const _ReadinessCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.items});

  final List<_HomeFeature> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, index) => items[index],
    );
  }
}

class _HomeFeature extends StatelessWidget {
  const _HomeFeature({
    required this.asset,
    required this.label,
    required this.onTap,
  });

  final String asset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutdoorAssetIcon(asset: asset, size: 48),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _ReadinessRow(
              asset: 'assets/visuals/icons/library/premium/offline.webp',
              label: 'Mapa offline',
              value: 'Preparar',
              onTap: () => context.go('/offline'),
            ),
            const Divider(height: 24),
            const _ReadinessRow(
              asset: 'assets/visuals/icons/library/premium/map.webp',
              label: 'Ubicación',
              value: 'Disponible',
            ),
            const Divider(height: 24),
            _ReadinessRow(
              asset: 'assets/visuals/icons/library/premium/safety.webp',
              label: 'Contacto de confianza',
              value: 'Configurar',
              onTap: () => context.go('/safety/contacts'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({
    required this.asset,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String asset;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            OutdoorAssetIcon(asset: asset, size: 34),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            Text(
              value,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}
