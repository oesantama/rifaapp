import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Holds the current session token and adds it to every API request.
class AuthSession {
  static String? token;

  /// Called when the server rejects the session (expired, password changed, account disabled).
  static VoidCallback? onUnauthorized;

  static Map<String, String> headers([Map<String, String>? extra]) => {
        if (token != null) 'Authorization': 'Bearer $token',
        ...?extra,
      };

  static http.Response _check(http.Response response) {
    if (response.statusCode == 401 && token != null) {
      onUnauthorized?.call();
    }
    return response;
  }
}

/// Error returned by the API with a user-facing message.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  factory ApiException.fromResponse(http.Response response) {
    String message = 'Error del servidor (${response.statusCode}).';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) message = body['error'];
    } catch (_) {}
    return ApiException(response.statusCode, message);
  }

  @override
  String toString() => message;
}

Future<http.Response> authGet(Uri url, {Map<String, String>? headers}) =>
    http.get(url, headers: AuthSession.headers(headers)).then(AuthSession._check);

Future<http.Response> authPost(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    http.post(url, headers: AuthSession.headers(headers), body: body, encoding: encoding).then(AuthSession._check);

Future<http.Response> authPut(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    http.put(url, headers: AuthSession.headers(headers), body: body, encoding: encoding).then(AuthSession._check);

Future<http.Response> authDelete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    http.delete(url, headers: AuthSession.headers(headers), body: body, encoding: encoding).then(AuthSession._check);
