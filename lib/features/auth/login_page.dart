import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/session_controller.dart';

final class LoginPage extends StatefulWidget {
  const LoginPage({required this.session, super.key});
  final SessionController session;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  Timer? _countdown;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.session.challenge != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _message =
              'Sign-in could not be completed. Check your code and connection, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = widget.session.challenge;
    final remaining =
        challenge?.resendAt.difference(DateTime.now().toUtc()).inSeconds ?? 0;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Icon(Icons.admin_panel_settings_outlined, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Providentia Admin',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        challenge == null
                            ? 'Enter your email to sign in or request administrator access.'
                            : 'Enter the eight-digit code sent to ${challenge.email}.',
                      ),
                      const SizedBox(height: 24),
                      if (challenge == null) ...<Widget>[
                        TextField(
                          key: const Key('login-email'),
                          controller: _email,
                          enabled: !_busy,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const <String>[AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                          ),
                          onSubmitted: (_) => _request(),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy ? null : _request,
                          child: const Text('Email me a code'),
                        ),
                      ] else ...<Widget>[
                        TextField(
                          key: const Key('login-code'),
                          controller: _code,
                          enabled: !_busy,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          autofillHints: const <String>[
                            AutofillHints.oneTimeCode,
                          ],
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(8),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Email code',
                            helperText: 'Valid for ten minutes',
                          ),
                          onSubmitted: (_) => _verify(),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy ? null : _verify,
                          child: const Text('Verify and sign in'),
                        ),
                        TextButton(
                          onPressed: _busy || remaining > 0
                              ? null
                              : () => _run(() async {
                                  await widget.session.requestEmailCode(
                                    challenge.email,
                                  );
                                  _code.clear();
                                }),
                          child: Text(
                            remaining > 0
                                ? 'Resend in ${remaining}s'
                                : 'Send a new code',
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(widget.session.cancelEmailCode),
                          child: const Text('Use another email'),
                        ),
                      ],
                      if (_busy) const LinearProgressIndicator(),
                      if (_message ?? widget.session.error case final message?)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(message, semanticsLabel: message),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _request() {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      setState(() => _message = 'Enter a valid email address.');
      return;
    }
    unawaited(_run(() => widget.session.requestEmailCode(_email.text.trim())));
  }

  void _verify() {
    if (_code.text.length != 8) {
      setState(() => _message = 'Enter all eight digits.');
      return;
    }
    unawaited(
      _run(() async {
        await widget.session.verifyEmailCode(_code.text);
      }),
    );
  }
}
