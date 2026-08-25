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
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'ApiException($statusCode, $message)';
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
  }) => ApiClient._(
    baseUri,
    httpClient,
    accessTokenProvider,
    ensureAccessToken,
    onAuthorizationLost,
  );

  ApiClient._(
    this.baseUri,
    this._http,
    this._accessTokenProvider,
    this._ensureAccessToken,
    this._onAuthorizationLost,
  );

  final Uri baseUri;
  final http.Client _http;
  final AccessTokenProvider _accessTokenProvider;
  final EnsureAccessTokenCallback _ensureAccessToken;
  final AuthorizationLostCallback _onAuthorizationLost;

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
    if (!await _ensureAccessToken(force: false)) {
      _onAuthorizationLost();
      throw const ApiException(
        statusCode: 401,
        message: 'The administrator session must be renewed.',
      );
    }
    var response = await _send(
      method,
      path,
      body: body,
      query: query,
      headers: headers,
      authenticated: true,
    );
    if (response.statusCode == 401 && await _ensureAccessToken(force: true)) {
      response = await _send(
        method,
        path,
        body: body,
        query: query,
        headers: headers,
        authenticated: true,
      );
    }
    return _complete(response, authorizationRequired: true);
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
    final uri = baseUri
        .resolve(path)
        .replace(
          queryParameters: query == null || query.isEmpty ? null : query,
        );
    final request = http.Request(method, uri);
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

    if (authorizationRequired &&
        (response.statusCode == 401 || response.statusCode == 403)) {
      _onAuthorizationLost();
    }
    Map<String, Object?>? problem;
    try {
      final decoded = response.jsonBody;
      if (decoded is Map<String, Object?>) problem = decoded;
    } on FormatException {
      // The status and generic message remain authoritative for non-JSON errors.
    }
    final detail = problem?['detail'];
    final title = problem?['title'];
    throw ApiException(
      statusCode: response.statusCode,
      message: detail is String
          ? detail
          : title is String
          ? title
          : 'The server rejected the request.',
      problem: problem,
    );
  }

  void close() => _http.close();
}
