import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/catalog/catalog_maintenance_page.dart';

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

void main() {
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
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an audit reason.'), findsOneWidget);
      expect(api.requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(_field('canonical name'), 'Dry goods');
      await tester.enterText(_field('Audit reason'), 'Add pantry category');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Dry goods'), findsOneWidget);

      for (final action in ['Save', 'Archive', 'Restore']) {
        await tester.tap(find.text(action == 'Save' ? 'Dry goods' : 'Pantry'));
        await tester.pumpAndSettle();
        await tester.enterText(_field('canonical name'), 'Pantry');
        await tester.enterText(
          _field('Audit reason'),
          'Reviewed category change',
        );
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
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('canonical name'), 'Pantry');
    await tester.enterText(_field('Audit reason'), 'Create category');
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
    expect(api.requests.where((r) => r.method == 'PUT'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
