import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/app/admin_layout.dart';
import 'package:providentia_admin/app/theme.dart';
import 'package:providentia_admin/core/api/api_client.dart';
import 'package:providentia_admin/core/auth/operator_authorization.dart';
import 'package:providentia_admin/features/geography/country_administration_page.dart';

import '../support/fake_api.dart';

final _authorization = OperatorAuthorization.fromPermissions([
  'countries.manage',
  'policies.manage',
]);
const _country = <String, Object?>{
  'code': 'NA',
  'name': 'Namibia',
  'published': true,
  'defaultCurrency': 'NAD',
  'defaultTimezone': 'Africa/Windhoek',
};
const _settings = <String, Object?>{
  'code': 'NA',
  'published': 1,
  'default_currency': 'NAD',
  'default_timezone': 'Africa/Windhoek',
  'account_group_id': 'starter',
  'invited_group_id': 'invited',
  'home_group_id': 'home',
  'policy_id': 'policy',
  'revision': 4,
};
const _policy = <String, Object?>{
  'id': 'policy',
  'title': 'Privacy notice',
  'body':
      'This privacy notice describes how account and household data are processed by authorized operators to provide and improve the service.',
  'country_code': 'NA',
  'status': 'published',
  'revision': 3,
  'updated_at': '2026-09-01',
};

Future<void> _pump(
  WidgetTester tester,
  FakeApi api, {
  bool policies = false,
  OperatorAuthorization? authorization,
  Size size = const Size(1100, 1100),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(
        body: CountryAdministrationPage(
          api: api,
          authorization: authorization ?? _authorization,
          policies: policies,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in <Size>[const Size(720, 700), const Size(1440, 1000)]) {
    testWidgets(
      'country form keeps counters, borders and validation apart at ${size.width.toInt()}px',
      (tester) async {
        final api = FakeApi((r) async {
          if (r.path.endsWith('/groups')) {
            return jsonResponse({
              'data': r.query?['scope'] == 'account'
                  ? [
                      {'id': 'starter', 'name': 'New accounts'},
                      {'id': 'invited', 'name': 'Invited accounts'},
                    ]
                  : [
                      {'id': 'home', 'name': 'Starter homes'},
                    ],
            });
          }
          if (r.path.endsWith('/privacy-policies')) {
            return jsonResponse({
              'data': [_policy],
            });
          }
          if (r.path.endsWith('/reference-updates')) {
            return jsonResponse({'data': []});
          }
          return jsonResponse(
            r.path.endsWith('/NA')
                ? _settings
                : {
                    'data': [_country],
                  },
          );
        });
        await _pump(tester, api, size: size);
        await tester.tap(find.text('Namibia'));
        await tester.pumpAndSettle();

        expect(find.byType(AdminFormFields), findsOneWidget);
        final currency = tester.getRect(
          find.widgetWithText(TextFormField, 'Default currency'),
        );
        final timezone = tester.getRect(
          find.widgetWithText(TextFormField, 'Default timezone'),
        );
        expect(timezone.top - currency.bottom, greaterThanOrEqualTo(19));
        expect(find.text('3/3'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Default timezone'),
          '',
        );
        await tester.tap(find.text('Save country'));
        await tester.pumpAndSettle();
        expect(find.text('Enter a timezone.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'country settings preserve independent starter groups and save publication with a revision',
    (tester) async {
      final api = FakeApi((r) async {
        if (r.path.endsWith('/groups')) {
          return jsonResponse({
            'data': r.query?['scope'] == 'account'
                ? [
                    {'id': 'starter', 'name': 'New accounts'},
                    {'id': 'invited', 'name': 'Invited accounts'},
                  ]
                : [
                    {'id': 'home', 'name': 'Starter homes'},
                  ],
          });
        }
        if (r.path.endsWith('/privacy-policies')) {
          return jsonResponse({
            'data': [_policy],
          });
        }
        if (r.path.endsWith('/reference-updates')) {
          return jsonResponse({'data': []});
        }
        return jsonResponse(
          r.path.endsWith('/NA')
              ? _settings
              : {
                  'data': [_country],
                },
        );
      });
      await _pump(tester, api);
      await tester.tap(find.text('Namibia'));
      await tester.pumpAndSettle();
      expect(find.text('New accounts'), findsOneWidget);
      expect(find.text('Invited accounts'), findsOneWidget);
      expect(find.text('Starter homes'), findsOneWidget);
      await tester.tap(find.text('Open registration in this country'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Default currency'),
        'usd',
      );
      await tester.tap(find.text('Save country'));
      await tester.pumpAndSettle();
      expect(api.requests.singleWhere((r) => r.method == 'PUT').body, {
        'published': false,
        'accountGroupId': 'starter',
        'invitedGroupId': 'invited',
        'homeGroupId': 'home',
        'policyId': 'policy',
        'defaultCurrency': 'USD',
        'defaultTimezone': 'Africa/Windhoek',
        'expectedRevision': 4,
      });
    },
  );
  testWidgets(
    'country managers without policy rights do not request or expose policy editing',
    (tester) async {
      final api = FakeApi((r) async {
        if (r.path.endsWith('/groups')) {
          return jsonResponse({
            'data': r.query?['scope'] == 'account'
                ? [
                    {'id': 'starter', 'name': 'New accounts'},
                    {'id': 'invited', 'name': 'Invited accounts'},
                  ]
                : [
                    {'id': 'home', 'name': 'Starter homes'},
                  ],
          });
        }
        return jsonResponse(
          r.path.endsWith('/NA')
              ? _settings
              : {
                  'data': r.path.endsWith('/countries') ? [_country] : [],
                },
        );
      });
      await _pump(
        tester,
        api,
        authorization: OperatorAuthorization.fromPermissions([
          'countries.manage',
        ]),
      );
      await tester.tap(find.text('Namibia'));
      await tester.pumpAndSettle();
      expect(find.text('Published privacy notice'), findsNothing);
      expect(
        api.requests.any((r) => r.path.contains('privacy-policies')),
        isFalse,
      );
      await tester.tap(find.text('Save country'));
      await tester.pumpAndSettle();
      expect(
        api.requests.singleWhere((r) => r.method == 'PUT').body,
        containsPair('policyId', 'policy'),
      );
    },
  );
  testWidgets(
    'reference update queues a job and shows its status without changing publication',
    (tester) async {
      var queued = false;
      final api = FakeApi((r) async {
        if (r.method == 'POST') {
          queued = true;
          return jsonResponse({'id': 'job'});
        }
        return jsonResponse({
          'data': r.path.endsWith('/countries')
              ? [_country]
              : queued
              ? [
                  {
                    'status': 'queued',
                    'processed_count': 0,
                    'created_at': '2026-09-07',
                  },
                ]
              : [],
        });
      });
      await _pump(tester, api);
      await tester.tap(find.text('Update country data'));
      await tester.pumpAndSettle();
      expect(find.text('Latest reference update: queued'), findsOneWidget);
      expect(
        api.requests.singleWhere((r) => r.method == 'POST').path,
        '/api/v1/admin/reference-updates',
      );
      expect(api.requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(find.byType(TextField), 'missing country');
      await tester.pumpAndSettle();
      expect(find.text('Namibia'), findsNothing);
    },
  );
  testWidgets(
    'editing a published policy creates a new version with preserved acceptance history',
    (tester) async {
      final api = FakeApi(
        (r) async => jsonResponse(
          r.method == 'GET'
              ? {
                  'data': [_policy],
                }
              : {},
        ),
      );
      await _pump(tester, api, policies: true);
      await tester.tap(find.text('Privacy notice'));
      await tester.pumpAndSettle();
      expect(find.text('Create a new policy version'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Updated privacy notice',
      );
      await tester.ensureVisible(find.text('Publish this version'));
      await tester.tap(find.text('Publish this version'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish version'));
      await tester.pumpAndSettle();
      final request = api.requests.singleWhere((r) => r.method == 'POST');
      expect(request.path, '/api/v1/admin/privacy-policies');
      expect(request.body, containsPair('expectedRevision', 0));
      expect(request.body, containsPair('status', 'published'));
      expect(api.requests.where((r) => r.method == 'PUT'), isEmpty);
    },
  );
  testWidgets(
    'only draft policies expose revision-bound removal and published notice remains',
    (tester) async {
      var removed = false;
      final api = FakeApi((request) async {
        if (request.method == 'DELETE') {
          removed = true;
          return jsonResponse({'removed': true});
        }
        return jsonResponse({
          'data': [
            _policy,
            if (!removed)
              {
                ..._policy,
                'id': 'draft',
                'title': 'Unused draft',
                'status': 'draft',
                'revision': 2,
              },
          ],
        });
      });
      await _pump(tester, api, policies: true);
      expect(find.byTooltip('Remove draft policy'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove draft policy'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Audit reason'),
        'Superseded draft',
      );
      await tester.pump();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      final request = api.requests.singleWhere((r) => r.method == 'DELETE');
      expect(request.path, '/api/v1/admin/privacy-policies/draft');
      expect(request.body, {
        'expectedRevision': 2,
        'reason': 'Superseded draft',
      });
      expect(find.text('Unused draft'), findsNothing);
      expect(find.text('Privacy notice'), findsOneWidget);
    },
  );

  testWidgets(
    'policy removal authorization loss clears the list and confirmation',
    (tester) async {
      final api = FakeApi((request) async {
        if (request.method == 'DELETE') {
          throw const ApiException(statusCode: 401, message: 'Expired');
        }
        return jsonResponse({
          'data': [
            {..._policy, 'status': 'draft'},
          ],
        });
      });
      await _pump(tester, api, policies: true);
      await tester.tap(find.byTooltip('Remove draft policy'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Audit reason'),
        'Unused',
      );
      await tester.pump();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(find.text('Privacy notice'), findsNothing);
      expect(find.widgetWithText(TextField, 'Audit reason'), findsNothing);
      expect(
        find.text('Administrator access changed. Sign in again.'),
        findsOneWidget,
      );
    },
  );
}
