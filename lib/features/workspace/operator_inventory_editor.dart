import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import '../../core/security/secure_id.dart';
import 'operator_inventory_repository.dart';

final class OperatorInventoryEditor extends StatefulWidget {
  const OperatorInventoryEditor({
    required this.repository,
    required this.session,
    required this.homeId,
    required this.kind,
    this.record,
    super.key,
  });
  final OperatorInventoryRepository repository;
  final SessionController session;
  final String homeId;
  final OperatorInventoryKind kind;
  final OperatorInventoryRecord? record;
  @override
  State<OperatorInventoryEditor> createState() =>
      _OperatorInventoryEditorState();
}

class _OperatorInventoryEditorState extends State<OperatorInventoryEditor> {
  late final _id = widget.record?.id ?? newUuidV4();
  late final _epoch = widget.session.authorizationEpoch;
  late final _name = TextEditingController(text: widget.record?.name ?? '');
  late final _pack = TextEditingController(text: widget.record?.packText ?? '');
  late String? _category = widget.record?.homeCategoryId;
  final _reason = TextEditingController();
  late final _storeLocation = TextEditingController(
    text: widget.record?.storeLocation ?? '',
  );
  late String _locationKind = widget.record?.locationKind ?? 'other';
  List<OperatorInventoryRecord> _categories = const [];
  bool _loading = false;
  bool _busy = false;
  bool _reloadRequired = false;
  String? _error;
  bool get _product => widget.kind == OperatorInventoryKind.product;
  bool get _catalog => widget.record?.catalogBacked ?? false;
  bool get _authorized =>
      mounted &&
      widget.session.phase == SessionPhase.authenticated &&
      widget.session.authorizationEpoch == _epoch &&
      widget.session.authorization.has('homes.manage');

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_authorizationChanged);
    if (_product) unawaited(_loadCategories());
  }

  @override
  void dispose() {
    widget.session.removeListener(_authorizationChanged);
    _name.dispose();
    _pack.dispose();
    _reason.dispose();
    _storeLocation.dispose();
    super.dispose();
  }

  void _authorizationChanged() {
    if (!_authorized) {
      _name.clear();
      _pack.clear();
      _reason.clear();
      _storeLocation.clear();
      setState(() {
        _categories = const [];
        _category = null;
        _error = null;
        _reloadRequired = true;
      });
    }
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);
    try {
      final categories = await widget.repository.categories(widget.homeId);
      if (!_authorized) return;
      setState(() {
        _categories = categories;
        _loading = false;
      });
    } on Object {
      if (!_authorized) return;
      setState(() {
        _error =
            'Household categories could not be loaded. Close and reload before editing.';
        _loading = false;
        _reloadRequired = true;
      });
    }
  }

  Future<void> _save({String? status}) async {
    if (!_authorized || _busy || _reloadRequired) return;
    final statusOnly = status != null;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Enter an audit reason.');
      return;
    }
    if (!statusOnly && !_catalog && _name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_product) {
        await widget.repository.saveProduct(
          homeId: widget.homeId,
          id: _id,
          expectedRevision: widget.record?.revision ?? 0,
          reason: _reason.text,
          editMetadata: !statusOnly,
          catalogBacked: _catalog,
          privateName: _name.text.trim(),
          packText: _pack.text.trim().isEmpty ? null : _pack.text.trim(),
          homeCategoryId: _category,
          status: status,
        );
      } else if (widget.kind == OperatorInventoryKind.location) {
        await widget.repository.saveLocation(
          homeId: widget.homeId,
          id: _id,
          expectedRevision: widget.record?.revision ?? 0,
          reason: _reason.text,
          name: statusOnly ? null : _name.text.trim(),
          kind: statusOnly ? null : _locationKind,
          status: status,
        );
      } else if (widget.kind == OperatorInventoryKind.store) {
        await widget.repository.saveStore(
          homeId: widget.homeId,
          id: _id,
          expectedRevision: widget.record?.revision ?? 0,
          reason: _reason.text,
          name: statusOnly ? null : _name.text.trim(),
          location: statusOnly ? null : _storeLocation.text.trim(),
          status: status,
        );
      } else {
        await widget.repository.saveCategory(
          homeId: widget.homeId,
          id: _id,
          expectedRevision: widget.record?.revision ?? 0,
          reason: _reason.text,
          name: statusOnly ? null : _name.text.trim(),
          status: status,
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
    final label = widget.kind.name;
    return AlertDialog(
      title: Text(
        '${widget.record == null ? 'Create' : 'Edit'} household $label',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_catalog)
                const Text(
                  'Catalog identity is maintained in Catalog. You can change this household category or archive this household product.',
                ),
              if (!_catalog)
                TextField(
                  controller: _name,
                  enabled: enabled,
                  maxLength: widget.kind == OperatorInventoryKind.location
                      ? 120
                      : 191,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              if (_product && !_catalog)
                TextField(
                  controller: _pack,
                  enabled: enabled,
                  maxLength: 191,
                  decoration: const InputDecoration(
                    labelText: 'Pack or measure',
                  ),
                ),
              if (widget.kind == OperatorInventoryKind.location)
                DropdownButtonFormField<String>(
                  initialValue: _locationKind,
                  decoration: const InputDecoration(labelText: 'Location kind'),
                  items: [
                    for (final kind in [
                      'pantry',
                      'shelf',
                      'fridge',
                      'freezer',
                      'household',
                      'other',
                    ])
                      DropdownMenuItem(value: kind, child: Text(kind)),
                  ],
                  onChanged: enabled
                      ? (value) => setState(() => _locationKind = value!)
                      : null,
                ),
              if (widget.kind == OperatorInventoryKind.store)
                TextField(
                  controller: _storeLocation,
                  enabled: enabled,
                  maxLength: 191,
                  decoration: const InputDecoration(
                    labelText: 'Store location',
                  ),
                ),
              if (_loading) const LinearProgressIndicator(),
              if (_product && !_loading)
                DropdownButtonFormField<String>(
                  initialValue: _category ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Household category',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('No category'),
                    ),
                    for (final category in _categories)
                      if (category.status == 'active' ||
                          category.id == _category)
                        DropdownMenuItem(
                          value: category.id,
                          child: Text(
                            '${category.name}${category.status == 'archived' ? ' (archived)' : ''}',
                          ),
                        ),
                    if (_category != null &&
                        !_categories.any(
                          (category) => category.id == _category,
                        ))
                      DropdownMenuItem(
                        value: _category,
                        child: const Text('Unavailable category'),
                      ),
                  ],
                  onChanged: enabled
                      ? (value) => setState(
                          () => _category = value == '' ? null : value,
                        )
                      : null,
                ),
              TextField(
                controller: _reason,
                enabled: enabled,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Audit reason'),
              ),
              if (widget.record != null)
                Text(
                  'Revision ${widget.record!.revision} · ${widget.record!.status}',
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        if (widget.record != null)
          OutlinedButton(
            onPressed: enabled
                ? () => _save(
                    status: widget.record!.status == 'archived'
                        ? 'active'
                        : 'archived',
                  )
                : null,
            child: Text(
              widget.record!.status == 'archived' ? 'Restore' : 'Archive',
            ),
          ),
        FilledButton(
          onPressed: enabled ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
