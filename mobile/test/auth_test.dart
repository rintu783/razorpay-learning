import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:razorpay_demo/auth/api_client.dart';
import 'package:razorpay_demo/auth/auth_service.dart';

/// A fake backend. `handler` decides the response; every request is recorded.
class FakeServer {
  final List<http.BaseRequest> requests = [];
  Future<http.Response> Function(http.BaseRequest req) handler;
  FakeServer(this.handler);

  MockClient get client => MockClient.streaming((req, body) async {
        requests.add(req);
        final res = await handler(req);
        return http.StreamedResponse(Stream.value(res.bodyBytes), res.statusCode, headers: res.headers);
      });

  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path).length;
}

http.Response json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> token(String t) => {'access_token': t, 'token_type': 'bearer', 'expires_in': 900};

void main() {
  group('ApiClient', () {
    test('sends no Authorization header before login, and a Bearer header after', () async {
      final server = FakeServer((_) async => json(200, {}));
      final api = ApiClient(client: server.client, baseUrl: 'http://api');
      await api.get('/a');
      api.setAccessToken('tok1');
      await api.get('/b');
      expect(server.requests[0].headers.containsKey('Authorization'), isFalse);
      expect(server.requests[1].headers['Authorization'], 'Bearer tok1');
    });

    test('on 401 it refreshes once and retries with the new token', () async {
      final server = FakeServer((req) async {
        if (req.url.path == '/auth/refresh') return json(200, token('new'));
        return req.headers['Authorization'] == 'Bearer new' ? json(200, {'ok': true}) : json(401, {'detail': 'Not authenticated'});
      });
      final api = ApiClient(client: server.client, baseUrl: 'http://api')..setAccessToken('old');
      final res = await api.post('/subscriptions/checkout', body: {'plan_id': 'pro'});
      expect(res.statusCode, 200);
      expect(server.count('POST', '/auth/refresh'), 1);
      expect(server.count('POST', '/subscriptions/checkout'), 2); // rejected once, then repeated
      final retry = server.requests.last as http.Request;
      expect(retry.body, jsonEncode({'plan_id': 'pro'})); // the body survives the retry
    });

    test('many requests failing at once share a single refresh call', () async {
      final server = FakeServer((req) async {
        if (req.url.path == '/auth/refresh') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return json(200, token('new'));
        }
        return req.headers['Authorization'] == 'Bearer new' ? json(200, {}) : json(401, {});
      });
      final api = ApiClient(client: server.client, baseUrl: 'http://api')..setAccessToken('old');
      final results = await Future.wait([api.get('/a'), api.get('/b'), api.get('/c')]);
      expect(results.map((r) => r.statusCode), [200, 200, 200]);
      expect(server.count('POST', '/auth/refresh'), 1);
    });

    test('a request that was already in flight during a refresh retries without refreshing again', () async {
      var refreshes = 0;
      final server = FakeServer((req) async {
        if (req.url.path == '/auth/refresh') {
          refreshes++;
          return json(200, token('new'));
        }
        if (req.url.path == '/slow') await Future<void>.delayed(const Duration(milliseconds: 50));
        return req.headers['Authorization'] == 'Bearer new' ? json(200, {}) : json(401, {});
      });
      final api = ApiClient(client: server.client, baseUrl: 'http://api')..setAccessToken('old');
      final slow = api.get('/slow'); // sent with the old token, answered 401 after the refresh finished
      await api.get('/fast');
      expect((await slow).statusCode, 200);
      expect(refreshes, 1);
    });

    test('when the refresh is rejected it reports an expired session and returns the 401', () async {
      final server = FakeServer((req) async => json(401, {'detail': 'x'}));
      var expired = 0;
      final api = ApiClient(client: server.client, baseUrl: 'http://api')
        ..setAccessToken('old')
        ..onSessionExpired = () => expired++;
      final res = await api.get('/users/me');
      expect(res.statusCode, 401);
      expect(expired, 1);
      await api.get('/users/me'); // the dead token is gone
      expect(server.requests.last.headers.containsKey('Authorization'), isFalse);
    });

    test('a server error during refresh throws and does NOT log the user out', () async {
      final server = FakeServer((req) async => req.url.path == '/auth/refresh' ? json(500, {}) : json(401, {}));
      var expired = 0;
      final api = ApiClient(client: server.client, baseUrl: 'http://api')
        ..setAccessToken('old')
        ..onSessionExpired = () => expired++;
      await expectLater(api.get('/users/me'), throwsA(isA<ApiException>()));
      expect(expired, 0);
    });

    test('unauthenticated calls (login) never trigger a refresh', () async {
      final server = FakeServer((_) async => json(401, {'detail': 'Invalid email or password'}));
      final api = ApiClient(client: server.client, baseUrl: 'http://api');
      final res = await api.post('/auth/login', body: {}, authenticated: false);
      expect(res.statusCode, 401);
      expect(server.count('POST', '/auth/refresh'), 0);
    });

    test('network failures become a readable ApiException', () async {
      final api = ApiClient(client: MockClient((_) async => throw http.ClientException('boom')), baseUrl: 'http://api');
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Cannot reach'))));
    });

    test('errorMessage understands strings, validation lists and rate limits', () {
      expect(ApiClient.errorMessage(json(409, {'detail': 'Email already registered'})), 'Email already registered');
      expect(
        ApiClient.errorMessage(json(422, {'detail': [{'loc': ['body', 'email'], 'msg': 'bad'}]})),
        'Enter a valid email address.',
      );
      expect(
        ApiClient.errorMessage(json(422, {'detail': [{'loc': ['body', 'password'], 'msg': 'bad'}]})),
        contains('8 to 128'),
      );
      expect(ApiClient.errorMessage(json(429, {'detail': 'x'})), contains('Too many attempts'));
      expect(ApiClient.errorMessage(http.Response('not json', 500)), contains('Something went wrong'));
    });
  });

  group('AuthService', () {
    late FakeServer server;
    late ApiClient api;
    late AuthService auth;

    setUp(() {
      server = FakeServer((_) async => json(404, {}));
      api = ApiClient(client: server.client, baseUrl: 'http://api');
      auth = AuthService(api);
    });

    test('starts in the unknown state', () => expect(auth.status.value, AuthStatus.unknown));

    test('login stores the token in memory and signs in', () async {
      server.handler = (req) async => req.url.path == '/auth/login'
          ? json(200, token('t1'))
          : (req.headers['Authorization'] == 'Bearer t1' ? json(200, {'email': 'a@b.com'}) : json(401, {}));
      await auth.login('  a@b.com ', 'password123');
      expect(auth.status.value, AuthStatus.signedIn);
      final login = server.requests.first as http.Request;
      expect(jsonDecode(login.body), {'email': 'a@b.com', 'password': 'password123'}); // email trimmed
      expect((await api.get('/users/me')).statusCode, 200); // the token is used afterwards
    });

    test('register expects 201 and signs in', () async {
      server.handler = (_) async => json(201, token('t2'));
      await auth.register('a@b.com', 'password123');
      expect(auth.status.value, AuthStatus.signedIn);
      expect(server.requests.single.url.path, '/auth/register');
    });

    test('wrong password throws the server message and stays signed out', () async {
      server.handler = (_) async => json(401, {'detail': 'Invalid email or password'});
      await expectLater(
        auth.login('a@b.com', 'nope'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Invalid email or password')),
      );
      expect(auth.status.value, AuthStatus.unknown);
      expect(server.count('POST', '/auth/refresh'), 0);
    });

    test('duplicate email on register shows the server message', () async {
      server.handler = (_) async => json(409, {'detail': 'Email already registered'});
      await expectLater(auth.register('a@b.com', 'password123'), throwsA(isA<ApiException>()));
    });

    test('restoreSession signs in when the cookie is valid', () async {
      server.handler = (_) async => json(200, token('t3'));
      await auth.restoreSession();
      expect(auth.status.value, AuthStatus.signedIn);
    });

    test('restoreSession signs out when there is no valid cookie', () async {
      server.handler = (_) async => json(401, {'detail': 'Session expired, please log in again'});
      await auth.restoreSession();
      expect(auth.status.value, AuthStatus.signedOut);
    });

    test('restoreSession signs out (no crash) when the server is down', () async {
      server.handler = (_) async => throw http.ClientException('down');
      await auth.restoreSession();
      expect(auth.status.value, AuthStatus.signedOut);
    });

    test('logout calls the server, drops the token and signs out', () async {
      server.handler = (req) async => req.url.path == '/auth/login' ? json(200, token('t4')) : http.Response('', 204);
      await auth.login('a@b.com', 'password123');
      await auth.logout();
      expect(auth.status.value, AuthStatus.signedOut);
      expect(server.count('POST', '/auth/logout'), 1);
      await api.get('/anything');
      expect(server.requests.last.headers.containsKey('Authorization'), isFalse);
    });

    test('logout still signs out locally when the server is unreachable', () async {
      server.handler = (req) async => req.url.path == '/auth/login' ? json(200, token('t5')) : throw http.ClientException('down');
      await auth.login('a@b.com', 'password123');
      await auth.logout();
      expect(auth.status.value, AuthStatus.signedOut);
    });

    test('an expired session elsewhere in the app signs the user out', () async {
      server.handler = (req) async => req.url.path == '/auth/login' ? json(200, token('t6')) : json(401, {});
      await auth.login('a@b.com', 'password123');
      await api.get('/users/me'); // 401, refresh 401 -> session expired
      expect(auth.status.value, AuthStatus.signedOut);
    });
  });
}
