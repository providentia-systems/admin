import 'dart:convert';
import 'dart:typed_data';

import 'package:providentia_admin/core/api/api_client.dart';

final class RecordedRequest {
  const RecordedRequest({
    required this.method,
    required this.path,
    this.body,
    this.query,
    this.headers,
  });

  final String method;
  final String path;
  final Object? body;
  final Map<String, String>? query;
  final Map<String, String>? headers;
}

typedef FakeHandler = Future<ApiResponse> Function(RecordedRequest request);

final class FakeApi implements AdminApi {
  FakeApi(this.handler);

  final FakeHandler handler;
  final List<RecordedRequest> requests = <RecordedRequest>[];

  @override
  Future<ApiResponse> delete(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => _send('DELETE', path, body: body, headers: headers);

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) => _send('GET', path, query: query, headers: headers);

  @override
  Future<ApiResponse> patch(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => _send('PATCH', path, body: body, headers: headers);

  @override
  Future<ApiResponse> post(
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) => _send('POST', path, body: body, query: query, headers: headers);

  @override
  Future<ApiResponse> postPublic(
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) => _send('POST', path, body: body, query: query, headers: headers);

  @override
  Future<ApiResponse> put(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => _send('PUT', path, body: body, headers: headers);

  Future<ApiResponse> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final request = RecordedRequest(
      method: method,
      path: path,
      body: body,
      query: query,
      headers: headers,
    );
    requests.add(request);
    return handler(request);
  }
}

ApiResponse jsonResponse(Map<String, Object?> body, {int status = 200}) =>
    ApiResponse(
      statusCode: status,
      headers: const <String, String>{'content-type': 'application/json'},
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );
