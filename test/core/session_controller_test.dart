import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/credential_store.dart';
import 'package:providentia_admin/core/auth/operator_authorization.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';

import '../support/fake_api.dart';

final _fixtureAccessExpiry = DateTime.now().toUtc().add(const Duration(hours:1)).toIso8601String();

const installationId = '44444444-4444-4444-8444-444444444444';

final class MemoryCredentialStore implements CredentialStore {
  String? installationId;
  Map<String, String> session = <String, String>{};
  Map<String, String> pending = <String, String>{};
  var clears = 0;
  var failWrites = false;
  var failClears = false;
  Completer<void>? sessionWriteBarrier;
  Completer<void>? sessionWriteStarted;

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
    final started = sessionWriteStarted;
    if (started != null && !started.isCompleted) started.complete();
    await sessionWriteBarrier?.future;
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
  'sessionId': '0198f4e2-7abc-7def-8abc-0123456789ab',
  'deviceId': '22222222-2222-4222-8222-222222222222',
  'installationId': installationId,
  'userId': '0198f4e3-7abc-7def-8abc-0123456789ab',
  'accessExpiresAt': _fixtureAccessExpiry,
  'refreshExpiresAt': '2026-10-01T00:00:00Z',
  'idleExpiresAt': '2026-10-01T00:00:00Z',
  'refreshIdleTtlSeconds': '2592000',
  'transport': 'native',
};

Map<String, String> durableStoredSession() => storedSession()
  ..remove('refreshExpiresAt')
  ..remove('idleExpiresAt')
  ..remove('refreshIdleTtlSeconds');

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

  test('restore replaces a malformed installation identifier', () async {
    final store = MemoryCredentialStore()..installationId = 'not-a-uuid';
    final controller = SessionController(
      api: FakeApi((_) async => throw StateError('must not call API')),
      credentialStore: store,
    );

    await controller.restore();

    expect(controller.phase, SessionPhase.signedOut);
    expect(store.installationId, isNot('not-a-uuid'));
    expect(
      store.installationId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('Admin bootstrap accepts an operator account with no home', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    final api = FakeApi(
      (_) async => jsonResponse(<String, Object?>{
        'userId': storedSession()['userId'],
        'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'catalog.read': true, 'catalog.review': true}}},
        'activeHomeId': null,
        'homes': <Object?>[],
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

  test('unknown permissions allow onboarding without operator access', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    final api = FakeApi(
      (_) async => jsonResponse(<String, Object?>{
        'userId': storedSession()['userId'],
        'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{}}},
      }),
    );
    final controller = SessionController(api: api, credentialStore: store);

    await controller.restore();

    expect(controller.phase, SessionPhase.authenticated);
    expect(controller.authorization.isOperator, isFalse);
    expect(store.session, isNotEmpty);
  });

  test('authorization loss purges privileged state synchronously', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = storedSession();
    final api = FakeApi(
      (_) async => jsonResponse(<String, Object?>{
        'userId': storedSession()['userId'],
        'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'accounts.read': true, 'accounts.manage': true, 'accounts.assign': true, 'people.read': true, 'homes.read': true, 'homes.manage': true, 'homes.assign': true, 'administrators.read': true, 'administrators.approve': true, 'administrators.manage': true, 'groups.manage': true, 'countries.manage': true, 'policies.manage': true, 'catalog.read': true, 'catalog.review': true, 'catalog.curate': true, 'billing.read': true, 'billing.manage': true, 'audit.read': true}}},
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

  test(
    'sign out revokes memory synchronously and clears both keyring tuples',
    () async {
      final store = MemoryCredentialStore()
        ..installationId = installationId
        ..session = storedSession()
        ..pending = <String, String>{'requestId': 'pending-secret'};
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/me') {
          return jsonResponse(<String, Object?>{
            'userId': storedSession()['userId'],
            'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'accounts.read': true, 'accounts.manage': true, 'accounts.assign': true, 'people.read': true, 'homes.read': true, 'homes.manage': true, 'homes.assign': true, 'administrators.read': true, 'administrators.approve': true, 'administrators.manage': true, 'groups.manage': true, 'countries.manage': true, 'policies.manage': true, 'catalog.read': true, 'catalog.review': true, 'catalog.curate': true, 'billing.read': true, 'billing.manage': true, 'audit.read': true}}},
          });
        }
        if (request.path == '/api/v1/auth/logout') {
          return jsonResponse(const <String, Object?>{});
        }
        throw StateError('unexpected ${request.path}');
      });
      final controller = SessionController(api: api, credentialStore: store);
      await controller.restore();
      final epoch = controller.authorizationEpoch;

      final revocation = controller.signOut();

      expect(controller.phase, SessionPhase.signedOut);
      expect(controller.accessToken, isNull);
      expect(controller.authorization.isOperator, isFalse);
      expect(controller.authorizationEpoch, epoch + 1);
      await revocation;
      expect(store.session, isEmpty);
      expect(store.pending, isEmpty);
      expect(store.clears, 1);
    },
  );

  test(
    'sign out surfaces a failed keyring purge without masking revocation',
    () async {
      final store = MemoryCredentialStore()
        ..installationId = installationId
        ..session = storedSession();
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/me') {
          return jsonResponse(<String, Object?>{
            'userId': storedSession()['userId'],
            'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'accounts.read': true, 'accounts.manage': true, 'accounts.assign': true, 'people.read': true, 'homes.read': true, 'homes.manage': true, 'homes.assign': true, 'administrators.read': true, 'administrators.approve': true, 'administrators.manage': true, 'groups.manage': true, 'countries.manage': true, 'policies.manage': true, 'catalog.read': true, 'catalog.review': true, 'catalog.curate': true, 'billing.read': true, 'billing.manage': true, 'audit.read': true}}},
          });
        }
        if (request.path == '/api/v1/auth/logout') {
          return jsonResponse(const <String, Object?>{});
        }
        throw StateError('unexpected ${request.path}');
      });
      final controller = SessionController(api: api, credentialStore: store);
      await controller.restore();
      store.failClears = true;

      await controller.signOut();

      expect(controller.phase, SessionPhase.signedOut);
      expect(controller.accessToken, isNull);
      expect(controller.authorization.isOperator, isFalse);
      expect(controller.error, contains('keyring'));
    },
  );

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

  test('durable session restores without any inactivity ceiling', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = durableStoredSession();
    final api = FakeApi((request) async {
      if (request.path == '/api/v1/me') {
        return jsonResponse(<String, Object?>{
          'userId': storedSession()['userId'],
          'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'accounts.read': true, 'accounts.manage': true, 'accounts.assign': true, 'people.read': true, 'homes.read': true, 'homes.manage': true, 'homes.assign': true, 'administrators.read': true, 'administrators.approve': true, 'administrators.manage': true, 'groups.manage': true, 'countries.manage': true, 'policies.manage': true, 'catalog.read': true, 'catalog.review': true, 'catalog.curate': true, 'billing.read': true, 'billing.manage': true, 'audit.read': true}}},
        });
      }
      throw StateError('unexpected ${request.path}');
    });
    final controller = SessionController(api: api, credentialStore: store);

    await controller.restore();

    expect(controller.phase, SessionPhase.authenticated);
    // A durable session never trips the local expiry ceiling; the fresh
    // access token is reused without a refresh rotation.
    expect(await controller.ensureFreshAccessToken(), isTrue);
    expect(controller.phase, SessionPhase.authenticated);
    expect(
      api.requests.where((request) => request.path == '/api/v1/auth/refresh'),
      isEmpty,
    );
  });

  test(
    'durable exchanged credentials round-trip null bounds through the store',
    () async {
      final store = MemoryCredentialStore()..installationId = installationId;
      late String requestId;
      late String expiresAt;
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/auth/email-codes') {
          requestId =
              '11111111-1111-4111-8111-111111111111';
          expiresAt = DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String();
          return jsonResponse(<String, Object?>{
            'accepted': true,
            'requestId': requestId,
            'expiresAt': expiresAt,
            'pollIntervalSeconds': 2,
          });
        }
        if (request.path.endsWith('/status')) {
          return jsonResponse(<String, Object?>{
            'requestId': requestId,
            'applicationKind': 'admin',
            'status': 'approved',
            'expiresAt': expiresAt,
          });
        }
        if (request.path.endsWith('/verify')) {
          return jsonResponse(<String, Object?>{
            ...rotatedSession(),
            'refreshExpiresAt': null,
            'idleExpiresAt': null,
            'refreshIdleTtlSeconds': null,
          });
        }
        if (request.path == '/api/v1/me') {
          return jsonResponse(<String, Object?>{
            'userId': storedSession()['userId'],
            'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'catalog.read': true, 'catalog.review': true}}},
          });
        }
        throw StateError('unexpected ${request.path}');
      });
      final controller = SessionController(api: api, credentialStore: store);
      await controller.restore();
      await controller.requestEmailCode('operator@example.test');

      expect(await controller.verifyEmailCode('12345678'), isTrue);

      expect(controller.phase, SessionPhase.authenticated);
      for (final key in <String>[
        'refreshExpiresAt',
        'idleExpiresAt',
        'refreshIdleTtlSeconds',
      ]) {
        expect(store.session[key], anyOf(isNull, isEmpty));
      }

      final restored = SessionController(api: api, credentialStore: store);
      await restored.restore();

      expect(restored.phase, SessionPhase.authenticated);
      expect(await restored.ensureFreshAccessToken(), isTrue);
    },
  );

  test('nonsense persisted idle bounds are still rejected', () async {
    for (final refreshIdleTtlSeconds in <String>[
      '899',
      '5184001',
      'not-a-number',
    ]) {
      final store = MemoryCredentialStore()
        ..installationId = installationId
        ..session = (storedSession()
          ..['refreshIdleTtlSeconds'] = refreshIdleTtlSeconds);
      final controller = SessionController(
        api: FakeApi((_) async => throw StateError('must not call API')),
        credentialStore: store,
      );

      await controller.restore();

      expect(controller.phase, SessionPhase.signedOut);
      expect(store.session, isEmpty);
    }
  });

  test('a partially bounded session tuple is purged as corrupt', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..session = (durableStoredSession()
        ..['refreshExpiresAt'] = '2026-10-01T00:00:00Z');
    final controller = SessionController(
      api: FakeApi((_) async => throw StateError('must not call API')),
      credentialStore: store,
    );

    await controller.restore();

    expect(controller.phase, SessionPhase.signedOut);
    expect(store.session, isEmpty);
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
          'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'accounts.read': true, 'accounts.manage': true, 'accounts.assign': true, 'people.read': true, 'homes.read': true, 'homes.manage': true, 'homes.assign': true, 'administrators.read': true, 'administrators.approve': true, 'administrators.manage': true, 'groups.manage': true, 'countries.manage': true, 'policies.manage': true, 'catalog.read': true, 'catalog.review': true, 'catalog.curate': true, 'billing.read': true, 'billing.manage': true, 'audit.read': true}}},
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
        'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'catalog.read': true, 'catalog.review': true}}},
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
          'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'accounts.read': true, 'accounts.manage': true, 'accounts.assign': true, 'people.read': true, 'homes.read': true, 'homes.manage': true, 'homes.assign': true, 'administrators.read': true, 'administrators.approve': true, 'administrators.manage': true, 'groups.manage': true, 'countries.manage': true, 'policies.manage': true, 'catalog.read': true, 'catalog.review': true, 'catalog.curate': true, 'billing.read': true, 'billing.manage': true, 'audit.read': true}}},
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
          'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'catalog.read': true, 'catalog.review': true}}},
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
          'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'billing.read': true, 'billing.manage': true}}},
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
            'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'catalog.read': true, 'catalog.review': true, 'catalog.curate': true}}},
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
          'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'accounts.read': true, 'accounts.manage': true, 'accounts.assign': true, 'people.read': true, 'homes.read': true, 'homes.manage': true, 'homes.assign': true, 'administrators.read': true, 'administrators.approve': true, 'administrators.manage': true, 'groups.manage': true, 'countries.manage': true, 'policies.manage': true, 'catalog.read': true, 'catalog.review': true, 'catalog.curate': true, 'billing.read': true, 'billing.manage': true, 'audit.read': true}}},
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
    'email code request is explicitly bound to the Admin application',
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

      await controller.requestEmailCode('operator@example.test');

      expect(startBody['applicationKind'], 'admin');
      expect(startBody['platform'], 'linux');
      expect(startBody['transport'], 'native');
      expect(controller.phase, SessionPhase.loginPending);
      expect(store.pending['challengeId'], isNotEmpty);
    },
  );

  test(
    'email code verification binds challenge and session credentials end to end',
    () async {
      final store = MemoryCredentialStore()..installationId = installationId;
      late String requestId;
      late String expiresAt;
      late Map<String, Object?> startBody;
      late Map<String, Object?> exchangeBody;
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/auth/email-codes') {
          startBody = request.body! as Map<String, Object?>;
          requestId = '11111111-1111-4111-8111-111111111111';
          expiresAt = DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String();
          return jsonResponse(<String, Object?>{
            'accepted': true,
            'requestId': requestId,
            'expiresAt': expiresAt,
            'pollIntervalSeconds': 2,
          });
        }
        if (request.path.endsWith('/status')) {
          return jsonResponse(<String, Object?>{
            'requestId': requestId,
            'applicationKind': 'admin',
            'status': 'approved',
            'expiresAt': expiresAt,
          });
        }
        if (request.path.endsWith('/verify')) {
          exchangeBody = request.body! as Map<String, Object?>;
          return jsonResponse(<String, Object?>{
            ...rotatedSession(),
            'activeHomeId': null,
          });
        }
        if (request.path == '/api/v1/me') {
          return jsonResponse(<String, Object?>{
            'userId': storedSession()['userId'],
            'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'catalog.read': true, 'catalog.review': true}}},
            'activeHomeId': null,
            'homes': <Object?>[],
          });
        }
        throw StateError('unexpected ${request.path}');
      });
      final controller = SessionController(api: api, credentialStore: store);
      await controller.restore();

      await controller.requestEmailCode('operator@example.test');
      final challenge = controller.challenge!;
      expect(await controller.verifyEmailCode('12345678'), isTrue);

      expect(startBody['applicationKind'], 'admin');
      expect(exchangeBody, <String, Object?>{
        'challengeId': challenge.challengeId,
        'bindingToken': challenge.bindingToken,
        'code': '12345678',
      });
      expect(controller.phase, SessionPhase.authenticated);
      expect(controller.userId, storedSession()['userId']);
      expect(controller.challenge, isNull);
      expect(store.pending, isEmpty);
      expect(store.session['refreshToken'], 'rotated-refresh-token');
    },
  );

  test(
    'cross-installation exchange purges the pending credential tuple',
    () async {
      final store = MemoryCredentialStore()..installationId = installationId;
      late String requestId;
      late String expiresAt;
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/auth/email-codes') {
          requestId =
              '11111111-1111-4111-8111-111111111111';
          expiresAt = DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String();
          return jsonResponse(<String, Object?>{
            'accepted': true,
            'requestId': requestId,
            'expiresAt': expiresAt,
            'pollIntervalSeconds': 2,
          });
        }
        if (request.path.endsWith('/status')) {
          return jsonResponse(<String, Object?>{
            'requestId': requestId,
            'applicationKind': 'admin',
            'status': 'approved',
            'expiresAt': expiresAt,
          });
        }
        if (request.path.endsWith('/verify')) {
          return jsonResponse(<String, Object?>{
            ...rotatedSession(),
            'installationId': '55555555-5555-4555-8555-555555555555',
          });
        }
        throw StateError('unexpected ${request.path}');
      });
      final controller = SessionController(api: api, credentialStore: store);
      await controller.restore();
      await controller.requestEmailCode('operator@example.test');

      await expectLater(controller.verifyEmailCode('12345678'), throwsFormatException);

      expect(controller.phase, SessionPhase.signedOut);
      expect(controller.accessToken, isNull);
      expect(store.session, isEmpty);
      expect(store.pending, isEmpty);
    },
  );

  test(
    'malformed session response fails closed without rendering wire data',
    () async {
      final store = MemoryCredentialStore();
      late String requestId;
      late String expiresAt;
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/auth/email-codes') {
          requestId =
              '11111111-1111-4111-8111-111111111111';
          expiresAt = DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String();
          return jsonResponse(<String, Object?>{
            'accepted': true,
            'requestId': requestId,
            'expiresAt': expiresAt,
            'pollIntervalSeconds': 2,
          });
        }
        return jsonResponse(<String, Object?>{
          'requestId': requestId,
          'applicationKind': 'admin',
          'status': 'server_internal_detail',
          'expiresAt': expiresAt,
        });
      });
      final controller = SessionController(api: api, credentialStore: store);
      await controller.restore();
      await controller.requestEmailCode('operator@example.test');

      await expectLater(controller.verifyEmailCode('12345678'), throwsFormatException);

      expect(controller.phase, SessionPhase.signedOut);
      expect(controller.error, isNot(contains('server_internal_detail')));
      expect(store.pending, isEmpty);
    },
  );

  test('corrupted restored login challenge is purged before verification', () async {
    final store = MemoryCredentialStore()
      ..installationId = installationId
      ..pending = <String, String>{
        'requestId': 'not-a-uuid',
        'pollToken': 'short',
        'codeVerifier': 'short',
        'state': 'short',
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
        'pollIntervalSeconds': '60',
      };
    final controller = SessionController(
      api: FakeApi((_) async => throw StateError('must not call API')),
      credentialStore: store,
    );

    await controller.restore();

    expect(controller.phase, SessionPhase.signedOut);
    expect(controller.challenge, isNull);
    expect(store.pending, isEmpty);
  });

  test('a new code request replaces the pending challenge', () async {
 final store = MemoryCredentialStore();
 var calls = 0;
 final api = FakeApi((request) async => jsonResponse(<String,Object?>{
 'challengeId': calls++ == 0 ? '11111111-1111-4111-8111-111111111111' : '22222222-2222-4222-8222-222222222222',
 'bindingToken': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'expiresAt': DateTime.now().toUtc().add(const Duration(minutes:10)).toIso8601String(), 'resendAfterSeconds':60}));
 final controller = SessionController(api:api, credentialStore:store);
 await controller.restore(); await controller.requestEmailCode('first@example.test');
 final old = controller.challenge!.challengeId;
 await controller.requestEmailCode('second@example.test');
 expect(controller.challenge!.challengeId,isNot(old));
 expect(store.pending['email'],'second@example.test');
});

  test(
    'cancellation during exchange persistence cannot restore a session',
    () async {
      final store = MemoryCredentialStore()..installationId = installationId;
      final barrier = Completer<void>();
      final writeStarted = Completer<void>();
      store.sessionWriteBarrier = barrier;
      store.sessionWriteStarted = writeStarted;
      late String requestId;
      late String expiresAt;
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/auth/email-codes') {
          requestId =
              '11111111-1111-4111-8111-111111111111';
          expiresAt = DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String();
          return jsonResponse(<String, Object?>{
            'accepted': true,
            'requestId': requestId,
            'expiresAt': expiresAt,
            'pollIntervalSeconds': 2,
          });
        }
        if (request.path.endsWith('/status')) {
          return jsonResponse(<String, Object?>{
            'requestId': requestId,
            'applicationKind': 'admin',
            'status': 'approved',
            'expiresAt': expiresAt,
          });
        }
        if (request.path.endsWith('/verify')) {
          return jsonResponse(rotatedSession());
        }
        if (request.path.endsWith('/cancel') ||
            request.path == '/api/v1/auth/logout') {
          return jsonResponse(<String, Object?>{});
        }
        throw StateError('unexpected ${request.path}');
      });
      final controller = SessionController(api: api, credentialStore: store);
      await controller.restore();
      await controller.requestEmailCode('operator@example.test');

      final poll = controller.verifyEmailCode('12345678');
      await writeStarted.future;
      await controller.cancelEmailCode();
      barrier.complete();

      expect(await poll, isFalse);
      expect(controller.phase, SessionPhase.signedOut);
      expect(controller.accessToken, isNull);
      expect(store.session, isEmpty);
      expect(store.pending, isEmpty);
    },
  );

  test(
    'cancellation during bootstrap purges and cannot reauthenticate',
    () async {
      final store = MemoryCredentialStore()..installationId = installationId;
      final meStarted = Completer<void>();
      final meResponse = Completer<ApiResponse>();
      late String requestId;
      late String expiresAt;
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/auth/email-codes') {
          requestId =
              '11111111-1111-4111-8111-111111111111';
          expiresAt = DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String();
          return jsonResponse(<String, Object?>{
            'accepted': true,
            'requestId': requestId,
            'expiresAt': expiresAt,
            'pollIntervalSeconds': 2,
          });
        }
        if (request.path.endsWith('/status')) {
          return jsonResponse(<String, Object?>{
            'requestId': requestId,
            'applicationKind': 'admin',
            'status': 'approved',
            'expiresAt': expiresAt,
          });
        }
        if (request.path.endsWith('/verify')) {
          return jsonResponse(rotatedSession());
        }
        if (request.path == '/api/v1/me') {
          if (!meStarted.isCompleted) meStarted.complete();
          return meResponse.future;
        }
        if (request.path == '/api/v1/auth/logout') {
          return jsonResponse(<String, Object?>{});
        }
        throw StateError('unexpected ${request.path}');
      });
      final controller = SessionController(api: api, credentialStore: store);
      await controller.restore();
      await controller.requestEmailCode('operator@example.test');

      final poll = controller.verifyEmailCode('12345678');
      await meStarted.future;
      await controller.cancelEmailCode();
      meResponse.complete(
        jsonResponse(<String, Object?>{
          'userId': storedSession()['userId'],
          'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'accounts.read': true, 'accounts.manage': true, 'accounts.assign': true, 'people.read': true, 'homes.read': true, 'homes.manage': true, 'homes.assign': true, 'administrators.read': true, 'administrators.approve': true, 'administrators.manage': true, 'groups.manage': true, 'countries.manage': true, 'policies.manage': true, 'catalog.read': true, 'catalog.review': true, 'catalog.curate': true, 'billing.read': true, 'billing.manage': true, 'audit.read': true}}},
        }),
      );

      expect(await poll, isFalse);
      expect(controller.phase, SessionPhase.signedOut);
      expect(controller.accessToken, isNull);
      expect(controller.authorization.isOperator, isFalse);
      expect(store.session, isEmpty);
      expect(store.pending, isEmpty);
    },
  );

  test(
    'bootstrap identity mismatch purges the restored operator session',
    () async {
      final store = MemoryCredentialStore()
        ..installationId = installationId
        ..session = storedSession();
      final api = FakeApi(
        (_) async => jsonResponse(<String, Object?>{
          'userId': '55555555-5555-4555-8555-555555555555',
          'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'accounts.read': true, 'accounts.manage': true, 'accounts.assign': true, 'people.read': true, 'homes.read': true, 'homes.manage': true, 'homes.assign': true, 'administrators.read': true, 'administrators.approve': true, 'administrators.manage': true, 'groups.manage': true, 'countries.manage': true, 'policies.manage': true, 'catalog.read': true, 'catalog.review': true, 'catalog.curate': true, 'billing.read': true, 'billing.manage': true, 'audit.read': true}}},
        }),
      );
      final controller = SessionController(api: api, credentialStore: store);

      await controller.restore();

      expect(controller.phase, SessionPhase.signedOut);
      expect(controller.authorization.isOperator, isFalse);
      expect(store.session, isEmpty);
    },
  );

  test(
    'an invalid verification response fails closed and clears pending data',
    () async {
      final store = MemoryCredentialStore();
      late String requestId;
      final api = FakeApi((request) async {
        if (request.path == '/api/v1/auth/email-codes') {
          requestId =
              '11111111-1111-4111-8111-111111111111';
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
      await controller.requestEmailCode('operator@example.test');

      await expectLater(controller.verifyEmailCode('12345678'), throwsFormatException);

      expect(controller.phase, SessionPhase.signedOut);
      expect(controller.challenge, isNull);
      expect(store.pending, isEmpty);
    },
  );

  test('cancellation wins a race with a pending verification response', () async {
    final store = MemoryCredentialStore();
    final statusResponse = Completer<ApiResponse>();
    late String requestId;
    final api = FakeApi((request) async {
      if (request.path == '/api/v1/auth/email-codes') {
        requestId =
            '11111111-1111-4111-8111-111111111111';
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
      if (request.path.endsWith('/verify')) return statusResponse.future;
      if (request.path.endsWith('/logout')) {
        return jsonResponse(<String, Object?>{});
      }
      throw StateError('unexpected ${request.path}');
    });
    final controller = SessionController(api: api, credentialStore: store);
    await controller.restore();
    await controller.requestEmailCode('operator@example.test');

    final poll = controller.verifyEmailCode('12345678');
    await Future<void>.delayed(Duration.zero);
    await controller.cancelEmailCode();
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
      api.requests.where((request) => request.path.endsWith('/verify')),
      hasLength(1),
    );
  });
}
