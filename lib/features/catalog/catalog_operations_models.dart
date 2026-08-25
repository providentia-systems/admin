import 'dart:collection';

import '../../core/security/secure_id.dart';

final class PublishedProduct {
  PublishedProduct({
    required this.id,
    required this.canonicalName,
    required this.brand,
    required this.category,
    required this.revision,
    required this.packId,
    required this.packText,
    required this.packStatus,
  }) {
    _requireUuid(id, 'product id');
    _requireText(canonicalName, 'canonical name', maximum: 191);
    _requireText(brand, 'brand', maximum: 120, allowEmpty: true);
    _requireText(category, 'category', maximum: 191);
    if (revision < 1) throw const FormatException('Invalid product revision.');
    if (packId != null) _requireUuid(packId!, 'pack id');
    if (packText != null && packText!.length > 191) {
      throw const FormatException('Invalid pack text.');
    }
    if (packStatus != null &&
        packStatus != 'published' &&
        packStatus != 'pending-normalization') {
      throw const FormatException('Invalid pack status.');
    }
  }

  factory PublishedProduct.fromJson(Map<String, Object?> json) =>
      PublishedProduct(
        id: _string(json, 'id'),
        canonicalName: _string(json, 'canonicalName'),
        brand: _string(json, 'brand', allowEmpty: true),
        category: _string(json, 'category'),
        revision: _positiveInt(json, 'revision'),
        packId: _nullableString(json, 'packId'),
        packText: _nullableString(json, 'packText'),
        packStatus: _nullableString(json, 'packStatus'),
      );

  final String id;
  final String canonicalName;
  final String brand;
  final String category;
  final int revision;
  final String? packId;
  final String? packText;
  final String? packStatus;
}

final class PublishedProductPage {
  PublishedProductPage({
    required List<PublishedProduct> data,
    required this.limit,
    required this.offset,
  }) : data = UnmodifiableListView<PublishedProduct>(data) {
    if (limit < 1 || limit > 100 || offset < 0 || data.length > limit) {
      throw const FormatException('Invalid product pagination.');
    }
  }

  factory PublishedProductPage.fromJson(Map<String, Object?> json) {
    final pagination = _object(json, 'pagination');
    return PublishedProductPage(
      data: _objectList(json, 'data').map(PublishedProduct.fromJson).toList(),
      limit: _boundedInt(pagination, 'limit', minimum: 1, maximum: 100),
      offset: _boundedInt(pagination, 'offset', minimum: 0),
    );
  }

  final List<PublishedProduct> data;
  final int limit;
  final int offset;

  bool get hasNext => data.length == limit;
}

final class CatalogIconSummary {
  CatalogIconSummary({
    required this.id,
    required this.assetDigest,
    required this.mediaType,
    required this.altText,
    required this.revision,
  }) {
    _requireUuid(id, 'icon id');
    if (!_digestPattern.hasMatch(assetDigest)) {
      throw const FormatException('Invalid icon digest.');
    }
    _requireText(mediaType, 'icon media type', maximum: 64);
    _requireText(altText, 'icon alt text', maximum: 191);
    if (revision < 1) throw const FormatException('Invalid icon revision.');
  }

  factory CatalogIconSummary.fromJson(Map<String, Object?> json) =>
      CatalogIconSummary(
        id: _string(json, 'id'),
        assetDigest: _string(json, 'assetDigest'),
        mediaType: _string(json, 'mediaType'),
        altText: _string(json, 'altText'),
        revision: _positiveInt(json, 'revision'),
      );

  final String id;
  final String assetDigest;
  final String mediaType;
  final String altText;
  final int revision;
}

final class CatalogProductDetail {
  CatalogProductDetail({
    required this.id,
    required this.requestedId,
    required this.redirected,
    required this.canonicalName,
    required this.brand,
    required this.categoryId,
    required this.category,
    required this.revision,
    required List<CatalogIconSummary> icons,
  }) : icons = UnmodifiableListView<CatalogIconSummary>(icons) {
    _requireUuid(id, 'product id');
    _requireUuid(requestedId, 'requested product id');
    _requireUuid(categoryId, 'category id');
    _requireText(canonicalName, 'canonical name', maximum: 191);
    _requireText(brand, 'brand', maximum: 120, allowEmpty: true);
    _requireText(category, 'category', maximum: 191);
    if (revision < 1 || (!redirected && id != requestedId)) {
      throw const FormatException('Invalid product detail.');
    }
  }

  factory CatalogProductDetail.fromJson(Map<String, Object?> json) {
    // Packs are intentionally not projected into Admin state, but their
    // required container is still validated so contract drift fails closed.
    _objectList(json, 'packs');
    return CatalogProductDetail(
      id: _string(json, 'id'),
      requestedId: _string(json, 'requestedId'),
      redirected: _bool(json, 'redirected'),
      canonicalName: _string(json, 'canonicalName'),
      brand: _string(json, 'brand', allowEmpty: true),
      categoryId: _string(json, 'categoryId'),
      category: _string(json, 'category'),
      revision: _positiveInt(json, 'revision'),
      icons: _objectList(
        json,
        'icons',
      ).map(CatalogIconSummary.fromJson).toList(),
    );
  }

  final String id;
  final String requestedId;
  final bool redirected;
  final String canonicalName;
  final String brand;
  final String categoryId;
  final String category;
  final int revision;
  final List<CatalogIconSummary> icons;

  int get currentIconRevision => icons.fold<int>(
    0,
    (current, icon) => icon.revision > current ? icon.revision : current,
  );
}

final class CatalogConflict {
  CatalogConflict({
    required this.id,
    required this.type,
    required this.key,
    required this.status,
    required this.revision,
    required this.existingEntityId,
    required this.candidateEntityId,
  }) {
    _requireUuid(id, 'conflict id');
    if (!const <String>{'duplicate', 'alias', 'barcode'}.contains(type) ||
        status != 'open' ||
        revision < 1) {
      throw const FormatException('Invalid catalog conflict.');
    }
    _requireText(key, 'conflict key', maximum: 191);
    if (existingEntityId != null) {
      _requireUuid(existingEntityId!, 'existing entity id');
    }
    if (candidateEntityId != null) {
      _requireUuid(candidateEntityId!, 'candidate entity id');
    }
  }

  factory CatalogConflict.fromJson(Map<String, Object?> json) =>
      CatalogConflict(
        id: _string(json, 'id'),
        type: _string(json, 'conflictType'),
        key: _string(json, 'conflictKey'),
        status: _string(json, 'status'),
        revision: _positiveInt(json, 'revision'),
        existingEntityId: _nullableString(json, 'existingEntityId'),
        candidateEntityId: _nullableString(json, 'candidateEntityId'),
      );

  final String id;
  final String type;
  final String key;
  final String status;
  final int revision;
  final String? existingEntityId;
  final String? candidateEntityId;
}

enum CatalogIconTargetType { product, category }

final class CatalogIconCommand {
  CatalogIconCommand({
    required this.targetType,
    required this.targetId,
    required this.assetDigest,
    required this.mediaType,
    required this.altText,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.provenance,
    required this.expectedRevision,
  }) {
    _requireUuid(targetId, 'icon target id');
    if (!_digestPattern.hasMatch(assetDigest) ||
        !const <String>{
          'image/png',
          'image/webp',
          'image/svg+xml',
        }.contains(mediaType) ||
        width < 16 ||
        width > 4096 ||
        height < 16 ||
        height > 4096 ||
        byteSize < 1 ||
        byteSize > 5242880 ||
        expectedRevision < 0) {
      throw const FormatException('Invalid catalog icon command.');
    }
    _requireText(altText, 'icon alt text', maximum: 191);
    _requireText(provenance, 'icon provenance', maximum: 191);
  }

  final CatalogIconTargetType targetType;
  final String targetId;
  final String assetDigest;
  final String mediaType;
  final String altText;
  final int width;
  final int height;
  final int byteSize;
  final String provenance;
  final int expectedRevision;
}

final class CatalogRevisionResult {
  CatalogRevisionResult({required this.id, required this.revision}) {
    _requireUuid(id, 'catalog revision id');
    if (revision < 1) throw const FormatException('Invalid catalog revision.');
  }

  factory CatalogRevisionResult.fromJson(Map<String, Object?> json) =>
      CatalogRevisionResult(
        id: _string(json, 'id'),
        revision: _positiveInt(json, 'revision'),
      );

  final String id;
  final int revision;
}

final class CatalogMergeProduct {
  CatalogMergeProduct({
    required this.id,
    required this.canonicalName,
    required this.brand,
    required this.status,
    required this.revision,
  }) {
    _requireUuid(id, 'merge product id');
    _requireText(canonicalName, 'merge product name', maximum: 191);
    _requireText(brand, 'merge product brand', maximum: 120, allowEmpty: true);
    if (status != 'published' || revision < 1) {
      throw const FormatException('Invalid merge product.');
    }
  }

  factory CatalogMergeProduct.fromJson(Map<String, Object?> json) =>
      CatalogMergeProduct(
        id: _string(json, 'id'),
        canonicalName: _string(json, 'canonicalName'),
        brand: _string(json, 'brand', allowEmpty: true),
        status: _string(json, 'status'),
        revision: _positiveInt(json, 'revision'),
      );

  final String id;
  final String canonicalName;
  final String brand;
  final String status;
  final int revision;
}

final class CatalogMergePreview {
  CatalogMergePreview({
    required this.survivorId,
    required List<String> duplicateIds,
    required this.eligible,
    required List<CatalogMergeProduct> products,
    required Map<String, int> affectedCounts,
    required List<String> conflicts,
  }) : duplicateIds = UnmodifiableListView<String>(duplicateIds),
       products = UnmodifiableListView<CatalogMergeProduct>(products),
       affectedCounts = UnmodifiableMapView<String, int>(affectedCounts),
       conflicts = UnmodifiableListView<String>(conflicts) {
    _requireUuid(survivorId, 'merge survivor id');
    if (duplicateIds.isEmpty ||
        duplicateIds.length > 20 ||
        duplicateIds.toSet().length != duplicateIds.length ||
        duplicateIds.contains(survivorId) ||
        duplicateIds.any((id) => !isUuid(id)) ||
        products.map((product) => product.id).toSet().length !=
            products.length ||
        affectedCounts.values.any((count) => count < 0) ||
        conflicts.any(
          (conflict) => conflict.isEmpty || conflict.length > 500,
        )) {
      throw const FormatException('Invalid merge preview.');
    }
    final expectedIds = <String>{survivorId, ...duplicateIds};
    if (!products
        .map((product) => product.id)
        .toSet()
        .containsAll(expectedIds)) {
      throw const FormatException('Merge preview omitted product revisions.');
    }
  }

  factory CatalogMergePreview.fromJson(Map<String, Object?> json) =>
      CatalogMergePreview(
        survivorId: _string(json, 'survivorId'),
        duplicateIds: _stringList(json, 'duplicateIds'),
        eligible: _bool(json, 'eligible'),
        products: _objectList(
          json,
          'products',
        ).map(CatalogMergeProduct.fromJson).toList(),
        affectedCounts: _knownAffectedCounts(json),
        conflicts: _stringList(json, 'conflicts'),
      );

  final String survivorId;
  final List<String> duplicateIds;
  final bool eligible;
  final List<CatalogMergeProduct> products;
  final Map<String, int> affectedCounts;
  final List<String> conflicts;

  Map<String, int> get revisions => <String, int>{
    for (final product in products) product.id: product.revision,
  };
}

final class CatalogMergeResult {
  CatalogMergeResult({
    required this.id,
    required this.status,
    required this.revision,
    required this.survivorId,
  }) {
    _requireUuid(id, 'merge id');
    _requireUuid(survivorId, 'merge survivor id');
    if (!const <String>{'applied', 'reversed'}.contains(status) ||
        revision < 1) {
      throw const FormatException('Invalid merge result.');
    }
  }

  factory CatalogMergeResult.fromJson(Map<String, Object?> json) =>
      CatalogMergeResult(
        id: _string(json, 'id'),
        status: _string(json, 'status'),
        revision: _positiveInt(json, 'revision'),
        survivorId: _string(json, 'survivorId'),
      );

  final String id;
  final String status;
  final int revision;
  final String survivorId;
}

final class CatalogMergeEvent {
  CatalogMergeEvent({
    required this.id,
    required this.survivorId,
    required List<String> duplicateIds,
    required this.status,
    required this.revision,
  }) : duplicateIds = UnmodifiableListView<String>(duplicateIds) {
    _requireUuid(id, 'merge id');
    _requireUuid(survivorId, 'merge survivor id');
    if (duplicateIds.any((id) => !isUuid(id)) ||
        !const <String>{'applied', 'reversed'}.contains(status) ||
        revision < 1) {
      throw const FormatException('Invalid merge event.');
    }
  }

  factory CatalogMergeEvent.fromJson(Map<String, Object?> json) =>
      CatalogMergeEvent(
        id: _string(json, 'id'),
        survivorId: _string(json, 'survivorId'),
        duplicateIds: _stringList(json, 'mergedIds'),
        status: _string(json, 'status'),
        revision: _positiveInt(json, 'revision'),
      );

  final String id;
  final String survivorId;
  final List<String> duplicateIds;
  final String status;
  final int revision;
}

Map<String, Object?> _object(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected $key object.');
  }
  return value;
}

List<Map<String, Object?>> _objectList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?>) throw FormatException('Expected $key list.');
  return value
      .map((entry) {
        if (entry is! Map<String, Object?>) {
          throw FormatException('Expected $key object.');
        }
        return entry;
      })
      .toList(growable: false);
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?> || value.any((entry) => entry is! String)) {
    throw FormatException('Expected $key string list.');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

Map<String, int> _intMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map<String, Object?> ||
      value.values.any((entry) => entry is! int)) {
    throw FormatException('Expected $key integer map.');
  }
  return Map<String, int>.unmodifiable(value.cast<String, int>());
}

Map<String, int> _knownAffectedCounts(Map<String, Object?> json) {
  final counts = _intMap(json, 'affectedCounts');
  const known = <String>{
    'variants',
    'packs',
    'aliases',
    'icons',
    'homeReferences',
  };
  if (!counts.keys.toSet().containsAll(known)) {
    throw const FormatException('Merge preview omitted affected counts.');
  }
  return Map<String, int>.unmodifiable(<String, int>{
    for (final key in known) key: counts[key]!,
  });
}

String _string(
  Map<String, Object?> json,
  String key, {
  bool allowEmpty = false,
}) {
  final value = json[key];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw FormatException('Expected $key string.');
  }
  return value;
}

String? _nullableString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Expected nullable $key.');
  return value;
}

bool _bool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Expected $key boolean.');
  return value;
}

int _positiveInt(Map<String, Object?> json, String key) =>
    _boundedInt(json, key, minimum: 1);

int _boundedInt(
  Map<String, Object?> json,
  String key, {
  required int minimum,
  int? maximum,
}) {
  final value = json[key];
  if (value is! int ||
      value < minimum ||
      (maximum != null && value > maximum)) {
    throw FormatException('Expected bounded $key integer.');
  }
  return value;
}

void _requireUuid(String value, String name) {
  if (!isUuid(value)) throw FormatException('Invalid $name.');
}

void _requireText(
  String value,
  String name, {
  required int maximum,
  bool allowEmpty = false,
}) {
  if ((!allowEmpty && value.trim().isEmpty) || value.length > maximum) {
    throw FormatException('Invalid $name.');
  }
}

final RegExp _digestPattern = RegExp(r'^[a-f0-9]{64}$');
