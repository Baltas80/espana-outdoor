import '../../core/contracts/source_gateway.dart';
import '../../core/weather/weather_models.dart';
import '../../core/weather/weather_service.dart';

/// Weather adapter that consumes the normalized first-party gateway rather
/// than exposing AEMET credentials to the mobile application.
final class GatewayWeatherService implements WeatherService {
  GatewayWeatherService({
    required SourceGateway gateway,
    this.sourceId = 'aemet-weather',
  }) : _gateway = gateway;

  final SourceGateway _gateway;
  final String sourceId;

  @override
  Future<WeatherForecast> dailyMunicipalityForecast(
    String municipalityCode,
  ) async {
    final dataSnapshot = await _gateway.fetch(
      sourceId,
      parameters: {'municipalityCode': municipalityCode},
    );

    final days = <WeatherDay>[];
    for (final record in dataSnapshot.data) {
      final dateText = record['date']?.toString();
      final date = dateText == null ? null : DateTime.tryParse(dateText);
      if (date == null) continue;

      days.add(
        WeatherDay(
          date: date,
          condition: _condition(record['condition']?.toString()),
          minTemperatureC: _double(record['min']),
          maxTemperatureC: _double(record['max']),
          precipitationProbabilityPercent:
              _int(record['precipitationProbability']),
          precipitationMm: _double(record['precipitationMm']),
          windSpeedKmh: _double(record['windSpeed']),
          windDirection: record['windDirection']?.toString(),
        ),
      );
    }

    return WeatherForecast(
      days: List.unmodifiable(days),
      source: dataSnapshot.provenance.source,
      fetchedAt: dataSnapshot.freshness.fetchedAt,
      sourceUpdatedAt: dataSnapshot.provenance.observedAt,
      freshnessStatus: _freshness(dataSnapshot.freshness.status),
    );
  }

  static WeatherFreshnessStatus _freshness(String value) =>
      WeatherFreshnessStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => WeatherFreshnessStatus.unknown,
      );

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    final text = value?.toString() ?? '';
    return double.tryParse(text.replaceAll(',', '.'));
  }

  static int? _int(Object? value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  static WeatherCondition _condition(String? value) {
    return WeatherCondition.values.firstWhere(
      (item) => item.name == value,
      orElse: () => WeatherCondition.unknown,
    );
  }
}
