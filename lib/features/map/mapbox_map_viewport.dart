import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

const mapboxStyleUri = String.fromEnvironment(
  'MAPBOX_STYLE_URI',
  defaultValue: 'mapbox://styles/mapbox/outdoors-v12',
);
const mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
const mapboxSnapshotterDiagnosticsEnabled = bool.fromEnvironment(
  'MAPBOX_SNAPSHOTTER_DIAGNOSTICS',
  defaultValue: false,
);

/// Staging can compare Android platform-view composition without changing the
/// production default. v3 defaults to Hybrid Composition + SurfaceView; the
/// legacy-compatible comparison uses Virtual Display + TextureView.
const mapboxAndroidViewMode = String.fromEnvironment(
  'MAPBOX_ANDROID_VIEW_MODE',
  defaultValue: 'hybrid-surface',
);
const mapboxMapWidgetDiagnosticStyle = String.fromEnvironment(
  'MAPBOX_MAP_WIDGET_DIAGNOSTIC_STYLE',
  defaultValue: 'none',
);

const _mapWidgetDiagnosticAppEnvironment = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'production',
);

class MapboxAndroidViewConfiguration {
  const MapboxAndroidViewConfiguration({
    required this.textureView,
    required this.hostingMode,
  });

  final bool textureView;
  // ignore: experimental_member_use
  final AndroidPlatformViewHostingMode hostingMode;
}

MapboxAndroidViewConfiguration mapboxAndroidViewConfiguration(String mode) {
  switch (mode) {
    case 'hybrid-surface':
      return const MapboxAndroidViewConfiguration(
        textureView: false,
        // ignore: experimental_member_use
        hostingMode: AndroidPlatformViewHostingMode.HC,
      );
    case 'virtual-texture':
      return const MapboxAndroidViewConfiguration(
        textureView: true,
        // ignore: experimental_member_use
        hostingMode: AndroidPlatformViewHostingMode.VD,
      );
    default:
      throw ArgumentError.value(
        mode,
        'mode',
        'must be hybrid-surface or virtual-texture',
      );
  }
}

/// Keeps the online MapView pixel ratio aligned with the Android TileStore
/// descriptor used by offline downloads. MapOptions defaults to 1.0; the
/// offline descriptor is created from Android displayMetrics.density.
MapOptions mapboxMapOptionsForPixelRatio(double pixelRatio) {
  if (!pixelRatio.isFinite || pixelRatio <= 0) {
    throw ArgumentError.value(
      pixelRatio,
      'pixelRatio',
      'must be finite and greater than zero',
    );
  }
  return MapOptions(
    pixelRatio: pixelRatio,
    glyphsRasterizationOptions: GlyphsRasterizationOptions(
      rasterizationMode: GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
      fontFamily: 'sans-serif',
    ),
  );
}

String formatMapboxTileId({int? z, int? x, int? y}) {
  if (z == null || x == null || y == null) return '-';
  return '$z/$x/$y';
}

/// Normalizes Mapbox resource enum labels for stable diagnostic grouping.
String mapboxResourceDiagnosticKind(Object rawKind) {
  final value = rawKind.toString().trim();
  final separator = value.lastIndexOf('.');
  return (separator < 0 ? value : value.substring(separator + 1)).toUpperCase();
}

/// Reserve diagnostic capacity for vector tiles before noisy 3D model traffic.
/// Standard styles can emit many model requests before tile fallback completes.
int mapboxResourceDiagnosticLimit(Object rawKind) {
  switch (mapboxResourceDiagnosticKind(rawKind)) {
    case 'TILE':
      return 300;
    case 'MODEL':
      return 16;
    case 'STYLE':
      return 32;
    case 'SPRITE_IMAGE':
    case 'SPRITE_JSON':
      return 24;
    default:
      return 24;
  }
}

String sanitizeMapboxDiagnostic(String message) {
  return message
      .replaceAll(
        RegExp(r'access_token=[^&\s]+', caseSensitive: false),
        'access_token=[REDACTED]',
      )
      .replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
        'Bearer [REDACTED]',
      );
}

/// Returns a self-contained style used to test the native Mapbox renderer
/// without network, sprite, glyph or vector-tile dependencies.
String mapboxSnapshotterBaselineStyleJson() {
  return jsonEncode(<String, Object?>{
    'version': 8,
    'sources': <String, Object?>{},
    'layers': <Object?>[
      <String, Object?>{
        'id': 'espana-outdoor-diagnostic-background',
        'type': 'background',
        'paint': <String, Object?>{
          'background-color': '#d9e6c7',
        },
      },
    ],
  });
}

/// A minimal Mapbox Streets vector source with one visible road layer.
/// It separates vector-tile retrieval/decoding from the production style.
String mapboxSnapshotterVectorStyleJson() {
  return jsonEncode(<String, Object?>{
    'version': 8,
    'sources': <String, Object?>{
      'espana-outdoor-diagnostic-streets': <String, Object?>{
        'type': 'vector',
        'url': 'mapbox://mapbox.mapbox-streets-v8',
        'minzoom': 0,
        'maxzoom': 14,
      },
    },
    'layers': <Object?>[
      <String, Object?>{
        'id': 'espana-outdoor-diagnostic-background',
        'type': 'background',
        'paint': <String, Object?>{
          'background-color': '#d9e6c7',
        },
      },
      <String, Object?>{
        'id': 'espana-outdoor-diagnostic-roads',
        'type': 'line',
        'source': 'espana-outdoor-diagnostic-streets',
        'source-layer': 'road',
        'minzoom': 5,
        'paint': <String, Object?>{
          'line-color': '#c43c39',
          'line-width': 2.5,
        },
      },
    ],
  });
}

/// Optional local style applied to the live MapWidget only in Android staging.
/// This bypasses the remote style/import pipeline while retaining the same
/// Flutter PlatformView and native Mapbox renderer.
/// A self-contained GeoJSON line style for the live MapWidget diagnostic.
/// It isolates line-layer rendering from vector-tile retrieval and TileStore.
String mapboxMapWidgetGeoJsonStyleJson() {
  return jsonEncode(<String, Object?>{
    'version': 8,
    'sources': <String, Object?>{
      'espana-outdoor-diagnostic-geojson': <String, Object?>{
        'type': 'geojson',
        'data': <String, Object?>{
          'type': 'FeatureCollection',
          'features': <Object?>[
            <String, Object?>{
              'type': 'Feature',
              'properties': <String, Object?>{'kind': 'diagnostic-road-a'},
              'geometry': <String, Object?>{
                'type': 'LineString',
                'coordinates': <List<double>>[
                  <double>[-4.813, 37.871],
                  <double>[-4.799, 37.879],
                  <double>[-4.7794, 37.8882],
                  <double>[-4.762, 37.898],
                  <double>[-4.747, 37.906],
                ],
              },
            },
            <String, Object?>{
              'type': 'Feature',
              'properties': <String, Object?>{'kind': 'diagnostic-road-b'},
              'geometry': <String, Object?>{
                'type': 'LineString',
                'coordinates': <List<double>>[
                  <double>[-4.802, 37.904],
                  <double>[-4.790, 37.896],
                  <double>[-4.7794, 37.8882],
                  <double>[-4.768, 37.879],
                  <double>[-4.755, 37.870],
                ],
              },
            },
          ],
        },
      },
    },
    'layers': <Object?>[
      <String, Object?>{
        'id': 'espana-outdoor-diagnostic-background',
        'type': 'background',
        'paint': <String, Object?>{
          'background-color': '#d9e6c7',
        },
      },
      <String, Object?>{
        'id': 'espana-outdoor-diagnostic-geojson-lines',
        'type': 'line',
        'source': 'espana-outdoor-diagnostic-geojson',
        'paint': <String, Object?>{
          'line-color': '#c43c39',
          'line-width': 5.0,
          'line-opacity': 1.0,
        },
        'layout': <String, Object?>{
          'line-cap': 'round',
          'line-join': 'round',
        },
      },
    ],
  });
}

String? mapboxMapWidgetDiagnosticStyleJson(String variant) {
  switch (variant) {
    case 'none':
      return null;
    case 'baseline':
      return mapboxSnapshotterBaselineStyleJson();
    case 'vector':
      return mapboxSnapshotterVectorStyleJson();
    case 'geojson':
      return mapboxMapWidgetGeoJsonStyleJson();
    default:
      throw ArgumentError.value(
        variant,
        'variant',
        'must be none, baseline, vector or geojson',
      );
  }
}

String _safeMapboxStyleOrigin(Object? rawValue) {
  if (rawValue is! String) return 'none';
  final uri = Uri.tryParse(rawValue);
  if (uri == null) return 'invalid';
  if (uri.scheme.isEmpty) return 'relative';
  final host = uri.host.isEmpty ? '-' : uri.host;
  return uri.scheme + '://' + host;
}

/// Returns useful style structure without exposing full URLs or access tokens.
String mapboxStyleDiagnosticsJson(String rawStyleJson) {
  final decoded = jsonDecode(rawStyleJson);
  if (decoded is! Map) {
    throw const FormatException('Mapbox style JSON must be an object.');
  }

  final sourceSummaries = <Map<String, Object?>>[];
  final rawSources = decoded['sources'];
  if (rawSources is Map) {
    for (final entry in rawSources.entries) {
      final source = entry.value;
      if (source is! Map) continue;
      final tiles = source['tiles'];
      final tileOrigins = tiles is List
          ? tiles
              .whereType<String>()
              .map(_safeMapboxStyleOrigin)
              .toSet()
              .toList(growable: false)
          : const <String>[];
      sourceSummaries.add(<String, Object?>{
        'id': entry.key.toString(),
        'type': source['type'] ?? 'unknown',
        'url_origin': _safeMapboxStyleOrigin(source['url']),
        'tiles_count': tiles is List ? tiles.length : 0,
        'tile_origins': tileOrigins,
        'minzoom': source['minzoom'],
        'maxzoom': source['maxzoom'],
      });
    }
  }

  final typeCounts = <String, int>{};
  final backgrounds = <Map<String, Object?>>[];
  final firstLayers = <Map<String, Object?>>[];
  final rawLayers = decoded['layers'];
  if (rawLayers is List) {
    for (final rawLayer in rawLayers) {
      if (rawLayer is! Map) continue;
      final type = rawLayer['type']?.toString() ?? 'unknown';
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
      final layout = rawLayer['layout'] is Map
          ? rawLayer['layout'] as Map
          : const <String, Object?>{};
      final paint = rawLayer['paint'] is Map
          ? rawLayer['paint'] as Map
          : const <String, Object?>{};
      if (type == 'background') {
        backgrounds.add(<String, Object?>{
          'id': rawLayer['id'],
          'visibility': layout['visibility'] ?? 'visible',
          'color': paint['background-color'],
          'opacity': paint['background-opacity'] ?? 1,
        });
      }
      if (firstLayers.length < 12) {
        firstLayers.add(<String, Object?>{
          'id': rawLayer['id'],
          'type': type,
          'source': rawLayer['source'],
          'source_layer': rawLayer['source-layer'],
          'visibility': layout['visibility'] ?? 'visible',
        });
      }
    }
  }

  return jsonEncode(<String, Object?>{
    'source_count': sourceSummaries.length,
    'sources': sourceSummaries,
    'layer_type_counts': typeCounts,
    'background_layers': backgrounds,
    'first_layers': firstLayers,
    'glyphs_origin': _safeMapboxStyleOrigin(decoded['glyphs']),
    'sprite_origin': _safeMapboxStyleOrigin(decoded['sprite']),
  });
}

void _emitMapboxSnapshotterPng(String kind, List<int> png) {
  final prefix = kind == 'baseline'
      ? 'MAPBOX_SNAPSHOTTER_PNG'
      : 'MAPBOX_SNAPSHOTTER_VECTOR_PNG';
  final encoded = base64Encode(png);
  const chunkSize = 700;
  final totalChunks = (encoded.length + chunkSize - 1) ~/ chunkSize;
  final digest = sha256.convert(png).toString();
  debugPrint(
    prefix + '_BEGIN bytes=' + png.length.toString() +
        ' chunks=' + totalChunks.toString() + ' sha256=' + digest,
  );
  for (var index = 0; index < totalChunks; index++) {
    final start = index * chunkSize;
    final end = (start + chunkSize < encoded.length)
        ? start + chunkSize
        : encoded.length;
    debugPrint(
      prefix + '_CHUNK index=' + index.toString() +
          ' total=' + totalChunks.toString() +
          ' data=' + encoded.substring(start, end),
    );
  }
  debugPrint(prefix + '_END sha256=' + digest);
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
  int _sourceDataEventsLogged = 0;
  final Map<String, int> _resourceEventsLoggedByKind = <String, int>{};
  final Set<String> _resourceSuppressionLogged = <String>{};
  String? _lastRenderMode;
  bool _mapOptionsLogged = false;
  bool _snapshotterCaptureStarted = false;
  bool _mapWidgetDiagnosticStyleAttempted = false;

  static const _maxSourceDataEventsToLog = 250;

  void _logMapboxDiagnostic(String event, [String details = '']) {
    final suffix = details.isEmpty ? '' : ' $details';
    debugPrint('MAPBOX_DIAGNOSTIC event=$event$suffix');
  }

  Future<void> _inspectLoadedStyle() async {
    final map = _map;
    if (map == null) return;

    try {
      final rawStyleJson = await map.getStyleJSON();
      final decoded = jsonDecode(rawStyleJson);
      if (decoded is! Map) {
        throw const FormatException('Mapbox returned a non-object style JSON.');
      }

      final rawLayers = decoded['layers'];
      final layers = rawLayers is List
          ? rawLayers.whereType<Map>().toList(growable: false)
          : const <Map>[];
      final rawSources = decoded['sources'];
      final sourceCount = rawSources is Map ? rawSources.length : 0;
      final backgroundLayers = layers
          .where((layer) => layer['type'] == 'background')
          .toList(growable: false);
      final backgroundPaint = backgroundLayers.isEmpty
          ? 'none'
          : jsonEncode(backgroundLayers.first['paint'] ?? const <String, Object?>{});
      final size = await map.getSize();
      final camera = await map.getCameraState();
      final styleLoaded = await map.isStyleLoaded();
      final center = camera.center.coordinates;

      debugPrint(
        'MAPBOX_STYLE_INSPECTION style_loaded=$styleLoaded '
        'layer_count=${layers.length} source_count=$sourceCount '
        'background_layer_count=${backgroundLayers.length} '
        'background_paint=${sanitizeMapboxDiagnostic(backgroundPaint)} '
        'width=${size.width} height=${size.height} zoom=${camera.zoom} '
        'lng=${center.lng} lat=${center.lat}',
      );
      debugPrint('MAPBOX_STYLE_DIAGNOSTIC ' + mapboxStyleDiagnosticsJson(rawStyleJson));
      if (mapboxSnapshotterDiagnosticsEnabled) {
        unawaited(_captureSnapshotterDiagnostic(size: size, camera: camera));
      } else {
        _logMapboxDiagnostic(
          'SNAPSHOTTER_DIAGNOSTIC',
          'enabled=false reason=map_widget_isolation',
        );
      }
    } catch (error) {
      debugPrint(
        'MAPBOX_STYLE_INSPECTION failed=${sanitizeMapboxDiagnostic(error.toString())}',
      );
    }
  }

  /// Captures a second image through Mapbox's standalone native Snapshotter.
  ///
  /// This bypasses the live MapWidget/platform-view composition path. Comparing
  /// it with adb screencap distinguishes a native Mapbox rendering problem from
  /// a Flutter/Android view-composition problem. It runs only in Android staging.
  Future<void> _captureSnapshotterDiagnostic({
    required mapbox.Size size,
    required mapbox.CameraState camera,
  }) async {
    if (!mapboxSnapshotterDiagnosticsEnabled ||
        const String.fromEnvironment('APP_ENV') != 'staging' ||
        defaultTargetPlatform != TargetPlatform.android ||
        _snapshotterCaptureStarted) {
      return;
    }
    _snapshotterCaptureStarted = true;
    final stopwatch = Stopwatch()..start();
    void logSnapshotterStage(String stage, [String details = '']) {
      _logMapboxDiagnostic(
        'SNAPSHOTTER_STAGE',
        'stage=$stage elapsed_ms=${stopwatch.elapsedMilliseconds}'
            '${details.isEmpty ? '' : ' $details'}',
      );
    }

    mapbox.Snapshotter? snapshotter;
    Completer<void>? styleLoaded;
    var activeStyleLabel = 'baseline';
    try {
      logSnapshotterStage('create_started');
      snapshotter = await mapbox.Snapshotter.create(
        options: mapbox.MapSnapshotOptions(
          size: size,
          pixelRatio: 1.0,
          glyphsRasterizationOptions: mapbox.GlyphsRasterizationOptions(
            rasterizationMode:
                mapbox.GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
            fontFamily: 'sans-serif',
          ),
          showsLogo: false,
          showsAttribution: false,
        ),
        onStyleLoadedListener: (_) {
          logSnapshotterStage(activeStyleLabel + '_style_loaded_callback');
          final pending = styleLoaded;
          if (pending != null && !pending.isCompleted) pending.complete();
        },
        onMapLoadErrorListener: (event) {
          final details =
              'type=${event.type} message=${sanitizeMapboxDiagnostic(event.message)}';
          logSnapshotterStage('map_load_error', 'style=' + activeStyleLabel + ' ' + details);
          final pending = styleLoaded;
          if (pending != null && !pending.isCompleted) {
            pending.completeError(StateError(details));
          }
        },
        onStyleDataLoadedListener: (event) {
          logSnapshotterStage(
            'style_data_loaded',
            'style=' + activeStyleLabel + ' type=${event.type}',
          );
        },
        onStyleImageMissingListener: (event) {
          logSnapshotterStage(
            'style_image_missing',
            'style=' + activeStyleLabel + ' id=${event.id}',
          );
        },
      ).timeout(const Duration(seconds: 30));
      logSnapshotterStage('create_completed');

      Future<void> captureStyle({
        required String label,
        required String styleJson,
        required int captureTimeoutSeconds,
      }) async {
        activeStyleLabel = label;
        styleLoaded = Completer<void>();
        logSnapshotterStage(label + '_style_set_started');
        await snapshotter!
            .setStyleJSON(styleJson)
            .timeout(const Duration(seconds: 30));
        logSnapshotterStage(label + '_style_set_completed');
        await styleLoaded!.future.timeout(const Duration(seconds: 45));
        logSnapshotterStage(label + '_style_loaded');
        await snapshotter!.setCamera(
          mapbox.CameraOptions(
            center: camera.center,
            zoom: camera.zoom,
            bearing: camera.bearing,
            pitch: camera.pitch,
          ),
        ).timeout(const Duration(seconds: 15));
        logSnapshotterStage(label + '_camera_set');
        logSnapshotterStage(label + '_capture_started');
        final png = await snapshotter!.start().timeout(
          Duration(seconds: captureTimeoutSeconds),
        );
        if (png == null || png.isEmpty) {
          throw StateError(label + '_snapshotter_returned_empty_png');
        }
        logSnapshotterStage(
          label + '_capture_completed',
          'bytes=' + png.length.toString(),
        );
        _emitMapboxSnapshotterPng(label, png);
      }

      // No external sources: proves that the native renderer can draw a frame.
      debugPrint('MAPBOX_SNAPSHOTTER_BASELINE style=solid-no-source');
      await captureStyle(
        label: 'baseline',
        styleJson: mapboxSnapshotterBaselineStyleJson(),
        captureTimeoutSeconds: 45,
      );

      // One Mapbox Streets vector source and one road layer isolate tile
      // retrieval/decoding from the 148-layer production style.
      debugPrint('MAPBOX_SNAPSHOTTER_VECTOR style=single-streets-road-layer');
      await captureStyle(
        label: 'vector',
        styleJson: mapboxSnapshotterVectorStyleJson(),
        captureTimeoutSeconds: 60,
      );
    } catch (error) {
      logSnapshotterStage(
        'failed',
        'style=' + activeStyleLabel +
            ' error=${sanitizeMapboxDiagnostic(error.toString())}',
      );
      debugPrint(
        'MAPBOX_SNAPSHOTTER_CAPTURE failed style=' + activeStyleLabel +
            ' error=${sanitizeMapboxDiagnostic(error.toString())}',
      );
    } finally {
      final activeSnapshotter = snapshotter;
      if (activeSnapshotter != null) {
        try {
          await activeSnapshotter.dispose().timeout(const Duration(seconds: 10));
          logSnapshotterStage('disposed');
        } catch (error) {
          logSnapshotterStage(
            'dispose_failed',
            'error=${sanitizeMapboxDiagnostic(error.toString())}',
          );
          debugPrint(
            'MAPBOX_SNAPSHOTTER_DISPOSE failed=${sanitizeMapboxDiagnostic(error.toString())}',
          );
        }
      }
    }
  }

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

  Future<void> _applyMapWidgetDiagnosticStyle() async {
    if (_mapWidgetDiagnosticStyleAttempted ||
        mapboxMapWidgetDiagnosticStyle == 'none') {
      return;
    }
    _mapWidgetDiagnosticStyleAttempted = true;

    final isStagingAndroid = _mapWidgetDiagnosticAppEnvironment == 'staging' &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;
    if (!isStagingAndroid) {
      _logMapboxDiagnostic(
        'MAP_WIDGET_DIAGNOSTIC_STYLE',
        'variant=$mapboxMapWidgetDiagnosticStyle result=rejected reason=staging_android_only',
      );
      return;
    }

    final styleJson = mapboxMapWidgetDiagnosticStyleJson(
      mapboxMapWidgetDiagnosticStyle,
    );
    final map = _map;
    if (styleJson == null || map == null) return;

    _logMapboxDiagnostic(
      'MAP_WIDGET_DIAGNOSTIC_STYLE',
      'variant=$mapboxMapWidgetDiagnosticStyle phase=load_json',
    );
    try {
      await map.loadStyleJson(styleJson);
      _logMapboxDiagnostic(
        'MAP_WIDGET_DIAGNOSTIC_STYLE',
        'variant=$mapboxMapWidgetDiagnosticStyle result=accepted',
      );
    } catch (error) {
      _logMapboxDiagnostic(
        'MAP_WIDGET_DIAGNOSTIC_STYLE',
        'variant=$mapboxMapWidgetDiagnosticStyle result=failed error=${sanitizeMapboxDiagnostic(error.toString())}',
      );
    }
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    final renderer =
        ui.ImageFilter.isShaderFilterSupported ? 'impeller' : 'skia';
    _logMapboxDiagnostic('FLUTTER_RENDERER', 'backend=$renderer');
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
    if (mapboxMapWidgetDiagnosticStyle != 'none' &&
        (_mapWidgetDiagnosticAppEnvironment != 'staging' ||
            kIsWeb ||
            defaultTargetPlatform != TargetPlatform.android)) {
      throw StateError(
        'MAPBOX_MAP_WIDGET_DIAGNOSTIC_STYLE is restricted to Android staging.',
      );
    }
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
    _logMapboxDiagnostic('STYLE_URI', 'value=$mapboxStyleUri');
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final androidView = mapboxAndroidViewConfiguration(mapboxAndroidViewMode);
    if (!_mapOptionsLogged) {
      _mapOptionsLogged = true;
      debugPrint(
        'MAPBOX_MAP_OPTIONS pixel_ratio=$devicePixelRatio '
        'glyphs=ideographs_local font=sans-serif',
      );
      debugPrint(
        'MAPBOX_ANDROID_VIEW mode=$mapboxAndroidViewMode '
        'texture_view=${androidView.textureView} '
        'hosting=${androidView.hostingMode}',
      );
    }
    return MapWidget(
      key: const ValueKey('espana-outdoor-mapbox-shared-viewport'),
      styleUri: mapboxStyleUri,
      mapOptions: mapboxMapOptionsForPixelRatio(devicePixelRatio),
      textureView: androidView.textureView,
      androidHostingMode: androidView.hostingMode,
      viewport: CameraViewportState(
        center: Point(coordinates: widget.initialCenter),
        zoom: widget.initialZoom,
        bearing: 0,
        pitch: 0,
      ),
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: (_) {
        _logMapboxDiagnostic('STYLE_LOADED');
        if (mapboxMapWidgetDiagnosticStyle != 'none' &&
            !_mapWidgetDiagnosticStyleAttempted) {
          unawaited(_applyMapWidgetDiagnosticStyle());
          return;
        }
        unawaited(_inspectLoadedStyle());
      },
      onMapLoadedListener: (_) {
        _logMapboxDiagnostic('MAP_LOADED');
      },
      onMapIdleListener: (_) {
        _logMapboxDiagnostic('MAP_IDLE');
      },
      onMapLoadErrorListener: (event) {
        _logMapboxDiagnostic(
          'MAP_LOAD_ERROR',
          'type=${event.type} source=${event.sourceId ?? '-'} '
              'tile=${event.tileId ?? '-'} '
              'message=${sanitizeMapboxDiagnostic(event.message)}',
        );
      },
      onStyleDataLoadedListener: (event) {
        _logMapboxDiagnostic('STYLE_DATA', 'type=${event.type}');
      },
      onSourceAddedListener: (event) {
        _logMapboxDiagnostic('SOURCE_ADDED', 'id=${event.id}');
      },
      onSourceDataLoadedListener: (event) {
        if (_sourceDataEventsLogged >= _maxSourceDataEventsToLog) return;
        _sourceDataEventsLogged++;
        final tileId = event.tileID;
        final tileLabel = formatMapboxTileId(
          z: tileId?.z,
          x: tileId?.x,
          y: tileId?.y,
        );
        _logMapboxDiagnostic(
          'SOURCE_DATA',
          'id=${event.id} type=${event.type} '
              'loaded=${event.loaded ?? 'unknown'} tile=$tileLabel',
        );
      },
      onResourceRequestListener: (event) {
        final kind = mapboxResourceDiagnosticKind(event.request.kind);
        final limit = mapboxResourceDiagnosticLimit(kind);
        final logged = _resourceEventsLoggedByKind[kind] ?? 0;
        if (logged >= limit) {
          if (_resourceSuppressionLogged.add(kind)) {
            _logMapboxDiagnostic(
              'RESOURCE_SUPPRESSED',
              'kind=$kind limit=$limit',
            );
          }
          return;
        }
        _resourceEventsLoggedByKind[kind] = logged + 1;
        final response = event.response;
        final error = response?.error;
        final requestHost = Uri.tryParse(event.request.url)?.host ?? 'unknown';
        _logMapboxDiagnostic(
          'RESOURCE',
          'kind=$kind host=$requestHost '
              'data_source=${event.dataSource} '
              'response_source=${response?.source ?? 'pending'} '
              'size=${response?.size ?? -1} '
              'error=${error?.reason ?? 'none'} '
              'cancelled=${event.cancelled}',
        );
      },
      onStyleImageMissingListener: (event) {
        _logMapboxDiagnostic('STYLE_IMAGE_MISSING', 'id=${event.id}');
      },
      onRenderFrameFinishedListener: (event) {
        final renderMode = event.renderMode.toString();
        if (_lastRenderMode == renderMode) return;
        _lastRenderMode = renderMode;
        _logMapboxDiagnostic(
          'RENDER_FRAME',
          'mode=$renderMode needs_repaint=${event.needsRepaint} '
              'placement_changed=${event.placementChanged}',
        );
      },
    );
  }
}
