import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../app/eo_components.dart';
import '../../core/maps/maplibre_style_loader.dart';

/// Reusable MapLibre surface shared by the map, planner and route detail.
class MapLibreMapViewport extends StatefulWidget {
  const MapLibreMapViewport({
    super.key,
    this.initialCenter = const ml.LatLng(40.4168, -3.7038),
    this.initialZoom = 7,
    this.routePoints = const <ml.LatLng>[],
    this.currentPosition,
    this.destination,
    this.onTap,
    this.onMapCreated,
  });

  final ml.LatLng initialCenter;
  final double initialZoom;
  final List<ml.LatLng> routePoints;
  final ml.LatLng? currentPosition;
  final ml.LatLng? destination;
  final ValueChanged<ml.LatLng>? onTap;
  final ValueChanged<ml.MapLibreMapController>? onMapCreated;

  @override
  State<MapLibreMapViewport> createState() => _MapLibreMapViewportState();
}

class _MapLibreMapViewportState extends State<MapLibreMapViewport> {
  late Future<String> _styleFuture;
  ml.MapLibreMapController? _controller;
  bool _styleLoaded = false;
  bool _updatingAnnotations = false;
  ml.Circle? _locationCircle;
  ml.Circle? _destinationCircle;
  ml.Line? _routeLine;

  @override
  void initState() {
    super.initState();
    _styleFuture = loadMapLibreStyle();
  }

  @override
  void didUpdateWidget(covariant MapLibreMapViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPosition != widget.currentPosition ||
        oldWidget.destination != widget.destination ||
        !_samePoints(oldWidget.routePoints, widget.routePoints)) {
      unawaited(_syncAnnotations());
    }
  }

  bool _samePoints(List<ml.LatLng> left, List<ml.LatLng> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  void _onMapCreated(ml.MapLibreMapController controller) {
    _controller = controller;
    widget.onMapCreated?.call(controller);
  }

  void _onStyleLoaded() {
    if (!mounted) return;
    debugPrint('EO_MAPLIBRE_STYLE_LOADED');
    setState(() => _styleLoaded = true);
    unawaited(_syncAnnotations());
  }

  Future<void> _syncAnnotations() async {
    final controller = _controller;
    if (!_styleLoaded || controller == null || _updatingAnnotations) return;
    _updatingAnnotations = true;
    try {
      _locationCircle = await _syncCircle(
        controller,
        current: _locationCircle,
        position: widget.currentPosition,
        color: '#1976D2',
      );
      _destinationCircle = await _syncCircle(
        controller,
        current: _destinationCircle,
        position: widget.destination,
        color: '#F28C28',
      );
      _routeLine = await _syncLine(controller, _routeLine, widget.routePoints);
    } catch (error, stackTrace) {
      debugPrint('EO_MAP annotations: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _updatingAnnotations = false;
    }
  }

  Future<ml.Circle?> _syncCircle(
    ml.MapLibreMapController controller, {
    required ml.Circle? current,
    required ml.LatLng? position,
    required String color,
  }) async {
    if (position == null) {
      if (current != null) await controller.removeCircle(current);
      return null;
    }
    final options = ml.CircleOptions(
      geometry: position,
      circleRadius: 8,
      circleColor: color,
      circleStrokeColor: '#FFFFFF',
      circleStrokeWidth: 2,
    );
    if (current == null) return controller.addCircle(options);
    await controller.updateCircle(current, options);
    return current;
  }

  Future<ml.Line?> _syncLine(
    ml.MapLibreMapController controller,
    ml.Line? current,
    List<ml.LatLng> points,
  ) async {
    if (points.length < 2) {
      if (current != null) await controller.removeLine(current);
      return null;
    }
    final options = ml.LineOptions(
      geometry: points,
      lineColor: '#4E9A66',
      lineWidth: 5,
      lineJoin: 'round',
    );
    if (current == null) return controller.addLine(options);
    await controller.updateLine(current, options);
    return current;
  }

  void _retry() {
    setState(() {
      _styleLoaded = false;
      _styleFuture = loadMapLibreStyle();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _styleFuture,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(EOSpacing.xxxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_outlined, size: 48),
                const SizedBox(height: EOSpacing.md),
                const Text(
                  'No se pudo cargar el mapa',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EOSpacing.sm),
                Text('${snapshot.error}', textAlign: TextAlign.center),
                const SizedBox(height: EOSpacing.md),
                EOButton(
                  label: 'Reintentar',
                  icon: Icons.refresh,
                  onPressed: _retry,
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      return Stack(
        children: [
          Positioned.fill(
            child: ml.MapLibreMap(
              initialCameraPosition: ml.CameraPosition(
                target: widget.initialCenter,
                zoom: widget.initialZoom,
              ),
              styleString: snapshot.data!,
              onMapCreated: _onMapCreated,
              onStyleLoadedCallback: _onStyleLoaded,
              onMapClick: widget.onTap == null
                  ? null
                  : (_, point) => widget.onTap!(point),
              compassEnabled: true,
              rotateGesturesEnabled: true,
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
              tiltGesturesEnabled: false,
              myLocationEnabled: false,
            ),
          ),
          if (!_styleLoaded)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      );
    },
  );
}
