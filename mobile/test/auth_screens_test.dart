import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:razorpay_demo/auth/api_client.dart';
import 'package:razorpay_demo/auth/auth_gate.dart';
import 'package:razorpay_demo/auth/auth_screen.dart';
import 'package:razorpay_demo/auth/auth_service.dart';
import 'package:razorpay_demo/users/edit_profile_screen.dart';
import 'package:razorpay_demo/users/user_service.dart';

http.Response json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> token(String t) => {'access_token': t, 'token_type': 'bearer', 'expires_in': 900};

class Backend {
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request req) handler = (_) async => json(404, {});

  void install() {
    final client = MockClient.streaming((req, body) async {
      final r = req as http.Request;
      requests.add(r);
      final res = await handler(r);
      return http.StreamedResponse(Stream.value(res.bodyBytes), res.statusCode, headers: res.headers);
    });
    ApiClient.instance = ApiClient(client: client, baseUrl: 'http://api');
    AuthService.instance = AuthService(ApiClient.instance);
  }

  List<http.Request> to(String path) => requests.where((r) => r.url.path == path).toList();
}

Widget app(Widget home) => MaterialApp(home: home);

Future<void> typeInto(WidgetTester t, String label, String text) async {
  await t.enterText(find.widgetWithText(TextFormField, label), text);
}

void main() {
  late Backend backend;
  setUp(() {
    backend = Backend()..install();
  });

  group('AuthScreen', () {
    testWidgets('shows login by default and switches to register', (t) async {
      await t.pumpWidget(app(const AuthScreen()));
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);
      await t.tap(find.text('New here? Create an account'));
      await t.pump();
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('At least 8 characters'), findsOneWidget);
    });

    testWidgets('empty and invalid input is rejected without calling the server', (t) async {
      await t.pumpWidget(app(const AuthScreen()));
      await t.tap(find.text('Log in'));
      await t.pump();
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);

      await typeInto(t, 'Email', 'not-an-email');
      await t.tap(find.text('Log in'));
      await t.pump();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(backend.requests, isEmpty);
    });

    testWidgets('register enforces the 8 character minimum, login does not', (t) async {
      await t.pumpWidget(app(const AuthScreen()));
      await typeInto(t, 'Email', 'a@b.com');
      await typeInto(t, 'Password', 'short');
      await t.tap(find.text('New here? Create an account'));
      await t.pump();
      await typeInto(t, 'Email', 'a@b.com');
      await typeInto(t, 'Password', 'short');
      await t.tap(find.text('Create account'));
      await t.pump();
      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(backend.requests, isEmpty);
    });

    testWidgets('successful login posts the credentials and signs in', (t) async {
      backend.handler = (_) async => json(200, token('t1'));
      await t.pumpWidget(app(const AuthScreen()));
      await typeInto(t, 'Email', ' me@example.com ');
      await typeInto(t, 'Password', 'my-password-1');
      await t.tap(find.text('Log in'));
      await t.pumpAndSettle();
      expect(jsonDecode(backend.to('/auth/login').single.body), {'email': 'me@example.com', 'password': 'my-password-1'});
      expect(AuthService.instance.status.value, AuthStatus.signedIn);
    });

    testWidgets('submitting with the Enter key works', (t) async {
      backend.handler = (_) async => json(200, token('t1'));
      await t.pumpWidget(app(const AuthScreen()));
      await typeInto(t, 'Email', 'me@example.com');
      await typeInto(t, 'Password', 'my-password-1');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(backend.to('/auth/login'), hasLength(1));
    });

    testWidgets('wrong password shows the server message and stays on the screen', (t) async {
      backend.handler = (_) async => json(401, {'detail': 'Invalid email or password'});
      await t.pumpWidget(app(const AuthScreen()));
      await typeInto(t, 'Email', 'me@example.com');
      await typeInto(t, 'Password', 'wrong-password');
      await t.tap(find.text('Log in'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('auth-error')), findsOneWidget);
      expect(find.text('Invalid email or password'), findsOneWidget);
      expect(AuthService.instance.status.value, isNot(AuthStatus.signedIn));
      expect(backend.to('/auth/refresh'), isEmpty);
    });

    testWidgets('register posts to /auth/register and shows "already registered"', (t) async {
      backend.handler = (_) async => json(409, {'detail': 'Email already registered'});
      await t.pumpWidget(app(const AuthScreen()));
      await t.tap(find.text('New here? Create an account'));
      await t.pump();
      await typeInto(t, 'Email', 'me@example.com');
      await typeInto(t, 'Password', 'my-password-1');
      await t.tap(find.text('Create account'));
      await t.pumpAndSettle();
      expect(backend.to('/auth/register'), hasLength(1));
      expect(find.text('Email already registered'), findsOneWidget);
    });

    testWidgets('a server that is down shows a readable error', (t) async {
      backend.handler = (_) async => throw http.ClientException('down');
      await t.pumpWidget(app(const AuthScreen()));
      await typeInto(t, 'Email', 'me@example.com');
      await typeInto(t, 'Password', 'my-password-1');
      await t.tap(find.text('Log in'));
      await t.pumpAndSettle();
      expect(find.textContaining('Cannot reach the server'), findsOneWidget);
    });

    testWidgets('the password is hidden until the eye button is pressed', (t) async {
      await t.pumpWidget(app(const AuthScreen()));
      bool obscured() => t.widget<EditableText>(find.descendant(
              of: find.widgetWithText(TextFormField, 'Password'), matching: find.byType(EditableText)))
          .obscureText;
      expect(obscured(), isTrue);
      await t.tap(find.byTooltip('Show password'));
      await t.pump();
      expect(obscured(), isFalse);
    });

    testWidgets('the button is disabled while the request is running (no double submit)', (t) async {
      final gate = Future<void>.delayed(const Duration(milliseconds: 200));
      backend.handler = (_) async {
        await gate;
        return json(200, token('t1'));
      };
      await t.pumpWidget(app(const AuthScreen()));
      await typeInto(t, 'Email', 'me@example.com');
      await typeInto(t, 'Password', 'my-password-1');
      await t.tap(find.text('Log in'));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await t.pumpAndSettle();
      expect(backend.to('/auth/login'), hasLength(1));
    });
  });

  group('AuthGate', () {
    Widget gate() => app(AuthGate(signedIn: (_) => const Scaffold(body: Text('APP HOME'))));

    testWidgets('shows a spinner while restoring, then the app when the cookie is valid', (t) async {
      backend.handler = (_) async => json(200, token('t1'));
      await t.pumpWidget(gate());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.text('APP HOME'), findsOneWidget);
      expect(backend.to('/auth/refresh'), hasLength(1));
    });

    testWidgets('shows the login screen when there is no valid session', (t) async {
      backend.handler = (_) async => json(401, {'detail': 'Session expired, please log in again'});
      await t.pumpWidget(gate());
      await t.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('APP HOME'), findsNothing);
    });

    testWidgets('logging in swaps the login screen for the app', (t) async {
      backend.handler = (req) async =>
          req.url.path == '/auth/refresh' ? json(401, {}) : json(200, token('t2'));
      await t.pumpWidget(gate());
      await t.pumpAndSettle();
      await typeInto(t, 'Email', 'me@example.com');
      await typeInto(t, 'Password', 'my-password-1');
      await t.tap(find.text('Log in'));
      await t.pumpAndSettle();
      expect(find.text('APP HOME'), findsOneWidget);
    });

    testWidgets('logout closes every open page and shows the login screen', (t) async {
      backend.handler = (req) async => req.url.path == '/auth/logout' ? http.Response('', 204) : json(200, token('t3'));
      await t.pumpWidget(app(AuthGate(
        signedIn: (_) => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const Scaffold(body: Text('DEEP PAGE'))),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await t.pumpAndSettle();
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('DEEP PAGE'), findsOneWidget);

      await AuthService.instance.logout();
      await t.pumpAndSettle();
      expect(find.text('DEEP PAGE'), findsNothing);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('a session the server rejects mid-use sends the user back to login', (t) async {
      backend.handler = (req) async => req.url.path == '/auth/refresh' && backend.to('/auth/refresh').length == 1
          ? json(200, token('t4'))
          : json(401, {});
      await t.pumpWidget(gate());
      await t.pumpAndSettle();
      expect(find.text('APP HOME'), findsOneWidget);
      await ApiClient.instance.get('/users/me'); // 401, then the refresh is rejected
      await t.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
    });
  });

  group('EditProfileScreen', () {
    final user = UserProfile('me@example.com', null, null, null);

    Future<void> open(WidgetTester t, {UserProfile? start, void Function(UserProfile?)? onResult}) async {
      await t.pumpWidget(app(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final saved = await Navigator.push<UserProfile>(
              context,
              MaterialPageRoute(builder: (_) => EditProfileScreen(user: start ?? user)),
            );
            onResult?.call(saved);
          },
          child: const Text('go'),
        ),
      )));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
    }

    testWidgets('prefills existing values and explains that email is fixed', (t) async {
      await open(t, start: UserProfile('me@example.com', 'Ann', 'Lee', '+91 98765 43210'));
      expect(find.widgetWithText(TextFormField, 'Ann'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '+91 98765 43210'), findsOneWidget);
      expect(find.textContaining('me@example.com'), findsOneWidget);
    });

    testWidgets('invalid phone is rejected before any request', (t) async {
      await open(t);
      await typeInto(t, 'Phone number', 'abc');
      await t.tap(find.text('Save'));
      await t.pump();
      expect(find.textContaining('Enter 7 to 30 digits'), findsOneWidget);
      expect(backend.requests, isEmpty);
    });

    testWidgets('save sends a PATCH and returns the updated profile', (t) async {
      ApiClient.instance.setAccessToken('tok');
      backend.handler = (_) async =>
          json(200, {'user_id': 'usr_1', 'email': 'me@example.com', 'first_name': 'Ann', 'last_name': 'Lee', 'phone': '+91 98765 43210'});
      UserProfile? result;
      await open(t, onResult: (u) => result = u);
      await typeInto(t, 'First name', ' Ann ');
      await typeInto(t, 'Last name', 'Lee');
      await typeInto(t, 'Phone number', '+91 98765 43210');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();

      final req = backend.to('/users/me').single;
      expect(req.method, 'PATCH');
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(req.body), {'first_name': 'Ann', 'last_name': 'Lee', 'phone': '+91 98765 43210'});
      expect(result?.fullName, 'Ann Lee');
      expect(find.text('Save'), findsNothing); // the screen closed
    });

    testWidgets('a server error is shown and the form stays open', (t) async {
      backend.handler = (_) async => json(422, {'detail': [{'loc': ['body', 'phone'], 'msg': 'bad'}]});
      await open(t);
      await typeInto(t, 'First name', 'Ann');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('profile-error')), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });
  });

  group('UserProfile', () {
    test('falls back to the email when no name is set', () {
      final p = UserProfile('zed@example.com', null, null, null);
      expect(p.fullName, '');
      expect(p.displayName, 'zed@example.com');
      expect(p.initials, 'Z');
    });

    test('uses name initials when set, and copes with one name only', () {
      expect(UserProfile('a@b.com', 'ann', 'lee', null).initials, 'AL');
      expect(UserProfile('a@b.com', 'Ann', null, null).displayName, 'Ann');
      expect(UserProfile('a@b.com', '', 'Lee', null).fullName, 'Lee');
    });
  });
}
