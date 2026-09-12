import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/workspace/operator_shopping_editor.dart';
import 'package:providentia_admin/features/workspace/operator_shopping_repository.dart';

import '../support/fake_api.dart';
import '../support/memory_credential_store.dart';

const _homeId = '11111111-1111-4111-8111-111111111111';
const _listId = '22222222-2222-4222-8222-222222222222';
const _lineId = '33333333-3333-4333-8333-333333333333';

Map<String, Object?> _record(
  bool line, {
  bool archived = false,
  bool checked = false,
}) => line
    ? {
        'id': _lineId,
        'shopping_list_id': _listId,
        'description': 'Oats',
        'quantity_to_buy': '2.5',
        'source': 'suggested',
        'revision': 7,
        'archived_at': archived ? '2026-09-12' : null,
        'checked_at': checked ? '2026-09-12' : null,
      }
    : {
        'id': _listId,
        'name': 'Weekly shop',
        'kind': 'manual',
        'status': archived ? 'archived' : 'open',
        'revision': 7,
      };

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

Future<void> _open(
  WidgetTester tester,
  FakeApi api, {
  bool line = false,
  Map<String, Object?>? record,
  SessionController? session,
}) async {
  final activeSession = session ?? await _session();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => OperatorShoppingEditor(
                repository: OperatorShoppingRepository(api),
                session: activeSession,
                homeId: _homeId,
                line: line,
                record: record,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _reason(WidgetTester tester) => tester.enterText(
  find.widgetWithText(TextField, 'Audit reason'),
  'Household support',
);

void main() {
  testWidgets('new list uses operator route and requires audit reason', (
    tester,
  ) async {
    final api = FakeApi((_) async => jsonResponse({}));
    await _open(tester, api);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Groceries');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.requests, isEmpty);
    await _reason(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.requests.single.method, 'POST');
    expect(
      api.requests.single.path,
      '/api/v1/admin/homes/$_homeId/shopping-lists',
    );
    final body = api.requests.single.body! as Map<String, Object?>;
    expect(body['name'], 'Groceries');
    expect(body['kind'], 'manual');
    expect(body['expectedRevision'], 0);
    expect(body['reason'], 'Household support');
  });

  testWidgets('new item binds selected open list revision and exact quantity', (
    tester,
  ) async {
    final api = FakeApi((request) async {
      if (request.method == 'GET') {
        return jsonResponse({
          'data': request.path.endsWith('shopping-lists')
              ? [_record(false)]
              : [],
        });
      }
      return jsonResponse({});
    });
    await _open(tester, api, line: true);
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Shopping list'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly shop').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Flour',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Quantity to buy'),
      '1.125',
    );
    await _reason(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final request = api.requests.singleWhere((r) => r.method == 'POST');
    expect(
      request.path,
      '/api/v1/admin/homes/$_homeId/shopping-lists/$_listId/lines',
    );
    final body = request.body! as Map<String, Object?>;
    expect(body['expectedListRevision'], 7);
    expect(body['expectedRevision'], 0);
    expect(body['quantityToBuy'], '1.125');
    expect(body['homeProductId'], isNull);
  });

  testWidgets('editing a suggested item changes only reviewed metadata', (
    tester,
  ) async {
    final api = FakeApi((_) async => jsonResponse({}));
    await _open(tester, api, line: true, record: _record(true));
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Rolled oats',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Quantity to buy'),
      '3.75',
    );
    await _reason(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.requests.single.method, 'PATCH');
    expect(api.requests.single.body, {
      'expectedRevision': 7,
      'reason': 'Household support',
      'description': 'Rolled oats',
      'quantityToBuy': '3.75',
    });
  });

  for (final line in [false, true]) {
    for (final archived in [false, true]) {
      testWidgets(
        '${line ? "item" : "list"} ${archived ? "restore" : "archive"} excludes unsaved edits',
        (tester) async {
          final api = FakeApi((_) async => jsonResponse({}));
          await _open(
            tester,
            api,
            line: line,
            record: _record(line, archived: archived),
          );
          await tester.enterText(
            find.widgetWithText(TextField, line ? 'Description' : 'Name'),
            'Unsaved field',
          );
          await _reason(tester);
          await tester.tap(
            find.widgetWithText(
              OutlinedButton,
              archived ? 'Restore' : 'Archive',
            ),
          );
          await tester.pumpAndSettle();
          expect(api.requests.single.body, {
            'expectedRevision': 7,
            'reason': 'Household support',
            if (line)
              'archived': !archived
            else
              'status': archived ? 'open' : 'archived',
          });
        },
      );
    }
  }

  for (final checked in [false, true]) {
    testWidgets(
      '${checked ? "uncheck" : "check"} retains metadata and revision binding',
      (tester) async {
        final api = FakeApi((_) async => jsonResponse({}));
        await _open(
          tester,
          api,
          line: true,
          record: _record(true, checked: checked),
        );
        await _reason(tester);
        await tester.tap(
          find.widgetWithText(OutlinedButton, checked ? 'Uncheck' : 'Check'),
        );
        await tester.pumpAndSettle();
        expect(api.requests.single.method, 'PUT');
        expect(
          api.requests.single.path,
          '/api/v1/admin/homes/$_homeId/shopping-lists/$_listId/lines/$_lineId/checked',
        );
        expect(api.requests.single.body, {
          'expectedRevision': 7,
          'reason': 'Household support',
          'checked': !checked,
        });
      },
    );
  }

  testWidgets('ambiguous save disables retry until the record is reloaded', (
    tester,
  ) async {
    final api = FakeApi(
      (_) async => throw const ApiException(
        statusCode: 503,
        message: 'Temporarily unavailable',
      ),
    );
    await _open(tester, api, record: _record(false));
    await _reason(tester);
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

  testWidgets(
    'authorization loss clears the editor and ignores a late save response',
    (tester) async {
      final response = Completer<ApiResponse>();
      final api = FakeApi((_) => response.future);
      final session = await _session();
      await _open(tester, api, record: _record(false), session: session);
      await _reason(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      session.authorizationLost();
      await tester.pump();
      expect(find.text('Weekly shop'), findsNothing);
      expect(find.text('Household support'), findsNothing);
      response.complete(jsonResponse({}));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'repository rejects attempts to rewrite immutable suggestion provenance',
    () async {
      final api = FakeApi((_) async => jsonResponse({}));
      await expectLater(
        OperatorShoppingRepository(api).saveLine(
          homeId: _homeId,
          listId: _listId,
          id: _lineId,
          revision: 7,
          reason: 'Support',
          fields: {'suggestionId': _lineId},
        ),
        throwsFormatException,
      );
      expect(api.requests, isEmpty);
    },
  );
}
