import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import '../../core/security/secure_id.dart';
import 'catalog_maintenance_repository.dart';

class CatalogMaintenancePage extends StatefulWidget {
  const CatalogMaintenancePage({
    required this.api,
    required this.session,
    required this.canCurate,
    super.key,
  });
  final AdminApi api;
  final SessionController session;
  final bool canCurate;
  @override
  State<CatalogMaintenancePage> createState() => _CatalogMaintenancePageState();
}

class _CatalogMaintenancePageState extends State<CatalogMaintenancePage> {
  late final _repository = CatalogMaintenanceRepository(widget.api);
  String _type = 'category';
  int _offset = 0;
  int _request = 0;
  List<CatalogEntity> _rows = const [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_authorizationChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.session.removeListener(_authorizationChanged);
    super.dispose();
  }

  void _authorizationChanged() {
    if (widget.session.phase != SessionPhase.authenticated) {
      ++_request;
      setState(() {
        _rows = const [];
        _error = null;
      });
    }
  }

  bool _authorized(int epoch) =>
      mounted &&
      widget.session.phase == SessionPhase.authenticated &&
      widget.session.authorizationEpoch == epoch;
  Future<void> _load() async {
    final epoch = widget.session.authorizationEpoch;
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _rows = const [];
    });
    try {
      final rows = await _repository.list(_type, offset: _offset);
      if (!_authorized(epoch) || request != _request) return;
      setState(() {
        _rows = rows;
        _busy = false;
      });
    } catch (_) {
      if (!_authorized(epoch) || request != _request) return;
      setState(() {
        _error = 'Catalog entities could not be loaded.';
        _busy = false;
      });
    }
  }

  Future<void> _edit([CatalogEntity? entity]) async {
    final epoch = widget.session.authorizationEpoch;
    await showDialog<void>(
      context: context,
      builder: (_) => _CatalogEntityEditor(
        repository: _repository,
        session: widget.session,
        type: _type,
        entity: entity,
      ),
    );
    if (_authorized(epoch)) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Catalog entities')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'Create, edit, archive and restore catalog identities. Changes require an audit reason. Referenced packs and units retain their historical measurement meaning.',
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: _type,
                  isExpanded: true,
                  items: [
                    for (final type in catalogEntityFields.keys)
                      DropdownMenuItem(value: type, child: Text(type)),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _type = value;
                            _offset = 0;
                          });
                          unawaited(_load());
                        },
                ),
              ),
              if (widget.canCurate)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Create'),
                ),
              IconButton(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          Expanded(
            child: ListView(
              children: [
                for (final row in _rows)
                  ListTile(
                    title: Text(row.label),
                    subtitle: Text('${row.status} · revision ${row.revision}'),
                    onTap: widget.canCurate ? () => _edit(row) : null,
                    trailing: widget.canCurate
                        ? const Icon(Icons.edit_outlined)
                        : null,
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _busy || _offset == 0
                    ? null
                    : () {
                        _offset -= 100;
                        unawaited(_load());
                      },
                child: const Text('Previous'),
              ),
              Text('Page ${_offset ~/ 100 + 1}'),
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
    ),
  );
}

class _CatalogEntityEditor extends StatefulWidget {
  const _CatalogEntityEditor({
    required this.repository,
    required this.session,
    required this.type,
    this.entity,
  });
  final CatalogMaintenanceRepository repository;
  final SessionController session;
  final String type;
  final CatalogEntity? entity;
  @override
  State<_CatalogEntityEditor> createState() => _CatalogEntityEditorState();
}

class _CatalogEntityEditorState extends State<_CatalogEntityEditor> {
  late final String _id = widget.entity?.id ?? newUuidV4();
  late final _fields = {
    for (final field in catalogEntityFields[widget.type]!)
      field: TextEditingController(
        text:
            widget.entity?.fields[field] ??
            switch (field) {
              'multiplicity' || 'baseFactor' => '1',
              'attributesJson' => '{}',
              'barcodeType' => 'other',
              _ => '',
            },
      ),
  };
  final _reason = TextEditingController();
  final Map<String, List<CatalogEntity>> _references = {};
  bool _busy = false;
  bool _conflict = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_revoke);
    unawaited(_loadReferences());
  }

  void _revoke() {
    if (widget.session.phase != SessionPhase.authenticated) {
      for (final field in _fields.values) {
        field.clear();
      }
      _reason.clear();
      setState(() {
        _references.clear();
        _busy = true;
      });
    }
  }

  Future<void> _loadReferences() async {
    final epoch = widget.session.authorizationEpoch;
    for (final field in _fields.keys.where((key) => key.endsWith('Id'))) {
      final type = field.substring(0, field.length - 2);
      final rows = <CatalogEntity>[];
      for (var offset = 0; offset < 10000; offset += 100) {
        try {
          final page = await widget.repository.list(type, offset: offset);
          if (!mounted ||
              widget.session.authorizationEpoch != epoch ||
              widget.session.phase != SessionPhase.authenticated) {
            return;
          }
          rows.addAll(
            page.where(
              (row) =>
                  row.status == 'published' || row.id == _fields[field]!.text,
            ),
          );
          if (page.length < 100) break;
        } catch (_) {
          if (mounted) {
            setState(
              () => _error =
                  'Reference choices could not be loaded. Close and retry.',
            );
          }
          return;
        }
      }
      if (mounted) setState(() => _references[field] = rows);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_revoke);
    for (final field in _fields.values) {
      field.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save(String status) async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Enter an audit reason.');
      return;
    }
    final epoch = widget.session.authorizationEpoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.save(
        type: widget.type,
        id: _id,
        revision: widget.entity?.revision ?? 0,
        status: status,
        reason: _reason.text.trim(),
        fields: {
          for (final entry in _fields.entries)
            entry.key:
                catalogNullableFields.contains(entry.key) &&
                    entry.value.text.trim().isEmpty
                ? null
                : entry.value.text.trim(),
        },
      );
      if (mounted &&
          widget.session.phase == SessionPhase.authenticated &&
          widget.session.authorizationEpoch == epoch) {
        Navigator.pop(context);
      }
    } on ApiException catch (error) {
      if (!mounted || widget.session.authorizationEpoch != epoch) return;
      setState(() {
        _busy = false;
        _conflict = error.isConflict;
        _error = error.isConflict
            ? 'The revision changed, this identity exists, or it remains in use. Close and refresh before retrying.'
            : 'The catalog change was rejected. Check the fields and your access.';
      });
    } catch (_) {
      if (!mounted || widget.session.authorizationEpoch != epoch) return;
      setState(() {
        _busy = false;
        _conflict = true;
        _error = 'The outcome is uncertain. Close and refresh before retrying.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.entity == null ? 'Create' : 'Edit'} ${widget.type}'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in _fields.entries)
              if (entry.key.endsWith('Id'))
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    '${entry.key}-${_references[entry.key]?.length}',
                  ),
                  initialValue:
                      _references[entry.key]?.any(
                            (row) => row.id == entry.value.text,
                          ) ==
                          true
                      ? entry.value.text
                      : '',
                  isExpanded: true,
                  decoration: InputDecoration(labelText: _label(entry.key)),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Select')),
                    for (final row
                        in _references[entry.key] ?? <CatalogEntity>[])
                      DropdownMenuItem(
                        value: row.id,
                        child: Text(row.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => entry.value.text = value ?? '',
                )
              else
                TextField(
                  controller: entry.value,
                  enabled: !_busy,
                  maxLines:
                      entry.key == 'ruleDefinition' ||
                          entry.key == 'attributesJson'
                      ? 4
                      : 1,
                  decoration: InputDecoration(labelText: _label(entry.key)),
                ),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Audit reason'),
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      if (widget.entity != null && widget.entity!.status != 'archived')
        TextButton(
          onPressed: _busy || _conflict ? null : () => _save('archived'),
          child: const Text('Archive'),
        ),
      FilledButton(
        onPressed: _busy || _conflict ? null : () => _save('published'),
        child: Text(widget.entity?.status == 'archived' ? 'Restore' : 'Save'),
      ),
    ],
  );
  String _label(String field) => field.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => ' ${match[0]!.toLowerCase()}',
  );
}
