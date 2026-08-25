import 'dart:convert';
import 'dart:typed_data';

enum AdminAccountLinkAction { verifyEmail, passwordReset }

final class AdminAccountLink {
  AdminAccountLink._(this.action, this._tokenBytes);

  final AdminAccountLinkAction action;
  Uint8List? _tokenBytes;

  bool get hasCredential => _tokenBytes != null;

  String get token {
    final bytes = _tokenBytes;
    if (bytes == null) {
      throw StateError('The account-link credential has already been cleared.');
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void clear() {
    _tokenBytes?.fillRange(0, _tokenBytes!.length, 0);
    _tokenBytes = null;
  }
}

bool looksLikeAdminAccountLink(Uri uri) =>
    uri.fragment.split('&').any((part) => part.startsWith('action='));

AdminAccountLink parseAdminAccountLink(Uri uri) {
  if (uri.scheme != 'providentia-admin' ||
      uri.host != 'login-link' ||
      uri.path != '/admin' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery) {
    throw const FormatException('Not a Providentia Admin account link.');
  }
  final parameters = <String, String>{};
  for (final part in uri.fragment.split('&')) {
    final separator = part.indexOf('=');
    if (separator <= 0 || separator == part.length - 1) {
      throw const FormatException('Malformed Admin account-link fragment.');
    }
    final key = Uri.decodeQueryComponent(part.substring(0, separator));
    final value = Uri.decodeQueryComponent(part.substring(separator + 1));
    if (parameters.containsKey(key)) {
      throw const FormatException('Duplicate Admin account-link parameter.');
    }
    parameters[key] = value;
  }
  if (parameters.length != 2 ||
      !parameters.containsKey('action') ||
      !parameters.containsKey('token')) {
    throw const FormatException(
      'Admin account-link parameters were incomplete.',
    );
  }
  final action = switch (parameters['action']) {
    'verify-email' => AdminAccountLinkAction.verifyEmail,
    'password-reset' => AdminAccountLinkAction.passwordReset,
    _ => throw const FormatException('Unknown Admin account-link action.'),
  };
  final token = parameters['token']!;
  if (token.length < 40 ||
      token.length > 128 ||
      !_tokenPattern.hasMatch(token)) {
    throw const FormatException('Admin account-link credential was malformed.');
  }
  try {
    return AdminAccountLink._(
      action,
      Uint8List.fromList(base64Url.decode(base64Url.normalize(token))),
    );
  } on FormatException {
    throw const FormatException('Admin account-link credential was malformed.');
  }
}

final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]+$');
