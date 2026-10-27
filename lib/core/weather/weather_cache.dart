import 'dart:convert';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'weather_models.dart';

/// Small durable cache for weather responses. Cached data must retain source
/// and timestamps; consumers decide whether stale data is safe to display.
class WeatherCache {
  WeatherCache({Box<String>? box})
      : _box = box ?? Hive.box<String>(_boxName);

  static const _boxName = 'weather_cache';
  final Box<String> _box;

  Future<void> put(String key, WeatherForecast forecast) async {
    await _box.put(key, jsonEncode(_encode(forecast)));
  }

  WeatherForecast? get(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      return _decode(Map<String, dynamic>.from(value));
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) => _box.delete(key);

  static Map<String, dynamic> _encode(WeatherForecast forecast) => {
        'source': forecast.source,
        'fetchedAt': forecast.fetchedAt.toIso8601String(),
        'sourceUpdatedAt': forecast.sourceUpdatedAt?.toIso8601String(),
        'freshnessStatus': forecast.freshnessStatus.name,
        'days': forecast.days
            .map((day) => {
                  'date': day.date.toIso8601String(),
                  'condition': day.condition.name,
                  'min': day.minTemperatureC,
                  'max': day.maxTemperatureC,
                  'precipitationProbability':
                      day.precipitationProbabilityPercent,
                  'precipitationMm': day.precipitationMm,
                  'windSpeed': day.windSpeedKmh,
                  'windDirection': day.windDirection,
                })
            .toList(),
      };

  static WeatherForecast _decode(Map<String, dynamic> value) {
    final days = (value['days'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((raw) => WeatherDay(
              date: DateTime.parse(raw['date'] as String),
              condition: WeatherCondition.values.firstWhere(
                (item) => item.name == raw['condition'],
                orElse: () => WeatherCondition.unknown,
              ),
              minTemperatureC: (raw['min'] as num?)?.toDouble(),
              maxTemperatureC: (raw['max'] as num?)?.toDouble(),
              precipitationProbabilityPercent:
                  (raw['precipitationProbability'] as num?)?.toInt(),
              precipitationMm: (raw['precipitationMm'] as num?)?.toDouble(),
              windSpeedKmh: (raw['windSpeed'] as num?)?.toDouble(),
              windDirection: raw['windDirection'] as String?,
            ))
        .toList(growable: false);

    return WeatherForecast(
      days: days,
      source: value['source'] as String? ?? 'unknown',
      fetchedAt: DateTime.parse(value['fetchedAt'] as String),
      sourceUpdatedAt: value['sourceUpdatedAt'] == null
          ? null
          : DateTime.parse(value['sourceUpdatedAt'] as String),
      freshnessStatus: WeatherFreshnessStatus.values.firstWhere(
        (status) => status.name == value['freshnessStatus'],
        orElse: () => WeatherFreshnessStatus.unknown,
      ),
    );
  }
}
