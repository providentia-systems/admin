import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/features/catalog/catalog_models.dart';
import 'package:providentia_admin/features/catalog/catalog_repository.dart';

import '../support/fake_api.dart';

void main() {
  const storePricePayload = <String, Object?>{
    'productId': '0198f4e1-7abc-7def-8abc-0123456789ab',
    'packId': '0198f4e2-7abc-7def-8abc-0123456789ab',
    'storeName': 'Central Market',
    'storeLocation': 'Windhoek',
    'price': '12.50',
    'currency': 'NAD',
    'observedOn': '2026-08-24',
  };

  test('reads a strict typed store-price moderation projection', () async {
    final api = FakeApi(
      (_) async => jsonResponse(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': '0198f4e3-7abc-7def-8abc-0123456789ab',
            'type': 'store_price',
            'status': 'pending',
            'revision': 3,
            'payload': storePricePayload,
          },
        ],
      }),
    );

    final item = (await CatalogRepository(api).contributionReview()).single;

    expect(item.title, 'Central Market · NAD 12.50');
    expect(item.storePrice?.storeLocation, 'Windhoek');
    expect(item.storePrice?.productId, storePricePayload['productId']);
    expect(item.storePrice?.packId, storePricePayload['packId']);
    expect(api.requests.single.path, '/api/v1/catalog-contributions/review');
    expect(api.requests.single.query, <String, String>{
      'limit': '50',
      'offset': '0',
    });
  });

  test('store-price projection fails closed on household metadata', () async {
    final api = FakeApi(
      (_) async => jsonResponse(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': '0198f4e3-7abc-7def-8abc-0123456789ab',
            'type': 'store_price',
            'status': 'pending',
            'revision': 3,
            'payload': <String, Object?>{
              ...storePricePayload,
              'homeId': '0198f4e4-7abc-7def-8abc-0123456789ab',
            },
          },
        ],
      }),
    );

    await expectLater(
      CatalogRepository(api).contributionReview(),
      throwsA(isA<FormatException>()),
    );
  });

  test('store-price DTO rejects malformed values and revisions', () {
    expect(
      () => StorePriceModeration.fromJson(<String, Object?>{
        ...storePricePayload,
        'currency': 'nad',
      }),
      throwsFormatException,
    );
    expect(
      () => CatalogQueueItem.fromJson(<String, Object?>{
        'type': 'store_price',
        'revision': 0,
        'payload': storePricePayload,
      }),
      throwsFormatException,
    );
  });

  test(
    'proposal decision uses backend decision vocabulary and revision',
    () async {
      final api = FakeApi((_) async => jsonResponse(<String, Object?>{}));
      final repository = CatalogRepository(api);

      await repository.decideProposal(
        proposalId: 'proposal-id',
        approve: true,
        reason: 'Verified catalog identity',
        expectedRevision: 7,
      );

      expect(api.requests.single.body, <String, Object?>{
        'decision': 'approve',
        'reason': 'Verified catalog identity',
        'expectedRevision': 7,
      });
    },
  );

  test('contribution decision uses approved/rejected vocabulary', () async {
    final api = FakeApi((_) async => jsonResponse(<String, Object?>{}));
    final repository = CatalogRepository(api);

    await repository.decideContribution(
      contributionId: 'contribution-id',
      approve: false,
      reason: 'Insufficient evidence',
      expectedRevision: 2,
    );

    expect(api.requests.single.method, 'PUT');
    expect(api.requests.single.body, <String, Object?>{
      'decision': 'rejected',
      'reason': 'Insufficient evidence',
      'expectedRevision': 2,
    });
  });

  test(
    'accepts a bounded no-store WebP preview with matching digest',
    () async {
      final bytes = Uint8List.fromList(utf8.encode('fake-webp'));
      final digest = sha256.convert(bytes).toString();
      final api = FakeApi(
        (_) async => ApiResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'image/webp',
            'cache-control': 'no-store',
            'x-content-sha256': digest,
          },
          bytes: bytes,
        ),
      );

      final preview = await CatalogRepository(
        api,
      ).imagePreview('image-id', expectedRevision: 4);
      expect(preview.sha256Digest, digest);
      preview.dispose();
      expect(bytes, everyElement(0));
    },
  );

  test('rejects and wipes a preview with a mismatched digest', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final api = FakeApi(
      (_) async => ApiResponse(
        statusCode: 200,
        headers: const <String, String>{
          'content-type': 'image/webp',
          'cache-control': 'no-store',
          'x-content-sha256': 'bad',
        },
        bytes: bytes,
      ),
    );

    await expectLater(
      CatalogRepository(api).imagePreview('image-id', expectedRevision: 4),
      throwsFormatException,
    );
    expect(bytes, everyElement(0));
  });

  test('constant-time digest comparison is exact', () {
    expect(CatalogRepository.constantTimeEquals('abc', 'abc'), isTrue);
    expect(CatalogRepository.constantTimeEquals('abc', 'abd'), isFalse);
    expect(CatalogRepository.constantTimeEquals('abc', 'abc0'), isFalse);
  });
}
