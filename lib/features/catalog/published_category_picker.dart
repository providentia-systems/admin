import 'dart:async';
import 'package:flutter/material.dart';
import 'catalog_models.dart';

typedef CategoryPageLoader =
    Future<List<PublishedCategory>> Function(String query, int offset);

Future<PublishedCategory?> showPublishedCategoryPicker({
  required BuildContext context,
  required CategoryPageLoader loadPage,
}) => showDialog<PublishedCategory>(
  context: context,
  builder: (_) => _CategoryPicker(loadPage: loadPage),
);

final class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({required this.loadPage});
  final CategoryPageLoader loadPage;
  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  final _query = TextEditingController();
  var _page = 0;
  var _generation = 0;
  var _loading = false;
  String? _error;
  List<PublishedCategory> _items = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({bool restart = false}) async {
    if (restart) {
      _page = 0;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _items = const [];
    });
    try {
      final items = await widget.loadPage(_query.text.trim(), _page * 50);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Categories could not be read safely. Retry the page.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Select published category'),
    content: SizedBox(
      width: 620,
      height: 460,
      child: Column(
        children: <Widget>[
          TextField(
            key: const Key('category-search-query'),
            controller: _query,
            decoration: const InputDecoration(
              labelText: 'Search categories',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: (_) => _load(restart: true),
          ),
          const Text(
            'Live list. Refresh after catalog changes to restart paging.',
          ),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Previous category page',
                onPressed: _loading || _page == 0
                    ? null
                    : () {
                        _page--;
                        unawaited(_load());
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page ${_page + 1}'),
              IconButton(
                tooltip: 'Next category page',
                onPressed: _loading || _items.length < 50
                    ? null
                    : () {
                        _page++;
                        unawaited(_load());
                      },
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: _loading ? null : () => _load(restart: true),
                child: const Text('Refresh'),
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          Expanded(
            child: _error != null
                ? Center(
                    child: TextButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return ListTile(
                        key: Key('published-category-${item.id}'),
                        title: Text(item.canonicalName),
                        subtitle: Text('Revision ${item.revision}'),
                        onTap: _loading
                            ? null
                            : () => Navigator.pop(context, item),
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
}
