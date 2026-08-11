import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/api/perennia_api_client.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/sync/controllers/sync_status_controller.dart';
import 'package:perennia/features/sync/repositories/sync_repository.dart';

void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  late AppDatabase database;
  late DateTime now;
  late SyncStatusRepository repository;
  late ProviderContainer container;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  setUp(() {
    database = AppDatabase.inMemory();
    now = DateTime.utc(2026, 6, 22, 12);
    repository = SyncStatusRepository(database, clock: () => now);
    container = ProviderContainer(
      overrides: [
        syncStatusRepositoryProvider.overrideWith((ref) => repository),
        syncNowProvider.overrideWith((ref) => () => now),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test(
      'controller keeps transient failures quiet but banners stale failures '
      'and auth expiry', () async {
    final states = <SyncStatusState>[];
    final subscription = container.listen(
      syncStatusControllerProvider,
      (_, next) {
        if (next case AsyncData(:final value)) {
          states.add(value);
        }
      },
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await _waitFor(() => states.isNotEmpty);

    await repository.recordSuccess(
      serverClock: now.subtract(const Duration(hours: 1)).toIso8601String(),
    );
    await repository.recordFailure(Exception('offline'));
    await _waitFor(() => states.last.kind == SyncStatusKind.failed);

    expect(
      states.last.lastSuccessfulSyncAt,
      now.subtract(const Duration(hours: 1)),
    );
    expect(states.last.showsFailureBanner, isFalse);

    now = DateTime.utc(2026, 6, 23, 13);
    await repository.recordFailure(Exception('still offline'));
    await _waitFor(() => states.last.showsFailureBanner);

    expect(states.last.kind, SyncStatusKind.failed);
    expect(states.last.showsFailureBanner, isTrue);

    await repository.recordAuthExpired(
      const ApiException(statusCode: 401, body: '{"code":"sync_unauthorized"}'),
    );
    await _waitFor(() => states.last.kind == SyncStatusKind.authExpired);

    expect(states.last.showsFailureBanner, isTrue);
  });

  test('sync failure status does not block local writes', () async {
    await repository.recordAuthExpired(
      const ApiException(statusCode: 401, body: '{"code":"sync_unauthorized"}'),
    );

    final repositories = TrainingRepositories(
      database,
      platformSeedSource: const _StarterSeedSource(),
    );
    final result = await repositories.logDefaultWeightRepsSet(
      now: DateTime.utc(2026, 6, 22, 8),
      timezone: 'UTC',
    );
    final sets = await repositories.sets.listActiveForWorkout(
      result.workoutSessionId,
    );

    expect(sets, hasLength(1));
    expect(sets.single.values.reps?.entered, '5');
  });

  test('sync status state defensively copies integration statuses', () {
    final integrations = <IntegrationStatusState>[
      IntegrationStatusState(
        source: 'garmin',
        condition: IntegrationStatusCondition.ok,
        recoveryAction: IntegrationStatusRecoveryAction.none,
        observedAt: now,
      ),
    ];

    final state = SyncStatusState(
      kind: SyncStatusKind.synced,
      observedAt: now,
      integrationStatuses: integrations,
    );

    integrations.add(
      IntegrationStatusState(
        source: 'strava',
        condition: IntegrationStatusCondition.ok,
        recoveryAction: IntegrationStatusRecoveryAction.none,
        observedAt: now,
      ),
    );

    expect(state.integrationStatuses, hasLength(1));
    expect(state.integrationStatuses.single.source, 'garmin');
    expect(
      () => state.integrationStatuses.add(
        IntegrationStatusState(
          source: 'manual',
          condition: IntegrationStatusCondition.ok,
          recoveryAction: IntegrationStatusRecoveryAction.none,
          observedAt: now,
        ),
      ),
      throwsUnsupportedError,
    );
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  fail('Timed out waiting for condition.');
}

class _StarterSeedSource implements PlatformExerciseSeedSource {
  const _StarterSeedSource();

  @override
  Future<PlatformExerciseSeed> load() async {
    return PlatformExerciseSeed(
      categories: <SeedExerciseCategory>[],
      exercises: <SeedExercise>[
        SeedExercise(
          id: '01910000-0000-7000-8000-000000000101',
          name: TrainingRepositories.starterWeightRepsExerciseName,
          dimensions: <DimensionId>[DimensionId.load, DimensionId.reps],
          categoryId: null,
          notes: null,
          updatedAt: DateTime.utc(2026),
        ),
      ],
    );
  }
}
