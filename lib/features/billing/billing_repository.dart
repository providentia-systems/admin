import '../../core/api/api_client.dart';

final class BillingPlan {
  const BillingPlan({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.revision,
  });

  factory BillingPlan.fromJson(Map<String, Object?> json) => BillingPlan(
    id: json['id']! as String,
    code: json['code']! as String,
    name: json['name'] as String? ?? json['code']! as String,
    status: json['status']! as String,
    revision: json['revision']! as int,
  );

  final String id;
  final String code;
  final String name;
  final String status;
  final int revision;
}

final class BillingRepository {
  const BillingRepository(this._api);
  final AdminApi _api;

  Future<List<BillingPlan>> listPlans() async {
    final response = await _api.get('/api/v1/operator/billing/plans');
    final data = response.jsonObject['data'];
    if (data is! List<Object?>) return const <BillingPlan>[];
    return List<BillingPlan>.unmodifiable(
      data.whereType<Map<String, Object?>>().map(BillingPlan.fromJson),
    );
  }
}

