import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/catalog/catalog_operations_models.dart';
import 'package:providentia_admin/features/catalog/catalog_product_inspection.dart';

const _id = '0198f4e1-7abc-7def-8abc-0123456789ab';
Map<String, Object?> _detail() => {
  'id': _id,
  'requestedId': _id,
  'redirected': false,
  'canonicalName': 'Rice',
  'brand': '',
  'categoryId': _id,
  'category': 'Pantry',
  'revision': 2,
  'icons': <Object?>[],
  'packs': <Object?>[
    {
      'id': _id,
      'packText': '3 x 0.125 kg',
      'amount': '0.125',
      'normalizedBaseAmount': '375.00000000',
      'multiplicity': 3,
      'revision': 4,
    },
  ],
};

void main() {
  testWidgets(
    'published detail retains exact measures and opens product master',
    (tester) async {
      var opened = false;
      final product = CatalogProductDetail.fromJson(_detail());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogProductInspection(
              product: product,
              onManage: () => opened = true,
            ),
          ),
        ),
      );
      expect(find.text('Brand: Missing'), findsOneWidget);
      expect(find.text('3 x 0.125 kg'), findsOneWidget);
      expect(find.text('Normalized base amount: 375.00000000'), findsOneWidget);
      expect(product.packs.single.revision, 4);
      await tester.tap(find.text('Manage product, packs and identities'));
      expect(opened, isTrue);
    },
  );
  testWidgets('pack controls identify the selected published pack', (
    tester,
  ) async {
    var added = false;
    CatalogPackSummary? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogProductInspection(
            product: CatalogProductDetail.fromJson(_detail()),
            onManage: () {},
            onAddPack: () => added = true,
            onEditPack: (pack) => edited = pack,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('add-canonical-pack')));
    expect(added, isTrue);
    final edit = find.byKey(const Key('edit-canonical-pack-$_id'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    expect(edited?.id, _id);
    expect(edited?.revision, 4);
    expect(tester.takeException(), isNull);
  });
  test('malformed nested pack fails closed instead of being discarded', () {
    final detail = _detail();
    ((detail['packs']! as List<Object?>).single!
            as Map<String, Object?>)['multiplicity'] =
        '3';
    expect(() => CatalogProductDetail.fromJson(detail), throwsFormatException);
  });
}
