import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import 'catalog_models.dart';
import 'catalog_operations_page.dart';
import 'catalog_operations_repository.dart';
import 'catalog_repository.dart';
import 'published_product_picker.dart';

enum _CatalogLane { proposals, contributions, operations }

final class CatalogPage extends StatefulWidget {
  const CatalogPage({
    required this.api,
    required this.session,
    required this.canReview,
    required this.canCurate,
    super.key,
  });

  final AdminApi api;
  final SessionController session;
  final bool canReview;
  final bool canCurate;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final CatalogRepository _repository;
  late _CatalogLane _lane;
  var _queue = 'proposals';
  var _loading = true;
  var _hasError = false;
  List<CatalogQueueItem> _items = const <CatalogQueueItem>[];
  CatalogQueueItem? _selected;
  ModerationPreview? _preview;

  @override
  void initState() {
    super.initState();
    _repository = CatalogRepository(widget.api);
    _lane = widget.canReview
        ? _CatalogLane.proposals
        : _CatalogLane.contributions;
    unawaited(_load());
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Global catalog moderation',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Approve consent-bound contributions and moderate attribution-free global categories and products.',
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            SegmentedButton<_CatalogLane>(
              segments: <ButtonSegment<_CatalogLane>>[
                if (widget.canReview)
                  const ButtonSegment(
                    value: _CatalogLane.proposals,
                    label: Text('Catalog workbench'),
                    icon: Icon(Icons.rule_folder_outlined),
                  ),
                const ButtonSegment(
                  value: _CatalogLane.contributions,
                  label: Text('Contributions'),
                  icon: Icon(Icons.volunteer_activism_outlined),
                ),
                const ButtonSegment(
                  value: _CatalogLane.operations,
                  label: Text('Catalog operations'),
                  icon: Icon(Icons.account_tree_outlined),
                ),
              ],
              selected: <_CatalogLane>{_lane},
              onSelectionChanged: (selection) {
                _clearPreview();
                setState(() {
                  _lane = selection.single;
                  _selected = null;
                });
                unawaited(_load());
              },
            ),
            const SizedBox(width: 16),
            if (_lane == _CatalogLane.proposals)
              DropdownButton<String>(
                value: _queue,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'proposals',
                    child: Text('Proposals'),
                  ),
                  DropdownMenuItem(
                    value: 'duplicates',
                    child: Text('Duplicates'),
                  ),
                  DropdownMenuItem(value: 'aliases', child: Text('Aliases')),
                  DropdownMenuItem(value: 'barcodes', child: Text('Barcodes')),
                  DropdownMenuItem(value: 'icons', child: Text('Icons')),
                  DropdownMenuItem(value: 'merges', child: Text('Merges')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _queue = value;
                    _selected = null;
                  });
                  unawaited(_load());
                },
              ),
            const Spacer(),
            if (_lane != _CatalogLane.operations)
              IconButton.filledTonal(
                tooltip: 'Refresh moderation queue',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_lane != _CatalogLane.operations && _hasError)
          MaterialBanner(
            content: const Text('The moderation queue could not be loaded.'),
            actions: <Widget>[
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        if (_lane != _CatalogLane.operations && _loading)
          const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Expanded(
          child: _lane == _CatalogLane.operations
              ? CatalogOperationsPage(
                  api: widget.api,
                  session: widget.session,
                  canReview: widget.canReview,
                  canCurate: widget.canCurate,
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: Card(
                        child: _items.isEmpty
                            ? const Center(child: Text('This queue is empty.'))
                            : ListView.separated(
                                itemCount: _items.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  return ListTile(
                                    selected: item.id == _selected?.id,
                                    title: Text(item.title),
                                    subtitle: Text(
                                      '${item.kind} • revision ${item.revision}',
                                    ),
                                    trailing: Chip(label: Text(item.status)),
                                    onTap: () {
                                      _clearPreview();
                                      setState(() => _selected = item);
                                    },
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: Card(
                        child: _selected == null
                            ? const Center(
                                child: Text(
                                  'Select a moderation item to review it.',
                                ),
                              )
                            : CatalogModerationDetail(
                                item: _selected!,
                                isContribution:
                                    _lane == _CatalogLane.contributions,
                                canReview: widget.canReview,
                                canCurate: widget.canCurate,
                                preview: _preview,
                                onDecision: _decide,
                                onPreview: _loadPreview,
                                onLinkProposal: _linkProposal,
                                onPublishImage: _publishImage,
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    ),
  );

  Future<void> _load() async {
    if (_lane == _CatalogLane.operations) {
      setState(() {
        _loading = false;
        _hasError = false;
      });
      return;
    }
    final epoch = widget.session.authorizationEpoch;
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final items = _lane == _CatalogLane.proposals
          ? await _repository.workbench(queue: _queue)
          : await _repository.contributionReview();
      if (!_isAuthorized(epoch)) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on Object {
      if (!_isAuthorized(epoch)) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _decide(bool approve) async {
    final item = _selected;
    if (item == null) return;
    final reason = await _textDialog(
      title: approve ? 'Approve item' : 'Reject item',
      label: 'Auditable moderation reason',
    );
    if (reason == null || reason.isEmpty) return;
    try {
      if (_lane == _CatalogLane.proposals) {
        await _repository.decideProposal(
          proposalId: item.id,
          approve: approve,
          reason: reason,
          expectedRevision: item.revision,
        );
      } else {
        await _repository.decideContribution(
          contributionId: item.id,
          approve: approve,
          reason: reason,
          expectedRevision: item.revision,
        );
      }
      _clearPreview();
      setState(() => _selected = null);
      await _load();
    } on ApiException catch (error) {
      if (mounted) _snack(_safeApiMessage(error));
      if (error.isConflict) await _load();
    }
  }

  Future<void> _loadPreview() async {
    final item = _selected;
    if (item == null) return;
    try {
      final epoch = widget.session.authorizationEpoch;
      final preview = await _repository.imagePreview(
        item.id,
        expectedRevision: item.revision,
      );
      if (!_isAuthorized(epoch) || _selected?.id != item.id) {
        preview.dispose();
        return;
      }
      _clearPreview();
      setState(() => _preview = preview);
    } on Object {
      if (mounted) _snack('The moderation preview failed safety validation.');
    }
  }

  Future<void> _linkProposal() async {
    final item = _selected;
    if (item == null) return;
    final categories = await _repository.categories();
    if (!mounted) return;
    final category = await showDialog<PublishedCategory>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select published category'),
        children: categories
            .map(
              (entry) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry),
                child: Text(entry.canonicalName),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (category == null) return;
    try {
      await _repository.linkContributionProposal(
        contributionId: item.id,
        publishedCategoryId: category.id,
        expectedRevision: item.revision,
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) _snack(_safeApiMessage(error));
      if (error.isConflict) await _load();
    }
  }

  Future<void> _publishImage() async {
    final item = _selected;
    if (item == null) return;
    final product = await showPublishedProductPicker(
      context: context,
      operations: CatalogOperationsRepository(widget.api),
      title: 'Choose the product for this verified image',
    );
    if (product == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish verified image?'),
        content: Text(
          'Publish the sanitized image to ${product.canonicalName} '
          'using contribution revision ${item.revision} and current icon '
          'revision ${product.currentIconRevision}?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-image-publication'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish image'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.publishImage(
        contributionId: item.id,
        productId: product.id,
        expectedContributionRevision: item.revision,
        expectedIconRevision: product.currentIconRevision,
      );
      _clearPreview();
      await _load();
    } on ApiException catch (error) {
      if (mounted) _snack(_safeApiMessage(error));
      if (error.isConflict) await _load();
    }
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(labelText: label),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _clearPreview() {
    _preview?.dispose();
    _preview = null;
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  bool _isAuthorized(int epoch) =>
      mounted &&
      widget.session.phase == SessionPhase.authenticated &&
      widget.session.authorizationEpoch == epoch;

  static String _safeApiMessage(ApiException error) => error.isConflict
      ? 'This item changed on the server. The queue was reloaded.'
      : 'The moderation operation was rejected (HTTP ${error.statusCode}).';
}

@visibleForTesting
final class CatalogModerationDetail extends StatelessWidget {
  const CatalogModerationDetail({
    required this.item,
    required this.isContribution,
    required this.canReview,
    required this.canCurate,
    required this.preview,
    required this.onDecision,
    required this.onPreview,
    required this.onLinkProposal,
    required this.onPublishImage,
    super.key,
  });

  final CatalogQueueItem item;
  final bool isContribution;
  final bool canReview;
  final bool canCurate;
  final ModerationPreview? preview;
  final ValueChanged<bool> onDecision;
  final VoidCallback onPreview;
  final VoidCallback onLinkProposal;
  final VoidCallback onPublishImage;

  @override
  Widget build(BuildContext context) {
    final productIdentityContribution =
        isContribution && item.isProductIdentityContribution;
    final imageContribution = isContribution && item.isProductImageContribution;
    final storePriceContribution =
        isContribution && item.isStorePriceContribution;
    final storePrice = item.storePrice;
    final approvedContribution = isContribution && item.status == 'approved';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(item.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            Chip(label: Text(item.kind)),
            Chip(label: Text(item.status)),
            Chip(label: Text('Revision ${item.revision}')),
          ],
        ),
        const SizedBox(height: 16),
        for (final entry in item.raw.entries)
          if (!_sensitiveKey(entry.key) &&
              !(entry.key == 'payload' && item.storePrice != null))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: SelectableText('${entry.key}: ${entry.value}'),
            ),
        if (storePriceContribution && storePrice != null) ...<Widget>[
          const Divider(height: 32),
          _StorePriceModerationView(price: storePrice),
        ],
        if (imageContribution) ...<Widget>[
          const Divider(height: 32),
          if (preview == null)
            OutlinedButton.icon(
              onPressed: canReview ? onPreview : null,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Load no-store verified preview'),
            )
          else ...<Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Image.memory(
                preview!.bytes,
                gaplessPlayback: false,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) =>
                    const Text('Preview cannot be decoded.'),
              ),
            ),
            const SizedBox(height: 8),
            SelectableText('SHA-256: ${preview!.sha256Digest}'),
          ],
        ],
        const Divider(height: 32),
        if (canReview && item.status == 'pending')
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('approve-moderation-item'),
                onPressed: () => onDecision(true),
                icon: const Icon(Icons.check),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                key: const Key('reject-moderation-item'),
                onPressed: () => onDecision(false),
                icon: const Icon(Icons.close),
                label: const Text('Reject'),
              ),
            ],
          ),
        if (isContribution && canCurate && !approvedContribution) ...<Widget>[
          const SizedBox(height: 12),
          const Text(
            'Curator publication actions become available only after the current contribution revision is approved.',
          ),
        ],
        if (isContribution &&
            canCurate &&
            approvedContribution &&
            (productIdentityContribution || imageContribution)) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: <Widget>[
              if (productIdentityContribution)
                OutlinedButton(
                  key: const Key('link-product-proposal'),
                  onPressed: onLinkProposal,
                  child: const Text('Link product proposal'),
                ),
              if (imageContribution)
                FilledButton.tonal(
                  key: const Key('publish-verified-image'),
                  onPressed: preview == null ? null : onPublishImage,
                  child: const Text('Publish verified image'),
                ),
            ],
          ),
        ],
        if (storePriceContribution &&
            canCurate &&
            approvedContribution) ...<Widget>[
          const SizedBox(height: 12),
          const Text(
            'This approved store-price fact is published by the consent-bound '
            'contribution feed. It does not create a product proposal or '
            'replace a product image.',
            key: Key('store-price-publication-boundary'),
          ),
        ],
      ],
    );
  }

  static bool _sensitiveKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('credential') ||
        normalized.contains('homeid') ||
        normalized.contains('userid') ||
        normalized.contains('providerreference');
  }
}

final class _StorePriceModerationView extends StatelessWidget {
  const _StorePriceModerationView({required this.price});

  final StorePriceModeration price;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Store-price moderation details',
    child: Column(
      key: const Key('store-price-moderation-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Shared store-price fact',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SelectableText('Store: ${price.storeName}'),
        SelectableText('Location: ${price.storeLocation ?? 'Not supplied'}'),
        SelectableText('Price: ${price.currency} ${price.price}'),
        SelectableText('Observed on: ${price.observedOn}'),
        SelectableText('Product ID: ${price.productId}'),
        SelectableText('Pack ID: ${price.packId}'),
      ],
    ),
  );
}
