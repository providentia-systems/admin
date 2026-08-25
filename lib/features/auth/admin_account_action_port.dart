import '../../core/api/api_client.dart';

abstract interface class AdminAccountActionPort {
  Future<void> verifyEmail(String token);
  Future<void> resendVerification(String email);
  Future<void> requestPasswordReset(String email);
  Future<void> completePasswordReset({
    required String token,
    required String password,
  });
}

/// Revokes the local administrator session after the Backend has atomically
/// completed a password reset and invalidated every server session.
///
/// Keeping this as a narrow port prevents the account-action controller from
/// depending on the full session controller or privileged application shell.
abstract interface class AdminPasswordResetSessionBoundary {
  Future<void> revokeAfterPasswordReset();
}

final class CallbackAdminPasswordResetSessionBoundary
    implements AdminPasswordResetSessionBoundary {
  const CallbackAdminPasswordResetSessionBoundary(this._revoke);

  final Future<void> Function() _revoke;

  @override
  Future<void> revokeAfterPasswordReset() => _revoke();
}

final class HttpAdminAccountActionPort implements AdminAccountActionPort {
  const HttpAdminAccountActionPort(this._api);

  final AdminApi _api;

  @override
  Future<void> verifyEmail(String token) => _api.postPublic(
    '/api/v1/auth/verify-email',
    body: <String, Object?>{'applicationKind': 'admin', 'token': token},
  );

  @override
  Future<void> resendVerification(String email) => _api.postPublic(
    '/api/v1/auth/verify-email/resend',
    body: <String, Object?>{'applicationKind': 'admin', 'email': email},
  );

  @override
  Future<void> requestPasswordReset(String email) => _api.postPublic(
    '/api/v1/auth/password-reset/request',
    body: <String, Object?>{'applicationKind': 'admin', 'email': email},
  );

  @override
  Future<void> completePasswordReset({
    required String token,
    required String password,
  }) => _api.postPublic(
    '/api/v1/auth/password-reset/complete',
    body: <String, Object?>{
      'applicationKind': 'admin',
      'token': token,
      'password': password,
    },
  );
}
