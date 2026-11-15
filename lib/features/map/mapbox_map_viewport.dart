import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const mapboxStyleUri = 'mapbox://styles/mapbox/outdoors-v12';
const mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

String _mapboxFailureClass(String? message) {
  final value = (message ?? '').toLowerCase();
  final status = RegExp(
    r'\bhttp(?:\s+status\s+code)?\s*[:=]?\s*(\d{3})\b',
  ).firstMatch(value)?.group(1);
  if (status != null) return 'http_$status';
  if (RegExp(r'\b401\b|\b403\b|unauthori[sz]ed|forbidden').hasMatch(value)) {
    return 'authorization';
  }
  if (value.contains('certificate') || value.contains('ssl') || value.contains('tls')) {
    return 'tls';
  }
  if (value.contains('timeout') || value.contains('timed out')) return 'timeout';
  if (value.contains('unknownhost') || value.contains('dns') || value.contains('resolve host')) {
    return 'dns';
  }
  if (value.contains('connection') || value.contains('network')) return 'network';
  if (value.contains('not found')) return 'not_found';
  return message == null || message.isEmpty ? 'unknown' : 'other';
}

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
  bool _routeCameraFitted = false;
  bool _annotationsReady = false;
  bool _styleLoadedLogged = false;
  bool _mapLoadedLogged = false;
  bool _fullFrameLogged = false;
  bool _mapIdleLogged = false;
  int _partialFrameCount = 0;
  int _resourceSuccessCount = 0;
  int _resourceCancellationCount = 0;
  int _resourceLookupMissCount = 0;
  int _resourceFailureCount = 0;

  bool _sameRoutePoints(List<Position> first, List<Position> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index].lng != second[index].lng ||
          first[index].lat != second[index].lat) {
        return false;
      }
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant MapboxMapViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final routeChanged = !_sameRoutePoints(
      oldWidget.routePoints,
      widget.routePoints,
    );
    if (routeChanged) _routeCameraFitted = false;
    if (_annotationsReady &&
        (routeChanged ||
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
      await _fitRouteInView();
    } catch (error) {
      debugPrint('Mapbox route overlay update failed: $error');
    }
  }

  Future<void> _fitRouteInView() async {
    final map = _map;
    if (_routeCameraFitted || map == null || widget.routePoints.length < 2) {
      return;
    }
    _routeCameraFitted = true;
    try {
      final camera = await map.cameraForCoordinates(
        [
          for (final coordinate in widget.routePoints)
            Point(coordinates: coordinate),
        ],
        MbxEdgeInsets(top: 125, left: 36, bottom: 250, right: 36),
        0,
        0,
      );
      await map.easeTo(
        camera,
        MapAnimationOptions(duration: 650),
      );
    } catch (error) {
      _routeCameraFitted = false;
      debugPrint('Mapbox could not fit the complete route: $error');
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
      onStyleLoadedListener: (_) {
        if (_styleLoadedLogged) return;
        _styleLoadedLogged = true;
        debugPrint('MAPBOX_MAP_STYLE_LOADED');
      },
      onMapLoadedListener: (_) {
        if (_mapLoadedLogged) return;
        _mapLoadedLogged = true;
        debugPrint(
          'MAPBOX_MAP_LOADED partial_frames=$_partialFrameCount '
          'resource_successes=$_resourceSuccessCount '
          'resource_cancellations=$_resourceCancellationCount '
          'resource_lookup_misses=$_resourceLookupMissCount '
          'resource_failures=$_resourceFailureCount',
        );
      },
      onRenderFrameFinishedListener: (event) {
        if (event.renderMode == RenderMode.FULL) {
          if (_fullFrameLogged) return;
          _fullFrameLogged = true;
          debugPrint('MAPBOX_MAP_FULL_FRAME');
          return;
        }
        _partialFrameCount++;
        // Keep diagnostics bounded: partial frames can be emitted continuously
        // while network resources are missing or the camera is still changing.
        if (_partialFrameCount <= 3) {
          debugPrint(
            'MAPBOX_MAP_PARTIAL_FRAME count=$_partialFrameCount '
            'needs_repaint=${event.needsRepaint} '
            'placement_changed=${event.placementChanged}',
          );
        }
      },
      onMapIdleListener: (_) {
        if (_mapIdleLogged) return;
        _mapIdleLogged = true;
        debugPrint(
          'MAPBOX_MAP_IDLE partial_frames=$_partialFrameCount '
          'resource_successes=$_resourceSuccessCount '
          'resource_cancellations=$_resourceCancellationCount '
          'resource_lookup_misses=$_resourceLookupMissCount '
          'resource_failures=$_resourceFailureCount',
        );
      },
      onResourceRequestListener: (event) {
        final response = event.response;
        final error = response?.error;
        final kind = event.request.kind;
        final responseSource = response?.source.name ?? 'unknown';
        final dataSource = event.dataSource.name;

        // A cancelled cache/TileStore lookup is not itself a failed network
        // request. Keep it separate so diagnostics do not confuse expected
        // offline misses with failed HTTP resource loads.
        if (event.cancelled) {
          _resourceCancellationCount++;
          if (_resourceCancellationCount <= 20) {
            debugPrint(
              'MAPBOX_RESOURCE_CANCELLED kind=$kind '
              'data_source=$dataSource '
              'reason=${error?.reason ?? 'cancelled'} '
              'response_source=$responseSource '
              'size=${response?.size ?? 0}',
            );
          }
          return;
        }

        if (error != null) {
          // NOT_FOUND from the local cache/TileStore is a lookup miss, not a
          // failed map resource. READ_ONLY mode is expected to fall back to an
          // individual tile request when the pack has no matching tile.
          if (error.reason.name == 'NOT_FOUND' &&
              dataSource == 'DATABASE' &&
              (responseSource == 'CACHE' || responseSource == 'TILE_STORE')) {
            _resourceLookupMissCount++;
            if (_resourceLookupMissCount <= 20) {
              debugPrint(
                'MAPBOX_RESOURCE_LOOKUP_MISS kind=$kind '
                'data_source=$dataSource '
                'response_source=$responseSource',
              );
            }
            return;
          }
          _resourceFailureCount++;
          if (_resourceFailureCount <= 20) {
            // Never log request URLs or response messages: Mapbox URLs can
            // contain the public access token. The error class is sufficient.
            debugPrint(
              'MAPBOX_RESOURCE_FAILURE kind=$kind '
              'data_source=$dataSource '
              'reason=${error.reason} '
              'failure_class=${_mapboxFailureClass(error.message)} '
              'response_source=$responseSource '
              'size=${response?.size ?? 0}',
            );
          }
          return;
        }

        _resourceSuccessCount++;
        if (_resourceSuccessCount <= 20) {
          debugPrint(
            'MAPBOX_RESOURCE_OK kind=$kind '
            'data_source=$dataSource '
            'response_source=$responseSource '
            'size=${response?.size ?? 0}',
          );
        }
      },
      onMapLoadErrorListener: (event) {
        debugPrint(
          'MAPBOX_MAP_LOAD_ERROR type=${event.type} '
          'source=${event.sourceId ?? 'unknown'} '
          'failure_class=${_mapboxFailureClass(event.message)}',
        );
      },
    );
  }
}
