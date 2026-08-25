import 'dart:convert';
import 'dart:typed_data';

final class AdminApprovalLink {
  AdminApprovalLink._(this.requestId, this._approvalBytes);

  final String requestId;
  Uint8List? _approvalBytes;

  bool get hasCredential => _approvalBytes != null;

  String get approvalToken {
    final bytes = _approvalBytes;
    if (bytes == null) {
      throw StateError('The approval credential has already been cleared.');
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  void clear() {
    _approvalBytes?.fillRange(0, _approvalBytes!.length, 0);
    _approvalBytes = null;
  }
}

AdminApprovalLink parseAdminApprovalLink(Uri uri) {
  if (uri.scheme != 'providentia-admin' ||
      uri.host != 'login-link' ||
      uri.path != '/admin' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery) {
    throw const FormatException('Not a Providentia Admin login link.');
  }
  final parameters = <String, String>{};
  for (final part in uri.fragment.split('&')) {
    final separator = part.indexOf('=');
    if (separator <= 0 || separator == part.length - 1) {
      throw const FormatException('Malformed Admin login link fragment.');
    }
    final key = Uri.decodeQueryComponent(part.substring(0, separator));
    final value = Uri.decodeQueryComponent(part.substring(separator + 1));
    if (parameters.containsKey(key)) {
      throw const FormatException('Duplicate Admin login link parameter.');
    }
    parameters[key] = value;
  }
  if (parameters.length != 2 ||
      !parameters.containsKey('requestId') ||
      !parameters.containsKey('approval')) {
    throw const FormatException('Admin login link parameters were incomplete.');
  }

  final requestId = parameters['requestId']!;
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(requestId)) {
    throw const FormatException(
      'Admin login request identifier was malformed.',
    );
  }
  final token = parameters['approval']!;
  if (token.length < 40 ||
      token.length > 128 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token)) {
    throw const FormatException('Admin approval credential was malformed.');
  }
  Uint8List approvalBytes;
  try {
    approvalBytes = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(token)),
    );
  } on FormatException {
    throw const FormatException('Admin approval credential was malformed.');
  }
  return AdminApprovalLink._(requestId, approvalBytes);
}
