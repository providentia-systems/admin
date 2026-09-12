import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/workspace/operator_inventory_editor.dart';
import 'package:providentia_admin/features/workspace/operator_inventory_repository.dart';
import 'package:providentia_admin/features/workspace/operator_stock_preference_editor.dart';
import 'package:providentia_admin/features/workspace/operator_stock_preference_repository.dart';

import '../support/fake_api.dart';
import '../support/memory_credential_store.dart';

const _home = '60000000-0000-4000-8000-000000000001';
const _product = '60000000-0000-4000-8000-000000000002';
const _category = '60000000-0000-4000-8000-000000000003';

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
            'features': {'homes.read': true, 'homes.manage': true},
          },
        },
      }),
    ),
  );
  await session.restore();
  addTearDown(session.dispose);
  return session;
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _harness(WidgetTester tester, Widget Function() editor) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              await showDialog<void>(
                context: context,
                builder: (_) => editor(),
              );
            },
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'household category creates, edits, archives and restores with audit revision',
    (tester) async {
      final session = await _session();
      OperatorInventoryRecord? record;
      final api = FakeApi((request) async {
        final body = request.body! as Map<String, Object?>;
        record = OperatorInventoryRecord(
          id: body['id'] as String? ?? record!.id,
          kind: OperatorInventoryKind.category,
          revision: (body['expectedRevision']! as int) + 1,
          status: body['status'] as String? ?? record?.status ?? 'active',
          name: body['name'] as String? ?? record!.name,
        );
        return jsonResponse({'id': record!.id});
      });
      await _harness(
        tester,
        () => OperatorInventoryEditor(
          repository: OperatorInventoryRepository(api),
          session: session,
          homeId: _home,
          kind: OperatorInventoryKind.category,
          record: record,
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an audit reason.'), findsOneWidget);
      expect(api.requests, isEmpty);
      await tester.enterText(_field('Name'), 'Pantry');
      await tester.enterText(_field('Audit reason'), 'Create category');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      for (final action in ['Save', 'Archive', 'Restore']) {
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        await tester.enterText(_field('Name'), 'Dry goods');
        await tester.enterText(
          _field('Audit reason'),
          'Reviewed household change',
        );
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
      }
      expect(api.requests.map((request) => request.method), [
        'POST',
        'PATCH',
        'PATCH',
        'PATCH',
      ]);
      expect(
        api.requests.map(
          (request) => (request.body! as Map)['expectedRevision'],
        ),
        [0, 1, 2, 3],
      );
      expect(record!.status, 'active');
      expect(record!.name, 'Dry goods');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog household metadata keeps global identity out of the mutation',
    (tester) async {
      final session = await _session();
      final api = FakeApi(
        (request) async => jsonResponse(
          request.method == 'GET'
              ? {
                  'data': [
                    {
                      'id': _category,
                      'name': 'Pantry',
                      'status': 'active',
                      'revision': 1,
                    },
                  ],
                }
              : {'revision': 3},
        ),
      );
      await _harness(
        tester,
        () => OperatorInventoryEditor(
          repository: OperatorInventoryRepository(api),
          session: session,
          homeId: _home,
          kind: OperatorInventoryKind.product,
          record: const OperatorInventoryRecord(
            id: _product,
            kind: OperatorInventoryKind.product,
            revision: 2,
            status: 'active',
            name: '',
            productId: _product,
            homeCategoryId: _category,
          ),
        ),
      );
      expect(_field('Name'), findsNothing);
      expect(_field('Pack or measure'), findsNothing);
      await tester.enterText(
        _field('Audit reason'),
        'Household category correction',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final write = api.requests.singleWhere(
        (request) => request.method == 'PATCH',
      );
      expect(write.body, {
        'expectedRevision': 2,
        'reason': 'Household category correction',
        'homeCategoryId': _category,
      });
      expect(write.path, '/api/v1/admin/homes/$_home/products/$_product');
    },
  );

  testWidgets(
    'conflict requires reload and authorization loss clears the private editor',
    (tester) async {
      final session = await _session();
      final api = FakeApi(
        (_) async => throw const ApiException(
          statusCode: 409,
          message: 'Changed elsewhere',
        ),
      );
      await _harness(
        tester,
        () => OperatorInventoryEditor(
          repository: OperatorInventoryRepository(api),
          session: session,
          homeId: _home,
          kind: OperatorInventoryKind.category,
          record: const OperatorInventoryRecord(
            id: _category,
            kind: OperatorInventoryKind.category,
            revision: 1,
            status: 'active',
            name: 'Private pantry',
          ),
        ),
      );
      await tester.enterText(_field('Audit reason'), 'Rename category');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Close and reload before retrying.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      session.authorizationLost();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Private pantry'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stock preferences edit minimum and reset with current revision',
    (tester) async {
      final session = await _session();
      var preference = <String, Object?>{
        'homeProductId': _product,
        'minimumQuantity': null,
        'alwaysKeep': false,
        'neverSuggest': false,
        'preferredPackId': null,
        'leadTimeDays': 0,
        'targetCoverageDays': null,
        'snoozeUntil': null,
        'revision': 0,
        'packOptions': <Object?>[],
      };
      final api = FakeApi((request) async {
        if (request.method == 'GET') return jsonResponse(preference);
        final body = request.body! as Map<String, Object?>;
        preference = {
          ...preference,
          ...body,
          'revision': (body['expectedRevision']! as int) + 1,
        };
        return jsonResponse({'revision': preference['revision']});
      });
      await _harness(
        tester,
        () => OperatorStockPreferenceEditor(
          repository: OperatorStockPreferenceRepository(api),
          session: session,
          homeId: _home,
          homeProductId: _product,
        ),
      );
      await tester.enterText(_field('Minimum quantity (optional)'), '3.5');
      await tester.tap(find.text('Always keep in stock'));
      await tester.enterText(_field('Lead time (days)'), '2');
      await tester.enterText(_field('Target coverage (days, optional)'), '14');
      await tester.enterText(
        _field('Audit reason'),
        'Set minimum for shopping recommendations',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(preference['minimumQuantity'], '3.5');
      expect(preference['alwaysKeep'], true);
      expect(preference['targetCoverageDays'], 14);
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset to defaults'));
      await tester.enterText(_field('Audit reason'), 'Remove custom policy');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(preference['minimumQuantity'], isNull);
      expect(preference['alwaysKeep'], false);
      expect(preference['expectedRevision'], 1);
      expect(preference['revision'], 2);
    },
  );

  testWidgets(
    'stock preference validation and conflict prevent blind overwrite',
    (tester) async {
      final session = await _session();
      final api = FakeApi((request) async {
        if (request.method == 'PUT') {
          throw const ApiException(statusCode: 409, message: 'Policy changed');
        }
        return jsonResponse({
          'homeProductId': _product,
          'minimumQuantity': '1',
          'alwaysKeep': false,
          'neverSuggest': false,
          'preferredPackId': null,
          'leadTimeDays': 0,
          'targetCoverageDays': null,
          'snoozeUntil': null,
          'revision': 3,
          'packOptions': <Object?>[],
        });
      });
      await _harness(
        tester,
        () => OperatorStockPreferenceEditor(
          repository: OperatorStockPreferenceRepository(api),
          session: session,
          homeId: _home,
          homeProductId: _product,
        ),
      );
      await tester.enterText(_field('Audit reason'), 'Change stock minimum');
      await tester.enterText(_field('Minimum quantity (optional)'), '-1');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('non-negative minimum quantity'),
        findsOneWidget,
      );
      expect(api.requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(_field('Minimum quantity (optional)'), '4');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Close and reload before retrying.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      session.authorizationLost();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    },
  );
}
