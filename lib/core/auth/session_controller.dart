import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../security/secure_id.dart';
import 'credential_store.dart';
import 'operator_authorization.dart';

enum SessionPhase { restoring, signedOut, loginPending, authenticated }

final class EmailCodeChallenge {
  const EmailCodeChallenge({
    required this.challengeId,
    required this.bindingToken,
    required this.email,
    required this.expiresAt,
    required this.resendAt,
  });
  final String challengeId;
  final String bindingToken;
  final String email;
  final DateTime expiresAt;
  final DateTime resendAt;
}

final class SessionController extends ChangeNotifier {
  factory SessionController({
    required AdminApi api,
    required CredentialStore credentialStore,
  }) => SessionController._(api, credentialStore);

  SessionController._(this._api, this._credentialStore);

  final AdminApi _api;
  final CredentialStore _credentialStore;

  SessionPhase _phase = SessionPhase.restoring;
  OperatorAuthorization _authorization = OperatorAuthorization.none;
  String? _accessToken;
  String? _refreshToken;
  String? _sessionId;
  String? _deviceId;
  String? _installationId;
  String? _userId;
  DateTime? _accessExpiresAt;
  DateTime? _refreshExpiresAt;
  DateTime? _idleExpiresAt;
  EmailCodeChallenge? _challenge;
  String? _error;
  Map<String, Object?> _profile = const <String, Object?>{};
  Map<String, Object?> get profile => _profile;
  Future<void> reloadProfile() => _bootstrapAuthorization();
  int _authorizationEpoch = 0;
  int _sessionEpoch = 0;
  int _loginEpoch = 0;
  Future<bool>? _refreshInFlight;

  SessionPhase get phase => _phase;
  OperatorAuthorization get authorization => _authorization;
  String? get accessToken => _accessToken;
  String? get userId => _userId;
  EmailCodeChallenge? get challenge => _challenge;
  String? get error => _error;
  int get authorizationEpoch => _authorizationEpoch;

  Future<void> restore() async {
    _phase = SessionPhase.restoring;
    _error = null;
    notifyListeners();
    try {
      _installationId = await _credentialStore.readInstallationId();
      if (_installationId == null || !isUuid(_installationId!)) {
        _installationId = newUuidV4();
        await _credentialStore.writeInstallationId(_installationId!);
      }
      final stored = await _credentialStore.readSession();
      if (stored.isEmpty) {
        await _restorePendingLogin();
        return;
      }
      if (!_hasAtomicSession(stored)) {
        await _purgeSession(
          'Stored administrator credentials were incomplete.',
        );
        return;
      }
      _activateSession(stored);
      await _bootstrapAuthorization();
    } on Object {
      await _purgeSession('Your administrator session must be renewed.');
    }
  }

  Future<void> requestEmailCode(String email) async {
    final loginEpoch = ++_loginEpoch;
    _error = null;
    final installationId = _installationId ?? newUuidV4();
    _installationId = installationId;
    await _credentialStore.writeInstallationId(installationId);
    final response = await _api.postPublic(
      '/api/v1/auth/email-codes',
      body: <String, Object?>{
        'email': email.trim(),
        'applicationKind': 'admin',
        'installationId': installationId,
        'deviceName': 'Providentia Admin for Linux',
        'platform': 'linux',
        'transport': 'native',
      },
    );
    if (loginEpoch != _loginEpoch) return;
    final json = response.jsonObject;
    final challenge = EmailCodeChallenge(
      challengeId: json['challengeId']! as String,
      bindingToken: json['bindingToken']! as String,
      email: email.trim(),
      expiresAt: DateTime.parse(json['expiresAt']! as String).toUtc(),
      resendAt: DateTime.now().toUtc().add(
        Duration(seconds: json['resendAfterSeconds']! as int),
      ),
    );
    if (!isUuid(challenge.challengeId) ||
        !_isBase64UrlSecret(
          challenge.bindingToken,
          minimum: 40,
          maximum: 128,
        )) {
      throw const FormatException('Invalid email verification response.');
    }
    await _credentialStore.writePendingLogin(<String, String>{
      'challengeId': challenge.challengeId,
      'bindingToken': challenge.bindingToken,
      'email': challenge.email,
      'expiresAt': challenge.expiresAt.toIso8601String(),
      'resendAt': challenge.resendAt.toIso8601String(),
    });
    if (loginEpoch != _loginEpoch) {
      await _credentialStore.clearPendingLogin();
      return;
    }
    _challenge = challenge;
    _phase = SessionPhase.loginPending;
    notifyListeners();
  }

  Future<bool> verifyEmailCode(String code) async {
    final current = _challenge;
    if (current == null) return false;
    if (!RegExp(r'^[0-9]{8}$').hasMatch(code)) {
      throw const FormatException('Enter the eight-digit email code.');
    }
    final loginEpoch = _loginEpoch;
    final response = await _api.postPublic(
      '/api/v1/auth/email-codes/verify',
      body: <String, Object?>{
        'challengeId': current.challengeId,
        'bindingToken': current.bindingToken,
        'code': code,
      },
    );
    final credentials = response.jsonObject;
    if (loginEpoch != _loginEpoch || !identical(current, _challenge)) {
      await _discardCredentials(credentials);
      return false;
    }
    try {
      final established = await _establishSession(
        credentials,
        expectedLoginEpoch: loginEpoch,
        expectedChallenge: current,
      );
      if (!established) {
        await _discardCredentials(credentials);
        return false;
      }
      await _bootstrapAuthorization(expectedSessionEpoch: _sessionEpoch);
      return _phase == SessionPhase.authenticated;
    } on Object {
      await _purgeSession(
        'The administrator session could not be established. Request a new code.',
      );
      rethrow;
    }
  }

  Future<void> cancelEmailCode() async {
    ++_loginEpoch;
    _challenge = null;
    _phase = SessionPhase.signedOut;
    _error = null;
    notifyListeners();
    await _credentialStore.clearPendingLogin();
  }

  Future<void> signOut() async {
    final refresh = _refreshToken;
    // Revoke local authorization before the first await. A late refresh or a
    // slow logout transport must never keep privileged widgets alive.
    _clearMemory(null);
    notifyListeners();
    try {
      await _api.postPublic(
        '/api/v1/auth/logout',
        body: refresh == null
            ? null
            : <String, Object?>{'refreshToken': refresh},
      );
    } on Object {
      // Local credential destruction does not depend on network success.
    } finally {
      await _clearStoredCredentialMaterial();
    }
  }

  void authorizationLost() {
    // This synchronous state transition prevents stale privileged widgets from
    // emitting after a 401/403 while secure-storage cleanup completes.
    _clearMemory('Administrator authorization was lost. Sign in again.');
    notifyListeners();
    unawaited(_clearStoredCredentialMaterial());
  }

  Future<bool> ensureFreshAccessToken({bool force = false}) {
    final accessToken = _accessToken;
    final refreshToken = _refreshToken;
    final accessExpiresAt = _accessExpiresAt;
    if (accessToken == null ||
        refreshToken == null ||
        accessExpiresAt == null) {
      return Future<bool>.value(false);
    }

    // A durable trusted-device session has null expiry bounds and lives until
    // explicit sign-out, revocation, or an account-level invalidation.
    final now = DateTime.now().toUtc();
    final refreshExpiresAt = _refreshExpiresAt;
    final idleExpiresAt = _idleExpiresAt;
    if ((refreshExpiresAt != null && !refreshExpiresAt.isAfter(now)) ||
        (idleExpiresAt != null && !idleExpiresAt.isAfter(now))) {
      authorizationLost();
      return Future<bool>.value(false);
    }
    if (!force &&
        accessExpiresAt.isAfter(now.add(const Duration(minutes: 1)))) {
      return Future<bool>.value(true);
    }

    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final epoch = _sessionEpoch;
    late final Future<bool> refresh;
    refresh = _rotateSession(epoch).whenComplete(() {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    });
    _refreshInFlight = refresh;
    return refresh;
  }

  Future<void> refreshAuthorization() => _bootstrapAuthorization();

  Future<bool> _rotateSession(int epoch) async {
    final refreshToken = _refreshToken;
    final expectedSessionId = _sessionId;
    final expectedDeviceId = _deviceId;
    final expectedUserId = _userId;
    if (refreshToken == null ||
        expectedSessionId == null ||
        expectedDeviceId == null ||
        expectedUserId == null) {
      return false;
    }
    try {
      final response = await _api.postPublic(
        '/api/v1/auth/refresh',
        body: <String, Object?>{'refreshToken': refreshToken},
      );
      if (epoch != _sessionEpoch) return false;
      final values = _credentialValues(response.jsonObject);
      _validateSession(
        values,
        expectedSessionId: expectedSessionId,
        expectedDeviceId: expectedDeviceId,
        expectedUserId: expectedUserId,
      );
      await _credentialStore.writeSession(values);
      if (epoch != _sessionEpoch) {
        await _credentialStore.clearSession();
        return false;
      }
      _activateSession(values);
      return true;
    } on Object {
      if (epoch == _sessionEpoch) {
        await _purgeSession('Your administrator session must be renewed.');
      }
      return false;
    }
  }

  Future<void> _bootstrapAuthorization({int? expectedSessionEpoch}) async {
    final epoch = expectedSessionEpoch ?? _sessionEpoch;
    final response = await _api.get('/api/v1/me');
    if (epoch != _sessionEpoch || _accessToken == null) return;
    final json = response.jsonObject;
    final bootstrapUserId = json['userId'];
    if (bootstrapUserId is! String ||
        !isUuid(bootstrapUserId) ||
        bootstrapUserId != _userId) {
      await _purgeSession(
        'The administrator identity binding could not be verified.',
      );
      return;
    }
    final profile =
        json['profile'] as Map<String, Object?>? ?? const <String, Object?>{};
    _profile = profile;
    final access =
        profile['administratorAccess'] as Map<String, Object?>? ??
        const <String, Object?>{};
    final features =
        access['features'] as Map<String, Object?>? ??
        const <String, Object?>{};
    final authorization = OperatorAuthorization.fromPermissions(
      features.entries
          .where((entry) => entry.value == true)
          .map((entry) => entry.key),
    );
    if (!setEquals(_authorization.permissions, authorization.permissions)) {
      _authorizationEpoch += 1;
    }
    _authorization = authorization;
    _phase = SessionPhase.authenticated;
    _error = null;
    notifyListeners();
  }

  Future<void> _purgeSession(String? message) async {
    _clearMemory(message);
    notifyListeners();
    await _clearStoredCredentialMaterial();
  }

  void _clearMemory(String? message) {
    final hadSensitiveState =
        _accessToken != null ||
        _refreshToken != null ||
        _authorization.isOperator ||
        _challenge != null;
    if (hadSensitiveState) {
      _authorizationEpoch += 1;
      _sessionEpoch += 1;
      _loginEpoch += 1;
    }
    _profile = const <String, Object?>{};
    _accessToken = null;
    _refreshToken = null;
    _sessionId = null;
    _deviceId = null;
    _userId = null;
    _accessExpiresAt = null;
    _refreshExpiresAt = null;
    _idleExpiresAt = null;
    _refreshInFlight = null;
    _authorization = OperatorAuthorization.none;
    _challenge = null;
    _phase = SessionPhase.signedOut;
    _error = message;
  }

  Future<bool> _clearStoredCredentialMaterial() async {
    var cleared = true;
    try {
      await _credentialStore.clearSession();
    } on Object {
      cleared = false;
    }
    try {
      await _credentialStore.clearPendingLogin();
    } on Object {
      cleared = false;
    }
    if (!cleared) {
      _error = 'The system keyring could not clear stored credentials.';
      notifyListeners();
    }
    return cleared;
  }

  Future<void> _restorePendingLogin() async {
    final values = await _credentialStore.readPendingLogin();
    try {
      if (values.isEmpty) {
        _phase = SessionPhase.signedOut;
      } else {
        final challenge = EmailCodeChallenge(
          challengeId: values['challengeId']!,
          bindingToken: values['bindingToken']!,
          email: values['email']!,
          expiresAt: DateTime.parse(values['expiresAt']!),
          resendAt: DateTime.parse(values['resendAt']!),
        );
        if (!isUuid(challenge.challengeId) ||
            !_isBase64UrlSecret(
              challenge.bindingToken,
              minimum: 40,
              maximum: 128,
            ) ||
            !challenge.expiresAt.isAfter(DateTime.now().toUtc())) {
          throw const FormatException('Stored code request expired.');
        }
        _challenge = challenge;
        _phase = SessionPhase.loginPending;
      }
    } on Object {
      await _credentialStore.clearPendingLogin();
      _phase = SessionPhase.signedOut;
    }
    notifyListeners();
  }

  Future<bool> _establishSession(
    Map<String, Object?> credentials, {
    required int expectedLoginEpoch,
    required EmailCodeChallenge expectedChallenge,
  }) async {
    final values = _credentialValues(credentials);
    _validateSession(values);
    await _credentialStore.writeSession(values);
    if (expectedLoginEpoch != _loginEpoch ||
        !identical(expectedChallenge, _challenge)) {
      await _credentialStore.clearSession();
      return false;
    }
    await _credentialStore.clearPendingLogin();
    if (expectedLoginEpoch != _loginEpoch ||
        !identical(expectedChallenge, _challenge)) {
      await _credentialStore.clearSession();
      return false;
    }
    _challenge = null;
    _sessionEpoch += 1;
    _activateSession(values);
    return true;
  }

  void _activateSession(Map<String, String> values) {
    _validateSession(values);
    _accessToken = values['accessToken'];
    _refreshToken = values['refreshToken'];
    _sessionId = values['sessionId'];
    _deviceId = values['deviceId'];
    _userId = values['userId'];
    _accessExpiresAt = DateTime.parse(values['accessExpiresAt']!).toUtc();
    final refreshExpiresAt = _durableBound(values, 'refreshExpiresAt');
    final idleExpiresAt = _durableBound(values, 'idleExpiresAt');
    _refreshExpiresAt = refreshExpiresAt == null
        ? null
        : DateTime.parse(refreshExpiresAt).toUtc();
    _idleExpiresAt = idleExpiresAt == null
        ? null
        : DateTime.parse(idleExpiresAt).toUtc();
  }

  void _validateSession(
    Map<String, String> values, {
    String? expectedSessionId,
    String? expectedDeviceId,
    String? expectedUserId,
  }) {
    if (!_hasAtomicSession(values)) {
      throw const FormatException('Native session credentials are incomplete.');
    }
    if (values['installationId'] != _installationId ||
        values['transport'] != 'native') {
      throw const FormatException('Session installation binding mismatch.');
    }
    for (final key in <String>[
      'sessionId',
      'deviceId',
      'installationId',
      'userId',
    ]) {
      if (!isUuid(values[key]!)) {
        throw const FormatException('Session identifier was malformed.');
      }
    }
    if ((expectedSessionId != null &&
            values['sessionId'] != expectedSessionId) ||
        (expectedDeviceId != null && values['deviceId'] != expectedDeviceId) ||
        (expectedUserId != null && values['userId'] != expectedUserId)) {
      throw const FormatException('Rotated session binding mismatch.');
    }
    final access = DateTime.parse(values['accessExpiresAt']!).toUtc();
    // Durable trusted-device sessions null every inactivity bound together;
    // a bounded session carries all three. Any mixed shape is corrupt.
    final refreshExpiresAt = _durableBound(values, 'refreshExpiresAt');
    final idleExpiresAt = _durableBound(values, 'idleExpiresAt');
    final refreshIdleTtlSeconds = _durableBound(
      values,
      'refreshIdleTtlSeconds',
    );
    final bounds = <String?>[
      refreshExpiresAt,
      idleExpiresAt,
      refreshIdleTtlSeconds,
    ];
    final boundedCount = bounds.whereType<String>().length;
    if (boundedCount != 0 && boundedCount != bounds.length) {
      throw const FormatException('Session idle bounds were incoherent.');
    }
    if (boundedCount == 0) return;
    final refresh = DateTime.parse(refreshExpiresAt!).toUtc();
    final idle = DateTime.parse(idleExpiresAt!).toUtc();
    final now = DateTime.now().toUtc();
    if (!refresh.isAfter(now) ||
        !idle.isAfter(now) ||
        access.isAfter(refresh)) {
      throw const FormatException('Session expiry bounds were invalid.');
    }
    final idleTtl = int.tryParse(refreshIdleTtlSeconds!);
    if (idleTtl == null || idleTtl < 900 || idleTtl > 5184000) {
      throw const FormatException('Session idle bound was invalid.');
    }
  }

  Future<void> _discardCredentials(Map<String, Object?> credentials) async {
    final refreshToken = credentials['refreshToken'];
    if (refreshToken is! String || refreshToken.isEmpty) return;
    try {
      await _api.postPublic(
        '/api/v1/auth/logout',
        body: <String, Object?>{'refreshToken': refreshToken},
      );
    } on Object {
      // The stale exchange result is never activated or persisted locally.
    }
  }

  static Map<String, String> _credentialValues(
    Map<String, Object?> credentials,
  ) => credentials.map(
    (key, value) => MapEntry(key, value == null ? '' : value.toString()),
  );

  static bool _hasAtomicSession(Map<String, String> values) {
    // refreshExpiresAt, idleExpiresAt and refreshIdleTtlSeconds are absent (or
    // empty) for a durable trusted-device session; _validateSession rejects
    // any partially bounded tuple.
    const required = <String>{
      'accessToken',
      'refreshToken',
      'sessionId',
      'deviceId',
      'installationId',
      'userId',
      'accessExpiresAt',
      'transport',
    };
    return required.every((key) => values[key]?.isNotEmpty ?? false);
  }

  /// Normalizes a nullable session bound: the wire maps `null` to an empty
  /// string and the credential store omits the key entirely.
  static String? _durableBound(Map<String, String> values, String key) {
    final value = values[key];
    return (value == null || value.isEmpty) ? null : value;
  }

  static bool _isBase64UrlSecret(
    String value, {
    required int minimum,
    required int maximum,
  }) =>
      value.length >= minimum &&
      value.length <= maximum &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
}
