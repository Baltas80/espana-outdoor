import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const mapboxStyleUri = 'mapbox://styles/mapbox/outdoors-v12';
const mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

/// Shared Mapbox surface for the main map, route planner and GPX detail.
class MapboxMapViewport extends StatefulWidget {
  const MapboxMapViewport({
    super.key,
    required this.initialCenter,
    required this.initialZoom,
    this.routePoints = const <Position>[],
    this.currentPosition,
    this.destination,
    this.onTap,
    this.onMapCreated,
  });

  final Position initialCenter;
  final double initialZoom;
  final List<Position> routePoints;
  final Position? currentPosition;
  final Position? destination;
  final ValueChanged<Position>? onTap;
  final ValueChanged<MapboxMap>? onMapCreated;

  @override
  State<MapboxMapViewport> createState() => _MapboxMapViewportState();
}

class _MapboxMapViewportState extends State<MapboxMapViewport> {
  MapboxMap? _map;
  PolylineAnnotationManager? _lineManager;
  CircleAnnotationManager? _circleManager;
  bool _annotationsReady = false;

  @override
  void didUpdateWidget(covariant MapboxMapViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_annotationsReady &&
        (oldWidget.routePoints != widget.routePoints ||
         oldWidget.currentPosition != widget.currentPosition ||
         oldWidget.destination != widget.destination)) {
      _syncAnnotations();
    }
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    widget.onMapCreated?.call(map);
    map.addInteraction(
      TapInteraction.onMap((context) {
        widget.onTap?.call(context.point.coordinates);
      }),
    );
    try {
      _lineManager = await map.annotations.createPolylineAnnotationManager();
      _circleManager = await map.annotations.createCircleAnnotationManager();
      _annotationsReady = true;
      await _syncAnnotations();
    } catch (error) {
      debugPrint('Mapbox annotations unavailable: $error');
    }
  }

  Future<void> _syncAnnotations() async {
    final lines = _lineManager;
    final circles = _circleManager;
    if (!_annotationsReady || lines == null || circles == null) return;
    try {
      await lines.deleteAll();
      await circles.deleteAll();
      if (widget.routePoints.length >= 2) {
        await lines.create(
          PolylineAnnotationOptions(
            geometry: LineString(coordinates: widget.routePoints),
            lineColor: const Color(0xFF38B66A).toARGB32(),
            lineWidth: 4,
          ),
        );
      }
      final markers = <CircleAnnotationOptions>[];
      final current = widget.currentPosition;
      if (current != null) {
        markers.add(CircleAnnotationOptions(
          geometry: Point(coordinates: current),
          circleColor: const Color(0xFF2D8CFF).toARGB32(),
          circleRadius: 7,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2,
        ));
      }
      final destination = widget.destination;
      if (destination != null) {
        markers.add(CircleAnnotationOptions(
          geometry: Point(coordinates: destination),
          circleColor: const Color(0xFFE84A4A).toARGB32(),
          circleRadius: 8,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2,
        ));
      }
      if (markers.isNotEmpty) await circles.createMulti(markers);
    } catch (error) {
      debugPrint('Mapbox route overlay update failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (mapboxAccessToken.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Mapa no disponible: falta MAPBOX_ACCESS_TOKEN en esta compilación.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return MapWidget(
      key: const ValueKey('espana-outdoor-mapbox-shared-viewport'),
      styleUri: mapboxStyleUri,
      viewport: CameraViewportState(
        center: Point(coordinates: widget.initialCenter),
        zoom: widget.initialZoom,
        bearing: 0,
        pitch: 0,
      ),
      onMapCreated: _onMapCreated,
    );
  }
}
