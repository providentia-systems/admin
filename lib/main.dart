import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app/providentia_admin_app.dart';
import 'core/api/api_client.dart';
import 'core/auth/credential_store.dart';
import 'core/auth/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const backendUrl = String.fromEnvironment(
    'PROVIDENTIA_API_URL',
    defaultValue: 'http://localhost:8080',
  );
  final credentialStore = SecureCredentialStore();
  late final SessionController session;
  final api = ApiClient(
    baseUri: Uri.parse(backendUrl),
    httpClient: http.Client(),
    accessTokenProvider: () => session.accessToken,
    onAuthorizationLost: () => session.authorizationLost(),
  );
  session = SessionController(api: api, credentialStore: credentialStore);

  runApp(ProvidentiaAdminApp(api: api, session: session));
  unawaited(session.restore());
}

