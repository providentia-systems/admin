import '../../core/api/api_client.dart';
import '../../core/security/secure_id.dart';

enum OperatorInventoryKind { product, category, location, store }

final class OperatorInventoryRecord {
  const OperatorInventoryRecord({
    required this.id,
    required this.kind,
    required this.revision,
    required this.status,
    required this.name,
    this.productId,
    this.packId,
    this.packText,
    this.homeCategoryId,
    this.locationKind,
    this.storeLocation,
  });

  factory OperatorInventoryRecord.fromRow(
    OperatorInventoryKind kind,
    Map<String, Object?> row,
  ) {
    final id = row['id'];
    final revision = int.tryParse('${row['revision']}');
    final status = row['status'];
    if (id is! String ||
        !isUuid(id) ||
        revision == null ||
        revision < 1 ||
        (status != 'active' && status != 'archived')) {
      throw const FormatException('Invalid household record.');
    }
    String? text(String field) {
      final value = row[field];
      if (value == null || value is String) return value as String?;
      throw const FormatException('Invalid household record field.');
    }

    return OperatorInventoryRecord(
      id: id,
      kind: kind,
      revision: revision,
      status: status! as String,
      name:
          text(
            kind == OperatorInventoryKind.product ? 'private_name' : 'name',
          ) ??
          '',
      productId: text('product_id'),
      packId: text('pack_id'),
      packText: text('original_pack_text'),
      homeCategoryId: text('home_category_id'),
      locationKind: text('kind'),
      storeLocation: text('location'),
    );
  }

  final String id;
  final OperatorInventoryKind kind;
  final int revision;
  final String status;
  final String name;
  final String? productId;
  final String? packId;
  final String? packText;
  final String? homeCategoryId;
  final String? locationKind;
  final String? storeLocation;
  bool get catalogBacked => productId != null || packId != null;
}

final class OperatorInventoryRepository {
  const OperatorInventoryRepository(this._api);
  final AdminApi _api;

  Future<List<OperatorInventoryRecord>> categories(String homeId) async {
    _identifier(homeId);
    final records = <OperatorInventoryRecord>[];
    for (var offset = 0; ; offset += 100) {
      final response = await _api.get(
        '/api/v1/admin/homes/$homeId/records/categories',
        query: {'offset': '$offset'},
      );
      final data = response.jsonObject['data'];
      if (data is! List<Object?>) {
        throw const FormatException('Invalid category list.');
      }
      records.addAll(
        data.map((row) {
          if (row is! Map<String, Object?>) {
            throw const FormatException('Invalid category.');
          }
          return OperatorInventoryRecord.fromRow(
            OperatorInventoryKind.category,
            row,
          );
        }),
      );
      if (data.length < 100) return List.unmodifiable(records);
    }
  }

  Future<void> saveCategory({
    required String homeId,
    required String id,
    required int expectedRevision,
    required String reason,
    String? name,
    String? status,
  }) => _save(
    homeId: homeId,
    id: id,
    collection: 'categories',
    expectedRevision: expectedRevision,
    reason: reason,
    fields: {'name': ?name, 'status': ?status},
  );

  Future<void> saveProduct({
    required String homeId,
    required String id,
    required int expectedRevision,
    required String reason,
    required bool editMetadata,
    required bool catalogBacked,
    String? privateName,
    String? packText,
    String? homeCategoryId,
    String? status,
  }) => _save(
    homeId: homeId,
    id: id,
    collection: 'products',
    expectedRevision: expectedRevision,
    reason: reason,
    fields: {
      if (editMetadata && !catalogBacked) ...{
        'privateName': privateName,
        'originalPackText': packText,
      },
      if (editMetadata) 'homeCategoryId': homeCategoryId,
      'status': ?status,
    },
  );

  Future<void> saveLocation({
    required String homeId,
    required String id,
    required int expectedRevision,
    required String reason,
    String? name,
    String? kind,
    String? status,
  }) => _save(
    homeId: homeId,
    id: id,
    collection: 'locations',
    expectedRevision: expectedRevision,
    reason: reason,
    fields: {'name': ?name, 'kind': ?kind, 'status': ?status},
  );

  Future<void> saveStore({
    required String homeId,
    required String id,
    required int expectedRevision,
    required String reason,
    String? name,
    String? location,
    String? status,
  }) => _save(
    homeId: homeId,
    id: id,
    collection: 'stores',
    expectedRevision: expectedRevision,
    reason: reason,
    fields: {'name': ?name, 'location': ?location, 'status': ?status},
  );

  Future<void> _save({
    required String homeId,
    required String id,
    required String collection,
    required int expectedRevision,
    required String reason,
    required Map<String, Object?> fields,
  }) async {
    _identifier(homeId);
    _identifier(id);
    if (expectedRevision < 0 ||
        reason.trim().isEmpty ||
        reason.trim().length > 500) {
      throw const FormatException('A revision and audit reason are required.');
    }
    final body = <String, Object?>{
      if (expectedRevision == 0) 'id': id,
      'expectedRevision': expectedRevision,
      'reason': reason.trim(),
      ...fields,
    };
    final path = '/api/v1/admin/homes/$homeId/$collection';
    if (expectedRevision == 0) {
      await _api.post(path, body: body);
    } else {
      await _api.patch('$path/$id', body: body);
    }
  }

  void _identifier(String value) {
    if (!isUuid(value)) {
      throw const FormatException('Invalid household identifier.');
    }
  }
}
