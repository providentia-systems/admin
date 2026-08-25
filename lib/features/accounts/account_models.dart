final class OperatorAccount {
  const OperatorAccount({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.emailVerified,
    required this.status,
    required this.revision,
    required this.homeCount,
    required this.activeSessionCount,
    required this.platformRoles,
    this.homes = const <OperatorHome>[],
  });

  factory OperatorAccount.fromJson(Map<String, Object?> json) {
    final roles = json['platformRoles'];
    final homes = json['homes'];
    return OperatorAccount(
      userId: json['userId']! as String,
      email: json['email']! as String,
      displayName: json['displayName'] as String? ?? '',
      emailVerified: json['emailVerified']! as bool,
      status: json['status']! as String,
      revision: json['revision']! as int,
      homeCount: json['homeCount']! as int,
      activeSessionCount: json['activeSessionCount']! as int,
      platformRoles: roles is List<Object?>
          ? List<String>.unmodifiable(roles.whereType<String>())
          : const <String>[],
      homes: homes is List<Object?>
          ? List<OperatorHome>.unmodifiable(
              homes.whereType<Map<String, Object?>>().map(OperatorHome.fromJson),
            )
          : const <OperatorHome>[],
    );
  }

  final String userId;
  final String email;
  final String displayName;
  final bool emailVerified;
  final String status;
  final int revision;
  final int homeCount;
  final int activeSessionCount;
  final List<String> platformRoles;
  final List<OperatorHome> homes;

  bool get isClosed => status == 'closed';
}

final class OperatorHome {
  const OperatorHome({
    required this.homeId,
    required this.name,
    required this.role,
    required this.status,
    this.subscriptionStatus,
  });

  factory OperatorHome.fromJson(Map<String, Object?> json) {
    final subscription = json['subscription'];
    return OperatorHome(
      homeId: json['homeId']! as String,
      name: json['name']! as String,
      role: json['membershipRole']! as String,
      status: json['membershipStatus']! as String,
      subscriptionStatus: subscription is Map<String, Object?>
          ? subscription['status'] as String?
          : null,
    );
  }

  final String homeId;
  final String name;
  final String role;
  final String status;
  final String? subscriptionStatus;
}

final class OperatorAccountPage {
  const OperatorAccountPage({
    required this.data,
    required this.limit,
    required this.offset,
    required this.total,
  });

  factory OperatorAccountPage.fromJson(Map<String, Object?> json) {
    final data = json['data'];
    final pagination = json['pagination'];
    final page = pagination is Map<String, Object?>
        ? pagination
        : const <String, Object?>{};
    return OperatorAccountPage(
      data: data is List<Object?>
          ? List<OperatorAccount>.unmodifiable(
              data
                  .whereType<Map<String, Object?>>()
                  .map(OperatorAccount.fromJson),
            )
          : const <OperatorAccount>[],
      limit: page['limit'] as int? ?? 50,
      offset: page['offset'] as int? ?? 0,
      total: page['total'] as int? ?? 0,
    );
  }

  final List<OperatorAccount> data;
  final int limit;
  final int offset;
  final int total;
}
