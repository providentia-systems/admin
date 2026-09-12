import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/workspace/operator_inventory_editor.dart';
import 'package:providentia_admin/features/workspace/operator_inventory_repository.dart';

import '../support/fake_api.dart';
import '../support/memory_credential_store.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';
const _recordId = '22222222-2222-4222-8222-222222222222';

Future<SessionController> _session() async {
  final store = MemoryCredentialStore(installationId: memoryInstallationId)
    ..session = memoryStoredSession();
  final session = SessionController(
    credentialStore: store,
    api: FakeApi(
      (_) async => jsonResponse({
        'userId': store.session['userId'],
        'profile': {
          'administratorAccess': {
            'features': {'homes.manage': true, 'homes.read': true},
          },
        },
      }),
    ),
  );
  await session.restore();
  addTearDown(session.dispose);
  return session;
}

void main() {
  for (final kind in [
    OperatorInventoryKind.location,
    OperatorInventoryKind.store,
  ]) {
    testWidgets(
      '${kind.name} editor creates only through audited operator routes',
      (tester) async {
        final api = FakeApi((_) async => jsonResponse({}));
        final session = await _session();
        await _open(
          tester,
          OperatorInventoryEditor(
            repository: OperatorInventoryRepository(api),
            session: session,
            homeId: _homeId,
            kind: kind,
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Name'),
          kind == OperatorInventoryKind.location
              ? 'Pantry shelf'
              : 'Family shop',
        );
        if (kind == OperatorInventoryKind.store) {
          await tester.enterText(
            find.widgetWithText(TextField, 'Store location'),
            'Windhoek',
          );
        }
        await tester.enterText(
          find.widgetWithText(TextField, 'Audit reason'),
          'Household support',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(api.requests, hasLength(1));
        final request = api.requests.single;
        final body = request.body! as Map<String, Object?>;
        expect(request.method, 'POST');
        expect(request.path, '/api/v1/admin/homes/$_homeId/${kind.name}s');
        expect(body['expectedRevision'], 0);
        expect(body['reason'], 'Household support');
        expect(body['id'], isA<String>());
        if (kind == OperatorInventoryKind.location) {
          expect(body['kind'], 'other');
        } else {
          expect(body['location'], 'Windhoek');
        }
        expect(tester.takeException(), isNull);
      },
    );

    for (final archived in [false, true]) {
      testWidgets(
        '${kind.name} ${archived ? "restore" : "archive"} is revision bound and excludes unsaved fields',
        (tester) async {
          final api = FakeApi((_) async => jsonResponse({}));
          await _open(
            tester,
            OperatorInventoryEditor(
              repository: OperatorInventoryRepository(api),
              session: await _session(),
              homeId: _homeId,
              kind: kind,
              record: OperatorInventoryRecord(
                id: _recordId,
                kind: kind,
                revision: 7,
                status: archived ? 'archived' : 'active',
                name: 'Original name',
                locationKind: 'pantry',
                storeLocation: 'Windhoek',
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, 'Name'),
            'Unconfirmed edit',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Audit reason'),
            'Lifecycle correction',
          );
          await tester.tap(
            find.widgetWithText(
              OutlinedButton,
              archived ? 'Restore' : 'Archive',
            ),
          );
          await tester.pumpAndSettle();
          expect(api.requests.single.method, 'PATCH');
          expect(
            api.requests.single.path,
            '/api/v1/admin/homes/$_homeId/${kind.name}s/$_recordId',
          );
          expect(api.requests.single.body, {
            'expectedRevision': 7,
            'reason': 'Lifecycle correction',
            'status': archived ? 'active' : 'archived',
          });
        },
      );
    }
  }

  testWidgets('store revision conflict prevents another save until reloaded', (
    tester,
  ) async {
    final api = FakeApi(
      (_) async => throw const ApiException(
        statusCode: 409,
        message: 'Changed elsewhere',
      ),
    );
    await _open(
      tester,
      OperatorInventoryEditor(
        repository: OperatorInventoryRepository(api),
        session: await _session(),
        homeId: _homeId,
        kind: OperatorInventoryKind.store,
        record: const OperatorInventoryRecord(
          id: _recordId,
          kind: OperatorInventoryKind.store,
          revision: 2,
          status: 'active',
          name: 'Shop',
          storeLocation: 'Town',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Audit reason'),
      'Correct location',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Close and reload'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(api.requests, hasLength(1));
  });
}

Future<void> _open(WidgetTester tester, OperatorInventoryEditor editor) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showDialog<bool>(context: context, builder: (_) => editor),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}
