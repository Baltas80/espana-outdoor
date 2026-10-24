import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/oidc_config.dart';
import '../../core/auth/oidc_service.dart';
import 'user_profile.dart';
import 'user_profile_api.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final OidcService _auth =
      OidcService(config: OidcConfig.fromEnvironment());
  late final UserProfileApi _profileApi = UserProfileApi();

  UserProfile? _profile;
  bool _profileLoading = true;
  bool _signedIn = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshAccount();
  }

  @override
  void dispose() {
    _profileApi.close();
    super.dispose();
  }

  Future<void> _refreshAccount() async {
    try {
      if (!_auth.isConfigured || !_profileApi.isConfigured) {
        if (mounted) {
          setState(() {
            _signedIn = false;
            _profile = null;
          });
        }
        return;
      }

      final token = await _auth.accessToken();
      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _signedIn = false;
            _profile = null;
          });
        }
        return;
      }

      if (mounted) setState(() => _signedIn = true);
      final profile = await _profileApi.getMyProfile(token);
      if (mounted) setState(() => _profile = profile);
    } on UserProfileApiException catch (error) {
      if (mounted) {
        setState(() => _profile = null);
        _show(error.message);
      }
    } on Object {
      if (mounted) {
        setState(() => _profile = null);
        _show('No se pudo conectar con el servicio de perfiles.');
      }
    } finally {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _openProfileEditor() async {
    final updated = await context.push<UserProfile>('/profile/register');
    if (!mounted) return;

    if (updated != null) {
      setState(() {
        _profile = updated;
        _signedIn = true;
      });
    } else {
      await _refreshAccount();
    }
  }

  Future<void> _signIn() async {
    if (!_auth.isConfigured || !_profileApi.isConfigured) {
      _show(
        !_auth.isConfigured
            ? 'Identidad OIDC no configurada en esta versión.'
            : 'Servicio de perfiles no configurado en esta versión.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await _auth.signIn();
      await _refreshAccount();
    } on Object {
      if (mounted) _show('No se pudo iniciar sesión. Comprueba la conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await _auth.signOut();
      if (mounted) {
        setState(() {
          _signedIn = false;
          _profile = null;
        });
      }
    } on Object {
      if (mounted) _show('No se pudo cerrar la sesión local.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

  @override
  Widget build(BuildContext context) {
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
                              profile?.displayName ??
                                  (_profileLoading
                                      ? 'Cargando perfil…'
                                      : 'Tu perfil outdoor'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              profile != null
                                  ? '@${profile.username}'
                                  : _signedIn
                                      ? 'Completa tu perfil'
                                      : 'Una cuenta para web y app',
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
                                  profile != null
                                      ? 'Perfil sincronizado'
                                      : _signedIn
                                          ? 'Cuenta conectada'
                                          : 'Cuenta no conectada',
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
                        tooltip: _signedIn
                            ? 'Cerrar sesión en este dispositivo'
                            : 'Crear cuenta o iniciar sesión',
                        onPressed: _busy
                            ? null
                            : (_signedIn ? _signOut : _signIn),
                        icon: Icon(_signedIn ? Icons.logout : Icons.login),
                      ),
                    ],
                  ),
                  if (profile?.homeArea.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(profile!.homeArea),
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
                      onPressed:
                          _profileLoading ? null : _openProfileEditor,
                      icon: Icon(
                        profile == null
                            ? Icons.person_add_alt_1
                            : Icons.edit_outlined,
                      ),
                      label: Text(
                        profile == null
                            ? 'Crear mi perfil compartido'
                            : 'Editar mi perfil',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Los datos del perfil se guardan en el servidor y se comparten con la web.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
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
