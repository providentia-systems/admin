import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/auth/session_controller.dart';
import '../features/auth/login_page.dart';
import '../features/profile/account_profile_page.dart';
import '../features/profile/admin_profile_port.dart';
import 'admin_shell.dart';
import 'theme.dart';

final class ProvidentiaAdminApp extends StatelessWidget {
  const ProvidentiaAdminApp({
    required this.api,
    required this.session,
    super.key,
  });

  final ApiClient api;
  final SessionController session;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Providentia Admin',
    debugShowCheckedModeBanner: false,
    theme: buildAdminTheme(),
    home: AnimatedBuilder(
      animation: session,
      builder: (context, _) => switch (session.phase) {
        SessionPhase.restoring => const _RestoringPage(),
        SessionPhase.signedOut ||
        SessionPhase.loginPending => LoginPage(session: session),
        SessionPhase.authenticated =>
          session.profile['onboardingComplete'] != true
              ? AccountProfilePage(
                  port: AdminProfilePort(api),
                  onChanged: session.reloadProfile,
                  onboarding: true,
                  onSignOut: session.signOut,
                )
              : !session.authorization.isOperator
              ? _ApprovalPendingPage(session: session)
              : AdminShell(
                  key: ValueKey<int>(session.authorizationEpoch),
                  api: api,
                  session: session,
                ),
      },
    ),
  );
}

final class _RestoringPage extends StatelessWidget {
  const _RestoringPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Semantics(
        label: 'Restoring administrator session',
        child: const CircularProgressIndicator(),
      ),
    ),
  );
}

final class _ApprovalPendingPage extends StatelessWidget {
  const _ApprovalPendingPage({required this.session});
  final SessionController session;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Administrator access'),
      actions: <Widget>[
        IconButton(
          onPressed: session.signOut,
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: Center(
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.admin_panel_settings_outlined, size: 64),
              const SizedBox(height: 24),
              Text(
                session.profile['administratorStatus'] == 'pending'
                    ? 'Your administrator request is awaiting approval.'
                    : 'Your account has no active administrator permissions.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: session.reloadProfile,
                child: const Text('Check access'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
