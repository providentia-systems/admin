import '../../core/api/api_client.dart';
import 'platform_administrator_models.dart';

enum PlatformAdministrationFailureKind {
  forbidden,
  conflict,
  validation,
  unavailable,
}

final class PlatformAdministrationFailure implements Exception {
  const PlatformAdministrationFailure({
    required this.kind,
    required this.safeMessage,
  });

  final PlatformAdministrationFailureKind kind;
  final String safeMessage;
}

abstract interface class PlatformAdministrationPort {
  Future<List<PlatformAdministrator>> list();
  Future<PlatformAdministrator> grant(String email);
  Future<void> revoke({
    required String administratorId,
    required int expectedRevision,
  });
}

final class PlatformAdministratorRepository
    implements PlatformAdministrationPort {
  const PlatformAdministratorRepository(this._api);

  final AdminApi _api;

  @override
  Future<List<PlatformAdministrator>> list() async {
    try {
      final response = await _api.get('/api/v1/platform/administrators');
      final data = response.jsonObject['data'];
      if (data is! List<Object?>) {
        throw const FormatException('Expected administrator list.');
      }
      return List<PlatformAdministrator>.unmodifiable(
        data.map((value) {
          if (value is! Map<String, Object?>) {
            throw const FormatException('Expected administrator object.');
          }
          return PlatformAdministrator.fromJson(value);
        }),
      );
    } on ApiException catch (error) {
      throw _mapFailure(error, conflictAction: 'list');
    } on FormatException {
      throw const PlatformAdministrationFailure(
        kind: PlatformAdministrationFailureKind.unavailable,
        safeMessage: 'Administrator details could not be read safely.',
      );
    }
  }

  @override
  Future<PlatformAdministrator> grant(String email) async {
    try {
      final response = await _api.post(
        '/api/v1/platform/administrators',
        body: <String, Object?>{'email': email},
      );
      return PlatformAdministrator.fromJson(response.jsonObject);
    } on ApiException catch (error) {
      throw _mapFailure(error, conflictAction: 'grant');
    } on FormatException {
      throw const PlatformAdministrationFailure(
        kind: PlatformAdministrationFailureKind.unavailable,
        safeMessage: 'The administrator grant response was invalid.',
      );
    }
  }

  @override
  Future<void> revoke({
    required String administratorId,
    required int expectedRevision,
  }) async {
    try {
      await _api.post(
        '/api/v1/platform/administrators/$administratorId/revoke',
        body: <String, Object?>{'expectedRevision': expectedRevision},
      );
    } on ApiException catch (error) {
      throw _mapFailure(error, conflictAction: 'revoke');
    }
  }
}

PlatformAdministrationFailure _mapFailure(
  ApiException error, {
  required String conflictAction,
}) => switch (error.statusCode) {
  401 || 403 => const PlatformAdministrationFailure(
    kind: PlatformAdministrationFailureKind.forbidden,
    safeMessage: 'Platform-administrator authorization was lost.',
  ),
  409 => PlatformAdministrationFailure(
    kind: PlatformAdministrationFailureKind.conflict,
    safeMessage: switch (conflictAction) {
      'grant' => 'That administrator grant already exists.',
      'revoke' =>
        'The administrator changed or is the final active administrator.',
      _ => 'The administrator list changed. Refresh and try again.',
    },
  ),
  400 || 422 => const PlatformAdministrationFailure(
    kind: PlatformAdministrationFailureKind.validation,
    safeMessage: 'Check the administrator details and try again.',
  ),
  _ => const PlatformAdministrationFailure(
    kind: PlatformAdministrationFailureKind.unavailable,
    safeMessage: 'Platform administration is temporarily unavailable.',
  ),
};
