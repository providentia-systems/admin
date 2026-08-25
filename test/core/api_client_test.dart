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
      onAuthorizationLost: () {},
    );

    await client.get('/api/v1/me');

    expect(observed.headers['Authorization'], 'Bearer secret-access-token');
    expect(observed.headers['X-Request-ID'], isNotEmpty);
    expect(observed.url.path, '/api/v1/me');
  });

  test('invokes fail-closed callback before exposing a 403', () async {
    var lost = false;
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
  });
}
