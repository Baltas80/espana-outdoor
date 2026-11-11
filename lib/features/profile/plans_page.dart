import 'package:flutter/material.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../app/outdoor_visuals.dart';
import '../../app/design_system/eo_icon_library.dart';
import '../../domain/subscriptions/entitlements.dart';
import '../../infrastructure/subscriptions/revenuecat_subscription_service.dart';

class PlansPage extends StatefulWidget {
  const PlansPage({super.key});

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  final _subscriptions = RevenueCatSubscriptionService.fromEnvironment();
  OutdoorPlan _selectedPlan = OutdoorPlan.free;

  static const _features = <({String label, OutdoorEntitlement entitlement})>[
    (
      label: 'Descubrimiento y planificación de rutas',
      entitlement: OutdoorEntitlement.routeDiscovery
    ),
    (
      label: 'GPS y grabación',
      entitlement: OutdoorEntitlement.gpsRecording
    ),
    (
      label: 'Importar y exportar GPX',
      entitlement: OutdoorEntitlement.gpxImportExport
    ),
    (
      label: 'Mapas offline avanzados',
      entitlement: OutdoorEntitlement.advancedOfflineMaps
    ),
    (
      label: 'Evaluación de seguridad de ruta',
      entitlement: OutdoorEntitlement.routeSafetyAssessment
    ),
    (label: 'Modo Mascota', entitlement: OutdoorEntitlement.petMode),
    (label: 'Guía de fauna', entitlement: OutdoorEntitlement.faunaGuide),
    (label: 'NATURA PROTECT', entitlement: OutdoorEntitlement.naturaProtect),
    (label: 'Rescue Link', entitlement: OutdoorEntitlement.rescueLink),
    (
      label: 'Alertas avanzadas',
      entitlement: OutdoorEntitlement.advancedAlerts
    ),
    (
      label: 'Datos profesionales',
      entitlement: OutdoorEntitlement.professionalData
    ),
    (
      label: 'API y analítica avanzada',
      entitlement: OutdoorEntitlement.apiAccess
    ),
  ];

  String _planName(OutdoorPlan plan) => switch (plan) {
        OutdoorPlan.free => 'FREE',
        OutdoorPlan.premium => 'PREMIUM',
        OutdoorPlan.professional => 'PROFESSIONAL',
      };

  Future<void> _selectPlan(OutdoorPlan plan) async {
    if (plan == OutdoorPlan.free) {
      setState(() => _selectedPlan = plan);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan FREE seleccionado.')),
      );
      return;
    }

    const apiKey = String.fromEnvironment('REVENUECAT_API_KEY');
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El catálogo de compras todavía no está configurado en este APK.',
          ),
        ),
      );
      return;
    }

    try {
      setState(() => _selectedPlan = plan);
      await _subscriptions.configure();

      final entitlement =
          plan == OutdoorPlan.premium ? 'premium' : 'professional';
      await RevenueCatUI.presentPaywallIfNeeded(entitlement);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir la suscripción: $error')),
      );
    }
  }

  Future<void> _restore() async {
    const apiKey = String.fromEnvironment('REVENUECAT_API_KEY');
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Las compras todavía no están configuradas en este APK.',
          ),
        ),
      );
      return;
    }

    try {
      await _subscriptions.configure();
      await _subscriptions.restorePurchases();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compras restauradas.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron restaurar las compras: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const OutdoorVisualHero(
            asset: 'assets/visuals/hero_plans.svg',
            title: 'Planes',
            subtitle: 'Capacidades claras para cada forma de explorar.',
          ),
          const SizedBox(height: 14),
          const Center(child: EOIcon(EOIconName.plans, size: 72)),
          const SizedBox(height: 18),
          Text(
            'Elige cómo quieres explorar',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'FREE funciona sin compra. PREMIUM y PROFESSIONAL se conectan al catálogo de la tienda cuando RevenueCat está configurado.',
          ),
          const SizedBox(height: 14),
          for (final plan in OutdoorPlan.values) ...[
            _PlanCard(
              plan: plan,
              selected: _selectedPlan == plan,
              planName: _planName(plan),
              features: _features,
              onPressed: () => _selectPlan(plan),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _restore,
            icon: const Icon(Icons.restore),
            label: const Text('Restaurar compras'),
          ),
          const SizedBox(height: 14),
          Text(
            'Las funciones críticas de emergencia no dependen de la suscripción.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.planName,
    required this.features,
    required this.onPressed,
  });

  final OutdoorPlan plan;
  final bool selected;
  final String planName;
  final List<({String label, OutdoorEntitlement entitlement})> features;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final allowed = features
        .where(
          (feature) => EntitlementCatalog.allows(plan, feature.entitlement),
        )
        .map((feature) => feature.label)
        .take(4)
        .toList(growable: false);

    return Card(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    planName,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            for (final feature in allowed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(feature)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPressed,
                child: Text(plan == OutdoorPlan.free ? 'Usar FREE' : 'Continuar con $planName'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
