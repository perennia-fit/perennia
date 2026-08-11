import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/home/services/workout_auto_finish_service.dart';

void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  test('open check finishes stale workouts before recording the open time',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final store = _MemoryWorkoutInteractionStore();
    final workoutId = await repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
        timezone: 'Australia/Brisbane',
      ),
      actor: 'tester',
    );
    final workout = await repositories.workoutSessions.getById(workoutId);
    final lastInteractionAt =
        workout!.updatedAt.add(const Duration(minutes: 5));
    final openedAt = lastInteractionAt.add(
      workoutAutoFinishIdleThreshold + const Duration(minutes: 30),
    );
    await store.saveLastInteractionAt(lastInteractionAt);
    final service = WorkoutAutoFinishService(
      workoutSessions: repositories.workoutSessions,
      interactionStore: store,
      now: () => openedAt,
    );

    final finished = await service.checkForStaleWorkoutsOnOpen();

    expect(finished.map((entry) => entry.workoutId), <String>[workoutId]);
    expect(
      (await repositories.workoutSessions.getById(workoutId))?.endedAt,
      lastInteractionAt.add(workoutAutoFinishIdleThreshold),
    );
    expect(await store.loadLastInteractionAt(), openedAt);
  });
}

class _MemoryWorkoutInteractionStore implements WorkoutInteractionStore {
  DateTime? _lastInteractionAt;

  @override
  Future<DateTime?> loadLastInteractionAt() async => _lastInteractionAt;

  @override
  Future<void> saveLastInteractionAt(DateTime interactedAt) async {
    _lastInteractionAt = interactedAt.toUtc();
  }
}
