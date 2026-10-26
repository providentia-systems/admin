import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/workspace/operator_inventory_repository.dart';

import '../support/fake_api.dart';

void main() {
  const home = '60000000-0000-4000-8000-000000000001';
  const id = '60000000-0000-4000-8000-000000000002';
  const family = '60000000-0000-4000-8000-000000000003';

  test('Step 2 family-only records reopen without inventing a pack', () {
    for (var reopen = 0; reopen < 2; reopen++) {
      final record = OperatorInventoryRecord.fromRow(
        OperatorInventoryKind.product,
        <String, Object?>{
          'id': id,
          'revision': 7,
          'status': 'active',
          'product_id': family,
          'pack_id': null,
          'private_name': 'Original imported description',
          'original_pack_text': 'Unresolved original 2x wording',
        },
      );
      expect(record.id, id);
      expect(record.productId, family);
      expect(record.packId, isNull);
      expect(record.catalogBacked, isTrue);
      expect(record.packText, 'Unresolved original 2x wording');
      expect(record.revision, 7);
    }
  });

  test(
    'Step 2 family overrides retain identity and target household fields',
    () async {
      final api = FakeApi((request) async {
        expect(request.method, 'PATCH');
        expect(request.path, '/api/v1/admin/homes/$home/products/$id');
        expect(request.body, <String, Object?>{
          'expectedRevision': 7,
          'reason': 'Synthetic categorization',
          'privateName': 'Household description',
          'originalPackText': 'Original 2x wording',
          'homeCategoryId': null,
          'globalCategoryId': null,
        });
        return jsonResponse(<String, Object?>{'id': id});
      });
      await OperatorInventoryRepository(api).saveProduct(
        homeId: home,
        id: id,
        expectedRevision: 7,
        reason: 'Synthetic categorization',
        setPrivateName: true,
        privateName: 'Household description',
        setPackText: true,
        packText: 'Original 2x wording',
        setCategory: true,
      );
      expect(api.requests, hasLength(1));
    },
  );
}
