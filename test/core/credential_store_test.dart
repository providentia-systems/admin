import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/auth/credential_store.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';

import '../support/fake_api.dart';

import '../support/memory_credential_store.dart';

final class _MemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'SecureCredentialStore must not use ${invocation.memberName}.',
  );
}

void main() {
  test('bounded session tuples round-trip every persisted key', () async {
    final storage = _MemorySecureStorage();
    final store = SecureCredentialStore(storage: storage);

    await store.writeSession(memoryStoredSession());

    expect(await store.readSession(), memoryStoredSession());
    expect(storage.values.keys, everyElement(startsWith('providentia.admin.')));
  });

  test('durable null bounds are persisted as absent keys', () async {
    final storage = _MemorySecureStorage();
    final store = SecureCredentialStore(storage: storage);
    final durable = memoryStoredSession()
      ..['refreshExpiresAt'] = ''
      ..['idleExpiresAt'] = ''
      ..['refreshIdleTtlSeconds'] = '';

    await store.writeSession(durable);

    final restored = await store.readSession();
    expect(restored.containsKey('refreshExpiresAt'), isFalse);
    expect(restored.containsKey('idleExpiresAt'), isFalse);
    expect(restored.containsKey('refreshIdleTtlSeconds'), isFalse);
    expect(restored['accessToken'], 'access-token');
    expect(restored['refreshIdleTtlSeconds'], isNull);
    expect(
      storage.values.containsKey('providentia.admin.refreshIdleTtlSeconds'),
      isFalse,
    );
  });

  test(
    'rotating a bounded tuple into a durable one drops stale bounds',
    () async {
      final storage = _MemorySecureStorage();
      final store = SecureCredentialStore(storage: storage);
      await store.writeSession(memoryStoredSession());

      await store.writeSession(
        memoryStoredSession()
          ..['refreshExpiresAt'] = ''
          ..['idleExpiresAt'] = ''
          ..['refreshIdleTtlSeconds'] = '',
      );

      final restored = await store.readSession();
      expect(restored.containsKey('refreshExpiresAt'), isFalse);
      expect(restored.containsKey('idleExpiresAt'), isFalse);
      expect(restored.containsKey('refreshIdleTtlSeconds'), isFalse);

      await store.clearSession();
      expect(await store.readSession(), isEmpty);
    },
  );

  test('pending login and installation tuples stay namespaced', () async {
    final storage = _MemorySecureStorage();
    final store = SecureCredentialStore(storage: storage);

    await store.writeInstallationId(memoryInstallationId);
    await store.writePendingLogin(<String, String>{
      'challengeId': memoryInstallationId,
      'bindingToken': 'binding-token',
      'email': 'person@example.test',
      'expiresAt': '2026-12-01T00:00:00Z',
      'resendAt': '2026-11-30T23:51:00Z',
      'ignored': 'never-stored',
    });

    expect(await store.readInstallationId(), memoryInstallationId);
    final pending = await store.readPendingLogin();
    expect(pending['challengeId'], memoryInstallationId);
    expect(pending['bindingToken'], 'binding-token');
    expect(pending.containsKey('ignored'), isFalse);
    expect(storage.values.keys, everyElement(startsWith('providentia.admin.')));

    await store.clearPendingLogin();
    expect(await store.readPendingLogin(), isEmpty);
    expect(await store.readInstallationId(), memoryInstallationId);
  });
  test(
    'installation identity survives logout and is never mistaken for a session',
    () async {
      final storage = _MemorySecureStorage();
      final store = SecureCredentialStore(storage: storage);
      await store.writeInstallationId(memoryInstallationId);
      expect(await store.readSession(), isEmpty);
      await store.writeSession(memoryStoredSession());
      expect(
        storage.values.keys.where((key) => key.endsWith('.session')),
        hasLength(1),
      );
      await store.clearSession();
      expect(await store.readSession(), isEmpty);
      expect(await store.readInstallationId(), memoryInstallationId);
    },
  );

  test('malformed credential envelopes fail closed', () async {
    final storage = _MemorySecureStorage();
    storage.values['providentia.admin.session'] = '{"accessToken":42}';
    final store = SecureCredentialStore(storage: storage);
    await expectLater(store.readSession(), throwsFormatException);
    await store.clearSession();
    expect(await store.readSession(), isEmpty);
  });
  test(
    'a new controller resumes the email code from production credential storage',
    () async {
      final storage = _MemorySecureStorage();
      final credentials = SecureCredentialStore(storage: storage);
      final api = FakeApi(
        (_) async => jsonResponse({
          'challengeId': '11111111-1111-4111-8111-111111111111',
          'bindingToken': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
          'resendAfterSeconds': 60,
        }),
      );
      final first = SessionController(api: api, credentialStore: credentials);
      await first.restore();
      await first.requestEmailCode('person@example.test');
      final installationId = await credentials.readInstallationId();
      first.dispose();
      final restored = SessionController(
        api: api,
        credentialStore: credentials,
      );
      await restored.restore();
      expect(restored.phase, SessionPhase.loginPending);
      expect(restored.challenge?.email, 'person@example.test');
      expect(
        restored.challenge?.bindingToken,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(await credentials.readInstallationId(), installationId);
      expect(api.requests, hasLength(1));
      restored.dispose();
    },
  );
}
