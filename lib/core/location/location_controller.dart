import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

final locationControllerProvider =
    NotifierProvider<LocationController, LocationState>(LocationController.new);

class LocationState {
  const LocationState({
    this.position,
    this.message = 'Pulsa el botón para usar tu ubicación.',
    this.isTracking = false,
    this.isStale = false,
  });

  final Position? position;
  final String message;

  /// True while a live GPS position stream is being consumed. When false the
  /// app is not keeping the radio on for background updates (battery-safe).
  final bool isTracking;

  /// True when tracking was interrupted but the last known position is still
  /// shown. The UI must present it as outdated, never as the live fix.
  final bool isStale;

  LocationState copyWith({
    Object? position = _unset,
    String? message,
    bool? isTracking,
    bool? isStale,
  }) =>
      LocationState(
        position: identical(position, _unset)
            ? this.position
            : position as Position?,
        message: message ?? this.message,
        isTracking: isTracking ?? this.isTracking,
        isStale: isStale ?? this.isStale,
      );

  static const _unset = Object();
}

class LocationController extends Notifier<LocationState> {
  StreamSubscription<Position>? _subscription;
  bool _disposed = false;

  @override
  LocationState build() {
    ref.onDispose(() {
      _disposed = true;
      final subscription = _subscription;
      if (subscription != null) unawaited(subscription.cancel());
    });
    return const LocationState();
  }

  Future<void> locate() async {
    state = state.copyWith(message: 'Obteniendo ubicación…');
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await stopTracking();
        state = state.copyWith(
          message: 'Activa la ubicación del dispositivo para continuar.',
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await stopTracking();
        state = state.copyWith(
          message: 'Permiso de ubicación no disponible.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));

      state = state.copyWith(
        position: position,
        isStale: false,
        message: 'Seguimiento GPS activo.',
      );
      _startTracking();
    } catch (_) {
      // A failed refresh must not silently keep presenting the previous fix
      // as if it were current.
      state = state.copyWith(
        isStale: state.position != null,
        message: state.position == null
            ? 'No se ha podido obtener la ubicación. Comprueba el GPS e inténtalo de nuevo.'
            : 'No se ha podido actualizar la ubicación; se muestra la última conocida.',
      );
    }
  }

  /// Stops the GPS position stream so the radio is not kept alive when the
  /// user is not navigating (battery). The last known position is retained
  /// but flagged as stale.
  Future<void> stopTracking() async {
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) await subscription.cancel();
    if (_disposed) return;
    state = state.copyWith(
      isTracking: false,
      isStale: state.position != null,
      message: state.position == null
          ? 'Pulsa el botón para usar tu ubicación.'
          : 'Seguimiento detenido. Última posición conocida.',
    );
  }

  void _startTracking() {
    _subscription?.cancel();
    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (position) {
        if (_disposed) return;
        state = state.copyWith(
          position: position,
          isTracking: true,
          isStale: false,
          message: 'Seguimiento GPS activo.',
        );
      },
      onError: (Object _) {
        if (_disposed) return;
        unawaited(_subscription?.cancel());
        _subscription = null;
        state = state.copyWith(
          isTracking: false,
          isStale: state.position != null,
          message: 'Seguimiento GPS interrumpido.',
        );
      },
      onDone: () {
        if (_disposed) return;
        _subscription = null;
        state = state.copyWith(
          isTracking: false,
          isStale: state.position != null,
          message: 'Seguimiento GPS interrumpido.',
        );
      },
      cancelOnError: true,
    );
    state = state.copyWith(isTracking: true);
  }
}
