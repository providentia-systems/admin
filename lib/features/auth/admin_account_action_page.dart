import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_account_action_controller.dart';

final class AdminAccountActionPage extends StatelessWidget {
  const AdminAccountActionPage({required this.controller, super.key});

  final AdminAccountActionController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Administrator account security')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _content(context),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context) => switch (controller.phase) {
    AdminAccountActionPhase.processing ||
    AdminAccountActionPhase.resetting => const Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CircularProgressIndicator(),
        SizedBox(height: 20),
        Text('Completing the administrator account-security action…'),
      ],
    ),
    AdminAccountActionPhase.resetReady => _PasswordResetForm(
      onSubmit: controller.completePasswordReset,
    ),
    AdminAccountActionPhase.verified => _outcome(
      context,
      icon: Icons.mark_email_read_outlined,
      message: 'Administrator email address verified.',
    ),
    AdminAccountActionPhase.resetComplete => _outcome(
      context,
      icon: Icons.password_outlined,
      message: 'Administrator account password reset completed.',
    ),
    AdminAccountActionPhase.requestSent => _outcome(
      context,
      icon: Icons.outgoing_mail,
      message:
          'If the address is eligible, an application-bound message has been sent.',
    ),
    AdminAccountActionPhase.failed => _outcome(
      context,
      icon: Icons.gpp_bad,
      message: 'This administrator account action cannot be completed.',
    ),
    AdminAccountActionPhase.idle ||
    AdminAccountActionPhase.dismissed => const SizedBox.shrink(),
  };

  Widget _outcome(
    BuildContext context, {
    required IconData icon,
    required String message,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: 48),
      const SizedBox(height: 16),
      Text(message, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 24),
      FilledButton(onPressed: controller.dismiss, child: const Text('Close')),
    ],
  );
}

final class _PasswordResetForm extends StatefulWidget {
  const _PasswordResetForm({required this.onSubmit});

  final Future<void> Function(String password) onSubmit;

  @override
  State<_PasswordResetForm> createState() => _PasswordResetFormState();
}

class _PasswordResetFormState extends State<_PasswordResetForm> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  String? _validation;

  @override
  void dispose() {
    _password.clear();
    _confirmation.clear();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text('Reset password', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        'Enter at least 12 characters. The application-bound token remains memory-only and is cleared after this attempt.',
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('admin-reset-password'),
        controller: _password,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'New password'),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('admin-reset-confirmation'),
        controller: _confirmation,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Confirm password'),
      ),
      if (_validation case final message?) ...<Widget>[
        const SizedBox(height: 8),
        Text(message),
      ],
      const SizedBox(height: 20),
      FilledButton(
        key: const Key('complete-admin-password-reset'),
        onPressed: _submit,
        child: const Text('Reset password'),
      ),
    ],
  );

  void _submit() {
    final password = _password.text;
    if (password.length < 12 ||
        password.length > 1024 ||
        password != _confirmation.text) {
      setState(() {
        _validation = 'Passwords must match and contain 12 to 1024 characters.';
      });
      return;
    }
    unawaited(widget.onSubmit(password));
    _password.clear();
    _confirmation.clear();
  }
}
