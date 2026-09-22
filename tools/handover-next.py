#!/usr/bin/env python3
"""Exercise the actual editor controls without bypassing revision or audit guards."""
from pathlib import Path
p = Path('test/features/catalog_maintenance_page_test.dart')
s = p.read_text()
s = s.replace("import 'package:providentia_admin/features/catalog/catalog_maintenance_page.dart';", "import 'package:providentia_admin/features/catalog/catalog_maintenance_page.dart';\nimport 'package:providentia_admin/features/catalog/catalog_maintenance_repository.dart';")
s = s.replace("find.text('Create')", "find.text('Add category')")
s = s.replace("      await tester.tap(find.text('Save'));\n      await tester.pumpAndSettle();\n      expect(find.text('Enter an audit reason.'), findsOneWidget);", "      await _otherReason(tester, '');\n      await tester.tap(find.text('Save'));\n      await tester.pumpAndSettle();\n      expect(find.text('Enter an audit reason of no more than 500 characters.'), findsOneWidget);")
s = s.replace("await tester.enterText(_field('Audit reason'), 'Add pantry category');", "await tester.enterText(find.byKey(const Key('catalog-reason-other')), 'Add pantry category');")
s = s.replace("        await tester.enterText(\n          _field('Audit reason'),\n          'Reviewed category change',\n        );", "        await _otherReason(tester, 'Reviewed category change');")
s = s.replace("await tester.enterText(_field('Audit reason'), 'Create category');", "await _otherReason(tester, 'Create category');")
s = s.replace("    await tester.tap(find.text('Close'));\n    await tester.pumpAndSettle();", "    await tester.tap(find.text('Close'));\n    await tester.pumpAndSettle();\n    expect(find.text('Discard unsaved changes?'), findsOneWidget);\n    await tester.tap(find.text('Discard changes'));\n    await tester.pumpAndSettle();")
helper = '''Future<void> _otherReason(WidgetTester tester, String explanation) async {
  final choice = find.byKey(const Key('catalog-reason-choice'));
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Other').last);
  await tester.pumpAndSettle();
  final field = find.byKey(const Key('catalog-reason-other'));
  await tester.ensureVisible(field);
  await tester.enterText(field, explanation);
}

'''
s = s.replace('void main() {', helper + '''void main() {
  test('maintenance repository forwards bounded search and offset to the same endpoint', () async {
    final api = FakeApi((request) async {
      expect(request.path, '/api/v1/catalog-admin/entities/category');
      expect(request.query, {'offset': '100', 'q': 'Pantry'});
      return jsonResponse({'data': []});
    });
    expect(await CatalogMaintenanceRepository(api).list('category', offset: 100, query: ' Pantry '), isEmpty);
    expect(api.requests, hasLength(1));
  });

  testWidgets('dirty editor keeps text until explicit discard and does not write', (tester) async {
    final api = FakeApi((_) async => jsonResponse({'data': []}));
    await _pump(tester, api);
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('canonical name'), 'Unsaved pantry');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field('canonical name')).controller!.text, 'Unsaved pantry');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsNothing);
    expect(api.requests.where((request) => request.method == 'PUT'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct Products and Categories keep independent search context', (tester) async {
    final api = FakeApi((_) async => jsonResponse({'data': []}));
    await _pump(tester, api);
    final search = find.byKey(const Key('catalog-entity-search'));
    await tester.enterText(search, 'Pantry');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(api.requests.last.query?['q'], 'Pantry');
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    expect(api.requests.last.path, '/api/v1/catalog-admin/entities/product');
    expect(find.text('Add product'), findsOneWidget);
    await tester.enterText(search, 'Rice');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, 'Pantry');
    expect(api.requests.last.query?['q'], 'Pantry');
    expect(api.requests.last.query?['offset'], '0');
    expect(tester.takeException(), isNull);
  });
''', 1)
p.write_text(s)
print('Direct editor, search context, Other reasons, concurrency and discard regressions installed.')
