import 'package:providentia_admin/features/access/access_repository.dart';
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
    'profile': <String,Object?>{'administratorAccess': <String,Object?>{'features': <String,Object?>{'accounts.read': true, 'accounts.manage': true, 'accounts.assign': true, 'people.read': true, 'homes.read': true, 'homes.manage': true, 'homes.assign': true, 'administrators.read': true, 'administrators.approve': true, 'administrators.manage': true, 'groups.manage': true, 'countries.manage': true, 'policies.manage': true, 'catalog.read': true, 'catalog.review': true, 'catalog.curate': true, 'billing.read': true, 'billing.manage': true, 'audit.read': true}}},
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

  test('account assignment uses its own revision and one group', () async {
    final api = FakeApi((_) async => jsonResponse({}));
    await AccessRepository(api).assign('account','account-id','group-id',4);
    expect(api.requests.single.method,'PUT');
    expect(api.requests.single.path,'/api/v1/admin/access/account/account-id');
    expect(api.requests.single.body,{'groupId':'group-id','expectedRevision':4});
  });
}
