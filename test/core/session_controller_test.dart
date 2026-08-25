import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/credential_store.dart';
import 'package:providentia_admin/core/auth/operator_authorization.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';

import '../support/fake_api.dart';

const installationId = '44444444-4444-4444-8444-444444444444';

final class MemoryCredentialStore implements CredentialStore {
  String? installationId;
  Map<String, String> session = <String, String>{};
  Map<String, String> pending = <String, String>{};
  var clears = 0;
  var failWrites = false;
  var failClears = false;

  @override
  Future<void> clearSession() async {
    if (failClears) throw StateError('keyring unavailable');
    clears += 1;
    session.clear();
  }

  @override
  Future<void> clearPendingLogin() async => pending.clear();

  @override
  Future<String?> readInstallationId() async => installationId;

  @override
  Future<Map<String, String>> readPendingLogin() async => Map.of(pending);

  @override
  Future<Map<String, String>> readSession() async => Map.of(session);

  @override
  Future<void> writeInstallationId(String value) async =>
      installationId = value;

  @override
  Future<void> writeSession(Map<String, String> values) async {
    if (failWrites) throw StateError('keyring unavailable');
    session = Map.of(values);
  }

  @override
  Future<void> writePendingLogin(Map<String, String> values) async {
    pending = Map.of(values);
  }
}

Map<String, String> storedSession() => <String, String>{
  'accessToken': 'access-token',
  'refreshToken': 'refresh-token',
  'sessionId': '11111111-1111-4111-8111-111111111111',
  'deviceId': '22222222-2222-4222-8222-222222222222',
  'installationId': installationId,
  'userId': '33333333-3333-4333-8333-333333333333',
  'accessExpiresAt': '2026-09-01T00:00:00Z',
  'refreshExpiresAt': '2026-10-01T00:00:00Z',
  'idleExpiresAt': '2026-10-01T00:00:00Z',
  'refreshIdleTtlSeconds': '2592000',
  'transport': 'native',
};

Map<String, Object?> rotatedSession({
  String accessToken = 'rotated-access-token',
  String refreshToken = 'rotated-refresh-token',
  String? deviceId,
}) => <String, Object?>{
  ...storedSession(),
  'accessToken': accessToken,
  'refreshToken': refreshToken,
  'deviceId': ?deviceId,
};

void main() {
  test(
    'restore without credentials signs out and creates installation',
    () async {
      final store = MemoryCredentialStore();
      final api = FakeApi((_) async => throw StateError('must not call API'));
      final controller = SessionController(api: api, credentialStore: store);

      await controller.restore();

      expect(controller.phase, SessionPhase.signedOut);
      expect(store.installationId, isNotNull);
      expect(api.requests, isEmpty);
    },
  );

  test('restore bootstraps capabilities from backend roles', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    final api = FakeApi(
      (_) async => jsonResponse(<String, Object?>{
        'userId': 'user-id',
        'platformRoles': <Object?>['catalog_reviewer'],
      }),
    );
    final controller = SessionController(api: api, credentialStore: store);

    await controller.restore();

    expect(controller.phase, SessionPhase.authenticated);
    expect(
      controller.authorization.allows(OperatorCapability.reviewCatalog),
      isTrue,
    );
    expect(api.requests.single.path, '/api/v1/me');
  });

  test('unknown role fails closed during bootstrap', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    final api = FakeApi(
      (_) async => jsonResponse(<String, Object?>{
        'userId': 'user-id',
        'platformRoles': <Object?>['home_owner'],
      }),
    );
    final controller = SessionController(api: api, credentialStore: store);

    await controller.restore();

    expect(controller.phase, SessionPhase.signedOut);
    expect(controller.authorization.isOperator, isFalse);
    expect(store.session, isEmpty);
  });

  test('authorization loss purges privileged state synchronously', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    final api = FakeApi(
      (_) async => jsonResponse(<String, Object?>{
        'userId': 'user-id',
        'platformRoles': <Object?>['platform_administrator'],
      }),
    );
    final controller = SessionController(api: api, credentialStore: store);
    await controller.restore();
    final epoch = controller.authorizationEpoch;

    controller.authorizationLost();

    expect(controller.phase, SessionPhase.signedOut);
    expect(controller.accessToken, isNull);
    expect(controller.authorization.isOperator, isFalse);
    expect(controller.authorizationEpoch, epoch + 1);
  });

  test('partial secure tuple is purged instead of restored', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = <String, String>{'refreshToken': 'orphaned'};
    final controller = SessionController(
      api: FakeApi((_) async => throw StateError('must not call API')),
      credentialStore: store,
    );

    await controller.restore();

    expect(controller.phase, SessionPhase.signedOut);
    expect(store.session, isEmpty);
    expect(store.clears, 1);
  });

  test('sign out purges memory after a non-API transport failure', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    var calls = 0;
    final api = FakeApi((request) async {
      calls += 1;
      if (request.path == '/api/v1/me') {
        return jsonResponse(<String, Object?>{
          'userId': storedSession()['userId'],
          'platformRoles': <Object?>['platform_administrator'],
        });
      }
      throw StateError('network unavailable');
    });
    final controller = SessionController(api: api, credentialStore: store);
    await controller.restore();

    final signOut = controller.signOut();

    expect(controller.phase, SessionPhase.signedOut);
    expect(controller.accessToken, isNull);
    await signOut;

    expect(calls, 2);
    expect(store.session, isEmpty);
  });

  test('keyring clear failure still removes in-memory authorization', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    final api = FakeApi(
      (_) async => jsonResponse(<String, Object?>{
        'userId': storedSession()['userId'],
        'platformRoles': <Object?>['catalog_reviewer'],
      }),
    );
    final controller = SessionController(api: api, credentialStore: store);
    await controller.restore();
    store.failClears = true;

    controller.authorizationLost();
    await Future<void>.delayed(Duration.zero);

    expect(controller.phase, SessionPhase.signedOut);
    expect(controller.authorization.isOperator, isFalse);
    expect(controller.error, contains('keyring'));
  });

  test('concurrent access refreshes share one rotating request', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    final refreshResponse = Completer<ApiResponse>();
    var refreshCalls = 0;
    final api = FakeApi((request) async {
      if (request.path == '/api/v1/me') {
        return jsonResponse(<String, Object?>{
          'userId': storedSession()['userId'],
          'platformRoles': <Object?>['platform_administrator'],
        });
      }
      if (request.path == '/api/v1/auth/refresh') {
        refreshCalls += 1;
        return refreshResponse.future;
      }
      throw StateError('unexpected ${request.path}');
    });
    final controller = SessionController(api: api, credentialStore: store);
    await controller.restore();

    final first = controller.ensureFreshAccessToken(force: true);
    final second = controller.ensureFreshAccessToken(force: true);
    await Future<void>.delayed(Duration.zero);
    expect(refreshCalls, 1);
    refreshResponse.complete(jsonResponse(rotatedSession()));

    expect(await Future.wait(<Future<bool>>[first, second]), <bool>[
      true,
      true,
    ]);
    expect(controller.accessToken, 'rotated-access-token');
    expect(store.session['refreshToken'], 'rotated-refresh-token');
  });

  test('refresh persistence failure never activates rotated memory', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    final api = FakeApi((request) async {
      if (request.path == '/api/v1/me') {
        return jsonResponse(<String, Object?>{
          'userId': storedSession()['userId'],
          'platformRoles': <Object?>['catalog_reviewer'],
        });
      }
      return jsonResponse(rotatedSession());
    });
    final controller = SessionController(api: api, credentialStore: store);
    await controller.restore();
    store.failWrites = true;

    expect(await controller.ensureFreshAccessToken(force: true), isFalse);

    expect(controller.phase, SessionPhase.signedOut);
    expect(controller.accessToken, isNull);
    expect(store.session, isEmpty);
  });

  test('invalid refresh response purges the native session', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    final api = FakeApi((request) async {
      if (request.path == '/api/v1/me') {
        return jsonResponse(<String, Object?>{
          'userId': storedSession()['userId'],
          'platformRoles': <Object?>['billing_operator'],
        });
      }
      throw const ApiException(statusCode: 401, message: 'invalid refresh');
    });
    final controller = SessionController(api: api, credentialStore: store);
    await controller.restore();

    expect(await controller.ensureFreshAccessToken(force: true), isFalse);

    expect(controller.phase, SessionPhase.signedOut);
    expect(store.session, isEmpty);
  });

  test(
    'rotated credentials must preserve session, device and user bindings',
    () async {
      final store = MemoryCredentialStore()
        ..installationId = installationId
        ..session = storedSession();
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/me') {
          return jsonResponse(<String, Object?>{
            'userId': storedSession()['userId'],
            'platformRoles': <Object?>['catalog_curator'],
          });
        }
        return jsonResponse(
          rotatedSession(deviceId: '55555555-5555-4555-8555-555555555555'),
        );
      });
      final controller = SessionController(api: api, credentialStore: store);
      await controller.restore();

      expect(await controller.ensureFreshAccessToken(force: true), isFalse);

      expect(controller.phase, SessionPhase.signedOut);
      expect(store.session, isEmpty);
    },
  );

  test('logout wins a race with an in-flight refresh', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    final refreshResponse = Completer<ApiResponse>();
    final api = FakeApi((request) async {
      if (request.path == '/api/v1/me') {
        return jsonResponse(<String, Object?>{
          'userId': storedSession()['userId'],
          'platformRoles': <Object?>['platform_administrator'],
        });
      }
      if (request.path == '/api/v1/auth/refresh') {
        return refreshResponse.future;
      }
      if (request.path == '/api/v1/auth/logout') {
        return jsonResponse(<String, Object?>{});
      }
      throw StateError('unexpected ${request.path}');
    });
    final controller = SessionController(api: api, credentialStore: store);
    await controller.restore();

    final refresh = controller.ensureFreshAccessToken(force: true);
    await Future<void>.delayed(Duration.zero);
    await controller.signOut();
    refreshResponse.complete(jsonResponse(rotatedSession()));

    expect(await refresh, isFalse);
    expect(controller.phase, SessionPhase.signedOut);
    expect(controller.accessToken, isNull);
    expect(store.session, isEmpty);
  });

  test(
    'login-link start is explicitly bound to the Admin application',
    () async {
      final store = MemoryCredentialStore();
      late Map<String, Object?> startBody;
      final api = FakeApi((request) async {
        startBody = request.body! as Map<String, Object?>;
        return jsonResponse(<String, Object?>{
          'accepted': true,
          'requestId': startBody['requestId'],
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
          'pollIntervalSeconds': 2,
        });
      });
      final controller = SessionController(api: api, credentialStore: store);
      await controller.restore();

      await controller.startLoginLink('operator@example.test');

      expect(startBody['applicationKind'], 'admin');
      expect(startBody['platform'], 'linux');
      expect(startBody['transport'], 'native');
      expect(controller.phase, SessionPhase.loginPending);
      expect(store.pending['requestId'], isNotEmpty);
    },
  );

  test(
    'status for another application fails closed and clears pending data',
    () async {
      final store = MemoryCredentialStore();
      late String requestId;
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/auth/login-links') {
          requestId =
              (request.body! as Map<String, Object?>)['requestId']! as String;
          return jsonResponse(<String, Object?>{
            'accepted': true,
            'requestId': requestId,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 10))
                .toIso8601String(),
            'pollIntervalSeconds': 2,
          });
        }
        return jsonResponse(<String, Object?>{
          'requestId': requestId,
          'applicationKind': 'homeowner',
          'status': 'pending',
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
        });
      });
      final controller = SessionController(api: api, credentialStore: store);
      await controller.restore();
      await controller.startLoginLink('operator@example.test');

      await expectLater(controller.pollLoginLink(), throwsFormatException);

      expect(controller.phase, SessionPhase.signedOut);
      expect(controller.challenge, isNull);
      expect(store.pending, isEmpty);
    },
  );

  test('cancellation wins a race with a pending status response', () async {
    final store = MemoryCredentialStore();
    final statusResponse = Completer<ApiResponse>();
    late String requestId;
    final api = FakeApi((request) async {
      if (request.path == '/api/v1/auth/login-links') {
        requestId =
            (request.body! as Map<String, Object?>)['requestId']! as String;
        return jsonResponse(<String, Object?>{
          'accepted': true,
          'requestId': requestId,
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
          'pollIntervalSeconds': 2,
        });
      }
      if (request.path.endsWith('/status')) return statusResponse.future;
      if (request.path.endsWith('/cancel')) {
        return jsonResponse(<String, Object?>{});
      }
      throw StateError('unexpected ${request.path}');
    });
    final controller = SessionController(api: api, credentialStore: store);
    await controller.restore();
    await controller.startLoginLink('operator@example.test');

    final poll = controller.pollLoginLink();
    await Future<void>.delayed(Duration.zero);
    await controller.cancelLoginLink();
    statusResponse.complete(
      jsonResponse(<String, Object?>{
        'requestId': requestId,
        'applicationKind': 'admin',
        'status': 'approved',
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
      }),
    );

    expect(await poll, isFalse);
    expect(controller.phase, SessionPhase.signedOut);
    expect(
      api.requests.where((request) => request.path.endsWith('/exchange')),
      isEmpty,
    );
  });
}
