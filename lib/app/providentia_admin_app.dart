import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/auth/session_controller.dart';
import '../features/auth/login_page.dart';
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
        SessionPhase.authenticated => AdminShell(
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
