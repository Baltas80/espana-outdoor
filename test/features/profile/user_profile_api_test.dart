import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:espana_outdoors/features/profile/user_profile.dart';
import 'package:espana_outdoors/features/profile/user_profile_api.dart';

void main() {
  const validToken = 'signed-test-token';

  test('requires an HTTPS API base URL', () {
    expect(
      UserProfileApi(baseUrl: 'https://api.example.com').isConfigured,
      isTrue,
    );
    expect(
      UserProfileApi(baseUrl: 'http://api.example.com').isConfigured,
      isFalse,
    );
    expect(UserProfileApi(baseUrl: '').isConfigured, isFalse);
  });

  test('loads the authenticated user profile and sends bearer token', () async {
    var requestSeen = false;
    final client = MockClient((request) async {
      requestSeen = true;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.example.com/v1/me/profile');
      expect(request.headers['Authorization'], 'Bearer $validToken');
      return http.Response(
        jsonEncode({
          'displayName': 'Alex Senderista',
          'username': 'alex_1',
          'homeArea': 'Córdoba',
          'bio': 'Senderismo',
          'createdAt': '2026-10-24T10:00:00Z',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = UserProfileApi(
      client: client,
      baseUrl: 'https://api.example.com',
    );
    final profile = await api.getMyProfile(validToken);
    api.close();

    expect(requestSeen, isTrue);
    expect(profile?.displayName, 'Alex Senderista');
    expect(profile?.username, 'alex_1');
    expect(profile?.homeArea, 'Córdoba');
    expect(profile?.bio, 'Senderismo');
  });

  test('returns null when the authenticated user has no profile yet', () async {
    final api = UserProfileApi(
      client: MockClient((_) async => http.Response(
        jsonEncode({'error': 'profile not created'}),
        404,
      )),
      baseUrl: 'https://api.example.com',
    );

    expect(await api.getMyProfile(validToken), isNull);
    api.close();
  });

  test('creates or updates the shared profile through PUT', () async {
    final api = UserProfileApi(
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.headers['Authorization'], 'Bearer $validToken');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['username'], 'alex_1');
        expect(body['displayName'], 'Alex');
        return http.Response(
          jsonEncode({
            'displayName': 'Alex',
            'username': 'alex_1',
            'homeArea': '',
            'bio': '',
          }),
          200,
        );
      }),
      baseUrl: 'https://api.example.com',
    );

    final saved = await api.saveMyProfile(
      accessToken: validToken,
      profile: const UserProfile(
        displayName: ' Alex ',
        username: 'Alex_1',
      ),
    );

    expect(saved.displayName, 'Alex');
    expect(saved.username, 'alex_1');
    api.close();
  });

  test('shows a useful conflict error for duplicate aliases', () async {
    final api = UserProfileApi(
      client: MockClient((_) async => http.Response(
        jsonEncode({'error': 'username already in use'}),
        409,
      )),
      baseUrl: 'https://api.example.com',
    );

    await expectLater(
      api.saveMyProfile(
        accessToken: validToken,
        profile: const UserProfile(
          displayName: 'Alex',
          username: 'alex_1',
        ),
      ),
      throwsA(
        isA<UserProfileApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          409,
        ),
      ),
    );
    api.close();
  });

  test('rejects invalid profile data before making a request', () async {
    var requestMade = false;
    final api = UserProfileApi(
      client: MockClient((_) async {
        requestMade = true;
        return http.Response('{}', 200);
      }),
      baseUrl: 'https://api.example.com',
    );

    await expectLater(
      api.saveMyProfile(
        accessToken: validToken,
        profile: const UserProfile(
          displayName: 'A',
          username: 'Invalid Alias',
        ),
      ),
      throwsA(isA<UserProfileApiException>()),
    );

    expect(requestMade, isFalse);
    api.close();
  });

  test('translates backend validation errors into Spanish', () async {
    final api = UserProfileApi(
      client: MockClient((_) async => http.Response(
        jsonEncode({
          'error': 'displayName must contain between 2 and 50 characters',
        }),
        400,
      )),
      baseUrl: 'https://api.example.com',
    );

    await expectLater(
      api.saveMyProfile(
        accessToken: validToken,
        profile: const UserProfile(
          displayName: 'Alex',
          username: 'alex_1',
        ),
      ),
      throwsA(
        isA<UserProfileApiException>().having(
          (error) => error.message,
          'message',
          'El nombre debe tener entre 2 y 50 caracteres.',
        ),
      ),
    );
    api.close();
  });
}
