import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia_admin/app/providentia_admin_app.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/auth/admin_approval_controller.dart';
import 'package:providentia_admin/features/auth/admin_approval_port.dart';

import '../support/fake_api.dart';
import '../support/memory_credential_store.dart';

ApiClient _appApi(SessionController session) => ApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(
    (_) async => http.Response(
      '{"data": []}',
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    ),
  ),
  accessTokenProvider: () => session.accessToken,
  ensureAccessToken: ({required force}) =>
      session.ensureFreshAccessToken(force: force),
  onAuthorizationLost: session.authorizationLost,
);

void main() {
  testWidgets('authorization loss purges the shell and returns to sign-in', (
    tester,
  ) async {
    final store = MemoryCredentialStore(installationId: memoryInstallationId)
      ..session = memoryStoredSession();
    final sessionApi = FakeApi((request) async {
      if (request.path == '/api/v1/me') {
        return jsonResponse(<String, Object?>{
          'userId': memoryStoredSession()['userId'],
          'platformRoles': <Object?>['platform_administrator'],
        });
      }
      throw StateError('unexpected ${request.path}');
    });
    final session = SessionController(api: sessionApi, credentialStore: store);
    await session.restore();
    expect(session.phase, SessionPhase.authenticated);

    final appApi = _appApi(session);
    final approval = AdminApprovalController(
      HttpAdminLoginApprovalPort(appApi),
    );
    addTearDown(() {
      approval.dispose();
      appApi.close();
    });

    await tester.pumpWidget(
      ProvidentiaAdminApp(api: appApi, approval: approval, session: session),
    );
    await tester.pumpAndSettle();

    expect(find.text('Providentia administration'), findsOneWidget);
    expect(find.text('Platform administrators'), findsOneWidget);

    await tester.tap(find.text('Billing'));
    await tester.pumpAndSettle();
    expect(find.text('Free stabilization phase'), findsOneWidget);

    session.authorizationLost();
    await tester.pump();

    expect(find.text('Providentia administration'), findsNothing);
    expect(
      find.text('Sign in with an account that has a platform operator role.'),
      findsOneWidget,
    );

    await tester.pumpAndSettle();
    expect(store.session, isEmpty);
    expect(session.accessToken, isNull);
    expect(session.authorization.isOperator, isFalse);
  });

  testWidgets('a restoring session shows progress without privileged UI', (
    tester,
  ) async {
    final session = SessionController(
      api: FakeApi((_) async => throw StateError('must not call API')),
      credentialStore: MemoryCredentialStore(
        installationId: memoryInstallationId,
      ),
    );
    final appApi = _appApi(session);
    final approval = AdminApprovalController(
      HttpAdminLoginApprovalPort(appApi),
    );
    addTearDown(() {
      approval.dispose();
      appApi.close();
    });

    await tester.pumpWidget(
      ProvidentiaAdminApp(api: appApi, approval: approval, session: session),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Providentia administration'), findsNothing);
  });
}
