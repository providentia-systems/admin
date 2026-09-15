import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/catalog/catalog_models.dart';
import 'package:providentia_admin/features/catalog/catalog_page.dart';

import '../support/fake_api.dart';
import '../support/memory_credential_store.dart';

void main() {
  for (final field in [
    'homeId',
    'quantity',
    'location',
    'email',
    'receiptId',
    'rawImage',
    'notes',
  ]) {
    test('identity projection rejects private $field before presentation', () {
      final row = _row();
      (row['payload']! as Map<String, Object?>)[field] = 'PRIVATE';
      expect(() => CatalogQueueItem.fromJson(row), throwsFormatException);
    });
  }
  test('proposal moderation status and type retain their current revision', () {
    final item = CatalogQueueItem.fromJson({
      'id': _id,
      'proposalType': 'product',
      'moderationStatus': 'pending',
      'revision': 4,
      'canonicalName': 'Synthetic rice',
    });
    expect(item.kind, 'product');
    expect(item.status, 'pending');
    expect(item.revision, 4);
  });
  for (final canCurate in [true, false]) {
    testWidgets('pending queue approval retains item for curator=$canCurate', (
      tester,
    ) async {
      var approved = false;
      final api = FakeApi((request) async {
        if (request.path.endsWith('/decision')) {
          expect(request.method, 'PUT');
          expect(request.body, {
            'decision': 'approved',
            'reason': 'Synthetic reviewed identity',
            'expectedRevision': 1,
          });
          approved = true;
          return jsonResponse({});
        }
        if (request.path.endsWith('/workbench')) {
          return jsonResponse({'data': <Object?>[]});
        }
        expect(request.path, '/api/v1/catalog-contributions/review');
        expect(request.query?['status'], approved ? 'approved' : 'pending');
        return jsonResponse({
          'data': [_row(approved: approved)],
        });
      });
      final store = MemoryCredentialStore(installationId: memoryInstallationId)
        ..session = memoryStoredSession();
      final session = SessionController(
        credentialStore: store,
        api: FakeApi(
          (_) async => jsonResponse({
            'userId': store.session['userId'],
            'profile': {
              'administratorAccess': {
                'features': {'catalogReview': true, 'catalogCurate': canCurate},
              },
            },
          }),
        ),
      );
      await session.restore();
      addTearDown(session.dispose);
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogPage(
              api: api,
              session: session,
              canReview: true,
              canCurate: canCurate,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contributions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic rice'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('approve-moderation-item')),
      );
      await tester.tap(find.byKey(const Key('approve-moderation-item')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Synthetic reviewed identity',
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(approved, isTrue);
      expect(find.text('Revision 2'), findsOneWidget);
      expect(
        find.textContaining('Not published: link a product proposal next.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('link-product-proposal')),
        canCurate ? findsOneWidget : findsNothing,
      );
      expect(
        api.requests.where((request) => request.method == 'PUT'),
        hasLength(1),
      );
      expect(
        api.requests.any((request) => request.path.endsWith('/proposal')),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Map<String, Object?> _row({bool approved = false}) => {
  'id': _id,
  'contributionType': 'product_identity',
  'status': approved ? 'approved' : 'pending',
  'revision': approved ? 2 : 1,
  'payload': <String, Object?>{
    'canonicalName': 'Synthetic rice',
    'brand': null,
    'categoryLabel': 'Pantry',
    'barcode': null,
    'packText': '1 kg',
  },
  'consentNoticeVersion': 1,
  'consentRevision': 1,
  'createdAt': '2026-09-14T12:00:00Z',
};
const _id = '0198f4e3-7abc-7def-8abc-0123456789ab';
