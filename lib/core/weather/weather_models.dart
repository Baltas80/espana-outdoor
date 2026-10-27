/// Domain models for weather data.
///
/// The models deliberately keep provenance and freshness alongside values so
/// safety decisions never lose the source or timestamp that produced them.
library;

enum WeatherFreshnessStatus { current, aging, stale, unavailable, unknown }

enum WeatherCondition {
  clear,
  partlyCloudy,
  cloudy,
  rain,
  storm,
  snow,
  fog,
  unknown,
}

class WeatherDay {
  const WeatherDay({
    required this.date,
    required this.condition,
    this.minTemperatureC,
    this.maxTemperatureC,
    this.precipitationProbabilityPercent,
    this.precipitationMm,
    this.windSpeedKmh,
    this.windDirection,
  });

  final DateTime date;
  final WeatherCondition condition;
  final double? minTemperatureC;
  final double? maxTemperatureC;
  final int? precipitationProbabilityPercent;
  final double? precipitationMm;
  final double? windSpeedKmh;
  final String? windDirection;
}

class WeatherForecast {
  const WeatherForecast({
    required this.days,
    required this.source,
    required this.fetchedAt,
    this.sourceUpdatedAt,
    this.freshnessStatus = WeatherFreshnessStatus.unknown,
  });

  final List<WeatherDay> days;
  final String source;
  final DateTime fetchedAt;
  final DateTime? sourceUpdatedAt;
  final WeatherFreshnessStatus freshnessStatus;

  bool get isEmpty => days.isEmpty;
}
