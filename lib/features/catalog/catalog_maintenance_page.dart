import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import '../../core/security/secure_id.dart';
import 'catalog_maintenance_repository.dart';
import 'catalog_reason_field.dart';

class CatalogMaintenancePage extends StatefulWidget {
  const CatalogMaintenancePage({
    required this.api,
    required this.session,
    required this.canCurate,
    this.productId,
    super.key,
  });
  final AdminApi api;
  final SessionController session;
  final bool canCurate;
  final String? productId;
  @override
  State<CatalogMaintenancePage> createState() => _CatalogMaintenancePageState();
}

class _CatalogMaintenancePageState extends State<CatalogMaintenancePage> {
  late final _repository = CatalogMaintenanceRepository(widget.api);
  late String _type = widget.productId == null ? 'category' : 'product';
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _contexts = <String, ({String query, int offset, double scroll})>{};
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
    _query.dispose();
    _scroll.dispose();
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
      final rows = await _repository.list(
        _type,
        offset: _offset,
        productId: widget.productId,
        query: _query.text,
      );
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
    if (!widget.canCurate || _busy) return;
    final epoch = widget.session.authorizationEpoch;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CatalogEntityEditor(
        repository: _repository,
        session: widget.session,
        type: _type,
        productId: widget.productId,
        entity: entity,
      ),
    );
    if (_authorized(epoch)) await _load();
  }

  void _selectType(String type) {
    if (_busy || type == _type) return;
    _contexts[_type] = (
      query: _query.text,
      offset: _offset,
      scroll: _scroll.hasClients ? _scroll.offset : 0,
    );
    final previous = _contexts[type];
    setState(() {
      _type = type;
      _query.text = previous?.query ?? '';
      _offset = previous?.offset ?? 0;
    });
    unawaited(
      _load().then((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(
            (previous?.scroll ?? 0).clamp(0, _scroll.position.maxScrollExtent),
          );
        }
      }),
    );
  }

  void _search() {
    if (_busy) return;
    if (_query.text.runes.length > 191) {
      setState(() => _error = 'Search text must not exceed 191 characters.');
      return;
    }
    setState(() => _offset = 0);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.productId == null ? 'Catalog entities' : 'Product master',
      ),
    ),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'Create, edit, archive and restore catalog identities. Changes require an audit reason. Referenced packs and units retain their historical measurement meaning.',
          ),
          const SizedBox(height: 24),
          if (widget.productId == null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  ChoiceChip(
                    label: const Text('Products'),
                    selected: _type == 'product',
                    onSelected: _busy ? null : (_) => _selectType('product'),
                  ),
                  ChoiceChip(
                    label: const Text('Categories'),
                    selected: _type == 'category',
                    onSelected: _busy ? null : (_) => _selectType('category'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_type),
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Catalog entity',
                    ),
                    items: [
                      for (final type in catalogEntityFields.keys)
                        if (widget.productId == null || type != 'identity-rule')
                          DropdownMenuItem(value: type, child: Text(type)),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) _selectType(value);
                          },
                  ),
                ),
                if (widget.canCurate &&
                    (widget.productId == null ||
                        !const {'product', 'category', 'unit'}.contains(_type)))
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _edit(),
                    icon: const Icon(Icons.add),
                    label: Text('Add $_type'),
                  ),
                IconButton(
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('catalog-entity-search'),
            controller: _query,
            enabled: !_busy,
            textInputAction: TextInputAction.search,
            maxLength: 191,
            decoration: InputDecoration(
              labelText: 'Search $_type records',
              helperText:
                  'Searches all matching records, including archived identities.',
              suffixIcon: IconButton(
                onPressed: _busy ? null : _search,
                tooltip: 'Search catalog records',
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          Expanded(
            child: ListView(
              controller: _scroll,
              children: [
                for (final row in _rows)
                  ListTile(
                    key: ValueKey(row.id),
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
    this.productId,
  });
  final CatalogMaintenanceRepository repository;
  final SessionController session;
  final String type;
  final CatalogEntity? entity;
  final String? productId;
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
              'productId' => widget.productId ?? '',
              _ => '',
            },
      ),
  };
  final _reason = TextEditingController();
  final Map<String, List<CatalogEntity>> _references = {};
  late final Map<String, String> _initialFields;
  bool _allowExit = false;
  bool _confirmingExit = false;
  bool get _dirty => _fields.entries.any(
    (entry) => entry.value.text != _initialFields[entry.key],
  );

  bool _busy = false;
  bool _conflict = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _initialFields = {
      for (final entry in _fields.entries) entry.key: entry.value.text,
    };
    for (final field in _fields.values) {
      field.addListener(_fieldChanged);
    }
    widget.session.addListener(_revoke);
    unawaited(_loadReferences());
  }

  void _fieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _close() async {
    if (_busy || _confirmingExit) return;
    if (_dirty) {
      _confirmingExit = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text('Your catalog changes have not been saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard changes'),
            ),
          ],
        ),
      );
      _confirmingExit = false;
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _allowExit = true);
    Navigator.pop(context);
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
          final page = await widget.repository.list(
            type,
            offset: offset,
            productId: const {'product', 'variant', 'pack'}.contains(type)
                ? widget.productId
                : null,
          );
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
    if (_reason.text.trim().isEmpty || _reason.text.runes.length > 500) {
      setState(
        () => _error = 'Enter an audit reason of no more than 500 characters.',
      );
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
        setState(() => _allowExit = true);
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
  Widget build(BuildContext context) => PopScope(
    canPop: _allowExit || (!_busy && !_dirty),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: AlertDialog(
      title: Text(
        '${widget.entity == null ? 'Create' : 'Edit'} ${widget.type}',
      ),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom) *
                .65,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in _fields.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: entry.key.endsWith('Id')
                        ? DropdownButtonFormField<String>(
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
                            decoration: InputDecoration(
                              labelText: _label(entry.key),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('Select'),
                              ),
                              for (final row
                                  in _references[entry.key] ??
                                      <CatalogEntity>[])
                                DropdownMenuItem(
                                  value: row.id,
                                  child: Text(
                                    row.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => entry.value.text = value ?? '',
                          )
                        : TextField(
                            controller: entry.value,
                            enabled: !_busy,
                            maxLines:
                                entry.key == 'ruleDefinition' ||
                                    entry.key == 'attributesJson'
                                ? 4
                                : 1,
                            decoration: InputDecoration(
                              labelText: _label(entry.key),
                            ),
                          ),
                  ),
                const SizedBox(height: 8),
                CatalogReasonField(
                  controller: _reason,
                  creating: widget.entity == null,
                  enabled: !_busy,
                ),
                if (_error != null) Text(_error!),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _close,
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
    ),
  );
  String _label(String field) => field.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => ' ${match[0]!.toLowerCase()}',
  );
}
