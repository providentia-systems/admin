import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CredentialStore {
  Future<Map<String, String>> readSession();
  Future<void> writeSession(Map<String, String> values);
  Future<void> clearSession();
  Future<Map<String, String>> readPendingLogin();
  Future<void> writePendingLogin(Map<String, String> values);
  Future<void> clearPendingLogin();
  Future<String?> readInstallationId();
  Future<void> writeInstallationId(String value);
}

final class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _prefix = 'providentia.admin.';
  // refreshExpiresAt, idleExpiresAt and refreshIdleTtlSeconds are nullable:
  // a durable trusted-device session has no inactivity ceiling, so those
  // bounds are persisted only when the backend actually issued them. A null
  // bound is represented by the key being absent from the keyring.
  static const _sessionKeys = <String>[
    'accessToken',
    'refreshToken',
    'sessionId',
    'deviceId',
    'installationId',
    'userId',
    'accessExpiresAt',
    'refreshExpiresAt',
    'idleExpiresAt',
    'refreshIdleTtlSeconds',
    'transport',
  ];
  static const _pendingKeys = <String>[
    'requestId',
    'pollToken',
    'codeVerifier',
    'state',
    'expiresAt',
    'pollIntervalSeconds',
  ];

  @override
  Future<void> clearSession() async {
    for (final key in _sessionKeys) {
      await _storage.delete(key: '$_prefix$key');
    }
  }

  @override
  Future<void> clearPendingLogin() async {
    for (final key in _pendingKeys) {
      await _storage.delete(key: '${_prefix}pending.$key');
    }
  }

  @override
  Future<String?> readInstallationId() =>
      _storage.read(key: '${_prefix}installationId');

  @override
  Future<Map<String, String>> readSession() async {
    final result = <String, String>{};
    for (final key in _sessionKeys) {
      final value = await _storage.read(key: '$_prefix$key');
      if (value != null) result[key] = value;
    }
    return result;
  }

  @override
  Future<Map<String, String>> readPendingLogin() async {
    final result = <String, String>{};
    for (final key in _pendingKeys) {
      final value = await _storage.read(key: '${_prefix}pending.$key');
      if (value != null) result[key] = value;
    }
    return result;
  }

  @override
  Future<void> writeInstallationId(String value) =>
      _storage.write(key: '${_prefix}installationId', value: value);

  @override
  Future<void> writeSession(Map<String, String> values) async {
    await clearSession();
    for (final entry in values.entries) {
      if (_sessionKeys.contains(entry.key) && entry.value.isNotEmpty) {
        await _storage.write(key: '$_prefix${entry.key}', value: entry.value);
      }
    }
  }

  @override
  Future<void> writePendingLogin(Map<String, String> values) async {
    await clearPendingLogin();
    for (final entry in values.entries) {
      if (_pendingKeys.contains(entry.key)) {
        await _storage.write(
          key: '${_prefix}pending.${entry.key}',
          value: entry.value,
        );
      }
    }
  }
}
