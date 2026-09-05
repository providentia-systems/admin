import '../../core/api/api_client.dart';

typedef Record = Map<String, Object?>;

List<Record> records(Record response) =>
    (response['data'] as List<Object?>? ?? const <Object?>[])
        .map((value) => Map<String, Object?>.from(value! as Map))
        .toList(growable: false);

Record objectMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};

int integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

String displayLabel(String key) => key
    .replaceAll('_', ' ')
    .replaceAll('.', ' / ')
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    );

final class AccessRepository {
  const AccessRepository(this.api);
  final AdminApi api;

  Future<List<Record>> catalog() async =>
      records((await api.get('/api/v1/admin/access/catalog')).jsonObject);

  Future<List<Record>> groups(String scope) async => records(
    (await api.get(
      '/api/v1/admin/access/groups',
      query: <String, String>{'scope': scope},
    )).jsonObject,
  );

  Future<Record> save(Record value) async {
    final id = value['id'];
    final body = <String, Object?>{
      for (final key in <String>[
        'scope',
        'name',
        'description',
        'features',
        'limits',
        'delegablePermissions',
        'rolePermissions',
      ])
        key: value[key],
      'expectedRevision': integer(value['revision']),
    };
    final response = id == null
        ? await api.post('/api/v1/admin/access/groups', body: body)
        : await api.put('/api/v1/admin/access/groups/$id', body: body);
    return response.jsonObject;
  }

  Future<Record> assignment(String scope, String subjectId) async =>
      (await api.get('/api/v1/admin/access/$scope/$subjectId')).jsonObject;

  Future<void> assign(
    String scope,
    String subjectId,
    String groupId,
    int revision,
  ) async {
    await api.put(
      '/api/v1/admin/access/$scope/$subjectId',
      body: <String, Object?>{'groupId': groupId, 'expectedRevision': revision},
    );
  }
}
