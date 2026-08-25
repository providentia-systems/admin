import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/accounts/account_repository.dart';

import '../support/fake_api.dart';

void main() {
  const account = <String, Object?>{
    'userId': '11111111-1111-4111-8111-111111111111',
    'email': 'operator@example.test',
    'emailVerified': true,
    'displayName': 'Operator',
    'status': 'active',
    'revision': 3,
    'createdAt': '2026-01-01T00:00:00Z',
    'statusChangedAt': null,
    'suspendedAt': null,
    'closedAt': null,
    'homeCount': 1,
    'activeSessionCount': 2,
    'platformRoles': <Object?>['platform_administrator'],
  };

  test('lists privacy-safe accounts with explicit filters', () async {
    final api = FakeApi(
      (_) async => jsonResponse(<String, Object?>{
        'data': <Object?>[account],
        'pagination': <String, Object?>{'limit': 50, 'offset': 0, 'total': 1},
      }),
    );
    final repository = AccountRepository(api);

    final page = await repository.list(search: 'operator', status: 'active');

    expect(page.data.single.email, 'operator@example.test');
    expect(page.total, 1);
    expect(api.requests.single.path, '/api/v1/admin/accounts');
    expect(api.requests.single.query, containsPair('search', 'operator'));
    expect(api.requests.single.query, containsPair('status', 'active'));
  });

  test('status mutation is revision-bound and auditable', () async {
    final api = FakeApi((_) async => jsonResponse(account));
    final repository = AccountRepository(api);

    await repository.changeStatus(
      userId: account['userId']! as String,
      status: 'suspended',
      reason: 'Security review required',
      expectedRevision: 3,
    );

    final request = api.requests.single;
    expect(request.method, 'PATCH');
    expect(request.path, endsWith('/status'));
    expect(request.body, <String, Object?>{
      'status': 'suspended',
      'reason': 'Security review required',
      'expectedRevision': 3,
    });
  });

  test('role grant and revoke share canonical revision-bound route', () async {
    final api = FakeApi((_) async => jsonResponse(account));
    final repository = AccountRepository(api);

    await repository.changeRole(
      userId: account['userId']! as String,
      role: 'catalog_reviewer',
      expectedRevision: 3,
      grant: true,
    );
    await repository.changeRole(
      userId: account['userId']! as String,
      role: 'catalog_reviewer',
      expectedRevision: 4,
      grant: false,
    );

    expect(api.requests[0].method, 'PUT');
    expect(api.requests[1].method, 'DELETE');
    expect(api.requests[0].path, api.requests[1].path);
    expect(api.requests[1].body, <String, Object?>{'expectedRevision': 4});
  });
}
