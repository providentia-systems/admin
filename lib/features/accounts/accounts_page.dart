import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import 'account_models.dart';
import 'account_repository.dart';

final class AccountsPage extends StatefulWidget {
  const AccountsPage({required this.api, required this.session, super.key});

  final AdminApi api;
  final SessionController session;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  late final AccountRepository _repository;
  final _search = TextEditingController();
  Timer? _debounce;
  OperatorAccountPage? _page;
  OperatorAccount? _selected;
  String? _status;
  var _hasError = false;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _repository = AccountRepository(widget.api);
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Accounts', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          'Privacy-safe identity, home membership summary, status, sessions and platform roles.',
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Search email or display name',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 350),
                    () => unawaited(_load()),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String?>(
              value: _status,
              hint: const Text('All statuses'),
              items: const <DropdownMenuItem<String?>>[
                DropdownMenuItem(value: null, child: Text('All statuses')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                DropdownMenuItem(value: 'closed', child: Text('Closed')),
              ],
              onChanged: (value) {
                setState(() => _status = value);
                unawaited(_load());
              },
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              tooltip: 'Refresh accounts',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_hasError)
          _ErrorBanner(retry: _load),
        if (_loading) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Card(
                  child: _AccountList(
                    accounts: _page?.data ?? const <OperatorAccount>[],
                    selectedId: _selected?.userId,
                    onSelected: _select,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Card(
                  child: _selected == null
                      ? const Center(
                          child: Text('Select an account to inspect it.'),
                        )
                      : _AccountDetail(
                          account: _selected!,
                          onStatus: _changeStatus,
                          onRole: _changeRole,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _load() async {
    final epoch = widget.session.authorizationEpoch;
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final page = await _repository.list(
        search: _search.text,
        status: _status,
      );
      if (!_isAuthorized(epoch)) return;
      setState(() {
        _page = page;
        _loading = false;
      });
      final selectedId = _selected?.userId;
      if (selectedId != null &&
          !page.data.any((account) => account.userId == selectedId)) {
        setState(() => _selected = null);
      }
    } on Object {
      if (!_isAuthorized(epoch)) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _select(OperatorAccount account) async {
    final epoch = widget.session.authorizationEpoch;
    setState(() => _selected = account);
    try {
      final detail = await _repository.get(account.userId);
      if (_isAuthorized(epoch) && _selected?.userId == detail.userId) {
        setState(() => _selected = detail);
      }
    } on Object {
      if (_isAuthorized(epoch)) _snack('The account could not be loaded.');
    }
  }

  Future<void> _changeStatus(String status) async {
    final selected = _selected;
    if (selected == null) return;
    final reason = await _reasonDialog(
      title: '${status[0].toUpperCase()}${status.substring(1)} account',
    );
    if (reason == null) return;
    try {
      final updated = await _repository.changeStatus(
        userId: selected.userId,
        status: status,
        reason: reason,
        expectedRevision: selected.revision,
      );
      if (!mounted) return;
      setState(() => _selected = updated);
      await _load();
    } on ApiException catch (error) {
      if (error.isConflict) await _select(selected);
      if (mounted) _snack(_safeApiMessage(error));
    }
  }

  Future<void> _changeRole(String role, bool grant) async {
    final selected = _selected;
    if (selected == null) return;
    try {
      final updated = await _repository.changeRole(
        userId: selected.userId,
        role: role,
        expectedRevision: selected.revision,
        grant: grant,
      );
      if (!mounted) return;
      setState(() => _selected = updated);
      await _load();
    } on ApiException catch (error) {
      if (error.isConflict) await _select(selected);
      if (mounted) _snack(_safeApiMessage(error));
    }
  }

  Future<String?> _reasonDialog({required String title}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Auditable reason (at least 5 characters)',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 5) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  bool _isAuthorized(int epoch) =>
      mounted &&
      widget.session.phase == SessionPhase.authenticated &&
      widget.session.authorizationEpoch == epoch;

  static String _safeApiMessage(ApiException error) => error.isConflict
      ? 'The account changed on the server. Its current state was reloaded.'
      : 'The account operation was rejected (HTTP ${error.statusCode}).';
}

final class _AccountList extends StatelessWidget {
  const _AccountList({
    required this.accounts,
    required this.selectedId,
    required this.onSelected,
  });

  final List<OperatorAccount> accounts;
  final String? selectedId;
  final ValueChanged<OperatorAccount> onSelected;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return const Center(child: Text('No accounts match these filters.'));
    }
    return ListView.separated(
      itemCount: accounts.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final account = accounts[index];
        return ListTile(
          selected: account.userId == selectedId,
          title: Text(
            account.displayName.isEmpty ? account.email : account.displayName,
          ),
          subtitle: Text(account.email),
          trailing: Chip(label: Text(account.status)),
          onTap: () => onSelected(account),
        );
      },
    );
  }
}

final class _AccountDetail extends StatelessWidget {
  const _AccountDetail({
    required this.account,
    required this.onStatus,
    required this.onRole,
  });

  final OperatorAccount account;
  final ValueChanged<String> onStatus;
  final void Function(String role, bool grant) onRole;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: <Widget>[
      Text(
        account.displayName.isEmpty ? account.email : account.displayName,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 4),
      SelectableText(account.email),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          Chip(label: Text('Status: ${account.status}')),
          Chip(label: Text('Revision ${account.revision}')),
          Chip(label: Text('${account.homeCount} home(s)')),
          Chip(label: Text('${account.activeSessionCount} session(s)')),
        ],
      ),
      const Divider(height: 32),
      Text('Platform roles', style: Theme.of(context).textTheme.titleMedium),
      for (final role in const <String>[
        'platform_administrator',
        'catalog_reviewer',
        'catalog_curator',
        'billing_operator',
      ])
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: account.platformRoles.contains(role),
          title: Text(role.replaceAll('_', ' ')),
          onChanged: account.isClosed
              ? null
              : (value) => onRole(role, value ?? false),
        ),
      const Divider(height: 32),
      Text('Lifecycle', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          OutlinedButton(
            onPressed: account.status == 'active'
                ? null
                : () => onStatus('active'),
            child: const Text('Activate'),
          ),
          OutlinedButton(
            onPressed: account.status == 'suspended' || account.isClosed
                ? null
                : () => onStatus('suspended'),
            child: const Text('Suspend'),
          ),
          FilledButton.tonal(
            onPressed: account.isClosed ? null : () => onStatus('closed'),
            child: const Text('Close permanently'),
          ),
        ],
      ),
      if (account.homes.isNotEmpty) ...<Widget>[
        const Divider(height: 32),
        Text(
          'Home membership summary',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final home in account.homes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(home.name),
            subtitle: Text('${home.role} • ${home.status}'),
            trailing: home.subscriptionStatus == null
                ? null
                : Chip(label: Text(home.subscriptionStatus!)),
          ),
      ],
    ],
  );
}

final class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.retry});
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: const Text('The account list could not be loaded.'),
    leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
    actions: <Widget>[
      TextButton(onPressed: retry, child: const Text('Retry')),
    ],
  );
}
