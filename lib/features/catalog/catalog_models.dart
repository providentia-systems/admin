import 'dart:typed_data';

final class CatalogQueueItem {
  const CatalogQueueItem({
    required this.id,
    required this.revision,
    required this.status,
    required this.kind,
    required this.title,
    required this.raw,
  });

  factory CatalogQueueItem.fromJson(Map<String, Object?> json) {
    String firstString(Iterable<String> keys, String fallback) {
      for (final key in keys) {
        final value = json[key];
        if (value is String && value.isNotEmpty) return value;
      }
      return fallback;
    }

    return CatalogQueueItem(
      id: firstString(const ['id', 'proposalId', 'contributionId'], 'unknown'),
      revision: json['revision'] as int? ??
          json['contributionRevision'] as int? ??
          1,
      status: firstString(const ['status', 'decision'], 'pending'),
      kind: firstString(const ['kind', 'type', 'contributionType'], 'proposal'),
      title: firstString(
        const ['canonicalName', 'productName', 'submittedName', 'name'],
        'Unnamed catalog item',
      ),
      raw: Map<String, Object?>.unmodifiable(json),
    );
  }

  final String id;
  final int revision;
  final String status;
  final String kind;
  final String title;
  final Map<String, Object?> raw;
}

final class PublishedCategory {
  const PublishedCategory({
    required this.id,
    required this.canonicalName,
    required this.revision,
  });

  factory PublishedCategory.fromJson(Map<String, Object?> json) => PublishedCategory(
    id: json['id']! as String,
    canonicalName: json['canonicalName']! as String,
    revision: json['revision']! as int,
  );

  final String id;
  final String canonicalName;
  final int revision;
}

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

