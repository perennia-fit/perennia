import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/api/perennia_api_client.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/settings/widgets/settings_providers.dart';
import 'package:perennia/features/sync/repositories/sync_repository.dart';

void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  late AppDatabase database;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  setUp(() {
    database = AppDatabase.inMemory();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'Sync now exhausts a full remote page when LWW applies no rows',
    () async {
      final updatedAt = DateTime.utc(2026, 7, 27, 9);
      await _insertSyncedDependencies(database, updatedAt);

      final firstPage = <Map<String, Object?>>[];
      for (var index = 0; index < 100; index += 1) {
        final id = 'logged-set-$index';
        await database.into(database.loggedSets).insert(
              LoggedSetsCompanion.insert(
                id: id,
                workoutId: 'workout-1',
                exerciseId: 'exercise-1',
                position: index,
                repsValue: const Value<double?>(5),
                repsUnit: const Value<String?>('rep'),
                repsEntered: const Value<String?>('5'),
                syncDeviceId: const Value<String?>('remote-device'),
                syncPreviouslySynced: const Value<bool>(true),
                updatedAt: updatedAt,
              ),
            );
        firstPage.add(_pulledLoggedSetChange(id, index, updatedAt));
      }

      var pullRequests = 0;
      final repository = SyncRepository(
        database: database,
        apiClientFactory: (baseUrl) => PerenniaApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/sync/pull');
            pullRequests += 1;

            if (pullRequests == 1) {
              return _pullResponse(
                changes: firstPage,
                nextCursor: 'cursor-1',
                serverClock: '2026-07-27T09:00:01.000Z',
              );
            }
            if (pullRequests == 2) {
              return _pullResponse(
                changes: <Map<String, Object?>>[
                  _pulledRoutineChange(
                    updatedAt: DateTime.utc(2026, 7, 27, 9, 1),
                  ),
                ],
                nextCursor: 'cursor-2',
                serverClock: '2026-07-27T09:01:01.000Z',
              );
            }
            fail('Sync now requested an unexpected third pull window.');
          }),
        ),
      );
      final container = ProviderContainer(
        overrides: <Override>[
          syncRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(settingsSyncNowProvider)(
        session: _session(),
        deviceId: 'device-a',
      );

      expect(pullRequests, 2);
      expect(result.appliedCount, 1);
      expect(
        await (database.select(database.planRoutines)
              ..where((row) => row.id.equals('routine-new')))
            .getSingle()
            .then((row) => row.name),
        'Advanced rotation',
      );
    },
  );
}

Future<void> _insertSyncedDependencies(
  AppDatabase database,
  DateTime updatedAt,
) async {
  await database.into(database.exercises).insert(
        ExercisesCompanion.insert(
          id: 'exercise-1',
          libraryOrigin: const Value<String>('user'),
          name: 'Back Squat',
          dimensionIds: '["reps"]',
          syncDeviceId: const Value<String?>('remote-device'),
          syncPreviouslySynced: const Value<bool>(true),
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.workoutSessions).insert(
        WorkoutSessionsCompanion.insert(
          id: 'workout-1',
          startedAt: updatedAt,
          timezone: 'UTC',
          localDate: const Value<String>('2026-07-27'),
          syncDeviceId: const Value<String?>('remote-device'),
          syncPreviouslySynced: const Value<bool>(true),
          updatedAt: updatedAt,
        ),
      );
}

Map<String, Object?> _pulledLoggedSetChange(
  String id,
  int position,
  DateTime updatedAt,
) {
  return <String, Object?>{
    'entity': AppDatabase.loggedSetsTable,
    'id': id,
    'deviceId': 'remote-device',
    'payload': <String, Object?>{
      'id': id,
      'workout_id': 'workout-1',
      'exercise_id': 'exercise-1',
      'position': position,
      'planned_rest_after': null,
      'performed_at': null,
      'load_value': null,
      'load_unit': null,
      'load_entered': null,
      'reps_value': 5,
      'reps_unit': 'rep',
      'reps_entered': '5',
      'duration_value': null,
      'duration_unit': null,
      'duration_entered': null,
      'distance_value': null,
      'distance_unit': null,
      'distance_entered': null,
      'comment': null,
      'side': null,
      'rpe': null,
      'is_completed': false,
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': null,
    },
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': null,
  };
}

Map<String, Object?> _pulledRoutineChange({
  required DateTime updatedAt,
}) {
  return <String, Object?>{
    'entity': 'routines',
    'id': 'routine-new',
    'deviceId': 'agent-device',
    'payload': <String, Object?>{
      'id': 'routine-new',
      'name': 'Advanced rotation',
      'notes': null,
      'cadence_kind': 'rotating',
      'cadence_window': 8,
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': null,
    },
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': null,
  };
}

http.Response _pullResponse({
  required List<Map<String, Object?>> changes,
  required String nextCursor,
  required String serverClock,
}) {
  return http.Response(
    jsonEncode(<String, Object?>{
      'protocolVersion': 1,
      'fullResyncRequired': false,
      'changes': changes,
      'nextCursor': nextCursor,
      'serverClock': serverClock,
    }),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

AuthSession _session() {
  return AuthSession(
    provider: AuthSessionProvider.email,
    serverUrl: Uri.parse('https://sync.example'),
    userId: 'user-1',
    userEmail: 'athlete@example.com',
    userName: 'Athlete',
    token: 'session-token',
  );
}
