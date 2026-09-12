import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/admin_layout.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/operator_authorization.dart';
import '../../core/auth/session_controller.dart';
import '../access/access_groups_page.dart';
import '../access/access_repository.dart';
import 'operator_image.dart';
import 'operator_inventory_editor.dart';
import 'operator_inventory_repository.dart';
import 'operator_shopping_editor.dart';
import 'operator_shopping_repository.dart';
import 'operator_stock_preference_editor.dart';
import 'operator_stock_preference_repository.dart';

/// Paged operator projection. The backend authorizes every collection read.
final class OperatorRecordsPage extends StatefulWidget {
  const OperatorRecordsPage({
    required this.api,
    required this.authorization,
    required this.session,
    this.audit = false,
    super.key,
  });
  final AdminApi api;
  final OperatorAuthorization authorization;
  final SessionController session;
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
    widget.session.addListener(_authorizationChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.session.removeListener(_authorizationChanged);
    _search.dispose();
    super.dispose();
  }

  bool get _canEdit =>
      _home != null &&
      widget.session.phase == SessionPhase.authenticated &&
      widget.session.authorization.has('homes.manage') &&
      const [
        'products',
        'categories',
        'locations',
        'stores',
        'shopping-lists',
        'shopping-lines',
      ].contains(_collection);

  void _authorizationChanged() {
    if (widget.session.phase != SessionPhase.authenticated) {
      ++_generation;
      _search.clear();
      setState(() {
        _home = null;
        _rows = [];
        _error = null;
        _busy = false;
      });
    }
  }

  bool _authorized(int epoch) =>
      mounted &&
      widget.session.phase == SessionPhase.authenticated &&
      widget.session.authorizationEpoch == epoch;

  Future<void> _edit([Record? row]) async {
    if (!_canEdit) return;
    final epoch = widget.session.authorizationEpoch;
    final homeId = '${_home!['id']}';
    if (_collection == 'shopping-lists' || _collection == 'shopping-lines') {
      await showDialog<bool>(
        context: context,
        builder: (_) => OperatorShoppingEditor(
          repository: OperatorShoppingRepository(widget.api),
          session: widget.session,
          homeId: homeId,
          line: _collection == 'shopping-lines',
          record: row,
        ),
      );
      if (_authorized(epoch)) await _load();
      return;
    }
    final kind = switch (_collection) {
      'products' => OperatorInventoryKind.product,
      'categories' => OperatorInventoryKind.category,
      'locations' => OperatorInventoryKind.location,
      'stores' => OperatorInventoryKind.store,
      _ => throw StateError('Unsupported household editor.'),
    };
    try {
      await showDialog<bool>(
        context: context,
        builder: (_) => OperatorInventoryEditor(
          repository: OperatorInventoryRepository(widget.api),
          session: widget.session,
          homeId: homeId,
          kind: kind,
          record: row == null
              ? null
              : OperatorInventoryRecord.fromRow(kind, row),
        ),
      );
      if (_authorized(epoch)) await _load();
    } on Object {
      if (_authorized(epoch)) {
        setState(
          () => _error =
              'This record cannot be edited. Reload the household records.',
        );
      }
    }
  }

  Future<void> _preferences(Record row) async {
    if (!_canEdit || _collection != 'products') return;
    final epoch = widget.session.authorizationEpoch;
    final homeId = '${_home!['id']}';
    await showDialog<bool>(
      context: context,
      builder: (_) => OperatorStockPreferenceEditor(
        repository: OperatorStockPreferenceRepository(widget.api),
        session: widget.session,
        homeId: homeId,
        homeProductId: '${row['id']}',
      ),
    );
    if (_authorized(epoch)) await _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final epoch = widget.session.authorizationEpoch;
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
      if (_authorized(epoch) && generation == _generation) {
        setState(() {
          _rows = records(response.jsonObject);
          _busy = false;
        });
      }
    } on Object catch (error) {
      if (_authorized(epoch) && generation == _generation) {
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
    final epoch = widget.session.authorizationEpoch;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = (await widget.api.get(
        '/api/v1/admin/homes/${home['id']}',
      )).jsonObject;
      if (!_authorized(epoch) || generation != _generation) return;
      setState(() {
        _home = result;
        _offset = 0;
      });
      await _load();
    } on Object catch (error) {
      if (_authorized(epoch) && generation == _generation) {
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
            Align(
              alignment: Alignment.centerLeft,
              child: OperatorImage(
                api: widget.api,
                path:
                    '/api/v1/admin/homes/${Uri.encodeComponent('${_home!['id']}')}/image',
                label: 'Home image',
                placeholder: Icons.home_outlined,
              ),
            ),
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
                if (_canEdit)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _edit(),
                    icon: const Icon(Icons.add),
                    label: Text(switch (_collection) {
                      'products' => 'Create product',
                      'categories' => 'Create category',
                      'locations' => 'Create location',
                      'stores' => 'Create store',
                      'shopping-lists' => 'Create shopping list',
                      'shopping-lines' => 'Create shopping item',
                      _ => 'Create',
                    }),
                  ),
                DropdownButton<String>(
                  value: _collection,
                  items: <DropdownMenuItem<String>>[
                    for (final collection in <String>[
                      'products',
                      'categories',
                      'locations',
                      'stores',
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
                : AdminDataTableViewport(
                    child: DataTable(
                      showCheckboxColumn: false,
                      dataRowMinHeight: 48,
                      dataRowMaxHeight: double.infinity,
                      columns: <DataColumn>[
                        if (_canEdit) const DataColumn(label: Text('Edit')),
                        if (_canEdit && _collection == 'products')
                          const DataColumn(label: Text('Stock preferences')),
                        if (_home == null && !widget.audit)
                          const DataColumn(label: Text('Open')),
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
                              if (_canEdit)
                                DataCell(
                                  IconButton(
                                    tooltip: 'Edit record',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: _busy ? null : () => _edit(row),
                                  ),
                                ),
                              if (_canEdit && _collection == 'products')
                                DataCell(
                                  IconButton(
                                    tooltip: 'Stock preferences',
                                    icon: const Icon(Icons.tune),
                                    onPressed:
                                        _busy || row['status'] != 'active'
                                        ? null
                                        : () => _preferences(row),
                                  ),
                                ),
                              if (_home == null && !widget.audit)
                                DataCell(
                                  IconButton(
                                    tooltip: 'Open ${row['name']}',
                                    icon: const Icon(Icons.open_in_new),
                                    onPressed: _busy ? null : () => _open(row),
                                  ),
                                ),
                              for (final key in keys)
                                DataCell(
                                  AdminTableCell(
                                    identifier: isAdminIdentifierColumn(key),
                                    value: row[key] is Map || row[key] is List
                                        ? jsonEncode(row[key])
                                        : '${row[key] ?? ''}',
                                  ),
                                ),
                            ],
                          ),
                      ],
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
