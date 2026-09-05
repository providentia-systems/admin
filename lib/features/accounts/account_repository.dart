import '../../core/api/api_client.dart';
import 'account_models.dart';

final class AccountRepository {
  const AccountRepository(this._api);

  final AdminApi _api;

  Future<OperatorAccountPage> list({
    String search = '',
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _api.get(
      '/api/v1/admin/accounts',
      query: <String, String>{
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (status != null && status.isNotEmpty) 'status': status,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return OperatorAccountPage.fromJson(response.jsonObject);
  }

  Future<OperatorAccount> get(String userId) async {
    final response = await _api.get('/api/v1/admin/accounts/$userId');
    return OperatorAccount.fromJson(response.jsonObject);
  }

  Future<OperatorAccount> changeStatus({
    required String userId,
    required String status,
    required String reason,
    required int expectedRevision,
  }) async {
    final response = await _api.patch(
      '/api/v1/admin/accounts/$userId/status',
      body: <String, Object?>{
        'status': status,
        'reason': reason.trim(),
        'expectedRevision': expectedRevision,
      },
    );
    return OperatorAccount.fromJson(response.jsonObject);
  }
}
