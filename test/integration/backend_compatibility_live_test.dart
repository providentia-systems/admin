import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/features/access/access_repository.dart';
import 'package:providentia_admin/features/workspace/operator_inventory_repository.dart';

// Invoked only by the paired lane, which owns the disposable backend database
// and ephemeral native sessions. Ordinary source tests require no HTTP service.
void main() {
  final fixturePath =
      Platform.environment['PROVIDENTIA_ADMIN_COMPATIBILITY_FIXTURE'];
  final backendUrl =
      Platform.environment['PROVIDENTIA_ADMIN_COMPATIBILITY_URL'];
  if (fixturePath != null || backendUrl != null) {
    final origin = Uri.tryParse(backendUrl ?? '');
    if (fixturePath == null ||
        origin == null ||
        origin.scheme != 'http' ||
        origin.host != '127.0.0.1' ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw StateError('An explicit disposable loopback fixture is required.');
    }
  }
  test(
    'native Admin adapters preserve resolved inventory, overrides and backend guards',
    () async {
      final fixture = _object(
        jsonDecode(await File(fixturePath!).readAsString()),
      );
      final inventory = _object(fixture['adminCompatibility']);
      final sessions = _object(fixture['sessions']);
      final client = http.Client();
      addTearDown(client.close);
      var resourceForbidden = 0;
      var identityLost = 0;
      ApiClient apiFor(String actor) => ApiClient(
        baseUri: validateBackendUri(Uri.parse(backendUrl!)),
        httpClient: client,
        accessTokenProvider: () =>
            _object(sessions[actor])['accessToken'] as String,
        ensureAccessToken: ({required force}) async => true,
        onAuthorizationLost: () => identityLost++,
        onResourceForbidden: () => resourceForbidden++,
      );
      var phase = 'read homes, products, categories and stock';
      try {
        final api = apiFor('alice');
        final repository = OperatorInventoryRepository(api);
        final homeId = fixture['homeId'] as String;
        final linkedId = inventory['linkedId'] as String;
        final privateId = inventory['privateId'] as String;
        final localCategoryId = inventory['localCategoryId'] as String;
        final globalCategoryId = inventory['globalCategoryId'] as String;
        final homes =
            (await api.get('/api/v1/admin/homes')).jsonObject['data']
                as List<Object?>;
        expect(homes.any((row) => _object(row)['id'] == homeId), isTrue);
        expect(
          (await api.get('/api/v1/admin/homes/$homeId')).jsonObject['id'],
          homeId,
        );
        expect(
          (await repository.categories(
            homeId,
          )).any((row) => row.id == localCategoryId),
          isTrue,
        );
        expect(
          (await repository.globalCategories()).any(
            (row) => row.id == globalCategoryId,
          ),
          isTrue,
        );

        Future<List<Map<String, Object?>>> records(String collection) async {
          final data =
              (await api.get(
                    '/api/v1/admin/homes/$homeId/records/$collection',
                    query: {'offset': '0'},
                  )).jsonObject['data']
                  as List<Object?>;
          return data.map(_object).toList(growable: false);
        }

        Future<Map<String, Object?>> product() async => (await records(
          'products',
        )).singleWhere((row) => row['id'] == linkedId);
        var row = await product();
        expect(row['name'], inventory['canonicalName']);
        expect(row['pack_text'], inventory['canonicalPack']);
        expect(row['category_scope'], 'Global');
        expect(row['home_category_id'], isNull);
        expect(row['global_category_id'], isNull);
        final original = OperatorInventoryRecord.fromRow(
          OperatorInventoryKind.product,
          row,
        );
        final stock = await records('stock');
        final linkedStock = stock.singleWhere(
          (balance) => balance['home_product_id'] == linkedId,
        );
        expect(linkedStock['name'], inventory['canonicalName']);
        expect(linkedStock['pack_text'], '2 kg');
        expect(linkedStock['unit'], 'kg');
        expect('${linkedStock['quantity']}', matches(RegExp(r'^-0\.1250*$')));
        final privateStock = stock.singleWhere(
          (balance) => balance['home_product_id'] == privateId,
        );
        expect(privateStock['name'], 'Synthetic private stock');
        expect(privateStock['pack_text'], 'Not specified');
        expect('${privateStock['quantity']}', matches(RegExp(r'^0(?:\.0+)?$')));

        phase = 'save household name, pack and local category';
        await repository.saveProduct(
          homeId: homeId,
          id: linkedId,
          expectedRevision: original.revision,
          reason: 'Synthetic household override acceptance',
          setPrivateName: true,
          privateName: 'Synthetic household name',
          setPackText: true,
          packText: 'Household pack label',
          setCategory: true,
          homeCategoryId: localCategoryId,
        );
        row = await product();
        expect(row['id'], linkedId);
        expect(row['name'], 'Synthetic household name');
        expect(row['pack_text'], 'Household pack label');
        expect(row['category_name'], 'Synthetic local pantry');
        expect(row['global_category_id'], isNull);
        var revision = int.parse('${row['revision']}');
        await expectLater(
          repository.saveProduct(
            homeId: homeId,
            id: linkedId,
            expectedRevision: original.revision,
            reason: 'Synthetic stale revision',
            setPrivateName: true,
            privateName: 'Must not save',
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.isConflict,
              'revision conflict',
              isTrue,
            ),
          ),
        );
        await repository.saveProduct(
          homeId: homeId,
          id: linkedId,
          expectedRevision: revision,
          reason: 'Synthetic global override acceptance',
          setCategory: true,
          globalCategoryId: globalCategoryId,
        );
        row = await product();
        expect(row['home_category_id'], isNull);
        expect(row['global_category_id'], globalCategoryId);
        revision = int.parse('${row['revision']}');
        await repository.saveProduct(
          homeId: homeId,
          id: linkedId,
          expectedRevision: revision,
          reason: 'Synthetic inherited fallback acceptance',
          setPrivateName: true,
          privateName: null,
          setPackText: true,
          packText: null,
          setCategory: true,
        );
        row = await product();
        expect(row['name'], inventory['canonicalName']);
        expect(row['pack_text'], inventory['canonicalPack']);
        expect(row['home_category_id'], isNull);
        expect(row['global_category_id'], isNull);
        expect(row['category_scope'], 'Global');
        revision = int.parse('${row['revision']}');
        await expectLater(
          repository.saveProduct(
            homeId: homeId,
            id: linkedId,
            expectedRevision: revision,
            reason: 'Synthetic history guard acceptance',
            unit: 'g',
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.isConflict,
              'history conflict',
              isTrue,
            ),
          ),
        );
        row = await product();
        expect(row['unit'], 'kg');
        expect(int.parse('${row['revision']}'), revision);
        final afterStock = (await records(
          'stock',
        )).singleWhere((balance) => balance['home_product_id'] == linkedId);
        expect(afterStock['quantity'], linkedStock['quantity']);

        // A valid household identity without administrator grants receives 403.
        // The transport invalidates the resource without destroying its identity.
        await expectLater(
          apiFor('bob').get('/api/v1/admin/homes/$homeId/records/products'),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.isForbidden,
              'operator authorization',
              isTrue,
            ),
          ),
        );
        expect(resourceForbidden, 1);
        expect(identityLost, 0);

        // Grant, then remove operator access while preserving the same native
        // session. Every request must observe the backend's current capabilities.
        phase = 'grant delegated operator capability';
        final access = AccessRepository(api);
        final readerGroup = await access.save({
          'scope': 'admin',
          'name': 'Synthetic paired reader',
          'description': 'Disposable operator authorization acceptance',
          'features': <String, Object?>{'homes.read': true},
          'limits': <String, Object?>{},
          'delegablePermissions': <String>[],
          'rolePermissions': <String, Object?>{},
          'revision': 0,
        });
        final bobId = _object(sessions['bob'])['userId'] as String;
        await api.post(
          '/api/v1/admin/administrators/$bobId/review',
          body: {
            'status': 'approved',
            'groupId': readerGroup['id'],
            'expectedRevision': inventory['administratorRequestRevision'],
            'assignmentRevision': 0,
          },
        );
        phase = 'read with delegated operator capability';
        final delegatedApi = apiFor('bob');
        expect(
          (await delegatedApi.get(
            '/api/v1/admin/homes/$homeId/records/products',
          )).statusCode,
          200,
        );
        phase = 'revoke delegated operator capability';
        final readerRevision = int.parse('${readerGroup['revision']}');
        await access.save({
          ...readerGroup,
          'features': <String, Object?>{},
          'revision': readerRevision,
        });
        await expectLater(
          delegatedApi.get('/api/v1/admin/homes/$homeId/records/products'),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.isForbidden,
              'revoked operator capability',
              isTrue,
            ),
          ),
        );
        expect(resourceForbidden, 2);
        expect(identityLost, 0);
        phase = 'restore delegated operator capability';
        // Re-granting access demonstrates that the session was retained and that
        // the failed resource response was not a successful stale projection.
        await access.save({
          ...readerGroup,
          'features': <String, Object?>{'homes.read': true},
          'revision': readerRevision + 1,
        });
        expect(
          (await delegatedApi.get(
            '/api/v1/admin/homes/$homeId/records/products',
          )).statusCode,
          200,
        );
      } on ApiException catch (error) {
        fail('Live compatibility phase $phase failed: $error');
      }
    },
    skip: fixturePath == null || backendUrl == null
        ? 'Run through tool/run_backend_compatibility.sh with a disposable paired backend.'
        : false,
  );
}

Map<String, Object?> _object(Object? value) =>
    (value! as Map).cast<String, Object?>();
