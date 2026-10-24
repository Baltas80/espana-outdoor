import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/oidc_config.dart';
import '../../core/auth/oidc_service.dart';
import 'user_profile.dart';
import 'user_profile_api.dart';

class ProfileRegistrationPage extends StatefulWidget {
  const ProfileRegistrationPage({super.key});

  @override
  State<ProfileRegistrationPage> createState() =>
      _ProfileRegistrationPageState();
}

class _ProfileRegistrationPageState extends State<ProfileRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _homeAreaController = TextEditingController();
  final _bioController = TextEditingController();

  late final OidcService _auth =
      OidcService(config: OidcConfig.fromEnvironment());
  late final UserProfileApi _profileApi = UserProfileApi();

  bool _loading = true;
  bool _saving = false;
  bool _authBusy = false;
  bool _signedIn = false;

  static final _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,19}$');

  @override
  void initState() {
    super.initState();
    _loadAccountProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _homeAreaController.dispose();
    _bioController.dispose();
    _profileApi.close();
    super.dispose();
  }

  Future<void> _loadAccountProfile() async {
    try {
      if (!_auth.isConfigured || !_profileApi.isConfigured) return;

      final token = await _auth.accessToken();
      if (token == null || token.isEmpty) return;

      if (mounted) setState(() => _signedIn = true);
      final profile = await _profileApi.getMyProfile(token);
      if (!mounted || profile == null) return;
      _fillForm(profile);
    } on UserProfileApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } on Object {
      if (mounted) {
        _showMessage(
          'No se pudo cargar el perfil del servidor. Comprueba la conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fillForm(UserProfile profile) {
    _displayNameController.text = profile.displayName;
    _usernameController.text = profile.username;
    _homeAreaController.text = profile.homeArea;
    _bioController.text = profile.bio;
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_profileApi.isConfigured) {
      _showMessage(
        'El servicio compartido de perfiles no está configurado en esta versión.',
      );
      return;
    }
    if (!_auth.isConfigured) {
      _showMessage(
        'La identidad OIDC no está configurada en esta versión de la app.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      var token = await _auth.accessToken();
      if (token == null || token.isEmpty) {
        // The existing OIDC authorization flow opens the hosted login page.
        // Users can select Register there when Keycloak self-registration
        // is enabled. Form values stay in the current route while redirected.
        await _auth.signIn();
        token = await _auth.accessToken();
      }

      if (token == null || token.isEmpty) {
        throw const UserProfileApiException(
          401,
          'Inicia sesión o crea tu cuenta para guardar el perfil compartido.',
        );
      }

      final saved = await _profileApi.saveMyProfile(
        accessToken: token,
        profile: UserProfile(
          displayName: _displayNameController.text.trim(),
          username: _usernameController.text.trim().toLowerCase(),
          homeArea: _homeAreaController.text.trim(),
          bio: _bioController.text.trim(),
        ),
      );

      if (mounted) context.pop(saved);
    } on UserProfileApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } on Object {
      if (mounted) {
        _showMessage(
          'No se pudo guardar el perfil compartido. Comprueba la conexión e inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openIdentityProvider() async {
    if (!_auth.isConfigured) {
      _showMessage('Identidad OIDC no configurada en esta versión de la app.');
      return;
    }
    if (!_profileApi.isConfigured) {
      _showMessage(
        'El servicio de perfiles todavía no está configurado en esta versión.',
      );
      return;
    }

    setState(() => _authBusy = true);
    try {
      await _auth.signIn();
      final token = await _auth.accessToken();
      if (token == null || token.isEmpty) {
        throw const UserProfileApiException(
          401,
          'No se ha podido completar la sesión.',
        );
      }
      final profile = await _profileApi.getMyProfile(token);
      if (!mounted) return;

      setState(() => _signedIn = true);
      if (profile != null) {
        _fillForm(profile);
        _showMessage('Cuenta conectada. Perfil sincronizado desde el servidor.');
      } else {
        _showMessage(
          'Cuenta conectada. Completa el perfil y guárdalo para compartirlo entre web y app.',
        );
      }
    } on UserProfileApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } on Object {
      if (mounted) {
        _showMessage(
          'No se pudo conectar con la cuenta. Comprueba OIDC y el servicio de perfiles.',
        );
      }
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _validateDisplayName(String? value) {
    final name = (value ?? '').trim();
    if (name.runes.length < 2) return 'Introduce al menos 2 caracteres.';
    if (name.runes.length > 50) return 'Máximo 50 caracteres.';
    return null;
  }

  String? _validateUsername(String? value) {
    final username = (value ?? '').trim().toLowerCase();
    if (!_usernamePattern.hasMatch(username)) {
      return 'Usa 3–20 caracteres: letras, números, punto, guion o guion bajo.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Registro de perfil')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: colors.primaryContainer,
                                foregroundColor: colors.onPrimaryContainer,
                                child: const Icon(
                                  Icons.person_outline,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Tu identidad outdoor',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _signedIn
                                          ? 'Tu perfil se sincroniza con tu cuenta.'
                                          : 'Usa la misma cuenta en Android y en la web.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _displayNameController,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  maxLength: 50,
                                  validator: _validateDisplayName,
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre visible *',
                                    hintText: 'Cómo quieres aparecer',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _usernameController,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textInputAction: TextInputAction.next,
                                  validator: _validateUsername,
                                  decoration: const InputDecoration(
                                    labelText: 'Alias público *',
                                    hintText: 'senderista_82',
                                    prefixText: '@',
                                    prefixIcon: Icon(Icons.alternate_email),
                                    helperText:
                                        'Alias único de 3 a 20 caracteres.',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _homeAreaController,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  maxLength: 80,
                                  decoration: const InputDecoration(
                                    labelText: 'Zona habitual (opcional)',
                                    hintText: 'Provincia o zona de actividad',
                                    prefixIcon: Icon(Icons.place_outlined),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _bioController,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  maxLength: 160,
                                  maxLines: 3,
                                  minLines: 2,
                                  decoration: const InputDecoration(
                                    labelText: 'Presentación (opcional)',
                                    hintText:
                                        'Qué actividades disfrutas al aire libre',
                                    prefixIcon: Icon(Icons.notes_outlined),
                                    alignLabelWithHint: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: _saving ? null : _saveProfile,
                                    icon: _saving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.cloud_upload_outlined),
                                    label: Text(
                                      _saving
                                          ? 'Conectando y guardando…'
                                          : 'Guardar en mi cuenta',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cuenta de España Outdoor',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'La identidad se gestiona en Keycloak. El perfil se guarda en el servidor y se comparte entre la web y la aplicación.',
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _authBusy ? null : _openIdentityProvider,
                              icon: _authBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.lock_outline),
                              label: Text(
                                _authBusy
                                    ? 'Conectando cuenta…'
                                    : _signedIn
                                        ? 'Actualizar conexión'
                                        : 'Crear cuenta / iniciar sesión',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            !_auth.isConfigured
                                ? 'Falta configurar OIDC en la compilación de la app.'
                                : !_profileApi.isConfigured
                                    ? 'Falta configurar PROFILE_API_BASE_URL en la compilación de la app.'
                                    : 'Si no tienes cuenta, selecciona la opción de registro en la pantalla de Keycloak.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
