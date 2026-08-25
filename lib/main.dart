import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app/providentia_admin_app.dart';
import 'core/api/api_client.dart';
import 'core/auth/admin_account_link.dart';
import 'core/auth/credential_store.dart';
import 'core/auth/session_controller.dart';
import 'core/platform/application_link_source.dart';
import 'features/auth/admin_account_action_controller.dart';
import 'features/auth/admin_account_action_port.dart';
import 'features/auth/admin_approval_controller.dart';
import 'features/auth/admin_approval_port.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();

  const backendUrl = String.fromEnvironment(
    'PROVIDENTIA_API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  final backendUri = validateBackendUri(Uri.parse(backendUrl));
  final credentialStore = SecureCredentialStore();
  late final SessionController session;
  final api = ApiClient(
    baseUri: backendUri,
    httpClient: http.Client(),
    accessTokenProvider: () => session.accessToken,
    ensureAccessToken: ({required force}) =>
        session.ensureFreshAccessToken(force: force),
    onAuthorizationLost: () => session.authorizationLost(),
  );
  session = SessionController(api: api, credentialStore: credentialStore);
  final approval = AdminApprovalController(HttpAdminLoginApprovalPort(api));
  final accountActions = AdminAccountActionController(
    HttpAdminAccountActionPort(api),
  );
  final linkSource = LinuxApplicationLinkSource();
  await linkSource.start();
  void handleApplicationLink(Uri uri) {
    if (looksLikeAdminAccountLink(uri)) {
      unawaited(accountActions.begin(uri));
    } else {
      unawaited(approval.begin(uri));
    }
  }

  linkSource.links.listen(handleApplicationLink);
  for (final argument in arguments.take(1)) {
    final uri = Uri.tryParse(argument);
    if (uri != null) handleApplicationLink(uri);
  }

  runApp(
    ProvidentiaAdminApp(
      api: api,
      approval: approval,
      accountActions: accountActions,
      session: session,
    ),
  );
  unawaited(session.restore());
}
