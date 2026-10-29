import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const mapboxStyleUri = 'mapbox://styles/mapbox/outdoors-v12';
const mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

/// Mapbox surface used by the primary Android map.
/// Offline resources are managed separately by OfflinePage through TileStore.
class MapboxMapViewport extends StatelessWidget {
  const MapboxMapViewport({
    super.key,
    required this.initialCenter,
    required this.initialZoom,
    this.onMapCreated,
  });

  final Position initialCenter;
  final double initialZoom;
  final ValueChanged<MapboxMap>? onMapCreated;

  @override
  Widget build(BuildContext context) {
    if (mapboxAccessToken.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Mapa no disponible: falta la configuración segura '
            'MAPBOX_ACCESS_TOKEN para esta compilación.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return MapWidget(
      key: const ValueKey('espana-outdoor-mapbox-map'),
      styleUri: mapboxStyleUri,
      viewport: CameraViewportState(
        center: Point(coordinates: initialCenter),
        zoom: initialZoom,
        bearing: 0,
        pitch: 0,
      ),
      onMapCreated: onMapCreated,
    );
  }
}
