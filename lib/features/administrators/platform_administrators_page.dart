import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import 'platform_administration_controller.dart';
import 'platform_administrator_models.dart';
import 'platform_administrator_repository.dart';

final class PlatformAdministratorsPage extends StatefulWidget {
  const PlatformAdministratorsPage({
    required this.api,
    this.administrationPort,
    super.key,
  });

  final AdminApi api;
  final PlatformAdministrationPort? administrationPort;

  @override
  State<PlatformAdministratorsPage> createState() =>
      _PlatformAdministratorsPageState();
}

class _PlatformAdministratorsPageState
    extends State<PlatformAdministratorsPage> {
  late final PlatformAdministrationController _controller;
  final _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = PlatformAdministrationController(
      widget.administrationPort ?? PlatformAdministratorRepository(widget.api),
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _email.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final snapshot = _controller.snapshot;
      final activeCount = snapshot.administrators
          .where(
            (administrator) =>
                administrator.status == PlatformAdministratorStatus.active,
          )
          .length;
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Platform administrators',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Grant the global operator role by verified email address. '
              'Pending grants activate after that address completes verification.',
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('administrator-email'),
                    controller: _email,
                    enabled: !snapshot.loading,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const <String>[AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Administrator email address',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    onSubmitted: snapshot.loading ? null : (_) => _grant(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  key: const Key('grant-administrator'),
                  onPressed: snapshot.loading ? null : _grant,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Grant'),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  tooltip: 'Refresh administrators',
                  onPressed: snapshot.loading ? null : _controller.load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (snapshot.safeMessage case final message?)
              MaterialBanner(
                key: const Key('administrator-safe-message'),
                content: Text(message),
                actions: <Widget>[
                  TextButton(
                    onPressed: snapshot.loading ? null : _controller.load,
                    child: const Text('Reload'),
                  ),
                ],
              ),
            if (snapshot.loading) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                child: snapshot.administrators.isEmpty && !snapshot.loading
                    ? const Center(
                        child: Text('No administrator grants were returned.'),
                      )
                    : ListView.separated(
                        itemCount: snapshot.administrators.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final administrator = snapshot.administrators[index];
                          final isFinalActive =
                              administrator.status ==
                                  PlatformAdministratorStatus.active &&
                              activeCount <= 1;
                          return ListTile(
                            key: Key('administrator-${administrator.id}'),
                            leading: Icon(
                              administrator.status ==
                                      PlatformAdministratorStatus.active
                                  ? Icons.admin_panel_settings
                                  : Icons.mark_email_unread_outlined,
                            ),
                            title: Text(administrator.email),
                            subtitle: Text(
                              '${administrator.status.name} • granted '
                              '${_dateLabel(administrator.createdAt)} • '
                              'revision ${administrator.revision}',
                            ),
                            trailing: Tooltip(
                              message: isFinalActive
                                  ? 'The final active platform administrator cannot be revoked.'
                                  : 'Revoke platform-administrator access',
                              child: IconButton(
                                key: Key(
                                  'revoke-administrator-${administrator.id}',
                                ),
                                onPressed: snapshot.loading || isFinalActive
                                    ? null
                                    : () => _confirmRevoke(administrator),
                                icon: const Icon(Icons.person_remove_outlined),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _grant() async {
    await _controller.grant(_email.text);
    if (mounted && _controller.snapshot.safeMessage == null) {
      _email.clear();
    }
  }

  Future<void> _confirmRevoke(PlatformAdministrator administrator) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke platform administrator?'),
        content: Text(
          'This removes global operator access for ${administrator.email}. '
          'The operation is revision-bound and will be rejected if the grant changed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-revoke-administrator'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke access'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.revoke(administrator);
  }

  static String _dateLabel(DateTime value) =>
      value.toUtc().toIso8601String().substring(0, 10);
}
