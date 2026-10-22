import 'package:espana_outdoors/core/safety/route_readiness_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = RouteReadinessEngine();

  test('returns apto when no relevant risk is present', () {
    final result = engine.evaluate(const RouteReadinessInput());

    expect(result.status, RouteReadiness.apto);
    expect(result.reasons, isNotEmpty);
  });

  test('official closure always overrides other factors', () {
    final result = engine.evaluate(
      const RouteReadinessInput(
        routeClosed: true,
        severeWeather: true,
      ),
    );

    expect(result.status, RouteReadiness.noRecomendado);
    expect(result.reasons, contains('La ruta figura como cerrada.'));
  });

  test('official emergency alert always overrides lower risk inputs', () {
    final result = engine.evaluate(
      const RouteReadinessInput(
        criticalOfficialAlert: true,
        routeRiskLevel: 1,
        weatherRiskLevel: 1,
        hazardRiskLevel: 1,
      ),
    );

    expect(result.status, RouteReadiness.noRecomendado);
  });

  test('critical hazard yields no recomendado', () {
    final result = engine.evaluate(
      const RouteReadinessInput(hazardRiskLevel: 3),
    );

    expect(result.status, RouteReadiness.noRecomendado);
  });

  test('combined severe weather and elevated route risk yields no recomendado', () {
    final result = engine.evaluate(
      const RouteReadinessInput(
        severeWeather: true,
        routeRiskLevel: 2,
      ),
    );

    expect(result.status, RouteReadiness.noRecomendado);
  });

  test('moderate weather risk yields precaucion with evidence', () {
    final result = engine.evaluate(
      const RouteReadinessInput(weatherRiskLevel: 1),
    );

    expect(result.status, RouteReadiness.precaucion);
    expect(result.reasons, isNotEmpty);
  });

  test('stale information never upgrades a route to apto', () {
    final result = engine.evaluate(
      const RouteReadinessInput(staleData: true),
    );

    expect(result.status, RouteReadiness.precaucion);
    expect(result.reasons, isNotEmpty);
  });

  test('invalid risk scores are rejected', () {
    expect(
      () => engine.evaluate(const RouteReadinessInput(routeRiskLevel: 4)),
      throwsArgumentError,
    );
  });
}
