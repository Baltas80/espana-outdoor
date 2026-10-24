import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/oidc_config.dart';
import '../../core/auth/oidc_service.dart';
import 'user_profile_store.dart';

class ProfileRegistrationPage extends StatefulWidget {
  const ProfileRegistrationPage({super.key});

  @override
  State<ProfileRegistrationPage> createState() =>
      _ProfileRegistrationPageState();
}

class _ProfileRegistrationPageState extends State<ProfileRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _store = UserProfileStore();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _homeAreaController = TextEditingController();
  final _bioController = TextEditingController();

  late final OidcService _auth =
      OidcService(config: OidcConfig.fromEnvironment());

  bool _loading = true;
  bool _saving = false;
  bool _authBusy = false;

  static final _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,19}$');

  @override
  void initState() {
    super.initState();
    _loadSavedProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _homeAreaController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedProfile() async {
    try {
      final profile = await _store.load();
      if (profile != null) {
        _displayNameController.text = profile.displayName;
        _usernameController.text = profile.username;
        _homeAreaController.text = profile.homeArea;
        _bioController.text = profile.bio;
      }
    } on Object {
      if (mounted) {
        _showMessage('No se pudieron cargar los datos guardados.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final profile = UserProfile(
      displayName: _displayNameController.text.trim(),
      username: _usernameController.text.trim().toLowerCase(),
      homeArea: _homeAreaController.text.trim(),
      bio: _bioController.text.trim(),
    );

    try {
      await _store.save(profile);
      if (mounted) context.pop(profile);
    } on Object {
      if (mounted) {
        _showMessage(
          'No se pudo guardar el perfil. Comprueba los datos e inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openIdentityProvider() async {
    if (!_auth.isConfigured) {
      _showMessage(
        'El proveedor de cuentas todavía no está configurado en este entorno.',
      );
      return;
    }

    setState(() => _authBusy = true);
    try {
      await _auth.signIn();
      if (mounted) {
        _showMessage(
          'Autenticación completada. Los datos del perfil siguen guardándose localmente.',
        );
      }
    } on Object {
      if (mounted) {
        _showMessage(
          'No se pudo abrir la cuenta. Comprueba la configuración OIDC e inténtalo de nuevo.',
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
    final name = value?.trim() ?? '';
    if (name.length < 2) return 'Introduce al menos 2 caracteres.';
    if (name.length > 50) return 'Máximo 50 caracteres.';
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
                                      'Completa los datos que verán otros usuarios.',
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
                                        'Entre 3 y 20 caracteres. Se guardará en minúsculas.',
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
                                        : const Icon(Icons.save_outlined),
                                    label: Text(
                                      _saving
                                          ? 'Guardando…'
                                          : 'Guardar perfil',
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
                            'Cuenta de usuario',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'La cuenta se gestiona con el proveedor de identidad de España Outdoor. No introduzcas aquí una contraseña.',
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
                                    ? 'Abriendo proveedor…'
                                    : 'Crear cuenta / iniciar sesión',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _auth.isConfigured
                                ? 'El alta de nuevas cuentas aparecerá si el proveedor tiene habilitado el registro.'
                                : 'El registro online requiere configurar OIDC/Keycloak en el entorno de la aplicación.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'El perfil se guarda en este dispositivo. La sincronización con una cuenta en la nube requiere conectar el servicio de perfiles del servidor.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
    );
  }
}
