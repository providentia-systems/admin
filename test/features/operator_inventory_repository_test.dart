import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/workspace/operator_inventory_repository.dart';

import '../support/fake_api.dart';

const _home = '60000000-0000-4000-8000-000000000001';
const _product = '60000000-0000-4000-8000-000000000002';
const _category = '60000000-0000-4000-8000-000000000003';

void main() {
  test(
    'product records retain raw overrides independently of resolved fields',
    () {
      final record =
          OperatorInventoryRecord.fromRow(OperatorInventoryKind.product, {
            'id': _product,
            'revision': '9',
            'status': 'archived',
            'private_name': null,
            'original_pack_text': null,
            'home_category_id': null,
            'global_category_id': _category,
            'name': 'Catalog flour',
            'pack_text': '1 kg',
            'category_name': 'Global staples',
            'unit': 'kg',
          });
      expect(record.name, '');
      expect(record.packText, isNull);
      expect(record.homeCategoryId, isNull);
      expect(record.globalCategoryId, _category);
      expect(record.categoryName, 'Global staples');
      expect(record.resolvedName, 'Catalog flour');
      expect(record.resolvedPackText, '1 kg');
      expect(record.unit, 'kg');
      expect(record.revision, 9);
    },
  );

  test(
    'omitted metadata stays omitted and explicit null clears both scopes',
    () async {
      final api = FakeApi((_) async => jsonResponse({'revision': 10}));
      final repository = OperatorInventoryRepository(api);
      await repository.saveProduct(
        homeId: _home,
        id: _product,
        expectedRevision: 9,
        reason: ' Rename only ',
        setPrivateName: true,
        privateName: 'Household flour',
      );
      expect(api.requests.last.body, {
        'expectedRevision': 9,
        'reason': 'Rename only',
        'privateName': 'Household flour',
      });
      await repository.saveProduct(
        homeId: _home,
        id: _product,
        expectedRevision: 10,
        reason: 'Restore catalog fallback',
        setCategory: true,
      );
      expect(api.requests.last.body, {
        'expectedRevision': 10,
        'reason': 'Restore catalog fallback',
        'homeCategoryId': null,
        'globalCategoryId': null,
      });
      await repository.saveProduct(
        homeId: _home,
        id: _product,
        expectedRevision: 11,
        reason: 'Archive reviewed product',
        status: 'archived',
      );
      expect(api.requests.last.body, {
        'expectedRevision': 11,
        'reason': 'Archive reviewed product',
        'status': 'archived',
      });
    },
  );

  test('empty change rejects before any privileged request', () async {
    final api = FakeApi((_) async => jsonResponse({}));
    await expectLater(
      OperatorInventoryRepository(api).saveProduct(
        homeId: _home,
        id: _product,
        expectedRevision: 1,
        reason: 'Review',
      ),
      throwsFormatException,
    );
    expect(api.requests, isEmpty);
  });

  test(
    'global categories page beyond one hundred without losing choices',
    () async {
      final api = FakeApi((request) async {
        expect(request.path, '/api/v1/catalog/categories');
        expect(request.query!['limit'], '100');
        final offset = int.parse(request.query!['offset']!);
        return jsonResponse({
          'data': [
            for (var index = offset; index < (offset == 0 ? 100 : 101); index++)
              {
                'id':
                    '60000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
                'canonicalName': 'Category $index',
                'revision': 1,
              },
          ],
        });
      });
      final categories = await OperatorInventoryRepository(
        api,
      ).globalCategories();
      expect(categories, hasLength(101));
      expect(categories.last.canonicalName, 'Category 100');
      expect(api.requests.map((request) => request.query!['offset']), [
        '0',
        '100',
      ]);
    },
  );
}
