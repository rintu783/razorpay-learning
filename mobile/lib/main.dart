import 'package:flutter/material.dart';
import 'package:http/browser_client.dart';

import 'auth/api_client.dart';
import 'auth/auth_gate.dart';
import 'auth/auth_service.dart';
import 'home/home_screen.dart';

void main() {
  // withCredentials makes the browser send the HttpOnly refresh cookie to the API (different origin).
  ApiClient.instance = ApiClient(client: BrowserClient()..withCredentials = true);
  AuthService.instance = AuthService(ApiClient.instance);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Whiskr',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: AuthGate(signedIn: (_) => const HomeScreen()),
    );
  }
}
