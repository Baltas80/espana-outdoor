import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:espana_outdoors/core/auth/community_identity_api.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    final response = await handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  test('loads canonical profile and sends bearer access token', () async {
    final client = _FakeClient((request) async => http.Response(
          jsonEncode({
            'id': 'canonical-user-uuid',
            'displayName': 'Outdoor User',
            'email': 'verified@example.test',
            'createdAt': '2026-10-29T10:00:00.000Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        ));
    final api = CommunityIdentityApi(
      baseUri: Uri.parse('https://api.example.test'),
      client: client,
    );

    final profile = await api.fetchMyProfile('valid-access-token');

    expect(profile.id, 'canonical-user-uuid');
    expect(profile.displayName, 'Outdoor User');
    expect(profile.email, 'verified@example.test');
    expect(client.lastRequest?.url.path, '/v1/me');
    expect(
      client.lastRequest?.headers['Authorization'],
      'Bearer valid-access-token',
    );
    api.close();
  });

  test('reports an invalid or expired API token', () async {
    final client = _FakeClient((_) async => http.Response('{"error":"unauthorized"}', 401));
    final api = CommunityIdentityApi(
      baseUri: Uri.parse('https://api.example.test'),
      client: client,
    );

    await expectLater(
      api.fetchMyProfile('expired-token'),
      throwsA(isA<CommunityIdentityApiException>()),
    );
    api.close();
  });

  test('rejects a response without the canonical user ID', () async {
    final client = _FakeClient((_) async => http.Response(
          jsonEncode({'displayName': 'No ID'}),
          200,
        ));
    final api = CommunityIdentityApi(
      baseUri: Uri.parse('https://api.example.test'),
      client: client,
    );

    await expectLater(
      api.fetchMyProfile('valid-access-token'),
      throwsA(isA<FormatException>()),
    );
    api.close();
  });

  test('fails closed when API base URL is not configured', () async {
    final api = CommunityIdentityApi(baseUri: null);

    expect(api.isConfigured, isFalse);
    await expectLater(
      api.fetchMyProfile('valid-access-token'),
      throwsA(isA<StateError>()),
    );
    api.close();
  });
}
