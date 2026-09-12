import '../../core/api/api_client.dart';
import '../../core/security/secure_id.dart';

final class OperatorShoppingRepository {
  const OperatorShoppingRepository(this._api);
  final AdminApi _api;

  Future<List<Map<String, Object?>>> options(
    String homeId,
    String collection,
  ) async {
    _identifier(homeId);
    if (collection != 'shopping-lists' && collection != 'products') {
      throw const FormatException('Unsupported shopping selector.');
    }
    final rows = <Map<String, Object?>>[];
    for (var offset = 0; offset < 10000; offset += 100) {
      final response = await _api.get(
        '/api/v1/admin/homes/$homeId/records/$collection',
        query: {'offset': '$offset'},
      );
      final data = response.jsonObject['data'];
      if (data is! List<Object?>) {
        throw const FormatException('Invalid household records.');
      }
      for (final row in data) {
        if (row is! Map<String, Object?> || row['id'] is! String) {
          throw const FormatException('Invalid household record.');
        }
        _identifier(row['id']! as String);
        rows.add(Map.unmodifiable(row));
      }
      if (data.length < 100) return List.unmodifiable(rows);
    }
    throw const FormatException('Too many records for this selector.');
  }

  Future<void> saveList({
    required String homeId,
    required String id,
    required int revision,
    required String reason,
    required Map<String, Object?> fields,
  }) => _save(
    homeId: homeId,
    id: id,
    revision: revision,
    reason: reason,
    fields: fields,
    collection: 'shopping-lists',
  );

  Future<void> saveLine({
    required String homeId,
    required String listId,
    required String id,
    required int revision,
    required String reason,
    required Map<String, Object?> fields,
    bool checking = false,
  }) {
    _identifier(listId);
    return _save(
      homeId: homeId,
      id: id,
      revision: revision,
      reason: reason,
      fields: fields,
      collection: 'shopping-lists/$listId/lines',
      checking: checking,
    );
  }

  Future<void> _save({
    required String homeId,
    required String id,
    required int revision,
    required String reason,
    required Map<String, Object?> fields,
    required String collection,
    bool checking = false,
  }) async {
    _identifier(homeId);
    _identifier(id);
    final creating = revision == 0;
    final line = collection.contains('/lines');
    final allowed = checking
        ? {'checked'}
        : line
        ? {
            'description',
            'quantityToBuy',
            if (creating) ...{
              'expectedListRevision',
              'homeProductId',
            } else
              'archived',
          }
        : {'name', if (creating) 'kind' else 'status'};
    if (revision < 0 ||
        (checking && creating) ||
        fields.isEmpty ||
        !allowed.containsAll(fields.keys) ||
        reason.trim().isEmpty ||
        reason.trim().length > 500) {
      throw const FormatException(
        'A revision, audit reason and supported shopping fields are required.',
      );
    }
    final body = <String, Object?>{
      if (creating) 'id': id,
      'expectedRevision': revision,
      'reason': reason.trim(),
      ...fields,
    };
    final path = '/api/v1/admin/homes/$homeId/$collection';
    if (creating) {
      await _api.post(path, body: body);
    } else if (checking) {
      await _api.put('$path/$id/checked', body: body);
    } else {
      await _api.patch('$path/$id', body: body);
    }
  }

  void _identifier(String value) {
    if (!isUuid(value)) {
      throw const FormatException('Invalid household shopping identifier.');
    }
  }
}
