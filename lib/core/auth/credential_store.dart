import 'dart:convert';

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
    'refreshState',
  ];
  static const _pendingKeys = <String>[
    'challengeId',
    'bindingToken',
    'email',
    'expiresAt',
    'resendAt',
  ];

  @override
  Future<void> clearSession() => _storage.delete(key: '${_prefix}session');

  @override
  Future<void> clearPendingLogin() =>
      _storage.delete(key: '${_prefix}pendingLogin');

  @override
  Future<String?> readInstallationId() =>
      _storage.read(key: '${_prefix}installationId');

  @override
  Future<Map<String, String>> readSession() =>
      _readEnvelope('session', _sessionKeys);

  @override
  Future<Map<String, String>> readPendingLogin() =>
      _readEnvelope('pendingLogin', _pendingKeys);

  Future<Map<String, String>> _readEnvelope(
    String name,
    List<String> allowed,
  ) async {
    final stored = await _storage.read(key: '$_prefix$name');
    if (stored == null) return <String, String>{};
    final decoded = jsonDecode(stored);
    if (decoded is! Map<String, Object?> ||
        decoded.values.any((value) => value is! String)) {
      throw const FormatException('Stored credential envelope is malformed.');
    }
    return <String, String>{
      for (final entry in decoded.entries)
        if (allowed.contains(entry.key) && (entry.value! as String).isNotEmpty)
          entry.key: entry.value! as String,
    };
  }

  @override
  Future<void> writeInstallationId(String value) =>
      _storage.write(key: '${_prefix}installationId', value: value);

  @override
  Future<void> writeSession(Map<String, String> values) =>
      _writeEnvelope('session', values, _sessionKeys);

  @override
  Future<void> writePendingLogin(Map<String, String> values) =>
      _writeEnvelope('pendingLogin', values, _pendingKeys);

  Future<void> _writeEnvelope(
    String name,
    Map<String, String> values,
    List<String> allowed,
  ) => _storage.write(
    key: '$_prefix$name',
    value: jsonEncode(<String, String>{
      for (final entry in values.entries)
        if (allowed.contains(entry.key) && entry.value.isNotEmpty)
          entry.key: entry.value,
    }),
  );
}
