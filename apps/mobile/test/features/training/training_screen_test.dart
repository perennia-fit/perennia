import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, driftRuntimeOptions;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/analytics/repositories/exercise_analytics_repository.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/analytics/widgets/exercise_overview_screen.dart';
import 'package:perennia/features/training/services/timer_background_scheduler.dart';
import 'package:perennia/features/training/widgets/rest_strip.dart';
import 'package:perennia/features/training/widgets/training_screen.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

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

  group('training screen', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    _testTrainingScreen(
        'renders exactly the fields for a load and reps exercise', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Back Squat',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );

      await _pumpTrainingScreen(tester, repositories, workoutExerciseId!);

      expect(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        findsOneWidget,
      );
      expect(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        findsOneWidget,
      );
      expect(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.duration)),
        findsNothing,
      );
      expect(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.distance)),
        findsNothing,
      );
      expect(
        find.byKey(TrainingScreen.decrementButtonKey(DimensionId.load)),
        findsOneWidget,
      );
      expect(
        find.byKey(TrainingScreen.incrementButtonKey(DimensionId.load)),
        findsOneWidget,
      );
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.load)),
        isEmpty,
      );
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        isEmpty,
      );
      expect(find.byKey(TrainingScreen.commentFieldKey), findsOneWidget);
      expect(find.byKey(TrainingScreen.sideFieldKey), findsNothing);
      expect(find.byKey(TrainingScreen.rpeFieldKey), findsNothing);
    });

    _testTrainingScreen(
        'tapping a dimension field selects its value to replace it', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Back Squat',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      await _pumpTrainingScreen(tester, repositories, workoutExerciseId!);
      final loadField =
          find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load));
      await tester.enterText(loadField, '0');
      await tester.pump();

      await tester.tap(loadField);
      await tester.pump();

      final controller = tester.widget<TextField>(loadField).controller!;
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );
    });

    _testTrainingScreen('uses the settings default increment for load steppers',
        (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Back Squat',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId!,
        settingsRepository: InMemorySettingsRepository(
          const AppSettings(defaultWeightIncrement: 5),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      await tester.tap(
        find.byKey(TrainingScreen.incrementButtonKey(DimensionId.load)),
      );
      await tester.pump();
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '5',
      );

      await tester.tap(
        find.byKey(TrainingScreen.incrementButtonKey(DimensionId.reps)),
      );
      await tester.pump();
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '1',
      );
    });

    _testTrainingScreen('renders exactly the fields for a timed exercise', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Plank',
          type: ExerciseType(const <DimensionId>[DimensionId.duration]),
        ),
      );

      await _pumpTrainingScreen(tester, repositories, workoutExerciseId!);

      expect(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        findsNothing,
      );
      expect(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        findsNothing,
      );
      expect(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.duration)),
        findsOneWidget,
      );
      expect(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.distance)),
        findsNothing,
      );
    });

    _testTrainingScreen(
        'increments and decrements dimension inputs by defaults', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );

      await _pumpTrainingScreen(tester, repositories, workoutExerciseId!);

      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '80',
      );
      await tester.tap(
        find.byKey(TrainingScreen.incrementButtonKey(DimensionId.load)),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );
      await tester.tap(
        find.byKey(TrainingScreen.incrementButtonKey(DimensionId.reps)),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(TrainingScreen.decrementButtonKey(DimensionId.reps)),
      );
      await tester.pump();

      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '82.5',
      );
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );
    });

    _testTrainingScreen('saves a self-describing set for the workout exercise',
        (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );

      await _pumpTrainingScreen(tester, repositories, workoutExerciseId!);

      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '100',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);

      final workoutExercise = await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId),
      );
      final sets = await tester.runAsync(
        () => repositories.sets.listActiveForWorkout(
          workoutExercise!.workoutId,
        ),
      );
      final logs = await tester.runAsync(
        repositories.activityLog.listEntries,
      );

      expect(sets, hasLength(1));
      final savedSet = sets!.single;
      expect(savedSet.exerciseId, workoutExercise!.exerciseId);
      expect(savedSet.values.dimensionIds, <DimensionId>[
        DimensionId.load,
        DimensionId.reps,
      ]);
      expect(savedSet.values.load?.entered, '100');
      expect(savedSet.values.reps?.entered, '5');
      expect(savedSet.isCompleted, isTrue);
      expect(
        logs!
            .where(
              (entry) =>
                  entry.entityTable == AppDatabase.loggedSetsTable &&
                  entry.entityId == savedSet.id &&
                  entry.beforeImage == null &&
                  entry.afterImage?['load_entered'] == '100' &&
                  entry.afterImage?['reps_entered'] == '5',
            )
            .length,
        1,
      );
      expect(savedSet.comment, isNull);
      expect(savedSet.side, isNull);
      expect(savedSet.rpe, isNull);
    });

    _testTrainingScreen(
      'saves a sparse cardio set with duration parts and no distance',
      (tester) async {
        final workoutExerciseId = await tester.runAsync(
          () => _createWorkoutExercise(
            repositories,
            name: 'Stair Master',
            type: ExerciseType(
              const <DimensionId>[
                DimensionId.distance,
                DimensionId.duration,
              ],
            ),
          ),
        );
        final workoutExercise = await tester.runAsync(
          () => repositories.workoutExercises.getById(workoutExerciseId!),
        );
        final setStream = StreamController<List<LoggedSetRecord>>();
        addTearDown(setStream.close);

        await _emitSets(
            tester, repositories, workoutExercise!.workoutId, setStream);
        await _pumpTrainingScreen(
          tester,
          repositories,
          workoutExerciseId!,
          setsStream: setStream.stream,
        );

        expect(
          find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.distance)),
          findsOneWidget,
        );
        expect(
          find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.duration)),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(TrainingScreen.durationHoursFieldKey),
          '1',
        );
        await tester.enterText(
          find.byKey(TrainingScreen.durationMinutesFieldKey),
          '2',
        );
        await tester.enterText(
          find.byKey(TrainingScreen.durationSecondsFieldKey),
          '3',
        );
        await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
        await _settleRepositoryWork(tester);
        await _emitSets(
          tester,
          repositories,
          workoutExercise.workoutId,
          setStream,
        );

        final sets = await tester.runAsync(
          () => repositories.sets.listActiveForWorkout(
            workoutExercise.workoutId,
          ),
        );

        expect(sets, hasLength(1));
        final savedSet = sets!.single;
        expect(savedSet.values.dimensionIds, <DimensionId>[
          DimensionId.duration,
        ]);
        expect(savedSet.values.duration?.entered, '3723');
        expect(savedSet.values.distance, isNull);
        expect(find.text('1:02:03'), findsOneWidget);
      },
    );

    _testTrainingScreen('keeps saved dimensions as defaults for the next set', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );

      await _pumpTrainingScreen(tester, repositories, workoutExerciseId!);

      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '100',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);

      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '100',
      );
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );

      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);

      final workoutExercise = await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId),
      );
      final sets = await tester.runAsync(
        () => repositories.sets.listActiveForWorkout(
          workoutExercise!.workoutId,
        ),
      );

      expect(sets, hasLength(2));
      expect(sets!.map((set) => set.position), <int>[0, 1]);
      expect(
        sets.map((set) => set.values.load?.entered),
        <String?>['100', '100'],
      );
      expect(
        sets.map((set) => set.values.reps?.entered),
        <String?>['5', '5'],
      );
    });

    _testTrainingScreen(
        'Log set starts the rest in the strip; Stop, then Start rest', (
      tester,
    ) async {
      final scheduler = _RecordingTimerBackgroundScheduler(
        TimerBackgroundPermissionStatus.granted,
      );
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final workoutExercise = (await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId!),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId!,
        timerBackgroundScheduler: scheduler,
      );

      // Idle: Start rest, and the strip sits directly above Log set.
      expect(find.byKey(TrainingScreen.restStripStartKey), findsOneWidget);
      _expectMinimumTargetSize(
        tester,
        find.byKey(TrainingScreen.restStripStartKey),
      );
      expect(
        tester.getRect(find.byKey(TrainingScreen.restStripKey)).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(TrainingScreen.logSetButtonKey)).top,
        ),
      );

      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '100',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);

      RestTimerRecord? timer = await tester.runAsync<RestTimerRecord?>(
        () => repositories.restTimers.getCurrentForWorkout(
          workoutExercise.workoutId,
        ),
      );
      expect(timer?.duration, const Duration(seconds: 120));
      expect(timer?.sourceSetId, isNotNull);

      await _waitForFinder(tester, find.byKey(TrainingScreen.restStripStopKey));
      expect(_restStripSeconds(tester), inInclusiveRange(117, 120));
      expect(find.byKey(TrainingScreen.restStripStartKey), findsNothing);

      await tester.tap(find.byKey(TrainingScreen.restStripStopKey));
      await _settleRepositoryWork(tester);

      timer = await tester.runAsync<RestTimerRecord?>(
        () => repositories.restTimers.getCurrentForWorkout(
          workoutExercise.workoutId,
        ),
      );
      expect(timer, isNull);
      expect(scheduler.cancels, isNotEmpty);
      await _waitForFinder(
        tester,
        find.byKey(TrainingScreen.restStripStartKey),
      );

      // Start rest starts the form's Rest after: 2:00 stepped down to 1:30.
      await tester.tap(find.byKey(TrainingScreen.restAfterDecrementKey));
      await tester.tap(find.byKey(TrainingScreen.restAfterDecrementKey));
      await tester.pump();
      expect(_restText(tester), '1:30');
      await tester.tap(find.byKey(TrainingScreen.restStripStartKey));
      await _settleRepositoryWork(tester);

      timer = await tester.runAsync<RestTimerRecord?>(
        () => repositories.restTimers.getCurrentForWorkout(
          workoutExercise.workoutId,
        ),
      );
      expect(timer?.duration, const Duration(seconds: 90));
      expect(timer?.sourceSetId, isNull);
      expect(scheduler.schedules.last.timerId, timer!.id);
      await _waitForFinder(tester, find.byKey(TrainingScreen.restStripStopKey));
    });

    _testTrainingScreen('Start rest is disabled at Off', (tester) async {
      final workoutExerciseId = (await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      ))!;

      await _pumpTrainingScreen(tester, repositories, workoutExerciseId);
      // 2:00 down to Off in 15 s steps.
      for (var step = 0; step < 8; step += 1) {
        await tester.tap(find.byKey(TrainingScreen.restAfterDecrementKey));
      }
      await tester.pump();

      expect(_restText(tester), 'Off');
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(TrainingScreen.restStripStartKey),
            )
            .onPressed,
        isNull,
      );
    });

    _testTrainingScreen(
        'the strip adjusts a running rest and reschedules its alert', (
      tester,
    ) async {
      final scheduler = _RecordingTimerBackgroundScheduler(
        TimerBackgroundPermissionStatus.granted,
      );
      final workoutExerciseId = (await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      ))!;
      final workoutExercise = (await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId),
      ))!;
      final timerId = (await tester.runAsync<String>(
        () => repositories.restTimers.start(
          RestTimerDraft(
            workoutId: workoutExercise.workoutId,
            duration: const Duration(seconds: 90),
          ),
        ),
      ))!;
      final before = (await tester.runAsync(
        () => repositories.restTimers.getById(timerId),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId,
        timerBackgroundScheduler: scheduler,
      );
      await _waitForFinder(tester, find.byKey(TrainingScreen.restStripStopKey));
      expect(_restStripSeconds(tester), inInclusiveRange(87, 90));

      await tester.tap(find.byKey(TrainingScreen.restStripAdjustKey(15)));
      await _settle(tester);

      var timer = (await tester.runAsync(
        () => repositories.restTimers.getById(timerId),
      ))!;
      expect(timer.duration, const Duration(seconds: 105));
      expect(
        timer.deadlineAt.difference(before.deadlineAt),
        const Duration(seconds: 15),
      );
      expect(scheduler.cancels, <String>[timerId]);
      expect(scheduler.schedules.single.deadlineAt, timer.deadlineAt.toUtc());
      expect(_restStripSeconds(tester), inInclusiveRange(102, 105));

      await tester.tap(find.byKey(TrainingScreen.restStripAdjustKey(-15)));
      await _settle(tester);
      await tester.tap(find.byKey(TrainingScreen.restStripAdjustKey(-15)));
      await _settle(tester);

      timer = (await tester.runAsync<RestTimerRecord?>(
        () => repositories.restTimers.getById(timerId),
      ))!;
      expect(timer.duration, const Duration(seconds: 75));
      expect(scheduler.cancels, <String>[timerId, timerId, timerId]);
      expect(scheduler.schedules.last.deadlineAt, timer.deadlineAt.toUtc());
      expect(_restStripSeconds(tester), inInclusiveRange(72, 75));

      await tester.tap(find.byKey(TrainingScreen.restStripStopKey));
      await _settle(tester);

      timer = (await tester.runAsync<RestTimerRecord?>(
        () => repositories.restTimers.getById(timerId),
      ))!;
      expect(timer.status, RestTimerStatus.canceled);
      expect(scheduler.cancels, hasLength(4));
      await _waitForFinder(
        tester,
        find.byKey(TrainingScreen.restStripStartKey),
      );
    });

    _testTrainingScreen(
        'the volume sheet sets the volume Log set starts its rest with', (
      tester,
    ) async {
      final workoutExerciseId = (await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      ))!;
      final workoutExercise = (await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId),
      ))!;
      final timerId = (await tester.runAsync<String>(
        () => repositories.restTimers.start(
          RestTimerDraft(
            workoutId: workoutExercise.workoutId,
            duration: const Duration(seconds: 90),
          ),
        ),
      ))!;

      await _pumpTrainingScreen(tester, repositories, workoutExerciseId);
      await _waitForFinder(tester, find.byKey(TrainingScreen.restStripStopKey));
      expect(find.byKey(TrainingScreen.restTimerVolumeSliderKey), findsNothing);

      await tester.tap(find.textContaining(RegExp(r'^Rest \d')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Alert volume'), findsOneWidget);

      // Drag the thumb past the slider's start: volume 0.
      await tester.drag(
        find.byKey(TrainingScreen.restTimerVolumeSliderKey),
        const Offset(-1000, 0),
      );
      await _settleRepositoryWork(tester);

      final adjusted = await tester.runAsync(
        () => repositories.restTimers.getById(timerId),
      );
      expect(adjusted?.alertVolume, 0);

      // Close the sheet, stop the rest, and log: the new rest keeps volume 0.
      await tester.tapAt(const Offset(400, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(TrainingScreen.restStripStopKey));
      await _settleRepositoryWork(tester);
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '100',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);

      final logged = await tester.runAsync(
        () => repositories.restTimers.getCurrentForWorkout(
          workoutExercise.workoutId,
        ),
      );
      expect(logged?.id, isNot(timerId));
      expect(logged?.alertVolume, 0);
    });

    _testTrainingScreen(
        'keeps in-app rest timer running when alerts are denied', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final workoutExercise = (await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId!),
      ))!;
      final scheduler = _RecordingTimerBackgroundScheduler(
        TimerBackgroundPermissionStatus.denied,
      );

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId!,
        timerBackgroundScheduler: scheduler,
      );

      expect(scheduler.schedules, isEmpty);

      await tester.tap(find.byKey(TrainingScreen.restStripStartKey));
      await _settleRepositoryWork(tester);

      final timer = await tester.runAsync<RestTimerRecord?>(
        () => repositories.restTimers.getCurrentForWorkout(
          workoutExercise.workoutId,
        ),
      );
      expect(timer?.duration, const Duration(seconds: 120));
      expect(timer, isNotNull);
      expect(scheduler.schedules.map((schedule) => schedule.timerId),
          <String>[timer!.id]);
      expect(
        find.textContaining('Background timer alerts are off'),
        findsOneWidget,
      );
      await _waitForFinder(tester, find.byKey(TrainingScreen.restStripStopKey));
    });

    _testTrainingScreen('fires foreground alert for an expired persisted timer',
        (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final workoutExercise = (await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId!),
      ))!;
      final alert = _RecordingRestTimerAlert();
      final timerId = (await tester.runAsync<String>(
        () => repositories.restTimers.start(
          RestTimerDraft(
            workoutId: workoutExercise.workoutId,
            duration: const Duration(seconds: 1),
            alertVolume: 0.25,
          ),
          now: DateTime.utc(2020),
        ),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId!,
        restTimerAlert: alert,
      );
      await _pumpFrames(tester);

      final timer = await tester.runAsync(
        () => repositories.restTimers.getById(timerId),
      );
      expect(alert.volumes, <double>[0.25]);
      expect(timer?.status, RestTimerStatus.expired);
      expect(timer?.alertFiredAt, isNotNull);
    });

    _testTrainingScreen(
        'the rest strip and its ticker survive a Log set auto-advance',
        (tester) async {
      // Regression for: swapping `_stateFuture` on auto-select-next-set
      // used to drop the Training Screen body to `SizedBox.expand()` for a
      // frame, unmounting the rest timer and cancelling its `Timer.periodic`.
      // Runs the PRODUCTION ticker path (`enableRestTimerTicker: true`).
      final benchWorkoutExerciseId = (await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      ))!;
      final benchWorkoutExercise = (await tester.runAsync(
        () => repositories.workoutExercises.getById(benchWorkoutExerciseId),
      ))!;
      final rowWorkoutExerciseId = (await tester.runAsync(
        () => _createWorkoutExerciseInWorkout(
          repositories,
          workoutId: benchWorkoutExercise.workoutId,
          name: 'Barbell Row',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      ))!;
      // A group with >= 2 members is what makes the save auto-advance.
      await tester.runAsync(
        () => repositories.exerciseGroups.create(
          ExerciseGroupDraft(
            workoutId: benchWorkoutExercise.workoutId,
            name: 'A1 superset',
            colorHex: '#2F6FED',
            workoutExerciseIds: <String>[
              benchWorkoutExerciseId,
              rowWorkoutExerciseId,
            ],
          ),
        ),
      );
      // A live, far-from-expiry rest timer: its ticker is actively running.
      await tester.runAsync<String>(
        () => repositories.restTimers.start(
          RestTimerDraft(
            workoutId: benchWorkoutExercise.workoutId,
            duration: const Duration(hours: 1),
          ),
        ),
      );

      await _pumpTrainingScreen(
        tester,
        repositories,
        benchWorkoutExerciseId,
        enableRestTimerTicker: true,
      );
      await _waitForFinder(
        tester,
        find.byKey(TrainingScreen.restStripStopKey),
      );

      // Capture the strip's State identity BEFORE the advance. If the strip
      // is unmounted and remounted, this State (and its ticker) is replaced.
      final stripStateBefore = _restStripState(tester);

      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '100',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);
      // Auto-advance lands on the grouped exercise.
      await _waitForFinder(tester, find.text('Barbell Row'));

      // The strip is still on screen and it is the SAME State object: the
      // ticker was never torn down.
      expect(find.byKey(TrainingScreen.restStripKey), findsOneWidget);
      final stripStateAfter = _restStripState(tester);
      expect(
        identical(stripStateBefore, stripStateAfter),
        isTrue,
        reason: 'The rest strip State (and its ticker) must survive the '
            'Log set auto-advance to the next grouped exercise.',
      );

      await _disposeWidgetTree(tester);
    });

    _testTrainingScreen(
        'fires the 3-2-1 prepare cue exactly once inside the last 3 seconds',
        (tester) async {
      final workoutExerciseId = (await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      ))!;
      final workoutExercise = (await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId),
      ))!;
      final alert = _RecordingRestTimerAlert();
      // 2s remaining => already inside the <= 3s prepare window on first tick,
      // but NOT yet expired (end cue must not fire).
      final timerId = (await tester.runAsync<String>(
        () => repositories.restTimers.start(
          RestTimerDraft(
            workoutId: workoutExercise.workoutId,
            duration: const Duration(seconds: 2),
            alertVolume: 0.5,
          ),
        ),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId,
        restTimerAlert: alert,
        enableRestTimerTicker: true,
      );
      await _pumpFrames(tester);
      // Pump again: the prepare cue must NOT fire a second time (fire-once).
      await _settleRepositoryWork(tester);
      await _pumpFrames(tester);

      expect(
        alert.prepareVolumes,
        <double>[0.5],
        reason: 'The prepare cue fires exactly once, at the slider volume.',
      );
      expect(
        alert.volumes,
        isEmpty,
        reason: 'The end cue must not fire while the timer is still running.',
      );
      final timer = await tester.runAsync(
        () => repositories.restTimers.getById(timerId),
      );
      expect(timer?.prepareAlertFiredAt, isNotNull);
      expect(timer?.status, RestTimerStatus.running);

      await _disposeWidgetTree(tester);
    });

    _testTrainingScreen(
        'suppresses the prepare cue when timer sounds are turned off',
        (tester) async {
      final workoutExerciseId = (await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      ))!;
      final workoutExercise = (await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId),
      ))!;
      final alert = _RecordingRestTimerAlert();
      await tester.runAsync<String>(
        () => repositories.restTimers.start(
          RestTimerDraft(
            workoutId: workoutExercise.workoutId,
            duration: const Duration(seconds: 2),
            alertVolume: 0.5,
          ),
        ),
      );

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId,
        restTimerAlert: alert,
        enableRestTimerTicker: true,
        settingsRepository: InMemorySettingsRepository(
          AppSettings.defaults.copyWith(restTimerSoundsEnabled: false),
        ),
      );
      await _pumpFrames(tester);
      await _settleRepositoryWork(tester);
      await _pumpFrames(tester);

      expect(
        alert.prepareVolumes,
        isEmpty,
        reason: 'Toggle off => no prepare sound/haptic beyond visual.',
      );

      await _disposeWidgetTree(tester);
    });

    _testTrainingScreen('saves comments RPE and alternating unilateral sides', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bulgarian Split Squat',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
          isUnilateral: true,
          usesRpe: true,
        ),
      );
      final workoutExercise = await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId!),
      );

      await _pumpTrainingScreen(tester, repositories, workoutExerciseId!);

      expect(find.byKey(TrainingScreen.commentFieldKey), findsOneWidget);
      expect(find.byKey(TrainingScreen.sideFieldKey), findsOneWidget);
      expect(find.byKey(TrainingScreen.rpeFieldKey), findsOneWidget);

      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '24',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '8',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.commentFieldKey),
        'Smooth left',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.rpeFieldKey),
        '7.5',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);

      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '24',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '8',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.commentFieldKey),
        'Smooth right',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);

      final sets = await tester.runAsync(
        () => repositories.sets.listActiveForWorkout(
          workoutExercise!.workoutId,
        ),
      );
      final logs = await tester.runAsync(
        repositories.activityLog.listEntries,
      );

      expect(sets, hasLength(2));
      expect(sets![0].comment, 'Smooth left');
      expect(sets[0].side, SetSide.left);
      expect(sets[0].rpe, 7.5);
      expect(sets[1].comment, 'Smooth right');
      expect(sets[1].side, SetSide.right);
      expect(sets[1].rpe, isNull);
      expect(
        logs!
            .where(
              (entry) =>
                  entry.entityTable == AppDatabase.loggedSetsTable &&
                  entry.entityId == sets[0].id &&
                  entry.afterImage?['comment'] == 'Smooth left' &&
                  entry.afterImage?['side'] == 'left' &&
                  entry.afterImage?['rpe'] == 7.5,
            )
            .length,
        1,
      );
    });

    for (final ended in <bool>[false, true]) {
      _testTrainingScreen(
          'CUJ 11: the Navigation Panel shows each exercise\'s progress'
          '${ended ? ' and no Now on an ended Workout' : ' and Now'}', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final incline = await tester.runAsync(
          () => _createPlannedExercise(
            repositories,
            name: 'Incline Press',
            planned: List<LoggedSet>.filled(3, _repsValues('8')),
            performedCount: 2,
            endedAt: ended ? DateTime.utc(2026, 11, 2, 7) : null,
          ),
        );
        final workoutId = incline!.workoutId;
        final pullUp = await tester.runAsync(
          () => _createPlannedExercise(
            repositories,
            workoutId: workoutId,
            name: 'Pull-Up',
            planned: List<LoggedSet>.filled(3, _repsValues('8')),
            performedCount: 2,
          ),
        );
        final pushdown = await tester.runAsync(
          () => _createPlannedExercise(
            repositories,
            workoutId: workoutId,
            name: 'Triceps Pushdown',
            planned: List<LoggedSet>.filled(2, _repsValues('12')),
          ),
        );
        final curl = await tester.runAsync(
          () => _createPlannedExercise(
            repositories,
            workoutId: workoutId,
            name: 'Dumbbell Curl',
            planned: List<LoggedSet>.filled(2, _repsValues('10')),
            performedCount: 2,
          ),
        );
        await tester.runAsync(
          () => repositories.exerciseGroups.create(
            ExerciseGroupDraft(
              workoutId: workoutId,
              name: 'Superset A',
              colorHex: '#2F6FED',
              workoutExerciseIds: <String>[
                incline.workoutExerciseId,
                pullUp!.workoutExerciseId,
              ],
            ),
          ),
        );

        await _pumpTrainingScreen(
          tester,
          repositories,
          pushdown!.workoutExerciseId,
        );
        await tester.tap(find.byKey(TrainingScreen.navigationPanelButtonKey));
        await _pumpDrawerAnimation(tester);

        Finder inRow(String workoutExerciseId, Finder matching) {
          return find.descendant(
            of: find.byKey(TrainingScreen.navigationItemKey(workoutExerciseId)),
            matching: matching,
          );
        }

        // The same count text as the Workout screen's cards.
        expect(
          inRow(incline.workoutExerciseId, find.text('2/3 sets')),
          findsOneWidget,
        );
        expect(
          inRow(pullUp!.workoutExerciseId, find.text('2/3 sets')),
          findsOneWidget,
        );
        expect(
          inRow(pushdown.workoutExerciseId, find.text('0/2 sets')),
          findsOneWidget,
        );
        expect(
            inRow(curl!.workoutExerciseId, find.text('Done')), findsOneWidget);
        expect(
          inRow(curl.workoutExerciseId, find.byIcon(Icons.check)),
          findsOneWidget,
        );
        // Now is on the superset's first row, not on the open exercise.
        expect(
          inRow(incline.workoutExerciseId, find.text('Now')),
          ended ? findsNothing : findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(TrainingScreen.navigationPanelKey),
            matching: find.text('Now'),
          ),
          ended ? findsNothing : findsOneWidget,
        );
        if (!ended) {
          expect(
            find.bySemanticsLabel(RegExp('Incline Press.*Now', dotAll: true)),
            findsOneWidget,
          );
        }
        // The open exercise stays highlighted.
        expect(
          tester
              .widget<ListTile>(
                find.byKey(
                  TrainingScreen.navigationItemKey(pushdown.workoutExerciseId),
                ),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<ListTile>(
                find.byKey(
                  TrainingScreen.navigationItemKey(incline.workoutExerciseId),
                ),
              )
              .selected,
          isFalse,
        );
        for (final plan in <_PlanFixture>[incline, pullUp, pushdown, curl]) {
          _expectMinimumTargetSize(
            tester,
            find.byKey(
                TrainingScreen.navigationItemKey(plan.workoutExerciseId)),
          );
        }
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      });
    }

    _testTrainingScreen(
        'navigation drawer lists set counts and jumps exercises', (
      tester,
    ) async {
      final benchWorkoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final benchWorkoutExercise = await tester.runAsync(
        () => repositories.workoutExercises.getById(benchWorkoutExerciseId!),
      );
      final rowWorkoutExerciseId = await tester.runAsync(
        () => _createWorkoutExerciseInWorkout(
          repositories,
          workoutId: benchWorkoutExercise!.workoutId,
          name: 'Barbell Row',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      await tester.runAsync(
        () => _createBenchSet(
          repositories,
          workoutId: benchWorkoutExercise!.workoutId,
          exerciseId: benchWorkoutExercise.exerciseId,
          position: 0,
          load: '80',
          reps: '5',
        ),
      );
      await tester.runAsync(
        () => _createBenchSet(
          repositories,
          workoutId: benchWorkoutExercise!.workoutId,
          exerciseId: benchWorkoutExercise.exerciseId,
          position: 1,
          load: '82.5',
          reps: '4',
        ),
      );

      await _pumpTrainingScreen(
        tester,
        repositories,
        benchWorkoutExerciseId!,
      );

      await tester.tap(find.byKey(TrainingScreen.navigationPanelButtonKey));
      await _pumpDrawerAnimation(tester);

      expect(find.byKey(TrainingScreen.navigationPanelKey), findsOneWidget);
      expect(find.text('Bench Press'), findsWidgets);
      expect(find.text('Barbell Row'), findsOneWidget);
      // Two Planned Sets and none performed: Bench Press is Now.
      expect(find.text('0/2 sets'), findsOneWidget);
      expect(find.text('No sets'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            TrainingScreen.navigationItemKey(benchWorkoutExerciseId),
          ),
          matching: find.text('Now'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(TrainingScreen.navigationItemKey(rowWorkoutExerciseId!)),
      );
      await _pumpDrawerAnimation(tester);

      expect(find.byKey(TrainingScreen.navigationPanelKey), findsNothing);
      expect(find.text('Barbell Row'), findsOneWidget);
      await _disposeWidgetTree(tester);
    });

    test('navigation panel ignores unrelated exercise changes', () async {
      final benchWorkoutExerciseId = await _createWorkoutExercise(
        repositories,
        name: 'Bench Press',
        type: ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.reps],
        ),
      );
      final benchWorkoutExercise =
          await repositories.workoutExercises.getById(benchWorkoutExerciseId);
      final unrelatedExerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Unrelated Curl',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );

      final emissions = <List<String>>[];
      final subscription = watchNavigationPanelExerciseNamesForTesting(
        repositories,
        benchWorkoutExercise!.workoutId,
      ).listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitForCondition(
        () => emissions.any((names) => names.contains('Bench Press')),
      );
      await pumpEventQueue(times: 5);
      final initialEmissionCount = emissions.length;

      await repositories.exercises.rename(
        unrelatedExerciseId,
        name: 'Renamed Unrelated Curl',
        actor: 'tester',
      );
      await pumpEventQueue(times: 5);

      expect(emissions, hasLength(initialEmissionCount));
      expect(emissions.last, contains('Bench Press'));

      await repositories.exercises.rename(
        benchWorkoutExercise.exerciseId,
        name: 'Competition Bench Press',
        actor: 'tester',
      );
      await _waitForCondition(
        () =>
            emissions.length > initialEmissionCount &&
            emissions.last.contains('Competition Bench Press'),
      );
    });

    _testTrainingScreen('opens exercise overview from the navigation drawer', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final workoutExercise = await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId!),
      );
      await tester.runAsync(
        () => _createBenchSet(
          repositories,
          workoutId: workoutExercise!.workoutId,
          exerciseId: workoutExercise.exerciseId,
          position: 0,
          load: '80',
          reps: '5',
        ),
      );

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId!,
      );
      await tester.tap(find.byKey(TrainingScreen.navigationPanelButtonKey));
      await _pumpDrawerAnimation(tester);
      await tester.tap(find.byKey(TrainingScreen.overviewButtonKey(
        workoutExerciseId,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await _waitForFinder(
        tester,
        find.byKey(ExerciseOverviewScreen.historyTabKey),
      );
      expect(find.byKey(ExerciseOverviewScreen.recordsTabKey), findsOneWidget);
      expect(find.text('Bench Press'), findsWidgets);

      await _disposeWidgetTree(tester);
    });

    _testTrainingScreen(
        'creates groups and auto-advances only grouped exercises', (
      tester,
    ) async {
      final benchWorkoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final benchWorkoutExercise = await tester.runAsync(
        () => repositories.workoutExercises.getById(benchWorkoutExerciseId!),
      );
      final rowWorkoutExerciseId = await tester.runAsync(
        () => _createWorkoutExerciseInWorkout(
          repositories,
          workoutId: benchWorkoutExercise!.workoutId,
          name: 'Barbell Row',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final curlWorkoutExerciseId = await tester.runAsync(
        () => _createWorkoutExerciseInWorkout(
          repositories,
          workoutId: benchWorkoutExercise!.workoutId,
          name: 'Curl',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );

      await _pumpTrainingScreen(
        tester,
        repositories,
        benchWorkoutExerciseId!,
      );
      await tester.tap(find.byKey(TrainingScreen.navigationPanelButtonKey));
      await _pumpDrawerAnimation(tester);
      await tester.tap(find.byKey(TrainingScreen.createGroupButtonKey));
      await tester.pump();
      await tester.enterText(
        find.byKey(TrainingScreen.groupNameFieldKey),
        'A1 superset',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.groupColorFieldKey),
        '#ff8800',
      );
      await tester.ensureVisible(
        find.byKey(
          TrainingScreen.groupMemberCheckboxKey(benchWorkoutExerciseId),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          TrainingScreen.groupMemberCheckboxKey(benchWorkoutExerciseId),
        ),
      );
      await tester.ensureVisible(
        find.byKey(
          TrainingScreen.groupMemberCheckboxKey(rowWorkoutExerciseId!),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          TrainingScreen.groupMemberCheckboxKey(rowWorkoutExerciseId),
        ),
      );
      await tester.ensureVisible(find.byKey(TrainingScreen.saveGroupButtonKey));
      await tester.pump();
      await tester.tap(find.byKey(TrainingScreen.saveGroupButtonKey));
      await _settleRepositoryWork(tester);

      final groups = await tester.runAsync(
        () => repositories.exerciseGroups.listActiveForWorkout(
          benchWorkoutExercise!.workoutId,
        ),
      );
      expect(groups, hasLength(1));
      expect(groups!.single.name, 'A1 superset');
      expect(groups.single.colorHex, '#FF8800');

      await tester.tap(
        find.byKey(TrainingScreen.navigationItemKey(benchWorkoutExerciseId)),
      );
      await _pumpDrawerAnimation(tester);
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '100',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);

      await _waitForFinder(tester, find.text('Barbell Row'));

      await tester.tap(find.byKey(TrainingScreen.navigationPanelButtonKey));
      await _pumpDrawerAnimation(tester);
      await tester.tap(
        find.byKey(TrainingScreen.navigationItemKey(curlWorkoutExerciseId!)),
      );
      await _pumpDrawerAnimation(tester);
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '20',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '12',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);

      await _waitForFinder(tester, find.text('Curl'));
      await _disposeWidgetTree(tester);
    });

    _testTrainingScreen(
        'prefills from the latest prior set and saves a new set', (
      tester,
    ) async {
      final exerciseId = await tester.runAsync(
        () => repositories.exercises.create(
          ExerciseDraft(
            name: 'Bench Press',
            type: ExerciseType(
              const <DimensionId>[DimensionId.load, DimensionId.reps],
            ),
          ),
        ),
      );
      final priorWorkoutId = await tester.runAsync(
        () => repositories.workoutSessions.create(
          WorkoutSessionDraft(
            startedAt: DateTime.utc(2026, 6, 1, 5),
            timezone: 'Australia/Brisbane',
          ),
        ),
      );
      final priorSetId = await tester.runAsync(
        () => _createBenchSet(
          repositories,
          workoutId: priorWorkoutId!,
          exerciseId: exerciseId!,
          position: 0,
          load: '82.5',
          reps: '4',
          isCompleted: true,
        ),
      );
      final currentWorkoutId = await tester.runAsync(
        () => repositories.workoutSessions.create(
          WorkoutSessionDraft(
            startedAt: DateTime.utc(2026, 6, 14, 5),
            timezone: 'Australia/Brisbane',
          ),
        ),
      );
      final workoutExerciseId = await tester.runAsync(
        () => repositories.workoutExercises.create(
          WorkoutExerciseDraft(
            workoutId: currentWorkoutId!,
            exerciseId: exerciseId!,
          ),
        ),
      );

      await _pumpTrainingScreen(tester, repositories, workoutExerciseId!);

      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '82.5',
      );
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '4',
      );

      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '85',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);

      final currentSets = await tester.runAsync(
        () => repositories.sets.listActiveForWorkout(currentWorkoutId!),
      );
      final priorSet = await tester.runAsync(
        () => repositories.sets.getById(priorSetId!),
      );

      expect(currentSets, hasLength(1));
      expect(currentSets!.single.id, isNot(priorSetId));
      expect(currentSets.single.values.load?.entered, '85');
      expect(currentSets.single.values.reps?.entered, '4');
      expect(priorSet?.values.load?.entered, '82.5');
      expect(priorSet?.values.reps?.entered, '4');
    });

    _testTrainingScreen(
      'shows a trophy only for logged sets that become headline records',
      (tester) async {
        final exerciseId = await tester.runAsync(
          () => repositories.exercises.create(
            ExerciseDraft(
              name: 'Bench Press',
              type: ExerciseType(
                const <DimensionId>[DimensionId.load, DimensionId.reps],
              ),
            ),
          ),
        );
        final priorWorkoutId = await tester.runAsync(
          () => repositories.workoutSessions.create(
            WorkoutSessionDraft(
              startedAt: DateTime.utc(2026, 6, 1, 5),
              timezone: 'Australia/Brisbane',
            ),
          ),
        );
        await tester.runAsync(
          () => _createBenchSet(
            repositories,
            workoutId: priorWorkoutId!,
            exerciseId: exerciseId!,
            position: 0,
            load: '90',
            reps: '5',
            isCompleted: true,
            actor: 'agent',
          ),
        );
        final currentWorkoutId = await tester.runAsync(
          () => repositories.workoutSessions.create(
            WorkoutSessionDraft(
              startedAt: DateTime.utc(2026, 6, 14, 5),
              timezone: 'Australia/Brisbane',
            ),
          ),
        );
        final workoutExerciseId = await tester.runAsync(
          () => repositories.workoutExercises.create(
            WorkoutExerciseDraft(
              workoutId: currentWorkoutId!,
              exerciseId: exerciseId!,
            ),
          ),
        );
        final setStream = StreamController<List<LoggedSetRecord>>();
        final recordSetIdsStream = StreamController<Set<String>>();
        addTearDown(setStream.close);
        addTearDown(recordSetIdsStream.close);

        await _emitSets(tester, repositories, currentWorkoutId!, setStream);
        await _pumpTrainingScreen(
          tester,
          repositories,
          workoutExerciseId!,
          setsStream: setStream.stream,
          recordSetIdsStream: recordSetIdsStream.stream,
        );
        await _emitSets(tester, repositories, currentWorkoutId, setStream);
        await _emitRecordSetIds(
          tester,
          repositories,
          exerciseId!,
          recordSetIdsStream,
        );

        await tester.enterText(
          find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
          '85',
        );
        await tester.enterText(
          find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
          '5',
        );
        await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
        await _settleRepositoryWork(tester);
        await _emitSets(tester, repositories, currentWorkoutId, setStream);
        await _emitRecordSetIds(
          tester,
          repositories,
          exerciseId,
          recordSetIdsStream,
        );

        final nonRecordSet = (await tester.runAsync(
          () => repositories.sets.listActiveForWorkout(currentWorkoutId),
        ))!
            .single;
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          find.byKey(TrainingScreen.recordTrophyKey(nonRecordSet.id)),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
          '95',
        );
        await tester.enterText(
          find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
          '5',
        );
        await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
        await _settleRepositoryWork(tester);
        await _emitSets(tester, repositories, currentWorkoutId, setStream);
        await _emitRecordSetIds(
          tester,
          repositories,
          exerciseId,
          recordSetIdsStream,
        );

        final currentSets = await tester.runAsync(
          () => repositories.sets.listActiveForWorkout(currentWorkoutId),
        );
        final recordSet = currentSets!.singleWhere(
          (set) => set.values.load?.entered == '95',
        );
        await _waitForFinder(
          tester,
          find.byKey(TrainingScreen.recordTrophyKey(recordSet.id)),
        );
        expect(
          find.byKey(TrainingScreen.recordTrophyKey(nonRecordSet.id)),
          findsNothing,
        );
      },
    );

    _testTrainingScreen('hides record trophies when PR tracking is disabled', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final workoutExercise = await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId!),
      );
      final setId = await tester.runAsync(
        () => _createBenchSet(
          repositories,
          workoutId: workoutExercise!.workoutId,
          exerciseId: workoutExercise.exerciseId,
          position: 0,
          load: '100',
          reps: '5',
          isCompleted: true,
        ),
      );
      final sets = await tester.runAsync(
        () => repositories.sets.listActiveForWorkout(
          workoutExercise!.workoutId,
        ),
      );

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId!,
        setsStream: Stream<List<LoggedSetRecord>>.value(sets!),
        recordSetIdsStream: Stream<Set<String>>.value(<String>{setId!}),
        settingsRepository: InMemorySettingsRepository(
          const AppSettings(prTrackingEnabled: false),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byKey(TrainingScreen.recordTrophyKey(setId)), findsNothing);
    });

    _testTrainingScreen(
      'detects log-time trophies through the analytics provider',
      (tester) async {
        final exerciseId = (await tester.runAsync(
          () => repositories.exercises.create(
            ExerciseDraft(
              name: 'Bench Press',
              type: ExerciseType(
                const <DimensionId>[DimensionId.load, DimensionId.reps],
              ),
            ),
          ),
        ))!;
        final priorWorkoutId = (await tester.runAsync(
          () => repositories.workoutSessions.create(
            WorkoutSessionDraft(
              startedAt: DateTime.utc(2026, 6, 1, 5),
              timezone: 'Australia/Brisbane',
            ),
          ),
        ))!;
        await tester.runAsync(
          () => _createBenchSet(
            repositories,
            workoutId: priorWorkoutId,
            exerciseId: exerciseId,
            position: 0,
            load: '90',
            reps: '5',
            actor: 'agent',
          ),
        );
        final currentWorkoutId = (await tester.runAsync(
          () => repositories.workoutSessions.create(
            WorkoutSessionDraft(
              startedAt: DateTime.utc(2026, 6, 14, 5),
              timezone: 'Australia/Brisbane',
            ),
          ),
        ))!;
        final workoutExerciseId = (await tester.runAsync(
          () => repositories.workoutExercises.create(
            WorkoutExerciseDraft(
              workoutId: currentWorkoutId,
              exerciseId: exerciseId,
            ),
          ),
        ))!;
        final plannedSetId = (await tester.runAsync(
          () => _createBenchSet(
            repositories,
            workoutId: currentWorkoutId,
            exerciseId: exerciseId,
            position: 0,
            load: '82.5',
            reps: '5',
          ),
        ))!;
        final setStream = StreamController<List<LoggedSetRecord>>();
        addTearDown(setStream.close);

        await _emitSets(tester, repositories, currentWorkoutId, setStream);
        await _pumpTrainingScreen(
          tester,
          repositories,
          workoutExerciseId,
          setsStream: setStream.stream,
          useProductionRecordProvider: true,
        );
        await _emitSets(tester, repositories, currentWorkoutId, setStream);
        // Log set fills the planned 82.5 kg x 5, the Current Set.
        await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
        await _settleRepositoryWork(tester);
        await _emitSets(tester, repositories, currentWorkoutId, setStream);
        await _pumpFrames(tester);

        expect(
          find.byKey(TrainingScreen.recordTrophyKey(plannedSetId)),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
          '85',
        );
        await tester.enterText(
          find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
          '5',
        );
        await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
        await _settleRepositoryWork(tester);
        await _emitSets(tester, repositories, currentWorkoutId, setStream);
        await _pumpFrames(tester);

        final nonRecordSet = (await tester.runAsync(
          () => repositories.sets.listActiveForWorkout(currentWorkoutId),
        ))!
            .singleWhere((set) => set.values.load?.entered == '85');
        expect(
          find.byKey(TrainingScreen.recordTrophyKey(nonRecordSet.id)),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
          '95',
        );
        await tester.enterText(
          find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
          '5',
        );
        await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
        await _settleRepositoryWork(tester);
        await _emitSets(tester, repositories, currentWorkoutId, setStream);

        final recordSet = (await tester.runAsync(
          () => repositories.sets.listActiveForWorkout(currentWorkoutId),
        ))!
            .singleWhere((set) => set.values.load?.entered == '95');
        await _waitForFinder(
          tester,
          find.byKey(TrainingScreen.recordTrophyKey(recordSet.id)),
        );
        expect(
          find.byKey(TrainingScreen.recordTrophyKey(nonRecordSet.id)),
          findsNothing,
        );
        expect(
          find.byKey(TrainingScreen.recordTrophyKey(plannedSetId)),
          findsNothing,
        );

        await _disposeWidgetTree(tester);
      },
    );

    _testTrainingScreen('does not show a trophy for completion-only records', (
      tester,
    ) async {
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Mobility Check',
          type: ExerciseType.empty,
        ),
      );
      final workoutExercise = await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId!),
      );
      final setStream = StreamController<List<LoggedSetRecord>>();
      final recordSetIdsStream = StreamController<Set<String>>();
      addTearDown(setStream.close);
      addTearDown(recordSetIdsStream.close);

      await _emitSets(
          tester, repositories, workoutExercise!.workoutId, setStream);
      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId!,
        setsStream: setStream.stream,
        recordSetIdsStream: recordSetIdsStream.stream,
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settleRepositoryWork(tester);
      await _emitSets(
          tester, repositories, workoutExercise.workoutId, setStream);
      await _emitRecordSetIds(
        tester,
        repositories,
        workoutExercise.exerciseId,
        recordSetIdsStream,
      );

      final loggedSet = (await tester.runAsync(
        () => repositories.sets.listActiveForWorkout(workoutExercise.workoutId),
      ))!
          .single;
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('Completed set'), findsOneWidget);
      expect(
        find.byKey(TrainingScreen.recordTrophyKey(loggedSet.id)),
        findsNothing,
      );
    });

    _testTrainingScreen(
      'audited logging controls expose labels targets and contrast',
      (tester) async {
        for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
          final themeName = theme.brightness.name;
          final semantics = tester.ensureSemantics();
          final benchWorkoutExerciseId = (await tester.runAsync(
            () => _createWorkoutExercise(
              repositories,
              name: 'Bench Press $themeName',
              type: ExerciseType(
                const <DimensionId>[DimensionId.load, DimensionId.reps],
              ),
              isUnilateral: true,
            ),
          ))!;
          final benchWorkoutExercise = await tester.runAsync(
            () => repositories.workoutExercises.getById(
              benchWorkoutExerciseId,
            ),
          );
          final rowWorkoutExerciseId = (await tester.runAsync(
            () => _createWorkoutExerciseInWorkout(
              repositories,
              workoutId: benchWorkoutExercise!.workoutId,
              name: 'Barbell Row $themeName',
              type: ExerciseType(
                const <DimensionId>[DimensionId.load, DimensionId.reps],
              ),
            ),
          ))!;
          final setId = (await tester.runAsync(
            () => _createBenchSet(
              repositories,
              workoutId: benchWorkoutExercise!.workoutId,
              exerciseId: benchWorkoutExercise.exerciseId,
              position: 0,
              load: '80',
              reps: '5',
            ),
          ))!;
          final loggedSet = await tester.runAsync(
            () => repositories.sets.getById(setId),
          );
          final groupName = 'A1 superset $themeName';
          await tester.runAsync(
            () => repositories.exerciseGroups.create(
              ExerciseGroupDraft(
                workoutId: benchWorkoutExercise!.workoutId,
                name: groupName,
                colorHex: '#2F6FED',
                workoutExerciseIds: <String>[
                  benchWorkoutExerciseId,
                  rowWorkoutExerciseId,
                ],
              ),
            ),
          );

          // A running rest, so the strip shows its time and buttons.
          await tester.runAsync(
            () => repositories.restTimers.start(
              RestTimerDraft(
                workoutId: benchWorkoutExercise!.workoutId,
                duration: const Duration(seconds: 90),
              ),
            ),
          );

          await _pumpTrainingScreen(
            tester,
            repositories,
            benchWorkoutExerciseId,
            setsStream: Stream<List<LoggedSetRecord>>.value(
              <LoggedSetRecord>[loggedSet!],
            ),
            theme: theme,
            textScaler: TextScaler.linear(2.0),
          );
          await _waitForFinder(
            tester,
            find.byKey(TrainingScreen.setTileKey(setId)),
          );

          expect(find.semantics.byLabel('Decrease Load'), findsOne);
          expect(find.semantics.byLabel('Increase Load'), findsOne);
          expect(find.semantics.byLabel('Decrease rest'), findsOne);
          expect(find.semantics.byLabel('Increase rest'), findsOne);
          expect(
            find.semantics.byLabel(RegExp(r'Set 1, next, 80 kg x 5')),
            findsOne,
          );
          expect(find.semantics.byLabel('Reorder set'), findsOne);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  (widget.properties.customSemanticsActions?.keys.any(
                        (action) => action.label == 'Remove planned set',
                      ) ??
                      false),
            ),
            findsOneWidget,
          );
          expect(find.byTooltip('Left side'), findsOneWidget);
          expect(find.byTooltip('Right side'), findsOneWidget);
          _expectMinimumTargetSize(
            tester,
            find.byKey(TrainingScreen.decrementButtonKey(DimensionId.load)),
          );
          _expectMinimumTargetSize(
            tester,
            find.byKey(TrainingScreen.incrementButtonKey(DimensionId.load)),
          );
          _expectMinimumTargetSize(
            tester,
            find.byKey(TrainingScreen.restAfterDecrementKey),
          );
          _expectMinimumTargetSize(
            tester,
            find.byKey(TrainingScreen.restAfterIncrementKey),
          );
          _expectMinimumTargetSize(
            tester,
            find.byKey(TrainingScreen.addSetButtonKey),
          );
          _expectMinimumTargetSize(
            tester,
            find.byKey(TrainingScreen.addRoundButtonKey),
          );
          _expectMinimumTargetSize(
            tester,
            find.byKey(TrainingScreen.reorderHandleKey(setId)),
          );
          _expectMinimumTargetSize(
            tester,
            find.byKey(TrainingScreen.logSetButtonKey),
          );

          // The rest strip: its time, ±15 s and Stop.
          await _waitForFinder(
            tester,
            find.byKey(TrainingScreen.restStripStopKey),
          );
          expect(
            find.semantics.byLabel(
              RegExp(r'^Rest, 1 minutes (2\d|30) seconds left$'),
            ),
            findsOne,
          );
          expect(find.semantics.byLabel('Rest 15 seconds less'), findsOne);
          expect(find.semantics.byLabel('Rest 15 seconds more'), findsOne);
          expect(find.byTooltip('Stop rest'), findsOneWidget);
          for (final key in <Key>[
            TrainingScreen.restStripAdjustKey(-15),
            TrainingScreen.restStripAdjustKey(15),
            TrainingScreen.restStripStopKey,
          ]) {
            _expectMinimumTargetSize(tester, find.byKey(key));
          }
          // Text scale 2.0: the pinned strip and Log set stay on screen,
          // the strip directly above the button.
          final screen = Offset.zero & tester.view.physicalSize;
          final strip = tester.getRect(find.byKey(TrainingScreen.restStripKey));
          final logSet =
              tester.getRect(find.byKey(TrainingScreen.logSetButtonKey));
          expect(screen.contains(strip.topLeft), isTrue);
          expect(screen.contains(logSet.bottomRight), isTrue);
          expect(strip.bottom, lessThanOrEqualTo(logSet.top));

          await tester.tap(find.byKey(TrainingScreen.navigationPanelButtonKey));
          await _pumpDrawerAnimation(tester);

          expect(
            find.descendant(
              of: find.byKey(TrainingScreen.navigationPanelKey),
              matching: find.textContaining(groupName),
            ),
            // Both members' subtitles and the group's own tile.
            findsNWidgets(3),
          );
          // Barbell Row has no Planned Set, so Log set would not move.
          expect(find.text('$groupName · Round 1 of 1'), findsOneWidget);
          expect(
            find.semantics.byLabel(
              RegExp('Exercise group ${RegExp.escape(groupName)}'),
            ),
            findsWidgets,
          );
          expect(
            find.semantics.byLabel('Group color for $groupName'),
            findsWidgets,
          );
          _expectMinimumTargetSize(
            tester,
            find.byKey(
              TrainingScreen.navigationItemKey(benchWorkoutExerciseId),
            ),
          );
          _expectMinimumTargetSize(
            tester,
            find.byKey(
              TrainingScreen.overviewButtonKey(benchWorkoutExerciseId),
            ),
          );

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          semantics.dispose();
          await _disposeWidgetTree(tester);
        }
      },
    );
  });

  group('log set', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    _testTrainingScreen('CUJ 1: logs a planned Set and Undo reverts it', (
      tester,
    ) async {
      final scheduler = _RecordingTimerBackgroundScheduler(
        TimerBackgroundPermissionStatus.granted,
      );
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: List<LoggedSet>.filled(
            3,
            _loadRepsValues(load: '60', reps: '10'),
          ),
          rest: const Duration(seconds: 90),
        ),
      ))!;
      final ids = plan.setIds;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
        timerBackgroundScheduler: scheduler,
      );
      await _settle(tester);

      expect(_rowLabel(tester, ids[0]), 'Set 1, next, 60 kg x 10');
      expect(_rowLabel(tester, ids[1]), 'Set 2, planned, 60 kg x 10');
      expect(_rowLabel(tester, ids[2]), 'Set 3, planned, 60 kg x 10');
      expect(_rowIsHighlighted(tester, ids[0]), isTrue);
      expect(_rowIsHighlighted(tester, ids[1]), isFalse);
      expect(find.byType(Checkbox), findsNothing);
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '60',
      );
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '10',
      );
      expect(_restText(tester), '1:30');
      expect(_logSetLabel(tester), 'Log set 1 of 3');

      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settle(tester);

      expect(_rowLabel(tester, ids[0]), 'Set 1, done, 60 kg x 10');
      expect(_rowLabel(tester, ids[1]), 'Set 2, next, 60 kg x 10');
      expect(
        find.descendant(
          of: find.byKey(TrainingScreen.setTileKey(ids[0])),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(find.text('Set 1 logged'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(_logSetLabel(tester), 'Log set 2 of 3');
      final timer = await tester.runAsync(
        () => repositories.restTimers.getCurrentForWorkout(plan.workoutId),
      );
      expect(timer?.duration, const Duration(seconds: 90));
      expect(timer?.sourceSetId, ids[0]);
      final logged = await tester.runAsync(
        () => repositories.sets.getById(ids[0]),
      );
      expect(logged?.isCompleted, isTrue);
      expect(logged?.plannedRestAfter, const Duration(seconds: 90));

      await _tapUndo(tester);
      await _settle(tester);

      final undone = await tester.runAsync(
        () => repositories.sets.getById(ids[0]),
      );
      expect(undone?.isCompleted, isFalse);
      expect(
        await tester.runAsync(
          () => repositories.restTimers.getCurrentForWorkout(plan.workoutId),
        ),
        isNull,
      );
      expect(scheduler.cancels, contains(timer!.id));
      expect(_rowLabel(tester, ids[0]), 'Set 1, next, 60 kg x 10');
      expect(_logSetLabel(tester), 'Log set 1 of 3');
    });

    _testTrainingScreen('CUJ 2: a weight missing from the plan carries', (
      tester,
    ) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Incline Press',
          planned: List<LoggedSet>.filled(
            3,
            _loadRepsValues(load: '0', reps: '10'),
          ),
        ),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '26',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settle(tester);

      final sets = (await tester.runAsync(
        () => _setsOf(repositories, plan),
      ))!;
      expect(sets.map((set) => set.isCompleted), <bool>[true, false, false]);
      expect(
        sets.map((set) => set.values.load?.entered),
        <String>['26', '26', '26'],
      );
      expect(
        sets.map((set) => set.values.reps?.entered),
        <String>['10', '10', '10'],
      );
      expect(find.text('Set 1 logged · 2 later sets updated'), findsOneWidget);
      expect(_rowLabel(tester, sets[1].id), 'Set 2, next, 26 kg x 10');
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '26',
      );
    });

    _testTrainingScreen('CUJ 4a: a copy-previous placeholder fills once', (
      tester,
    ) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Pull-Up',
          type: ExerciseType(const <DimensionId>[DimensionId.reps]),
          planned: List<LoggedSet>.filled(3, _repsValues('0')),
        ),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '8',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settle(tester);

      var sets = (await tester.runAsync(() => _setsOf(repositories, plan)))!;
      expect(
        sets.map((set) => set.values.reps?.entered),
        <String>['8', '8', '8'],
      );
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '8',
      );

      // The next Log set needs no typing.
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settle(tester);

      sets = (await tester.runAsync(() => _setsOf(repositories, plan)))!;
      expect(sets.map((set) => set.isCompleted), <bool>[true, true, false]);
      expect(sets[1].values.reps?.entered, '8');
    });

    _testTrainingScreen('CUJ 5: a changed rest runs, carries and is remembered',
        (tester) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: List<LoggedSet>.filled(
            3,
            _loadRepsValues(load: '60', reps: '10'),
          ),
          rest: const Duration(seconds: 90),
        ),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      expect(_restText(tester), '1:30');
      await tester.tap(find.byKey(TrainingScreen.restAfterIncrementKey));
      await tester.pump();
      await tester.tap(find.byKey(TrainingScreen.restAfterIncrementKey));
      await tester.pump();
      expect(_restText(tester), '2:00');

      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settle(tester);

      final timer = await tester.runAsync(
        () => repositories.restTimers.getCurrentForWorkout(plan.workoutId),
      );
      expect(timer?.duration, const Duration(seconds: 120));
      final sets = (await tester.runAsync(() => _setsOf(repositories, plan)))!;
      expect(
        sets.map((set) => set.plannedRestAfter),
        List<Duration>.filled(3, const Duration(seconds: 120)),
      );
      expect(_restText(tester), '2:00');
      expect(
        await tester.runAsync(
          () => repositories.sets.findRememberedRest(plan.exerciseId),
        ),
        const Duration(seconds: 120),
      );

      // The next Workout without a planned rest starts Rest after at 2:00.
      await _disposeWidgetTree(tester);
      final nextWorkoutExerciseId = (await tester.runAsync(() async {
        final workoutId = await repositories.workoutSessions.create(
          WorkoutSessionDraft(
            startedAt: DateTime.utc(2026, 11, 3, 6),
            timezone: 'UTC',
          ),
        );
        return repositories.workoutExercises.create(
          WorkoutExerciseDraft(
            workoutId: workoutId,
            exerciseId: plan.exerciseId,
          ),
        );
      }))!;
      await _pumpTrainingScreen(
        tester,
        repositories,
        nextWorkoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      expect(_logSetLabel(tester), 'Log set');
      expect(_restText(tester), '2:00');
    });

    _testTrainingScreen('CUJ 7: walks a superset round by round', (
      tester,
    ) async {
      final incline = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Incline Press',
          planned: List<LoggedSet>.filled(
            3,
            _loadRepsValues(load: '26', reps: '10'),
          ),
          rest: Duration.zero,
        ),
      ))!;
      final pullUp = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          workoutId: incline.workoutId,
          name: 'Pull-Up',
          type: ExerciseType(const <DimensionId>[DimensionId.reps]),
          planned: List<LoggedSet>.filled(3, _repsValues('8')),
          rest: const Duration(seconds: 60),
        ),
      ))!;
      await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          workoutId: incline.workoutId,
          name: 'Triceps Pushdown',
          planned: List<LoggedSet>.filled(
            2,
            _loadRepsValues(load: '20', reps: '12'),
          ),
          rest: Duration.zero,
        ),
      );
      await tester.runAsync(
        () => repositories.exerciseGroups.create(
          ExerciseGroupDraft(
            workoutId: incline.workoutId,
            name: 'Superset',
            colorHex: '#2F6FED',
            workoutExerciseIds: <String>[
              incline.workoutExerciseId,
              pullUp.workoutExerciseId,
            ],
          ),
        ),
      );

      await _pumpTrainingScreen(
        tester,
        repositories,
        incline.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      expect(
        _contextLine(tester),
        'Superset · Round 1 of 3 · Next: Pull-Up',
      );

      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _waitForContextLine(
        tester,
        'Superset · Round 1 of 3 · Next: Incline Press',
      );
      expect(find.widgetWithText(AppBar, 'Pull-Up'), findsOneWidget);

      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _waitForContextLine(
        tester,
        'Superset · Round 2 of 3 · Next: Pull-Up',
      );
      expect(find.widgetWithText(AppBar, 'Incline Press'), findsOneWidget);

      for (final next in <String>[
        'Superset · Round 2 of 3 · Next: Incline Press',
        'Superset · Round 3 of 3 · Next: Pull-Up',
        // Only Pull-Up has a Set left, so Log set would not move.
        'Superset · Round 3 of 3',
      ]) {
        await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
        await _waitForContextLine(tester, next);
      }
      expect(find.byKey(TrainingScreen.nextExerciseButtonKey), findsNothing);

      // The last Set of the round: the screen stays on Pull-Up.
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _waitForContextLine(tester, 'Superset · All rounds done');
      await _settle(tester);
      expect(find.widgetWithText(AppBar, 'Pull-Up'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Next: Triceps Pushdown'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(TrainingScreen.nextExerciseButtonKey));
      await _waitForFinder(
        tester,
        find.widgetWithText(AppBar, 'Triceps Pushdown'),
      );
      await _settle(tester);
      expect(_logSetLabel(tester), 'Log set 1 of 2');
    });

    _testTrainingScreen(
        'CUJ 8: one more Set after a 0 s plan starts no timer, then Add set',
        (tester) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Triceps Pushdown',
          planned: List<LoggedSet>.filled(
            2,
            _loadRepsValues(load: '20', reps: '12'),
          ),
          rest: Duration.zero,
        ),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      expect(_restText(tester), 'Off');
      for (var i = 0; i < 2; i += 1) {
        await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
        await _settle(tester);
      }
      expect(_logSetLabel(tester), 'Log set');
      expect(_restText(tester), 'Off');

      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settle(tester);

      var sets = (await tester.runAsync(() => _setsOf(repositories, plan)))!;
      expect(sets, hasLength(3));
      expect(sets.every((set) => set.isCompleted), isTrue);
      expect(sets[2].values, _loadRepsValues(load: '20', reps: '12'));
      // The extra Set keeps the plan's Off it was shown, so the Set after
      // it shows Off too rather than falling back to 2:00.
      expect(sets[2].plannedRestAfter, Duration.zero);
      expect(_restText(tester), 'Off');
      expect(find.text('Set 3 logged'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => repositories.restTimers.getCurrentForWorkout(plan.workoutId),
        ),
        isNull,
      );
      expect(find.widgetWithText(AppBar, 'Triceps Pushdown'), findsOneWidget);
      // The button stays usable.
      expect(
        tester
            .widget<FilledButton>(find.byKey(TrainingScreen.logSetButtonKey))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(TrainingScreen.addSetButtonKey));
      await _settle(tester);

      sets = (await tester.runAsync(() => _setsOf(repositories, plan)))!;
      expect(sets, hasLength(4));
      expect(sets[3].isCompleted, isFalse);
      expect(sets[3].values, _loadRepsValues(load: '20', reps: '12'));
      expect(sets[3].plannedRestAfter, Duration.zero);
      expect(_rowLabel(tester, sets[3].id), 'Set 4, next, 20 kg x 12');
      expect(_logSetLabel(tester), 'Log set 4 of 4');
      expect(_restText(tester), 'Off');
    });

    _testTrainingScreen(
        'a rest changed on an unplanned exercise sticks across unchanged Sets',
        (tester) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: const <LoggedSet>[],
        ),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '60',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '10',
      );
      expect(_restText(tester), '2:00');
      for (var step = 0; step < 2; step += 1) {
        await tester.tap(find.byKey(TrainingScreen.restAfterIncrementKey));
        await tester.pump();
      }
      expect(_restText(tester), '2:30');

      // Set 1 with the changed rest, then Sets 2 and 3 left at 2:30.
      for (var index = 0; index < 3; index += 1) {
        await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
        await _settle(tester);
        expect(_restText(tester), '2:30');
        final timer = await tester.runAsync(
          () => repositories.restTimers.getCurrentForWorkout(plan.workoutId),
        );
        expect(timer?.duration, const Duration(seconds: 150));
      }

      final sets = (await tester.runAsync(() => _setsOf(repositories, plan)))!;
      expect(sets, hasLength(3));
      expect(
        sets.map((set) => set.plannedRestAfter),
        List<Duration>.filled(3, const Duration(seconds: 150)),
      );
    });

    _testTrainingScreen('CUJ 9: fixes a logged Set in Update mode', (
      tester,
    ) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: <LoggedSet>[
            _loadRepsValues(load: '60', reps: '9'),
            _loadRepsValues(load: '60', reps: '10'),
            _loadRepsValues(load: '60', reps: '10'),
          ],
          performedCount: 1,
        ),
      ))!;
      final ids = plan.setIds;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      expect(_rowLabel(tester, ids[1]), 'Set 2, next, 60 kg x 10');

      await tester.tap(find.byKey(TrainingScreen.setTileKey(ids[0])));
      await tester.pump();

      expect(_rowIsHighlighted(tester, ids[0]), isTrue);
      expect(_rowIsHighlighted(tester, ids[1]), isFalse);
      expect(find.byKey(TrainingScreen.logSetButtonKey), findsNothing);
      expect(find.byKey(TrainingScreen.updateSetButtonKey), findsOneWidget);
      expect(
        find.byKey(TrainingScreen.deleteSelectedSetButtonKey),
        findsOneWidget,
      );
      expect(find.byKey(TrainingScreen.notDoneButtonKey), findsOneWidget);
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '9',
      );

      // Update writes the fix and carries nothing.
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '62.5',
      );
      await tester.tap(find.byKey(TrainingScreen.updateSetButtonKey));
      await _settle(tester);
      var sets = (await tester.runAsync(() => _setsOf(repositories, plan)))!;
      expect(sets[0].values.load?.entered, '62.5');
      expect(sets[1].values.load?.entered, '60');
      expect(find.byKey(TrainingScreen.logSetButtonKey), findsOneWidget);
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '60',
      );

      // Not done returns it to the plan as the Current Set.
      await tester.tap(find.byKey(TrainingScreen.setTileKey(ids[0])));
      await tester.pump();
      await tester.tap(find.byKey(TrainingScreen.notDoneButtonKey));
      await _settle(tester);

      sets = (await tester.runAsync(() => _setsOf(repositories, plan)))!;
      expect(sets[0].isCompleted, isFalse);
      expect(_rowLabel(tester, ids[0]), 'Set 1, next, 62.5 kg x 9');
      expect(_logSetLabel(tester), 'Log set 1 of 3');
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '62.5',
      );
    });

    _testTrainingScreen('Delete in Update mode shows Undo, which restores', (
      tester,
    ) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: List<LoggedSet>.filled(
            2,
            _loadRepsValues(load: '60', reps: '10'),
          ),
          performedCount: 1,
        ),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      await tester.tap(find.byKey(TrainingScreen.setTileKey(plan.setIds[0])));
      await tester.pump();
      await tester.tap(find.byKey(TrainingScreen.deleteSelectedSetButtonKey));
      await _settle(tester);

      expect(find.text('Set deleted'), findsOneWidget);
      expect(
          find.byKey(TrainingScreen.setTileKey(plan.setIds[0])), findsNothing);
      expect(_logSetLabel(tester), 'Log set 1 of 1');

      await _tapUndo(tester);
      await _settle(tester);
      expect(
        find.byKey(TrainingScreen.setTileKey(plan.setIds[0])),
        findsOneWidget,
      );
      expect(_logSetLabel(tester), 'Log set 2 of 2');
    });

    _testTrainingScreen('CUJ 10: swiping a planned Set away offers Undo', (
      tester,
    ) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: List<LoggedSet>.filled(
            3,
            _loadRepsValues(load: '60', reps: '10'),
          ),
        ),
      ))!;
      final third = plan.setIds[2];

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      await tester.drag(
        find.byKey(TrainingScreen.setTileKey(third)),
        const Offset(-700, 0),
      );
      // The slide out, then the resize, before Dismissible reports it.
      for (var frame = 0; frame < 4; frame += 1) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await _settle(tester);

      expect(find.byKey(TrainingScreen.setTileKey(third)), findsNothing);
      expect(find.text('Planned set removed'), findsOneWidget);
      expect(
        (await tester.runAsync(() => repositories.sets.getById(third)))
            ?.deletedAt,
        isNotNull,
      );
      expect(_logSetLabel(tester), 'Log set 1 of 2');

      await _tapUndo(tester);
      await _settle(tester);

      expect(find.byKey(TrainingScreen.setTileKey(third)), findsOneWidget);
      expect(_rowLabel(tester, third), 'Set 3, planned, 60 kg x 10');
      expect(_logSetLabel(tester), 'Log set 1 of 3');
    });

    _testTrainingScreen('a double tap on Log set logs once', (tester) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: List<LoggedSet>.filled(
            3,
            _loadRepsValues(load: '60', reps: '10'),
          ),
        ),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settle(tester);

      final sets = (await tester.runAsync(() => _setsOf(repositories, plan)))!;
      expect(sets.map((set) => set.isCompleted), <bool>[true, false, false]);
    });

    _testTrainingScreen(
        'a second tap after the write but before the superset move is ignored',
        (tester) async {
      // Holds the rest's start after the Set is written, so a second tap
      // lands after the Sets stream shows Set 1 logged but before the
      // screen moves to Pull-Up.
      final gate = _RestTimerReadGate();
      final gatedDatabase =
          AppDatabase(NativeDatabase.memory().interceptWith(gate));
      addTearDown(() => tester.runAsync(gatedDatabase.close));
      final gatedRepositories = TrainingRepositories(gatedDatabase);
      final incline = (await tester.runAsync(
        () => _createPlannedExercise(
          gatedRepositories,
          name: 'Incline Press',
          planned: List<LoggedSet>.filled(
            3,
            _loadRepsValues(load: '26', reps: '10'),
          ),
          rest: const Duration(seconds: 60),
        ),
      ))!;
      final pullUp = (await tester.runAsync(
        () => _createPlannedExercise(
          gatedRepositories,
          workoutId: incline.workoutId,
          name: 'Pull-Up',
          type: ExerciseType(const <DimensionId>[DimensionId.reps]),
          planned: List<LoggedSet>.filled(3, _repsValues('8')),
          rest: const Duration(seconds: 60),
        ),
      ))!;
      await tester.runAsync(
        () => gatedRepositories.exerciseGroups.create(
          ExerciseGroupDraft(
            workoutId: incline.workoutId,
            name: 'Superset',
            colorHex: '#2F6FED',
            workoutExerciseIds: <String>[
              incline.workoutExerciseId,
              pullUp.workoutExerciseId,
            ],
          ),
        ),
      );

      await _pumpTrainingScreen(
        tester,
        gatedRepositories,
        incline.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      final ids = incline.setIds;

      gate.arm();
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      for (var attempt = 0;
          attempt < 50 &&
              _rowLabel(tester, ids[0]) != 'Set 1, done, 26 kg x 10';
          attempt += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(_rowLabel(tester, ids[0]), 'Set 1, done, 26 kg x 10');
      expect(gate.holding, isTrue);
      expect(find.widgetWithText(AppBar, 'Incline Press'), findsOneWidget);
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      gate.release();
      await _settle(tester);

      final sets =
          (await tester.runAsync(() => _setsOf(gatedRepositories, incline)))!;
      expect(sets.map((set) => set.isCompleted), <bool>[true, false, false]);
      expect(sets.first.id, ids.first);
      expect(find.widgetWithText(AppBar, 'Pull-Up'), findsOneWidget);
    });

    _testTrainingScreen('a kg plan on an imperial unit setting logs kg', (
      tester,
    ) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: <LoggedSet>[_loadRepsValues(load: '60', reps: '5')],
        ),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
        settingsRepository: InMemorySettingsRepository(
          AppSettings.defaults.copyWith(unitSystem: UnitSystem.imperial),
        ),
      );
      await _settle(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
            )
            .decoration
            ?.suffixText,
        'kg',
      );

      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settle(tester);

      final logged = (await tester.runAsync(
        () => repositories.sets.getById(plan.setIds.single),
      ))!;
      expect(logged.isCompleted, isTrue);
      expect(logged.values.load?.unit, TrainingUnit.kilogram);
    });

    _testTrainingScreen('Log set on an ended Workout starts no timer', (
      tester,
    ) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: <LoggedSet>[_loadRepsValues(load: '60', reps: '5')],
          rest: const Duration(seconds: 90),
          endedAt: DateTime.utc(2026, 11, 2, 7),
        ),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settle(tester);

      expect(
        (await tester.runAsync(
          () => repositories.sets.getById(plan.setIds.single),
        ))
            ?.isCompleted,
        isTrue,
      );
      expect(
        await tester.runAsync(
          () => repositories.restTimers.getCurrentForWorkout(plan.workoutId),
        ),
        isNull,
      );
    });

    _testTrainingScreen('a hard reject shows "Set not logged"', (tester) async {
      final workoutExerciseId = (await tester.runAsync(
        () => _createWorkoutExercise(
          repositories,
          name: 'Bench Press',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      ))!;
      final workoutExercise = (await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId),
      ))!;

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '2000',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );
      await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
      await _settle(tester);

      expect(
        find.text('Set not logged: Load must be no more than 1000 kg.'),
        findsOneWidget,
      );
      expect(find.text('Set 1 logged'), findsNothing);
      expect(
        await tester.runAsync(
          () => repositories.sets.listActiveForWorkout(
            workoutExercise.workoutId,
          ),
        ),
        isEmpty,
      );
    });

    _testTrainingScreen('a sync reloads a clean form but keeps a stepped value',
        (tester) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: List<LoggedSet>.filled(
            3,
            _loadRepsValues(load: '60', reps: '10'),
          ),
        ),
      ))!;
      final current = plan.setIds[0];

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);

      await tester.runAsync(
        () => repositories.sets.updateValues(
          current,
          values: _loadRepsValues(load: '60', reps: '8'),
          actor: 'sync',
        ),
      );
      await _settle(tester);
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '8',
      );

      await tester.tap(
        find.byKey(TrainingScreen.incrementButtonKey(DimensionId.load)),
      );
      await tester.pump();
      await tester.runAsync(
        () => repositories.sets.updateValues(
          current,
          values: _loadRepsValues(load: '60', reps: '7'),
          actor: 'sync',
        ),
      );
      await _settle(tester);

      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '62.5',
      );
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '8',
      );
      expect(_rowLabel(tester, current), 'Set 1, next, 60 kg x 7');
    });

    _testTrainingScreen(
        'Update mode survives a sync and ends when its Set is un-completed',
        (tester) async {
      final plan = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: List<LoggedSet>.filled(
            3,
            _loadRepsValues(load: '60', reps: '10'),
          ),
          performedCount: 1,
        ),
      ))!;
      final ids = plan.setIds;

      await _pumpTrainingScreen(
        tester,
        repositories,
        plan.workoutExerciseId,
        liveSets: true,
      );
      await _settle(tester);
      await tester.tap(find.byKey(TrainingScreen.setTileKey(ids[0])));
      await tester.pump();
      expect(find.byKey(TrainingScreen.updateSetButtonKey), findsOneWidget);

      await tester.runAsync(
        () => repositories.sets.updateValues(
          ids[1],
          values: _loadRepsValues(load: '65', reps: '10'),
          actor: 'sync',
        ),
      );
      await _settle(tester);
      expect(find.byKey(TrainingScreen.updateSetButtonKey), findsOneWidget);
      expect(_rowLabel(tester, ids[1]), 'Set 2, next, 65 kg x 10');

      await tester.runAsync(
        () => repositories.sets.setCompleted(
          ids[0],
          isCompleted: false,
          actor: 'sync',
        ),
      );
      await _settle(tester);
      expect(find.byKey(TrainingScreen.updateSetButtonKey), findsNothing);
      expect(_logSetLabel(tester), 'Log set 1 of 3');
      expect(_rowLabel(tester, ids[0]), 'Set 1, next, 60 kg x 10');
    });

    _testTrainingScreen(
        'text scale 2.0 on a phone keeps the strip and Log set visible', (
      tester,
    ) async {
      final bench = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          name: 'Bench Press',
          planned: List<LoggedSet>.filled(
            3,
            _loadRepsValues(load: '60', reps: '10'),
          ),
          rest: const Duration(seconds: 90),
          performedCount: 1,
        ),
      ))!;
      final row = (await tester.runAsync(
        () => _createPlannedExercise(
          repositories,
          workoutId: bench.workoutId,
          name: 'Barbell Row',
          planned: List<LoggedSet>.filled(
            3,
            _loadRepsValues(load: '50', reps: '10'),
          ),
        ),
      ))!;
      await tester.runAsync(
        () => repositories.exerciseGroups.create(
          ExerciseGroupDraft(
            workoutId: bench.workoutId,
            name: 'A1 superset',
            colorHex: '#2F6FED',
            workoutExerciseIds: <String>[
              bench.workoutExerciseId,
              row.workoutExerciseId,
            ],
          ),
        ),
      );
      await tester.runAsync(
        () => repositories.restTimers.start(
          RestTimerDraft(
            workoutId: bench.workoutId,
            duration: const Duration(minutes: 10),
          ),
        ),
      );

      await _pumpTrainingScreen(
        tester,
        repositories,
        bench.workoutExerciseId,
        liveSets: true,
        textScaler: TextScaler.linear(2.0),
        surfaceSize: const Size(412, 915),
      );
      await _settle(tester);
      await _waitForFinder(tester, find.byKey(TrainingScreen.restStripStopKey));

      expect(tester.takeException(), isNull);
      expect(_contextLine(tester), isNotNull);
      expect(_logSetLabel(tester), 'Log set 2 of 3');
      final screen = Offset.zero & tester.view.physicalSize;
      final strip = tester.getRect(find.byKey(TrainingScreen.restStripKey));
      final logSet = tester.getRect(find.byKey(TrainingScreen.logSetButtonKey));
      expect(screen.contains(strip.topLeft), isTrue);
      expect(screen.contains(logSet.bottomRight), isTrue);
      expect(strip.bottom, lessThanOrEqualTo(logSet.top));
      for (final key in <Key>[
        TrainingScreen.restStripAdjustKey(-15),
        TrainingScreen.restStripAdjustKey(15),
        TrainingScreen.restStripStopKey,
        TrainingScreen.logSetButtonKey,
      ]) {
        _expectMinimumTargetSize(tester, find.byKey(key));
      }
    });
  });

  group('kill and reopen', () {
    _testTrainingScreen(
        'CUJ 14: after a kill, Set 3 is current and the rest resumes', (
      tester,
    ) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('perennia_cuj14_'),
      ))!;
      final file = File('${directory.path}/perennia.sqlite');
      AppDatabase? database = AppDatabase.openFile(file);
      try {
        var repositories = TrainingRepositories(database);
        final bench = (await tester.runAsync(
          () => _createPlannedExercise(
            repositories,
            name: 'Bench Press',
            planned: List<LoggedSet>.filled(
              3,
              _loadRepsValues(load: '60', reps: '10'),
            ),
            rest: const Duration(seconds: 90),
            performedCount: 1,
          ),
        ))!;
        final row = (await tester.runAsync(
          () => _createPlannedExercise(
            repositories,
            workoutId: bench.workoutId,
            name: 'Barbell Row',
            planned: List<LoggedSet>.filled(
              3,
              _loadRepsValues(load: '50', reps: '10'),
            ),
            performedCount: 2,
          ),
        ))!;
        await tester.runAsync(
          () => repositories.exerciseGroups.create(
            ExerciseGroupDraft(
              workoutId: bench.workoutId,
              name: 'A1 superset',
              colorHex: '#2F6FED',
              workoutExerciseIds: <String>[
                bench.workoutExerciseId,
                row.workoutExerciseId,
              ],
            ),
          ),
        );

        await _pumpTrainingScreen(
          tester,
          repositories,
          bench.workoutExerciseId,
          liveSets: true,
        );
        await _settle(tester);
        expect(_logSetLabel(tester), 'Log set 2 of 3');
        await tester.tap(find.byKey(TrainingScreen.logSetButtonKey));
        await _settle(tester);
        final timer = (await tester.runAsync(
          () => repositories.restTimers.getCurrentForWorkout(bench.workoutId),
        ))!;
        expect(timer.sourceSetId, bench.setIds[1]);
        expect(timer.duration, const Duration(seconds: 90));

        // Kill: the tree goes and the database closes with the rest running.
        await _disposeWidgetTree(tester);
        await tester.runAsync(() => database!.close());
        database = null;

        // Reopen the same file and rebuild the screen on Bench Press.
        database = AppDatabase.openFile(file);
        repositories = TrainingRepositories(database);
        await _pumpTrainingScreen(
          tester,
          repositories,
          bench.workoutExerciseId,
          liveSets: true,
        );
        await _settle(tester);

        expect(_rowLabel(tester, bench.setIds[0]), 'Set 1, done, 60 kg x 10');
        expect(_rowLabel(tester, bench.setIds[1]), 'Set 2, done, 60 kg x 10');
        expect(_rowLabel(tester, bench.setIds[2]), 'Set 3, next, 60 kg x 10');
        expect(_logSetLabel(tester), 'Log set 3 of 3');
        expect(
          _contextLine(tester),
          'A1 superset · Round 3 of 3 · Next: Barbell Row',
        );
        final resumed = (await tester.runAsync(
          () => repositories.restTimers.getCurrentForWorkout(bench.workoutId),
        ))!;
        expect(resumed.id, timer.id);
        expect(resumed.status, RestTimerStatus.running);
        expect(resumed.deadlineAt, timer.deadlineAt);
        await _waitForFinder(
          tester,
          find.byKey(TrainingScreen.restStripStopKey),
        );
        final left = resumed.deadlineAt.difference(DateTime.now().toUtc());
        expect(
          _restStripSeconds(tester),
          inInclusiveRange(left.inSeconds - 2, left.inSeconds + 1),
        );
      } finally {
        await _disposeWidgetTree(tester);
        final open = database;
        await tester.runAsync(() async {
          await open?.close();
          await directory.delete(recursive: true);
        });
      }
    });
  });
}

/// A widget test of the Training Screen that always tears the tree down
/// with [_disposeWidgetTree]: the screen holds live Drift streams for the
/// whole Workout, whose cancellation leaves timers the binding must run.
void _testTrainingScreen(
  String description,
  WidgetTesterCallback callback,
) {
  testWidgets(description, (tester) async {
    try {
      await callback(tester);
    } finally {
      await _disposeWidgetTree(tester);
    }
  });
}

Future<String> _createWorkoutExercise(
  TrainingRepositories repositories, {
  required String name,
  required ExerciseType type,
  bool isUnilateral = false,
  bool usesRpe = false,
}) async {
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: name,
      type: type,
      isUnilateral: isUnilateral,
      usesRpe: usesRpe,
    ),
  );
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 6, 14, 6),
      timezone: 'Australia/Brisbane',
    ),
  );
  return repositories.workoutExercises.create(
    WorkoutExerciseDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
    ),
  );
}

Future<String> _createWorkoutExerciseInWorkout(
  TrainingRepositories repositories, {
  required String workoutId,
  required String name,
  required ExerciseType type,
}) async {
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: name,
      type: type,
    ),
  );
  return repositories.workoutExercises.create(
    WorkoutExerciseDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
    ),
  );
}

Future<String> _createBenchSet(
  TrainingRepositories repositories, {
  required String workoutId,
  required String exerciseId,
  required int position,
  required String load,
  required String reps,
  bool isCompleted = false,
  String actor = 'app',
}) {
  return repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
      position: position,
      values: _loadRepsValues(load: load, reps: reps),
      isCompleted: isCompleted,
    ),
    actor: actor,
  );
}

LoggedSet _loadRepsValues({
  required String load,
  required String reps,
}) {
  return LoggedSet.fromValues(
    <SetDimensionValue>[
      SetDimensionValue(
        dimension: DimensionId.load,
        entered: load,
        unit: TrainingUnit.kilogram,
      ),
      SetDimensionValue(
        dimension: DimensionId.reps,
        entered: reps,
        unit: TrainingUnit.repetition,
      ),
    ],
  );
}

Future<void> _pumpTrainingScreen(
  WidgetTester tester,
  TrainingRepositories repositories,
  String workoutExerciseId, {
  Stream<List<LoggedSetRecord>>? setsStream,
  Stream<Set<String>>? recordSetIdsStream,
  bool useProductionRecordProvider = false,
  RestTimerAlert? restTimerAlert,
  TimerBackgroundScheduler? timerBackgroundScheduler,
  SettingsRepository? settingsRepository,
  ThemeData? theme,
  TextScaler? textScaler,
  bool enableRestTimerTicker = false,
  bool liveSets = false,
  Size surfaceSize = const Size(800, 1600),
}) async {
  // A phone-tall surface, so the rows, the form and the pinned buttons are
  // all on screen without scrolling.
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final initialWorkoutExercise = await tester.runAsync(
    () => repositories.workoutExercises.getById(workoutExerciseId),
  );
  final initialExercise = await tester.runAsync(
    () => repositories.exercises.getById(initialWorkoutExercise!.exerciseId),
  );
  final initialPriorSet = await tester.runAsync(
    () => repositories.sets.findLatestPriorForExercise(
      exerciseId: initialWorkoutExercise!.exerciseId,
      beforeWorkoutId: initialWorkoutExercise.workoutId,
      dimensions: initialExercise!.type.dimensions,
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => repositories.database),
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        if (settingsRepository != null)
          settingsRepositoryProvider.overrideWith((ref) => settingsRepository),
        if (restTimerAlert != null)
          restTimerAlertProvider.overrideWith((ref) => restTimerAlert),
        if (timerBackgroundScheduler != null)
          timerBackgroundSchedulerProvider.overrideWith(
            (ref) => timerBackgroundScheduler,
          ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) {
          final scaler = textScaler;
          if (scaler == null || child == null) {
            return child ?? const SizedBox.shrink();
          }
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: child,
          );
        },
        home: TrainingScreen(
          workoutExerciseId: workoutExerciseId,
          initialWorkoutExercise: initialWorkoutExercise,
          initialExercise: initialExercise,
          initialPriorSet: initialPriorSet,
          setsStream: liveSets
              ? null
              : setsStream ??
                  Stream<List<LoggedSetRecord>>.value(
                    const <LoggedSetRecord>[],
                  ),
          recordSetIdsStream: useProductionRecordProvider
              ? recordSetIdsStream
              : recordSetIdsStream ??
                  Stream<Set<String>>.value(const <String>{}),
          enableRestTimerTicker: enableRestTimerTicker,
        ),
      ),
    ),
  );
  await _waitForFinder(
    tester,
    find.byWidgetPredicate(
      (widget) =>
          widget.key == TrainingScreen.logSetButtonKey ||
          widget.key == TrainingScreen.updateSetButtonKey,
    ),
  );
}

/// Resolves the rest strip's `State`, which owns the ticker. Its key sits
/// on the strip's root box, so walk up to the enclosing [RestStrip].
State _restStripState(WidgetTester tester) {
  return tester.state(
    find.ancestor(
      of: find.byKey(TrainingScreen.restStripKey),
      matching: find.byType(RestStrip),
    ),
  );
}

/// The strip's visible remaining time ("Rest 1:12") in seconds. The strip
/// counts down on the real clock, so callers allow for a few seconds.
int _restStripSeconds(WidgetTester tester) {
  final text = tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(TrainingScreen.restStripKey),
          matching: find.textContaining(RegExp(r'^Rest \d')),
        ),
      )
      .data!;
  final match = RegExp(r'^Rest (\d+):(\d\d)$').firstMatch(text);
  if (match == null) {
    fail('The rest strip reads "$text".');
  }
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

void _expectMinimumTargetSize(WidgetTester tester, Finder finder) {
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(48));
  expect(size.height, greaterThanOrEqualTo(48));
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _waitForFinder(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  fail('Timed out waiting for $finder.');
}

Future<void> _waitForCondition(
  bool Function() condition, {
  int attempts = 50,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (condition()) {
      return;
    }
  }

  fail('Timed out waiting for condition.');
}

String _fieldText(WidgetTester tester, Key key) {
  final field = tester.widget<TextField>(find.byKey(key));
  return field.controller?.text ?? '';
}

Future<void> _settleRepositoryWork(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pump();
}

Future<void> _pumpDrawerAnimation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _disposeWidgetTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _pumpFrames(tester);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await _pumpFrames(tester);
}

class _RecordingRestTimerAlert implements RestTimerAlert {
  final volumes = <double>[];
  final prepareVolumes = <double>[];

  @override
  Future<void> fire(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> firePrepare(double volume) async {
    prepareVolumes.add(volume);
  }
}

/// Once armed, holds the first read of the rest timer that follows a rest
/// timer insert (the Training Screen reading back the timer it started)
/// until [release].
class _RestTimerReadGate extends QueryInterceptor {
  var _armed = false;
  var _inserted = false;
  final _released = Completer<void>();
  var holding = false;

  void arm() => _armed = true;

  void release() {
    if (!_released.isCompleted) {
      _released.complete();
    }
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_armed && statement.contains(AppDatabase.restTimersTable)) {
      _inserted = true;
    }
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (_inserted && statement.contains(AppDatabase.restTimersTable)) {
      _inserted = false;
      _armed = false;
      holding = true;
      await _released.future;
      holding = false;
    }
    return super.runSelect(executor, statement, args);
  }
}

class _RecordingTimerBackgroundScheduler implements TimerBackgroundScheduler {
  _RecordingTimerBackgroundScheduler(this.status);

  final TimerBackgroundPermissionStatus status;
  final schedules = <TimerBackgroundSchedule>[];
  final cancels = <String>[];

  @override
  Future<TimerBackgroundPermissionStatus> requestPermissionIfNeeded() async {
    return status;
  }

  @override
  Future<TimerBackgroundPermissionStatus> notificationPermissionStatus() async {
    return status;
  }

  @override
  Future<TimerBackgroundPermissionStatus> schedule(
    TimerBackgroundSchedule schedule,
  ) async {
    schedules.add(schedule);
    return status;
  }

  @override
  Future<void> cancel(String timerId) async {
    cancels.add(timerId);
  }
}

Future<void> _emitSets(
  WidgetTester tester,
  TrainingRepositories repositories,
  String workoutId,
  StreamController<List<LoggedSetRecord>> controller,
) async {
  final sets = await tester.runAsync(
    () => repositories.sets.listActiveForWorkout(workoutId),
  );
  controller.add(sets ?? const <LoggedSetRecord>[]);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _emitRecordSetIds(
  WidgetTester tester,
  TrainingRepositories repositories,
  String exerciseId,
  StreamController<Set<String>> controller,
) async {
  final result = await tester.runAsync(
    () => ExerciseAnalyticsRepository(
      repositories.database,
    ).getForExercise(exerciseId),
  );
  controller.add(
    result?.headlineRecords.map((record) => record.setId).toSet() ??
        const <String>{},
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

class _PlanFixture {
  const _PlanFixture({
    required this.workoutId,
    required this.exerciseId,
    required this.workoutExerciseId,
    required this.setIds,
  });

  final String workoutId;
  final String exerciseId;
  final String workoutExerciseId;

  /// The Sets in plan order.
  final List<String> setIds;
}

/// An exercise in a Workout with [planned] Sets, the first
/// [performedCount] of them already performed, each with [rest].
Future<_PlanFixture> _createPlannedExercise(
  TrainingRepositories repositories, {
  String? workoutId,
  required String name,
  ExerciseType? type,
  required List<LoggedSet> planned,
  Duration? rest,
  int performedCount = 0,
  DateTime? endedAt,
}) async {
  final resolvedWorkoutId = workoutId ??
      await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 11, 2, 6),
          timezone: 'UTC',
          endedAt: endedAt,
        ),
      );
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: name,
      type: type ??
          ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
    ),
  );
  final workoutExerciseId = await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: resolvedWorkoutId, exerciseId: exerciseId),
  );
  final setIds = <String>[];
  for (var index = 0; index < planned.length; index += 1) {
    final position =
        await repositories.sets.nextPositionForWorkout(resolvedWorkoutId);
    setIds.add(
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: resolvedWorkoutId,
          exerciseId: exerciseId,
          position: position,
          values: planned[index],
          plannedRestAfter: rest,
          isCompleted: index < performedCount,
        ),
      ),
    );
  }
  return _PlanFixture(
    workoutId: resolvedWorkoutId,
    exerciseId: exerciseId,
    workoutExerciseId: workoutExerciseId,
    setIds: setIds,
  );
}

Future<List<LoggedSetRecord>> _setsOf(
  TrainingRepositories repositories,
  _PlanFixture plan,
) async {
  final sets = await repositories.sets.listActiveForWorkout(plan.workoutId);
  return sets.where((set) => set.exerciseId == plan.exerciseId).toList()
    ..sort((a, b) {
      final byPosition = a.position.compareTo(b.position);
      return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
    });
}

LoggedSet _repsValues(String reps) {
  return LoggedSet.fromValues(<SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.reps,
      entered: reps,
      unit: TrainingUnit.repetition,
    ),
  ]);
}

/// A Set row's semantics label ("Set 1, next, 60 kg x 10").
String _rowLabel(WidgetTester tester, String setId) {
  final labels = tester
      .widgetList<Semantics>(
        find.descendant(
          of: find.byKey(TrainingScreen.setTileKey(setId)),
          matching: find.byType(Semantics),
        ),
      )
      .map((semantics) => semantics.properties.label)
      .whereType<String>();
  return labels.firstWhere((label) => label.startsWith('Set '));
}

bool _rowIsHighlighted(WidgetTester tester, String setId) {
  return tester
      .widget<ListTile>(
        find.descendant(
          of: find.byKey(TrainingScreen.setTileKey(setId)),
          matching: find.byType(ListTile),
        ),
      )
      .selected;
}

String _logSetLabel(WidgetTester tester) {
  return tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(TrainingScreen.logSetButtonKey),
          matching: find.byType(Text),
        ),
      )
      .data!;
}

String _restText(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(TrainingScreen.restAfterValueKey))
      .data!;
}

String? _contextLine(WidgetTester tester) {
  final finder = find.byKey(TrainingScreen.contextLineKey);
  return finder.evaluate().isEmpty ? null : tester.widget<Text>(finder).data;
}

Future<void> _waitForContextLine(WidgetTester tester, String expected) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (_contextLine(tester) == expected) {
      return;
    }
  }
  fail('Timed out waiting for the context line "$expected"; it reads '
      '"${_contextLine(tester)}".');
}

/// Lets a tap's repository writes, and the Drift streams they wake, finish.
Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 6; round += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Taps the confirmation's Undo once the snack bar has finished sliding in.
Future<void> _tapUndo(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
}
