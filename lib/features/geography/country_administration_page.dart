import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/operator_authorization.dart';
import '../access/access_repository.dart';

final class CountryAdministrationPage extends StatefulWidget {
  const CountryAdministrationPage({
    required this.api,
    required this.authorization,
    this.policies = false,
    super.key,
  });
  final AdminApi api;
  final OperatorAuthorization authorization;
  final bool policies;
  @override
  State<CountryAdministrationPage> createState() =>
      _CountryAdministrationPageState();
}

class _CountryAdministrationPageState extends State<CountryAdministrationPage> {
  final _search = TextEditingController();
  List<Record> _rows = <Record>[];
  List<Record> _jobs = <Record>[];
  var _busy = true;
  String? _error;
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = records(
        (await widget.api.get(
          widget.policies
              ? '/api/v1/admin/privacy-policies'
              : '/api/v1/admin/countries',
        )).jsonObject,
      );
      final jobs = widget.policies
          ? <Record>[]
          : records(
              (await widget.api.get(
                '/api/v1/admin/reference-updates',
              )).jsonObject,
            );
      if (mounted) {
        setState(() {
          _rows = rows;
          _jobs = jobs;
          _busy = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is ApiException
              ? error.message
              : 'Country information could not be loaded.';
        });
      }
    }
  }

  Future<void> _edit([Record? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => widget.policies
          ? _PolicyEditor(api: widget.api, policy: row)
          : _CountryEditor(
              api: widget.api,
              country: row!,
              canReadPolicies: widget.authorization.has('policies.manage'),
            ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('/api/v1/admin/reference-updates');
      if (mounted) await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is ApiException
              ? error.message
              : 'The update could not be requested.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          widget.policies ? 'Privacy policies' : 'Countries and locations',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          widget.policies
              ? 'Published notices remain as accepted. Create a new version to change a published notice, then select it in the country settings.'
              : 'Publication, starter groups, currency and timezone are configured per country. Reference updates preserve these settings.',
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Filter by name or country',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : widget.policies
                  ? () => _edit()
                  : _update,
              icon: Icon(widget.policies ? Icons.add : Icons.download),
              label: Text(
                widget.policies ? 'New policy' : 'Update country data',
              ),
            ),
            IconButton(
              onPressed: _busy ? null : _load,
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_jobs.isNotEmpty)
          ExpansionTile(
            title: Text('Latest reference update: ${_jobs.first['status']}'),
            children: <Widget>[
              for (final job in _jobs)
                ListTile(
                  title: Text(
                    '${job['status']} · ${job['source_version'] ?? 'Version pending'}',
                  ),
                  subtitle: Text(
                    '${job['created_at']} · ${job['processed_count']} records · ${job['safe_message'] ?? ''}',
                  ),
                ),
              const ListTile(
                title: Text(
                  'Country data: dr5hn/countries-states-cities-database',
                ),
                subtitle: Text(
                  'Open Database License (ODbL). Upstream attribution is retained in the project documentation.',
                ),
              ),
            ],
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Expanded(
          child: ListView(
            children: <Widget>[
              for (final row in _rows.where(
                (row) =>
                    '${row['name'] ?? row['title']} ${row['code'] ?? row['country_code'] ?? 'default'}'
                        .toLowerCase()
                        .contains(_search.text.toLowerCase()),
              ))
                ListTile(
                  title: Text('${row['name'] ?? row['title']}'),
                  subtitle: Text(
                    widget.policies
                        ? '${row['country_code'] ?? 'Shared default'} · ${row['status']} · version ${row['revision']}'
                        : '${row['code']} · ${row['defaultCurrency']} · ${row['defaultTimezone']}',
                  ),
                  trailing: widget.policies
                      ? const Icon(Icons.edit_outlined)
                      : Chip(
                          label: Text(
                            row['published'] == true ||
                                    integer(row['published']) == 1
                                ? 'Published'
                                : 'Unpublished',
                          ),
                        ),
                  onTap: () => _edit(row),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CountryEditor extends StatefulWidget {
  const _CountryEditor({
    required this.api,
    required this.country,
    required this.canReadPolicies,
  });
  final AdminApi api;
  final Record country;
  final bool canReadPolicies;
  @override
  State<_CountryEditor> createState() => _CountryEditorState();
}

class _CountryEditorState extends State<_CountryEditor> {
  final _form = GlobalKey<FormState>();
  final _currency = TextEditingController();
  final _timezone = TextEditingController();
  Record? _settings;
  List<Record> _accounts = <Record>[];
  List<Record> _homes = <Record>[];
  List<Record> _policies = <Record>[];
  String? _accountGroup;
  String? _invitedGroup;
  String? _homeGroup;
  String? _policy;
  var _published = false;
  var _busy = true;
  String? _error;
  String get _code => '${widget.country['code']}';
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _currency.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = (await widget.api.get(
        '/api/v1/admin/countries/$_code',
      )).jsonObject;
      final repository = AccessRepository(widget.api);
      final accounts = await repository.groups('account');
      final homes = await repository.groups('home');
      final policies = widget.canReadPolicies
          ? records(
              (await widget.api.get(
                '/api/v1/admin/privacy-policies',
                query: <String, String>{'countryCode': _code},
              )).jsonObject,
            ).where((policy) => policy['status'] == 'published').toList()
          : <Record>[];
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _accounts = accounts;
        _homes = homes;
        _policies = policies;
        _accountGroup = settings['account_group_id'] as String?;
        _invitedGroup = settings['invited_group_id'] as String?;
        _homeGroup = settings['home_group_id'] as String?;
        _policy = settings['policy_id'] as String?;
        _published = integer(settings['published']) == 1;
        _currency.text = '${settings['default_currency']}';
        _timezone.text = '${settings['default_timezone']}';
        _busy = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is ApiException
              ? error.message
              : 'Country settings could not be loaded.';
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.put(
        '/api/v1/admin/countries/$_code',
        body: <String, Object?>{
          'published': _published,
          'accountGroupId': _accountGroup,
          'invitedGroupId': _invitedGroup,
          'homeGroupId': _homeGroup,
          'policyId': _policy,
          'defaultCurrency': _currency.text.trim().toUpperCase(),
          'defaultTimezone': _timezone.text.trim(),
          'expectedRevision': integer(_settings!['revision']),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (error is ApiException && error.isConflict) await _load();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is ApiException
              ? error.message
              : 'Country settings could not be saved.';
        });
      }
    }
  }

  Widget _groups(
    String label,
    List<Record> groups,
    String? selected,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$selected'),
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: <DropdownMenuItem<String>>[
      for (final group in groups)
        DropdownMenuItem(
          value: group['id'] as String,
          child: Text('${group['name']}'),
        ),
    ],
    onChanged: _busy ? null : onChanged,
    validator: (value) => value == null ? 'Select a group.' : null,
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.country['name']}'),
    content: SizedBox(
      width: 620,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_busy) const LinearProgressIndicator(),
              if (_settings != null) ...<Widget>[
                SwitchListTile(
                  title: const Text('Open registration in this country'),
                  value: _published,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _published = value),
                ),
                _groups(
                  'New account group',
                  _accounts,
                  _accountGroup,
                  (value) => setState(() => _accountGroup = value),
                ),
                _groups(
                  'Invited account group',
                  _accounts,
                  _invitedGroup,
                  (value) => setState(() => _invitedGroup = value),
                ),
                _groups(
                  'New home group',
                  _homes,
                  _homeGroup,
                  (value) => setState(() => _homeGroup = value),
                ),
                TextFormField(
                  controller: _currency,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Default currency',
                  ),
                  maxLength: 3,
                  validator: (value) =>
                      RegExp(r'^[A-Za-z]{3}$').hasMatch(value ?? '')
                      ? null
                      : 'Enter a three-letter currency code.',
                ),
                TextFormField(
                  controller: _timezone,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Default timezone',
                    hintText: 'Africa/Windhoek',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a timezone.'
                      : null,
                ),
                if (widget.canReadPolicies)
                  DropdownButtonFormField<String>(
                    key: ValueKey(_policy),
                    initialValue: _policy,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Published privacy notice',
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final policy in _policies)
                        DropdownMenuItem(
                          value: policy['id'] as String,
                          child: Text(
                            '${policy['title']} (${policy['updated_at']})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _policy = value),
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
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy || _settings == null ? null : _save,
        child: const Text('Save country'),
      ),
    ],
  );
}

class _PolicyEditor extends StatefulWidget {
  const _PolicyEditor({required this.api, this.policy});
  final AdminApi api;
  final Record? policy;
  @override
  State<_PolicyEditor> createState() => _PolicyEditorState();
}

class _PolicyEditorState extends State<_PolicyEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: '${widget.policy?['title'] ?? ''}',
  );
  late final _body = TextEditingController(
    text: '${widget.policy?['body'] ?? ''}',
  );
  late final _country = TextEditingController(
    text: '${widget.policy?['country_code'] ?? ''}',
  );
  var _publish = false;
  var _busy = false;
  String? _error;
  bool get _newVersion => widget.policy?['status'] == 'published';
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, Object?>{
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'countryCode': _country.text.trim().isEmpty
            ? null
            : _country.text.trim().toUpperCase(),
        'status': _publish ? 'published' : 'draft',
        'expectedRevision': _newVersion
            ? 0
            : integer(widget.policy?['revision']),
      };
      if (widget.policy == null || _newVersion) {
        await widget.api.post('/api/v1/admin/privacy-policies', body: body);
      } else {
        await widget.api.put(
          '/api/v1/admin/privacy-policies/${widget.policy!['id']}',
          body: body,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is ApiException
              ? error.message
              : 'The policy could not be saved.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_newVersion ? 'Create a new policy version' : 'Privacy policy'),
    content: SizedBox(
      width: 800,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_newVersion)
                const Text(
                  'The published version and its acceptance history remain unchanged.',
                ),
              TextFormField(
                controller: _title,
                enabled: !_busy,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a title.'
                    : null,
              ),
              TextFormField(
                controller: _country,
                enabled: !_busy,
                maxLength: 2,
                decoration: const InputDecoration(
                  labelText: 'Country code (leave empty for shared default)',
                ),
                validator: (value) =>
                    value == null ||
                        value.isEmpty ||
                        RegExp(r'^[A-Za-z]{2}$').hasMatch(value)
                    ? null
                    : 'Use a two-letter country code.',
              ),
              TextFormField(
                controller: _body,
                enabled: !_busy,
                minLines: 12,
                maxLines: 24,
                maxLength: 100000,
                decoration: const InputDecoration(labelText: 'Privacy notice'),
                validator: (value) => value == null || value.trim().length < 100
                    ? 'Enter the complete privacy notice (at least 100 characters).'
                    : null,
              ),
              SwitchListTile(
                title: const Text('Publish this version'),
                subtitle: const Text(
                  'Published text cannot be edited. Select this version in country settings to use it for registration.',
                ),
                value: _publish,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _publish = value),
              ),
              if (_error != null) Text(_error!),
            ],
          ),
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_publish ? 'Publish version' : 'Save draft'),
      ),
    ],
  );
}
