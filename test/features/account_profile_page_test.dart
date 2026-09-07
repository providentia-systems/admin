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
          Map<String, Object?>? body,
        })
      >[];
  bool onboarding = false;
  @override
  Future<Object?> call(
    String operation, {
    Map<String, String>? path,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    calls.add((operation: operation, path: path, body: body));
    return switch (operation) {
      'getAccountProfile' => {
        'displayName': 'Alex',
        'countryCode': 'NA',
        'stateId': null,
        'cityId': null,
        'locale': 'en',
        'timezone': 'Africa/Windhoek',
        'onboardingComplete': !onboarding,
        'avatarSource': 'default',
        'avatarRevision': 2,
        'revision': 5,
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
        ],
      },
      'getCountryPrivacyPolicy' => {
        'id': 'policy',
        'title': 'Privacy notice',
        'revision': 3,
        'body':
            'Authorized operators can inspect account and home data to provide and improve the service.',
      },
      'listCountryStates' => {
        'data': [
          {'id': 1, 'name': 'Khomas'},
        ],
      },
      'listCountryCities' => {
        'data': [
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
          'policyId': 'policy',
          'policyRevision': 3,
        },
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'profile changes save name and reference locations with current revision',
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
