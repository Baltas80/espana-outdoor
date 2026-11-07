import 'package:flutter/material.dart';
import '../../app/outdoor_visuals.dart';
import '../../app/design_system/eo_icon_library.dart';

import '../../core/sources/source_gateway_config.dart';
import '../../infrastructure/sources/remote_source_gateway.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  static const _sources = <({String name, String description, EOIconName icon})>[
    (name: 'AEMET', description: 'Meteorología y avisos meteorológicos oficiales.', icon: EOIconName.weather),
    (name: 'Protección Civil', description: 'Emergencias, avisos y recomendaciones oficiales.', icon: EOIconName.rescue),
    (name: 'MITECO', description: 'Incendios, medio ambiente y datos territoriales.', icon: EOIconName.wildfire),
    (name: 'Fuentes territoriales', description: 'Comunidades autónomas y administraciones competentes.', icon: EOIconName.map),
  ];

  late final Future<List<_AlertRecord>> _alertsFuture;

  @override
  void initState() {
    super.initState();
    _alertsFuture = _loadAlerts();
  }

  Future<List<_AlertRecord>> _loadAlerts() async {
    final config = SourceGatewayConfig.fromEnvironment();
    if (!config.isConfigured) return const [];

    final gateway = RemoteSourceGateway(baseUri: config.baseUri!);
    final snapshot = await gateway.fetch('alerts');
    return [
      for (final record in snapshot.data)
        if (_AlertRecord.tryParse(record) case final alert?) alert,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final gatewayConfigured = SourceGatewayConfig.fromEnvironment().isConfigured;

    return Scaffold(
      appBar: AppBar(title: const Text('Alertas y riesgos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          OutdoorVisualHero(asset: 'assets/visuals/hero_alerts.svg', title: 'Alertas y riesgos', subtitle: 'Información procedente de fuentes verificables.'),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EOIcon(EOIconName.alerts, size: 54),
                  const SizedBox(height: 12),
                  Text('Información verificable', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text('Las alertas activas se muestran únicamente cuando una fuente válida está conectada y existen datos verificables. No se generan alertas ficticias.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!gatewayConfigured)
            const Card(
              child: ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Fuente de alertas no conectada'),
                subtitle: Text('Configura SOURCE_GATEWAY_BASE_URL para recibir datos oficiales normalizados. La ausencia de datos no se interpreta como ausencia de riesgo.'),
              ),
            )
          else
            FutureBuilder<List<_AlertRecord>>(
              future: _alertsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())));
                }
                if (snapshot.hasError) {
                  return Card(child: ListTile(leading: const Icon(Icons.warning_amber_outlined), title: const Text('No se pudieron consultar las alertas'), subtitle: Text('${snapshot.error}')));
                }
                final alerts = snapshot.data ?? const <_AlertRecord>[];
                if (alerts.isEmpty) {
                  return const Card(
                    child: ListTile(
                      leading: Icon(Icons.check_circle_outline),
                      title: Text('Sin alertas activas recibidas'),
                      subtitle: Text('No hay datos activos devueltos por la fuente conectada. Esto no constituye una garantía de ausencia de riesgo.'),
                    ),
                  );
                }
                return Column(children: [for (final alert in alerts) ...[_AlertCard(alert: alert), const SizedBox(height: 8)]]);
              },
            ),
          const SizedBox(height: 12),
          Text('Fuentes previstas', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final source in _sources) ...[
            Card(child: ListTile(leading: EOIcon(source.icon, size: 40), title: Text(source.name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(source.description))),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          Text('España Outdoor no sustituye a 112, ES-Alert, Protección Civil ni a las autoridades competentes.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AlertRecord {
  const _AlertRecord({required this.title, required this.level, required this.source, required this.kind, this.description, this.updatedAt, this.expiresAt, this.certainty});

  final String title;
  final String level;
  final String source;
  final String kind;
  final String? description;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
  final String? certainty;

  static _AlertRecord? tryParse(Map<String, Object?> data) {
    final title = data['title'];
    final level = data['level'];
    final source = data['source'];
    final kind = data['kind'];
    if (title is! String || level is! String || source is! String || kind is! String) return null;
    return _AlertRecord(
      title: title,
      level: level,
      source: source,
      kind: kind,
      description: data['description'] as String?,
      updatedAt: DateTime.tryParse('${data['updatedAt']}')?.toUtc(),
      expiresAt: DateTime.tryParse('${data['expiresAt']}')?.toUtc(),
      certainty: data['certainty'] as String?,
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});
  final _AlertRecord alert;

  @override
  Widget build(BuildContext context) {
    final expired = alert.expiresAt != null && alert.expiresAt!.isBefore(DateTime.now().toUtc());
    return Card(
      child: ListTile(
        leading: Icon(alert.kind.toUpperCase() == 'ALERTA_OFICIAL' ? Icons.campaign : Icons.info_outline, color: Theme.of(context).colorScheme.primary),
        title: Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${alert.kind} · ${alert.level} · ${alert.source}${alert.certainty == null ? '' : ' · certeza ${alert.certainty}'}${expired ? ' · VIGENCIA CADUCADA' : ''}${alert.description == null ? '' : '\n${alert.description}'}'),
      ),
    );
  }
}
