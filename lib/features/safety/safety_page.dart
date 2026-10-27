import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/outdoor_visuals.dart';
import '../../core/domain/outdoor_models.dart';
import '../../core/emergency/emergency_contact_directory.dart';
import '../../core/emergency/emergency_service.dart';
import '../../core/emergency/emergency_share_service.dart';
import '../../core/emergency/trusted_contact_store.dart';

class SafetyPage extends StatefulWidget {
  const SafetyPage({super.key});

  @override
  State<SafetyPage> createState() => _SafetyPageState();
}

class _SafetyPageState extends State<SafetyPage> {
  final _emergency = const EmergencyService();
  final _share = const EmergencyShareService();
  final _contacts = TrustedContactStore();
  bool _capturing = false;

  Future<void> _prepareEmergencyCall() async {
    setState(() => _capturing = true);
    EmergencySnapshot? snapshot;
    try {
      snapshot = await _emergency
          .captureSnapshot(type: EmergencyType.other)
          .timeout(const Duration(seconds: 16));
    } catch (_) {
      // A location failure must not block the user from calling 112.
    }
    if (!mounted) return;
    setState(() => _capturing = false);

    const emergencyNumber = '112';
    final locationMessage = snapshot == null
        ? 'No se ha podido obtener la ubicación. Puedes llamar igualmente; '
            'comunica tu ubicación verbalmente si puedes.'
        : 'Ubicación preparada con una precisión aproximada de '
            '${snapshot.accuracyMeters.toStringAsFixed(0)} m.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Llamar al 112'),
        content: Text(locationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Llamar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final launched =
          await _emergency.callEmergencyServices(number: emergencyNumber);
      if (!mounted) return;
      if (!launched) {
        _show('No se pudo abrir la llamada. Marca 112 manualmente.');
      }
    } catch (_) {
      if (mounted) _show('No se pudo abrir la llamada. Marca 112 manualmente.');
    }
  }

  Future<void> _shareEmergency() async {
    setState(() => _capturing = true);
    final snapshot =
        await _emergency.captureSnapshot(type: EmergencyType.other);
    if (!mounted) return;
    setState(() => _capturing = false);
    if (snapshot == null) {
      _show('No se ha podido obtener la ubicación.');
      return;
    }
    final payload = _share.createPayload(snapshot: snapshot);
    final contacts =
        _contacts.load().where((contact) => contact.enabled).toList();
    if (contacts.isEmpty) {
      await _share.copyShareText(payload);
      if (mounted) {
        _show(
          'Alerta copiada. Configura un contacto de confianza para enviarla directamente.',
        );
      }
      return;
    }
    final contact = contacts.first;
    final opened = await _share.openSms(payload, contact.phone);
    if (mounted) {
      _show(
        opened
            ? 'Mensaje de alerta preparado.'
            : 'No se pudo abrir el SMS.',
      );
    }
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seguridad')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const OutdoorVisualHero(
            asset: 'assets/visuals/hero_safety.svg',
            title: 'SOS / Emergencia',
            subtitle: 'Llamada y ubicación en tiempo real.',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed:
                      _capturing ? null : _prepareEmergencyCall,
                  icon: const Icon(Icons.phone),
                  label: Text(
                    _capturing
                        ? 'OBTENIENDO UBICACIÓN…'
                        : 'ACTIVAR SOS',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Usa el SOS solo cuando necesites asistencia. España Outdoor no sustituye a los servicios profesionales.',
          ),
          const SizedBox(height: 16),
          _SafetyTile(
            icon: Icons.location_on_outlined,
            title: 'Mi ubicación',
            subtitle: 'Compartir en tiempo real',
            onTap: _shareEmergency,
          ),
          const SizedBox(height: 10),
          _SafetyTile(
            icon: Icons.contact_emergency_outlined,
            title: 'Contactos',
            subtitle: 'Contactos de emergencia',
            onTap: () => context.go('/safety/contacts'),
          ),
          const SizedBox(height: 10),
          _SafetyTile(
            icon: Icons.security_outlined,
            title: 'Seguridad',
            subtitle: 'Consejos y protocolos',
            onTap: () => context.go('/alerts'),
          ),
          const SizedBox(height: 10),
          _SafetyTile(
            icon: Icons.cell_tower_outlined,
            title: 'Cobertura',
            subtitle: 'Señal y comunicación',
            onTap: () => context.go('/map'),
          ),
          const SizedBox(height: 18),
          Text(
            'Información de seguridad',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _SafetyInfoRow(
            asset: 'assets/visuals/icons/wildlife.svg',
            title: 'Fauna y flora',
            subtitle: 'Respeta la naturaleza y anticipa riesgos.',
            onTap: () => context.go('/wildlife'),
          ),
          const SizedBox(height: 8),
          _SafetyInfoRow(
            asset: 'assets/visuals/icons/pets.svg',
            title: 'Mascotas',
            subtitle: 'Calor, agua, normativa y preparación.',
            onTap: () => context.go('/pets'),
          ),
          const SizedBox(height: 8),
          _SafetyInfoRow(
            asset: 'assets/visuals/icons/natura.svg',
            title: 'NATURA PROTECT',
            subtitle: 'Espacios sensibles y navegación responsable.',
            onTap: () => context.go('/natura'),
          ),
        ],
      ),
    );
  }
}

class _SafetyTile extends StatelessWidget {
  const _SafetyTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onTap,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          leading: Icon(icon, size: 30),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}

class _SafetyInfoRow extends StatelessWidget {
  const _SafetyInfoRow({
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String asset;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 76,
              height: 70,
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: OutdoorAssetIcon(asset: asset, size: 48),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
