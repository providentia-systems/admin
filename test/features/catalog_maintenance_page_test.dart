import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/catalog/catalog_maintenance_page.dart';
import 'package:providentia_admin/features/catalog/catalog_maintenance_repository.dart';

import '../support/fake_api.dart';
import '../support/memory_credential_store.dart';

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
            'features': {'catalogReview': true, 'catalogCurate': true},
          },
        },
      }),
    ),
  );
  await session.restore();
  expect(session.phase, SessionPhase.authenticated);
  return session;
}

Future<void> _pump(WidgetTester tester, FakeApi api) async {
  final session = await _session();
  addTearDown(session.dispose);
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: CatalogMaintenancePage(api: api, session: session, canCurate: true),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _otherReason(WidgetTester tester, String explanation) async {
  final choice = find.byKey(const Key('catalog-reason-choice'));
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Other').last);
  await tester.pumpAndSettle();
  final field = find.byKey(const Key('catalog-reason-other'));
  await tester.ensureVisible(field);
  await tester.enterText(field, explanation);
}

void main() {
  test(
    'maintenance repository forwards bounded search and offset to the same endpoint',
    () async {
      final api = FakeApi((request) async {
        expect(request.path, '/api/v1/catalog-admin/entities/category');
        expect(request.query, {'offset': '100', 'q': 'Pantry'});
        return jsonResponse({'data': []});
      });
      expect(
        await CatalogMaintenanceRepository(
          api,
        ).list('category', offset: 100, query: ' Pantry '),
        isEmpty,
      );
      expect(api.requests, hasLength(1));
    },
  );

  testWidgets(
    'dirty editor keeps text until explicit discard and does not write',
    (tester) async {
      final api = FakeApi((_) async => jsonResponse({'data': []}));
      await _pump(tester, api);
      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('canonical name'), 'Unsaved pantry');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_field('canonical name')).controller!.text,
        'Unsaved pantry',
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsNothing);
      expect(api.requests.where((request) => request.method == 'PUT'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'direct Products and Categories keep independent search context',
    (tester) async {
      final api = FakeApi((_) async => jsonResponse({'data': []}));
      await _pump(tester, api);
      final search = find.byKey(const Key('catalog-entity-search'));
      await tester.enterText(search, 'Pantry');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(api.requests.last.query?['q'], 'Pantry');
      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();
      expect(api.requests.last.path, '/api/v1/catalog-admin/entities/product');
      expect(find.text('Add product'), findsOneWidget);
      await tester.enterText(search, 'Rice');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, 'Pantry');
      expect(api.requests.last.query?['q'], 'Pantry');
      expect(api.requests.last.query?['offset'], '0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category create, edit, archive and restore use current revisions',
    (tester) async {
      Map<String, Object?>? entity;
      final api = FakeApi((request) async {
        if (request.method == 'GET') {
          return jsonResponse({
            'data': [?entity],
          });
        }
        final body = request.body! as Map<String, Object?>;
        entity = {
          'id': request.path.split('/').last,
          'type': 'category',
          'status': body['status'],
          'revision': (body['expectedRevision']! as int) + 1,
          'fields': body['fields'],
        };
        return jsonResponse(entity!);
      });
      await _pump(tester, api);
      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();
      await _otherReason(tester, '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter an audit reason of no more than 500 characters.'),
        findsOneWidget,
      );
      expect(api.requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(_field('canonical name'), 'Dry goods');
      await tester.enterText(
        find.byKey(const Key('catalog-reason-other')),
        'Add pantry category',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Dry goods'), findsOneWidget);

      for (final action in ['Save', 'Archive', 'Restore']) {
        await tester.tap(find.text(action == 'Save' ? 'Dry goods' : 'Pantry'));
        await tester.pumpAndSettle();
        await tester.enterText(_field('canonical name'), 'Pantry');
        await _otherReason(tester, 'Reviewed category change');
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final writes = api.requests.where((r) => r.method == 'PUT').toList();
      expect(writes.map((r) => (r.body! as Map)['expectedRevision']), [
        0,
        1,
        2,
        3,
      ]);
      expect(writes.map((r) => (r.body! as Map)['status']), [
        'published',
        'published',
        'archived',
        'published',
      ]);
      expect(find.text('published · revision 4'), findsOneWidget);
    },
  );

  testWidgets('conflict requires reload and prevents blind retry', (
    tester,
  ) async {
    final api = FakeApi((request) async {
      if (request.method == 'GET') return jsonResponse({'data': []});
      throw const ApiException(statusCode: 409, message: 'Conflict');
    });
    await _pump(tester, api);
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('canonical name'), 'Pantry');
    await _otherReason(tester, 'Create category');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Close and refresh before retrying.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(api.requests.where((r) => r.method == 'PUT'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
