import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
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

    testWidgets('renders exactly the fields for a load and reps exercise', (
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

    testWidgets('uses the settings default increment for load steppers', (
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

    testWidgets('renders exactly the fields for a timed exercise', (
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

    testWidgets('increments and decrements dimension inputs by defaults', (
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

    testWidgets('saves a self-describing set for the workout exercise', (
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
      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
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

    testWidgets(
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
        await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
        await _settleRepositoryWork(tester);
        await _emitSets(
          tester,
          repositories,
          workoutExercise!.workoutId,
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

    testWidgets('completed set rows hide completion status and checkbox', (
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
      final loggedSet = await tester.runAsync(
        () => repositories.sets.getById(setId!),
      );
      final setStream = StreamController<List<LoggedSetRecord>>();
      addTearDown(setStream.close);

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId!,
        setsStream: setStream.stream,
      );
      setStream.add(<LoggedSetRecord>[loggedSet!]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byKey(TrainingScreen.setTileKey(setId!)), findsOneWidget);
      expect(find.text('100 kg x 5'), findsOneWidget);
      expect(
        find.byKey(TrainingScreen.completeSetCheckboxKey(setId)),
        findsNothing,
      );
      expect(find.text('In progress'), findsNothing);
      expect(find.text('Complete'), findsNothing);
    });

    testWidgets('keeps saved dimensions as defaults for the next set', (
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
      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
      await _settleRepositoryWork(tester);

      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '100',
      );
      expect(
        _fieldText(tester, TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );

      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
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

    testWidgets('auto-starts rest timer on save and supports manual controls', (
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

      await _pumpTrainingScreen(tester, repositories, workoutExerciseId!);

      expect(find.byKey(TrainingScreen.restTimerPanelKey), findsOneWidget);
      expect(
        _fieldText(tester, TrainingScreen.restTimerDurationFieldKey),
        '120',
      );

      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '100',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );
      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
      await _settleRepositoryWork(tester);

      RestTimerRecord? timer = await tester.runAsync<RestTimerRecord?>(
        () => repositories.restTimers.getCurrentForWorkout(
          workoutExercise.workoutId,
        ),
      );
      expect(timer?.duration, const Duration(seconds: 120));
      expect(timer?.sourceSetId, isNotNull);

      await _waitForFinder(
        tester,
        find.byKey(TrainingScreen.restTimerCancelButtonKey),
      );
      await tester.tap(find.byKey(TrainingScreen.restTimerCancelButtonKey));
      await _settleRepositoryWork(tester);

      timer = await tester.runAsync<RestTimerRecord?>(
        () => repositories.restTimers.getCurrentForWorkout(
          workoutExercise.workoutId,
        ),
      );
      expect(timer, isNull);

      await tester.enterText(
        find.byKey(TrainingScreen.restTimerDurationFieldKey),
        '45',
      );
      await tester.tap(find.byKey(TrainingScreen.restTimerStartButtonKey));
      await _settleRepositoryWork(tester);

      timer = await tester.runAsync<RestTimerRecord?>(
        () => repositories.restTimers.getCurrentForWorkout(
          workoutExercise.workoutId,
        ),
      );
      expect(timer?.duration, const Duration(seconds: 45));
      expect(timer?.sourceSetId, isNull);
    });

    testWidgets('keeps in-app rest timer running when alerts are denied', (
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

      await tester.enterText(
        find.byKey(TrainingScreen.restTimerDurationFieldKey),
        '45',
      );
      await tester.tap(find.byKey(TrainingScreen.restTimerStartButtonKey));
      await _settleRepositoryWork(tester);

      final timer = await tester.runAsync<RestTimerRecord?>(
        () => repositories.restTimers.getCurrentForWorkout(
          workoutExercise.workoutId,
        ),
      );
      expect(timer?.duration, const Duration(seconds: 45));
      expect(timer, isNotNull);
      expect(scheduler.schedules.map((schedule) => schedule.timerId),
          <String>[timer!.id]);
      expect(
        find.textContaining('Background timer alerts are off'),
        findsOneWidget,
      );
    });

    testWidgets('starts planned rest when a planned set is marked complete', (
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
      final workoutExercise = (await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId!),
      ))!;
      final plannedSetId = await tester.runAsync(
        () => repositories.sets.create(
          LoggedSetDraft(
            workoutId: workoutExercise.workoutId,
            exerciseId: workoutExercise.exerciseId,
            position: 0,
            values: _loadRepsValues(load: '100', reps: '5'),
            plannedRestAfter: const Duration(seconds: 180),
          ),
        ),
      );
      final setStream = StreamController<List<LoggedSetRecord>>();
      addTearDown(setStream.close);

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId!,
        setsStream: setStream.stream,
      );
      await _emitSets(
        tester,
        repositories,
        workoutExercise.workoutId,
        setStream,
      );

      await tester.tap(
        find.byKey(TrainingScreen.completeSetCheckboxKey(plannedSetId!)),
      );
      await _settleRepositoryWork(tester);

      final timer = await tester.runAsync<RestTimerRecord?>(
        () => repositories.restTimers.getCurrentForWorkout(
          workoutExercise.workoutId,
        ),
      );
      expect(timer?.sourceSetId, plannedSetId);
      expect(timer?.duration, const Duration(seconds: 180));
    });

    testWidgets('fires foreground alert for an expired persisted timer', (
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

    testWidgets(
        'rest timer panel and its ticker survive a save-triggered auto-advance',
        (tester) async {
      // Regression for: swapping `_stateFuture` on auto-select-next-set
      // used to drop the Training Screen body to `SizedBox.expand()` for a
      // frame, unmounting `_RestTimerPanel` and cancelling its `Timer.periodic`.
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
        find.byKey(TrainingScreen.restTimerPanelKey),
      );

      // Capture the panel's State identity BEFORE the advance. If the panel is
      // unmounted and remounted, this State (and its ticker) is replaced. The
      // panel key sits on a StatelessWidget child, so walk up to the enclosing
      // stateful panel element.
      final panelStateBefore = _restTimerPanelState(tester);

      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.load)),
        '100',
      );
      await tester.enterText(
        find.byKey(TrainingScreen.dimensionFieldKey(DimensionId.reps)),
        '5',
      );
      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
      await _settleRepositoryWork(tester);
      // Auto-advance lands on the grouped exercise.
      await _waitForFinder(tester, find.text('Barbell Row'));

      // The panel is still on screen and it is the SAME State object: the
      // ticker was never torn down.
      expect(find.byKey(TrainingScreen.restTimerPanelKey), findsOneWidget);
      final panelStateAfter = _restTimerPanelState(tester);
      expect(
        identical(panelStateBefore, panelStateAfter),
        isTrue,
        reason: 'The rest-timer panel State (and its ticker) must survive the '
            'save-triggered auto-advance to the next grouped exercise.',
      );

      await _disposeWidgetTree(tester);
    });

    testWidgets(
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

    testWidgets('suppresses the prepare cue when timer sounds are turned off',
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

    testWidgets('saves comments RPE and alternating unilateral sides', (
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
      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
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
      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
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

    testWidgets('navigation drawer lists set counts and jumps exercises', (
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
      expect(find.text('2 sets'), findsOneWidget);
      expect(find.text('0 sets'), findsOneWidget);

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

    testWidgets('opens exercise overview from the navigation drawer', (
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

    testWidgets('creates groups and auto-advances only grouped exercises', (
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
      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
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
      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
      await _settleRepositoryWork(tester);

      await _waitForFinder(tester, find.text('Curl'));
      await _disposeWidgetTree(tester);
    });

    testWidgets('prefills from the latest prior set and saves a new set', (
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
      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
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

    testWidgets(
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

        await _pumpTrainingScreen(
          tester,
          repositories,
          workoutExerciseId!,
          setsStream: setStream.stream,
          recordSetIdsStream: recordSetIdsStream.stream,
        );
        await _emitSets(tester, repositories, currentWorkoutId!, setStream);
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
        await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
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
        await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
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

    testWidgets('hides record trophies when PR tracking is disabled', (
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

    testWidgets(
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
        final checkboxSetId = (await tester.runAsync(
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

        await _pumpTrainingScreen(
          tester,
          repositories,
          workoutExerciseId,
          setsStream: setStream.stream,
          useProductionRecordProvider: true,
        );
        await _emitSets(tester, repositories, currentWorkoutId, setStream);
        await tester.tap(
          find.byKey(TrainingScreen.completeSetCheckboxKey(checkboxSetId)),
        );
        await _settleRepositoryWork(tester);
        await _emitSets(tester, repositories, currentWorkoutId, setStream);
        await _pumpFrames(tester);

        expect(
          find.byKey(TrainingScreen.recordTrophyKey(checkboxSetId)),
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
        await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
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
        await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
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
          find.byKey(TrainingScreen.recordTrophyKey(checkboxSetId)),
          findsNothing,
        );

        await _disposeWidgetTree(tester);
      },
    );

    testWidgets('does not show a trophy for completion-only records', (
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

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId!,
        setsStream: setStream.stream,
        recordSetIdsStream: recordSetIdsStream.stream,
      );
      await tester.tap(find.byKey(TrainingScreen.saveSetButtonKey));
      await _settleRepositoryWork(tester);
      await _emitSets(
          tester, repositories, workoutExercise!.workoutId, setStream);
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

    testWidgets('edits deletes completes and exposes reorder handles', (
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
      final firstSetId = (await tester.runAsync(
        () => _createBenchSet(
          repositories,
          workoutId: workoutExercise!.workoutId,
          exerciseId: workoutExercise.exerciseId,
          position: 0,
          load: '80',
          reps: '5',
        ),
      ))!;
      final secondSetId = (await tester.runAsync(
        () => _createBenchSet(
          repositories,
          workoutId: workoutExercise!.workoutId,
          exerciseId: workoutExercise.exerciseId,
          position: 1,
          load: '82.5',
          reps: '4',
        ),
      ))!;
      final setStream = StreamController<List<LoggedSetRecord>>();
      addTearDown(setStream.close);

      await _pumpTrainingScreen(
        tester,
        repositories,
        workoutExerciseId!,
        setsStream: setStream.stream,
      );
      await _emitSets(
          tester, repositories, workoutExercise!.workoutId, setStream);

      expect(find.byKey(TrainingScreen.setTileKey(firstSetId)), findsOneWidget);
      expect(find.text('80 kg x 5'), findsOneWidget);
      expect(find.text('82.5 kg x 4'), findsOneWidget);
      expect(
        find.byKey(TrainingScreen.reorderHandleKey(firstSetId)),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(TrainingScreen.completeSetCheckboxKey(firstSetId)),
      );
      await _settleRepositoryWork(tester);
      await _emitSets(
          tester, repositories, workoutExercise.workoutId, setStream);

      final completedSet = await tester.runAsync(
        () => repositories.sets.getById(firstSetId),
      );
      expect(completedSet?.isCompleted, true);

      await tester.tap(find.byKey(TrainingScreen.editSetButtonKey(firstSetId)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(
          TrainingScreen.editDimensionFieldKey(
            firstSetId,
            DimensionId.load,
          ),
        ),
        '85',
      );
      await tester.enterText(
        find.byKey(
          TrainingScreen.editDimensionFieldKey(
            firstSetId,
            DimensionId.reps,
          ),
        ),
        '3',
      );
      await tester
          .tap(find.byKey(TrainingScreen.saveEditButtonKey(firstSetId)));
      await _settleRepositoryWork(tester);
      await _emitSets(
          tester, repositories, workoutExercise.workoutId, setStream);

      final editedSet = await tester.runAsync(
        () => repositories.sets.getById(firstSetId),
      );
      expect(editedSet?.values.load?.entered, '85');
      expect(editedSet?.values.reps?.entered, '3');
      expect(find.text('85 kg x 3'), findsOneWidget);

      await tester.tap(
        find.byKey(TrainingScreen.deleteSetButtonKey(secondSetId)),
      );
      await _settleRepositoryWork(tester);
      await _emitSets(
          tester, repositories, workoutExercise.workoutId, setStream);

      final activeSets = await tester.runAsync(
        () => repositories.sets.listActiveForWorkout(workoutExercise.workoutId),
      );
      final logs = await tester.runAsync(
        repositories.activityLog.listEntries,
      );

      expect(activeSets!.map((set) => set.id), <String>[firstSetId]);
      expect(find.byKey(TrainingScreen.setTileKey(secondSetId)), findsNothing);
      expect(
        logs!
            .where(
              (entry) =>
                  entry.entityTable == AppDatabase.loggedSetsTable &&
                  entry.entityId == firstSetId &&
                  entry.beforeImage?['is_completed'] == false &&
                  entry.afterImage?['is_completed'] == true,
            )
            .length,
        1,
      );
      expect(
        logs
            .where(
              (entry) =>
                  entry.entityTable == AppDatabase.loggedSetsTable &&
                  entry.entityId == secondSetId &&
                  entry.beforeImage?['deleted_at'] == null &&
                  entry.afterImage?['deleted_at'] != null,
            )
            .length,
        1,
      );
    });

    testWidgets(
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

          await _pumpTrainingScreen(
            tester,
            repositories,
            benchWorkoutExerciseId,
            setsStream: Stream<List<LoggedSetRecord>>.value(
              <LoggedSetRecord>[loggedSet!],
            ),
            theme: theme,
            textScaler: TextScaler.linear(1.8),
          );
          await _waitForFinder(
            tester,
            find.byKey(TrainingScreen.completeSetCheckboxKey(setId)),
          );

          expect(find.semantics.byLabel('Decrease Load'), findsOne);
          expect(find.semantics.byLabel('Increase Load'), findsOne);
          expect(
            find.semantics.byLabel(RegExp(r'Mark set complete')),
            findsOne,
          );
          expect(find.semantics.byLabel('Reorder set'), findsOne);
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
            find.byKey(TrainingScreen.completeSetCheckboxKey(setId)),
          );
          _expectMinimumTargetSize(
            tester,
            find.byKey(TrainingScreen.reorderHandleKey(setId)),
          );
          _expectMinimumTargetSize(
            tester,
            find.byKey(TrainingScreen.saveSetButtonKey),
          );

          await tester.tap(find.byKey(TrainingScreen.navigationPanelButtonKey));
          await _pumpDrawerAnimation(tester);

          expect(find.textContaining(groupName), findsNWidgets(2));
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
}) async {
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
          setsStream: setsStream ??
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
  await _waitForFinder(tester, find.text('Save set'));
}

/// Resolves the `State` of the rest-timer panel. Its key sits on a
/// `StatelessWidget` child, so walk up to the enclosing stateful panel element
/// (the private `_RestTimerPanelState`, which owns the ticker).
State _restTimerPanelState(WidgetTester tester) {
  final element = tester.element(
    find.byKey(TrainingScreen.restTimerPanelKey),
  );
  State? found;
  element.visitAncestorElements((ancestor) {
    if (ancestor is StatefulElement) {
      found = ancestor.state;
      return false;
    }
    return true;
  });
  if (found == null) {
    fail('No stateful ancestor found for the rest-timer panel.');
  }
  return found!;
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
