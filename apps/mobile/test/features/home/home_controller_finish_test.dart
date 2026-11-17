import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/home/controllers/home_controller.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';
import 'package:perennia/features/training/services/timer_background_scheduler.dart';

/// Finish and Delete stop the Workout's running rest and cancel its background
/// schedule, so no rest notification fires after the user has left.
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  const trainingDay = TrainingDayDate(year: 2026, month: 6, day: 16);
  final startedAt = DateTime.utc(2026, 6, 16, 8);

  late AppDatabase database;
  late TrainingRepositories repositories;
  late _RecordingScheduler scheduler;
  late HomeController controller;
  late String workoutId;

  /// The rest starts 30 minutes in and runs 2 minutes, so it is still
  /// counting down at 31 minutes.
  final restStartedAt = startedAt.add(const Duration(minutes: 30));
  final duringRest = startedAt.add(const Duration(minutes: 31));
  late DateTime now;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  setUp(() async {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(
      database,
      platformSeedSource: const _EmptySeedSource(),
    );
    scheduler = _RecordingScheduler();
    now = duringRest;
    final container = ProviderContainer(
      overrides: [
        trainingRepositoriesProvider.overrideWithValue(repositories),
        homeRepositoryProvider.overrideWithValue(
          RepositoryHomeRepository(
            repositories,
            now: () => now,
          ),
        ),
        timerBackgroundSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(container.dispose);
    controller = container.read(homeControllerProvider.notifier);

    workoutId = await repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: startedAt,
        timezone: 'UTC',
        localDate: trainingDay,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  /// Logs one Set in the Workout and starts the rest after it.
  Future<String> startRestAfterASet() async {
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Back Squat',
        type: ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.reps],
        ),
      ),
    );
    final setId = await repositories.sets.create(
      LoggedSetDraft(
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 0,
        values: LoggedSet.fromValues(<SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.load,
            entered: '100',
            unit: TrainingUnit.kilogram,
          ),
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '5',
            unit: TrainingUnit.repetition,
          ),
        ]),
        plannedRestAfter: const Duration(minutes: 2),
      ),
    );
    final set = (await repositories.sets.getById(setId))!;
    return (await repositories.restTimers.startForSet(
      set,
      now: restStartedAt,
    ))!;
  }

  Future<void> expectFinished() async {
    final workout = await repositories.workoutSessions.getById(workoutId);
    expect(workout!.endedAt, isNotNull);
  }

  test('cancels the running rest and its background schedule', () async {
    final timerId = await startRestAfterASet();

    await controller.finishWorkout(workoutId);

    await expectFinished();
    final timer = await repositories.restTimers.getById(timerId);
    expect(timer!.status, RestTimerStatus.canceled);
    expect(scheduler.cancelled, <String>[timerId]);
  });

  test('finishes with no rest and cancels nothing', () async {
    await controller.finishWorkout(workoutId);

    await expectFinished();
    expect(scheduler.cancelled, isEmpty);
  });

  test('leaves a rest that already ended alone', () async {
    final timerId = await startRestAfterASet();
    await repositories.restTimers.markAlertFired(
      timerId,
      now: startedAt.add(const Duration(minutes: 32)),
    );

    await controller.finishWorkout(workoutId);

    await expectFinished();
    final timer = await repositories.restTimers.getById(timerId);
    expect(timer!.status, RestTimerStatus.expired);
    expect(scheduler.cancelled, isEmpty);
  });

  test('records the finish and the cancel as one batch', () async {
    final timerId = await startRestAfterASet();
    final before = {
      for (final entry in await repositories.activityLog.listEntries())
        entry.id,
    };

    await controller.finishWorkout(workoutId);

    final entries = (await repositories.activityLog.listEntries())
        .where((entry) => !before.contains(entry.id))
        .toList();
    final workoutEntry =
        entries.singleWhere((entry) => entry.entityId == workoutId);
    final restEntry = entries.singleWhere((entry) => entry.entityId == timerId);
    expect(restEntry.batchId, workoutEntry.batchId);
  });

  test('leaves a running rest whose deadline has passed alone', () async {
    final timerId = await startRestAfterASet();
    now = startedAt.add(const Duration(minutes: 40));

    await controller.finishWorkout(workoutId);

    await expectFinished();
    final timer = await repositories.restTimers.getById(timerId);
    expect(timer!.status, RestTimerStatus.running);
    expect(timer.deletedAt, isNull);
    expect(scheduler.cancelled, isEmpty);
  });

  test('delete cancels the running rest and its background schedule', () async {
    final timerId = await startRestAfterASet();

    await controller.deleteWorkout(workoutId);

    final timer = await repositories.restTimers.getById(timerId);
    expect(timer!.status, RestTimerStatus.canceled);
    expect(scheduler.cancelled, <String>[timerId]);
  });

  test('delete cancels the schedule of a running rest past its deadline',
      () async {
    // The rest ran out in the background, so its row still says running and
    // its "Rest over" notification was posted. Delete cancels the row anyway,
    // so it also cancels the schedule, which removes that notification.
    final timerId = await startRestAfterASet();
    now = startedAt.add(const Duration(minutes: 40));

    await controller.deleteWorkout(workoutId);

    final timer = await repositories.restTimers.getById(timerId);
    expect(timer!.status, RestTimerStatus.canceled);
    expect(scheduler.cancelled, <String>[timerId]);
  });

  test('delete leaves the schedule of a rest that already ended alone',
      () async {
    final timerId = await startRestAfterASet();
    await repositories.restTimers.markAlertFired(
      timerId,
      now: startedAt.add(const Duration(minutes: 32)),
    );

    await controller.deleteWorkout(workoutId);

    expect(scheduler.cancelled, isEmpty);
  });

  test('delete with no running rest cancels no schedule', () async {
    await controller.deleteWorkout(workoutId);

    expect(scheduler.cancelled, isEmpty);
  });

  test('finishes when the schedule cancel fails', () async {
    final timerId = await startRestAfterASet();
    scheduler.failCancel = true;

    await controller.finishWorkout(workoutId);
    await pumpEventQueue();

    await expectFinished();
    final timer = await repositories.restTimers.getById(timerId);
    expect(timer!.status, RestTimerStatus.canceled);
    expect(scheduler.cancelled, <String>[timerId]);
  });
}

class _RecordingScheduler implements TimerBackgroundScheduler {
  final cancelled = <String>[];
  var failCancel = false;

  @override
  Future<void> cancel(String timerId) async {
    cancelled.add(timerId);
    if (failCancel) {
      throw PlatformException(code: 'unavailable');
    }
  }

  @override
  Future<TimerBackgroundPermissionStatus> requestPermissionIfNeeded() async {
    return TimerBackgroundPermissionStatus.granted;
  }

  @override
  Future<TimerBackgroundPermissionStatus> notificationPermissionStatus() async {
    return TimerBackgroundPermissionStatus.granted;
  }

  @override
  Future<TimerBackgroundPermissionStatus> schedule(
    TimerBackgroundSchedule schedule,
  ) async {
    return TimerBackgroundPermissionStatus.granted;
  }

  @override
  Future<void> setInAppTimerCues(bool active) async {}
}

class _EmptySeedSource implements PlatformExerciseSeedSource {
  const _EmptySeedSource();

  @override
  Future<PlatformExerciseSeed> load() async {
    return const PlatformExerciseSeed(
      categories: <SeedExerciseCategory>[],
      exercises: <SeedExercise>[],
    );
  }
}
