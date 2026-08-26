import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/auth/credential_store.dart';

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
      'requestId': memoryInstallationId,
      'pollToken': 'poll-token',
      'ignored': 'never-stored',
    });

    expect(await store.readInstallationId(), memoryInstallationId);
    final pending = await store.readPendingLogin();
    expect(pending['requestId'], memoryInstallationId);
    expect(pending['pollToken'], 'poll-token');
    expect(pending.containsKey('ignored'), isFalse);
    expect(storage.values.keys, everyElement(startsWith('providentia.admin.')));

    await store.clearPendingLogin();
    expect(await store.readPendingLogin(), isEmpty);
    expect(await store.readInstallationId(), memoryInstallationId);
  });
}
