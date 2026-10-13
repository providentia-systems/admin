import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/catalog/catalog_maintenance_repository.dart';
import '../support/fake_api.dart';

const _id = '0198f4e1-7abc-7def-8abc-0123456789ab';
void main() {
  Map<String, Object?> pack(String id, {String productId = _id}) => {
    'id': id,
    'type': 'pack',
    'status': 'published',
    'revision': 5,
    'fields': {
      'productId': productId,
      'variantId': null,
      'unitId': null,
      'originalPackText': '1 kg',
      'amount': '1',
      'multiplicity': '1',
    },
  };

  test(
    'direct pack editing finds current identity beyond the first page',
    () async {
      const targetId = '0198f4e2-7abc-7def-8abc-0123456789ab';
      final api = FakeApi((request) async {
        expect(request.path, '/api/v1/catalog-admin/entities/pack');
        expect(request.query!['productId'], _id);
        return jsonResponse({
          'data': request.query!['offset'] == '0'
              ? [
                  for (var index = 0; index < 100; index++)
                    pack(
                      '0198f4e1-7abc-7def-8abc-${index.toString().padLeft(12, '0')}',
                    ),
                ]
              : [pack(targetId)],
        });
      });
      final entity = await CatalogMaintenanceRepository(
        api,
      ).productPack(_id, targetId);
      expect(entity.id, targetId);
      expect(entity.revision, 5);
      expect(api.requests.map((request) => request.query!['offset']), [
        '0',
        '100',
      ]);
    },
  );

  test('missing or cross-product pack cannot enter the editor', () async {
    const targetId = '0198f4e2-7abc-7def-8abc-0123456789ab';
    for (final rows in [
      <Object?>[],
      [pack(targetId, productId: targetId)],
    ]) {
      final api = FakeApi((_) async => jsonResponse({'data': rows}));
      await expectLater(
        CatalogMaintenanceRepository(api).productPack(_id, targetId),
        throwsFormatException,
      );
      expect(api.requests, hasLength(1));
    }
  });

  test('edits preserve the entity revision and audit reason', () async {
    final api = FakeApi(
      (request) async => jsonResponse({
        'id': _id,
        'type': 'category',
        'status': 'archived',
        'revision': 4,
        'fields': {'canonicalName': 'Dry goods'},
      }),
    );
    final result = await CatalogMaintenanceRepository(api).save(
      type: 'category',
      id: _id,
      revision: 3,
      status: 'archived',
      reason: 'Duplicate retired',
      fields: {'canonicalName': 'Dry goods'},
    );
    expect(result.revision, 4);
    expect(result.status, 'archived');
    expect(
      api.requests.single.path,
      '/api/v1/catalog-admin/entities/category/$_id',
    );
    expect(api.requests.single.body, {
      'fields': {'canonicalName': 'Dry goods'},
      'status': 'archived',
      'expectedRevision': 3,
      'reason': 'Duplicate retired',
    });
  });
  test('cross-type and private-field responses fail closed', () async {
    final api = FakeApi(
      (_) async => jsonResponse({
        'data': [
          {
            'id': _id,
            'type': 'product',
            'status': 'published',
            'revision': 1,
            'fields': {'canonicalName': 'Rice', 'brand': '', 'categoryId': _id},
          },
        ],
      }),
    );
    await expectLater(
      CatalogMaintenanceRepository(api).list('category'),
      throwsFormatException,
    );
    expect(
      () => CatalogEntity.fromJson({
        'id': _id,
        'type': 'category',
        'status': 'published',
        'revision': 1,
        'fields': {'canonicalName': 'Private', 'homeId': _id},
      }),
      throwsFormatException,
    );
  });
}
