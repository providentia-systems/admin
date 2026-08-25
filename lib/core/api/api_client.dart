import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

typedef AccessTokenProvider = String? Function();
typedef AuthorizationLostCallback = void Function();

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

final class ApiClient {
  ApiClient({
    required this.baseUri,
    required http.Client httpClient,
    required AccessTokenProvider accessTokenProvider,
    required AuthorizationLostCallback onAuthorizationLost,
  }) : _http = httpClient,
       _accessTokenProvider = accessTokenProvider,
       _onAuthorizationLost = onAuthorizationLost;

  final Uri baseUri;
  final http.Client _http;
  final AccessTokenProvider _accessTokenProvider;
  final AuthorizationLostCallback _onAuthorizationLost;
  static const _uuid = Uuid();

  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) => request('GET', path, query: query, headers: headers);

  Future<ApiResponse> post(
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) => request('POST', path, body: body, query: query, headers: headers);

  Future<ApiResponse> put(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => request('PUT', path, body: body, headers: headers);

  Future<ApiResponse> patch(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => request('PATCH', path, body: body, headers: headers);

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
    final token = _accessTokenProvider();
    final uri = baseUri.resolve(path).replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final request = http.Request(method, uri);
    request.headers.addAll(<String, String>{
      'Accept': 'application/json',
      'X-Request-ID': _uuid.v4(),
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      ...?headers,
    });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final streamed = await _http.send(request);
    final bytes = await streamed.stream.toBytes();
    final response = ApiResponse(
      statusCode: streamed.statusCode,
      headers: streamed.headers,
      bytes: bytes,
    );
    if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
      return response;
    }

    if (streamed.statusCode == 401 || streamed.statusCode == 403) {
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
      statusCode: streamed.statusCode,
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

