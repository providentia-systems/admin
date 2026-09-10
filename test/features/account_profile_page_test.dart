import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/profile/account_profile_page.dart';
import 'package:providentia_admin/features/profile/profile_port.dart';

final class _ProfilePort implements ProfilePort {
  final calls =
      <
        ({
          String operation,
          Map<String, String>? path,
          Map<String, String>? query,
          Map<String, Object?>? body,
        })
      >[];
  bool onboarding = false;
  bool includeLocationNames = true;
  String countryCode = 'NA';
  int? stateId;
  int? cityId;
  int revision = 5;

  String? get stateName => switch ((countryCode, stateId)) {
    ('NA', 1) => 'Khomas',
    ('NA', 3) => 'Erongo',
    ('BW', 11) => 'South-East',
    _ => null,
  };

  String? get cityName => switch ((countryCode, cityId)) {
    ('NA', 2) => 'Windhoek',
    ('NA', 4) => 'Swakopmund',
    ('BW', 12) => 'Gaborone',
    _ => null,
  };

  @override
  Future<Object?> call(
    String operation, {
    Map<String, String>? path,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    calls.add((operation: operation, path: path, query: query, body: body));
    if (operation == 'updateAccountProfile' ||
        operation == 'completeAccountOnboarding') {
      countryCode = '${body!['countryCode']}';
      stateId = body['stateId'] as int?;
      cityId = body['cityId'] as int?;
      revision += 1;
      return <String, Object?>{};
    }
    return switch (operation) {
      'getAccountProfile' => {
        'displayName': 'Alex',
        'countryCode': countryCode,
        'stateId': stateId,
        'cityId': cityId,
        if (includeLocationNames) 'stateName': stateName,
        if (includeLocationNames) 'cityName': cityName,
        'locale': 'en',
        'timezone': countryCode == 'BW' ? 'Africa/Gaborone' : 'Africa/Windhoek',
        'onboardingComplete': !onboarding,
        'avatarSource': 'default',
        'avatarRevision': 2,
        'revision': revision,
        'emails': [
          {'id': 'primary', 'email': 'alex@example.test', 'primary': true},
          {'id': 'other', 'email': 'other@example.test', 'primary': false},
        ],
      },
      'listAvailableCountries' => {
        'data': [
          {
            'code': 'NA',
            'name': 'Namibia',
            'defaultTimezone': 'Africa/Windhoek',
          },
          {
            'code': 'BW',
            'name': 'Botswana',
            'defaultTimezone': 'Africa/Gaborone',
          },
        ],
      },
      'getCountryPrivacyPolicy' => {
        'id': 'policy-${path!['countryCode']}',
        'title': 'Privacy notice',
        'revision': 3,
        'body':
            'Authorized operators can inspect account and home data to provide and improve the service.',
      },
      'listCountryStates' => {
        'data': path?['countryCode'] == 'BW'
            ? [
                {'id': 11, 'name': 'South-East'},
              ]
            : [
                {'id': 1, 'name': 'Khomas'},
                {'id': 3, 'name': 'Erongo'},
              ],
      },
      'listCountryCities' => {
        'data': path?['countryCode'] == 'BW'
            ? [
                {'id': 12, 'name': 'Gaborone'},
              ]
            : query?['stateId'] == '3'
            ? [
                {'id': 4, 'name': 'Swakopmund'},
              ]
            : [
                {'id': 2, 'name': 'Windhoek'},
              ],
      },
      'requestAccountEmailCode' => {
        'challengeId': 'code',
        'bindingToken': 'binding',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
        'resendAfterSeconds': 60,
      },
      'requestSecurityCode' => {
        'challengeId': 'code',
        'bindingToken': 'binding',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
        'resendAfterSeconds': 60,
      },
      'verifySecurityCode' => {'proofToken': 'verified-proof'},
      _ => <String, Object?>{},
    };
  }
}

Future<void> _pump(
  WidgetTester tester,
  _ProfilePort port, {
  bool onboarding = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1300));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: AccountProfilePage(
        port: port,
        onboarding: onboarding,
        onChanged: () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'onboarding requires a name and agreement and records the exact policy version',
    (tester) async {
      final port = _ProfilePort()..onboarding = true;
      await _pump(tester, port, onboarding: true);
      await tester.tap(find.text('Complete account setup'));
      await tester.pumpAndSettle();
      expect(
        find.text('Select your country and accept its privacy notice.'),
        findsOneWidget,
      );
      expect(
        port.calls.where((r) => r.operation == 'completeAccountOnboarding'),
        isEmpty,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Your name'),
        '',
      );
      await tester.tap(
        find.text('I have read and agree to the privacy notice.'),
      );
      await tester.tap(find.text('Complete account setup'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your name.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Your name'),
        'Alex Home',
      );
      await tester.tap(find.text('Complete account setup'));
      await tester.pump();
      expect(
        port.calls
            .singleWhere((r) => r.operation == 'completeAccountOnboarding')
            .body,
        {
          'displayName': 'Alex Home',
          'countryCode': 'NA',
          'stateId': null,
          'cityId': null,
          'locale': 'en',
          'timezone': 'Africa/Windhoek',
          'expectedRevision': 5,
          'policyAccepted': true,
          'policyId': 'policy-NA',
          'policyRevision': 3,
        },
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'selected locations save, reopen with names, and remain clearable',
    (tester) async {
      final port = _ProfilePort();
      await _pump(tester, port);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Your name'),
        'Alex Updated',
      );
      await tester.tap(find.text('Region (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Khomas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('City (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Windhoek'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(
        port.calls
            .singleWhere((r) => r.operation == 'updateAccountProfile')
            .body,
        {
          'displayName': 'Alex Updated',
          'countryCode': 'NA',
          'stateId': 1,
          'cityId': 2,
          'locale': 'en',
          'timezone': 'Africa/Windhoek',
          'expectedRevision': 5,
        },
      );
      expect(
        port.calls.where((call) => call.operation == 'getAccountProfile'),
        hasLength(2),
      );
      expect(find.text('Khomas'), findsOneWidget);
      expect(find.text('Windhoek'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear region'));
      await tester.pumpAndSettle();
      expect(find.text('Not selected'), findsNWidgets(2));
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(
        port.calls
            .where((call) => call.operation == 'updateAccountProfile')
            .last
            .body,
        containsPair('stateId', null),
      );
      expect(
        port.calls
            .where((call) => call.operation == 'updateAccountProfile')
            .last
            .body,
        containsPair('cityId', null),
      );
    },
  );
  testWidgets(
    'saved IDs resolve through bounded country and region scoped lookups',
    (tester) async {
      final port = _ProfilePort()
        ..stateId = 1
        ..cityId = 2
        ..includeLocationNames = false;
      await _pump(tester, port);

      expect(find.text('Khomas'), findsOneWidget);
      expect(find.text('Windhoek'), findsOneWidget);
      expect(find.text('Region selected'), findsNothing);
      expect(find.text('City selected'), findsNothing);

      final stateLookup = port.calls.singleWhere(
        (call) => call.operation == 'listCountryStates',
      );
      expect(stateLookup.path, {'countryCode': 'NA'});
      expect(stateLookup.query, {'search': '', 'offset': '0'});
      final cityLookup = port.calls.singleWhere(
        (call) => call.operation == 'listCountryCities',
      );
      expect(cityLookup.path, {'countryCode': 'NA'});
      expect(cityLookup.query, {'search': '', 'offset': '0', 'stateId': '1'});
    },
  );
  testWidgets('changing region clears its dependent city', (tester) async {
    final port = _ProfilePort()
      ..stateId = 1
      ..cityId = 2;
    await _pump(tester, port);

    await tester.tap(find.text('Region (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erongo'));
    await tester.pumpAndSettle();

    expect(find.text('Erongo'), findsOneWidget);
    expect(find.text('Windhoek'), findsNothing);
    expect(find.text('Not selected'), findsOneWidget);
  });
  testWidgets(
    'country changes clear optional locations and require current acceptance',
    (tester) async {
      final port = _ProfilePort()
        ..stateId = 1
        ..cityId = 2;
      await _pump(tester, port);

      await tester.tap(find.text('Country'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Botswana'));
      await tester.pumpAndSettle();
      expect(find.text('Not selected'), findsNWidgets(2));

      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(
        find.text('Select your country and accept its privacy notice.'),
        findsOneWidget,
      );
      expect(
        port.calls.where((call) => call.operation == 'updateAccountProfile'),
        isEmpty,
      );

      await tester.tap(
        find.text('I have read and agree to the privacy notice.'),
      );
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(
        port.calls
            .singleWhere((call) => call.operation == 'updateAccountProfile')
            .body,
        {
          'displayName': 'Alex',
          'countryCode': 'BW',
          'stateId': null,
          'cityId': null,
          'locale': 'en',
          'timezone': 'Africa/Gaborone',
          'expectedRevision': 5,
          'policyAccepted': true,
          'policyId': 'policy-BW',
          'policyRevision': 3,
        },
      );
    },
  );
  testWidgets(
    'default avatar and opt-in lookup use revision-bound account operations',
    (tester) async {
      final port = _ProfilePort();
      await _pump(tester, port);
      await tester.tap(find.text('Use default avatar'));
      await tester.pumpAndSettle();
      expect(
        port.calls.singleWhere((r) => r.operation == 'deleteOwnAvatar').body,
        {'expectedRevision': 2},
      );
      await tester.tap(find.text('Look up avatar by verified email'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('other@example.test').first);
      await tester.pumpAndSettle();
      expect(
        port.calls.singleWhere((r) => r.operation == 'selectGravatar').body,
        {'emailId': 'other', 'expectedRevision': 5},
      );
    },
  );
  testWidgets(
    'primary email stays protected while another address is verified with a code',
    (tester) async {
      final port = _ProfilePort();
      await _pump(tester, port);
      await tester.ensureVisible(find.text('Add email address'));
      await tester.tap(find.text('Add email address'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'New email address'),
        'new@example.test',
      );
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Eight-digit code'),
        '12345678',
      );
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      final request = port.calls.singleWhere(
        (r) => r.operation == 'verifyAccountEmail',
      );
      expect(request.body, containsPair('code', '12345678'));
      expect(request.body, containsPair('challengeId', 'code'));
    },
  );
}
