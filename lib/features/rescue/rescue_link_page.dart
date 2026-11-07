import 'dart:async';

import 'package:flutter/material.dart';
import '../../app/outdoor_visuals.dart';
import '../../app/design_system/eo_icon_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/auth/oidc_config.dart';
import '../../core/domain/outdoor_models.dart';
import '../../core/location/location_controller.dart';
import '../../core/rescue/rescue_link_config.dart';
import '../../core/rescue/rescue_link_gateway.dart';
import '../../core/rescue/rescue_link_policy.dart';
import '../../core/auth/oidc_service.dart';
import '../../infrastructure/rescue/http_rescue_link_gateway.dart';

class RescueLinkPage extends ConsumerStatefulWidget {
  const RescueLinkPage({super.key});

  @override
  ConsumerState<RescueLinkPage> createState() => _RescueLinkPageState();
}

class _RescueLinkPageState extends ConsumerState<RescueLinkPage> {
  late final OidcService _auth =
      OidcService(config: OidcConfig.fromEnvironment());
  late final RescueLinkConfig _config = RescueLinkConfig.fromEnvironment();
  final http.Client _httpClient = http.Client();
  RescueLinkRemoteSession? _session;
  Timer? _expiryTimer;
  bool _busy = false;

  late final RescueLinkGateway _gateway = HttpRescueLinkGateway(
    baseUrl: _config.baseUrl,
    accessToken: _auth.accessToken,
    client: _httpClient,
    allowHttpForDevelopment: _config.allowHttpForDevelopment,
  );

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _httpClient.close();
    super.dispose();
  }

  void _scheduleExpiry(DateTime expiresAt) {
    _expiryTimer?.cancel();
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      _session = null;
      return;
    }
    _expiryTimer = Timer(remaining, () {
      if (!mounted) return;
      _expiryTimer?.cancel();
      setState(() => _session = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rescue Link ha caducado.')),
      );
    });
  }

  bool _sessionIsActive(RescueLinkRemoteSession session) {
    if (!DateTime.now().toUtc().isBefore(session.expiresAt)) {
      _expiryTimer?.cancel();
      _session = null;
      return false;
    }
    return true;
  }

  Future<void> _prepare() async {
    if (!_config.isConfigured) {
      _showError(
        'Rescue Link no está configurado para este entorno. No se ha creado ningún enlace.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(locationControllerProvider.notifier).locate();
      final position = ref.read(locationControllerProvider).position;
      if (position == null) {
        throw StateError('Necesitamos una ubicación antes de preparar Rescue Link.');
      }

      final policy = const RescueLinkPolicy();
      final expiresAt = DateTime.now().toUtc().add(policy.ttl);
      final session = await _gateway.create(
        RescueLinkCreateRequest(
          position: GeoPoint(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
          accuracyMeters: position.accuracy,
          type: EmergencyType.lost,
          expiresAt: expiresAt,
        ),
      );

      if (!mounted) return;
      setState(() => _session = session);
      _scheduleExpiry(session.expiresAt);
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    final session = _session;
    if (session == null || !_sessionIsActive(session)) return;
    setState(() => _busy = true);
    try {
      await _gateway.revoke(session.id);
      if (!mounted) return;
      _expiryTimer?.cancel();
      setState(() => _session = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rescue Link revocado.')),
      );
    } on Object catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLink() async {
    final session = _session;
    if (session == null || !_sessionIsActive(session)) return;
    await Clipboard.setData(
      ClipboardData(text: session.shareUrl.toString()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enlace Rescue Link copiado.')),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceFirst('Exception: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('Rescue Link')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          OutdoorVisualHero(asset: 'assets/visuals/hero_rescue.svg', title: 'Rescue Link', subtitle: 'Ayuda cercana, con controles de seguridad y privacidad.'),
          const SizedBox(height: 12),
          const Center(
            child: OutdoorAssetIcon(
              asset: 'assets/visuals/icons/library/premium/rescue.webp',
              size: 80,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.link_outlined,
                    size: 34,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ayuda sin crear otra víctima',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'La primera señal usa ubicación aproximada. La ubicación temporal más precisa solo se comparte dentro de una sesión autorizada.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _RoleTile(
            icon: const EOIcon(EOIconName.rescue, size: 32),
            title: '1. Servicios oficiales',
            subtitle: '112 y servicios competentes tienen prioridad.',
          ),
          const _RoleTile(
            icon: const EOIcon(EOIconName.contacts, size: 32),
            title: '2. Contactos de confianza',
            subtitle: 'Personas elegidas por el usuario.',
          ),
          const _RoleTile(
            icon: const Icon(Icons.volunteer_activism_outlined),
            title: '3. Voluntarios autorizados',
            subtitle: 'Solo cuando el escenario sea apto y con controles de riesgo.',
          ),
          const SizedBox(height: 16),
          if (session == null)
            FilledButton.icon(
              onPressed: _busy ? null : _prepare,
              icon: const Icon(Icons.location_searching),
              label: Text(
                _busy ? 'PREPARANDO RESCUE LINK…' : 'PREPARAR RESCUE LINK',
              ),
            )
          else ...[
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const EOIcon(EOIconName.safety, size: 32),
                title: const Text(
                  'Sesión activa',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Caduca ${session.expiresAt.toLocal().hour.toString().padLeft(2, '0')}:${session.expiresAt.toLocal().minute.toString().padLeft(2, '0')}. La ubicación exacta queda protegida en el backend y no se muestra en esta pantalla.',
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _copyLink,
              icon: const Icon(Icons.copy_outlined),
              label: const Text('COPIAR ENLACE'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _revoke,
              child: Text(_busy ? 'REVOCANDO…' : 'REVOCAR RESCUE LINK'),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Nunca se ofrecerán voluntarios dentro de incendios, evacuaciones, cierres o alertas oficiales graves. Rescue Link no sustituye al 112.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final Widget icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: icon,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitle),
      );
}