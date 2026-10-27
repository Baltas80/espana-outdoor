import 'package:flutter_test/flutter_test.dart';

import 'package:espana_outdoors/core/contracts/source_gateway.dart';
import 'package:espana_outdoors/infrastructure/sources/gateway_weather_service.dart';

void main() {
  test('normalizes gateway forecast records', () async {
    final gateway = _FakeGateway();

    final service = GatewayWeatherService(gateway: gateway);
    final forecast =
        await service.dailyMunicipalityForecast('03099');

    expect(forecast.days, hasLength(1));
    expect(forecast.days.single.condition.name, 'clear');
    expect(forecast.days.single.maxTemperatureC, 27.5);
    expect(forecast.source, 'AEMET OpenData');
    expect(forecast.fetchedAt, DateTime.utc(2026, 9, 23, 12));
    expect(forecast.sourceUpdatedAt, DateTime.utc(2026, 9, 23, 11));
    expect(forecast.freshnessStatus, WeatherFreshnessStatus.stale);
  });
}

final class _FakeGateway implements SourceGateway {
  @override
  Future<SourceSnapshot> health(String sourceId) async {
    return SourceSnapshot(
      sourceId: sourceId,
      kind: SourceKind.official,
      status: SourceStatus.healthy,
      observedAt: DateTime.utc(2026, 9, 23, 12),
      expiresAt: DateTime.utc(2026, 9, 23, 13),
      attribution: 'AEMET OpenData',
    );
  }

  @override
  Future<SourceDataSnapshot> fetch(
    String sourceId, {
    Map<String, Object?> parameters = const {},
  }) async {
    expect(parameters['municipalityCode'], '03099');
    return SourceDataSnapshot(
      data: [
        {
          'date': '2026-09-23',
          'condition': 'clear',
          'min': 13.0,
          'max': 27.5,
          'precipitationProbability': 0,
          'precipitationMm': 0,
          'windSpeed': 15,
          'windDirection': 'NE',
        },
      ],
      provenance: SourceProvenance(
        source: 'AEMET OpenData',
        licenseUrl: 'https://example.test/license',
        observedAt: DateTime.utc(2026, 9, 23, 11),
      ),
      freshness: SourceFreshness(
        status: 'stale',
        fetchedAt: DateTime.utc(2026, 9, 23, 12),
      ),
    );
  }
}
