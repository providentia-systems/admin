import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/session_controller.dart';

final class LoginPage extends StatefulWidget {
  const LoginPage({required this.session, super.key});

  final SessionController session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  Timer? _pollTimer;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.session.phase == SessionPhase.loginPending) _schedulePoll();
  }

  @override
  void didUpdateWidget(covariant LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.phase == SessionPhase.loginPending &&
        _pollTimer == null) {
      _schedulePoll();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.session.phase == SessionPhase.loginPending;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Providentia Admin',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pending
                        ? 'Open the secure link sent to your verified email. This window will continue when approval completes.'
                        : 'Sign in with an account that has a platform operator role.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (!pending) ...<Widget>[
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const <String>[AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Operator email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      onSubmitted: (_) => _start(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : _start,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: const Text('Send secure sign-in link'),
                    ),
                  ] else ...<Widget>[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _busy ? null : _cancel,
                      child: const Text('Cancel sign-in'),
                    ),
                  ],
                  if (widget.session.error case final error?) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _start() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid operator email address.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.session.startLoginLink(email);
      _schedulePoll();
    } on Object {
      if (mounted) _showError();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    final interval = widget.session.challenge?.pollInterval ??
        const Duration(seconds: 3);
    _pollTimer = Timer.periodic(interval, (_) async {
      if (_busy || !mounted) return;
      _busy = true;
      try {
        final completed = await widget.session.pollLoginLink();
        if (completed || widget.session.phase != SessionPhase.loginPending) {
          _pollTimer?.cancel();
          _pollTimer = null;
        }
      } on Object {
        if (mounted) _showError();
      } finally {
        _busy = false;
      }
    });
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    _pollTimer?.cancel();
    _pollTimer = null;
    await widget.session.cancelLoginLink();
    if (mounted) setState(() => _busy = false);
  }

  void _showError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sign-in could not be completed safely.')),
    );
  }
}
