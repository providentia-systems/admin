import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/auth/admin_account_link.dart';

import '../support/admin_approval_fixture.dart';

Uri accountLink(String action) => Uri.parse(
  'providentia-admin://login-link/admin#action=$action&token=$approvalToken',
);

void main() {
  test('parses only application-bound verification and reset fragments', () {
    final verification = parseAdminAccountLink(accountLink('verify-email'));
    final reset = parseAdminAccountLink(accountLink('password-reset'));

    expect(verification.action, AdminAccountLinkAction.verifyEmail);
    expect(reset.action, AdminAccountLinkAction.passwordReset);
    expect(verification.token, approvalToken);
    expect(looksLikeAdminAccountLink(accountLink('verify-email')), isTrue);
  });

  test('clearing an account link prevents credential replay', () {
    final link = parseAdminAccountLink(accountLink('password-reset'));

    link.clear();

    expect(link.hasCredential, isFalse);
    expect(() => link.token, throwsStateError);
  });

  test('rejects homeowner, query, duplicate and unknown action links', () {
    final invalid = <Uri>[
      Uri.parse(
        'providentia://login-link/admin#action=verify-email&token=$approvalToken',
      ),
      Uri.parse(
        'providentia-admin://login-link/homeowner#action=verify-email&token=$approvalToken',
      ),
      Uri.parse(
        'providentia-admin://login-link/admin?token=$approvalToken#action=verify-email',
      ),
      Uri.parse(
        'providentia-admin://login-link/admin#action=verify-email&action=verify-email&token=$approvalToken',
      ),
      accountLink('ownership-step-up'),
    ];

    for (final uri in invalid) {
      expect(() => parseAdminAccountLink(uri), throwsFormatException);
    }
  });
}
