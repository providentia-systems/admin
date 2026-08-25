import '../../core/api/api_client.dart';
import 'catalog_models.dart';
import 'catalog_operations_models.dart';

enum CatalogOperationsFailureKind {
  forbidden,
  conflict,
  validation,
  unavailable,
}

final class CatalogOperationsFailure implements Exception {
  const CatalogOperationsFailure({
    required this.kind,
    required this.safeMessage,
  });

  final CatalogOperationsFailureKind kind;
  final String safeMessage;
}

abstract interface class CatalogOperationsPort {
  Future<PublishedProductPage> searchProducts({
    required String query,
    required int limit,
    required int offset,
  });
  Future<CatalogProductDetail> product(String productId);
  Future<List<PublishedCategory>> searchCategories(String query);
  Future<List<CatalogConflict>> conflicts(String queue);
  Future<void> keepExisting({
    required CatalogConflict conflict,
    required String reason,
  });
  Future<CatalogRevisionResult> putIcon(CatalogIconCommand command);
  Future<CatalogMergePreview> previewMerge({
    required String survivorId,
    required List<String> duplicateIds,
  });
  Future<CatalogMergeResult> applyMerge({
    required CatalogMergePreview preview,
    required String reason,
  });
  Future<List<CatalogMergeEvent>> mergeEvents();
  Future<CatalogMergeResult> reverseMerge({
    required CatalogMergeEvent event,
    required String reason,
  });
}

final class CatalogOperationsRepository implements CatalogOperationsPort {
  const CatalogOperationsRepository(this._api);

  final AdminApi _api;

  @override
  Future<PublishedProductPage> searchProducts({
    required String query,
    required int limit,
    required int offset,
  }) => _run(() async {
    final cleaned = query.trim();
    if (cleaned.length > 191 || limit < 1 || limit > 100 || offset < 0) {
      throw const CatalogOperationsFailure(
        kind: CatalogOperationsFailureKind.validation,
        safeMessage: 'The product search was not valid.',
      );
    }
    final response = await _api.get(
      '/api/v1/catalog/products',
      query: <String, String>{
        if (cleaned.isNotEmpty) 'q': cleaned,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final page = PublishedProductPage.fromJson(response.jsonObject);
    if (page.limit != limit || page.offset != offset) {
      throw const FormatException('Product pagination changed unexpectedly.');
    }
    return page;
  });

  @override
  Future<CatalogProductDetail> product(String productId) => _run(() async {
    _requireUuid(productId, 'product');
    final response = await _api.get('/api/v1/catalog/products/$productId');
    final detail = CatalogProductDetail.fromJson(response.jsonObject);
    if (detail.requestedId != productId) {
      throw const FormatException('Product response changed request identity.');
    }
    return detail;
  });

  @override
  Future<List<PublishedCategory>> searchCategories(String query) =>
      _run(() async {
        final cleaned = query.trim();
        if (cleaned.length > 191) {
          throw const CatalogOperationsFailure(
            kind: CatalogOperationsFailureKind.validation,
            safeMessage: 'The category search was not valid.',
          );
        }
        final response = await _api.get(
          '/api/v1/catalog/categories',
          query: <String, String>{
            if (cleaned.isNotEmpty) 'q': cleaned,
            'limit': '100',
            'offset': '0',
          },
        );
        final data = response.jsonObject['data'];
        if (data is! List<Object?>) {
          throw const FormatException('Expected category data.');
        }
        return List<PublishedCategory>.unmodifiable(
          data.map((entry) {
            if (entry is! Map<String, Object?>) {
              throw const FormatException('Expected category object.');
            }
            return PublishedCategory.fromJson(entry);
          }),
        );
      });

  @override
  Future<List<CatalogConflict>> conflicts(String queue) => _run(() async {
    if (!const <String>{'duplicates', 'aliases', 'barcodes'}.contains(queue)) {
      throw const CatalogOperationsFailure(
        kind: CatalogOperationsFailureKind.validation,
        safeMessage: 'The conflict queue was not valid.',
      );
    }
    final response = await _api.get(
      '/api/v1/catalog-admin/workbench',
      query: <String, String>{'queue': queue, 'limit': '50', 'offset': '0'},
    );
    final data = response.jsonObject['data'];
    if (data is! List<Object?>) {
      throw const FormatException('Expected conflict data.');
    }
    return List<CatalogConflict>.unmodifiable(
      data.map((entry) {
        if (entry is! Map<String, Object?>) {
          throw const FormatException('Expected conflict object.');
        }
        final conflict = CatalogConflict.fromJson(entry);
        final expectedType = switch (queue) {
          'duplicates' => 'duplicate',
          'aliases' => 'alias',
          _ => 'barcode',
        };
        if (conflict.type != expectedType) {
          throw const FormatException('Conflict queue changed type.');
        }
        return conflict;
      }),
    );
  });

  @override
  Future<void> keepExisting({
    required CatalogConflict conflict,
    required String reason,
  }) => _run(() async {
    final cleaned = _reason(reason);
    await _api.post(
      '/api/v1/catalog-admin/conflicts/${conflict.id}/keep-existing',
      body: <String, Object?>{
        'reason': cleaned,
        'expectedRevision': conflict.revision,
      },
    );
  });

  @override
  Future<CatalogRevisionResult> putIcon(CatalogIconCommand command) =>
      _run(() async {
        final response = await _api.put(
          '/api/v1/catalog-admin/icons/'
          '${command.targetType.name}/${command.targetId}',
          body: <String, Object?>{
            'assetDigest': command.assetDigest,
            'mediaType': command.mediaType,
            'altText': command.altText.trim(),
            'width': command.width,
            'height': command.height,
            'byteSize': command.byteSize,
            'provenance': command.provenance.trim(),
            'expectedRevision': command.expectedRevision,
          },
        );
        return CatalogRevisionResult.fromJson(response.jsonObject);
      });

  @override
  Future<CatalogMergePreview> previewMerge({
    required String survivorId,
    required List<String> duplicateIds,
  }) => _run(() async {
    _requireUuid(survivorId, 'survivor');
    if (duplicateIds.isEmpty ||
        duplicateIds.length > 20 ||
        duplicateIds.toSet().length != duplicateIds.length ||
        duplicateIds.contains(survivorId)) {
      throw const CatalogOperationsFailure(
        kind: CatalogOperationsFailureKind.validation,
        safeMessage: 'Choose one survivor and 1 to 20 distinct duplicates.',
      );
    }
    for (final id in duplicateIds) {
      _requireUuid(id, 'duplicate');
    }
    final response = await _api.post(
      '/api/v1/catalog-admin/merges/preview',
      body: <String, Object?>{
        'survivorId': survivorId,
        'duplicateIds': duplicateIds,
      },
    );
    final preview = CatalogMergePreview.fromJson(response.jsonObject);
    if (preview.survivorId != survivorId ||
        !_sameIdentities(preview.duplicateIds, duplicateIds)) {
      throw const FormatException('Merge preview changed product identities.');
    }
    return preview;
  });

  @override
  Future<CatalogMergeResult> applyMerge({
    required CatalogMergePreview preview,
    required String reason,
  }) => _run(() async {
    if (!preview.eligible) {
      throw const CatalogOperationsFailure(
        kind: CatalogOperationsFailureKind.conflict,
        safeMessage: 'The merge preview contains unresolved conflicts.',
      );
    }
    final revisions = preview.revisions;
    final survivorRevision = revisions[preview.survivorId];
    if (survivorRevision == null ||
        preview.duplicateIds.any((id) => revisions[id] == null)) {
      throw const FormatException('Merge preview omitted revisions.');
    }
    final response = await _api.post(
      '/api/v1/catalog-admin/merges',
      body: <String, Object?>{
        'survivorId': preview.survivorId,
        'expectedSurvivorRevision': survivorRevision,
        'duplicateRevisions': <String, int>{
          for (final id in preview.duplicateIds) id: revisions[id]!,
        },
        'reason': _reason(reason),
      },
    );
    final result = CatalogMergeResult.fromJson(response.jsonObject);
    if (result.status != 'applied' || result.survivorId != preview.survivorId) {
      throw const FormatException('Merge result changed product identity.');
    }
    return result;
  });

  @override
  Future<List<CatalogMergeEvent>> mergeEvents() => _run(() async {
    final response = await _api.get(
      '/api/v1/catalog-admin/workbench',
      query: const <String, String>{
        'queue': 'merges',
        'limit': '50',
        'offset': '0',
      },
    );
    final data = response.jsonObject['data'];
    if (data is! List<Object?>) {
      throw const FormatException('Expected merge event data.');
    }
    return List<CatalogMergeEvent>.unmodifiable(
      data.map((entry) {
        if (entry is! Map<String, Object?>) {
          throw const FormatException('Expected merge event object.');
        }
        return CatalogMergeEvent.fromJson(entry);
      }),
    );
  });

  @override
  Future<CatalogMergeResult> reverseMerge({
    required CatalogMergeEvent event,
    required String reason,
  }) => _run(() async {
    if (event.status != 'applied') {
      throw const CatalogOperationsFailure(
        kind: CatalogOperationsFailureKind.conflict,
        safeMessage: 'Only an applied merge can be reversed.',
      );
    }
    final response = await _api.post(
      '/api/v1/catalog-admin/merges/${event.id}/reverse',
      body: <String, Object?>{
        'expectedRevision': event.revision,
        'reason': _reason(reason),
      },
    );
    final result = CatalogMergeResult.fromJson(response.jsonObject);
    if (result.id != event.id ||
        result.status != 'reversed' ||
        result.survivorId != event.survivorId) {
      throw const FormatException('Merge reversal changed identity.');
    }
    return result;
  });

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on CatalogOperationsFailure {
      rethrow;
    } on ApiException catch (error) {
      throw switch (error.statusCode) {
        401 || 403 => const CatalogOperationsFailure(
          kind: CatalogOperationsFailureKind.forbidden,
          safeMessage: 'Catalog operator authorization was lost.',
        ),
        409 => const CatalogOperationsFailure(
          kind: CatalogOperationsFailureKind.conflict,
          safeMessage: 'Catalog data changed. Reload and preview again.',
        ),
        400 || 422 => const CatalogOperationsFailure(
          kind: CatalogOperationsFailureKind.validation,
          safeMessage: 'The catalog operation was not valid.',
        ),
        _ => const CatalogOperationsFailure(
          kind: CatalogOperationsFailureKind.unavailable,
          safeMessage: 'Catalog operations are temporarily unavailable.',
        ),
      };
    } on FormatException {
      throw const CatalogOperationsFailure(
        kind: CatalogOperationsFailureKind.unavailable,
        safeMessage: 'Catalog data could not be read safely.',
      );
    }
  }

  static String _reason(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty || cleaned.length > 500) {
      throw const CatalogOperationsFailure(
        kind: CatalogOperationsFailureKind.validation,
        safeMessage: 'Enter an auditable reason of 1 to 500 characters.',
      );
    }
    return cleaned;
  }

  static bool _sameIdentities(List<String> left, List<String> right) =>
      left.length == right.length && left.toSet().containsAll(right);

  static void _requireUuid(String value, String name) {
    if (!_uuidPattern.hasMatch(value)) {
      throw CatalogOperationsFailure(
        kind: CatalogOperationsFailureKind.validation,
        safeMessage: 'The $name identity was not valid.',
      );
    }
  }
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
