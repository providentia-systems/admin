import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';
import '../access/access_groups_page.dart';
import '../access/access_repository.dart';

final class PlatformAdministratorsPage extends StatefulWidget {
  const PlatformAdministratorsPage({
    required this.api,
    required this.session,
    super.key,
  });
  final AdminApi api;
  final SessionController session;
  @override
  State<PlatformAdministratorsPage> createState() =>
      _PlatformAdministratorsPageState();
}

class _PlatformAdministratorsPageState
    extends State<PlatformAdministratorsPage> {
  var _busy = true;
  String? _error;
  List<Record> _administrators = <Record>[];
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = records(
        (await widget.api.get('/api/v1/admin/administrators')).jsonObject,
      );
      if (mounted) {
        setState(() {
          _administrators = data;
          _busy = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is ApiException
              ? error.message
              : 'Administrator requests could not be loaded.';
        });
      }
    }
  }

  Future<void> _review(Record administrator, String status) async {
    try {
      String? groupId;
      if (status == 'approved') {
        final groups = (await AccessRepository(widget.api).groups(
          'admin',
        )).where((group) => group['protected'] != true).toList();
        if (!mounted) return;
        groupId = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Approve into administrator group'),
            children: <Widget>[
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Create an administrator group before approving this request.',
                  ),
                ),
              for (final group in groups)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, group['id']),
                  child: Text('${group['name']}'),
                ),
            ],
          ),
        );
        if (groupId == null || !mounted) return;
      } else {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              '${status == 'suspended' ? 'Suspend' : 'Reject'} administrator?',
            ),
            content: Text(
              '${administrator['email']} will have no administrative access.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      setState(() => _busy = true);
      await widget.api.post(
        '/api/v1/admin/administrators/${administrator['user_id']}/review',
        body: <String, Object?>{
          'status': status,
          'groupId': ?groupId,
          'expectedRevision': integer(administrator['revision']),
          'assignmentRevision': integer(
            administrator['groupAssignmentRevision'],
          ),
        },
      );
      if (mounted) await _load();
    } on Object catch (error) {
      if (error is ApiException && error.isConflict && mounted) await _load();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is ApiException
              ? error.message
              : 'Administrator access could not be changed.';
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
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Administrators',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              onPressed: _busy ? null : _load,
              tooltip: 'Reload administrators',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const Text(
          'New administrators verify their email, complete their profile and wait for approval into one administrator group.',
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
              for (final admin in _administrators)
                Card(
                  child: ListTile(
                    title: Text('${admin['displayName'] ?? admin['email']}'),
                    subtitle: Text(
                      '${admin['email']} · ${admin['status']} · ${admin['groupName'] ?? 'No group'}',
                    ),
                    trailing:
                        admin['user_id'] == widget.session.userId ||
                            (admin['systemOwner'] == true || admin['systemOwner'] == 1)
                        ? const Icon(Icons.lock_outline)
                        : Wrap(
                            spacing: 8,
                            children: <Widget>[
                              if (widget.session.authorization.has(
                                'administrators.approve',
                              )) ...<Widget>[
                                if (admin['status'] != 'approved')
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _review(admin, 'approved'),
                                    child: const Text('Approve'),
                                  ),
                                if (admin['status'] == 'pending')
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _review(admin, 'rejected'),
                                    child: const Text('Reject'),
                                  ),
                                if (admin['status'] == 'approved')
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _review(admin, 'suspended'),
                                    child: const Text('Suspend'),
                                  ),
                              ],
                              if (admin['status'] == 'approved' &&
                                  widget.session.authorization.has(
                                    'administrators.manage',
                                  ))
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          final changed =
                                              await showGroupAssignment(
                                                context,
                                                widget.api,
                                                'admin',
                                                '${admin['user_id']}',
                                              );
                                          if (changed && mounted) await _load();
                                        },
                                  child: const Text('Change group'),
                                ),
                            ],
                          ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
