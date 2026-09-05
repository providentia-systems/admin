import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/operator_authorization.dart';
import '../access/access_groups_page.dart';
import '../access/access_repository.dart';

/// Paged operator projection. The backend authorizes every collection read.
final class OperatorRecordsPage extends StatefulWidget {
  const OperatorRecordsPage({
    required this.api,
    required this.authorization,
    this.audit = false,
    super.key,
  });
  final AdminApi api;
  final OperatorAuthorization authorization;
  final bool audit;
  @override
  State<OperatorRecordsPage> createState() => _OperatorRecordsPageState();
}

class _OperatorRecordsPageState extends State<OperatorRecordsPage> {
  final _search = TextEditingController();
  Record? _home;
  var _collection = 'products';
  var _offset = 0;
  var _generation = 0;
  var _busy = true;
  String? _error;
  List<Record> _rows = <Record>[];
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = widget.audit
          ? '/api/v1/admin/audit-events'
          : _home == null
          ? '/api/v1/admin/homes'
          : '/api/v1/admin/homes/${_home!['id']}/records/$_collection';
      final response = await widget.api.get(
        path,
        query: <String, String>{
          'offset': '$_offset',
          if (_home == null && !widget.audit) 'search': _search.text.trim(),
        },
      );
      if (mounted && generation == _generation) {
        setState(() {
          _rows = records(response.jsonObject);
          _busy = false;
        });
      }
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _rows = <Record>[];
          _busy = false;
          _error = error is ApiException
              ? error.message
              : 'The records could not be loaded.';
        });
      }
    }
  }

  Future<void> _open(Record home) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = (await widget.api.get(
        '/api/v1/admin/homes/${home['id']}',
      )).jsonObject;
      if (!mounted) return;
      setState(() {
        _home = result;
        _offset = 0;
      });
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is ApiException
              ? error.message
              : 'This home could not be opened.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = <String>{
      for (final row in _rows) ...row.keys,
    }.where((key) => key != 'home_id').toList();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (_home != null)
                IconButton(
                  tooltip: 'All homes',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _home = null;
                            _offset = 0;
                          });
                          unawaited(_load());
                        },
                ),
              Expanded(
                child: Text(
                  widget.audit
                      ? 'Audit history'
                      : _home == null
                      ? 'Homes'
                      : '${_home!['name']}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'Reload',
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (!widget.audit && _home == null)
            TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: 'Search homes',
                suffixIcon: IconButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _offset = 0;
                          unawaited(_load());
                        },
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) {
                _offset = 0;
                unawaited(_load());
              },
            ),
          if (_home != null) ...<Widget>[
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  'Group: ${objectMap(_home!['access'])['groupName'] ?? 'Unassigned'}',
                ),
                if (widget.authorization.has('homes.assign'))
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final changed = await showGroupAssignment(
                              context,
                              widget.api,
                              'home',
                              '${_home!['id']}',
                            );
                            if (changed && mounted) await _open(_home!);
                          },
                    child: const Text('Change group'),
                  ),
                DropdownButton<String>(
                  value: _collection,
                  items: <DropdownMenuItem<String>>[
                    for (final collection in <String>[
                      'products',
                      'categories',
                      'locations',
                      'stock',
                      'movements',
                      'receipts',
                      'receipt-lines',
                      'prices',
                      'shopping-lists',
                      'shopping-lines',
                      'sharing',
                      if (widget.authorization.has('people.read')) ...<String>[
                        'memberships',
                        'invitations',
                      ],
                    ])
                      DropdownMenuItem(
                        value: collection,
                        child: Text(
                          displayLabel(collection.replaceAll('-', ' ')),
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() {
                            _collection = value!;
                            _offset = 0;
                          });
                          unawaited(_load());
                        },
                ),
              ],
            ),
            if ((_home!['description'] as String? ?? '').isNotEmpty)
              Text('${_home!['description']}'),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: _rows.isEmpty
                ? const Center(child: Text('No records found.'))
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columns: <DataColumn>[
                          for (final key in keys)
                            DataColumn(label: Text(displayLabel(key))),
                        ],
                        rows: <DataRow>[
                          for (final row in _rows)
                            DataRow(
                              onSelectChanged: _home == null && !widget.audit
                                  ? (_) => _open(row)
                                  : null,
                              cells: <DataCell>[
                                for (final key in keys)
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 320,
                                      ),
                                      child: SelectableText(
                                        row[key] is Map || row[key] is List
                                            ? jsonEncode(row[key])
                                            : '${row[key] ?? ''}',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          Row(
            children: <Widget>[
              Text(
                'Showing ${_rows.isEmpty ? 0 : _offset + 1}–${_offset + _rows.length}',
              ),
              const Spacer(),
              TextButton(
                onPressed: _busy || _offset == 0
                    ? null
                    : () {
                        _offset = (_offset - 100).clamp(0, _offset);
                        unawaited(_load());
                      },
                child: const Text('Previous'),
              ),
              TextButton(
                onPressed: _busy || _rows.length < 100
                    ? null
                    : () {
                        _offset += 100;
                        unawaited(_load());
                      },
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
