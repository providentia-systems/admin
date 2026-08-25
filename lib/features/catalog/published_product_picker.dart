import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog_operations_models.dart';
import 'catalog_operations_repository.dart';

Future<CatalogProductDetail?> showPublishedProductPicker({
  required BuildContext context,
  required CatalogOperationsPort operations,
  String title = 'Select a published product',
}) => showDialog<CatalogProductDetail>(
  context: context,
  builder: (_) =>
      PublishedProductPickerDialog(operations: operations, title: title),
);

final class PublishedProductPickerDialog extends StatefulWidget {
  const PublishedProductPickerDialog({
    required this.operations,
    required this.title,
    super.key,
  });

  final CatalogOperationsPort operations;
  final String title;

  @override
  State<PublishedProductPickerDialog> createState() =>
      _PublishedProductPickerDialogState();
}

class _PublishedProductPickerDialogState
    extends State<PublishedProductPickerDialog> {
  final _query = TextEditingController();
  PublishedProductPage? _page;
  CatalogProductDetail? _selected;
  var _loading = true;
  var _generation = 0;
  var _offset = 0;
  String? _safeMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _generation += 1;
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 880,
      height: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('product-search-query'),
                  controller: _query,
                  enabled: !_loading,
                  decoration: const InputDecoration(
                    labelText: 'Canonical name, brand, category or pack',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) {
                    _offset = 0;
                    unawaited(_search());
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('product-search-submit'),
                tooltip: 'Search published products',
                onPressed: _loading
                    ? null
                    : () {
                        _offset = 0;
                        unawaited(_search());
                      },
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_safeMessage case final message?) ...<Widget>[
            const SizedBox(height: 8),
            Text(message, key: const Key('product-search-safe-message')),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text(
                _page == null
                    ? 'No page loaded'
                    : 'Results ${_page!.offset + 1}-'
                          '${_page!.offset + _page!.data.length}',
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Previous product page',
                onPressed: _loading || _offset == 0
                    ? null
                    : () {
                        _offset = (_offset - (_page?.limit ?? 50)).clamp(
                          0,
                          _offset,
                        );
                        unawaited(_search());
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next product page',
                onPressed: _loading || !(_page?.hasNext ?? false)
                    ? null
                    : () {
                        _offset += _page!.limit;
                        unawaited(_search());
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Card(
                    child: _page == null || _page!.data.isEmpty
                        ? const Center(child: Text('No products found.'))
                        : ListView.separated(
                            itemCount: _page!.data.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final product = _page!.data[index];
                              return ListTile(
                                key: Key('published-product-${product.id}'),
                                selected: _selected?.id == product.id,
                                title: Text(product.canonicalName),
                                subtitle: Text(
                                  <String>[
                                    if (product.brand.isNotEmpty) product.brand,
                                    product.category,
                                    ?product.packText,
                                  ].join(' • '),
                                ),
                                onTap: _loading ? null : () => _select(product),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    child: _selected == null
                        ? const Center(
                            child: Text('Select a product to load details.'),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  _selected!.canonicalName,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _selected!.brand.isEmpty
                                      ? _selected!.category
                                      : '${_selected!.brand} • ${_selected!.category}',
                                ),
                                const SizedBox(height: 8),
                                SelectableText('Product: ${_selected!.id}'),
                                Text('Revision ${_selected!.revision}'),
                                Text(
                                  'Current icon revision '
                                  '${_selected!.currentIconRevision}',
                                ),
                                if (_selected!.redirected) ...<Widget>[
                                  const SizedBox(height: 12),
                                  const Text(
                                    'The requested product redirects to this canonical identity.',
                                  ),
                                ],
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('choose-published-product'),
        onPressed: _loading || _selected == null
            ? null
            : () => Navigator.pop(context, _selected),
        child: const Text('Choose canonical product'),
      ),
    ],
  );

  Future<void> _search() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _safeMessage = null;
      _selected = null;
    });
    try {
      final page = await widget.operations.searchProducts(
        query: _query.text,
        limit: 50,
        offset: _offset,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } on CatalogOperationsFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _safeMessage = failure.safeMessage;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _safeMessage = 'Published products could not be loaded safely.';
      });
    }
  }

  Future<void> _select(PublishedProduct product) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _safeMessage = null;
    });
    try {
      final detail = await widget.operations.product(product.id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _selected = detail;
        _loading = false;
      });
    } on CatalogOperationsFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _safeMessage = failure.safeMessage;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _safeMessage = 'The product detail could not be loaded safely.';
      });
    }
  }
}
