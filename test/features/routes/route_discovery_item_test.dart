import 'package:flutter_test/flutter_test.dart';
import 'package:espana_outdoors/features/routes/route_discovery_item.dart';

void main() {
  const routes = <RouteDiscoveryItem>[
    RouteDiscoveryItem(
      asset: '',
      icon: '',
      title: 'Lagos de Covadonga',
      subtitle: 'Picos de Europa · Asturias',
      meta: 'MODERADA · 12,4 km · 650 m',
      activity: 'Senderismo',
    ),
    RouteDiscoveryItem(
      asset: '',
      icon: '',
      title: 'Ruta de prueba BTT',
      subtitle: 'Sierra de Córdoba · Andalucía',
      meta: 'DIFÍCIL · 24 km',
      activity: 'MTB',
    ),
    RouteDiscoveryItem(
      asset: '',
      icon: '',
      title: 'Ruta de cicloturismo',
      subtitle: 'Vía Verde · Jaén',
      meta: 'FÁCIL · 32 km',
      activity: 'Cicloturismo',
    ),
  ];

  test('empty or whitespace query preserves all activities', () {
    expect(
      routes.where(
        (route) => route.matches(
          query: '',
          selectedActivity: 'Todas',
        ),
      ),
      hasLength(3),
    );
    expect(
      routes.where(
        (route) => route.matches(
          query: '   ',
          selectedActivity: 'Todas',
        ),
      ),
      hasLength(3),
    );
  });

  test('search is case-insensitive and matches titles', () {
    final result = routes
        .where(
          (route) => route.matches(
            query: 'cOvAdOnGa',
            selectedActivity: 'Todas',
          ),
        )
        .toList();

    expect(result, hasLength(1));
    expect(result.single.title, 'Lagos de Covadonga');
  });

  test('search ignores Spanish diacritics', () {
    final result = routes
        .where(
          (route) => route.matches(
            query: 'andalucia',
            selectedActivity: 'Todas',
          ),
        )
        .toList();

    expect(result, hasLength(1));
    expect(result.single.activity, 'MTB');
  });

  test('search includes subtitle, metadata and activity', () {
    expect(
      routes.where(
        (route) => route.matches(
          query: 'Asturias',
          selectedActivity: 'Todas',
        ),
      ),
      hasLength(1),
    );
    expect(
      routes.where(
        (route) => route.matches(
          query: '24 KM',
          selectedActivity: 'Todas',
        ),
      ),
      hasLength(1),
    );
    expect(
      routes.where(
        (route) => route.matches(
          query: 'cicloturismo',
          selectedActivity: 'Todas',
        ),
      ),
      hasLength(1),
    );
  });

  test('activity filter selects only matching routes', () {
    expect(
      routes.where(
        (route) => route.matches(
          query: '',
          selectedActivity: 'Senderismo',
        ),
      ),
      hasLength(1),
    );
    expect(
      routes.where(
        (route) => route.matches(
          query: '',
          selectedActivity: 'MTB',
        ),
      ),
      hasLength(1),
    );
  });

  test('search and activity filter are combined', () {
    expect(
      routes.where(
        (route) => route.matches(
          query: 'Córdoba',
          selectedActivity: 'MTB',
        ),
      ),
      hasLength(1),
    );
    expect(
      routes.where(
        (route) => route.matches(
          query: 'Córdoba',
          selectedActivity: 'Senderismo',
        ),
      ),
      isEmpty,
    );
  });
}
