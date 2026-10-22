enum RouteReadiness {
  apto,
  precaucion,
  noRecomendado,
}

/// Evidence used by the route-readiness decision. Null means that the source
/// has not supplied a value; it must never be interpreted as "safe".
class RouteReadinessInput {
  const RouteReadinessInput({
    this.routeClosed = false,
    this.officialEvacuation = false,
    this.criticalOfficialAlert = false,
    this.severeWeather = false,
    this.highExposure = false,
    this.highIsolation = false,
    this.petRestricted = false,
    this.petHeatRisk = false,
    this.staleData = false,
    this.missingCriticalData = false,
    this.weatherRiskLevel = 0,
    this.hazardRiskLevel = 0,
    this.routeRiskLevel = 0,
    this.poorVisibility = false,
    this.extremeHeatOrCold = false,
    this.petCompatible = true,
  });

  final bool routeClosed;
  final bool officialEvacuation;
  final bool criticalOfficialAlert;
  final bool severeWeather;
  final bool highExposure;
  final bool highIsolation;
  final bool petRestricted;
  final bool petHeatRisk;
  final bool staleData;
  final bool missingCriticalData;
  final int weatherRiskLevel;
  final int hazardRiskLevel;
  final int routeRiskLevel;
  final bool poorVisibility;
  final bool extremeHeatOrCold;
  final bool petCompatible;

  bool get isValid =>
      weatherRiskLevel >= 0 && weatherRiskLevel <= 3 &&
      hazardRiskLevel >= 0 && hazardRiskLevel <= 3 &&
      routeRiskLevel >= 0 && routeRiskLevel <= 3;
}

class RouteReadinessResult {
  const RouteReadinessResult({
    required this.status,
    required this.reasons,
  });

  final RouteReadiness status;
  final List<String> reasons;
}

/// Deterministic product policy for "¿PUEDO HACER ESTA RUTA HOY?".
///
/// This layer only evaluates supplied evidence. It does not fetch weather,
/// alerts or closures and therefore cannot fabricate a safety assessment.
class RouteReadinessEngine {
  const RouteReadinessEngine();

  RouteReadinessResult evaluate(RouteReadinessInput input) {
    if (!input.isValid) {
      throw ArgumentError.value(input, 'input', 'Niveles de riesgo invalidos.');
    }

    final reasons = <String>[];

    if (input.routeClosed) {
      reasons.add('La ruta figura como cerrada.');
    }
    if (input.officialEvacuation) {
      reasons.add('Existe una evacuacion oficial activa.');
    }
    if (input.criticalOfficialAlert) {
      reasons.add('Existe una alerta oficial critica aplicable a la zona.');
    }

    if (reasons.isNotEmpty) {
      return RouteReadinessResult(
        status: RouteReadiness.noRecomendado,
        reasons: List.unmodifiable(reasons),
      );
    }

    if (input.weatherRiskLevel >= 1) {
      reasons.add('La meteorologia indica un nivel de riesgo relevante.');
    }
    if (input.hazardRiskLevel >= 1) {
      reasons.add('Hay peligros que requieren precaucion.');
    }
    if (input.routeRiskLevel >= 1) {
      reasons.add('La ruta presenta factores de riesgo.');
    }
    if (input.severeWeather) {
      reasons.add('Se han identificado condiciones meteorologicas adversas.');
    }
    if (input.poorVisibility) {
      reasons.add('La visibilidad es desfavorable.');
    }
    if (input.extremeHeatOrCold) {
      reasons.add('Se han detectado condiciones termicas extremas.');
    }
    if (input.highExposure) {
      reasons.add('La ruta presenta exposicion elevada.');
    }
    if (input.highIsolation) {
      reasons.add('La ruta presenta aislamiento elevado.');
    }
    if (input.petRestricted || !input.petCompatible) {
      reasons.add('La ruta puede no ser compatible con la mascota seleccionada.');
    }
    if (input.petHeatRisk) {
      reasons.add('Las condiciones termicas elevan el riesgo para mascotas.');
    }
    if (input.staleData) {
      reasons.add('Parte de la informacion disponible esta desactualizada.');
    }
    if (input.missingCriticalData) {
      reasons.add('Faltan datos criticos para una evaluacion completa.');
    }

    final criticalConditions =
        input.hazardRiskLevel >= 3 ||
        input.weatherRiskLevel >= 3 ||
        input.routeRiskLevel >= 3 ||
        (input.severeWeather && input.routeRiskLevel >= 2) ||
        (input.severeWeather && input.hazardRiskLevel >= 2);

    if (criticalConditions) {
      return RouteReadinessResult(
        status: RouteReadiness.noRecomendado,
        reasons: List.unmodifiable(reasons),
      );
    }

    if (reasons.isNotEmpty) {
      return RouteReadinessResult(
        status: RouteReadiness.precaucion,
        reasons: List.unmodifiable(reasons),
      );
    }

    return const RouteReadinessResult(
      status: RouteReadiness.apto,
      reasons: ['No se han detectado impedimentos con los datos disponibles.'],
    );
  }
}
