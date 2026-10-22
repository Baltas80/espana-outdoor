import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../core/gpx/gpx_export_service.dart';
import '../../core/gpx/gpx_import_service.dart';
import '../../core/models/route_summary.dart';
import '../map/maplibre_map_viewport.dart';

class RouteDetailPage extends StatefulWidget {
  const RouteDetailPage({super.key, this.route, this.track});
  final RouteSummary? route;
  final ImportedTrack? track;
  @override
  State<RouteDetailPage> createState() => _RouteDetailPageState();
}

class _RouteDetailPageState extends State<RouteDetailPage> {
  final _exporter = const GpxExportService();
  Future<void> _exportTrack() async {
    final track = widget.track;
    if (track == null) return;
    try {
      final saved = await _exporter.saveTrack(track);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved == null ? 'Exportación cancelada.' : 'GPX guardado.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo exportar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final route = widget.route;
    final title = track?.name ?? route?.name ?? 'Detalle de ruta';
    final List<LatLng> points = track == null
        ? const <LatLng>[]
        : track.points
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList(growable: false);
    final center = points.isNotEmpty ? points[points.length ~/ 2] : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (track != null)
            IconButton(
              tooltip: 'Exportar GPX',
              onPressed: _exportTrack,
              icon: const Icon(Icons.file_download_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: MapLibreMapViewport(
                initialCenter: ml.LatLng(
                  center?.latitude ?? 40.4168,
                  center?.longitude ?? -3.7038,
                ),
                initialZoom: center == null ? 7 : 14,
                routePoints: points
                    .map((point) => ml.LatLng(point.latitude, point.longitude))
                    .toList(growable: false),
              ),
            ),
          ),
          if (track != null) ...[
            const SizedBox(height: 10),
            const Text(
              'La traza se conserva completa en el GPX y en el registro de la ruta.',
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 18),
          if (track != null) _TrackStats(track: track),
          if (route != null) _RouteStats(route: route),
          if (track != null || route != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push('/navigation'),
                icon: const Icon(Icons.navigation_outlined),
                label: const Text('Iniciar navegación GPS'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrackStats extends StatelessWidget {
  const _TrackStats({required this.track});
  final ImportedTrack track;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        children: [
          _Stat(
            label: 'Distancia',
            value: '${(track.distanceMeters / 1000).toStringAsFixed(2)} km',
          ),
          _Stat(
            label: 'Desnivel +',
            value: '+${track.ascentMeters.toStringAsFixed(0)} m',
          ),
          _Stat(
            label: 'Desnivel -',
            value: '-${track.descentMeters.toStringAsFixed(0)} m',
          ),
          _Stat(label: 'Puntos', value: '${track.points.length}'),
        ],
      ),
    ),
  );
}

class _RouteStats extends StatelessWidget {
  const _RouteStats({required this.route});
  final RouteSummary route;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        children: [
          _Stat(
            label: 'Distancia',
            value: '${route.distanceKm.toStringAsFixed(1)} km',
          ),
          _Stat(
            label: 'Desnivel +',
            value: '+${route.elevationGainM.toStringAsFixed(0)} m',
          ),
          _Stat(label: 'Tiempo', value: '${route.durationMinutes} min'),
          _Stat(label: 'Dificultad', value: route.difficulty),
        ],
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 125,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}
