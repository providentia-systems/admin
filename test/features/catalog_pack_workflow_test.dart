import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/catalog/catalog_operations_page.dart';

import '../support/fake_api.dart';
import '../support/memory_credential_store.dart';

const _productId = '0198f4e1-7abc-7def-8abc-0123456789ab';
const _packId = '0198f4e2-7abc-7def-8abc-0123456789ab';
const _unitId = '0198f4e3-7abc-7def-8abc-0123456789ab';
const _categoryId = '0198f4e4-7abc-7def-8abc-0123456789ab';

Map<String, Object?> _pack({int revision = 4}) => {
  'id': _packId,
  'type': 'pack',
  'status': 'published',
  'revision': revision,
  'fields': <String, Object?>{
    'productId': _productId,
    'variantId': null,
    'unitId': _unitId,
    'originalPackText': '4 × 1 kg',
    'amount': '1',
    'multiplicity': '4',
  },
};

Future<void> _pump(WidgetTester tester, FakeApi api) async {
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
  addTearDown(session.dispose);
  await tester.binding.setSurfaceSize(const Size(1500, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CatalogOperationsPage(
          api: api,
          session: session,
          canReview: false,
          canCurate: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('select-canonical-product')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('published-product-$_productId')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('choose-published-product')));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

FakeApi _api({
  required List<Map<String, Object?>> packs,
  bool conflict = false,
  int? publishedRevision,
  bool missingPack = false,
}) => FakeApi((request) async {
  if (request.method == 'PUT') {
    if (conflict) {
      throw const ApiException(statusCode: 409, message: 'Conflict');
    }
    final body = request.body! as Map<String, Object?>;
    final saved = {
      'id': request.path.split('/').last,
      'type': 'pack',
      'status': body['status'],
      'revision': (body['expectedRevision']! as int) + 1,
      'fields': body['fields'],
    };
    packs.removeWhere((pack) => pack['id'] == saved['id']);
    packs.add(saved);
    publishedRevision = null;
    return jsonResponse(saved);
  }
  switch (request.path) {
    case '/api/v1/catalog/products':
      return jsonResponse({
        'data': [
          {
            'id': _productId,
            'canonicalName': 'Apples',
            'brand': '',
            'category': 'Fruit',
            'revision': 2,
            'packId': null,
            'packText': null,
            'packStatus': null,
          },
        ],
        'pagination': {'limit': 50, 'offset': 0},
      });
    case '/api/v1/catalog/products/$_productId':
      return jsonResponse({
        'id': _productId,
        'requestedId': _productId,
        'redirected': false,
        'canonicalName': 'Apples',
        'brand': '',
        'category': 'Fruit',
        'categoryId': _categoryId,
        'revision': 2,
        'icons': <Object?>[],
        'packs': [
          for (final pack in packs)
            {
              'id': pack['id'],
              'revision': publishedRevision ?? pack['revision'],
              'packText': (pack['fields']! as Map)['originalPackText'],
              'amount': (pack['fields']! as Map)['amount'],
              'multiplicity': int.parse(
                (pack['fields']! as Map)['multiplicity']! as String,
              ),
              'normalizedBaseAmount': '4000.00000000',
            },
        ],
      });
    case '/api/v1/catalog-admin/entities/product':
      expect(request.query!['productId'], _productId);
      return jsonResponse({
        'data': [
          {
            'id': _productId,
            'type': 'product',
            'status': 'published',
            'revision': 2,
            'fields': {
              'canonicalName': 'Apples',
              'brand': '',
              'categoryId': _categoryId,
            },
          },
        ],
      });
    case '/api/v1/catalog-admin/entities/unit':
      return jsonResponse({
        'data': [
          {
            'id': _unitId,
            'type': 'unit',
            'status': 'published',
            'revision': 1,
            'fields': {
              'symbol': 'kg',
              'name': 'Kilograms',
              'dimension': 'mass',
              'baseFactor': '1000',
            },
          },
        ],
      });
    case '/api/v1/catalog-admin/entities/pack':
      expect(request.query!['productId'], _productId);
      return jsonResponse({'data': missingPack ? <Object?>[] : packs});
    default:
      return jsonResponse({'data': <Object?>[]});
  }
});

void main() {
  testWidgets(
    'direct pack creation stays linked and refreshes published detail',
    (tester) async {
      final packs = <Map<String, Object?>>[];
      final api = _api(packs: packs);
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('add-canonical-pack')));
      await tester.pumpAndSettle();
      expect(find.text('Create pack'), findsOneWidget);
      final product = find.widgetWithText(
        DropdownButtonFormField<String>,
        'product id',
      );
      expect(
        tester.widget<DropdownButtonFormField<String>>(product).onChanged,
        isNull,
      );
      await tester.enterText(_field('Pack description'), '4 × 1 kg');
      await tester.enterText(_field('Amount per unit'), '1');
      await tester.enterText(_field('Units per pack'), '4');
      final unit = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Measurement unit',
      );
      await tester.ensureVisible(unit);
      await tester.tap(unit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kilograms').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final write = api.requests.singleWhere(
        (request) => request.method == 'PUT',
      );
      expect(write.body, {
        'fields': {
          'productId': _productId,
          'variantId': null,
          'unitId': _unitId,
          'originalPackText': '4 × 1 kg',
          'amount': '1',
          'multiplicity': '4',
        },
        'status': 'published',
        'expectedRevision': 0,
        'reason': 'Add catalog identity',
      });
      expect(find.text('Published packs (1)'), findsOneWidget);
      expect(find.text('4 × 1 kg'), findsOneWidget);
      expect(find.text('Create pack'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('direct pack editing loads current fields and revision', (
    tester,
  ) async {
    final api = _api(packs: [_pack(revision: 8)], publishedRevision: 4);
    await _pump(tester, api);
    final edit = find.byKey(const Key('edit-canonical-pack-$_packId'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Edit pack'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('Amount per unit')).controller!.text,
      '1',
    );
    expect(
      tester.widget<TextField>(_field('Units per pack')).controller!.text,
      '4',
    );
    await tester.enterText(_field('Pack description'), 'Four 1 kg bags');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final body =
        api.requests.singleWhere((r) => r.method == 'PUT').body! as Map;
    expect(body['expectedRevision'], 8);
    expect((body['fields']! as Map)['unitId'], _unitId);
    expect((body['fields']! as Map)['productId'], _productId);
    expect(find.text('Four 1 kg bags'), findsOneWidget);
    expect(find.text('Multiplicity: 4 · revision 9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pack conflicts prevent blind retry and retain typed corrections',
    (tester) async {
      final api = _api(packs: [_pack()], conflict: true);
      await _pump(tester, api);
      final edit = find.byKey(const Key('edit-canonical-pack-$_packId'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(_field('Pack description'), 'Four 1 kg bags');
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
      expect(api.requests.where((r) => r.method == 'PUT'), hasLength(1));
      expect(
        tester.widget<TextField>(_field('Pack description')).controller!.text,
        'Four 1 kg bags',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing pack fails safely and Reload fetches published detail', (
    tester,
  ) async {
    final api = _api(packs: [_pack()], missingPack: true);
    await _pump(tester, api);
    final edit = find.byKey(const Key('edit-canonical-pack-$_packId'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Edit pack'), findsNothing);
    expect(
      find.text('The pack could not be loaded safely. Reload and try again.'),
      findsOneWidget,
    );
    final detailReads = api.requests
        .where(
          (request) => request.path == '/api/v1/catalog/products/$_productId',
        )
        .length;
    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(
      api.requests
          .where(
            (request) => request.path == '/api/v1/catalog/products/$_productId',
          )
          .length,
      detailReads + 1,
    );
    expect(api.requests.where((request) => request.method == 'PUT'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
