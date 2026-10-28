import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../app/eo_components.dart';
import '../../core/location/location_controller.dart';
import '../../core/location/route_recorder.dart';
import '../menu/menu_sheet.dart';
import 'maplibre_map_viewport.dart';

class MapLibreMapPage extends ConsumerStatefulWidget {
  const MapLibreMapPage({super.key});

  @override
  ConsumerState<MapLibreMapPage> createState() => _MapLibreMapPageState();
}

class _MapLibreMapPageState extends ConsumerState<MapLibreMapPage> {
  ml.MapLibreMapController? _controller;
  bool _locating = false;

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EOColors.night,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => const MenuSheet(),
    );
  }

  Future<void> _useLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      await ref.read(locationControllerProvider.notifier).locate();
      if (!mounted) return;
      final location = ref.read(locationControllerProvider);
      final position = location.position;
      if (position == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(location.message)));
        return;
      }
      await _controller?.animateCamera(
        ml.CameraUpdate.newCameraPosition(
          ml.CameraPosition(
            target: ml.LatLng(position.latitude, position.longitude),
            zoom: 16,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo obtener la ubicación: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _recenter() async {
    final position = ref.read(locationControllerProvider).position;
    if (position == null) {
      await _useLocation();
      return;
    }
    await _controller?.animateCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: ml.LatLng(position.latitude, position.longitude),
          zoom: 15,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationControllerProvider);
    final recording = ref.watch(routeRecorderProvider);
    final recorder = ref.read(routeRecorderProvider.notifier);
    final position = location.position;
    return Scaffold(
      backgroundColor: EOColors.night,
      appBar: EOAppBar(
        title: 'Mapa',
        actions: [
          EOIconButton(
            icon: Icons.center_focus_strong,
            tooltip: 'Centrar mapa',
            onPressed: _recenter,
            size: 44,
          ),
          const SizedBox(width: 4),
          EOIconButton(
            icon: Icons.menu,
            tooltip: 'Menú',
            onPressed: _openMenu,
            size: 44,
          ),
          const SizedBox(width: 4),
          EOIconButton(
            icon: Icons.download_outlined,
            tooltip: 'Mapas offline',
            onPressed: () => context.push('/offline'),
            size: 44,
          ),
          const SizedBox(width: 4),
          EOIconButton(
            icon: Icons.navigation_outlined,
            tooltip: 'Navegación GPS',
            onPressed: () => context.push('/navigation'),
            size: 44,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapLibreMapViewport(
              initialCenter: position == null
                  ? const ml.LatLng(40.2, -3.7)
                  : ml.LatLng(position.latitude, position.longitude),
              initialZoom: position == null ? 5.5 : 15,
              currentPosition: position == null
                  ? null
                  : ml.LatLng(position.latitude, position.longitude),
              onMapCreated: (controller) => _controller = controller,
            ),
          ),
          Positioned(
            left: EOSpacing.lg,
            right: EOSpacing.lg,
            top: EOSpacing.lg,
            child: EOMapPanel(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: EOSpacing.md,
                vertical: EOSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(Icons.map_outlined, color: EOColors.green),
                  const SizedBox(width: EOSpacing.sm),
                  Expanded(
                    child: Text(
                      recording.isRecording
                          ? 'Grabando ${(recording.distanceMeters / 1000).toStringAsFixed(2)} km'
                          : location.message,
                      style: EOTextStyles.body,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: EOSpacing.lg,
            bottom: EOSpacing.lg,
            child: EOMapPanel(
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal: EOSpacing.sm,
                vertical: 5,
              ),
              blur: false,
              child: Text(
                '© OpenStreetMap contributors',
                style: EOTextStyles.label,
              ),
            ),
          ),
          Positioned(
            right: EOSpacing.lg,
            bottom: 88,
            child: EOIconButton(
              icon: recording.isRecording
                  ? Icons.stop
                  : Icons.fiber_manual_record,
              tooltip: recording.isRecording
                  ? 'Detener grabación'
                  : 'Grabar ruta',
              selected: recording.isRecording,
              danger: recording.isRecording,
              onPressed: () async {
                try {
                  if (recording.isRecording) {
                    await recorder.stop();
                  } else {
                    await recorder.start();
                  }
                } on Object catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error.toString())));
                }
              },
            ),
          ),
          Positioned(
            right: EOSpacing.lg,
            bottom: 148,
            child: EOIconButton(
              icon: Icons.navigation_outlined,
              tooltip: 'Navegación GPS',
              onPressed: () => context.push('/navigation'),
            ),
          ),
          Positioned(
            right: EOSpacing.lg,
            bottom: EOSpacing.lg,
            child: EOIconButton(
              icon: Icons.my_location,
              tooltip: 'Usar mi ubicación',
              selected: position != null,
              onPressed: _locating ? null : _useLocation,
            ),
          ),
        ],
      ),
    );
  }
}
