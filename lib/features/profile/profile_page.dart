import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/oidc_config.dart';
import '../../core/auth/oidc_service.dart';
import 'user_profile_store.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final OidcService _auth =
      OidcService(config: OidcConfig.fromEnvironment());
  final UserProfileStore _profileStore = UserProfileStore();

  UserProfile? _profile;
  bool _profileLoading = true;
  bool? _signedIn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _refreshAuth();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileStore.load();
      if (mounted) setState(() => _profile = profile);
    } on Object {
      if (mounted) _show('No se pudo cargar el perfil guardado.');
    } finally {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _openProfileEditor() async {
    final updated = await context.push<UserProfile>('/profile/register');
    if (!mounted) return;

    if (updated != null) {
      setState(() => _profile = updated);
    } else {
      await _loadProfile();
    }
  }

  Future<void> _refreshAuth() async {
    if (!_auth.isConfigured) {
      if (mounted) setState(() => _signedIn = false);
      return;
    }
    try {
      final value = await _auth.isSignedIn();
      if (mounted) setState(() => _signedIn = value);
    } on Object {
      if (mounted) setState(() => _signedIn = false);
    }
  }

  Future<void> _signIn() async {
    if (!_auth.isConfigured) {
      _show('Identidad OIDC no configurada para este entorno.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth.signIn();
      await _refreshAuth();
    } on Object catch (error) {
      if (mounted) _show('No se pudo iniciar sesión: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await _auth.signOut();
      await _refreshAuth();
    } on Object catch (error) {
      if (mounted) _show('No se pudo cerrar sesión: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

  @override
  Widget build(BuildContext context) {
    final signedIn = _signedIn == true;
    final profile = _profile;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          IconButton(
            tooltip: 'Configuración',
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 39,
                        backgroundColor: colors.primaryContainer,
                        foregroundColor: colors.onPrimaryContainer,
                        child: const Icon(Icons.person_outline, size: 42),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.displayName ?? 'Tu perfil outdoor',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              profile == null
                                  ? (_profileLoading
                                      ? 'Cargando perfil…'
                                      : 'Completa tus datos para empezar')
                                  : '@${profile.username}',
                            ),
                            const SizedBox(height: 8),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Text(
                                  profile == null
                                      ? 'Perfil pendiente'
                                      : 'Perfil local',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: signedIn
                            ? 'Cerrar sesión'
                            : 'Crear cuenta o iniciar sesión',
                        onPressed:
                            _busy ? null : (signedIn ? _signOut : _signIn),
                        icon: Icon(signedIn ? Icons.logout : Icons.login),
                      ),
                    ],
                  ),
                  if (profile?.homeArea.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        profile!.homeArea,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                  if (profile?.bio.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(profile!.bio),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _profileLoading ? null : _openProfileEditor,
                      icon: Icon(
                        profile == null
                            ? Icons.person_add_alt_1
                            : Icons.edit_outlined,
                      ),
                      label: Text(
                        profile == null ? 'Crear mi perfil' : 'Editar mi perfil',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ProfileItem(
            icon: Icons.favorite_border,
            title: 'Rutas guardadas',
            onTap: () => context.go('/routes'),
          ),
          _ProfileItem(
            icon: Icons.download_for_offline_outlined,
            title: 'Mapas offline',
            onTap: () => context.go('/offline'),
          ),
          _ProfileItem(
            icon: Icons.photo_library_outlined,
            title: 'Mis fotos',
          ),
          _ProfileItem(
            icon: Icons.place_outlined,
            title: 'Puntos de interés',
            onTap: () => context.go('/explore'),
          ),
          _ProfileItem(
            icon: Icons.history,
            title: 'Historial',
          ),
          _ProfileItem(
            icon: Icons.emoji_events_outlined,
            title: 'Logros',
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              onTap: () => context.go('/profile/plans'),
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text(
                'Free · Premium · Professional',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Capacidades y funciones del servicio.'),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileItem extends StatelessWidget {
  const _ProfileItem({
    required this.icon,
    required this.title,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 1),
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}
