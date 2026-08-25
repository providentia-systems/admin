import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/auth/admin_account_action_controller.dart';
import 'package:providentia_admin/features/auth/admin_account_action_page.dart';
import 'package:providentia_admin/features/auth/admin_account_action_port.dart';

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
    final controller = AdminAccountActionController(port);

    await controller.begin(_accountLink('verify-email'));

    expect(port.verifications, <String>[approvalToken]);
    expect(controller.phase, AdminAccountActionPhase.verified);
    expect(controller.hasEphemeralCredential, isFalse);
  });

  test(
    'recovery requests normalize email and remain enumeration-safe',
    () async {
      final port = _FakeAccountActionPort();
      final controller = AdminAccountActionController(port);

      await controller.requestPasswordReset(' OPERATOR@Example.Test ');

      expect(port.resetRequests, <String>['operator@example.test']);
      expect(controller.phase, AdminAccountActionPhase.requestSent);
    },
  );

  testWidgets('password reset never renders the fragment credential', (
    tester,
  ) async {
    final port = _FakeAccountActionPort();
    final controller = AdminAccountActionController(port);
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
    expect(controller.phase, AdminAccountActionPhase.resetComplete);
    expect(controller.hasEphemeralCredential, isFalse);
  });
}
