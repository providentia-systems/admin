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
      if (_installationId == null || !_isUuid(_installationId!)) {
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
    if (_challenge != null || _phase == SessionPhase.loginPending) {
      throw StateError('An administrator sign-in request is already pending.');
    }
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
    late Map<String, Object?> statusJson;
    Object? status;
    DateTime statusExpiresAt;
    try {
      statusJson = statusResponse.jsonObject;
      status = statusJson['status'];
      statusExpiresAt = DateTime.parse(
        statusJson['expiresAt']! as String,
      ).toUtc();
    } on Object {
      await _invalidatePendingLogin(
        'The administrator sign-in request could not be verified.',
      );
      throw const FormatException('Login status binding mismatch.');
    }
    const statuses = <String>{
      'pending',
      'approved',
      'denied',
      'exchanged',
      'expired',
      'cancelled',
    };
    final expiryDrift = statusExpiresAt
        .difference(current.expiresAt.toUtc())
        .inMilliseconds
        .abs();
    if (statusJson['requestId'] != current.requestId ||
        statusJson['applicationKind'] != 'admin' ||
        status is! String ||
        !statuses.contains(status) ||
        expiryDrift > const Duration(seconds: 1).inMilliseconds) {
      await _invalidatePendingLogin(
        'The administrator sign-in request could not be verified.',
      );
      throw const FormatException('Login status binding mismatch.');
    }
    if (status == 'pending') return false;
    if (status != 'approved') {
      await _invalidatePendingLogin(
        'The administrator sign-in request is no longer active.',
      );
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
      try {
        await _discardCredentials(exchange.jsonObject);
      } on Object {
        // A stale response is never trusted or allowed to reactivate state.
      }
      return false;
    }
    try {
      final credentials = exchange.jsonObject;
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
        'The administrator session could not be established.',
      );
      rethrow;
    }
  }

  Future<void> cancelLoginLink() async {
    final current = _challenge;
    final refreshToken = _refreshToken;
    _clearMemory(null);
    notifyListeners();
    await _clearStoredCredentialMaterial();
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
    if (refreshToken != null) {
      try {
        await _api.postPublic(
          '/api/v1/auth/logout',
          body: <String, Object?>{'refreshToken': refreshToken},
        );
      } on Object {
        // The newly exchanged session is already destroyed locally.
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

  Future<void> _bootstrapAuthorization({int? expectedSessionEpoch}) async {
    final epoch = expectedSessionEpoch ?? _sessionEpoch;
    final response = await _api.get('/api/v1/me');
    if (epoch != _sessionEpoch || _accessToken == null) return;
    final json = response.jsonObject;
    final bootstrapUserId = json['userId'];
    if (bootstrapUserId is! String ||
        !_isUuid(bootstrapUserId) ||
        bootstrapUserId != _userId) {
      await _purgeSession(
        'The administrator identity binding could not be verified.',
      );
      return;
    }
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
      final requestId = values['requestId']!;
      final pollToken = values['pollToken']!;
      final codeVerifier = values['codeVerifier']!;
      final state = values['state']!;
      final now = DateTime.now().toUtc();
      if (!_isUuid(requestId) ||
          !_isBase64UrlSecret(pollToken, minimum: 43, maximum: 128) ||
          !_isBase64UrlSecret(codeVerifier, minimum: 43, maximum: 128) ||
          !_isBase64UrlSecret(state, minimum: 32, maximum: 256) ||
          interval < 1 ||
          interval > 30 ||
          !expiresAt.toUtc().isAfter(now) ||
          expiresAt.toUtc().isAfter(now.add(const Duration(hours: 1)))) {
        throw const FormatException('Stored login challenge was malformed.');
      }
      final challenge = LoginLinkChallenge(
        requestId: requestId,
        pollToken: pollToken,
        codeVerifier: codeVerifier,
        state: state,
        expiresAt: expiresAt,
        pollInterval: Duration(seconds: interval),
      );
      _challenge = challenge;
      _phase = SessionPhase.loginPending;
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

  Future<bool> _establishSession(
    Map<String, Object?> credentials, {
    required int expectedLoginEpoch,
    required LoginLinkChallenge expectedChallenge,
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

  static bool _isBase64UrlSecret(
    String value, {
    required int minimum,
    required int maximum,
  }) =>
      value.length >= minimum &&
      value.length <= maximum &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

  static String _secret(int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _challengeFor(String value) => base64Url
      .encode(sha256.convert(ascii.encode(value)).bytes)
      .replaceAll('=', '');
}
