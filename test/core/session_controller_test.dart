import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/auth/credential_store.dart';
import 'package:providentia_admin/core/auth/operator_authorization.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';

import '../support/fake_api.dart';

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
  'userId': '33333333-3333-4333-8333-333333333333',
  'accessExpiresAt': '2026-09-01T00:00:00Z',
  'refreshExpiresAt': '2026-10-01T00:00:00Z',
  'idleExpiresAt': '2026-10-01T00:00:00Z',
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
      ..installationId = 'installation-id'
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
      ..installationId = 'installation-id'
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
      ..installationId = 'installation-id'
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
      ..installationId = 'installation-id'
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
      ..installationId = 'installation-id'
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

    await controller.signOut();

    expect(calls, 2);
    expect(controller.phase, SessionPhase.signedOut);
    expect(controller.accessToken, isNull);
    expect(store.session, isEmpty);
  });

  test('keyring clear failure still removes in-memory authorization', () async {
    final store = MemoryCredentialStore()
      ..installationId = 'installation-id'
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
}
