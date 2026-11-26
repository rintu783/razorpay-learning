import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// An error with a message that is safe to show to the user.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// The one place that talks to the backend.
///
/// - Keeps the short-lived access token in memory only (never in localStorage), so a page reload
///   starts without it and gets a new one from the HttpOnly refresh cookie.
/// - Adds `Authorization: Bearer <token>` to every request.
/// - On a 401 it refreshes the session once and retries the request. When many requests fail at
///   the same moment, they share a single refresh call. The server rotates refresh tokens, so two
///   parallel refreshes would otherwise look like token theft.
///
/// This file has no browser imports so it can be unit tested. `main()` creates [instance] with a
/// browser client that has `withCredentials = true`, which makes the browser send the refresh cookie.
class ApiClient {
  ApiClient({required http.Client client, String? baseUrl, this.timeout = const Duration(seconds: 20)})
      // ignore: prefer_initializing_formals (a named parameter cannot be private)
      : _client = client,
        baseUrl = baseUrl ?? defaultBaseUrl;

  /// Override at build time: `flutter build web --dart-define=API_BASE_URL=https://api.example.com`
  static const defaultBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

  /// Set once in main().
  static late ApiClient instance;

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  String? _accessToken;
  Future<bool>? _refreshing;

  /// Called when the session can no longer be restored (the refresh cookie is missing or rejected).
  void Function()? onSessionExpired;

  void setAccessToken(String? token) => _accessToken = token;

  Future<http.Response> get(String path) => _request('GET', path);

  Future<http.Response> post(String path, {Object? body, bool authenticated = true}) =>
      _request('POST', path, body: body, authenticated: authenticated);

  Future<http.Response> patch(String path, {Object? body}) => _request('PATCH', path, body: body);

  /// Gets a new access token using the refresh cookie. Resolves to false when the user must log in
  /// again, and throws [ApiException] when the server cannot be reached (so we do not log out on a
  /// network blip). Concurrent calls share one request.
  Future<bool> refreshSession() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final res = await _send('POST', '/auth/refresh', null, false);
    if (res.statusCode == 200) {
      _accessToken = (jsonDecode(res.body) as Map<String, dynamic>)['access_token'] as String;
      return true;
    }
    if (res.statusCode == 401) {
      _accessToken = null;
      return false;
    }
    throw ApiException('Could not restore your session (${res.statusCode}). Please try again.', res.statusCode);
  }

  Future<http.Response> _request(String method, String path, {Object? body, bool authenticated = true}) async {
    final tokenUsed = _accessToken;
    final res = await _send(method, path, body, authenticated);
    if (res.statusCode != 401 || !authenticated) return res;

    // Another request may already have refreshed while this one was in flight.
    final alreadyRefreshed = _accessToken != null && _accessToken != tokenUsed;
    if (!alreadyRefreshed && !await refreshSession()) {
      onSessionExpired?.call();
      return res;
    }
    return _send(method, path, body, authenticated); // the first attempt was rejected, so it is safe to repeat
  }

  Future<http.Response> _send(String method, String path, Object? body, bool authenticated) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final token = _accessToken;
    if (authenticated && token != null) req.headers['Authorization'] = 'Bearer $token';
    try {
      final streamed = await _client.send(req).timeout(timeout);
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException('The server took too long to respond. Please try again.');
    } on http.ClientException {
      throw ApiException('Cannot reach the server. Check your connection and try again.');
    }
  }

  /// A readable message from an error response. Understands FastAPI's `detail` as a string or as a
  /// list of validation errors.
  static String errorMessage(http.Response res, {String fallback = 'Something went wrong. Please try again.'}) {
    if (res.statusCode == 429) return 'Too many attempts. Please wait a minute and try again.';
    try {
      final detail = (jsonDecode(res.body) as Map<String, dynamic>)['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final loc = (detail.first['loc'] as List?)?.last;
        if (loc == 'email') return 'Enter a valid email address.';
        if (loc == 'password') return 'Password must be 8 to 128 characters.';
        if (loc == 'phone') return 'Enter a valid phone number (7 to 30 digits, spaces, + or -).';
        if (loc == 'first_name' || loc == 'last_name') return 'Names can be at most 60 characters.';
        return '${detail.first['msg'] ?? fallback}';
      }
    } catch (_) {}
    return fallback;
  }
}
