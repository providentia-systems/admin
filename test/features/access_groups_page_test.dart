import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/app/admin_layout.dart';
import 'package:providentia_admin/app/theme.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/features/access/access_groups_page.dart';

import '../support/fake_api.dart';

const _definition = <String, Object?>{
  'scope': 'home',
  'features': <String>['members.invite'],
  'limits': <String>['members.total'],
};
Map<String, Object?> _group({bool protected = false}) => <String, Object?>{
  'id': 'group-one',
  'name': 'Starter',
  'scope': 'home',
  'description': 'Default home',
  'features': <String, Object?>{'members.invite': false},
  'limits': <String, Object?>{'members.total': 10},
  'delegablePermissions': <String>[],
  'rolePermissions': <String, Object?>{},
  'revision': 7,
  'protected': protected,
};

Future<void> _pump(
  WidgetTester tester,
  FakeApi api, {
  Size size = const Size(1100, 1000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(body: AccessGroupsPage(api: api)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in <Size>[const Size(720, 700), const Size(1440, 1000)]) {
    testWidgets(
      'account and home group editors keep field subtext clear at ${size.width.toInt()}px',
      (tester) async {
        final api = FakeApi((r) async {
          if (r.path.endsWith('/catalog')) {
            return jsonResponse({
              'data': <Map<String, Object?>>[
                _definition,
                <String, Object?>{..._definition, 'scope': 'account'},
              ],
            });
          }
          return jsonResponse({
            'data': <Map<String, Object?>>[
              <String, Object?>{
                ..._group(),
                'scope': r.query?['scope'] ?? 'home',
              },
            ],
          });
        });
        await _pump(tester, api, size: size);

        for (final scope in <String>['home', 'account']) {
          if (scope == 'account') {
            await tester.tap(find.text('Accounts'));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text('Starter'));
          await tester.pumpAndSettle();

          expect(find.byType(AdminFormFields), findsWidgets);
          final name = tester.getRect(
            find.widgetWithText(TextFormField, 'Group name'),
          );
          final description = tester.getRect(
            find.widgetWithText(TextFormField, 'Description'),
          );
          expect(description.top - name.bottom, greaterThanOrEqualTo(19));
          expect(find.text('7/120'), findsOneWidget);
          expect(find.text('12/1000'), findsOneWidget);

          await tester.enterText(
            find.widgetWithText(TextFormField, 'Group name'),
            '',
          );
          await tester.tap(find.text('Save group'));
          await tester.pumpAndSettle();
          expect(find.text('Enter a name.'), findsOneWidget);
          final invalidName = tester.getRect(
            find.widgetWithText(TextFormField, 'Group name'),
          );
          final descriptionAfterValidation = tester.getRect(
            find.widgetWithText(TextFormField, 'Description'),
          );
          expect(
            descriptionAfterValidation.top - invalidName.bottom,
            greaterThanOrEqualTo(19),
          );
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
        }
      },
    );
  }

  testWidgets(
    'editing a home group changes invitation quota and inherited permissions',
    (tester) async {
      final api = FakeApi(
        (r) async => r.path.endsWith('/catalog')
            ? jsonResponse({
                'data': [_definition],
              })
            : r.method == 'GET'
            ? jsonResponse({
                'data': [_group()],
              })
            : jsonResponse(_group()),
      );
      await _pump(tester, api);
      await tester.tap(find.text('Starter'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckboxListTile, 'members / invite').first,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'members / total'),
        '3',
      );
      await tester.tap(find.widgetWithText(ExpansionTile, 'members / invite'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Homeowner may change this permission'),
      );
      await tester.tap(find.text('Homeowner may change this permission'));
      await tester.tap(find.text('Default for manager'));
      await tester.tap(find.text('Save group'));
      await tester.pumpAndSettle();
      final request = api.requests.singleWhere((r) => r.method == 'PUT');
      expect(request.path, '/api/v1/admin/access/groups/group-one');
      expect(request.body, containsPair('expectedRevision', 7));
      expect(request.body, containsPair('limits', {'members.total': 3}));
      expect(request.body, containsPair('features', {'members.invite': true}));
      expect(
        request.body,
        containsPair('delegablePermissions', ['members.invite']),
      );
      expect((request.body as Map)['rolePermissions'], {
        'manager': ['members.invite'],
        'member': [],
        'viewer': [],
      });
    },
  );

  testWidgets(
    'new groups validate names and integer allowances before sending',
    (tester) async {
      final api = FakeApi(
        (r) async => r.path.endsWith('/catalog')
            ? jsonResponse({
                'data': [_definition],
              })
            : r.method == 'GET'
            ? jsonResponse({'data': []})
            : jsonResponse(_group()),
      );
      await _pump(tester, api);
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save group'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Group name'),
        'Family',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'members / total'),
        '-2',
      );
      await tester.tap(find.text('Save group'));
      await tester.pumpAndSettle();
      expect(
        find.text('Use -1 or a nonnegative whole number.'),
        findsOneWidget,
      );
      expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'members / total'),
        '-1',
      );
      await tester.tap(find.text('Save group'));
      await tester.pumpAndSettle();
      expect(
        api.requests.singleWhere((r) => r.method == 'POST').body,
        containsPair('limits', {'members.total': -1}),
      );
    },
  );

  testWidgets('system owner group is visible but immutable', (tester) async {
    final api = FakeApi(
      (r) async => jsonResponse({
        'data': r.path.endsWith('/catalog')
            ? [_definition]
            : [_group(protected: true)],
      }),
    );
    await _pump(tester, api);
    await tester.tap(find.text('Starter'));
    await tester.pumpAndSettle();
    expect(find.text('System owner permissions'), findsOneWidget);
    expect(find.text('Save group'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Group name'),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(api.requests.every((r) => r.method == 'GET'), isTrue);
  });

  testWidgets(
    'group assignment reloads after a conflict and uses the current revision',
    (tester) async {
      var revision = 1;
      final api = FakeApi((r) async {
        if (r.path.endsWith('/groups')) {
          return jsonResponse({
            'data': [_group()],
          });
        }
        if (r.method == 'GET') {
          return jsonResponse({'groupId': 'group-one', 'revision': revision});
        }
        if (revision == 1) {
          revision = 2;
          throw const ApiException(
            statusCode: 409,
            message: 'Changed by another administrator.',
          );
        }
        return jsonResponse({});
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showGroupAssignment(context, api, 'home', 'home-one'),
                child: const Text('Assign'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Assign'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assign group'));
      await tester.pumpAndSettle();
      expect(find.text('Changed by another administrator.'), findsOneWidget);
      await tester.tap(find.text('Assign group'));
      await tester.pumpAndSettle();
      expect(
        api.requests
            .where((r) => r.method == 'PUT')
            .map((r) => (r.body as Map)['expectedRevision']),
        [1, 2],
      );
    },
  );
}
