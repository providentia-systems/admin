import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/administrators/platform_administration_controller.dart';
import 'package:providentia_admin/features/administrators/platform_administrator_models.dart';
import 'package:providentia_admin/features/administrators/platform_administrator_repository.dart';
import 'package:providentia_admin/features/administrators/platform_administrators_page.dart';

import '../support/fake_api.dart';

const _administratorJson = <String, Object?>{
  'id': '11111111-1111-4111-8111-111111111111',
  'email': 'admin@example.test',
  'status': 'active',
  'revision': 4,
  'createdAt': '2026-08-01T00:00:00Z',
};

PlatformAdministrator _administrator({
  String id = '11111111-1111-4111-8111-111111111111',
  String email = 'admin@example.test',
  PlatformAdministratorStatus status = PlatformAdministratorStatus.active,
  int revision = 4,
}) => PlatformAdministrator(
  id: id,
  email: email,
  status: status,
  revision: revision,
  createdAt: DateTime.utc(2026, 8),
);

final class _MemoryAdministrationPort implements PlatformAdministrationPort {
  _MemoryAdministrationPort(this.administrators);

  List<PlatformAdministrator> administrators;
  final List<String> grants = <String>[];
  final List<(String, int)> revocations = <(String, int)>[];
  PlatformAdministrationFailure? grantFailure;
  PlatformAdministrationFailure? revokeFailure;
  Completer<List<PlatformAdministrator>>? pendingList;

  @override
  Future<PlatformAdministrator> grant(String email) async {
    grants.add(email);
    final failure = grantFailure;
    if (failure != null) throw failure;
    return _administrator(email: email);
  }

  @override
  Future<List<PlatformAdministrator>> list() async =>
      pendingList?.future ?? List<PlatformAdministrator>.of(administrators);

  @override
  Future<void> revoke({
    required String administratorId,
    required int expectedRevision,
  }) async {
    revocations.add((administratorId, expectedRevision));
    final failure = revokeFailure;
    if (failure != null) throw failure;
  }
}

void main() {
  group('PlatformAdministratorRepository', () {
    test('lists strict administrator grants on the global route', () async {
      final api = FakeApi(
        (_) async => jsonResponse(<String, Object?>{
          'data': <Object?>[_administratorJson],
        }),
      );

      final administrators = await PlatformAdministratorRepository(api).list();

      expect(administrators.single.email, 'admin@example.test');
      expect(administrators.single.status, PlatformAdministratorStatus.active);
      expect(api.requests.single.method, 'GET');
      expect(api.requests.single.path, '/api/v1/platform/administrators');
    });

    test('grant normalizes no wire fields and posts only email', () async {
      final api = FakeApi((_) async => jsonResponse(_administratorJson));

      await PlatformAdministratorRepository(api).grant('admin@example.test');

      expect(api.requests.single.method, 'POST');
      expect(api.requests.single.path, '/api/v1/platform/administrators');
      expect(api.requests.single.body, <String, Object?>{
        'email': 'admin@example.test',
      });
    });

    test('revoke is revision-bound on the grant identifier', () async {
      final api = FakeApi((_) async => jsonResponse(const <String, Object?>{}));

      await PlatformAdministratorRepository(api).revoke(
        administratorId: _administratorJson['id']! as String,
        expectedRevision: 4,
      );

      expect(api.requests.single.method, 'POST');
      expect(
        api.requests.single.path,
        '/api/v1/platform/administrators/'
        '11111111-1111-4111-8111-111111111111/revoke',
      );
      expect(api.requests.single.body, <String, Object?>{
        'expectedRevision': 4,
      });
    });

    test('malformed DTOs fail closed with a safe repository failure', () async {
      final api = FakeApi(
        (_) async => jsonResponse(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{..._administratorJson, 'revision': 0},
          ],
        }),
      );

      await expectLater(
        PlatformAdministratorRepository(api).list(),
        throwsA(
          isA<PlatformAdministrationFailure>().having(
            (failure) => failure.safeMessage,
            'safeMessage',
            'Administrator details could not be read safely.',
          ),
        ),
      );
    });
  });

  group('PlatformAdministrationController', () {
    test('normalizes grants and reloads the authoritative list', () async {
      final port = _MemoryAdministrationPort(<PlatformAdministrator>[
        _administrator(),
      ]);
      final controller = PlatformAdministrationController(port);

      await controller.grant('  NEW.ADMIN@Example.Test  ');

      expect(port.grants, <String>['new.admin@example.test']);
      expect(controller.snapshot.administrators, hasLength(1));
      expect(controller.snapshot.safeMessage, isNull);
    });

    test('invalid email is rejected without reaching the port', () async {
      final port = _MemoryAdministrationPort(const <PlatformAdministrator>[]);
      final controller = PlatformAdministrationController(port);

      await controller.grant('not-an-email');

      expect(port.grants, isEmpty);
      expect(controller.snapshot.safeMessage, 'Enter a valid email address.');
    });

    test('conflict reloads the authoritative revision', () async {
      final current = _administrator(revision: 8);
      final port = _MemoryAdministrationPort(<PlatformAdministrator>[current])
        ..revokeFailure = const PlatformAdministrationFailure(
          kind: PlatformAdministrationFailureKind.conflict,
          safeMessage: 'The administrator changed.',
        );
      final controller = PlatformAdministrationController(port);

      await controller.revoke(_administrator(revision: 4));

      expect(port.revocations.single.$2, 4);
      expect(controller.snapshot.administrators.single.revision, 8);
      expect(controller.snapshot.safeMessage, 'The administrator changed.');
    });

    test('late list completion cannot notify after disposal', () async {
      final pending = Completer<List<PlatformAdministrator>>();
      final port = _MemoryAdministrationPort(const <PlatformAdministrator>[])
        ..pendingList = pending;
      final controller = PlatformAdministrationController(port);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      final loading = controller.load();
      expect(notifications, 1);
      controller.dispose();
      pending.complete(<PlatformAdministrator>[_administrator()]);
      await loading;

      expect(notifications, 1);
    });
  });

  group('PlatformAdministratorsPage', () {
    testWidgets('protects the final active administrator', (tester) async {
      final only = _administrator();
      final port = _MemoryAdministrationPort(<PlatformAdministrator>[only]);
      final api = FakeApi((_) async => throw StateError('unexpected API call'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlatformAdministratorsPage(
              api: api,
              administrationPort: port,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final revoke = tester.widget<IconButton>(
        find.byKey(Key('revoke-administrator-${only.id}')),
      );
      expect(revoke.onPressed, isNull);
      final protection = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(Key('revoke-administrator-${only.id}')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(protection.message, contains('final active'));
    });

    testWidgets('confirms a revision-bound revoke', (tester) async {
      final first = _administrator();
      final second = _administrator(
        id: '22222222-2222-4222-8222-222222222222',
        email: 'second@example.test',
        revision: 6,
      );
      final port = _MemoryAdministrationPort(<PlatformAdministrator>[
        first,
        second,
      ]);
      final api = FakeApi((_) async => throw StateError('unexpected API call'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlatformAdministratorsPage(
              api: api,
              administrationPort: port,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('revoke-administrator-${first.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Revoke platform administrator?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-revoke-administrator')));
      await tester.pumpAndSettle();

      expect(port.revocations, <(String, int)>[(first.id, first.revision)]);
    });
  });
}
