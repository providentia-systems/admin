import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/catalog/catalog_operations_models.dart';
import 'package:providentia_admin/features/catalog/catalog_operations_repository.dart';
import 'package:providentia_admin/features/catalog/published_product_picker.dart';

import '../support/fake_api.dart';

const productId = '0198f4e1-7abc-7def-8abc-0123456789ab';
const duplicateId = '0198f4e2-7abc-7def-8abc-0123456789ab';
const categoryId = '0198f4e3-7abc-7def-8abc-0123456789ab';
const iconId = '0198f4e4-7abc-7def-8abc-0123456789ab';
const conflictId = '0198f4e5-7abc-7def-8abc-0123456789ab';
const mergeId = '0198f4e6-7abc-7def-8abc-0123456789ab';
const digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const productSummary = <String, Object?>{
  'id': productId,
  'canonicalName': 'Brown rice',
  'brand': 'Providentia',
  'category': 'Rice',
  'revision': 7,
  'packId': null,
  'packText': null,
  'packStatus': null,
};

Map<String, Object?> productDetail({
  String requestedId = productId,
  String id = productId,
  bool redirected = false,
}) => <String, Object?>{
  'id': id,
  'requestedId': requestedId,
  'redirected': redirected,
  'canonicalName': 'Brown rice',
  'brand': 'Providentia',
  'categoryId': categoryId,
  'category': 'Rice',
  'revision': 7,
  'packs': <Object?>[],
  'icons': <Object?>[
    <String, Object?>{
      'id': iconId,
      'assetDigest': digest,
      'mediaType': 'image/webp',
      'altText': 'Bag of brown rice',
      'revision': 3,
    },
  ],
};

Map<String, Object?> mergePreview() => <String, Object?>{
  'survivorId': productId,
  'duplicateIds': <Object?>[duplicateId],
  'eligible': true,
  'products': <Object?>[
    <String, Object?>{
      'id': productId,
      'canonicalName': 'Brown rice',
      'brand': 'Providentia',
      'status': 'published',
      'revision': 7,
    },
    <String, Object?>{
      'id': duplicateId,
      'canonicalName': 'Brown rice 1kg',
      'brand': 'Providentia',
      'status': 'published',
      'revision': 4,
    },
  ],
  'affectedCounts': <String, Object?>{
    'variants': 1,
    'packs': 2,
    'aliases': 3,
    'icons': 1,
    'homeReferences': 5,
    'futurePrivateDetail': 99,
  },
  'conflicts': <Object?>[],
};

void main() {
  group('CatalogOperationsRepository identities', () {
    test('searches a bounded product page with exact pagination', () async {
      final api = FakeApi(
        (_) async => jsonResponse(<String, Object?>{
          'data': <Object?>[productSummary],
          'pagination': <String, Object?>{'limit': 50, 'offset': 0},
        }),
      );

      final page = await CatalogOperationsRepository(
        api,
      ).searchProducts(query: ' rice ', limit: 50, offset: 0);

      expect(page.data.single.id, productId);
      expect(api.requests.single.path, '/api/v1/catalog/products');
      expect(api.requests.single.query, <String, String>{
        'q': 'rice',
        'limit': '50',
        'offset': '0',
      });
    });

    test('loads detail and derives the exact active icon revision', () async {
      final api = FakeApi((_) async => jsonResponse(productDetail()));

      final detail = await CatalogOperationsRepository(api).product(productId);

      expect(detail.currentIconRevision, 3);
      expect(api.requests.single.path, '/api/v1/catalog/products/$productId');
    });

    test('rejects a response bound to another requested product', () async {
      final api = FakeApi(
        (_) async => jsonResponse(
          productDetail(requestedId: duplicateId, id: duplicateId),
        ),
      );

      await expectLater(
        CatalogOperationsRepository(api).product(productId),
        throwsA(
          isA<CatalogOperationsFailure>().having(
            (failure) => failure.safeMessage,
            'safeMessage',
            'Catalog data could not be read safely.',
          ),
        ),
      );
    });

    test('loads only typed published category identity', () async {
      final api = FakeApi(
        (_) async => jsonResponse(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'id': categoryId,
              'canonicalName': 'Rice',
              'revision': 2,
              'unexpectedPrivateField': 'ignored',
            },
          ],
          'pagination': <String, Object?>{'limit': 100, 'offset': 0},
        }),
      );

      final categories = await CatalogOperationsRepository(
        api,
      ).searchCategories('Rice');

      expect(categories.single.canonicalName, 'Rice');
      expect(api.requests.single.path, '/api/v1/catalog/categories');
    });
  });

  testWidgets('product picker loads exact detail before selection', (
    tester,
  ) async {
    final api = FakeApi((request) async {
      if (request.path == '/api/v1/catalog/products') {
        return jsonResponse(<String, Object?>{
          'data': <Object?>[productSummary],
          'pagination': <String, Object?>{'limit': 50, 'offset': 0},
        });
      }
      return jsonResponse(productDetail());
    });
    final operations = CatalogOperationsRepository(api);
    CatalogProductDetail? chosen;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                chosen = await showPublishedProductPicker(
                  context: context,
                  operations: operations,
                );
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(find.text('Brown rice'), findsOneWidget);

    await tester.tap(find.byKey(const Key('published-product-$productId')));
    await tester.pumpAndSettle();
    expect(find.text('Current icon revision 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('choose-published-product')));
    await tester.pumpAndSettle();
    expect(chosen?.id, productId);
  });

  group('CatalogOperationsRepository governance', () {
    test('keeps an existing conflict with reason and revision', () async {
      final conflict = CatalogConflict.fromJson(<String, Object?>{
        'id': conflictId,
        'conflictType': 'duplicate',
        'conflictKey': 'brown rice',
        'status': 'open',
        'revision': 6,
        'existingEntityId': productId,
        'candidateEntityId': duplicateId,
      });
      final api = FakeApi((_) async => jsonResponse(const <String, Object?>{}));

      await CatalogOperationsRepository(
        api,
      ).keepExisting(conflict: conflict, reason: ' Canonical record verified ');

      expect(
        api.requests.single.path,
        '/api/v1/catalog-admin/conflicts/$conflictId/keep-existing',
      );
      expect(api.requests.single.body, <String, Object?>{
        'reason': 'Canonical record verified',
        'expectedRevision': 6,
      });
    });

    test('puts content-addressed icon metadata at current revision', () async {
      final api = FakeApi(
        (_) async =>
            jsonResponse(<String, Object?>{'id': iconId, 'revision': 4}),
      );
      final command = CatalogIconCommand(
        targetType: CatalogIconTargetType.product,
        targetId: productId,
        assetDigest: digest,
        mediaType: 'image/webp',
        altText: 'Bag of brown rice',
        width: 512,
        height: 512,
        byteSize: 4096,
        provenance: 'Operator-curated global asset',
        expectedRevision: 3,
      );

      final result = await CatalogOperationsRepository(api).putIcon(command);

      expect(result.revision, 4);
      expect(
        api.requests.single.path,
        '/api/v1/catalog-admin/icons/product/$productId',
      );
      expect(api.requests.single.body, containsPair('expectedRevision', 3));
    });

    test('previews then applies only preview-supplied revisions', () async {
      final api = FakeApi((request) async {
        if (request.path.endsWith('/preview')) {
          return jsonResponse(mergePreview());
        }
        return jsonResponse(<String, Object?>{
          'id': mergeId,
          'status': 'applied',
          'revision': 1,
          'survivorId': productId,
          'duplicateIds': <Object?>[duplicateId],
        });
      });
      final repository = CatalogOperationsRepository(api);

      final preview = await repository.previewMerge(
        survivorId: productId,
        duplicateIds: const <String>[duplicateId],
      );
      final result = await repository.applyMerge(
        preview: preview,
        reason: 'Same canonical grocery identity',
      );

      expect(preview.affectedCounts, isNot(contains('futurePrivateDetail')));
      expect(result.status, 'applied');
      expect(api.requests[0].body, <String, Object?>{
        'survivorId': productId,
        'duplicateIds': <String>[duplicateId],
      });
      expect(api.requests[1].body, <String, Object?>{
        'survivorId': productId,
        'expectedSurvivorRevision': 7,
        'duplicateRevisions': <String, int>{duplicateId: 4},
        'reason': 'Same canonical grocery identity',
      });
    });

    test('reverses only an applied event at its current revision', () async {
      final event = CatalogMergeEvent.fromJson(<String, Object?>{
        'id': mergeId,
        'survivorId': productId,
        'mergedIds': <Object?>[duplicateId],
        'status': 'applied',
        'revision': 2,
      });
      final api = FakeApi(
        (_) async => jsonResponse(<String, Object?>{
          'id': mergeId,
          'status': 'reversed',
          'revision': 3,
          'survivorId': productId,
          'restoredProductIds': <Object?>[duplicateId],
        }),
      );

      await CatalogOperationsRepository(
        api,
      ).reverseMerge(event: event, reason: 'Products differ materially');

      expect(
        api.requests.single.path,
        '/api/v1/catalog-admin/merges/$mergeId/reverse',
      );
      expect(api.requests.single.body, <String, Object?>{
        'expectedRevision': 2,
        'reason': 'Products differ materially',
      });
    });
  });
}
