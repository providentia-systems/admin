import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/features/catalog/catalog_repository.dart';

import '../support/fake_api.dart';

void main() {
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
