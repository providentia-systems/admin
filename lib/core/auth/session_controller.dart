import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
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
  SessionController({
    required AdminApi api,
    required CredentialStore credentialStore,
    Uuid uuid = const Uuid(),
  }) : _api = api,
       _credentialStore = credentialStore,
       _uuid = uuid;

  final AdminApi _api;
  final CredentialStore _credentialStore;
  final Uuid _uuid;

  SessionPhase _phase = SessionPhase.restoring;
  OperatorAuthorization _authorization = OperatorAuthorization.none;
  String? _accessToken;
  String? _refreshToken;
  String? _installationId;
  String? _userId;
  LoginLinkChallenge? _challenge;
  String? _error;
  int _authorizationEpoch = 0;

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
    _installationId = await _credentialStore.readInstallationId();
    if (_installationId == null) {
      _installationId = _uuid.v4();
      await _credentialStore.writeInstallationId(_installationId!);
    }
    final stored = await _credentialStore.readSession();
    _accessToken = stored['accessToken'];
    _refreshToken = stored['refreshToken'];
    _userId = stored['userId'];
    if (_accessToken == null || _accessToken!.isEmpty) {
      _setSignedOut();
      return;
    }
    try {
      await _bootstrapAuthorization();
    } on Object catch (exception) {
      await _purgeSession('Your administrator session must be renewed.');
      if (kDebugMode) _error = exception.toString();
    }
  }

  Future<void> startLoginLink(String email) async {
    _error = null;
    final installationId = _installationId ?? _uuid.v4();
    _installationId = installationId;
    await _credentialStore.writeInstallationId(installationId);
    final requestId = _uuid.v4();
    final pollToken = _secret(32);
    final verifier = _secret(64);
    final state = _secret(32);
    final response = await _api.post(
      '/api/v1/auth/login-links',
      body: <String, Object?>{
        'requestId': requestId,
        'email': email.trim(),
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
    final json = response.jsonObject;
    final serverRequestId = json['requestId'];
    if (serverRequestId != requestId) {
      throw const FormatException('Login request binding was not preserved.');
    }
    _challenge = LoginLinkChallenge(
      requestId: requestId,
      pollToken: pollToken,
      codeVerifier: verifier,
      state: state,
      expiresAt: DateTime.parse(json['expiresAt']! as String),
      pollInterval: Duration(seconds: json['pollIntervalSeconds']! as int),
    );
    _phase = SessionPhase.loginPending;
    notifyListeners();
  }

  Future<bool> pollLoginLink() async {
    final current = _challenge;
    if (current == null) return false;
    if (DateTime.now().toUtc().isAfter(current.expiresAt.toUtc())) {
      await cancelLoginLink();
      _error = 'The sign-in link expired. Request a new link.';
      notifyListeners();
      return false;
    }
    final statusResponse = await _api.post(
      '/api/v1/auth/login-links/${current.requestId}/status',
      body: <String, Object?>{'pollToken': current.pollToken},
    );
    final status = statusResponse.jsonObject['status'];
    if (status == 'pending') return false;
    if (status != 'approved') {
      _challenge = null;
      _phase = SessionPhase.signedOut;
      _error = 'The sign-in request was $status.';
      notifyListeners();
      return false;
    }

    final exchange = await _api.post(
      '/api/v1/auth/login-links/${current.requestId}/exchange',
      body: <String, Object?>{
        'pollToken': current.pollToken,
        'codeVerifier': current.codeVerifier,
        'state': current.state,
      },
    );
    final credentials = exchange.jsonObject;
    if (credentials['installationId'] != _installationId) {
      throw const FormatException('Session installation binding mismatch.');
    }
    final accessToken = credentials['accessToken'];
    final refreshToken = credentials['refreshToken'];
    if (accessToken is! String || refreshToken is! String) {
      throw const FormatException('Native session credentials are incomplete.');
    }
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _userId = credentials['userId'] as String?;
    await _credentialStore.writeSession(
      credentials.map(
        (key, value) => MapEntry(key, value == null ? '' : value.toString()),
      ),
    );
    _challenge = null;
    await _bootstrapAuthorization();
    return true;
  }

  Future<void> cancelLoginLink() async {
    final current = _challenge;
    _challenge = null;
    _phase = SessionPhase.signedOut;
    notifyListeners();
    if (current != null) {
      try {
        await _api.post(
          '/api/v1/auth/login-links/${current.requestId}/cancel',
          body: <String, Object?>{'pollToken': current.pollToken},
        );
      } on ApiException {
        // Local cancellation is authoritative for this installation.
      }
    }
  }

  Future<void> signOut() async {
    final refresh = _refreshToken;
    try {
      await _api.post(
        '/api/v1/auth/logout',
        body: refresh == null ? null : <String, Object?>{'refreshToken': refresh},
      );
    } on ApiException {
      // Credentials are always removed locally even if server revocation fails.
    }
    await _purgeSession(null);
  }

  void authorizationLost() {
    // This synchronous state transition prevents stale privileged widgets from
    // emitting after a 401/403 while secure-storage cleanup completes.
    _authorizationEpoch += 1;
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
    _authorization = OperatorAuthorization.none;
    _challenge = null;
    _phase = SessionPhase.signedOut;
    _error = 'Administrator authorization was lost. Sign in again.';
    notifyListeners();
    unawaited(_credentialStore.clearSession());
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
    _authorization = authorization;
    _userId = json['userId'] as String? ?? _userId;
    _phase = SessionPhase.authenticated;
    _error = null;
    notifyListeners();
  }

  Future<void> _purgeSession(String? message) async {
    _authorizationEpoch += 1;
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
    _authorization = OperatorAuthorization.none;
    _challenge = null;
    _phase = SessionPhase.signedOut;
    _error = message;
    await _credentialStore.clearSession();
    notifyListeners();
  }

  void _setSignedOut() {
    _phase = SessionPhase.signedOut;
    _authorization = OperatorAuthorization.none;
    notifyListeners();
  }

  static String _secret(int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _challengeFor(String value) =>
      base64Url.encode(sha256.convert(ascii.encode(value)).bytes).replaceAll('=', '');
}
