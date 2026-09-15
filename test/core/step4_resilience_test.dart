// Regression tests for session resilience and strict catalog parsing.
// Real HTTP conformance is executed separately by the paired backend lane.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/catalog/catalog_repository.dart';
import '../core/session_controller_test.dart' as fixtures;
import '../support/fake_api.dart';

void main() {
  test(
    'ADM-01 ordinary forbidden action does not invalidate the session',
    () async {
      var losses = 0;
      final api = ApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode({'detail': 'Forbidden'}), 403),
        ),
        accessTokenProvider: () => 'synthetic-access',
        ensureAccessToken: ({required force}) async => true,
        onAuthorizationLost: () => losses++,
      );
      await expectLater(
        api.get('/api/v1/catalog-admin/workbench'),
        throwsA(isA<ApiException>()),
      );
      expect(
        losses,
        0,
        reason: 'A resource denial must not purge an otherwise valid session.',
      );
    },
  );

  for (final status in [429, 503]) {
    test(
      'ADM-02 restore $status preserves recoverable stored credentials but grants no authority',
      () async {
        final store = fixtures.MemoryCredentialStore()
          ..installationId = fixtures.installationId
          ..session = fixtures.storedSession();
        final controller = SessionController(
          api: FakeApi(
            (_) async => throw ApiException(
              statusCode: status,
              message: 'Synthetic temporary error',
            ),
          ),
          credentialStore: store,
        );
        addTearDown(controller.dispose);
        await controller.restore();
        expect(controller.phase, isNot(SessionPhase.authenticated));
        expect(
          store.session['refreshToken'],
          'refresh-token',
          reason: 'Temporary failure is not proof of revoked credentials.',
        );
      },
    );
  }

  test(
    'ADM-02 invalid credentials still clear sensitive state (negative control)',
    () async {
      final store = fixtures.MemoryCredentialStore()
        ..installationId = fixtures.installationId
        ..session = fixtures.storedSession();
      final controller = SessionController(
        api: FakeApi(
          (_) async => throw const ApiException(
            statusCode: 401,
            message: 'Invalid session',
          ),
        ),
        credentialStore: store,
      );
      addTearDown(controller.dispose);
      await controller.restore();
      expect(controller.phase, SessionPhase.signedOut);
      expect(store.session, isEmpty);
      expect(controller.accessToken, isNull);
    },
  );

  test(
    'ADM-02 refresh 503 preserves recoverable material and does not claim renewal',
    () async {
      final store = fixtures.MemoryCredentialStore()
        ..installationId = fixtures.installationId
        ..session = fixtures.storedSession();
      final controller = SessionController(
        api: FakeApi((request) async {
          if (request.path == '/api/v1/auth/refresh') {
            throw const ApiException(
              statusCode: 503,
              message: 'Service unavailable',
            );
          }
          return jsonResponse({
            'userId': fixtures.storedSession()['userId'],
            'profile': {
              'administratorAccess': {
                'features': {'catalog.read': true},
              },
            },
          });
        }),
        credentialStore: store,
      );
      addTearDown(controller.dispose);
      await controller.restore();
      expect(controller.phase, SessionPhase.authenticated);
      expect(await controller.ensureFreshAccessToken(force: true), isFalse);
      expect(store.session['refreshToken'], 'refresh-token');
    },
  );

  test('ERR-01 malformed workbench must not become empty success', () async {
    final repo = CatalogRepository(
      FakeApi((_) async => jsonResponse({'data': 'malformed'})),
    );
    await expectLater(repo.workbench(), throwsA(isA<FormatException>()));
  });

  test(
    'ERR-01 malformed contribution entries must not be silently dropped',
    () async {
      final repo = CatalogRepository(
        FakeApi(
          (_) async => jsonResponse({
            'data': [42],
          }),
        ),
      );
      await expectLater(
        repo.contributionReview(),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('ERR-01 malformed categories must not become empty success', () async {
    final repo = CatalogRepository(
      FakeApi(
        (_) async => jsonResponse({
          'data': {'not': 'a-list'},
        }),
      ),
    );
    await expectLater(repo.categories(), throwsA(isA<FormatException>()));
  });
  test(
    'ADM-02 lost rotation response persists a fence across restart',
    () async {
      final store = fixtures.MemoryCredentialStore()
        ..installationId = fixtures.installationId
        ..session = fixtures.storedSession();
      var rotations = 0;
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/me') return _me();
        rotations++;
        throw TimeoutException('Synthetic response loss after commit');
      });
      final first = SessionController(api: api, credentialStore: store);
      await first.restore();
      expect(await first.ensureFreshAccessToken(force: true), isFalse);
      expect(first.phase, SessionPhase.reauthenticationRequired);
      expect(first.accessToken, isNull);
      expect(store.session['refreshState'], 'pending');
      first.dispose();
      final second = SessionController(api: api, credentialStore: store);
      addTearDown(second.dispose);
      await second.restore();
      expect(second.phase, SessionPhase.reauthenticationRequired);
      expect(await second.ensureFreshAccessToken(force: true), isFalse);
      expect(rotations, 1);
    },
  );

  for (final notSent in [true, false]) {
    test(
      'ADM-02 verified pre-send/rate-limit failure can safely recover ($notSent)',
      () async {
        final store = fixtures.MemoryCredentialStore()
          ..installationId = fixtures.installationId
          ..session = fixtures.storedSession();
        var calls = 0;
        final controller = SessionController(
          api: FakeApi((request) async {
            if (request.path == '/api/v1/me') return _me();
            calls++;
            if (calls == 1) {
              if (notSent) throw const ApiRequestNotSentException();
              throw const ApiException(
                statusCode: 429,
                message: 'rate limited',
                problem: {
                  'type': 'urn:providentia:authentication-rate-limited',
                },
              );
            }
            return jsonResponse(fixtures.rotatedSession());
          }),
          credentialStore: store,
        );
        addTearDown(controller.dispose);
        await controller.restore();
        expect(await controller.ensureFreshAccessToken(force: true), isFalse);
        expect(controller.phase, SessionPhase.temporarilyUnavailable);
        expect(controller.accessToken, isNull);
        expect(store.session.containsKey('refreshState'), isFalse);
        expect(await controller.ensureFreshAccessToken(force: true), isFalse);
        expect(calls, 1);
        await controller.restore();
        expect(controller.phase, SessionPhase.authenticated);
        expect(await controller.ensureFreshAccessToken(force: true), isTrue);
        expect(calls, 2);
      },
    );
  }

  test(
    'ADM-01 permission refresh keeps identity and restores unrelated capabilities',
    () async {
      final store = fixtures.MemoryCredentialStore()
        ..installationId = fixtures.installationId
        ..session = fixtures.storedSession();
      var reads = 0;
      final changed = Completer<ApiResponse>();
      final controller = SessionController(
        api: FakeApi((_) async {
          reads++;
          return reads == 1 ? _me() : changed.future;
        }),
        credentialStore: store,
      );
      addTearDown(controller.dispose);
      await controller.restore();
      final epoch = controller.authorizationEpoch;
      controller.resourceForbidden();
      expect(controller.authorization.permissions, isEmpty);
      expect(controller.authorizationEpoch, greaterThan(epoch));
      expect(store.session['refreshToken'], 'refresh-token');
      changed.complete(
        jsonResponse({
          'userId': fixtures.storedSession()['userId'],
          'profile': {
            'administratorAccess': {
              'features': {'billing.read': true},
            },
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, SessionPhase.authenticated);
      expect(controller.authorization.has('billing.read'), isTrue);
      expect(controller.authorization.has('catalog.review'), isFalse);
      expect(controller.accessToken, 'access-token');
    },
  );

  test(
    'ADM-01 late successful body cannot cross an authorization epoch',
    () async {
      var epoch = 0;
      final reply = Completer<http.Response>();
      final api = ApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) => reply.future),
        accessTokenProvider: () => 'access',
        ensureAccessToken: ({required force}) async => true,
        onAuthorizationLost: () =>
            fail('a stale result must not revoke the new session'),
        authorizationEpochProvider: () => epoch,
      );
      final request = api.get('/api/v1/me');
      final assertion = expectLater(
        request,
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
      await Future<void>.delayed(Duration.zero);
      epoch++;
      reply.complete(http.Response('{"sensitive":"synthetic"}', 200));
      await assertion;
    },
  );
}

ApiResponse _me() => jsonResponse({
  'userId': fixtures.storedSession()['userId'],
  'profile': {
    'administratorAccess': {
      'features': {'catalog.read': true, 'catalog.review': true},
    },
  },
});
