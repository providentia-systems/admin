import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import 'catalog_models.dart';
import 'catalog_operations_models.dart';
import 'catalog_operations_repository.dart';
import 'published_product_picker.dart';

enum _OperationsSection { identities, conflicts, merges }

final class CatalogOperationsPage extends StatefulWidget {
  const CatalogOperationsPage({
    required this.api,
    required this.session,
    required this.canReview,
    required this.canCurate,
    this.operationsPort,
    super.key,
  });

  final AdminApi api;
  final SessionController session;
  final bool canReview;
  final bool canCurate;
  final CatalogOperationsPort? operationsPort;

  @override
  State<CatalogOperationsPage> createState() => _CatalogOperationsPageState();
}

class _CatalogOperationsPageState extends State<CatalogOperationsPage> {
  late final CatalogOperationsPort _operations;
  late _OperationsSection _section;
  var _conflictQueue = 'duplicates';
  var _loading = false;
  String? _safeMessage;
  List<CatalogConflict> _conflicts = const <CatalogConflict>[];
  List<CatalogMergeEvent> _mergeEvents = const <CatalogMergeEvent>[];
  CatalogProductDetail? _selectedProduct;
  PublishedCategory? _selectedCategory;
  CatalogProductDetail? _survivor;
  List<CatalogProductDetail> _duplicates = const <CatalogProductDetail>[];
  CatalogMergePreview? _preview;

  @override
  void initState() {
    super.initState();
    _operations =
        widget.operationsPort ?? CatalogOperationsRepository(widget.api);
    _section = widget.canCurate
        ? _OperationsSection.identities
        : _OperationsSection.conflicts;
    if (widget.canReview) unawaited(_loadConflicts());
    if (widget.canCurate) unawaited(_loadMergeEvents());
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          SegmentedButton<_OperationsSection>(
            segments: <ButtonSegment<_OperationsSection>>[
              if (widget.canCurate)
                const ButtonSegment<_OperationsSection>(
                  value: _OperationsSection.identities,
                  icon: Icon(Icons.manage_search),
                  label: Text('Published identities'),
                ),
              if (widget.canReview)
                const ButtonSegment<_OperationsSection>(
                  value: _OperationsSection.conflicts,
                  icon: Icon(Icons.rule),
                  label: Text('Conflicts'),
                ),
              if (widget.canCurate)
                const ButtonSegment<_OperationsSection>(
                  value: _OperationsSection.merges,
                  icon: Icon(Icons.merge),
                  label: Text('Reversible merges'),
                ),
            ],
            selected: <_OperationsSection>{_section},
            onSelectionChanged: _loading
                ? null
                : (selection) => setState(() {
                    _section = selection.single;
                    _safeMessage = null;
                  }),
          ),
          const Spacer(),
          if (_loading)
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
        ],
      ),
      if (_safeMessage case final message?) ...<Widget>[
        const SizedBox(height: 8),
        MaterialBanner(
          key: const Key('catalog-operations-safe-message'),
          content: Text(message),
          actions: <Widget>[
            TextButton(onPressed: _reloadSection, child: const Text('Reload')),
          ],
        ),
      ],
      const SizedBox(height: 12),
      Expanded(
        child: switch (_section) {
          _OperationsSection.identities => _identities(),
          _OperationsSection.conflicts => _conflictWorkbench(),
          _OperationsSection.merges => _mergeWorkbench(),
        },
      ),
    ],
  );

  Widget _identities() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Canonical products',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Search published global identities and inspect the exact current revision before updating icon metadata.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('select-canonical-product'),
                  onPressed: _loading ? null : _chooseProduct,
                  icon: const Icon(Icons.search),
                  label: const Text('Search canonical products'),
                ),
                const SizedBox(height: 16),
                if (_selectedProduct case final product?) ...<Widget>[
                  Text(
                    product.canonicalName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    product.brand.isEmpty
                        ? product.category
                        : '${product.brand} • ${product.category}',
                  ),
                  const SizedBox(height: 8),
                  SelectableText('Product: ${product.id}'),
                  Text('Product revision ${product.revision}'),
                  Text('Current icon revision ${product.currentIconRevision}'),
                  if (product.redirected)
                    const Text('Resolved to the canonical redirect target.'),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    key: const Key('update-product-icon'),
                    onPressed: _loading ? null : _updateProductIcon,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      product.currentIconRevision == 0
                          ? 'Add content-addressed icon'
                          : 'Replace content-addressed icon',
                    ),
                  ),
                ] else
                  const Expanded(
                    child: Center(
                      child: Text('No canonical product is selected.'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Published categories',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Browse privacy-safe global category identities and their governance revisions.',
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const Key('browse-published-categories'),
                  onPressed: _loading ? null : _chooseCategory,
                  icon: const Icon(Icons.category_outlined),
                  label: const Text('Browse published categories'),
                ),
                const SizedBox(height: 16),
                if (_selectedCategory case final category?) ...<Widget>[
                  Text(
                    category.canonicalName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText('Category: ${category.id}'),
                  Text('Governance revision ${category.revision}'),
                ] else
                  const Expanded(
                    child: Center(
                      child: Text('No published category is selected.'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _conflictWorkbench() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          DropdownButton<String>(
            key: const Key('catalog-conflict-queue'),
            value: _conflictQueue,
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'duplicates', child: Text('Duplicates')),
              DropdownMenuItem(value: 'aliases', child: Text('Aliases')),
              DropdownMenuItem(value: 'barcodes', child: Text('Barcodes')),
            ],
            onChanged: _loading
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _conflictQueue = value);
                    unawaited(_loadConflicts());
                  },
          ),
          const Spacer(),
          IconButton.filledTonal(
            tooltip: 'Reload conflicts',
            onPressed: _loading ? null : _loadConflicts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Expanded(
        child: Card(
          child: _conflicts.isEmpty
              ? const Center(child: Text('This conflict queue is empty.'))
              : ListView.separated(
                  itemCount: _conflicts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final conflict = _conflicts[index];
                    return ListTile(
                      key: Key('catalog-conflict-${conflict.id}'),
                      leading: const Icon(Icons.compare_arrows),
                      title: Text(conflict.key),
                      subtitle: Text(
                        '${conflict.type} • revision ${conflict.revision}',
                      ),
                      trailing: FilledButton.tonal(
                        key: Key('keep-existing-${conflict.id}'),
                        onPressed: _loading
                            ? null
                            : () => _keepExisting(conflict),
                        child: const Text('Keep existing'),
                      ),
                    );
                  },
                ),
        ),
      ),
    ],
  );

  Widget _mergeWorkbench() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Expanded(
        flex: 3,
        child: Card(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Text(
                'Preview a merge',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'A non-mutating preview must be eligible and supply every current product revision before Apply is enabled.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('choose-merge-survivor'),
                onPressed: _loading ? null : _chooseSurvivor,
                icon: const Icon(Icons.looks_one_outlined),
                label: Text(
                  _survivor == null
                      ? 'Choose survivor'
                      : 'Survivor: ${_survivor!.canonicalName}',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('add-merge-duplicate'),
                onPressed: _loading ? null : _addDuplicate,
                icon: const Icon(Icons.add),
                label: const Text('Add duplicate'),
              ),
              if (_duplicates.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _duplicates
                      .map(
                        (duplicate) => InputChip(
                          label: Text(duplicate.canonicalName),
                          onDeleted: _loading
                              ? null
                              : () => setState(() {
                                  _duplicates = _duplicates
                                      .where((item) => item.id != duplicate.id)
                                      .toList(growable: false);
                                  _preview = null;
                                }),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('preview-catalog-merge'),
                onPressed: _loading || _survivor == null || _duplicates.isEmpty
                    ? null
                    : _previewMerge,
                icon: const Icon(Icons.preview_outlined),
                label: const Text('Preview merge impact'),
              ),
              if (_preview case final preview?) ...<Widget>[
                const Divider(height: 32),
                Text(
                  preview.eligible ? 'Eligible preview' : 'Blocked preview',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final entry in preview.affectedCounts.entries)
                  Text('${entry.key}: ${entry.value}'),
                if (preview.conflicts.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  for (final conflict in preview.conflicts)
                    Text('Conflict: $conflict'),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('apply-catalog-merge'),
                  onPressed: _loading || !preview.eligible ? null : _applyMerge,
                  icon: const Icon(Icons.merge),
                  label: const Text('Apply this exact preview'),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        flex: 2,
        child: Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    Text(
                      'Merge history',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Reload merge history',
                      onPressed: _loading ? null : _loadMergeEvents,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _mergeEvents.isEmpty
                    ? const Center(child: Text('No merge events found.'))
                    : ListView.separated(
                        itemCount: _mergeEvents.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final event = _mergeEvents[index];
                          return ListTile(
                            key: Key('catalog-merge-${event.id}'),
                            title: Text(
                              '${event.duplicateIds.length} duplicate(s)',
                            ),
                            subtitle: Text(
                              '${event.status} • revision ${event.revision}',
                            ),
                            trailing: event.status == 'applied'
                                ? IconButton(
                                    key: Key(
                                      'reverse-catalog-merge-${event.id}',
                                    ),
                                    tooltip: 'Reverse merge',
                                    onPressed: _loading
                                        ? null
                                        : () => _reverseMerge(event),
                                    icon: const Icon(Icons.undo),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Future<void> _chooseProduct() async {
    final product = await showPublishedProductPicker(
      context: context,
      operations: _operations,
    );
    if (mounted && product != null) setState(() => _selectedProduct = product);
  }

  Future<void> _chooseCategory() async {
    final category = await showDialog<PublishedCategory>(
      context: context,
      builder: (_) => _PublishedCategoryPicker(operations: _operations),
    );
    if (mounted && category != null) {
      setState(() => _selectedCategory = category);
    }
  }

  Future<void> _updateProductIcon() async {
    final product = _selectedProduct;
    if (product == null) return;
    final command = await showDialog<CatalogIconCommand>(
      context: context,
      builder: (_) => _CatalogIconDialog(product: product),
    );
    if (command == null) return;
    final epoch = widget.session.authorizationEpoch;
    _begin();
    try {
      await _operations.putIcon(command);
      final refreshed = await _operations.product(product.id);
      if (_authorized(epoch)) {
        setState(() {
          _selectedProduct = refreshed;
          _loading = false;
        });
      }
    } on CatalogOperationsFailure catch (failure) {
      if (_authorized(epoch)) _fail(failure.safeMessage);
    } on Object {
      if (_authorized(epoch)) _fail('The icon update could not be completed.');
    }
  }

  Future<void> _loadConflicts() async {
    final epoch = widget.session.authorizationEpoch;
    _begin();
    try {
      final conflicts = await _operations.conflicts(_conflictQueue);
      if (_authorized(epoch)) {
        setState(() {
          _conflicts = conflicts;
          _loading = false;
        });
      }
    } on CatalogOperationsFailure catch (failure) {
      if (_authorized(epoch)) _fail(failure.safeMessage);
    } on Object {
      if (_authorized(epoch)) _fail('Catalog conflicts could not be loaded.');
    }
  }

  Future<void> _keepExisting(CatalogConflict conflict) async {
    final reason = await _reasonDialog('Keep the existing catalog identity');
    if (reason == null) return;
    final epoch = widget.session.authorizationEpoch;
    _begin();
    try {
      await _operations.keepExisting(conflict: conflict, reason: reason);
      if (_authorized(epoch)) await _loadConflicts();
    } on CatalogOperationsFailure catch (failure) {
      if (_authorized(epoch)) {
        _fail(failure.safeMessage);
        if (failure.kind == CatalogOperationsFailureKind.conflict) {
          await _loadConflicts();
        }
      }
    } on Object {
      if (_authorized(epoch)) _fail('The conflict decision was not applied.');
    }
  }

  Future<void> _chooseSurvivor() async {
    final product = await showPublishedProductPicker(
      context: context,
      operations: _operations,
      title: 'Choose the canonical survivor',
    );
    if (!mounted || product == null) return;
    if (_duplicates.any((duplicate) => duplicate.id == product.id)) {
      _fail('The survivor cannot also be a duplicate.');
      return;
    }
    setState(() {
      _survivor = product;
      _preview = null;
    });
  }

  Future<void> _addDuplicate() async {
    if (_duplicates.length >= 20) {
      _fail('A merge preview accepts at most 20 duplicates.');
      return;
    }
    final product = await showPublishedProductPicker(
      context: context,
      operations: _operations,
      title: 'Add a duplicate product',
    );
    if (!mounted || product == null) return;
    if (_survivor?.id == product.id ||
        _duplicates.any((duplicate) => duplicate.id == product.id)) {
      _fail('Choose a distinct duplicate product.');
      return;
    }
    setState(() {
      _duplicates = <CatalogProductDetail>[..._duplicates, product];
      _preview = null;
    });
  }

  Future<void> _previewMerge() async {
    final survivor = _survivor;
    if (survivor == null || _duplicates.isEmpty) return;
    final epoch = widget.session.authorizationEpoch;
    _begin();
    try {
      final preview = await _operations.previewMerge(
        survivorId: survivor.id,
        duplicateIds: _duplicates.map((product) => product.id).toList(),
      );
      if (_authorized(epoch)) {
        setState(() {
          _preview = preview;
          _loading = false;
        });
      }
    } on CatalogOperationsFailure catch (failure) {
      if (_authorized(epoch)) _fail(failure.safeMessage);
    } on Object {
      if (_authorized(epoch)) _fail('The merge preview could not be loaded.');
    }
  }

  Future<void> _applyMerge() async {
    final preview = _preview;
    if (preview == null || !preview.eligible) return;
    final reason = await _reasonDialog('Apply catalog merge');
    if (reason == null) return;
    final epoch = widget.session.authorizationEpoch;
    _begin();
    try {
      await _operations.applyMerge(preview: preview, reason: reason);
      if (!_authorized(epoch)) return;
      setState(() {
        _preview = null;
        _survivor = null;
        _duplicates = const <CatalogProductDetail>[];
        _loading = false;
      });
      await _loadMergeEvents();
    } on CatalogOperationsFailure catch (failure) {
      if (_authorized(epoch)) {
        _preview = null;
        _fail(failure.safeMessage);
      }
    } on Object {
      if (_authorized(epoch)) _fail('The catalog merge was not applied.');
    }
  }

  Future<void> _loadMergeEvents() async {
    final epoch = widget.session.authorizationEpoch;
    _begin();
    try {
      final events = await _operations.mergeEvents();
      if (_authorized(epoch)) {
        setState(() {
          _mergeEvents = events;
          _loading = false;
        });
      }
    } on CatalogOperationsFailure catch (failure) {
      if (_authorized(epoch)) _fail(failure.safeMessage);
    } on Object {
      if (_authorized(epoch)) _fail('Merge history could not be loaded.');
    }
  }

  Future<void> _reverseMerge(CatalogMergeEvent event) async {
    final reason = await _reasonDialog('Reverse catalog merge');
    if (reason == null) return;
    final epoch = widget.session.authorizationEpoch;
    _begin();
    try {
      await _operations.reverseMerge(event: event, reason: reason);
      if (_authorized(epoch)) await _loadMergeEvents();
    } on CatalogOperationsFailure catch (failure) {
      if (_authorized(epoch)) {
        _fail(failure.safeMessage);
        if (failure.kind == CatalogOperationsFailureKind.conflict) {
          await _loadMergeEvents();
        }
      }
    } on Object {
      if (_authorized(epoch)) _fail('The merge reversal was not applied.');
    }
  }

  Future<String?> _reasonDialog(String title) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('catalog-operation-reason'),
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Auditable reason'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-catalog-operation'),
            onPressed: () {
              final cleaned = controller.text.trim();
              if (cleaned.isNotEmpty) Navigator.pop(context, cleaned);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }

  void _reloadSection() {
    switch (_section) {
      case _OperationsSection.identities:
        setState(() => _safeMessage = null);
      case _OperationsSection.conflicts:
        unawaited(_loadConflicts());
      case _OperationsSection.merges:
        unawaited(_loadMergeEvents());
    }
  }

  void _begin() => setState(() {
    _loading = true;
    _safeMessage = null;
  });

  void _fail(String message) => setState(() {
    _loading = false;
    _safeMessage = message;
  });

  bool _authorized(int epoch) =>
      mounted &&
      widget.session.phase == SessionPhase.authenticated &&
      widget.session.authorizationEpoch == epoch;
}

final class _PublishedCategoryPicker extends StatefulWidget {
  const _PublishedCategoryPicker({required this.operations});

  final CatalogOperationsPort operations;

  @override
  State<_PublishedCategoryPicker> createState() =>
      _PublishedCategoryPickerState();
}

class _PublishedCategoryPickerState extends State<_PublishedCategoryPicker> {
  final _query = TextEditingController();
  List<PublishedCategory>? _categories;
  String? _safeMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Published categories'),
    content: SizedBox(
      width: 620,
      height: 460,
      child: Column(
        children: <Widget>[
          TextField(
            key: const Key('category-search-query'),
            controller: _query,
            decoration: const InputDecoration(
              labelText: 'Canonical category name',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (_) => _load(),
          ),
          if (_safeMessage case final message?) Text(message),
          const SizedBox(height: 8),
          Expanded(
            child: _categories == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: _categories!.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final category = _categories![index];
                      return ListTile(
                        key: Key('published-category-${category.id}'),
                        title: Text(category.canonicalName),
                        subtitle: Text('Revision ${category.revision}'),
                        onTap: () => Navigator.pop(context, category),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );

  Future<void> _load() async {
    setState(() {
      _categories = null;
      _safeMessage = null;
    });
    try {
      final categories = await widget.operations.searchCategories(_query.text);
      if (mounted) setState(() => _categories = categories);
    } on CatalogOperationsFailure catch (failure) {
      if (mounted) {
        setState(() {
          _categories = const <PublishedCategory>[];
          _safeMessage = failure.safeMessage;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _categories = const <PublishedCategory>[];
          _safeMessage = 'Published categories could not be loaded safely.';
        });
      }
    }
  }
}

final class _CatalogIconDialog extends StatefulWidget {
  const _CatalogIconDialog({required this.product});

  final CatalogProductDetail product;

  @override
  State<_CatalogIconDialog> createState() => _CatalogIconDialogState();
}

class _CatalogIconDialogState extends State<_CatalogIconDialog> {
  final _digest = TextEditingController();
  final _altText = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _byteSize = TextEditingController();
  final _provenance = TextEditingController();
  var _mediaType = 'image/webp';
  String? _validation;

  @override
  void dispose() {
    _digest.dispose();
    _altText.dispose();
    _width.dispose();
    _height.dispose();
    _byteSize.dispose();
    _provenance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Update icon for ${widget.product.canonicalName}'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Text(
              'Expected current icon revision: '
              '${widget.product.currentIconRevision}',
            ),
            TextField(
              key: const Key('icon-asset-digest'),
              controller: _digest,
              maxLength: 64,
              decoration: const InputDecoration(
                labelText: 'Lowercase SHA-256 asset digest',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _mediaType,
              decoration: const InputDecoration(labelText: 'Media type'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'image/webp', child: Text('WebP')),
                DropdownMenuItem(value: 'image/png', child: Text('PNG')),
                DropdownMenuItem(value: 'image/svg+xml', child: Text('SVG')),
              ],
              onChanged: (value) => _mediaType = value ?? _mediaType,
            ),
            TextField(
              controller: _altText,
              maxLength: 191,
              decoration: const InputDecoration(labelText: 'Alt text'),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _width,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Width'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _height,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Height'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _byteSize,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Byte size'),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _provenance,
              maxLength: 191,
              decoration: const InputDecoration(labelText: 'Provenance'),
            ),
            if (_validation case final message?)
              Text(message, key: const Key('icon-command-validation')),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('confirm-icon-command'),
        onPressed: _confirm,
        child: const Text('Update icon metadata'),
      ),
    ],
  );

  void _confirm() {
    try {
      final command = CatalogIconCommand(
        targetType: CatalogIconTargetType.product,
        targetId: widget.product.id,
        assetDigest: _digest.text.trim(),
        mediaType: _mediaType,
        altText: _altText.text.trim(),
        width: int.parse(_width.text.trim()),
        height: int.parse(_height.text.trim()),
        byteSize: int.parse(_byteSize.text.trim()),
        provenance: _provenance.text.trim(),
        expectedRevision: widget.product.currentIconRevision,
      );
      Navigator.pop(context, command);
    } on Object {
      setState(() {
        _validation =
            'Check the digest, dimensions, size and descriptive text.';
      });
    }
  }
}
