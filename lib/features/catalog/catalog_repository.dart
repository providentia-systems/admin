import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/api/api_client.dart';
import 'catalog_models.dart';

final class CatalogRepository {
  const CatalogRepository(this._api);

  final AdminApi _api;

  Future<List<CatalogQueueItem>> workbench({
    String queue = 'proposals',
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _api.get(
      '/api/v1/catalog-admin/workbench',
      query: <String, String>{
        'queue': queue,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return _items(response.jsonObject['data']);
  }

  Future<List<CatalogQueueItem>> contributionReview({
    String? status,
    String? type,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _api.get(
      '/api/v1/catalog-contributions/review',
      query: <String, String>{
        if (status != null) 'status': status,
        if (type != null) 'type': type,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return _items(response.jsonObject['data']);
  }

  Future<void> decideProposal({
    required String proposalId,
    required bool approve,
    required String reason,
    required int expectedRevision,
  }) async {
    await _api.post(
      '/api/v1/catalog-admin/proposals/$proposalId/decision',
      body: <String, Object?>{
        'decision': approve ? 'approve' : 'reject',
        'reason': reason.trim(),
        'expectedRevision': expectedRevision,
      },
    );
  }

  Future<void> decideContribution({
    required String contributionId,
    required bool approve,
    required String reason,
    required int expectedRevision,
  }) async {
    await _api.put(
      '/api/v1/catalog-contributions/$contributionId/decision',
      body: <String, Object?>{
        'decision': approve ? 'approved' : 'rejected',
        'reason': reason.trim(),
        'expectedRevision': expectedRevision,
      },
    );
  }

  Future<List<PublishedCategory>> categories({String query = ''}) async {
    final response = await _api.get(
      '/api/v1/catalog/categories',
      query: <String, String>{
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'limit': '100',
        'offset': '0',
      },
    );
    final data = response.jsonObject['data'];
    if (data is! List<Object?>) return const <PublishedCategory>[];
    return List<PublishedCategory>.unmodifiable(
      data
          .whereType<Map<String, Object?>>()
          .map(PublishedCategory.fromJson),
    );
  }

  Future<void> linkContributionProposal({
    required String contributionId,
    required String publishedCategoryId,
    required int expectedRevision,
  }) async {
    await _api.put(
      '/api/v1/catalog-contributions/$contributionId/proposal',
      body: <String, Object?>{
        'publishedCategoryId': publishedCategoryId,
        'expectedRevision': expectedRevision,
      },
    );
  }

  Future<ModerationPreview> imagePreview(String contributionId) async {
    final response = await _api.get(
      '/api/v1/catalog-contributions/$contributionId/image-preview',
      headers: const <String, String>{'Accept': 'image/webp'},
    );
    final contentType = response.headers['content-type']?.split(';').first;
    final cacheControl = response.headers['cache-control'];
    final expectedDigest = response.headers['x-content-sha256'];
    if (contentType != 'image/webp' || cacheControl != 'no-store') {
      response.bytes.fillRange(0, response.bytes.length, 0);
      throw const FormatException('Unsafe moderation preview headers.');
    }
    if (response.bytes.isEmpty || response.bytes.length > 5 * 1024 * 1024) {
      response.bytes.fillRange(0, response.bytes.length, 0);
      throw const FormatException('Unsafe moderation preview size.');
    }
    final actualDigest = sha256.convert(response.bytes).toString();
    if (expectedDigest == null ||
        !constantTimeEquals(expectedDigest, actualDigest)) {
      response.bytes.fillRange(0, response.bytes.length, 0);
      throw const FormatException('Moderation preview digest mismatch.');
    }
    return ModerationPreview(
      bytes: response.bytes,
      sha256Digest: actualDigest,
      contentType: contentType,
    );
  }

  Future<void> publishImage({
    required String contributionId,
    required String productId,
    required int expectedContributionRevision,
    required int expectedIconRevision,
  }) async {
    await _api.put(
      '/api/v1/catalog-contributions/$contributionId/image-publication',
      body: <String, Object?>{
        'productId': productId,
        'expectedContributionRevision': expectedContributionRevision,
        'expectedIconRevision': expectedIconRevision,
      },
    );
  }

  static List<CatalogQueueItem> _items(Object? data) {
    if (data is! List<Object?>) return const <CatalogQueueItem>[];
    return List<CatalogQueueItem>.unmodifiable(
      data.whereType<Map<String, Object?>>().map(CatalogQueueItem.fromJson),
    );
  }

  static bool constantTimeEquals(String expected, String actual) {
    final a = ascii.encode(expected);
    final b = ascii.encode(actual);
    var difference = a.length ^ b.length;
    final length = a.length > b.length ? a.length : b.length;
    for (var index = 0; index < length; index += 1) {
      final left = index < a.length ? a[index] : 0;
      final right = index < b.length ? b[index] : 0;
      difference |= left ^ right;
    }
    return difference == 0;
  }
}

