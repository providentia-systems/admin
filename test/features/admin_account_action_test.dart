import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia_admin/app/providentia_admin_app.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/credential_store.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/auth/admin_account_action_controller.dart';
import 'package:providentia_admin/features/auth/admin_account_action_page.dart';
import 'package:providentia_admin/features/auth/admin_account_action_port.dart';
import 'package:providentia_admin/features/auth/admin_approval_controller.dart';
import 'package:providentia_admin/features/auth/admin_approval_port.dart';
import 'package:providentia_admin/features/auth/login_page.dart';

import '../support/admin_approval_fixture.dart';
import '../support/fake_api.dart';

final class _FakeAccountActionPort implements AdminAccountActionPort {
  final List<String> verifications = <String>[];
  final List<String> resends = <String>[];
  final List<String> resetRequests = <String>[];
  final List<(String, String)> resets = <(String, String)>[];

  @override
  Future<void> completePasswordReset({
    required String token,
    required String password,
  }) async => resets.add((token, password));

  @override
  Future<void> requestPasswordReset(String email) async =>
      resetRequests.add(email);

  @override
  Future<void> resendVerification(String email) async => resends.add(email);

  @override
  Future<void> verifyEmail(String token) async => verifications.add(token);
}

final class _FailingAccountActionPort implements AdminAccountActionPort {
  @override
  Future<void> completePasswordReset({
    required String token,
    required String password,
  }) async => throw StateError('transport detail');

  @override
  Future<void> requestPasswordReset(String email) async =>
      throw StateError('transport detail');

  @override
  Future<void> resendVerification(String email) async =>
      throw StateError('transport detail');

  @override
  Future<void> verifyEmail(String token) async =>
      throw StateError('transport detail');
}

final class _DelayedResetAccountActionPort implements AdminAccountActionPort {
  final Completer<void> resetGate = Completer<void>();

  @override
  Future<void> completePasswordReset({
    required String token,
    required String password,
  }) => resetGate.future;

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> resendVerification(String email) async {}

  @override
  Future<void> verifyEmail(String token) async {}
}

final class _FakePasswordResetSessionBoundary
    implements AdminPasswordResetSessionBoundary {
  var calls = 0;

  @override
  Future<void> revokeAfterPasswordReset() async => calls += 1;
}

final class _EmptyCredentialStore implements CredentialStore {
  String? installationId;
  Map<String, String> session = <String, String>{};
  Map<String, String> pending = <String, String>{};
  var sessionClears = 0;
  var pendingClears = 0;

  @override
  Future<void> clearPendingLogin() async {
    pendingClears += 1;
    pending.clear();
  }

  @override
  Future<void> clearSession() async {
    sessionClears += 1;
    session.clear();
  }

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
  Future<void> writePendingLogin(Map<String, String> values) async =>
      pending = Map.of(values);

  @override
  Future<void> writeSession(Map<String, String> values) async =>
      session = Map.of(values);
}

AdminAccountActionController _controller(
  AdminAccountActionPort port, {
  AdminPasswordResetSessionBoundary? passwordResetSessionBoundary,
}) => AdminAccountActionController(
  port,
  passwordResetSessionBoundary:
      passwordResetSessionBoundary ?? _FakePasswordResetSessionBoundary(),
);

Uri _accountLink(String action) => Uri.parse(
  'providentia-admin://login-link/admin#action=$action&token=$approvalToken',
);

void main() {
  test('HTTP account actions bind every request to Admin', () async {
    final api = FakeApi((_) async => jsonResponse(const <String, Object?>{}));
    final port = HttpAdminAccountActionPort(api);

    await port.verifyEmail(approvalToken);
    await port.resendVerification('operator@example.test');
    await port.requestPasswordReset('operator@example.test');
    await port.completePasswordReset(
      token: approvalToken,
      password: 'a-strong-admin-password',
    );

    expect(api.requests.map((request) => request.path), <String>[
      '/api/v1/auth/verify-email',
      '/api/v1/auth/verify-email/resend',
      '/api/v1/auth/password-reset/request',
      '/api/v1/auth/password-reset/complete',
    ]);
    for (final request in api.requests) {
      expect(
        request.body as Map<String, Object?>,
        containsPair('applicationKind', 'admin'),
      );
    }
  });

  test('verification is one-shot and clears the fragment credential', () async {
    final port = _FakeAccountActionPort();
    final controller = _controller(port);

    await controller.begin(_accountLink('verify-email'));

    expect(port.verifications, <String>[approvalToken]);
    expect(controller.phase, AdminAccountActionPhase.verified);
    expect(controller.hasEphemeralCredential, isFalse);
  });

  test(
    'recovery requests normalize email and remain enumeration-safe',
    () async {
      final port = _FakeAccountActionPort();
      final controller = _controller(port);

      await controller.requestPasswordReset(' OPERATOR@Example.Test ');

      expect(port.resetRequests, <String>['operator@example.test']);
      expect(controller.phase, AdminAccountActionPhase.requestSent);
    },
  );

  testWidgets('password reset never renders the fragment credential', (
    tester,
  ) async {
    final port = _FakeAccountActionPort();
    final resetBoundary = _FakePasswordResetSessionBoundary();
    final controller = _controller(
      port,
      passwordResetSessionBoundary: resetBoundary,
    );
    await controller.begin(_accountLink('password-reset'));

    await tester.pumpWidget(
      MaterialApp(home: AdminAccountActionPage(controller: controller)),
    );
    expect(find.textContaining(approvalToken), findsNothing);

    await tester.enterText(
      find.byKey(const Key('admin-reset-password')),
      'a-strong-admin-password',
    );
    await tester.enterText(
      find.byKey(const Key('admin-reset-confirmation')),
      'a-strong-admin-password',
    );
    await tester.tap(find.byKey(const Key('complete-admin-password-reset')));
    await tester.pumpAndSettle();

    expect(port.resets.single.$1, approvalToken);
    expect(resetBoundary.calls, 1);
    expect(controller.phase, AdminAccountActionPhase.resetComplete);
    expect(controller.hasEphemeralCredential, isFalse);
  });

  testWidgets(
    'successful reset purges the live session and cannot reveal Admin shell',
    (tester) async {
      final store = _EmptyCredentialStore()
        ..installationId = _installationId
        ..session = _storedSession()
        ..pending = <String, String>{'requestId': 'pending-secret'};
      final sessionApi = FakeApi(
        (_) async => jsonResponse(<String, Object?>{
          'userId': _storedSession()['userId'],
          'platformRoles': <Object?>['platform_administrator'],
        }),
      );
      final session = SessionController(
        api: sessionApi,
        credentialStore: store,
      );
      await session.restore();
      expect(session.phase, SessionPhase.authenticated);

      final appApi = ApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient(
          (_) async => http.Response(
            '{}',
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          ),
        ),
        accessTokenProvider: () => session.accessToken,
        ensureAccessToken: ({required force}) =>
            session.ensureFreshAccessToken(force: force),
        onAuthorizationLost: session.authorizationLost,
      );
      final accountActions = _controller(
        _FakeAccountActionPort(),
        passwordResetSessionBoundary: CallbackAdminPasswordResetSessionBoundary(
          session.revokeAfterPasswordReset,
        ),
      );
      final approval = AdminApprovalController(
        HttpAdminLoginApprovalPort(appApi),
      );
      addTearDown(() {
        approval.dispose();
        accountActions.dispose();
        appApi.close();
      });
      await accountActions.begin(_accountLink('password-reset'));
      await tester.pumpWidget(
        ProvidentiaAdminApp(
          api: appApi,
          approval: approval,
          accountActions: accountActions,
          session: session,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('admin-reset-password')),
        'a-strong-admin-password',
      );
      await tester.enterText(
        find.byKey(const Key('admin-reset-confirmation')),
        'a-strong-admin-password',
      );
      await tester.tap(find.byKey(const Key('complete-admin-password-reset')));
      await tester.pumpAndSettle();

      expect(session.phase, SessionPhase.signedOut);
      expect(session.accessToken, isNull);
      expect(session.authorization.isOperator, isFalse);
      expect(store.session, isEmpty);
      expect(store.pending, isEmpty);
      expect(store.sessionClears, 1);
      expect(store.pendingClears, 1);

      accountActions.dismiss();
      await tester.pumpAndSettle();

      expect(find.text('Providentia administration'), findsNothing);
      expect(
        find.text('Sign in with an account that has a platform operator role.'),
        findsOneWidget,
      );
    },
  );

  test(
    'dismissed reset still revokes a session after server success',
    () async {
      final port = _DelayedResetAccountActionPort();
      final resetBoundary = _FakePasswordResetSessionBoundary();
      final controller = _controller(
        port,
        passwordResetSessionBoundary: resetBoundary,
      );
      await controller.begin(_accountLink('password-reset'));

      final resetting = controller.completePasswordReset(
        'a-strong-admin-password',
      );
      await Future<void>.delayed(Duration.zero);
      controller.dismiss();
      port.resetGate.complete();
      await resetting;

      expect(resetBoundary.calls, 1);
      expect(controller.phase, AdminAccountActionPhase.dismissed);
      expect(controller.hasEphemeralCredential, isFalse);
    },
  );

  testWidgets('failed account-message request clears busy state safely', (
    tester,
  ) async {
    final accountActions = _controller(_FailingAccountActionPort());
    final session = SessionController(
      api: FakeApi((_) async => throw StateError('must not call API')),
      credentialStore: _EmptyCredentialStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(session: session, accountActions: accountActions),
      ),
    );
    await tester.enterText(find.byType(TextField), 'operator@example.test');

    await tester.tap(find.byKey(const Key('request-admin-password-reset')));
    await tester.pumpAndSettle();

    expect(
      find.text('The account message could not be requested safely.'),
      findsOneWidget,
    );
    final button = tester.widget<TextButton>(
      find.byKey(const Key('request-admin-password-reset')),
    );
    expect(button.onPressed, isNotNull);
  });
}

const String _installationId = '44444444-4444-4444-8444-444444444444';

Map<String, String> _storedSession() => <String, String>{
  'accessToken': 'access-token',
  'refreshToken': 'refresh-token',
  'sessionId': '0198f4e2-7abc-7def-8abc-0123456789ab',
  'deviceId': '22222222-2222-4222-8222-222222222222',
  'installationId': _installationId,
  'userId': '0198f4e3-7abc-7def-8abc-0123456789ab',
  'accessExpiresAt': '2026-09-01T00:00:00Z',
  'refreshExpiresAt': '2026-10-01T00:00:00Z',
  'idleExpiresAt': '2026-10-01T00:00:00Z',
  'refreshIdleTtlSeconds': '2592000',
  'transport': 'native',
};
