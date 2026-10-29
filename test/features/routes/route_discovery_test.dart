import 'package:flutter_test/flutter_test.dart';

class _RouteDiscoveryItem {
  const _RouteDiscoveryItem({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.activity,
  });

  final String title;
  final String subtitle;
  final String meta;
  final String activity;

  bool matches(String query, String selectedActivity) {
    final normalizedQuery = query.trim().toLowerCase();
    final matchesQuery = normalizedQuery.isEmpty ||
        title.toLowerCase().contains(normalizedQuery) ||
        subtitle.toLowerCase().contains(normalizedQuery) ||
        meta.toLowerCase().contains(normalizedQuery) ||
        activity.toLowerCase().contains(normalizedQuery);
    final matchesActivity =
        selectedActivity == 'Todas' || activity == selectedActivity;
    return matchesQuery && matchesActivity;
  }
}

void main() {
  const routes = <_RouteDiscoveryItem>[
    _RouteDiscoveryItem(
      title: 'Lagos de Covadonga',
      subtitle: 'Picos de Europa · Asturias',
      meta: 'MODERADA · 12,4 km',
      activity: 'Senderismo',
    ),
    _RouteDiscoveryItem(
      title: 'Mulhacén · Sierra Nevada',
      subtitle: 'Granada · Andalucía',
      meta: 'DIFÍCIL · 18,7 km',
      activity: 'Senderismo',
    ),
    _RouteDiscoveryItem(
      title: 'Caminito del Rey',
      subtitle: 'Málaga · Andalucía',
      meta: 'FÁCIL · 8,3 km',
      activity: 'Senderismo',
    ),
  ];

  test('empty query and all activities preserve the catalogue', () {
    expect(
      routes.where((route) => route.matches('', 'Todas')).length,
      routes.length,
    );
  });

  test('query is case-insensitive and searches titles', () {
    final result = routes
        .where((route) => route.matches('cOvAdOnGa', 'Todas'))
        .toList();

    expect(result, hasLength(1));
    expect(result.single.title, 'Lagos de Covadonga');
  });

  test('query searches subtitle and metadata too', () {
    expect(
      routes.where((route) => route.matches('Andalucía', 'Todas')).length,
      2,
    );
    expect(
      routes.where((route) => route.matches('18,7 KM', 'Todas')).length,
      1,
    );
  });

  test('an unmatched activity returns no discovery items', () {
    expect(
      routes.where((route) => route.matches('', 'MTB')),
      isEmpty,
    );
  });

  test('search and activity filter are applied together', () {
    expect(
      routes.where((route) => route.matches('Granada', 'Senderismo')).length,
      1,
    );
    expect(
      routes.where((route) => route.matches('Granada', 'MTB')),
      isEmpty,
    );
  });
}
