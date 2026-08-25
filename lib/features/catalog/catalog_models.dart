import 'dart:typed_data';

import '../../core/security/secure_id.dart';

final class CatalogQueueItem {
  const CatalogQueueItem({
    required this.id,
    required this.revision,
    required this.status,
    required this.kind,
    required this.title,
    required this.raw,
    this.storePrice,
  });

  factory CatalogQueueItem.fromJson(Map<String, Object?> json) {
    String firstString(Iterable<String> keys, String fallback) {
      for (final key in keys) {
        final value = json[key];
        if (value is String && value.isNotEmpty) return value;
      }
      return fallback;
    }

    final kind = firstString(const [
      'kind',
      'type',
      'contributionType',
    ], 'proposal');
    final revision = json['revision'] ?? json['contributionRevision'] ?? 1;
    if (revision is! int || revision < 1) {
      throw const FormatException('Catalog moderation revision was malformed.');
    }
    final payload = json['payload'];
    final storePrice = switch (kind) {
      'store_price' when payload is Map<String, Object?> =>
        StorePriceModeration.fromJson(payload),
      'store_price' => throw const FormatException(
        'Store-price moderation payload was malformed.',
      ),
      _ => null,
    };
    String? payloadTitle() {
      if (payload is! Map<String, Object?>) return null;
      for (final key in const <String>[
        'canonicalName',
        'productName',
        'submittedName',
        'name',
      ]) {
        final value = payload[key];
        if (value is String && value.isNotEmpty) return value;
      }
      return null;
    }

    return CatalogQueueItem(
      id: firstString(const ['id', 'proposalId', 'contributionId'], 'unknown'),
      revision: revision,
      status: firstString(const ['status', 'decision'], 'pending'),
      kind: kind,
      title:
          storePrice?.title ??
          firstString(const [
            'canonicalName',
            'productName',
            'submittedName',
            'name',
          ], payloadTitle() ?? 'Unnamed catalog item'),
      raw: Map<String, Object?>.unmodifiable(json),
      storePrice: storePrice,
    );
  }

  final String id;
  final int revision;
  final String status;
  final String kind;
  final String title;
  final Map<String, Object?> raw;
  final StorePriceModeration? storePrice;

  bool get isProductIdentityContribution => kind == 'product_identity';
  bool get isProductImageContribution => kind == 'product_image';
  bool get isStorePriceContribution => kind == 'store_price';
}

/// Strict, attribution-free view of one consent-bound store-price fact.
///
/// The Backend projection contains only these seven fields. Rejecting unknown
/// fields here ensures a future server regression cannot silently expose
/// household metadata through the operator client.
final class StorePriceModeration {
  StorePriceModeration({
    required this.productId,
    required this.packId,
    required this.storeName,
    required this.price,
    required this.currency,
    required this.observedOn,
    this.storeLocation,
  }) {
    if (!isUuid(productId) ||
        !isUuid(packId) ||
        storeName.trim().isEmpty ||
        storeName.length > 191 ||
        (storeLocation?.length ?? 0) > 191 ||
        !_pricePattern.hasMatch(price) ||
        !_currencyPattern.hasMatch(currency) ||
        !_calendarDatePattern.hasMatch(observedOn)) {
      throw const FormatException(
        'Store-price moderation payload was malformed.',
      );
    }
    final date = DateTime.tryParse('${observedOn}T00:00:00Z');
    if (date == null || date.toIso8601String().substring(0, 10) != observedOn) {
      throw const FormatException(
        'Store-price moderation payload was malformed.',
      );
    }
  }

  factory StorePriceModeration.fromJson(Map<String, Object?> json) {
    if (!StorePriceModeration.allowedWireFields.containsAll(json.keys) ||
        !json.keys.toSet().containsAll(
          StorePriceModeration.requiredWireFields,
        )) {
      throw const FormatException(
        'Store-price moderation payload was malformed.',
      );
    }
    final productId = json['productId'];
    final packId = json['packId'];
    final storeName = json['storeName'];
    final storeLocation = json['storeLocation'];
    final price = json['price'];
    final currency = json['currency'];
    final observedOn = json['observedOn'];
    if (productId is! String ||
        packId is! String ||
        storeName is! String ||
        (storeLocation != null && storeLocation is! String) ||
        price is! String ||
        currency is! String ||
        observedOn is! String) {
      throw const FormatException(
        'Store-price moderation payload was malformed.',
      );
    }
    final cleanedLocation = (storeLocation as String?)?.trim();
    return StorePriceModeration(
      productId: productId,
      packId: packId,
      storeName: storeName.trim(),
      storeLocation: cleanedLocation == null || cleanedLocation.isEmpty
          ? null
          : cleanedLocation,
      price: price,
      currency: currency,
      observedOn: observedOn,
    );
  }

  static const Set<String> allowedWireFields = <String>{
    'productId',
    'packId',
    'storeName',
    'storeLocation',
    'price',
    'currency',
    'observedOn',
  };
  static const Set<String> requiredWireFields = <String>{
    'productId',
    'packId',
    'storeName',
    'price',
    'currency',
    'observedOn',
  };

  final String productId;
  final String packId;
  final String storeName;
  final String? storeLocation;
  final String price;
  final String currency;
  final String observedOn;

  String get title => '$storeName · $currency $price';
}

final class PublishedCategory {
  PublishedCategory({
    required this.id,
    required this.canonicalName,
    required this.revision,
  }) {
    if (!isUuid(id) ||
        canonicalName.trim().isEmpty ||
        canonicalName.length > 191 ||
        revision < 1) {
      throw const FormatException('Invalid published category.');
    }
  }

  factory PublishedCategory.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final canonicalName = json['canonicalName'];
    final revision = json['revision'];
    if (id is! String || canonicalName is! String || revision is! int) {
      throw const FormatException('Invalid published category.');
    }
    return PublishedCategory(
      id: id,
      canonicalName: canonicalName,
      revision: revision,
    );
  }

  final String id;
  final String canonicalName;
  final int revision;
}

final RegExp _pricePattern = RegExp(r'^(?:0|[1-9][0-9]{0,11})\.[0-9]{2,4}$');
final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');
final RegExp _calendarDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

final class ModerationPreview {
  ModerationPreview({
    required this.bytes,
    required this.sha256Digest,
    required this.contentType,
  });

  final Uint8List bytes;
  final String sha256Digest;
  final String contentType;

  void dispose() => bytes.fillRange(0, bytes.length, 0);
}
