import 'dart:convert';

import 'package:http/http.dart' as http;

import 'user_profile.dart';

/// Errors returned by the shared España Outdoor profile API.
final class UserProfileApiException implements Exception {
  const UserProfileApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// HTTP client for the canonical server-side profile.
///
/// The access token is provided by the existing OIDC service. Tokens are
/// never written to local preferences by this client.
final class UserProfileApi {
  UserProfileApi({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? const String.fromEnvironment(
          'PROFILE_API_BASE_URL',
        )).trim();

  final http.Client _client;
  final String _baseUrl;

  bool get isConfigured {
    final uri = Uri.tryParse(_baseUrl);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  Uri get _profileUri {
    if (!isConfigured) {
      throw StateError(
        'PROFILE_API_BASE_URL must be configured with an HTTPS URL.',
      );
    }

    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    return Uri.parse('$base/v1/me/profile');
  }

  Future<UserProfile?> getMyProfile(String accessToken) async {
    _requireToken(accessToken);

    final response = await _client.get(
      _profileUri,
      headers: _headers(accessToken),
    );

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw _apiError(response);
    }
    return _parseProfile(response.body);
  }

  Future<UserProfile> saveMyProfile({
    required String accessToken,
    required UserProfile profile,
  }) async {
    _requireToken(accessToken);
    _validateProfile(profile);

    final response = await _client.put(
      _profileUri,
      headers: _headers(accessToken),
      body: jsonEncode({
        'displayName': profile.displayName.trim(),
        'username': profile.username.trim().toLowerCase(),
        'homeArea': profile.homeArea.trim(),
        'bio': profile.bio.trim(),
      }),
    );

    if (response.statusCode != 200) throw _apiError(response);
    return _parseProfile(response.body);
  }

  void close() => _client.close();

  Map<String, String> _headers(String token) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  void _requireToken(String token) {
    if (token.trim().isEmpty) {
      throw const UserProfileApiException(
        401,
        'Inicia sesión para acceder a tu perfil.',
      );
    }
  }

  UserProfile _parseProfile(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object.');
      }
      return UserProfile(
        displayName: decoded['displayName'] as String? ?? '',
        username: decoded['username'] as String? ?? '',
        homeArea: decoded['homeArea'] as String? ?? '',
        bio: decoded['bio'] as String? ?? '',
      );
    } on Object {
      throw const UserProfileApiException(
        502,
        'El servidor devolvió un perfil no válido.',
      );
    }
  }

  UserProfileApiException _apiError(http.Response response) {
    String message = switch (response.statusCode) {
      401 => 'Tu sesión ha caducado. Vuelve a iniciar sesión.',
      403 => 'No tienes permiso para acceder al perfil.',
      409 => 'Ese alias ya está utilizado. Elige otro.',
      429 => 'Demasiadas peticiones. Espera un momento.',
      502 || 503 || 504 =>
        'El servicio de perfiles no está disponible temporalmente.',
      _ => 'No se pudo completar la operación del perfil.',
    };

    try {
      final decoded = jsonDecode(response.body);
      if (response.statusCode == 409 &&
          decoded is Map<String, dynamic> &&
          decoded['error'] == 'username already in use') {
        message = 'Ese alias ya está utilizado. Elige otro.';
      }
    } on Object {
      // Keep the stable, user-facing message when the body is not JSON.
    }

    return UserProfileApiException(response.statusCode, message);
  }

  void _validateProfile(UserProfile profile) {
    final name = profile.displayName.trim();
    final username = profile.username.trim().toLowerCase();
    final area = profile.homeArea.trim();
    final bio = profile.bio.trim();
    final usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{2,19}$');

    if (name.runes.length < 2 || name.runes.length > 50) {
      throw const UserProfileApiException(
        400,
        'El nombre debe tener entre 2 y 50 caracteres.',
      );
    }
    if (!usernamePattern.hasMatch(username)) {
      throw const UserProfileApiException(
        400,
        'El alias debe tener entre 3 y 20 caracteres válidos.',
      );
    }
    if (area.runes.length > 80 || bio.runes.length > 160) {
      throw const UserProfileApiException(
        400,
        'La zona o la presentación supera la longitud permitida.',
      );
    }
  }
}
