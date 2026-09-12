import '../../core/api/api_client.dart';
import '../../core/security/secure_id.dart';

final class OperatorStockPreference {
  const OperatorStockPreference({
    required this.revision,
    required this.alwaysKeep,
    required this.neverSuggest,
    required this.leadTimeDays,
    required this.packOptions,
    this.minimumQuantity,
    this.preferredPackId,
    this.targetCoverageDays,
    this.snoozeUntil,
  });

  factory OperatorStockPreference.fromJson(Map<String, Object?> json) {
    final packs = json['packOptions']! as List<Object?>;
    return OperatorStockPreference(
      revision: json['revision']! as int,
      minimumQuantity: json['minimumQuantity'] as String?,
      alwaysKeep: json['alwaysKeep']! as bool,
      neverSuggest: json['neverSuggest']! as bool,
      preferredPackId: json['preferredPackId'] as String?,
      leadTimeDays: json['leadTimeDays']! as int,
      targetCoverageDays: json['targetCoverageDays'] as int?,
      snoozeUntil: json['snoozeUntil'] as String?,
      packOptions: Map.unmodifiable({
        for (final value in packs.cast<Map<String, Object?>>())
          value['id']! as String: value['label']! as String,
      }),
    );
  }

  final int revision;
  final String? minimumQuantity;
  final bool alwaysKeep;
  final bool neverSuggest;
  final String? preferredPackId;
  final int leadTimeDays;
  final int? targetCoverageDays;
  final String? snoozeUntil;
  final Map<String, String> packOptions;
}

final class OperatorStockPreferenceRepository {
  const OperatorStockPreferenceRepository(this._api);
  final AdminApi _api;

  Future<OperatorStockPreference> load(
    String homeId,
    String homeProductId,
  ) async {
    final response = await _api.get(_path(homeId, homeProductId));
    final json = response.jsonObject;
    if (json['homeProductId'] != homeProductId) {
      throw const FormatException('Unexpected household product preference.');
    }
    return OperatorStockPreference.fromJson(json);
  }

  Future<void> save({
    required String homeId,
    required String homeProductId,
    required OperatorStockPreference preference,
    required String reason,
  }) async {
    if (reason.trim().isEmpty || preference.revision < 0) {
      throw const FormatException('An audit reason and revision are required.');
    }
    final response = await _api.put(
      _path(homeId, homeProductId),
      body: {
        'minimumQuantity': preference.minimumQuantity,
        'alwaysKeep': preference.alwaysKeep,
        'neverSuggest': preference.neverSuggest,
        'preferredPackId': preference.preferredPackId,
        'leadTimeDays': preference.leadTimeDays,
        'targetCoverageDays': preference.targetCoverageDays,
        'snoozeUntil': preference.snoozeUntil,
        'expectedRevision': preference.revision,
        'reason': reason.trim(),
      },
    );
    if (response.jsonObject['revision'] != preference.revision + 1) {
      throw const FormatException('Unexpected preference revision.');
    }
  }

  String _path(String homeId, String productId) {
    if (!isUuid(homeId) || !isUuid(productId)) {
      throw const FormatException('Invalid household product identifier.');
    }
    return '/api/v1/admin/homes/$homeId/stock-preferences/$productId';
  }
}
