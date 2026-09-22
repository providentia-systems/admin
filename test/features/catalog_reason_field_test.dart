import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/catalog/catalog_reason_field.dart';

void main() {
  testWidgets('ordinary edits have a visible default and Other requires text', (
    tester,
  ) async {
    final reason = TextEditingController();
    addTearDown(reason.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogReasonField(controller: reason, creating: false),
        ),
      ),
    );
    expect(reason.text, 'Correct catalog details');
    await tester.tap(find.byKey(const Key('catalog-reason-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    expect(reason.text, isEmpty);
    final input = find.byKey(const Key('catalog-reason-other'));
    expect(input, findsOneWidget);
    await tester.enterText(input, 'Owner-reviewed identity correction');
    expect(reason.text, 'Owner-reviewed identity correction');
    expect(
      tester.widget<TextFormField>(input).validator!('  '),
      'Enter a reason.',
    );
  });

  testWidgets(
    'creation reasons are contextual and existing custom text is preserved',
    (tester) async {
      final reason = TextEditingController(text: 'Existing explanation');
      addTearDown(reason.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogReasonField(
              controller: reason,
              creating: true,
              enabled: false,
            ),
          ),
        ),
      );
      expect(reason.text, 'Existing explanation');
      expect(find.byKey(const Key('catalog-reason-other')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('catalog-reason-other')),
            )
            .enabled,
        isFalse,
      );
    },
  );
}
