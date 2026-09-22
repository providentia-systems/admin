#!/usr/bin/env python3
"""Temporary, branch-scoped application of reviewed handover edits.

This script is removed from the final PR. It does not access user data, change
permissions, skip tests, or touch the default branch.
"""
from pathlib import Path
import re

root = Path.cwd()
p = root / 'lib/features/catalog/catalog_models.dart'
if 'enum CatalogQueueRecordType' not in p.read_text():
    s = p.read_text()
    s = s.replace('final class CatalogQueueItem {', '''/// Workbench resources are not interchangeable proposal identities.
enum CatalogQueueRecordType { proposal, contribution, missingIcon, conflict, merge }

final class CatalogQueueItem {''')
    s = s.replace('    this.storePrice,\n', '    this.storePrice,\n    this.recordType = CatalogQueueRecordType.proposal,\n', 1)
    s = s.replace('  factory CatalogQueueItem.fromJson(Map<String, Object?> json) {', '''  factory CatalogQueueItem.fromJson(
    Map<String, Object?> json, {
    String? queue,
  }) {''', 1)
    a = s.index('    final kind = firstString(')
    b = s.index('    final payload =', a)
    s = s[:a] + '''    final recordType = switch (queue) {
      'icons' => CatalogQueueRecordType.missingIcon,
      'duplicates' || 'aliases' || 'barcodes' => CatalogQueueRecordType.conflict,
      'merges' => CatalogQueueRecordType.merge,
      'proposals' => CatalogQueueRecordType.proposal,
      'contributions' => CatalogQueueRecordType.contribution,
      null when json.containsKey('targetId') => CatalogQueueRecordType.missingIcon,
      null when json.containsKey('conflictType') => CatalogQueueRecordType.conflict,
      null when json.containsKey('survivorId') => CatalogQueueRecordType.merge,
      null when json.containsKey('contributionType') ||
          const ['product_identity', 'product_image', 'store_price']
              .contains(json['type']) => CatalogQueueRecordType.contribution,
      null => CatalogQueueRecordType.proposal,
      _ => throw const FormatException('Unknown catalog workbench queue.'),
    };
    final kind = switch (recordType) {
      CatalogQueueRecordType.missingIcon => 'product needing icon',
      CatalogQueueRecordType.conflict => firstString(['conflictType'], ''),
      CatalogQueueRecordType.merge => 'merge',
      _ => firstString(['kind', 'type', 'contributionType', 'proposalType'], ''),
    };
    if (recordType == CatalogQueueRecordType.contribution) {
      // Normalize the old alias before applying the strict privacy gate.
      if (!json.containsKey('contributionType') && json.containsKey('type')) {
        json = {...json, 'contributionType': json['type']}..remove('type');
      }
      json = _contributionProjection(json, kind);
    }
    final revision = json['revision'] ?? json['contributionRevision'];
    final id = recordType == CatalogQueueRecordType.missingIcon
        ? json['targetId']
        : json['id'] ?? json['proposalId'] ?? json['contributionId'];
    final status = recordType == CatalogQueueRecordType.missingIcon
        ? 'Missing icon'
        : firstString(['status', 'moderationStatus', 'decision'], '');
    if (revision is! int || revision < 1 || id is! String || !isUuid(id) ||
        status.isEmpty || kind.isEmpty ||
        (recordType == CatalogQueueRecordType.missingIcon &&
            (json['targetType'] != 'product' ||
                json['canonicalName'] is! String ||
                (json['canonicalName']! as String).trim().isEmpty))) {
      throw const FormatException('Catalog workbench record was malformed.');
    }
''' + s[b:]
    s = s.replace("      id: firstString(const ['id', 'proposalId', 'contributionId'], 'unknown'),", '      id: id,')
    s = re.sub(r"      status: firstString\(const \[\s*'status',\s*'moderationStatus',\s*'decision',\s*\], 'pending'\),", '      status: status,\n      recordType: recordType,', s)
    s = s.replace('  final String id;\n  final int revision;', '  final CatalogQueueRecordType recordType;\n  final String id;\n  final int revision;', 1)
    s = s.replace('  bool get isProductIdentityContribution', '''  bool get isMissingIcon => recordType == CatalogQueueRecordType.missingIcon;
  bool get isProposal => recordType == CatalogQueueRecordType.proposal;
  bool get isContribution => recordType == CatalogQueueRecordType.contribution;
  bool get canDecide => (isProposal || isContribution) && status == 'pending';

  bool get isProductIdentityContribution''', 1)
    p.write_text(s)
    for name in ['catalog_repository.dart', 'catalog_operations_repository.dart']:
        p = root / 'lib/features/catalog' / name
        s = p.read_text().replace('    String? afterId,\n', '')
        s = s.replace("if (afterId == null) 'offset': '$offset' else 'afterId': afterId", "'offset': '$offset'")
        if name == 'catalog_repository.dart':
            s = s.replace("return _items(response.jsonObject['data']);", "return _items(response.jsonObject['data'], queue: queue);", 1)
            s = s.replace("return _items(response.jsonObject['data']);", "return _items(response.jsonObject['data'], queue: 'contributions');", 1)
            s = s.replace('static List<CatalogQueueItem> _items(Object? data)', 'static List<CatalogQueueItem> _items(Object? data, {required String queue})')
            s = s.replace('data.cast<Map<String, Object?>>().map(CatalogQueueItem.fromJson)', 'data.cast<Map<String, Object?>>().map(\n        (row) => CatalogQueueItem.fromJson(row, queue: queue),\n      )')
        p.write_text(s)
    p = root / 'lib/features/catalog/published_category_picker.dart'
    s = p.read_text().replace('Function(String query, String afterId)', 'Function(String query, int offset)')
    s = s.replace("  final _anchors = <String>[''];\n", '')
    s = re.sub(r"\s*_anchors\s*\.\.clear\(\)\s*\.\.add\(''\);", '', s)
    s = s.replace('_anchors[_page]', '_page * 50')
    s = re.sub(r'\s*_anchors\.removeRange\(_page \+ 1, _anchors.length\);\s*_anchors.add\(_items.last.id\);', '', s)
    s = s.replace('Partial live list. Refresh to include records added behind the current page.', 'Live list. Refresh after catalog changes to restart paging.')
    p.write_text(s)
    p = root / 'lib/features/catalog/catalog_page.dart'
    s = p.read_text().replace("  final _pageAnchors = <String>[''];\n", '')
    s = re.sub(r"\s*_pageAnchors\s*\.\.clear\(\)\s*\.\.add\(''\);", '', s)
    s = re.sub(r'\s*_pageAnchors\.removeRange\(\s*_offset ~/ 50 \+ 1,\s*_pageAnchors.length,\s*\);\s*_pageAnchors.add\(_items.last.id\);', '', s)
    s = s.replace('    if (focusId != null) {\n    }\n', '')
    s = s.replace('afterId: _pageAnchors[offset ~/ 50]', 'offset: offset')
    s = s.replace('          _pageAnchors.add(items.last.id);\n', '')
    s = s.replace('loadPage: (query, afterId)', 'loadPage: (query, offset)').replace('afterId: afterId', 'offset: offset')
    s = s.replace('child: OutlinedButton.icon(\n              icon: const Icon(Icons.edit_note)', "child: FilledButton.icon(\n              key: const Key('manage-catalog-entities'),\n              icon: const Icon(Icons.edit_note)", 1)
    s = s.replace("child: Text('Icons')", "child: Text('Products needing icons')")
    s = s.replace('if (item == null || _mutating || _loading) return;\n    final epoch = widget.session.authorizationEpoch;\n    final lane = _lane;', '''if (item == null || _mutating || _loading || !widget.canReview ||
        !item.canDecide ||
        (_lane == _CatalogLane.proposals && !item.isProposal) ||
        (_lane == _CatalogLane.contributions && !item.isContribution)) return;
    final epoch = widget.session.authorizationEpoch;
    final lane = _lane;''', 1)
    s = s.replace('                                onPublishImage: _publishImage,', '                                onPublishImage: _publishImage,\n                                onManageIcon: _manageIcon,\n                                onOpenOperations: _openOperations,')
    s = s.replace("  var _queue = 'proposals';", "  var _queue = 'proposals';\n  CatalogOperationsSection? _operationsSection;")
    s = s.replace('CatalogOperationsPage(\n', 'CatalogOperationsPage(\n                    key: ValueKey(_operationsSection),\n                    initialSection: _operationsSection,\n', 1)
    pos = s.index('  Future<void> _loadPreview()')
    s = s[:pos] + '''  void _openOperations() {
    final item = _selected;
    if (item == null || _loading || _mutating ||
        (item.recordType == CatalogQueueRecordType.merge
            ? !widget.canCurate : !widget.canReview)) return;
    _clearPreview();
    setState(() {
      _operationsSection = item.recordType == CatalogQueueRecordType.merge
          ? CatalogOperationsSection.merges
          : CatalogOperationsSection.conflicts;
      _lane = _CatalogLane.operations;
      _selected = null;
    });
    unawaited(_load());
  }

  Future<void> _manageIcon() async {
    final item = _selected;
    if (item == null || !item.isMissingIcon || !widget.canCurate ||
        _loading || _mutating) return;
    final epoch = widget.session.authorizationEpoch;
    setState(() => _mutating = true);
    final operations = CatalogOperationsRepository(widget.api);
    try {
      // Product revision and icon revision are different concurrency tokens.
      final product = await operations.product(item.id);
      if (!_isAuthorized(epoch)) return;
      final command = await showCatalogIconEditor(context: context, product: product);
      if (command == null || !_isAuthorized(epoch)) return;
      await operations.putIcon(command);
      if (_isAuthorized(epoch)) await _load();
    } on Object catch (error) {
      if (!_isAuthorized(epoch)) return;
      _snack(error is CatalogOperationsFailure ? error.safeMessage
          : 'The icon result could not be confirmed. Reload its current state before retrying.');
      await _load();
    } finally {
      if (_isAuthorized(epoch)) setState(() => _mutating = false);
    }
  }

''' + s[pos:]
    s = s.replace('    required this.onPublishImage,\n    super.key,', '    required this.onPublishImage,\n    this.onManageIcon,\n    this.onOpenOperations,\n    super.key,', 1)
    s = s.replace('  final VoidCallback onPublishImage;', '  final VoidCallback onPublishImage;\n  final VoidCallback? onManageIcon;\n  final VoidCallback? onOpenOperations;')
    s = s.replace("        if (canReview && item.status == 'pending')", "        if (canReview && item.canDecide)")
    anchor = '        if (storePriceContribution && storePrice != null) ...<Widget>['
    addition = '''        if (item.isMissingIcon) ...<Widget>[
          const Text('This product is already published. It needs an icon, not proposal approval. '
              'Review submitted images separately in Contributions.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('manage-missing-product-icon'),
            onPressed: canCurate ? onManageIcon : null,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add / manage icon'),
          ),
        ],
        if (item.recordType == CatalogQueueRecordType.conflict ||
            item.recordType == CatalogQueueRecordType.merge) ...<Widget>[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: (item.recordType == CatalogQueueRecordType.merge
                ? canCurate : canReview) ? onOpenOperations : null,
            child: Text(item.recordType == CatalogQueueRecordType.merge
                ? 'Open reversible merges' : 'Open conflict resolution'),
          ),
        ],
'''
    s = s.replace(anchor, addition + anchor)
    s = s.replace("      : 'The moderation operation was rejected (HTTP ${error.statusCode}).';", "      : error.statusCode == 404\n      ? 'The selected moderation record is no longer available. Reload the queue and select its current record.'\n      : 'The moderation operation was rejected (HTTP ${error.statusCode}). Reload the queue before retrying.';")
    p.write_text(s)
    p = root / 'lib/features/catalog/catalog_operations_page.dart'
    s = p.read_text().replace('_OperationsSection', 'CatalogOperationsSection')
    s = s.replace('    this.operationsPort,', '    this.operationsPort,\n    this.initialSection,')
    s = s.replace('  final CatalogOperationsPort? operationsPort;', '  final CatalogOperationsPort? operationsPort;\n  final CatalogOperationsSection? initialSection;')
    s = s.replace('    _section = widget.canCurate', '    _section = widget.initialSection ?? (widget.canCurate')
    s = s.replace(': CatalogOperationsSection.conflicts;\n    if', ': CatalogOperationsSection.conflicts);\n    if (!widget.canCurate && _section != CatalogOperationsSection.conflicts) {\n      _section = CatalogOperationsSection.conflicts;\n    }\n    if', 1)
    s = s.replace("  final _conflictAnchors = <String>[''];\n", '').replace("  final _mergeAnchors = <String>[''];\n", '')
    s = re.sub(r"\s*_(?:conflict|merge)Anchors\s*\.\.clear\(\)\s*\.\.add\(''\);", '', s)
    s = s.replace('    final anchors = merges ? _mergeAnchors : _conflictAnchors;\n', '')
    s = re.sub(r'      if \(forward\) {\s*anchors.removeRange\(page \+ 1, anchors.length\);\s*anchors.add\(merges \? _mergeEvents.last.id : _conflicts.last.id\);\s*}\n', '', s)
    s = s.replace('loadPage: (query, afterId)', 'loadPage: (query, offset)').replace('afterId: afterId', 'offset: offset')
    s = s.replace('afterId: _conflictAnchors[_conflictPage]', 'offset: _conflictPage * 50').replace('afterId: _mergeAnchors[_mergePage]', 'offset: _mergePage * 50')
    s = s.replace('final command = await showDialog<CatalogIconCommand>(\n      context: context,\n      builder: (_) => _CatalogIconDialog(product: product),\n    );', 'final command = await showCatalogIconEditor(context: context, product: product);')
    s = s.replace('final class _CatalogIconDialog', '''Future<CatalogIconCommand?> showCatalogIconEditor({
  required BuildContext context,
  required CatalogProductDetail product,
}) => showDialog<CatalogIconCommand>(
  context: context,
  builder: (_) => _CatalogIconDialog(product: product),
);

final class _CatalogIconDialog''', 1)
    p.write_text(s)

(root / 'test/features/handover_workbench_test.dart').write_text('''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/features/catalog/catalog_models.dart';
import 'package:providentia_admin/features/catalog/catalog_page.dart';
import 'package:providentia_admin/features/catalog/catalog_repository.dart';
import 'package:providentia_admin/features/catalog/published_category_picker.dart';

import '../support/fake_api.dart';

String id(int n) => '0198f4e1-7abc-7def-8abc-${n.toRadixString(16).padLeft(12, '0')}';
Map<String, Object?> icon(int n) => {
  'targetType': 'product', 'targetId': id(n),
  'canonicalName': 'Repeated product name', 'revision': 7,
};

void main() {
  test('missing-icon products retain target identity and cannot be approved', () {
    final item = CatalogQueueItem.fromJson(icon(1), queue: 'icons');
    expect(item.id, id(1));
    expect(item.recordType, CatalogQueueRecordType.missingIcon);
    expect(item.status, 'Missing icon');
    expect(item.canDecide, isFalse);
    expect(item.isProposal, isFalse);
    expect(item.isContribution, isFalse);
    expect(item.revision, 7);
  });

  test('malformed icons fail closed instead of inventing actionable identities', () {
    for (final row in <Map<String, Object?>>[
      {...icon(1)}..remove('targetId'),
      {...icon(1), 'targetId': 'unknown'},
      {...icon(1), 'targetType': 'proposal'},
      {...icon(1), 'revision': 0},
      {...icon(1), 'canonicalName': ''},
    ]) {
      expect(() => CatalogQueueItem.fromJson(row, queue: 'icons'), throwsFormatException);
    }
  });

  test('conflicts, merges and proposals retain distinct action boundaries', () {
    for (final queue in ['duplicates', 'aliases', 'barcodes']) {
      final item = CatalogQueueItem.fromJson({
        'id': id(1), 'proposalId': id(2), 'proposalType': 'product',
        'conflictType': 'duplicate', 'status': 'open', 'revision': 3,
      }, queue: queue);
      expect(item.id, id(1));
      expect(item.recordType, CatalogQueueRecordType.conflict);
      expect(item.canDecide, isFalse);
    }
    final merge = CatalogQueueItem.fromJson({
      'id': id(3), 'survivorId': id(4), 'status': 'applied', 'revision': 2,
    }, queue: 'merges');
    expect(merge.recordType, CatalogQueueRecordType.merge);
    expect(merge.canDecide, isFalse);
    final proposal = CatalogQueueItem.fromJson({
      'id': id(5), 'proposalType': 'category', 'moderationStatus': 'pending',
      'revision': 1, 'payload': {'canonicalName': 'Food'},
    }, queue: 'proposals');
    expect(proposal.canDecide, isTrue);
    expect(proposal.title, 'Food');
  });

  test('101 same-name icons page by supported offset without repeating page one', () async {
    final api = FakeApi((request) async {
      expect(request.method, 'GET');
      expect(request.path, '/api/v1/catalog-admin/workbench');
      expect(request.query!.containsKey('afterId'), isFalse);
      final start = int.parse(request.query!['offset']!);
      return jsonResponse({'data': [
        for (var n = start; n < start + 50 && n < 101; n++) icon(n + 1),
      ]});
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
  });

  testWidgets('icons offer only icon management, never a proposal decision', (tester) async {
    var managed = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CatalogModerationDetail(
      item: CatalogQueueItem.fromJson(icon(1), queue: 'icons'),
      isContribution: false, canReview: true, canCurate: true, preview: null,
      onDecision: (_) => fail('Product must never be sent to proposal decisions'),
      onPreview: () {}, onLinkProposal: () {}, onPublishImage: () {},
      onManageIcon: () => managed++,
    ))));
    expect(find.byKey(const Key('approve-moderation-item')), findsNothing);
    expect(find.byKey(const Key('reject-moderation-item')), findsNothing);
    final action = find.byKey(const Key('manage-missing-product-icon'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    expect(managed, 1);
  });

  testWidgets('category picker sends offsets across page and search changes', (tester) async {
    final offsets = <int>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => showPublishedCategoryPicker(
        context: context,
        loadPage: (query, offset) async {
          offsets.add(offset);
          return [for (var n = 0; n < 50; n++) PublishedCategory.fromJson({
            'id': id(offset + n + 1), 'canonicalName': 'Category ${offset + n + 1}', 'revision': 1,
          })];
        },
      ), child: const Text('Open categories')),
    ))));
    await tester.tap(find.text('Open categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next category page'));
    await tester.pumpAndSettle();
    expect(offsets, [0, 50]);
    expect(find.text('Category 51'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous category page'));
    await tester.pumpAndSettle();
    expect(offsets, [0, 50, 0]);
    await tester.enterText(find.byKey(const Key('category-search-query')), 'new');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(offsets.last, 0);
  });
}
''')
(root / 'docs/handover-implementation.md').write_text('''# Handover implementation record — 22 September 2026

## Scope and baseline

This branch implements the supplied owner handover in the existing architecture.
The source baseline was admin `f8d189a99f9e824840994b9595d4c06779d40a09`,
backend `544b789a44f64c50ed5274e46c8050fdee881180`, and client
`e491419f7c1d3694303f4277204385bd4bca21e8`. The historical Admin button branch
had no changes ahead of main. Production executables and owner databases were
not supplied; source and CI results do not establish deployment or recovery.

## Catalog workbench

The workbench now distinguishes proposals, consent-bound contributions,
missing-icon products, identity conflicts, and merge history. Product targets
in the Icons queue are already published products, not pending proposals. They
retain their real target IDs and cannot invoke proposal decisions. The queue
is labelled **Products needing icons** and opens the existing icon editor only
after fetching the current product and icon revision. Actual submitted-image
review remains separate and retains its no-store, bounded, digest-verified
preview and explicit approved-revision publication path.

Workbench, contribution, category, conflict and merge lists use the backend's
existing offset contract. No client-only cursor or invented unknown identity
is sent. Selection is reset when the queue changes, and old asynchronous
responses remain guarded by request generation and authorization epoch.

The **Manage catalog entities** entry uses the existing primary filled theme.
This does not change who can review or curate catalog records.

## Verification and remaining work

`test/features/handover_workbench_test.dart` covers 101 same-name icon targets,
empty and later pages, typed action boundaries, malformed targets, icon-only
actions and category page navigation. The existing image-publication and
privacy tests remain applicable. Test results belong to the exact reported CI
head; this document does not claim unrun checks passed.

The other handover workstreams — historical synchronization recovery,
provenance/order/diagnostics, relationship repair, effective household
projections, unified categories and publication, household name/measurement
customization, contextual reasons and complete integrated delivery — are not
claimed complete by this initial change.
''')
print('Catalog action and pagination edits applied; run unchanged quality gates.')
