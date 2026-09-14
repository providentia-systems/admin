import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import 'catalog_maintenance_page.dart';
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
  var _contributionStatus = 'pending';
  var _offset = 0;
  var _loadGeneration = 0;
  var _mutating = false;
  String? _returnContributionId;
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
        if (widget.canReview || widget.canCurate)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.edit_note),
              label: const Text('Manage catalog entities'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => CatalogMaintenancePage(
                    api: widget.api,
                    session: widget.session,
                    canCurate: widget.canCurate,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
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
              onSelectionChanged: _mutating
                  ? null
                  : (selection) {
                      _clearPreview();
                      setState(() {
                        _lane = selection.single;
                        _offset = 0;
                        _returnContributionId = null;
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
                onChanged: _mutating
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _queue = value;
                          _offset = 0;
                          _selected = null;
                        });
                        unawaited(_load());
                      },
              ),
            if (_lane == _CatalogLane.contributions)
              DropdownButton<String>(
                key: const Key('contribution-status'),
                value: _contributionStatus,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'pending',
                    child: Text('Pending review'),
                  ),
                  DropdownMenuItem(
                    value: 'approved',
                    child: Text('Approved / publication'),
                  ),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  DropdownMenuItem(
                    value: 'withdrawn',
                    child: Text('Withdrawn'),
                  ),
                ],
                onChanged: _mutating
                    ? null
                    : (value) {
                        if (value == null) return;
                        _clearPreview();
                        setState(() {
                          _contributionStatus = value;
                          _offset = 0;
                          _selected = null;
                        });
                        unawaited(_load());
                      },
              ),
            if (_lane != _CatalogLane.operations) ...<Widget>[
              IconButton(
                tooltip: 'Previous moderation page',
                onPressed: _loading || _mutating || _offset == 0
                    ? null
                    : () {
                        _offset -= 50;
                        _selected = null;
                        unawaited(_load());
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page ${_offset ~/ 50 + 1}'),
              IconButton(
                tooltip: 'Next moderation page',
                onPressed: _loading || _mutating || _items.length < 50
                    ? null
                    : () {
                        _offset += 50;
                        _selected = null;
                        unawaited(_load());
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
            if (_lane != _CatalogLane.operations)
              IconButton.filledTonal(
                tooltip: 'Refresh moderation queue',
                onPressed: _loading || _mutating ? null : () => _load(),
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_lane != _CatalogLane.operations && _hasError)
          MaterialBanner(
            content: const Text('The moderation queue could not be loaded.'),
            actions: <Widget>[
              TextButton(onPressed: () => _load(), child: const Text('Retry')),
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
                                    onTap: _loading || _mutating
                                        ? null
                                        : () {
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
                                canReview:
                                    widget.canReview && !_loading && !_mutating,
                                canCurate:
                                    widget.canCurate && !_loading && !_mutating,
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

  Future<void> _load({String? focusId}) async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final epoch = widget.session.authorizationEpoch;
    final lane = _lane;
    final status = _contributionStatus;
    final queue = _queue;
    final selectedId = focusId ?? _selected?.id;
    var offset = focusId == null ? _offset : 0;
    _clearPreview();
    setState(() {
      _selected = null;
      _items = const <CatalogQueueItem>[];
      _loading = lane != _CatalogLane.operations;
      _hasError = false;
    });
    if (lane == _CatalogLane.operations) return;
    bool current() => _isAuthorized(epoch) && generation == _loadGeneration;
    try {
      while (current()) {
        final items = lane == _CatalogLane.proposals
            ? await _repository.workbench(queue: queue, offset: offset)
            : await _repository.contributionReview(
                status: status,
                offset: offset,
              );
        if (!current()) return;
        final selected = items
            .where((item) => item.id == selectedId)
            .firstOrNull;
        // A just-approved item may not be on the first approved page. Seek it
        // using the existing bounded queue operation, never a private source.
        if (focusId != null && selected == null && items.length == 50) {
          offset += 50;
          continue;
        }
        setState(() {
          _items = items;
          _selected = selected;
          _offset = offset;
          _loading = false;
        });
        return;
      }
    } on Object {
      if (!current()) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _decide(bool approve) async {
    final item = _selected;
    if (item == null || _mutating || _loading) return;
    final epoch = widget.session.authorizationEpoch;
    final lane = _lane;
    if (approve && lane == _CatalogLane.proposals && !widget.canCurate) return;
    setState(() => _mutating = true);
    try {
      final reason = await _textDialog(
        title: approve
            ? (lane == _CatalogLane.proposals
                  ? 'Approve and publish proposal'
                  : 'Approve contribution')
            : 'Reject item',
        label: 'Auditable moderation reason',
      );
      if (!_isAuthorized(epoch) || reason == null || reason.isEmpty) return;
      if (lane == _CatalogLane.proposals) {
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
      if (!_isAuthorized(epoch)) return;
      if (lane == _CatalogLane.contributions) {
        _contributionStatus = approve ? 'approved' : 'rejected';
        await _load(focusId: item.id);
      } else if (_returnContributionId case final String contributionId) {
        _lane = _CatalogLane.contributions;
        _contributionStatus = 'approved';
        _returnContributionId = null;
        await _load(focusId: contributionId);
      } else {
        await _load();
      }
    } on Object catch (error) {
      if (!_isAuthorized(epoch)) return;
      _snack(
        error is ApiException
            ? _safeApiMessage(error)
            : 'The result could not be confirmed. Reload the current revision before retrying.',
      );
      // No automatic mutation retry: a lost response may already have committed.
      if (lane == _CatalogLane.contributions && approve) {
        _contributionStatus = 'approved';
      }
      await _load(focusId: item.id);
    } finally {
      if (_isAuthorized(epoch)) setState(() => _mutating = false);
    }
  }

  Future<void> _loadPreview() async {
    final item = _selected;
    if (item == null || _mutating || _loading) return;
    final epoch = widget.session.authorizationEpoch;
    final generation = _loadGeneration;
    try {
      final preview = await _repository.imagePreview(
        item.id,
        expectedRevision: item.revision,
      );
      if (!_isAuthorized(epoch) ||
          generation != _loadGeneration ||
          _selected?.id != item.id ||
          _selected?.revision != item.revision) {
        preview.dispose();
        return;
      }
      _clearPreview();
      setState(() => _preview = preview);
    } on Object {
      if (_isAuthorized(epoch)) {
        _snack(
          'The moderation preview failed safety validation. Reload the item before trying again.',
        );
      }
    }
  }

  Future<void> _linkProposal() async {
    final item = _selected;
    if (item == null || _mutating || _loading || !widget.canCurate) return;
    if (item.linkedProposalId case final String proposalId) {
      _lane = _CatalogLane.proposals;
      _queue = 'proposals';
      _returnContributionId = item.id;
      await _load(focusId: proposalId);
      return;
    }
    final epoch = widget.session.authorizationEpoch;
    setState(() => _mutating = true);
    try {
      final categories = await _repository.categories();
      if (!_isAuthorized(epoch)) return;
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
      if (category == null || !_isAuthorized(epoch)) return;
      await _repository.linkContributionProposal(
        contributionId: item.id,
        publishedCategoryId: category.id,
        expectedRevision: item.revision,
      );
      if (_isAuthorized(epoch)) await _load(focusId: item.id);
    } on Object catch (error) {
      if (!_isAuthorized(epoch)) return;
      _snack(
        error is ApiException
            ? _safeApiMessage(error)
            : 'The proposal result could not be confirmed. The current contribution was reloaded.',
      );
      await _load(focusId: item.id);
    } finally {
      if (_isAuthorized(epoch)) setState(() => _mutating = false);
    }
  }

  Future<void> _publishImage() async {
    final item = _selected;
    if (item == null ||
        _preview == null ||
        _mutating ||
        _loading ||
        !widget.canCurate) {
      return;
    }
    final epoch = widget.session.authorizationEpoch;
    setState(() => _mutating = true);
    try {
      final product = await showPublishedProductPicker(
        context: context,
        operations: CatalogOperationsRepository(widget.api),
        title: 'Choose the product for this verified image',
      );
      if (product == null || !_isAuthorized(epoch)) return;
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
      if (confirmed != true || !_isAuthorized(epoch)) return;
      await _repository.publishImage(
        contributionId: item.id,
        productId: product.id,
        expectedContributionRevision: item.revision,
        expectedIconRevision: product.currentIconRevision,
      );
      if (_isAuthorized(epoch)) await _load(focusId: item.id);
    } on Object catch (error) {
      if (!_isAuthorized(epoch)) return;
      _snack(
        error is ApiException
            ? _safeApiMessage(error)
            : 'Publication could not be confirmed. The current contribution was reloaded.',
      );
      await _load(focusId: item.id);
    } finally {
      if (_isAuthorized(epoch)) setState(() => _mutating = false);
    }
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
  }) async {
    var value = ''; // TextField owns its controller for the route lifetime.
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          onChanged: (text) => value = text,
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
            onPressed: () => Navigator.pop(context, value.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
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
        if (approvedContribution && !storePriceContribution) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            productIdentityContribution
                ? 'Contribution approved. ${item.linkedProposalId == null ? 'Not published: link a product proposal next.' : 'Linked proposal: ${item.linkedProposalStatus}. Only curator approval of that proposal publishes the product.'}'
                : item.imagePublished
                ? 'Verified image published to the selected product.'
                : 'Contribution approved, not published. Load the approved-revision preview before selecting the product.',
          ),
        ],
        const Divider(height: 32),
        if (canReview && item.status == 'pending')
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('approve-moderation-item'),
                onPressed: isContribution || canCurate
                    ? () => onDecision(true)
                    : null,
                icon: const Icon(Icons.check),
                label: Text(isContribution ? 'Approve' : 'Approve and publish'),
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
                  onPressed:
                      item.linkedProposalStatus == 'approved' ||
                          item.linkedProposalStatus == 'rejected'
                      ? null
                      : onLinkProposal,
                  child: Text(
                    item.linkedProposalId == null
                        ? 'Link product proposal'
                        : 'Review linked proposal',
                  ),
                ),
              if (imageContribution)
                FilledButton.tonal(
                  key: const Key('publish-verified-image'),
                  onPressed: preview == null || item.imagePublished
                      ? null
                      : onPublishImage,
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
