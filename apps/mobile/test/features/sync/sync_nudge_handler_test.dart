import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/sync/services/sync_coordinator.dart';
import 'package:perennia/features/sync/services/sync_nudge_handler.dart';

void main() {
  test('silent sync nudge requests a complete serialized Sync Run', () async {
    final requests = <({AuthSession session, String deviceId})>[];
    final handler = SyncNudgeHandler(
      synchronize: ({
        required AuthSession session,
        required String deviceId,
      }) async {
        requests.add((session: session, deviceId: deviceId));
        return const SyncCycleResult(
          appliedCount: 2,
          pushedCount: 1,
          serverClock: '2026-06-22T08:00:01.000Z',
        );
      },
    );

    final result = await handler.handleSilentPush(
      data: const <String, Object?>{
        'type': 'sync_nudge',
        'protocolVersion': '1',
        'reason': 'sync_push',
      },
      session: _session(),
      deviceId: 'device-a',
    );

    expect(result?.appliedCount, 2);
    expect(result?.pushedCount, 1);
    expect(requests.single.deviceId, 'device-a');
    expect(requests.single.session.token, 'session-token');
  });

  test('non-sync pushes and signed-out devices are ignored', () async {
    var requestCount = 0;
    final handler = SyncNudgeHandler(
      synchronize: ({
        required AuthSession session,
        required String deviceId,
      }) async {
        requestCount += 1;
        return SyncCycleResult.skipped;
      },
    );

    final nonNudge = await handler.handleSilentPush(
      data: const <String, Object?>{'type': 'marketing'},
      session: _session(),
      deviceId: 'device-a',
    );
    final signedOut = await handler.handleSilentPush(
      data: const <String, Object?>{
        'type': 'sync_nudge',
        'protocolVersion': 1,
      },
      session: null,
      deviceId: 'device-a',
    );

    expect(nonNudge, isNull);
    expect(signedOut, isNull);
    expect(requestCount, 0);
  });
}

AuthSession _session() {
  return AuthSession(
    provider: AuthSessionProvider.email,
    serverUrl: Uri.parse('https://sync.example/'),
    token: 'session-token',
    userEmail: 'user@example.com',
    userId: 'user-1',
    userName: 'Test User',
  );
}
