import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/features/profile/admin_profile_port.dart';
import 'package:providentia_admin/features/profile/profile_port.dart';

import '../support/fake_api.dart';

void main() {
  test(
    'profile requests use generated operations and retain proof bodies',
    () async {
      final api = FakeApi((_) async => jsonResponse({}));
      final port = AdminProfilePort(api);
      await port.call(
        'requestAccountEmailCode',
        body: {'email': 'new@example.test'},
      );
      await port.call(
        'updateAccountProfile',
        body: {'displayName': 'Alex', 'expectedRevision': 3},
      );
      await port.call(
        'removeAccountEmail',
        path: {'emailId': 'email-id'},
        body: {'proofToken': 'proof'},
      );
      expect(api.requests.map((r) => r.method), ['POST', 'PATCH', 'POST']);
      expect(api.requests.first.path, '/api/v1/me/emails/codes');
      expect(api.requests.last.body, {'proofToken': 'proof'});
    },
  );
  test('binary avatar responses stay binary', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final api = FakeApi(
      (_) async => ApiResponse(
        statusCode: 200,
        headers: {'content-type': 'image/png'},
        bytes: bytes,
      ),
    );
    expect(await AdminProfilePort(api).call('getOwnAvatar'), same(bytes));
  });
  test(
    'conflicts remain distinguishable so the profile can reload revisions',
    () async {
      final api = FakeApi(
        (_) async => throw const ApiException(
          statusCode: 409,
          message: 'Profile changed.',
        ),
      );
      await expectLater(
        AdminProfilePort(api).call('updateAccountProfile', body: {}),
        throwsA(
          isA<ProfileFailure>().having(
            (e) => e.isConflict,
            'isConflict',
            isTrue,
          ),
        ),
      );
    },
  );
  test('unknown operations fail without an HTTP request', () async {
    final api = FakeApi((_) async => jsonResponse({}));
    await expectLater(
      AdminProfilePort(api).call('unknownOperation'),
      throwsA(isA<ProfileFailure>()),
    );
    expect(api.requests, isEmpty);
  });
}
