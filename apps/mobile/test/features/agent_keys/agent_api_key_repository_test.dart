import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/api/perennia_api_client.dart';
import 'package:perennia/features/agent_keys/repositories/agent_api_key_repository.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';

void main() {
  test('HTTP repository uses the generated client and hides revoked keys',
      () async {
    final requests = <http.Request>[];
    final repository = HttpAgentApiKeyRepository(
      apiClientFactory: (baseUrl) {
        expect(baseUrl.toString(), 'https://cloud.example/');
        return PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.method == 'GET' &&
                request.url.path == '/agent/api-keys') {
              return http.Response(
                jsonEncode(<String, Object?>{
                  'keys': <Object?>[
                    _keyJson(id: 'active-key', name: 'Spotter'),
                    _keyJson(
                      id: 'revoked-key',
                      name: 'Old bot',
                      revoked: true,
                    ),
                  ],
                }),
                200,
                headers: const {'content-type': 'application/json'},
              );
            }
            if (request.method == 'POST' &&
                request.url.path == '/agent/api-keys') {
              return http.Response(
                jsonEncode(<String, Object?>{
                  'key': _keyJson(id: 'created-key', name: 'New coach'),
                  'secret': 'prn_agent_created_secret',
                }),
                201,
                headers: const {'content-type': 'application/json'},
              );
            }
            if (request.method == 'DELETE' &&
                request.url.path == '/agent/api-keys/active-key') {
              return http.Response(
                jsonEncode(<String, Object?>{'revoked': true}),
                200,
                headers: const {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }),
        );
      },
    );

    final listed = await repository.list(_session);
    final created = await repository.create(
      session: _session,
      name: 'New coach',
    );
    await repository.revoke(session: _session, keyId: 'active-key');

    expect(listed.map((key) => key.id), <String>['active-key']);
    expect(created.record.id, 'created-key');
    expect(created.secret, 'prn_agent_created_secret');
    expect(requests.map((request) => request.method), <String>[
      'GET',
      'POST',
      'DELETE',
    ]);
    expect(
      requests.every(
        (request) => request.headers['authorization'] == 'Bearer session-token',
      ),
      isTrue,
    );
    expect(jsonDecode(requests[1].body), <String, Object?>{
      'name': 'New coach',
    });
  });
}

final _session = AuthSession(
  provider: AuthSessionProvider.email,
  serverUrl: Uri.parse('https://cloud.example/'),
  token: 'session-token',
  userEmail: 'lifter@example.com',
  userId: 'user-1',
  userName: 'Lifter',
);

Map<String, Object?> _keyJson({
  required String id,
  required String name,
  bool revoked = false,
}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'prefix': 'prn_agent_',
    'start': 'abcd',
    'createdAt': '2026-06-24T07:30:00.000Z',
    'lastUsedAt': null,
    'revoked': revoked,
  };
}
