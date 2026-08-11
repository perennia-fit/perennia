import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/api/perennia_api_client.dart';

void main() {
  test('signInEmail posts credentials to the configured server URL', () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://self-host.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(_sessionResponse('email@example.com')),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.signInEmail(
      email: 'email@example.com',
      password: 'secret',
      callbackURL: 'https://self-host.example/auth/verified',
    );

    expect(response.token, 'session-token');
    expect(response.user.email, 'email@example.com');
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.toString(),
      'https://self-host.example/api/auth/sign-in/email',
    );
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'email': 'email@example.com',
      'password': 'secret',
      'callbackURL': 'https://self-host.example/auth/verified',
    });
  });

  test('signUpWithEmailAndPassword posts a new email account', () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://self-host.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(_signUpResponse('qa@example.test')),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.signUpWithEmailAndPassword(
      name: 'QA Lifter',
      email: 'qa@example.test',
      password: 'correct horse battery staple',
      callbackURL: 'https://self-host.example/auth/verified',
    );

    expect(response.token, isNull);
    expect(response.user.email, 'qa@example.test');
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.toString(),
      'https://self-host.example/api/auth/sign-up/email',
    );
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'name': 'QA Lifter',
      'email': 'qa@example.test',
      'password': 'correct horse battery staple',
      'callbackURL': 'https://self-host.example/auth/verified',
    });
  });

  test('sendVerificationEmail posts an email callback request', () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://self-host.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{'status': true}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.sendVerificationEmail(
      email: 'qa@example.test',
      callbackURL: 'https://self-host.example/auth/verified',
    );

    expect(response.status, isTrue);
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.toString(),
      'https://self-host.example/api/auth/send-verification-email',
    );
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'email': 'qa@example.test',
      'callbackURL': 'https://self-host.example/auth/verified',
    });
  });

  test('signOut posts the bearer token to the auth server', () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://self-host.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{'success': true}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.signOut(bearerToken: 'session-token');

    expect(response.success, isTrue);
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.toString(),
      'https://self-host.example/api/auth/sign-out',
    );
    expect(requests.single.headers['authorization'], 'Bearer session-token');
    expect(jsonDecode(requests.single.body), <String, Object?>{});
  });

  test('socialSignIn sends provider id tokens through the generated client',
      () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://cloud.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(_sessionResponse('google@example.com')),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.socialSignIn(
      provider: 'google',
      disableRedirect: true,
      idToken: const SocialIdToken(
        token: 'google-id-token',
        accessToken: 'google-access-token',
      ),
    );

    expect(response.token, 'session-token');
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.toString(),
      'https://cloud.example/api/auth/sign-in/social',
    );
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'provider': 'google',
      'disableRedirect': true,
      'idToken': <String, Object?>{
        'token': 'google-id-token',
        'accessToken': 'google-access-token',
      },
    });
  });

  test('agent API response DTOs snapshot list fields', () {
    const key = AgentApiKeyMetadata(
      id: 'key-1',
      name: 'Gym bot',
      createdAt: '2026-06-22T08:00:00.000Z',
      revoked: false,
    );
    const replacementKey = AgentApiKeyMetadata(
      id: 'key-2',
      name: 'Coach bot',
      createdAt: '2026-06-23T08:00:00.000Z',
      revoked: false,
    );
    final keys = <AgentApiKeyMetadata>[key];
    final keyResponse = AgentApiKeyListResponse(keys: keys);

    keys.add(replacementKey);

    expect(keyResponse.keys, <AgentApiKeyMetadata>[key]);
    expect(
      () => keyResponse.keys[0] = replacementKey,
      throwsA(isA<UnsupportedError>()),
    );

    const warning = AgentSetValidationIssue(
      field: 'values.duration',
      dimension: 'duration',
      rule: 'duration.warnAbove',
      message: 'Duration is unusually high.',
      limit: 14400,
    );
    final warnings = <AgentSetValidationIssue>[warning];
    final allowedSides = <String>['left', 'right'];
    final limits = _validationLimits(allowedSides: allowedSides);
    final validationResponse = AgentSetValidationResponse(
      accepted: true,
      warnings: warnings,
      limits: limits,
    );

    warnings.clear();
    allowedSides.add('both');

    expect(validationResponse.warnings, <AgentSetValidationIssue>[warning]);
    expect(validationResponse.limits.allowedSides, <String>['left', 'right']);
    expect(
      () => validationResponse.warnings[0] = warning,
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => validationResponse.limits.allowedSides[0] = 'both',
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('pushSync posts a bearer-authenticated logged-set batch', () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://sync.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{
            'protocolVersion': 1,
            'accepted': <String>['set-1'],
            'serverClock': '2026-06-22T08:00:01.000Z',
            'applied': <Object?>[
              <String, Object?>{
                'id': 'set-1',
                'updatedAt': '2026-06-22T08:00:00.000Z',
                'deviceId': 'device-a',
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.pushSync(
      bearerToken: 'session-token',
      protocolVersion: 1,
      deviceId: 'device-a',
      entity: 'logged_sets',
      changes: const <SyncPushChange>[
        SyncPushChange(
          id: 'set-1',
          payload: <String, Object?>{
            'id': 'set-1',
            'updated_at': '2026-06-22T08:00:00.000Z',
            'deleted_at': null,
          },
          updatedAt: '2026-06-22T08:00:00.000Z',
          activityLogId: 'activity-1',
          actor: 'app',
          batchId: 'batch-1',
          beforeImage: null,
          afterImage: <String, Object?>{
            'id': 'set-1',
            'updated_at': '2026-06-22T08:00:00.000Z',
            'deleted_at': null,
          },
          occurredAt: '2026-06-22T08:00:00.000Z',
        ),
      ],
    );

    expect(response.accepted, <String>['set-1']);
    expect(response.serverClock, '2026-06-22T08:00:01.000Z');
    expect(response.applied.single.id, 'set-1');
    expect(response.applied.single.updatedAt, '2026-06-22T08:00:00.000Z');
    expect(response.applied.single.deviceId, 'device-a');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.toString(), 'https://sync.example/sync/push');
    expect(requests.single.headers['authorization'], 'Bearer session-token');
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'protocolVersion': 1,
      'deviceId': 'device-a',
      'entity': 'logged_sets',
      'changes': <Object?>[
        <String, Object?>{
          'id': 'set-1',
          'payload': <String, Object?>{
            'id': 'set-1',
            'updated_at': '2026-06-22T08:00:00.000Z',
            'deleted_at': null,
          },
          'updatedAt': '2026-06-22T08:00:00.000Z',
          'deletedAt': null,
          'activityLogId': 'activity-1',
          'actor': 'app',
          'batchId': 'batch-1',
          'beforeImage': null,
          'afterImage': <String, Object?>{
            'id': 'set-1',
            'updated_at': '2026-06-22T08:00:00.000Z',
            'deleted_at': null,
          },
          'occurredAt': '2026-06-22T08:00:00.000Z',
        },
      ],
    });
  });

  test('getMonitoringSeriesBlob fetches a bearer-authenticated blob', () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://sync.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{
            'seriesId': 'series 1',
            'source': 'garmin',
            'externalId': 'activity-1:heart-rate',
            'seriesType': 'heartRate',
            'externalActivityId': 'activity-1',
            'sampleCount': 3,
            'encoding': 'canonical-series-delta-json-v1',
            'compression': 'gzip',
            'sha256': 'abc123',
            'uncompressedByteLength': 120,
            'compressedByteLength': 80,
            'blobBase64': 'H4sIAAAAAAAA',
            'updatedAt': '2026-06-25T09:00:00.000Z',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.getMonitoringSeriesBlob(
      bearerToken: 'session-token',
      seriesId: 'series 1',
    );

    expect(response.seriesId, 'series 1');
    expect(response.sampleCount, 3);
    expect(response.externalActivityId, 'activity-1');
    expect(requests.single.method, 'GET');
    expect(
      requests.single.url.toString(),
      'https://sync.example/monitoring/series/series%201/blob',
    );
    expect(requests.single.headers['authorization'], 'Bearer session-token');
  });

  test('pullSync posts the stored cursor and parses returned changes',
      () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://sync.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{
            'protocolVersion': 1,
            'nextCursor': 'cursor-1',
            'serverClock': '2026-06-22T08:00:01.000Z',
            'changes': <Object?>[
              <String, Object?>{
                'entity': 'logged_sets',
                'id': 'set-1',
                'deviceId': 'device-a',
                'payload': <String, Object?>{
                  'id': 'set-1',
                  'updated_at': '2026-06-22T08:00:00.000Z',
                  'deleted_at': null,
                },
                'updatedAt': '2026-06-22T08:00:00.000Z',
                'deletedAt': null,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.pullSync(
      bearerToken: 'session-token',
      protocolVersion: 1,
      cursor: null,
      limit: 100,
    );

    expect(response.fullResyncRequired, isFalse);
    expect(response.nextCursor, 'cursor-1');
    expect(response.serverClock, '2026-06-22T08:00:01.000Z');
    expect(response.changes.single.id, 'set-1');
    expect(response.changes.single.entity, 'logged_sets');
    expect(response.changes.single.deviceId, 'device-a');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.toString(), 'https://sync.example/sync/pull');
    expect(requests.single.headers['authorization'], 'Bearer session-token');
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'protocolVersion': 1,
      'cursor': null,
      'limit': 100,
    });
  });

  test('pullSync sends snapshot mode and parses full-resync signals', () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://sync.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{
            'protocolVersion': 1,
            'fullResyncRequired': true,
            'nextCursor': 'old-cursor',
            'serverClock': '2026-06-22T08:00:01.000Z',
            'changes': <Object?>[],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.pullSync(
      bearerToken: 'session-token',
      protocolVersion: 1,
      cursor: null,
      limit: 100,
      mode: 'snapshot',
    );

    expect(response.fullResyncRequired, isTrue);
    expect(response.changes, isEmpty);
    expect(requests.single.url.toString(), 'https://sync.example/sync/pull');
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'protocolVersion': 1,
      'cursor': null,
      'limit': 100,
      'mode': 'snapshot',
    });
  });

  test('registerDevicePushToken posts the signed-in device token', () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://sync.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{
            'registered': true,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.registerDevicePushToken(
      bearerToken: 'session-token',
      deviceId: 'device-a',
      platform: 'android',
      token: 'fcm-token-1',
    );

    expect(response.registered, isTrue);
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.toString(),
      'https://sync.example/sync/device-push-token',
    );
    expect(requests.single.headers['authorization'], 'Bearer session-token');
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'deviceId': 'device-a',
      'platform': 'android',
      'token': 'fcm-token-1',
    });
  });

  test('requestAccountDeletion posts the bearer token and parses marker',
      () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://sync.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{
            'deletionRequestedAt': '2026-06-22T16:00:00.000Z',
            'localReplicaPreserved': true,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.requestAccountDeletion(
      bearerToken: 'session-token',
    );

    expect(response.deletionRequestedAt, '2026-06-22T16:00:00.000Z');
    expect(response.localReplicaPreserved, isTrue);
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.toString(),
      'https://sync.example/account/deletion',
    );
    expect(requests.single.headers['authorization'], 'Bearer session-token');
    expect(requests.single.body, isEmpty);
  });

  test('purgeImportedData posts the explicit Settings purge request', () async {
    final requests = <http.Request>[];
    final client = PerenniaApiClient(
      baseUrl: Uri.parse('https://sync.example/'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, Object?>{
            'accepted': true,
            'duplicate': false,
            'batchId': 'purge-1',
            'serverClock': '2026-06-26T01:00:00.000Z',
            'source': 'garmin',
            'scope': 'gpsOnly',
            'tombstonedCounts': <String, Object?>{
              'externalActivities': 0,
              'metricReadings': 0,
              'monitoringSeries': 1,
              'materializedSets': 0,
              'activityLinks': 0,
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final response = await client.purgeImportedData(
      bearerToken: 'session-token',
      idempotencyKey: 'purge-1',
      scope: 'gpsOnly',
    );

    expect(response.accepted, isTrue);
    expect(response.duplicate, isFalse);
    expect(response.batchId, 'purge-1');
    expect(response.scope, 'gpsOnly');
    expect(response.tombstonedCounts.monitoringSeries, 1);
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.toString(),
      'https://sync.example/integrations/imported-data/purge',
    );
    expect(requests.single.headers['authorization'], 'Bearer session-token');
    expect(jsonDecode(requests.single.body), <String, Object?>{
      'idempotencyKey': 'purge-1',
      'source': 'garmin',
      'scope': 'gpsOnly',
    });
  });
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

AgentSetValidationLimits _validationLimits({
  required List<String> allowedSides,
}) {
  return AgentSetValidationLimits(
    numericMin: 0,
    maxDecimalPlaces: 3,
    loadMaxKilograms: 1000,
    loadMaxDecimalPlaces: 3,
    addedLoadWarnKilograms: 500,
    assistedLoadWarnKilograms: 500,
    repsMax: 1000,
    repsWarnAbove: 100,
    durationMaxSeconds: 86400,
    durationWarnAboveSeconds: 14400,
    distanceMaxKilometers: 1000,
    distanceWarnAboveKilometers: 100,
    rpeMin: 0,
    rpeMax: 10,
    rpeStep: 0.5,
    speedWarnAboveKilometersPerHour: 40,
    allowedSides: allowedSides,
  );
}
