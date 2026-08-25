import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia_admin/core/api/api_client.dart';

void main() {
  test('adds native bearer token and request correlation id', () async {
    late http.Request observed;
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response('{}', 200);
      }),
      accessTokenProvider: () => 'secret-access-token',
      ensureAccessToken: ({required force}) async => true,
      onAuthorizationLost: () {},
    );

    await client.get('/api/v1/me');

    expect(observed.headers['Authorization'], 'Bearer secret-access-token');
    expect(observed.headers['X-Request-ID'], isNotEmpty);
    expect(observed.url.path, '/api/v1/me');
  });

  test('invokes fail-closed callback before exposing a 403', () async {
    var lost = false;
    final refreshRequests = <bool>[];
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{'detail': 'Forbidden'}),
          403,
          headers: const <String, String>{'content-type': 'application/json'},
        ),
      ),
      accessTokenProvider: () => 'token',
      ensureAccessToken: ({required force}) async {
        refreshRequests.add(force);
        return true;
      },
      onAuthorizationLost: () => lost = true,
    );

    try {
      await client.get('/api/v1/admin/accounts');
      fail('request should fail');
    } on ApiException catch (error) {
      expect(lost, isTrue);
      expect(error.statusCode, 403);
      expect(error.message, 'Forbidden');
    }
    expect(refreshRequests, <bool>[false]);
  });

  test('refreshes once and retries a rejected authenticated request', () async {
    var token = 'initial-access-token';
    final observedTokens = <String?>[];
    final refreshRequests = <bool>[];
    final client = ApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient((request) async {
        observedTokens.add(request.headers['Authorization']);
        if (observedTokens.length == 1) {
          return http.Response('{}', 401);
        }
        return http.Response('{}', 200);
      }),
      accessTokenProvider: () => token,
      ensureAccessToken: ({required force}) async {
        refreshRequests.add(force);
        if (force) token = 'rotated-access-token';
        return true;
      },
      onAuthorizationLost: () => fail('retry must preserve authorization'),
    );

    await client.get('/api/v1/admin/accounts');

    expect(refreshRequests, <bool>[false, true]);
    expect(observedTokens, <String?>[
      'Bearer initial-access-token',
      'Bearer rotated-access-token',
    ]);
  });

  test(
    'public identity requests never attach or refresh a bearer token',
    () async {
      late http.Request observed;
      final client = ApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((request) async {
          observed = request;
          return http.Response('{}', 200);
        }),
        accessTokenProvider: () => 'must-not-leak',
        ensureAccessToken: ({required force}) async =>
            fail('public request must not refresh'),
        onAuthorizationLost: () => fail('public request is not privileged'),
      );

      await client.postPublic(
        '/api/v1/auth/refresh',
        body: <String, Object?>{'refreshToken': 'rotating-secret'},
      );

      expect(observed.headers['Authorization'], isNull);
    },
  );
}
