import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/auth/admin_approval_controller.dart';
import 'package:providentia_admin/features/auth/admin_approval_page.dart';
import 'package:providentia_admin/features/auth/admin_approval_port.dart';

import '../support/admin_approval_fixture.dart';
import '../support/fake_api.dart';

final class FakeApprovalPort implements AdminLoginApprovalPort {
  var proofCalls = 0;
  var reviewCalls = 0;
  final List<bool> decisions = <bool>[];

  @override
  Future<void> decide({
    required String requestId,
    required String approvalToken,
    required bool approve,
  }) async {
    expect(requestId, isNotEmpty);
    expect(approvalToken, isNotEmpty);
    decisions.add(approve);
  }

  @override
  Future<AdminApprovalProof> prove({
    required String requestId,
    required String approvalToken,
  }) async {
    proofCalls += 1;
    return AdminApprovalProof(
      requestId: requestId,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<AdminApprovalReview> review({
    required String requestId,
    required String approvalToken,
  }) async {
    reviewCalls += 1;
    final now = DateTime.now().toUtc();
    return AdminApprovalReview(
      requestId: requestId,
      deviceName: 'Providentia Admin for Linux',
      platform: 'linux',
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
  }
}

void main() {
  test(
    'HTTP approval port sends exact Admin-only proof, review and decision',
    () async {
      final api = FakeApi((request) async {
        final body = request.body! as Map<String, Object?>;
        expect(body['applicationKind'], 'admin');
        expect(body['approvalToken'], approvalToken);
        if (request.path.endsWith('/proof')) {
          return jsonResponse(<String, Object?>{
            'valid': true,
            'requestId': requestId,
            'applicationKind': 'admin',
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 5))
                .toIso8601String(),
          });
        }
        if (request.path.endsWith('/review')) {
          final now = DateTime.now().toUtc();
          return jsonResponse(<String, Object?>{
            'requestId': requestId,
            'applicationKind': 'admin',
            'deviceName': 'Providentia Admin for Linux',
            'platform': 'linux',
            'createdAt': now.toIso8601String(),
            'expiresAt': now.add(const Duration(minutes: 5)).toIso8601String(),
          });
        }
        expect(body['decision'], 'approve');
        return jsonResponse(<String, Object?>{
          'requestId': requestId,
          'applicationKind': 'admin',
          'status': 'received',
        });
      });
      final port = HttpAdminLoginApprovalPort(api);

      await port.prove(requestId: requestId, approvalToken: approvalToken);
      await port.review(requestId: requestId, approvalToken: approvalToken);
      await port.decide(
        requestId: requestId,
        approvalToken: approvalToken,
        approve: true,
      );

      expect(api.requests.map((request) => request.path), <String>[
        '/api/v1/auth/login-links/$requestId/proof',
        '/api/v1/auth/login-links/$requestId/review',
        '/api/v1/auth/login-links/$requestId/decision',
      ]);
    },
  );

  test(
    'review fails closed when Backend reports a different application',
    () async {
      final api = FakeApi(
        (_) async => jsonResponse(<String, Object?>{
          'requestId': requestId,
          'applicationKind': 'homeowner',
          'deviceName': 'Phone',
          'platform': 'android',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .toIso8601String(),
        }),
      );

      await expectLater(
        HttpAdminLoginApprovalPort(
          api,
        ).review(requestId: requestId, approvalToken: approvalToken),
        throwsFormatException,
      );
    },
  );

  testWidgets('operator can review and approve without exposing the token', (
    tester,
  ) async {
    final port = FakeApprovalPort();
    final controller = AdminApprovalController(port);
    await controller.begin(validAdminLink());

    await tester.pumpWidget(
      MaterialApp(home: AdminApprovalPage(controller: controller)),
    );

    expect(find.textContaining('Providentia Admin for Linux'), findsOneWidget);
    expect(find.textContaining(approvalToken), findsNothing);
    await tester.tap(find.byKey(const Key('approve-admin-login')));
    await tester.pumpAndSettle();

    expect(port.decisions, <bool>[true]);
    expect(controller.phase, AdminApprovalPhase.approved);
    expect(controller.hasEphemeralCredential, isFalse);
    expect(find.text('Administrator sign-in approved.'), findsOneWidget);
  });

  test(
    'decision is one-shot and denial clears the fragment credential',
    () async {
      final port = FakeApprovalPort();
      final controller = AdminApprovalController(port);
      await controller.begin(validAdminLink());

      await controller.decide(approve: false);
      await controller.decide(approve: true);

      expect(port.decisions, <bool>[false]);
      expect(controller.phase, AdminApprovalPhase.denied);
      expect(controller.hasEphemeralCredential, isFalse);
    },
  );
}
