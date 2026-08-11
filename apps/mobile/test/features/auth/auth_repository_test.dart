import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/api/perennia_api_client.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';

void main() {
  test('email sign-in routes to a custom server URL and stores token securely',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('perennia-auth-test-');
    addTearDown(() async => tempDir.delete(recursive: true));
    final authFile = File('${tempDir.path}/auth.json');
    final tokenStore = _FakeAuthSessionTokenStore();
    final seenRequests = <http.Request>[];
    final repository = FileAuthRepository(
      authFile: () async => authFile,
      tokenStore: tokenStore,
      apiClientFactory: (baseUrl) {
        expect(baseUrl.toString(), 'https://self.example/');
        return PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            seenRequests.add(request);
            return http.Response(
              jsonEncode(_sessionResponse('lifter@example.com')),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        );
      },
    );

    final session = await repository.signInWithEmail(
      serverUrl: Uri.parse('https://self.example'),
      email: 'lifter@example.com',
      password: 'secret',
    );
    final persisted = await repository.load();
    final persistedJson = await authFile.readAsString();

    expect(session.userEmail, 'lifter@example.com');
    expect(session.provider, AuthSessionProvider.email);
    expect(persisted.session?.token, 'session-token');
    expect(tokenStore.token, 'session-token');
    expect(persistedJson, isNot(contains('session-token')));
    expect(persisted.serverUrl.toString(), 'https://self.example/');
    expect(
      seenRequests.single.url.toString(),
      'https://self.example/api/auth/sign-in/email',
    );
    expect(jsonDecode(seenRequests.single.body), <String, Object?>{
      'email': 'lifter@example.com',
      'password': 'secret',
      'callbackURL': 'https://self.example/auth/verified',
    });
  });

  test('social sign-in uses provider id token against the selected server',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('perennia-social-test-');
    addTearDown(() async => tempDir.delete(recursive: true));
    final tokenStore = _FakeAuthSessionTokenStore();
    final seenBodies = <Map<String, Object?>>[];
    final repository = FileAuthRepository(
      authFile: () async => File('${tempDir.path}/auth.json'),
      tokenStore: tokenStore,
      socialIdTokenProvider: const _FakeSocialIdTokenProvider(),
      apiClientFactory: (baseUrl) {
        expect(baseUrl.toString(), 'https://staging.example/');
        return PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            seenBodies.add(jsonDecode(request.body) as Map<String, Object?>);
            return http.Response(
              jsonEncode(_sessionResponse('google@example.com')),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        );
      },
    );

    final session = await repository.signInWithSocial(
      serverUrl: Uri.parse('https://staging.example'),
      provider: AuthSocialProvider.google,
    );

    expect(session.provider, AuthSessionProvider.google);
    expect(session.userEmail, 'google@example.com');
    expect(tokenStore.token, 'session-token');
    expect(seenBodies.single['provider'], 'google');
    expect(seenBodies.single['disableRedirect'], true);
    expect(seenBodies.single['idToken'], <String, Object?>{
      'token': 'google-id-token',
    });
  });

  test('social sign-in maps missing auth routes to a server URL error',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('perennia-social-404-test-');
    addTearDown(() async => tempDir.delete(recursive: true));
    final repository = FileAuthRepository(
      authFile: () async => File('${tempDir.path}/auth.json'),
      tokenStore: _FakeAuthSessionTokenStore(),
      socialIdTokenProvider: const _FakeSocialIdTokenProvider(),
      apiClientFactory: (baseUrl) {
        return PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            return http.Response('', 404);
          }),
        );
      },
    );

    await expectLater(
      repository.signInWithSocial(
        serverUrl: Uri.parse('https://missing.example'),
        provider: AuthSocialProvider.google,
      ),
      throwsA(
        isA<AuthException>()
            .having(
              (error) => error.code,
              'code',
              AuthFailureCode.unavailable,
            )
            .having(
              (error) => error.message,
              'message',
              'Server URL does not look like a Perennia server.',
            ),
      ),
    );
  });

  test('email sign-up posts to the selected server and waits for verification',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('perennia-signup-test-');
    addTearDown(() async => tempDir.delete(recursive: true));
    final tokenStore = _FakeAuthSessionTokenStore();
    final seenRequests = <http.Request>[];
    final repository = FileAuthRepository(
      authFile: () async => File('${tempDir.path}/auth.json'),
      tokenStore: tokenStore,
      apiClientFactory: (baseUrl) {
        expect(baseUrl.toString(), 'https://self.example/');
        return PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            seenRequests.add(request);
            return http.Response(
              jsonEncode(_signUpResponse('qa@example.test')),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        );
      },
    );

    final outcome = await repository.signUpWithEmail(
      serverUrl: Uri.parse('https://self.example'),
      name: 'QA Lifter',
      email: 'qa@example.test',
      password: 'correct horse battery staple',
    );
    final persisted = await repository.load();

    expect(outcome.requiresEmailVerification, isTrue);
    expect(outcome.userEmail, 'qa@example.test');
    expect(outcome.session, isNull);
    expect(tokenStore.token, isNull);
    expect(persisted.serverUrl.toString(), 'https://self.example/');
    expect(persisted.session, isNull);
    expect(
      seenRequests.single.url.toString(),
      'https://self.example/api/auth/sign-up/email',
    );
    expect(jsonDecode(seenRequests.single.body), <String, Object?>{
      'name': 'QA Lifter',
      'email': 'qa@example.test',
      'password': 'correct horse battery staple',
      'callbackURL': 'https://self.example/auth/verified',
    });
  });

  test('resend verification email posts the selected callback URL', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('perennia-resend-verification-test-');
    addTearDown(() async => tempDir.delete(recursive: true));
    final seenRequests = <http.Request>[];
    final repository = FileAuthRepository(
      authFile: () async => File('${tempDir.path}/auth.json'),
      tokenStore: _FakeAuthSessionTokenStore(),
      apiClientFactory: (baseUrl) {
        expect(baseUrl.toString(), 'https://self.example/');
        return PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            seenRequests.add(request);
            return http.Response(
              jsonEncode(<String, Object?>{'status': true}),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        );
      },
    );

    await repository.resendVerificationEmail(
      serverUrl: Uri.parse('https://self.example'),
      email: 'qa@example.test',
    );

    expect(
      seenRequests.single.url.toString(),
      'https://self.example/api/auth/send-verification-email',
    );
    expect(jsonDecode(seenRequests.single.body), <String, Object?>{
      'email': 'qa@example.test',
      'callbackURL': 'https://self.example/auth/verified',
    });
  });

  test('unverified email sign-in maps to a resendable auth error', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('perennia-unverified-test-');
    addTearDown(() async => tempDir.delete(recursive: true));
    final repository = FileAuthRepository(
      authFile: () async => File('${tempDir.path}/auth.json'),
      tokenStore: _FakeAuthSessionTokenStore(),
      apiClientFactory: (baseUrl) {
        return PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode(<String, Object?>{'message': 'Email not verified'}),
              403,
              headers: const {'content-type': 'application/json'},
            );
          }),
        );
      },
    );

    await expectLater(
      repository.signInWithEmail(
        serverUrl: Uri.parse('https://self.example'),
        email: 'qa@example.test',
        password: 'correct horse battery staple',
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.code,
          'code',
          AuthFailureCode.emailNotVerified,
        ),
      ),
    );
  });

  test('load migrates legacy plaintext token into secure storage', () async {
    final tempDir = await Directory.systemTemp.createTemp('perennia-migrate-test-');
    addTearDown(() async => tempDir.delete(recursive: true));
    final authFile = File('${tempDir.path}/auth.json');
    await authFile.writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'serverUrl': 'https://legacy.example/',
        'session': <String, Object?>{
          'provider': 'email',
          'serverUrl': 'https://legacy.example/',
          'token': 'legacy-session-token',
          'userEmail': 'legacy@example.com',
          'userId': 'legacy-user',
          'userName': 'Legacy User',
        },
      }),
    );
    final tokenStore = _FakeAuthSessionTokenStore();
    final repository = FileAuthRepository(
      authFile: () async => authFile,
      tokenStore: tokenStore,
    );

    final loaded = await repository.load();
    final rewrittenJson = await authFile.readAsString();

    expect(loaded.session?.token, 'legacy-session-token');
    expect(tokenStore.token, 'legacy-session-token');
    expect(rewrittenJson, isNot(contains('legacy-session-token')));
    expect(rewrittenJson, contains('legacy@example.com'));
  });

  test('load preserves server URL when the secure session token is missing',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('perennia-missing-token-test-');
    addTearDown(() async => tempDir.delete(recursive: true));
    final authFile = File('${tempDir.path}/auth.json');
    await authFile.writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'serverUrl': 'https://self.example/',
        'session': <String, Object?>{
          'provider': 'email',
          'serverUrl': 'https://self.example/',
          'userEmail': 'lifter@example.com',
          'userId': 'user-1',
          'userName': 'Test User',
        },
      }),
    );
    final repository = FileAuthRepository(
      authFile: () async => authFile,
      tokenStore: _FakeAuthSessionTokenStore(),
    );

    final loaded = await repository.load();
    final rewrittenJson = await authFile.readAsString();

    expect(loaded.serverUrl.toString(), 'https://self.example/');
    expect(loaded.session, isNull);
    expect(rewrittenJson, contains('https://self.example/'));
    expect(rewrittenJson, isNot(contains('lifter@example.com')));
  });

  test('load preserves server URL when secure token storage cannot be read',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('perennia-token-read-fails-test-');
    addTearDown(() async => tempDir.delete(recursive: true));
    final authFile = File('${tempDir.path}/auth.json');
    await authFile.writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'serverUrl': 'https://restore.example/',
        'session': <String, Object?>{
          'provider': 'email',
          'serverUrl': 'https://restore.example/',
          'userEmail': 'restored@example.com',
          'userId': 'user-1',
          'userName': 'Restored User',
        },
      }),
    );
    final repository = FileAuthRepository(
      authFile: () async => authFile,
      tokenStore: const _UnreadableAuthSessionTokenStore(),
    );

    final loaded = await repository.load();
    final rewrittenJson = await authFile.readAsString();

    expect(loaded.serverUrl.toString(), 'https://restore.example/');
    expect(loaded.session, isNull);
    expect(rewrittenJson, contains('https://restore.example/'));
    expect(rewrittenJson, isNot(contains('restored@example.com')));
  });

  test('sign out deletes the secure session token', () async {
    final tempDir = await Directory.systemTemp.createTemp('perennia-signout-test-');
    addTearDown(() async => tempDir.delete(recursive: true));
    final tokenStore = _FakeAuthSessionTokenStore();
    final seenRequests = <http.Request>[];
    final repository = FileAuthRepository(
      authFile: () async => File('${tempDir.path}/auth.json'),
      tokenStore: tokenStore,
      apiClientFactory: (baseUrl) {
        return PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            seenRequests.add(request);
            if (request.url.path == '/api/auth/sign-out') {
              return http.Response(
                jsonEncode(<String, Object?>{'success': true}),
                200,
                headers: const {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode(_sessionResponse('signout@example.com')),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        );
      },
    );

    await repository.signInWithEmail(
      serverUrl: Uri.parse('https://cloud.example'),
      email: 'signout@example.com',
      password: 'secret',
    );
    await repository.signOut();

    expect(tokenStore.token, isNull);
    expect((await repository.load()).session, isNull);
    expect(
      seenRequests.map((request) => request.url.path),
      <String>['/api/auth/sign-in/email', '/api/auth/sign-out'],
    );
    expect(
      seenRequests.last.headers['authorization'],
      'Bearer session-token',
    );
  });

  test('server URL parser rejects non-http origins', () {
    expect(
      () => parseServerUrl('ftp://example.com'),
      throwsA(isA<FormatException>()),
    );
  });
}

class _FakeSocialIdTokenProvider implements SocialIdTokenProvider {
  const _FakeSocialIdTokenProvider();

  @override
  Future<SocialIdToken> idTokenFor(AuthSocialProvider provider) async {
    return SocialIdToken(token: '${provider.id}-id-token');
  }
}

class _FakeAuthSessionTokenStore implements AuthSessionTokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async {
    this.token = token;
  }

  @override
  Future<void> delete() async {
    token = null;
  }
}

class _UnreadableAuthSessionTokenStore implements AuthSessionTokenStore {
  const _UnreadableAuthSessionTokenStore();

  @override
  Future<String?> read() async {
    throw StateError('secure storage is unavailable');
  }

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> delete() async {}
}

Map<String, Object?> _sessionResponse(String email) {
  return <String, Object?>{
    'redirect': false,
    'token': 'session-token',
    'user': <String, Object?>{
      'id': 'user-1',
      'email': email,
      'name': 'Test User',
      'emailVerified': true,
    },
  };
}

Map<String, Object?> _signUpResponse(String email) {
  return <String, Object?>{
    'token': null,
    'user': <String, Object?>{
      'id': 'user-1',
      'email': email,
      'name': 'QA Lifter',
      'emailVerified': false,
    },
  };
}
