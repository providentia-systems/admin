import '../../core/api/api_client.dart';
import '../../core/security/secure_id.dart';

final class CatalogEntity {
  CatalogEntity.fromJson(Map<String, Object?> json)
    : id = json['id'] as String,
      type = json['type'] as String,
      status = json['status'] as String,
      revision = json['revision'] as int,
      fields = Map<String, String?>.unmodifiable(
        (json['fields'] as Map<String, Object?>).cast<String, String?>(),
      ) {
    if (!isUuid(id) || revision < 1 || !catalogEntityFields.containsKey(type)) {
      throw const FormatException('Invalid catalog identity.');
    }
    if (fields.keys
            .toSet()
            .difference(catalogEntityFields[type]!.toSet())
            .isNotEmpty ||
        fields.length != catalogEntityFields[type]!.length) {
      throw const FormatException('Unexpected catalog fields.');
    }
  }
  final String id;
  final String type;
  final String status;
  final int revision;
  final Map<String, String?> fields;
  String get label =>
      fields['canonicalName'] ??
      fields['name'] ??
      fields['originalPackText'] ??
      fields['canonicalLabel'] ??
      fields['rawAlias'] ??
      fields['barcode'] ??
      fields['ruleKey'] ??
      id;
}

const catalogEntityFields = <String, List<String>>{
  'category': ['canonicalName'],
  'product': ['canonicalName', 'brand', 'categoryId'],
  'unit': ['symbol', 'name', 'dimension', 'baseFactor'],
  'pack': [
    'productId',
    'variantId',
    'unitId',
    'originalPackText',
    'amount',
    'multiplicity',
  ],
  'variant': ['productId', 'canonicalLabel', 'attributesJson'],
  'alias': ['productId', 'variantId', 'packId', 'rawAlias'],
  'barcode': ['packId', 'barcode', 'barcodeType'],
  'identity-rule': ['ruleKey', 'family', 'ruleDefinition', 'provenance'],
};
const catalogNullableFields = {'variantId', 'unitId', 'amount', 'packId'};

final class CatalogMaintenanceRepository {
  const CatalogMaintenanceRepository(this.api);
  final AdminApi api;
  Future<List<CatalogEntity>> list(
    String type, {
    int offset = 0,
    String query = '',
    String? productId,
  }) async {
    final response = await api.get(
      '/api/v1/catalog-admin/entities/$type',
      query: {'offset': '$offset', 'productId': ?productId},
    );
    final rows = (response.jsonObject['data'] as List<Object?>)
        .map((row) => CatalogEntity.fromJson(row! as Map<String, Object?>))
        .toList(growable: false);
    if (rows.length > 100 || rows.any((row) => row.type != type)) {
      throw const FormatException('Unexpected catalog page.');
    }
    return rows;
  }

  Future<CatalogEntity> save({
    required String type,
    required String id,
    required int revision,
    required String status,
    required String reason,
    required Map<String, String?> fields,
  }) async {
    final response = await api.put(
      '/api/v1/catalog-admin/entities/$type/$id',
      body: {
        'fields': fields,
        'status': status,
        'expectedRevision': revision,
        'reason': reason,
      },
    );
    final result = CatalogEntity.fromJson(response.jsonObject);
    if (result.id != id ||
        result.type != type ||
        result.revision != revision + 1) {
      throw const FormatException('Unexpected catalog mutation response.');
    }
    return result;
  }
}
