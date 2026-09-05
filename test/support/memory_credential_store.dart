import 'package:providentia_admin/core/auth/credential_store.dart';

final class MemoryCredentialStore implements CredentialStore {
  MemoryCredentialStore({this.installationId});

  String? installationId;
  Map<String, String> session = <String, String>{};
  Map<String, String> pending = <String, String>{};

  @override
  Future<void> clearSession() async => session.clear();

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
  Future<void> writeSession(Map<String, String> values) async =>
      session = Map.of(values);

  @override
  Future<void> writePendingLogin(Map<String, String> values) async =>
      pending = Map.of(values);
}

const String memoryInstallationId = '44444444-4444-4444-8444-444444444444';

Map<String, String> memoryStoredSession() => <String, String>{
  'accessToken': 'access-token',
  'refreshToken': 'refresh-token',
  'sessionId': '0198f4e2-7abc-7def-8abc-0123456789ab',
  'deviceId': '22222222-2222-4222-8222-222222222222',
  'installationId': memoryInstallationId,
  'userId': '0198f4e3-7abc-7def-8abc-0123456789ab',
  'accessExpiresAt': _fixtureAccessExpiry,
  'refreshExpiresAt': '2026-10-01T00:00:00Z',
  'idleExpiresAt': '2026-10-01T00:00:00Z',
  'refreshIdleTtlSeconds': '2592000',
  'transport': 'native',
};
