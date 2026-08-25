import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../security/secure_id.dart';
import 'credential_store.dart';
import 'operator_authorization.dart';

enum SessionPhase { restoring, signedOut, loginPending, authenticated }

final class LoginLinkChallenge {
  const LoginLinkChallenge({
    required this.requestId,
    required this.pollToken,
    required this.codeVerifier,
    required this.state,
    required this.expiresAt,
    required this.pollInterval,
  });

  final String requestId;
  final String pollToken;
  final String codeVerifier;
  final String state;
  final DateTime expiresAt;
  final Duration pollInterval;
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
  LoginLinkChallenge? _challenge;
  String? _error;
  int _authorizationEpoch = 0;
  int _sessionEpoch = 0;
  int _loginEpoch = 0;
  Future<bool>? _refreshInFlight;

  SessionPhase get phase => _phase;
  OperatorAuthorization get authorization => _authorization;
  String? get accessToken => _accessToken;
  String? get userId => _userId;
  LoginLinkChallenge? get challenge => _challenge;
  String? get error => _error;
  int get authorizationEpoch => _authorizationEpoch;

  Future<void> restore() async {
    _phase = SessionPhase.restoring;
    _error = null;
    notifyListeners();
    try {
      _installationId = await _credentialStore.readInstallationId();
      if (_installationId == null) {
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

  Future<void> startLoginLink(String email) async {
    final loginEpoch = ++_loginEpoch;
    _error = null;
    final installationId = _installationId ?? newUuidV4();
    _installationId = installationId;
    await _credentialStore.writeInstallationId(installationId);
    final requestId = newUuidV4();
    final pollToken = _secret(32);
    final verifier = _secret(64);
    final state = _secret(32);
    final response = await _api.postPublic(
      '/api/v1/auth/login-links',
      body: <String, Object?>{
        'requestId': requestId,
        'email': email.trim(),
        'applicationKind': 'admin',
        'pollChallenge': _challengeFor(pollToken),
        'codeChallenge': _challengeFor(verifier),
        'codeChallengeMethod': 'S256',
        'state': state,
        'installationId': installationId,
        'deviceName': 'Providentia Admin for Linux',
        'platform': 'linux',
        'transport': 'native',
      },
    );
    if (loginEpoch != _loginEpoch) return;
    final json = response.jsonObject;
    final serverRequestId = json['requestId'];
    final expiresAt = DateTime.parse(json['expiresAt']! as String).toUtc();
    final pollIntervalSeconds = json['pollIntervalSeconds'];
    final now = DateTime.now().toUtc();
    if (json['accepted'] != true ||
        serverRequestId != requestId ||
        pollIntervalSeconds is! int ||
        pollIntervalSeconds < 1 ||
        pollIntervalSeconds > 30 ||
        !expiresAt.isAfter(now) ||
        expiresAt.isAfter(now.add(const Duration(hours: 1)))) {
      throw const FormatException('Login request binding was not preserved.');
    }
    final challenge = LoginLinkChallenge(
      requestId: requestId,
      pollToken: pollToken,
      codeVerifier: verifier,
      state: state,
      expiresAt: expiresAt,
      pollInterval: Duration(seconds: pollIntervalSeconds),
    );
    await _credentialStore.writePendingLogin(<String, String>{
      'requestId': challenge.requestId,
      'pollToken': challenge.pollToken,
      'codeVerifier': challenge.codeVerifier,
      'state': challenge.state,
      'expiresAt': challenge.expiresAt.toUtc().toIso8601String(),
      'pollIntervalSeconds': '${challenge.pollInterval.inSeconds}',
    });
    if (loginEpoch != _loginEpoch) {
      await _credentialStore.clearPendingLogin();
      return;
    }
    _challenge = challenge;
    _phase = SessionPhase.loginPending;
    notifyListeners();
  }

  Future<bool> pollLoginLink() async {
    final current = _challenge;
    if (current == null) return false;
    final loginEpoch = _loginEpoch;
    if (DateTime.now().toUtc().isAfter(current.expiresAt.toUtc())) {
      await cancelLoginLink();
      _error = 'The sign-in link expired. Request a new link.';
      notifyListeners();
      return false;
    }
    final statusResponse = await _api.postPublic(
      '/api/v1/auth/login-links/${current.requestId}/status',
      body: <String, Object?>{'pollToken': current.pollToken},
    );
    if (loginEpoch != _loginEpoch || !identical(current, _challenge)) {
      return false;
    }
    final statusJson = statusResponse.jsonObject;
    final statusExpiresAt = DateTime.parse(
      statusJson['expiresAt']! as String,
    ).toUtc();
    if (statusJson['requestId'] != current.requestId ||
        statusJson['applicationKind'] != 'admin' ||
        statusExpiresAt.isAfter(
          current.expiresAt.toUtc().add(const Duration(seconds: 1)),
        )) {
      await _invalidatePendingLogin(
        'The administrator sign-in request could not be verified.',
      );
      throw const FormatException('Login status binding mismatch.');
    }
    final status = statusJson['status'];
    if (status == 'pending') return false;
    if (status != 'approved') {
      _challenge = null;
      await _credentialStore.clearPendingLogin();
      _phase = SessionPhase.signedOut;
      _error = 'The sign-in request was $status.';
      notifyListeners();
      return false;
    }

    final exchange = await _api.postPublic(
      '/api/v1/auth/login-links/${current.requestId}/exchange',
      body: <String, Object?>{
        'pollToken': current.pollToken,
        'codeVerifier': current.codeVerifier,
        'state': current.state,
      },
    );
    if (loginEpoch != _loginEpoch || !identical(current, _challenge)) {
      await _discardCredentials(exchange.jsonObject);
      return false;
    }
    final credentials = exchange.jsonObject;
    if (credentials['installationId'] != _installationId) {
      throw const FormatException('Session installation binding mismatch.');
    }
    try {
      await _establishSession(credentials);
      await _credentialStore.clearPendingLogin();
      _challenge = null;
      await _bootstrapAuthorization();
      return _phase == SessionPhase.authenticated;
    } on Object {
      await _purgeSession(
        'The administrator session could not be established.',
      );
      rethrow;
    }
  }

  Future<void> cancelLoginLink() async {
    final current = _challenge;
    _loginEpoch += 1;
    _challenge = null;
    _phase = SessionPhase.signedOut;
    notifyListeners();
    await _credentialStore.clearPendingLogin();
    if (current != null) {
      try {
        await _api.postPublic(
          '/api/v1/auth/login-links/${current.requestId}/cancel',
          body: <String, Object?>{'pollToken': current.pollToken},
        );
      } on Object {
        // Local cancellation is authoritative for this installation.
      }
    }
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
    final refreshExpiresAt = _refreshExpiresAt;
    final idleExpiresAt = _idleExpiresAt;
    if (accessToken == null ||
        refreshToken == null ||
        accessExpiresAt == null ||
        refreshExpiresAt == null ||
        idleExpiresAt == null) {
      return Future<bool>.value(false);
    }

    final now = DateTime.now().toUtc();
    if (!refreshExpiresAt.isAfter(now) || !idleExpiresAt.isAfter(now)) {
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

  Future<void> _bootstrapAuthorization() async {
    final response = await _api.get('/api/v1/me');
    final json = response.jsonObject;
    final wireRoles = json['platformRoles'];
    final authorization = OperatorAuthorization.fromWire(
      wireRoles is List<Object?> ? wireRoles : const <Object?>[],
    );
    if (!authorization.isOperator) {
      await _purgeSession('This account has no Providentia operator role.');
      return;
    }
    if (!setEquals(_authorization.roles, authorization.roles)) {
      _authorizationEpoch += 1;
    }
    _authorization = authorization;
    _userId = json['userId'] as String? ?? _userId;
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

  Future<void> _clearStoredCredentialMaterial() async {
    try {
      await _credentialStore.clearSession();
      await _credentialStore.clearPendingLogin();
    } on Object {
      _error = 'The system keyring could not clear stored credentials.';
      notifyListeners();
    }
  }

  Future<void> _restorePendingLogin() async {
    final values = await _credentialStore.readPendingLogin();
    if (values.isEmpty) {
      _phase = SessionPhase.signedOut;
      _authorization = OperatorAuthorization.none;
      notifyListeners();
      return;
    }
    try {
      final expiresAt = DateTime.parse(values['expiresAt']!);
      final interval = int.parse(values['pollIntervalSeconds']!);
      final challenge = LoginLinkChallenge(
        requestId: values['requestId']!,
        pollToken: values['pollToken']!,
        codeVerifier: values['codeVerifier']!,
        state: values['state']!,
        expiresAt: expiresAt,
        pollInterval: Duration(seconds: interval),
      );
      if (DateTime.now().toUtc().isAfter(expiresAt.toUtc())) {
        await _credentialStore.clearPendingLogin();
        _phase = SessionPhase.signedOut;
      } else {
        _challenge = challenge;
        _phase = SessionPhase.loginPending;
      }
      notifyListeners();
    } on Object {
      await _credentialStore.clearPendingLogin();
      _phase = SessionPhase.signedOut;
      notifyListeners();
    }
  }

  Future<void> _invalidatePendingLogin(String message) async {
    _loginEpoch += 1;
    _challenge = null;
    _phase = SessionPhase.signedOut;
    _error = message;
    notifyListeners();
    await _credentialStore.clearPendingLogin();
  }

  Future<void> _establishSession(Map<String, Object?> credentials) async {
    final values = _credentialValues(credentials);
    _validateSession(values);
    await _credentialStore.writeSession(values);
    _sessionEpoch += 1;
    _activateSession(values);
  }

  void _activateSession(Map<String, String> values) {
    _validateSession(values);
    _accessToken = values['accessToken'];
    _refreshToken = values['refreshToken'];
    _sessionId = values['sessionId'];
    _deviceId = values['deviceId'];
    _userId = values['userId'];
    _accessExpiresAt = DateTime.parse(values['accessExpiresAt']!).toUtc();
    _refreshExpiresAt = DateTime.parse(values['refreshExpiresAt']!).toUtc();
    _idleExpiresAt = DateTime.parse(values['idleExpiresAt']!).toUtc();
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
      if (!_isUuid(values[key]!)) {
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
    final refresh = DateTime.parse(values['refreshExpiresAt']!).toUtc();
    final idle = DateTime.parse(values['idleExpiresAt']!).toUtc();
    final now = DateTime.now().toUtc();
    if (!refresh.isAfter(now) ||
        !idle.isAfter(now) ||
        access.isAfter(refresh)) {
      throw const FormatException('Session expiry bounds were invalid.');
    }
    final idleTtl = int.parse(values['refreshIdleTtlSeconds']!);
    if (idleTtl < 900 || idleTtl > 5184000) {
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
    const required = <String>{
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
    };
    return required.every((key) => values[key]?.isNotEmpty ?? false);
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  static String _secret(int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _challengeFor(String value) => base64Url
      .encode(sha256.convert(ascii.encode(value)).bytes)
      .replaceAll('=', '');
}
