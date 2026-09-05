import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia_admin/app/providentia_admin_app.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';

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
          'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'accounts.read': true, 'accounts.manage': true, 'accounts.assign': true, 'people.read': true, 'homes.read': true, 'homes.manage': true, 'homes.assign': true, 'administrators.read': true, 'administrators.approve': true, 'administrators.manage': true, 'groups.manage': true, 'countries.manage': true, 'policies.manage': true, 'catalog.read': true, 'catalog.review': true, 'catalog.curate': true, 'billing.read': true, 'billing.manage': true, 'audit.read': true}}},
        });
      }
      throw StateError('unexpected ${request.path}');
    });
    final session = SessionController(api: sessionApi, credentialStore: store);
    await session.restore();
    expect(session.phase, SessionPhase.authenticated);

    final appApi = _appApi(session);
    addTearDown(() {
      appApi.close();
    });

    await tester.pumpWidget(
      ProvidentiaAdminApp(api: appApi, session: session),
    );
    await tester.pumpAndSettle();

    expect(find.text('Providentia administration'), findsOneWidget);
    expect(find.text('Administrators'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Billing'), 180, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Billing'));
    await tester.pumpAndSettle();
    expect(find.text('Free stabilization phase'), findsOneWidget);

    session.authorizationLost();
    await tester.pump();

    expect(find.text('Providentia administration'), findsNothing);
    expect(
      find.text('Enter your email to sign in or request administrator access.'),
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
    addTearDown(() {
      appApi.close();
    });

    await tester.pumpWidget(
      ProvidentiaAdminApp(api: appApi, session: session),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Providentia administration'), findsNothing);
  });
}
