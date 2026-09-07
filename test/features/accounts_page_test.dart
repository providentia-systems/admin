import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/accounts/accounts_page.dart';

import '../support/fake_api.dart';
import '../support/memory_credential_store.dart';

Map<String, Object?> _account({String status = 'active', int revision = 4}) => {
  'userId': 'account-a',
  'email': 'alex@example.test',
  'displayName': 'Alex',
  'emailVerified': true,
  'status': status,
  'revision': revision,
  'homeCount': 1,
  'activeSessionCount': 2,
  'homes': [
    {
      'homeId': 'home-a',
      'name': 'Family',
      'membershipRole': 'owner',
      'membershipStatus': 'active',
    },
  ],
};
Future<SessionController> _session(List<String> permissions) async {
  final store = MemoryCredentialStore(installationId: memoryInstallationId)
    ..session = memoryStoredSession();
  final session = SessionController(
    credentialStore: store,
    api: FakeApi(
      (_) async => jsonResponse({
        'userId': store.session['userId'],
        'profile': {
          'administratorAccess': {
            'features': {
              for (final permission in permissions) permission: true,
            },
          },
        },
      }),
    ),
  );
  await session.restore();
  return session;
}

Future<void> _pump(
  WidgetTester tester,
  FakeApi api,
  SessionController session,
) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AccountsPage(api: api, session: session),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('account read access cannot fetch avatars or change lifecycle', (
    tester,
  ) async {
    final session = await _session(['accounts.read']);
    final api = FakeApi(
      (r) async => jsonResponse(
        r.path.endsWith('/accounts')
            ? {
                'data': [_account()],
                'pagination': {'limit': 50, 'offset': 0, 'total': 1},
              }
            : _account(),
      ),
    );
    await _pump(tester, api, session);
    await tester.tap(find.text('Alex'));
    await tester.pumpAndSettle();
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('owner • active'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Suspend'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Change account group'),
          )
          .onPressed,
      isNull,
    );
    expect(api.requests.any((r) => r.path.endsWith('/avatar')), isFalse);
  });
  testWidgets(
    'authorized account operator inspects avatar and changes lifecycle with an auditable reason',
    (tester) async {
      final session = await _session([
        'accounts.read',
        'accounts.manage',
        'people.read',
      ]);
      var status = 'active';
      var revision = 4;
      final api = FakeApi((r) async {
        if (r.path.endsWith('/avatar')) {
          return ApiResponse(statusCode: 204, headers: {}, bytes: Uint8List(0));
        }
        if (r.method == 'PATCH') {
          status = 'suspended';
          revision = 5;
        }
        return jsonResponse(
          r.path.endsWith('/accounts')
              ? {
                  'data': [_account(status: status, revision: revision)],
                  'pagination': {'limit': 50, 'offset': 0, 'total': 1},
                }
              : _account(status: status, revision: revision),
        );
      });
      await _pump(tester, api, session);
      await tester.tap(find.text('Alex'));
      await tester.pumpAndSettle();
      expect(
        api.requests.any(
          (r) => r.path == '/api/v1/admin/users/account-a/avatar',
        ),
        isTrue,
      );
      await tester.tap(find.text('Suspend'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Auditable reason (at least 5 characters)',
        ),
        'Requested account suspension',
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      final request = api.requests.singleWhere((r) => r.method == 'PATCH');
      expect(request.path, '/api/v1/admin/accounts/account-a/status');
      expect(request.body, {
        'status': 'suspended',
        'reason': 'Requested account suspension',
        'expectedRevision': 4,
      });
      expect(find.text('Status: suspended'), findsOneWidget);
    },
  );
}
