import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/catalog/catalog_maintenance_repository.dart';
import '../support/fake_api.dart';

const _id = '0198f4e1-7abc-7def-8abc-0123456789ab';
void main() {
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
