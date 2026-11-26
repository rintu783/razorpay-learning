import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

enum AuthStatus {
  /// App just started; we have not yet tried to restore a session.
  unknown,
  signedOut,
  signedIn,
}

/// Register, login, logout and session restore. The UI listens to [status].
class AuthService {
  AuthService(this._api) {
    _api.onSessionExpired = () => status.value = AuthStatus.signedOut;
  }

  /// Set once in main().
  static late AuthService instance;

  final ApiClient _api;
  final ValueNotifier<AuthStatus> status = ValueNotifier(AuthStatus.unknown);

  /// Call at app start. The browser sends the HttpOnly refresh cookie, so a returning user gets a
  /// new access token without typing a password.
  Future<void> restoreSession() async {
    try {
      status.value = await _api.refreshSession() ? AuthStatus.signedIn : AuthStatus.signedOut;
    } on ApiException {
      status.value = AuthStatus.signedOut; // server unreachable: the login screen will show the error
    }
  }

  Future<void> register(String email, String password) => _authenticate('/auth/register', email, password, 201);

  Future<void> login(String email, String password) => _authenticate('/auth/login', email, password, 200);

  Future<void> _authenticate(String path, String email, String password, int okStatus) async {
    final res = await _api.post(
      path,
      body: {'email': email.trim(), 'password': password},
      authenticated: false, // a 401 here means "wrong password", not "session expired"
    );
    if (res.statusCode != okStatus) {
      throw ApiException(ApiClient.errorMessage(res), res.statusCode);
    }
    _api.setAccessToken((jsonDecode(res.body) as Map<String, dynamic>)['access_token'] as String);
    status.value = AuthStatus.signedIn;
  }

  /// Always ends signed out on this device, even if the server cannot be reached.
  Future<void> logout() async {
    try {
      await _api.post('/auth/logout', authenticated: false);
    } on ApiException {
      // The cookie could not be cleared server-side. The local session still ends below.
    }
    _api.setAccessToken(null);
    status.value = AuthStatus.signedOut;
  }
}
