import 'package:providentia_api_client/providentia_api_client.dart';

import '../../core/api/api_client.dart';
import 'profile_port.dart';

final class AdminProfilePort implements ProfilePort {
  const AdminProfilePort(this.api);
  final AdminApi api;
  @override
  Future<Object?> call(
    String operation, {
    Map<String, String>? path,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final definition = adminApiOperations[operation];
    if (definition == null) {
      throw const ProfileFailure('This client needs an API contract update.');
    }
    var endpoint = definition.pathTemplate;
    for (final entry in (path ?? <String, String>{}).entries) {
      endpoint = endpoint.replaceAll(
        '{${entry.key}}',
        Uri.encodeComponent(entry.value),
      );
    }
    try {
      final response = switch (definition.method) {
        'GET' => await api.get(endpoint, query: query),
        'POST' => await api.post(endpoint, body: body, query: query),
        'PUT' => await api.put(endpoint, body: body),
        'DELETE' => await api.delete(endpoint, body: body),
        _ => throw const ProfileFailure(
          'The profile operation is unavailable.',
        ),
      };
      if (response.headers['content-type']?.startsWith('image/') == true) {
        return response.bytes;
      }
      return response.jsonBody;
    } on ApiException catch (error) {
      throw ProfileFailure(error.message);
    }
  }
}
