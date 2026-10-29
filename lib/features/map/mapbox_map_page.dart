import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../app/eo_components.dart';
import '../../core/location/location_controller.dart';
import '../../core/location/route_recorder.dart';
import '../menu/menu_sheet.dart';
import 'mapbox_map_viewport.dart';

class MapboxMapPage extends ConsumerStatefulWidget {
  const MapboxMapPage({super.key});

  @override
  ConsumerState<MapboxMapPage> createState() => _MapboxMapPageState();
}

class _MapboxMapPageState extends ConsumerState<MapboxMapPage> {
  MapboxMap? _controller;
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
      await _controller?.easeTo(
        CameraOptions(
          center: Point(coordinates: Position(position.longitude, position.latitude)),
          zoom: 16,
        ), MapAnimationOptions(duration: 500),
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
    await _controller?.easeTo(
      CameraOptions(
        center: Point(coordinates: Position(position.longitude, position.latitude)),
        zoom: 15,
      ), MapAnimationOptions(duration: 500),
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
            child: MapboxMapViewport(
              initialCenter: position == null
                  ? Position(-4.7794, 37.8882)
                  : Position(position.longitude, position.latitude),
              initialZoom: position == null ? 12 : 15,
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
                '© Mapbox · © OpenStreetMap contributors',
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
