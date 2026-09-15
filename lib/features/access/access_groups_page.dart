import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/admin_layout.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import 'access_repository.dart';

final class AccessGroupsPage extends StatefulWidget {
  const AccessGroupsPage({required this.api, this.session, super.key});
  final AdminApi api;
  final SessionController? session;
  @override
  State<AccessGroupsPage> createState() => _AccessGroupsPageState();
}

class _AccessGroupsPageState extends State<AccessGroupsPage> {
  late final _repository = AccessRepository(widget.api);
  var _scope = 'home';
  var _loading = true;
  String? _error;
  List<Record> _groups = <Record>[];
  List<Record> _catalog = <Record>[];
  var _generation = 0;
  var _revoked = false;

  @override
  void initState() {
    super.initState();
    widget.session?.addListener(_authorizationChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.session?.removeListener(_authorizationChanged);
    super.dispose();
  }

  bool _authorized(int? epoch) =>
      mounted &&
      !_revoked &&
      (widget.session == null ||
          (widget.session!.phase == SessionPhase.authenticated &&
              widget.session!.authorizationEpoch == epoch));

  void _authorizationChanged() {
    if (widget.session?.phase != SessionPhase.authenticated ||
        widget.session?.authorization.has('groups.manage') == false) {
      _purge();
    }
  }

  void _purge() {
    if (!mounted) return;
    ++_generation;
    setState(() {
      _revoked = true;
      _groups = [];
      _catalog = [];
      _error = null;
    });
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _load() async {
    if (_revoked) return;
    final epoch = widget.session?.authorizationEpoch;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait(<Future<List<Record>>>[
        _repository.groups(_scope),
        _repository.catalog(),
      ]);
      if (!_authorized(epoch) || generation != _generation) return;
      setState(() {
        _groups = values[0];
        _catalog = values[1];
        _loading = false;
      });
    } on Object catch (error) {
      if (error is ApiException &&
          (error.isUnauthorized || error.isForbidden)) {
        _purge();
        return;
      }
      if (!_authorized(epoch) || generation != _generation) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Groups could not be loaded.';
        _loading = false;
      });
    }
  }

  Future<void> _edit([Record? group]) async {
    final epoch = widget.session?.authorizationEpoch;
    final definition = _catalog.firstWhere((value) => value['scope'] == _scope);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) {
        final editor = GroupEditor(
          repository: _repository,
          scope: _scope,
          definition: definition,
          group: group,
        );
        final session = widget.session;
        return session == null
            ? editor
            : AnimatedBuilder(
                animation: session,
                builder: (_, _) =>
                    _authorized(epoch) ? editor : const SizedBox.shrink(),
              );
      },
    );
    if (saved == true && _authorized(epoch)) await _load();
  }

  Future<void> _remove(Record group) async {
    final epoch = widget.session?.authorizationEpoch;
    final reason = await confirmAdministrativeRemoval(
      context,
      label: '${group['name']}',
      session: widget.session,
      detail:
          'Only unused custom groups can be removed. Built-in groups, assignments and country defaults are protected. The audit history is retained.',
    );
    if (reason == null || !_authorized(epoch)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repository.remove(group, reason);
      if (_authorized(epoch)) await _load();
    } on Object catch (error) {
      if (error is ApiException &&
          (error.isUnauthorized || error.isForbidden)) {
        _purge();
        return;
      }
      if (!_authorized(epoch)) return;
      await _load();
      if (!_authorized(epoch)) return;
      setState(
        () => _error = error is ApiException
            ? error.message
            : 'The group could not be removed. Reload before trying again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => _revoked
      ? const Center(
          child: Text(
            'Access to this page changed. Refresh your permissions to continue.',
          ),
        )
      : Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Access groups',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Each account, home and administrator has one group in its scope. Existing records remain when allowances are lowered.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SegmentedButton<String>(
                    segments: const <ButtonSegment<String>>[
                      ButtonSegment(value: 'account', label: Text('Accounts')),
                      ButtonSegment(value: 'home', label: Text('Homes')),
                      ButtonSegment(
                        value: 'admin',
                        label: Text('Administrators'),
                      ),
                    ],
                    selected: <String>{_scope},
                    onSelectionChanged: (value) {
                      setState(() {
                        _scope = value.single;
                        _groups = <Record>[];
                      });
                      unawaited(_load());
                    },
                  ),
                  FilledButton.icon(
                    onPressed: _loading || _error != null
                        ? null
                        : () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Create group'),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Reload groups',
                  ),
                ],
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Expanded(
                child: ListView(
                  children: <Widget>[
                    for (final group in _groups)
                      ListTile(
                        title: Text('${group['name']}'),
                        subtitle: Text('${group['description'] ?? ''}'),
                        trailing: group['protected'] == true
                            ? const Icon(Icons.lock_outline)
                            : IconButton(
                                tooltip: 'Remove group',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _loading
                                    ? null
                                    : () => _remove(group),
                              ),
                        onTap: () => _edit(group),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
}

final class GroupEditor extends StatefulWidget {
  const GroupEditor({
    required this.repository,
    required this.scope,
    required this.definition,
    this.group,
    super.key,
  });
  final AccessRepository repository;
  final String scope;
  final Record definition;
  final Record? group;
  @override
  State<GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<GroupEditor> {
  late Record? _group = widget.group;
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: '${_group?['name'] ?? ''}');
  late final _description = TextEditingController(
    text: '${_group?['description'] ?? ''}',
  );
  late final _features = objectMap(_group?['features']);
  late final Map<String, TextEditingController> _limits =
      <String, TextEditingController>{
        for (final key in widget.definition['limits']! as List)
          '$key': TextEditingController(
            text: '${objectMap(_group?['limits'])[key] ?? 0}',
          ),
      };
  late final Set<String> _delegable =
      (_group?['delegablePermissions'] as List? ?? <Object?>[])
          .cast<String>()
          .toSet();
  late final Map<String, Set<String>> _roles = <String, Set<String>>{
    for (final role in <String>['manager', 'member', 'viewer'])
      role:
          (objectMap(_group?['rolePermissions'])[role] as List? ?? <Object?>[])
              .cast<String>()
              .toSet(),
  };
  bool get _readOnly => _group?['protected'] == true;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    for (final controller in _limits.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.save(<String, Object?>{
        ...?_group,
        'scope': widget.scope,
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'features': _features,
        'limits': <String, int>{
          for (final entry in _limits.entries)
            entry.key: int.parse(entry.value.text),
        },
        'delegablePermissions': widget.scope == 'home'
            ? _delegable.toList()
            : <String>[],
        'rolePermissions': widget.scope == 'home'
            ? <String, List<String>>{
                for (final entry in _roles.entries)
                  entry.key: entry.value.toList(),
              }
            : <String, Object?>{},
      });
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (error is ApiException && error.isConflict && _group != null) {
        try {
          final groups = await widget.repository.groups(widget.scope);
          final current = groups
              .where((value) => value['id'] == _group!['id'])
              .firstOrNull;
          if (current != null && mounted) {
            _group = current;
            _name.text = '${current['name']}';
            _description.text = '${current['description'] ?? ''}';
            _features
              ..clear()
              ..addAll(objectMap(current['features']));
            for (final entry in _limits.entries) {
              entry.value.text =
                  '${objectMap(current['limits'])[entry.key] ?? 0}';
            }
            _delegable
              ..clear()
              ..addAll(
                (current['delegablePermissions'] as List? ?? <Object?>[])
                    .cast<String>(),
              );
            for (final entry in _roles.entries) {
              entry.value
                ..clear()
                ..addAll(
                  (objectMap(current['rolePermissions'])[entry.key] as List? ??
                          <Object?>[])
                      .cast<String>(),
                );
            }
          }
        } on Object {
          // The conflict is still shown; the caller can close and reload.
        }
      }
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is ApiException
              ? error.message
              : 'The group could not be saved.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _readOnly
          ? 'System owner permissions'
          : _group == null
          ? 'Create ${widget.scope} group'
          : 'Edit ${_group!['name']}',
    ),
    content: SizedBox(
      width: 760,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: AdminFormFields(
            children: <Widget>[
              TextFormField(
                controller: _name,
                enabled: !_readOnly && !_saving,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Group name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a name.'
                    : null,
              ),
              TextFormField(
                controller: _description,
                enabled: !_readOnly && !_saving,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const Text('Features'),
              for (final rawKey in widget.definition['features']! as List)
                CheckboxListTile(
                  title: Text(displayLabel('$rawKey')),
                  value: _features[rawKey] == true,
                  onChanged: _readOnly || _saving
                      ? null
                      : (enabled) => setState(
                          () => _features['$rawKey'] = enabled == true,
                        ),
                ),
              if (_limits.isNotEmpty) ...<Widget>[
                const Divider(),
                const Text(
                  'Allowances — enter -1 for unlimited; 0 prevents additions.',
                ),
                for (final entry in _limits.entries)
                  TextFormField(
                    controller: entry.value,
                    enabled: !_readOnly && !_saving,
                    decoration: InputDecoration(
                      labelText: displayLabel(entry.key),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    validator: (value) {
                      final number = int.tryParse(value ?? '');
                      return number == null || number < -1
                          ? 'Use -1 or a nonnegative whole number.'
                          : null;
                    },
                  ),
              ],
              if (widget.scope == 'home') ...<Widget>[
                const Divider(),
                const Text(
                  'Homeowner control and inherited role defaults. The home group always caps access.',
                ),
                for (final rawKey in widget.definition['features']! as List)
                  ExpansionTile(
                    title: Text(displayLabel('$rawKey')),
                    children: <Widget>[
                      CheckboxListTile(
                        title: const Text(
                          'Homeowner may change this permission',
                        ),
                        value: _delegable.contains(rawKey),
                        onChanged: _readOnly || _saving
                            ? null
                            : (value) => setState(() {
                                value == true
                                    ? _delegable.add('$rawKey')
                                    : _delegable.remove(rawKey);
                              }),
                      ),
                      for (final entry in _roles.entries)
                        CheckboxListTile(
                          title: Text('Default for ${entry.key}'),
                          value: entry.value.contains(rawKey),
                          onChanged: _readOnly || _saving
                              ? null
                              : (value) => setState(() {
                                  value == true
                                      ? entry.value.add('$rawKey')
                                      : entry.value.remove(rawKey);
                                }),
                        ),
                    ],
                  ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      if (!_readOnly)
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save group'),
        ),
    ],
  );
}

Future<bool> showGroupAssignment(
  BuildContext context,
  AdminApi api,
  String scope,
  String subjectId,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => _AssignmentDialog(
          repository: AccessRepository(api),
          scope: scope,
          subjectId: subjectId,
        ),
      ) ??
      false;
}

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog({
    required this.repository,
    required this.scope,
    required this.subjectId,
  });
  final AccessRepository repository;
  final String scope;
  final String subjectId;
  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  List<Record>? _groups;
  Record? _assignment;
  String? _selected;
  String? _error;
  var _busy = true;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final groups = await widget.repository.groups(widget.scope);
      final assignment = await widget.repository.assignment(
        widget.scope,
        widget.subjectId,
      );
      if (mounted) {
        setState(() {
          _groups = groups
              .where((group) => group['protected'] != true)
              .toList();
          _assignment = assignment;
          _selected =
              _groups!.any((group) => group['id'] == assignment['groupId'])
              ? assignment['groupId'] as String?
              : null;
          _busy = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ApiException
              ? error.message
              : 'The assignment could not be loaded.';
          _busy = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.assign(
        widget.scope,
        widget.subjectId,
        _selected!,
        integer(_assignment!['revision']),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (error.isConflict) await _load();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The group assignment could not be saved.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Assign ${widget.scope} group'),
    content: SizedBox(
      width: 480,
      child: AdminFormFields(
        children: <Widget>[
          if (_busy) const LinearProgressIndicator(),
          if (_groups != null)
            DropdownButtonFormField<String>(
              initialValue: _selected,
              key: ValueKey(_selected),
              decoration: const InputDecoration(labelText: 'Group'),
              items: <DropdownMenuItem<String>>[
                for (final group in _groups!)
                  DropdownMenuItem(
                    value: group['id'] as String,
                    child: Text('${group['name']}'),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _selected = value),
            ),
          const Text(
            'Existing records remain. The new group controls further additions and available features.',
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy || _selected == null || _assignment == null
            ? null
            : _save,
        child: const Text('Assign group'),
      ),
    ],
  );
}
