import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/catalog/catalog_models.dart';
import 'package:providentia_admin/features/catalog/catalog_page.dart';
import 'package:providentia_admin/features/catalog/catalog_repository.dart';
import 'package:providentia_admin/features/catalog/published_category_picker.dart';

import '../support/fake_api.dart';

String id(int n) =>
    '0198f4e1-7abc-7def-8abc-${n.toRadixString(16).padLeft(12, '0')}';
Map<String, Object?> icon(int n) => {
  'targetType': 'product',
  'targetId': id(n),
  'canonicalName': 'Repeated product name',
  'revision': 7,
};

void main() {
  test(
    'missing-icon products retain target identity and cannot be approved',
    () {
      final item = CatalogQueueItem.fromJson(icon(1), queue: 'icons');
      expect(item.id, id(1));
      expect(item.recordType, CatalogQueueRecordType.missingIcon);
      expect(item.status, 'Missing icon');
      expect(item.canDecide, isFalse);
      expect(item.isProposal, isFalse);
      expect(item.isContribution, isFalse);
      expect(item.revision, 7);
    },
  );

  test(
    'malformed icons fail closed instead of inventing actionable identities',
    () {
      for (final row in <Map<String, Object?>>[
        {...icon(1)}..remove('targetId'),
        {...icon(1), 'targetId': 'unknown'},
        {...icon(1), 'targetType': 'proposal'},
        {...icon(1), 'revision': 0},
        {...icon(1), 'canonicalName': ''},
      ]) {
        expect(
          () => CatalogQueueItem.fromJson(row, queue: 'icons'),
          throwsFormatException,
        );
      }
    },
  );

  test('conflicts, merges and proposals retain distinct action boundaries', () {
    for (final queue in ['duplicates', 'aliases', 'barcodes']) {
      final item = CatalogQueueItem.fromJson({
        'id': id(1),
        'proposalId': id(2),
        'proposalType': 'product',
        'conflictType': 'duplicate',
        'status': 'open',
        'revision': 3,
      }, queue: queue);
      expect(item.id, id(1));
      expect(item.recordType, CatalogQueueRecordType.conflict);
      expect(item.canDecide, isFalse);
    }
    final merge = CatalogQueueItem.fromJson({
      'id': id(3),
      'survivorId': id(4),
      'status': 'applied',
      'revision': 2,
    }, queue: 'merges');
    expect(merge.recordType, CatalogQueueRecordType.merge);
    expect(merge.canDecide, isFalse);
    final proposal = CatalogQueueItem.fromJson({
      'id': id(5),
      'proposalType': 'category',
      'moderationStatus': 'pending',
      'revision': 1,
      'payload': {'canonicalName': 'Food'},
    }, queue: 'proposals');
    expect(proposal.canDecide, isTrue);
    expect(proposal.title, 'Food');
  });

  test(
    '101 same-name icons page by supported offset without repeating page one',
    () async {
      final api = FakeApi((request) async {
        expect(request.method, 'GET');
        expect(request.path, '/api/v1/catalog-admin/workbench');
        expect(request.query!.containsKey('afterId'), isFalse);
        final start = int.parse(request.query!['offset']!);
        return jsonResponse({
          'data': [
            for (var n = start; n < start + 50 && n < 101; n++) icon(n + 1),
          ],
        });
      });
      final repository = CatalogRepository(api);
      final all = <CatalogQueueItem>[];
      for (final offset in [0, 50, 100, 150]) {
        final page = await repository.workbench(queue: 'icons', offset: offset);
        all.addAll(page);
        if (offset == 150) expect(page, isEmpty);
      }
      expect(all.length, 101);
      expect(all.map((item) => item.id).toSet().length, 101);
      expect(all.every((item) => !item.canDecide), isTrue);
    },
  );

  testWidgets('icons offer only icon management, never a proposal decision', (
    tester,
  ) async {
    var managed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogModerationDetail(
            item: CatalogQueueItem.fromJson(icon(1), queue: 'icons'),
            isContribution: false,
            canReview: true,
            canCurate: true,
            preview: null,
            onDecision: (_) =>
                fail('Product must never be sent to proposal decisions'),
            onPreview: () {},
            onLinkProposal: () {},
            onPublishImage: () {},
            onManageIcon: () => managed++,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('approve-moderation-item')), findsNothing);
    expect(find.byKey(const Key('reject-moderation-item')), findsNothing);
    final action = find.byKey(const Key('manage-missing-product-icon'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    expect(managed, 1);
  });

  testWidgets('category picker sends offsets across page and search changes', (
    tester,
  ) async {
    final offsets = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPublishedCategoryPicker(
                context: context,
                loadPage: (query, offset) async {
                  offsets.add(offset);
                  return [
                    for (var n = 0; n < 50; n++)
                      PublishedCategory.fromJson({
                        'id': id(offset + n + 1),
                        'canonicalName': 'Category ${offset + n + 1}',
                        'revision': 1,
                      }),
                  ];
                },
              ),
              child: const Text('Open categories'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next category page'));
    await tester.pumpAndSettle();
    expect(offsets, [0, 50]);
    expect(find.text('Category 51'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous category page'));
    await tester.pumpAndSettle();
    expect(offsets, [0, 50, 0]);
    await tester.enterText(
      find.byKey(const Key('category-search-query')),
      'new',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(offsets.last, 0);
  });
}
