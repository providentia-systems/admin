import 'dart:collection';

import '../../core/security/secure_id.dart';

enum PlatformAdministratorStatus { pending, active }

final class PlatformAdministrator {
  PlatformAdministrator({
    required this.id,
    required this.email,
    required this.status,
    required this.revision,
    required this.createdAt,
  }) {
    if (!isUuid(id) || !_emailPattern.hasMatch(email) || revision < 1) {
      throw const FormatException('Platform administrator data was malformed.');
    }
  }

  factory PlatformAdministrator.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final email = json['email'];
    final revision = json['revision'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final status = switch (json['status']) {
      'pending' => PlatformAdministratorStatus.pending,
      'active' => PlatformAdministratorStatus.active,
      _ => null,
    };
    if (id is! String ||
        email is! String ||
        revision is! int ||
        createdAt == null ||
        status == null) {
      throw const FormatException('Platform administrator data was malformed.');
    }
    return PlatformAdministrator(
      id: id,
      email: email,
      status: status,
      revision: revision,
      createdAt: createdAt.toUtc(),
    );
  }

  final String id;
  final String email;
  final PlatformAdministratorStatus status;
  final int revision;
  final DateTime createdAt;
}

final class PlatformAdministrationSnapshot {
  PlatformAdministrationSnapshot({
    this.loading = false,
    List<PlatformAdministrator> administrators =
        const <PlatformAdministrator>[],
    this.safeMessage,
  }) : administrators = UnmodifiableListView<PlatformAdministrator>(
         List<PlatformAdministrator>.of(administrators),
       );

  final bool loading;
  final List<PlatformAdministrator> administrators;
  final String? safeMessage;
}

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
