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
    return _items(response.jsonObject['data'], queue: queue);
  }

  Future<List<CatalogQueueItem>> contributionReview({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _api.get(
      '/api/v1/catalog-contributions/review',
      query: <String, String>{
        'status': ?status,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return _items(response.jsonObject['data'], queue: 'contributions');
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

  Future<List<PublishedCategory>> categories({
    String query = '',
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await _api.get(
      '/api/v1/catalog/categories',
      query: <String, String>{
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final data = response.jsonObject['data'];
    if (data is! List<Object?> ||
        data.any((item) => item is! Map<String, Object?>)) {
      throw const FormatException('Invalid catalog category list.');
    }
    return List<PublishedCategory>.unmodifiable(
      data.cast<Map<String, Object?>>().map(PublishedCategory.fromJson),
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

  Future<ModerationPreview> imagePreview(
    String contributionId, {
    required int expectedRevision,
  }) async {
    final response = await _api.get(
      '/api/v1/catalog-contributions/$contributionId/image-preview',
      query: <String, String>{'expectedRevision': '$expectedRevision'},
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
      contentType: 'image/webp',
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

  static List<CatalogQueueItem> _items(Object? data, {required String queue}) {
    if (data is! List<Object?> ||
        data.any((item) => item is! Map<String, Object?>)) {
      throw const FormatException('Invalid catalog queue response.');
    }
    return List<CatalogQueueItem>.unmodifiable(
      data.cast<Map<String, Object?>>().map(
        (row) => CatalogQueueItem.fromJson(row, queue: queue),
      ),
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
