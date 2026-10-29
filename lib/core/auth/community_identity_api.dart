import 'dart:convert';

import 'package:http/http.dart' as http;

/// Canonical profile returned by the España Outdoor community API.
final class CommunityIdentityProfile {
  const CommunityIdentityProfile({
    required this.id,
    required this.displayName,
    required this.email,
    required this.createdAt,
  });

  final String id;
  final String? displayName;
  final String? email;
  final DateTime? createdAt;

  factory CommunityIdentityProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('The community API returned no canonical user ID.');
    }

    final createdAtValue = json['createdAt'];
    return CommunityIdentityProfile(
      id: id,
      displayName: json['displayName'] is String ? json['displayName'] as String : null,
      email: json['email'] is String ? json['email'] as String : null,
      createdAt: createdAtValue is String ? DateTime.tryParse(createdAtValue) : null,
    );
  }
}

/// Small authenticated adapter for the shared identity API.
final class CommunityIdentityApi {
  CommunityIdentityApi({
    required this.baseUri,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri? baseUri;
  final http.Client _client;
  final bool _ownsClient;

  static CommunityIdentityApi fromEnvironment({http.Client? client}) {
    const rawBaseUri = String.fromEnvironment('COMMUNITY_API_BASE_URL');
    final parsed = Uri.tryParse(rawBaseUri.trim());
    final valid = parsed != null &&
        (parsed.scheme == 'https' || parsed.scheme == 'http') &&
        parsed.host.isNotEmpty &&
        parsed.userInfo.isEmpty &&
        parsed.query.isEmpty &&
        parsed.fragment.isEmpty;
    return CommunityIdentityApi(
      baseUri: valid ? parsed : null,
      client: client,
    );
  }

  bool get isConfigured => baseUri != null;

  Future<CommunityIdentityProfile> fetchMyProfile(String accessToken) async {
    final base = baseUri;
    if (base == null) {
      throw StateError('Community API is not configured.');
    }
    if (accessToken.trim().isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken', 'Must not be empty.');
    }

    final endpoint = base.resolve('/v1/me');
    final response = await _client
        .get(
          endpoint,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 401) {
      throw const CommunityIdentityApiException(
        'La API ha rechazado el token. Comprueba la audiencia OIDC.',
      );
    }
    if (response.statusCode != 200) {
      throw CommunityIdentityApiException(
        'No se pudo recuperar el perfil (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The community API returned an invalid profile.');
    }
    return CommunityIdentityProfile.fromJson(decoded);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

final class CommunityIdentityApiException implements Exception {
  const CommunityIdentityApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
