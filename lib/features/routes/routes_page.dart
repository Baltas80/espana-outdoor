import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/outdoor_visuals.dart';
import '../../core/gpx/gpx_import_service.dart';
import '../../core/storage/local_route_store.dart';

class RoutesPage extends StatefulWidget {
  const RoutesPage({super.key});

  @override
  State<RoutesPage> createState() => _RoutesPageState();
}

class _RoutesPageState extends State<RoutesPage> {
  final _gpx = const GpxImportService();
  final _store = LocalRouteStore();

  ImportedTrack? _imported;
  String? _error;
  String _filter = 'Todas';

  @override
  void initState() {
    super.initState();
    _imported = _store.loadLatestImportedTrack();
  }

  Future<void> _importGpx() async {
    setState(() => _error = null);
    try {
      final imported = await _gpx.pickAndImport();
      if (!mounted || imported == null) return;
      await _store.saveImportedTrack(imported);
      if (!mounted) return;
      setState(() => _imported = imported);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rutas'),
        actions: [
          IconButton(
            tooltip: 'Filtrar',
            onPressed: () {},
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Importar GPX',
            onPressed: _importGpx,
            icon: const OutdoorAssetIcon(asset: 'assets/visuals/icons/library/premium/gpx.webp', size: 28),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const OutdoorVisualHero(
            asset: 'assets/images/routes/cami_ronda_costa_brava.jpg',
            title: 'Descubre rutas por España',
            subtitle: 'Rutas con contexto y preparación offline.',
          ),
          const SizedBox(height: 14),
          const _SearchField(),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in const [
                  ('Todas', null),
                  ('Senderismo', 'hiking'),
                  ('MTB', 'cycling'),
                  ('Cicloturismo', 'cycling'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      avatar: item.$2 == null
                          ? null
                          : OutdoorAssetIcon(
                              asset:
                                  'assets/visuals/icons/library/premium/${item.$2}.webp',
                              size: 24,
                            ),
                      label: Text(item.$1),
                      selected: _filter == item.$1,
                      onSelected: (_) => setState(() => _filter = item.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _RouteVisualCard(
            asset: 'assets/images/routes/lagos_covadonga.jpg',
            icon: 'assets/visuals/icons/library/premium/route.webp',
            title: 'Lagos de Covadonga',
            subtitle: 'Picos de Europa · Asturias',
            meta: 'MODERADA · 12,4 km · ↑ 650 m · 4–5 h',
            onTap: () => context.push('/routes/planner'),
          ),
          const SizedBox(height: 12),
          _RouteVisualCard(
            asset: 'assets/images/routes/mulhacen_sierra_nevada.jpg',
            icon: 'assets/visuals/icons/library/premium/nature.webp',
            title: 'Mulhacén · Sierra Nevada',
            subtitle: 'Sierra Nevada · Granada',
            meta: 'DIFÍCIL · 18,7 km · ↑ 1.320 m · 7–8 h',
            onTap: () => context.push('/routes/planner'),
          ),
          const SizedBox(height: 12),
          _RouteVisualCard(
            asset: 'assets/images/routes/caminito_del_rey.jpg',
            icon: 'assets/visuals/icons/library/premium/map.webp',
            title: 'Caminito del Rey',
            subtitle: 'Málaga · Andalucía',
            meta: 'FÁCIL · 8,3 km · ↑ 210 m · 2–3 h',
            onTap: () => context.push('/routes/planner'),
          ),
          const SizedBox(height: 18),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            ),
          if (_imported != null) ...[
            _ImportedTrackCard(
              track: _imported!,
              onOpen: () => context.push('/routes/detail', extra: _imported),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: () => context.push('/routes/planner'),
            icon: const OutdoorAssetIcon(asset: 'assets/visuals/icons/library/premium/route.webp', size: 24),
            label: const Text('Planificar una ruta'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _importGpx,
            icon: const OutdoorAssetIcon(asset: 'assets/visuals/icons/library/premium/gpx.webp', size: 24),
            label: const Text('Importar GPX'),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    return const TextField(
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Buscar rutas, refugios…',
      ),
    );
  }
}

class _RouteVisualCard extends StatelessWidget {
  const _RouteVisualCard({
    required this.asset,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.onTap,
  });

  final String asset;
  final String icon;
  final String title;
  final String subtitle;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 210,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              semanticLabel: title,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .04),
                    Colors.black.withValues(alpha: .82),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .34),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: OutdoorAssetIcon(asset: icon, size: 38),
                  ),
                  const Spacer(),
                  Text(
                    meta.split(' · ').first,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  splashColor: Colors.white24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportedTrackCard extends StatelessWidget {
  const _ImportedTrackCard({required this.track, required this.onOpen});

  final ImportedTrack track;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle_outline),
                SizedBox(width: 8),
                Text(
                  'GPX importado y guardado',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(track.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onOpen,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Ver ruta'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                Text('${(track.distanceMeters / 1000).toStringAsFixed(1)} km'),
                Text('+${track.ascentMeters.toStringAsFixed(0)} m'),
                Text('-${track.descentMeters.toStringAsFixed(0)} m'),
                Text('${track.points.length} puntos'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
