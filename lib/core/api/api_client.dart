import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../security/secure_id.dart';

const _maximumResponseBytes = 8 * 1024 * 1024;

Uri validateBackendUri(Uri uri) {
  final local =
      uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
  if (!uri.hasScheme || !uri.hasAuthority || uri.host.isEmpty) {
    throw const FormatException('The backend base URL must be absolute.');
  }
  if (uri.scheme != 'https' && !(local && uri.scheme == 'http')) {
    throw const FormatException(
      'The backend requires HTTPS except on the local loopback interface.',
    );
  }
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw const FormatException(
      'The backend base URL cannot contain credentials, query, or fragment.',
    );
  }
  if (uri.path.isNotEmpty && uri.path != '/') {
    throw const FormatException('The backend base URL cannot contain a path.');
  }
  return uri;
}

typedef AccessTokenProvider = String? Function();
typedef AuthorizationLostCallback = void Function();
typedef EnsureAccessTokenCallback =
    Future<bool> Function({required bool force});

abstract interface class AdminApi {
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  });
  Future<ApiResponse> post(
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  });
  Future<ApiResponse> postPublic(
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  });
  Future<ApiResponse> put(
    String path, {
    Object? body,
    Map<String, String>? headers,
  });
  Future<ApiResponse> patch(
    String path, {
    Object? body,
    Map<String, String>? headers,
  });
  Future<ApiResponse> delete(
    String path, {
    Object? body,
    Map<String, String>? headers,
  });
}

final class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.message,
    this.problem,
  });

  final int statusCode;
  final String message;
  final Map<String, Object?>? problem;

  bool get isConflict => statusCode == 409;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => 'ApiException($statusCode, $message)';
}

/// Only an adapter which can prove that no request bytes were handed to the
/// transport may use this exception. Socket/time-out failures are ambiguous.
final class ApiRequestNotSentException implements Exception {
  const ApiRequestNotSentException();
}

final class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bytes;

  Object? get jsonBody {
    if (bytes.isEmpty) return null;
    return jsonDecode(utf8.decode(bytes));
  }

  Map<String, Object?> get jsonObject {
    final body = jsonBody;
    if (body is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object response.');
    }
    return body;
  }
}

final class ApiClient implements AdminApi {
  factory ApiClient({
    required Uri baseUri,
    required http.Client httpClient,
    required AccessTokenProvider accessTokenProvider,
    required EnsureAccessTokenCallback ensureAccessToken,
    required AuthorizationLostCallback onAuthorizationLost,
    AuthorizationLostCallback? onResourceForbidden,
    int Function()? authorizationEpochProvider,
  }) => ApiClient._(
    baseUri,
    httpClient,
    accessTokenProvider,
    ensureAccessToken,
    onAuthorizationLost,
    onResourceForbidden,
    authorizationEpochProvider,
  );

  ApiClient._(
    this.baseUri,
    this._http,
    this._accessTokenProvider,
    this._ensureAccessToken,
    this._onAuthorizationLost,
    this._onResourceForbidden,
    this._authorizationEpochProvider,
  );

  final Uri baseUri;
  final http.Client _http;
  final AccessTokenProvider _accessTokenProvider;
  final EnsureAccessTokenCallback _ensureAccessToken;
  final AuthorizationLostCallback _onAuthorizationLost;
  final AuthorizationLostCallback? _onResourceForbidden;
  final int Function()? _authorizationEpochProvider;

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) => request('GET', path, query: query, headers: headers);

  @override
  Future<ApiResponse> post(
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) => request('POST', path, body: body, query: query, headers: headers);

  @override
  Future<ApiResponse> postPublic(
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final response = await _send(
      'POST',
      path,
      body: body,
      query: query,
      headers: headers,
      authenticated: false,
    );
    return _complete(response, authorizationRequired: false);
  }

  @override
  Future<ApiResponse> put(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => request('PUT', path, body: body, headers: headers);

  @override
  Future<ApiResponse> patch(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => request('PATCH', path, body: body, headers: headers);

  @override
  Future<ApiResponse> delete(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => request('DELETE', path, body: body, headers: headers);

  Future<ApiResponse> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final epoch = _authorizationEpochProvider?.call();
    if (!await _ensureAccessToken(force: false)) {
      // The session controller owns invalidation. A failed renewal may be a
      // temporary outage or an uncertain rotation, not revoked credentials.
      throw const ApiException(
        statusCode: 503,
        message: 'Session recovery is required before another request.',
        problem: <String, Object?>{
          'type': 'urn:providentia:session-recovery-required',
        },
      );
    }
    _checkEpoch(epoch);
    var response = await _send(
      method,
      path,
      body: body,
      query: query,
      headers: headers,
      authenticated: true,
    );
    _checkEpoch(epoch, response);
    if (response.statusCode == 401) {
      if (!await _ensureAccessToken(force: true)) {
        throw const ApiException(
          statusCode: 503,
          message: 'Session recovery is required before another request.',
          problem: <String, Object?>{
            'type': 'urn:providentia:session-recovery-required',
          },
        );
      }
      _checkEpoch(epoch, response);
      response = await _send(
        method,
        path,
        body: body,
        query: query,
        headers: headers,
        authenticated: true,
      );
    }
    _checkEpoch(epoch, response);
    return _complete(response, authorizationRequired: true);
  }

  void _checkEpoch(int? expected, [ApiResponse? response]) {
    if (expected != _authorizationEpochProvider?.call()) {
      response?.bytes.fillRange(0, response.bytes.length, 0);
      throw const ApiException(
        statusCode: 409,
        message:
            'Access changed while the request was in flight. Reload the page.',
        problem: <String, Object?>{
          'type': 'urn:providentia:authorization-changed',
        },
      );
    }
  }

  Future<ApiResponse> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    required bool authenticated,
  }) async {
    final token = authenticated ? _accessTokenProvider() : null;
    late final http.Request request;
    try {
      final uri = baseUri
          .resolve(path)
          .replace(
            queryParameters: query == null || query.isEmpty ? null : query,
          );
      if (uri.scheme != baseUri.scheme ||
          uri.host != baseUri.host ||
          uri.port != baseUri.port ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('The request origin is not the backend.');
      }
      request = http.Request(method, uri);
      request.headers.addAll(<String, String>{
        'Accept': 'application/json',
        'X-Request-ID': newUuidV4(),
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        ...?headers,
      });
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
    } on Object {
      throw const ApiRequestNotSentException();
    }

    final streamed = await _http.send(request);
    final declaredLength = streamed.contentLength;
    if (declaredLength != null && declaredLength > _maximumResponseBytes) {
      throw const FormatException(
        'The server response exceeded the safety limit.',
      );
    }
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in streamed.stream) {
      received += chunk.length;
      if (received > _maximumResponseBytes) {
        throw const FormatException(
          'The server response exceeded the safety limit.',
        );
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    return ApiResponse(
      statusCode: streamed.statusCode,
      headers: streamed.headers,
      bytes: bytes,
    );
  }

  ApiResponse _complete(
    ApiResponse response, {
    required bool authorizationRequired,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    if (authorizationRequired && response.statusCode == 401) {
      _onAuthorizationLost();
    } else if (authorizationRequired && response.statusCode == 403) {
      _onResourceForbidden?.call();
    }
    Map<String, Object?>? problem;
    try {
      final decoded = response.jsonBody;
      if (decoded is Map<String, Object?>) problem = decoded;
    } on FormatException {
      // The status and generic message remain authoritative for non-JSON errors.
    }
    // Only a contract discriminator and a redacted correlation ID may escape
    // the transport. Backend detail/title text can contain private payloads.
    final typeValue = problem?['type'];
    final type = typeValue is String && _problemType.hasMatch(typeValue)
        ? typeValue
        : 'about:blank';
    final requestValue = problem?['requestId'];
    final requestId =
        requestValue is String && _requestIdentity.hasMatch(requestValue)
        ? requestValue
        : null;
    throw ApiException(
      statusCode: response.statusCode,
      message: _safeProblemMessage(response.statusCode, type),
      problem: <String, Object?>{
        'type': type,
        'status': response.statusCode,
        'requestId': ?requestId,
      },
    );
  }

  static final RegExp _problemType = RegExp(
    r'^urn:providentia:[a-z][a-z0-9-]{0,80}$',
  );
  static final RegExp _requestIdentity = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String _safeProblemMessage(int status, String type) {
    if (type == 'urn:providentia:stale-revision') {
      return 'Reload the current revision before trying again.';
    }
    return switch (status) {
      401 => 'Sign in again to continue.',
      403 =>
        'You no longer have permission for this action. Refresh permissions.',
      404 =>
        'The requested record is unavailable or you no longer have access.',
      409 =>
        'This action conflicts with the current state. Reload and resolve the conflict.',
      400 || 422 => 'Review the submitted values before trying again.',
      413 => 'The request is too large. Choose a smaller input.',
      429 => 'Too many requests. Retry after the waiting period.',
      >= 500 => 'The service is temporarily unavailable. Retry the connection.',
      _ => 'The server rejected the request. Reload before trying again.',
    };
  }

  void close() => _http.close();
}
