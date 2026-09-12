import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import '../../core/security/secure_id.dart';
import 'operator_shopping_repository.dart';

final class OperatorShoppingEditor extends StatefulWidget {
  const OperatorShoppingEditor({
    required this.repository,
    required this.session,
    required this.homeId,
    required this.line,
    this.record,
    super.key,
  });
  final OperatorShoppingRepository repository;
  final SessionController session;
  final String homeId;
  final bool line;
  final Map<String, Object?>? record;
  @override
  State<OperatorShoppingEditor> createState() => _OperatorShoppingEditorState();
}

class _OperatorShoppingEditorState extends State<OperatorShoppingEditor> {
  late final _epoch = widget.session.authorizationEpoch;
  late final _id = widget.record?['id'] as String? ?? newUuidV4();
  late final _revision = widget.record == null
      ? 0
      : int.parse('${widget.record!['revision']}');
  late final _name = TextEditingController(
    text: '${widget.record?[widget.line ? 'description' : 'name'] ?? ''}',
  );
  late final _quantity = TextEditingController(
    text: '${widget.record?['quantity_to_buy'] ?? '1'}',
  );
  final _reason = TextEditingController();
  late String? _listId = widget.record?['shopping_list_id'] as String?;
  String? _productId;
  String _kind = 'manual';
  List<Map<String, Object?>> _lists = const [];
  List<Map<String, Object?>> _products = const [];
  bool _loading = false;
  bool _busy = false;
  bool _reloadRequired = false;
  String? _error;
  bool get _archived => widget.line
      ? (widget.record?['archived_at'] != null)
      : (widget.record?['status'] == 'archived');
  bool get _checked => widget.record?['checked_at'] != null;
  bool get _authorized =>
      mounted &&
      widget.session.phase == SessionPhase.authenticated &&
      widget.session.authorizationEpoch == _epoch &&
      widget.session.authorization.has('homes.manage');

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_authorizationChanged);
    if (widget.line && widget.record == null) unawaited(_loadOptions());
  }

  @override
  void dispose() {
    widget.session.removeListener(_authorizationChanged);
    _name.dispose();
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _authorizationChanged() {
    if (!_authorized) {
      _name.clear();
      _quantity.clear();
      _reason.clear();
      setState(() {
        _lists = [];
        _products = [];
        _listId = null;
        _productId = null;
        _error = null;
        _reloadRequired = true;
      });
    }
  }

  Future<void> _loadOptions() async {
    setState(() => _loading = true);
    try {
      final options = await Future.wait([
        widget.repository.options(widget.homeId, 'shopping-lists'),
        widget.repository.options(widget.homeId, 'products'),
      ]);
      if (!_authorized) return;
      setState(() {
        _lists = options[0].where((row) => row['status'] == 'open').toList();
        _products = options[1]
            .where((row) => row['status'] == 'active')
            .toList();
        _loading = false;
      });
    } on Object {
      if (!_authorized) return;
      setState(() {
        _loading = false;
        _reloadRequired = true;
        _error = 'Shopping choices could not be loaded. Close and reload.';
      });
    }
  }

  Future<void> _save({bool lifecycle = false, bool checking = false}) async {
    if (!_authorized || _busy || _loading || _reloadRequired) return;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Enter an audit reason.');
      return;
    }
    if (!lifecycle && !checking && _name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name or description.');
      return;
    }
    if (widget.line && _listId == null) {
      setState(() => _error = 'Choose an open shopping list.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.line) {
        final fields = <String, Object?>{};
        if (checking) {
          fields['checked'] = !_checked;
        } else if (lifecycle) {
          fields['archived'] = !_archived;
        } else {
          fields.addAll({
            'description': _name.text.trim(),
            'quantityToBuy': _quantity.text.trim(),
          });
          if (widget.record == null) {
            final parent = _lists.singleWhere((row) => row['id'] == _listId);
            fields.addAll({
              'expectedListRevision': int.parse('${parent['revision']}'),
              'homeProductId': _productId,
            });
          }
        }
        await widget.repository.saveLine(
          homeId: widget.homeId,
          listId: _listId!,
          id: _id,
          revision: _revision,
          reason: _reason.text,
          fields: fields,
          checking: checking,
        );
      } else {
        await widget.repository.saveList(
          homeId: widget.homeId,
          id: _id,
          revision: _revision,
          reason: _reason.text,
          fields: lifecycle
              ? {'status': _archived ? 'open' : 'archived'}
              : {
                  'name': _name.text.trim(),
                  if (widget.record == null) 'kind': _kind,
                },
        );
      }
      if (mounted && _authorized) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!_authorized) return;
      setState(() {
        _busy = false;
        _reloadRequired =
            error is! ApiException ||
            error.isConflict ||
            error.statusCode >= 500;
        _error = error is ApiException
            ? error.message
            : 'The save result could not be confirmed.';
        if (_reloadRequired) {
          _error = '$_error Close and reload before retrying.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_authorized) return const SizedBox.shrink();
    final enabled = !_busy && !_loading && !_reloadRequired;
    return AlertDialog(
      title: Text(
        '${widget.record == null ? 'Create' : 'Edit'} shopping ${widget.line ? 'item' : 'list'}',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.line && widget.record == null && !_loading) ...[
                DropdownButtonFormField<String>(
                  initialValue: _listId,
                  decoration: const InputDecoration(labelText: 'Shopping list'),
                  isExpanded: true,
                  items: [
                    for (final row in _lists)
                      DropdownMenuItem(
                        value: row['id']! as String,
                        child: Text('${row['name']}'),
                      ),
                  ],
                  onChanged: enabled
                      ? (value) => setState(() => _listId = value)
                      : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _productId ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Household product',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Free-text item'),
                    ),
                    for (final row in _products)
                      DropdownMenuItem(
                        value: row['id']! as String,
                        child: Text(
                          '${row['private_name'] ?? row['product_id'] ?? row['id']}',
                        ),
                      ),
                  ],
                  onChanged: enabled
                      ? (value) => setState(
                          () => _productId = value == '' ? null : value,
                        )
                      : null,
                ),
                if (_lists.isEmpty)
                  const Text(
                    'Create or restore a shopping list before adding an item.',
                  ),
              ],
              TextField(
                controller: _name,
                enabled: enabled,
                maxLength: widget.line ? 191 : 120,
                decoration: InputDecoration(
                  labelText: widget.line ? 'Description' : 'Name',
                ),
              ),
              if (widget.line)
                TextField(
                  controller: _quantity,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Quantity to buy',
                  ),
                ),
              if (!widget.line && widget.record == null)
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'List kind'),
                  items: [
                    for (final kind in ['manual', 'mixed', 'suggested'])
                      DropdownMenuItem(value: kind, child: Text(kind)),
                  ],
                  onChanged: enabled
                      ? (value) => setState(() => _kind = value!)
                      : null,
                ),
              TextField(
                controller: _reason,
                enabled: enabled,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Audit reason'),
              ),
              if (widget.record != null)
                Text('Revision $_revision${_archived ? ' · archived' : ''}'),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_loading || _busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        if (widget.line && widget.record != null && !_archived)
          OutlinedButton(
            onPressed: enabled ? () => _save(checking: true) : null,
            child: Text(_checked ? 'Uncheck' : 'Check'),
          ),
        if (widget.record != null)
          OutlinedButton(
            onPressed: enabled ? () => _save(lifecycle: true) : null,
            child: Text(_archived ? 'Restore' : 'Archive'),
          ),
        FilledButton(
          onPressed: enabled ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
