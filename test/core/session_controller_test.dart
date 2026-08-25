import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/auth/credential_store.dart';
import 'package:providentia_admin/core/auth/operator_authorization.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';

import '../support/fake_api.dart';

final class MemoryCredentialStore implements CredentialStore {
  String? installationId;
  Map<String, String> session = <String, String>{};
  var clears = 0;

  @override
  Future<void> clearSession() async {
    clears += 1;
    session.clear();
  }

  @override
  Future<String?> readInstallationId() async => installationId;

  @override
  Future<Map<String, String>> readSession() async => Map.of(session);

  @override
  Future<void> writeInstallationId(String value) async => installationId = value;

  @override
  Future<void> writeSession(Map<String, String> values) async {
    session = Map.of(values);
  }
}

void main() {
  test('restore without credentials signs out and creates installation', () async {
    final store = MemoryCredentialStore();
    final api = FakeApi((_) async => throw StateError('must not call API'));
    final controller = SessionController(api: api, credentialStore: store);

    await controller.restore();

    expect(controller.phase, SessionPhase.signedOut);
    expect(store.installationId, isNotNull);
    expect(api.requests, isEmpty);
  });

  test('restore bootstraps capabilities from backend roles', () async {
    final store = MemoryCredentialStore()
      ..installationId = 'installation-id'
      ..session = <String, String>{
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'userId': 'user-id',
      };
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
      ..session = <String, String>{'accessToken': 'token'};
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
      ..session = <String, String>{'accessToken': 'token'};
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
}

