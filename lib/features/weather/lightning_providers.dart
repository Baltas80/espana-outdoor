import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/weather/lightning_distance.dart';

/// App-level state for the lightning-distance calculator.
///
/// Kept in Riverpod (instead of widget-local `setState`) so the result is
/// shared and testable independently of the UI tree. The selected delay in
/// seconds drives the computed distance through [lightningDistanceProvider].
class LightningDelayController extends Notifier<double?> {
  @override
  double? build() => null;

  /// Parses a raw user entry (accepts comma or dot decimals). Invalid or
  /// negative input clears the current selection.
  void submit(String raw) {
    final seconds = double.tryParse(raw.replaceAll(',', '.'));
    state = (seconds == null || seconds < 0) ? null : seconds;
  }
}

final lightningDelayProvider =
    NotifierProvider.autoDispose<LightningDelayController, double?>(
  LightningDelayController.new,
);

final lightningDistanceProvider = Provider.autoDispose<LightningDistance?>(
  (ref) {
    final seconds = ref.watch(lightningDelayProvider);
    if (seconds == null) return null;
    return LightningDistance.fromThunderDelay(seconds);
  },
);
