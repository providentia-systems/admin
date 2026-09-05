import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/auth/login_page.dart';

import '../support/fake_api.dart';
import '../support/memory_credential_store.dart';

Future<SessionController> _signedOutSession(FakeApi api) async {
  final session = SessionController(
    api: api,
    credentialStore: MemoryCredentialStore(
      installationId: memoryInstallationId,
    ),
  );
  await session.restore();
  return session;
}

void main() {
  testWidgets('rejects an invalid operator email before any request', (
    tester,
  ) async {
    final api = FakeApi((_) async => throw StateError('must not call API'));
    final session = await _signedOutSession(api);

    await tester.pumpWidget(MaterialApp(home: LoginPage(session: session)));
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Email me a code'));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(api.requests, isEmpty);
  });

  testWidgets('code entry waits without polling and cancels safely', (
    tester,
  ) async {
    late String requestId;
    final api = FakeApi((request) async {
      if (request.path == '/api/v1/auth/email-codes') {
        requestId =
            '11111111-1111-4111-8111-111111111111';
        return jsonResponse(<String, Object?>{
          'accepted': true,
          'requestId': requestId,
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
          'pollIntervalSeconds': 2,
        });
      }
      if (request.path.endsWith('/status')) {
        return jsonResponse(<String, Object?>{
          'requestId': requestId,
          'applicationKind': 'admin',
          'status': 'pending',
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
        });
      }
      if (request.path.endsWith('/logout')) {
        return jsonResponse(const <String, Object?>{});
      }
      throw StateError('unexpected ${request.path}');
    });
    final session = await _signedOutSession(api);

    await tester.pumpWidget(MaterialApp(home: LoginPage(session: session)));
    await tester.enterText(find.byType(TextField), 'operator@example.test');
    await tester.tap(find.text('Email me a code'));
    // The pending view animates an indeterminate progress bar, so settle-style
    // pumping would never finish; bounded pumps flush the async transitions.
    await tester.pump();
    await tester.pump();

    expect(session.phase, SessionPhase.loginPending);
    expect(find.textContaining('Enter the eight-digit code'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();
    expect(
      api.requests.where((request) => request.path.endsWith('/status')),
      isEmpty,
    );
    expect(session.phase, SessionPhase.loginPending);

    await tester.tap(find.text('Use another email'));
    await tester.pump();
    await tester.pump();

    expect(session.phase, SessionPhase.signedOut);
    expect(
      api.requests.where((request) => request.path.endsWith('/logout')),
      isNotEmpty,
    );
    expect(
      find.text('Enter your email to sign in or request administrator access.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed code request surfaces a safe error message', (
    tester,
  ) async {
    final api = FakeApi((_) async => throw StateError('transport detail'));
    final session = await _signedOutSession(api);

    await tester.pumpWidget(MaterialApp(home: LoginPage(session: session)));
    await tester.enterText(find.byType(TextField), 'operator@example.test');
    await tester.tap(find.text('Email me a code'));
    await tester.pumpAndSettle();

    expect(find.text('Sign-in could not be completed. Check your code and connection, then try again.'), findsOneWidget);
    expect(find.textContaining('transport detail'), findsNothing);
    expect(session.phase, SessionPhase.signedOut);
  });
}
