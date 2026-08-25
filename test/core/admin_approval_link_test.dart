import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/auth/admin_approval_link.dart';

import '../support/admin_approval_fixture.dart';

void main() {
  test('parses only the Admin application fragment contract', () {
    final link = parseAdminApprovalLink(validAdminLink());

    expect(link.requestId, requestId);
    expect(link.approvalToken, approvalToken);
    expect(link.hasCredential, isTrue);
  });

  test('clears decoded approval bytes and prevents credential replay', () {
    final link = parseAdminApprovalLink(validAdminLink());

    link.clear();

    expect(link.hasCredential, isFalse);
    expect(() => link.approvalToken, throwsStateError);
  });

  test('rejects homeowner, query-secret and non-login Admin links', () {
    final invalid = <Uri>[
      Uri.parse(
        'providentia://login-link/admin#requestId=$requestId&approval=$approvalToken',
      ),
      Uri.parse(
        'providentia-admin://login-link/homeowner#requestId=$requestId&approval=$approvalToken',
      ),
      Uri.parse(
        'providentia-admin://login-link/admin?approval=$approvalToken#requestId=$requestId',
      ),
      Uri.parse(
        'providentia-admin://reset/admin#requestId=$requestId&approval=$approvalToken',
      ),
    ];

    for (final uri in invalid) {
      expect(() => parseAdminApprovalLink(uri), throwsFormatException);
    }
  });

  test('rejects duplicate, short or malformed fragment credentials', () {
    final invalid = <Uri>[
      Uri.parse(
        'providentia-admin://login-link/admin#requestId=$requestId&requestId=$requestId&approval=$approvalToken',
      ),
      Uri.parse(
        'providentia-admin://login-link/admin#requestId=$requestId&approval=short',
      ),
      Uri.parse(
        'providentia-admin://login-link/admin#requestId=$requestId&approval=${'A'.padRight(39, 'A')}!',
      ),
    ];

    for (final uri in invalid) {
      expect(() => parseAdminApprovalLink(uri), throwsFormatException);
    }
  });
}
