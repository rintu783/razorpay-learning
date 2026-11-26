import 'package:flutter/material.dart';

import 'auth_screen.dart';
import 'auth_service.dart';

/// Decides what the user sees: a splash while the session is being restored, the login/register
/// screen when signed out, and the app ([signedIn]) when signed in.
///
/// [signedIn] is passed in (instead of importing the home screen) so this file stays free of
/// browser-only code and can be tested without a browser.
class AuthGate extends StatefulWidget {
  final WidgetBuilder signedIn;
  const AuthGate({super.key, required this.signedIn});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService.instance;

  @override
  void initState() {
    super.initState();
    _auth.status.addListener(_onStatusChanged);
    if (_auth.status.value == AuthStatus.unknown) _auth.restoreSession();
  }

  @override
  void dispose() {
    _auth.status.removeListener(_onStatusChanged);
    super.dispose();
  }

  /// Pages the user opened (Account, Billing, dialogs) sit on top of this gate. When the session ends
  /// (logout, or the server rejecting the refresh token), close them all so the login screen shows.
  void _onStatusChanged() {
    if (_auth.status.value == AuthStatus.signedOut && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthStatus>(
      valueListenable: _auth.status,
      builder: (context, status, _) => switch (status) {
        AuthStatus.unknown => const _Splash(),
        AuthStatus.signedOut => const AuthScreen(),
        AuthStatus.signedIn => widget.signedIn(context),
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
