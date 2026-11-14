/// One editorial route shown in the discovery catalogue.
class RouteDiscoveryItem {
  const RouteDiscoveryItem({
    required this.asset,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.activity,
  });

  final String asset;
  final String icon;
  final String title;
  final String subtitle;
  final String meta;
  final String activity;

  bool matches({
    required String query,
    required String selectedActivity,
  }) {
    final normalizedQuery = _normalize(query);
    final searchableText = _normalize(
      '$title $subtitle $meta $activity',
    );
    final matchesQuery =
        normalizedQuery.isEmpty || searchableText.contains(normalizedQuery);
    final matchesActivity =
        selectedActivity == 'Todas' || activity == selectedActivity;
    return matchesQuery && matchesActivity;
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[áàäâ]'), 'a')
        .replaceAll(RegExp('[éèëê]'), 'e')
        .replaceAll(RegExp('[íìïî]'), 'i')
        .replaceAll(RegExp('[óòöô]'), 'o')
        .replaceAll(RegExp('[úùüû]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
