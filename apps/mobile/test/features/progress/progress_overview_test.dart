import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/analytics/progress_measure.dart';
import 'package:perennia/domain/training/focus_color.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/domain/training/training_progress.dart';
import 'package:perennia/features/home/controllers/home_controller.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';
import 'package:perennia/features/home/widgets/home_screen.dart';
import 'package:perennia/features/progress/controllers/progress_controller.dart';
import 'package:perennia/features/analytics/widgets/exercise_overview_screen.dart';
import 'package:perennia/features/progress/widgets/focus_time_card.dart';
import 'package:perennia/features/progress/widgets/key_exercises_card.dart';
import 'package:perennia/features/progress/widgets/new_bests_card.dart';
import 'package:perennia/features/progress/widgets/progress_sparkline.dart';
import 'package:perennia/features/progress/widgets/progress_overview.dart';
import 'package:perennia/features/progress/widgets/protocols_progress_card.dart';
import 'package:perennia/features/progress/widgets/this_week_card.dart';
import 'package:perennia/features/progress/widgets/trained_days_card.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/biometric_authenticator.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';
import 'package:perennia/features/protocols/widgets/consistency_screen.dart';
import 'package:perennia/features/protocols/widgets/protocols_lock_screen.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/template_picker/repositories/template_picker_feature_repository.dart';
import 'package:perennia/features/up_next/repositories/up_next_feature_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

// The CUJs' week runs from Monday 26 October to Sunday 1 November 2026, with
// one weekly Routine "Hybrid block": Monday Lower, Tuesday Run intervals,
// Thursday Upper, Saturday Long run.
const _monday = TrainingDayDate(year: 2026, month: 10, day: 26);

DateTime _at(int dayOffset, int hour, [int minute = 0]) {
  final date = _monday.addDays(dayOffset);
  return DateTime(date.year, date.month, date.day, hour, minute);
}

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

  late AppDatabase database;
  late TrainingRepositories repositories;
  late _LockStore lockStore;
  late String exerciseId;

  // Database work runs here, or under tester.runAsync, outside the widget
  // test's fake clock.
  setUp(() async {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(
      database,
      platformSeedSource: const _StarterFocusSeedSource(),
    );
    await repositories.catalog.ensurePlatformLibrarySeeded();
    exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Push-up',
        type: ExerciseType(const <DimensionId>[DimensionId.reps]),
      ),
    );
    lockStore = _LockStore();
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> completeSet(String workoutId) async {
    await repositories.sets.create(
      LoggedSetDraft(
        workoutId: workoutId,
        exerciseId: exerciseId,
        position: 0,
        isCompleted: true,
        values: LoggedSet.fromValues(<SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '10',
            unit: TrainingUnit.repetition,
          ),
        ]),
      ),
    );
  }

  Future<String> template(String name) {
    return repositories.workoutTemplates
        .create(WorkoutTemplateDraft(name: name));
  }

  /// A weekly Routine planning each template on its ISO weekday.
  Future<String> weeklyRoutine(String name, Map<String, int> weekdays) async {
    final routineId = await repositories.routinePlans.create(
      RoutinePlanDraft(name: name),
    );
    await repositories.routinePlans.setCadence(
      routineId,
      const Cadence.weekly(),
    );
    for (final MapEntry(key: templateId, value: weekday) in weekdays.entries) {
      await repositories.routinePlans.addTemplateReference(
        routineId,
        templateId,
        slot: weekday,
      );
    }
    return routineId;
  }

  /// A Workout started from [templateId] at [startedAt], as the start sheet
  /// or Up next (with [routineId] and [slot]) starts one. Unless [performed]
  /// is false, one Set is completed and the Workout ends after [length].
  Future<String> startFrom(
    String templateId,
    DateTime startedAt, {
    String? routineId,
    int? slot,
    bool performed = true,
    Duration length = const Duration(hours: 1),
  }) async {
    final result = await repositories.templateMaterialize.materialize(
      TemplateMaterializeRequest(
        workoutTemplateId: templateId,
        routineId: routineId,
        slot: slot,
      ),
      now: startedAt,
    );
    if (performed) {
      await completeSet(result.workoutId);
      await repositories.workoutSessions.updateEndedAt(
        result.workoutId,
        endedAt: startedAt.add(length),
      );
    }
    return result.workoutId;
  }

  /// A Workout with no template, one completed Set and the given length.
  Future<String> workout(
    DateTime startedAt, {
    Duration length = const Duration(hours: 1),
    String? focusId,
  }) async {
    final workoutId = await repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: startedAt,
        timezone: startedAt.timeZoneName,
        localDate: TrainingDayDate.fromDateTime(startedAt),
        endedAt: startedAt.add(length),
        focusId: focusId,
      ),
    );
    await completeSet(workoutId);
    return workoutId;
  }

  /// The Hybrid block Routine and its four templates.
  Future<({String routine, String lower, String run, String upper})>
      hybridBlock() async {
    final lower = await template('Lower');
    final run = await template('Run intervals');
    final upper = await template('Upper');
    final longRun = await template('Long run');
    final routine = await weeklyRoutine('Hybrid block', {
      lower: DateTime.monday,
      run: DateTime.tuesday,
      upper: DateTime.thursday,
      longRun: DateTime.saturday,
    });
    return (routine: routine, lower: lower, run: run, upper: upper);
  }

  List<Override> overrides(DateTime now) => <Override>[
        // Key exercises and New bests read the database through the
        // exercise analytics repository.
        appDatabaseProvider.overrideWith((ref) => database),
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        settingsRepositoryProvider.overrideWith(
          (ref) => InMemorySettingsRepository(),
        ),
        progressClockProvider.overrideWith((ref) => () => now),
        protocolsLockStoreProvider.overrideWith((ref) => lockStore),
        biometricAuthenticatorProvider.overrideWith((ref) => _NoBiometrics()),
        protocolsLockControllerProvider.overrideWith(
          () => ProtocolsLockController(
            hasher: const ProtocolsPinHasher(iterations: 10),
          ),
        ),
      ];

  /// Progress Overview on a surface tall enough to build every card.
  Future<void> pumpOverview(WidgetTester tester, DateTime now) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(now),
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ProgressOverview()),
        ),
      ),
    );
    await _settle(tester);
  }

  IconData? dayIcon(WidgetTester tester, int dayOffset) {
    final icons = find.descendant(
      of: find.byKey(ThisWeekCard.dayKey(_monday.addDays(dayOffset))),
      matching: find.byType(Icon),
    );
    return icons.evaluate().isEmpty ? null : tester.widget<Icon>(icons).icon;
  }

  String text(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data!;

  int cells(String kind) => find
      .byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('progress.trainedDays.$kind.'),
      )
      .evaluate()
      .length;

  testWidgets(
      'CUJ 1: the week reads Done, Trained, Not done and Done '
      'differently against the plan', (tester) async {
    await tester.runAsync(() async {
      final plan = await hybridBlock();
      final easySpin = await template('Easy spin');
      await startFrom(
        plan.lower,
        _at(0, 7),
        routineId: plan.routine,
        slot: DateTime.monday,
      );
      await startFrom(plan.run, _at(1, 7));
      await workout(_at(2, 7));
      await startFrom(easySpin, _at(5, 9));
    });

    await pumpOverview(tester, _at(6, 18));

    expect(dayIcon(tester, 0), Icons.check_circle);
    expect(dayIcon(tester, 1), Icons.check_circle);
    expect(dayIcon(tester, 2), Icons.add_circle_outline);
    expect(dayIcon(tester, 3), Icons.radio_button_unchecked);
    expect(dayIcon(tester, 4), isNull);
    expect(dayIcon(tester, 5), Icons.swap_horiz);
    expect(dayIcon(tester, 6), isNull);
    expect(
      text(tester, ThisWeekCard.summaryKey),
      '2 done · 1 done differently · 1 not done · 1 trained',
    );
    expect(text(tester, ThisWeekCard.comparedKey), 'Comparing Hybrid block');
    await _unmount(tester);
  });

  testWidgets(
      'CUJ 2: today is Pending until its planned workout has a '
      'completed Set', (tester) async {
    late ({String routine, String lower, String run, String upper}) plan;
    await tester.runAsync(() async {
      plan = await hybridBlock();
      await workout(_at(3, 6), length: const Duration(minutes: 40));
    });

    await pumpOverview(tester, _at(3, 9));

    expect(dayIcon(tester, 3), Icons.schedule);
    expect(dayIcon(tester, 5), Icons.event);
    // Monday and Tuesday passed without their workouts; today is not counted.
    expect(text(tester, ThisWeekCard.summaryKey), '2 not done');

    // One write per real-async step while the screen listens: each write
    // wakes the screen's queries, which run on the next settle.
    late String upperWorkout;
    await _write(tester, () async {
      upperWorkout = await startFrom(plan.upper, _at(3, 8), performed: false);
    });
    expect(dayIcon(tester, 3), Icons.schedule);
    await _write(tester, () => completeSet(upperWorkout));

    expect(dayIcon(tester, 3), Icons.check_circle);
    expect(text(tester, ThisWeekCard.summaryKey), '1 done · 2 not done');
    await _unmount(tester);
  });

  testWidgets(
      'CUJ 3: with only a rotating Routine, days are Trained or No '
      'plan', (tester) async {
    await tester.runAsync(() async {
      final lower = await template('Lower');
      final upper = await template('Upper');
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Four-day rotation'),
      );
      await repositories.routinePlans.addTemplateReference(routineId, lower);
      await repositories.routinePlans.addTemplateReference(routineId, upper);
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.rotating(4),
      );
      await startFrom(lower, _at(0, 7));
      await startFrom(upper, _at(2, 7));
    });

    await pumpOverview(tester, _at(6, 18));

    for (var offset = 0; offset < 7; offset += 1) {
      expect(
        dayIcon(tester, offset),
        offset == 0 || offset == 2 ? Icons.add_circle_outline : isNull,
        reason: '$offset',
      );
    }
    expect(text(tester, ThisWeekCard.comparedKey), 'Weekly Routines only.');
    expect(
      find.byKey(ThisWeekCard.legendKey(TrainingDayStatus.noPlan)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    expect(text(tester, ThisWeekCard.summaryKey), '2 trained');
    await _unmount(tester);
  });

  testWidgets(
      'CUJ 4: a planned session started after midnight belongs to '
      'the next date', (tester) async {
    await tester.runAsync(() async {
      final plan = await hybridBlock();
      await startFrom(plan.lower, _at(1, 0, 30));
    });

    await pumpOverview(tester, _at(2, 12));

    expect(dayIcon(tester, 0), Icons.radio_button_unchecked);
    expect(dayIcon(tester, 1), Icons.swap_horiz);
    await _unmount(tester);
  });

  testWidgets(
      'CUJ 5: an abandoned planned workout is Not done, not a '
      'Trained Day and no time', (tester) async {
    await tester.runAsync(() async {
      final plan = await hybridBlock();
      await startFrom(
        plan.run,
        _at(1, 7),
        routineId: plan.routine,
        slot: DateTime.tuesday,
        performed: false,
      );
    });

    await pumpOverview(tester, _at(2, 12));

    expect(dayIcon(tester, 1), Icons.radio_button_unchecked);
    expect(find.text('Logged workouts show here'), findsOneWidget);
    expect(find.text('Finished workouts show here'), findsOneWidget);
    await _unmount(tester);
  });

  Future<void> trainEveryOtherDayFor12Weeks() async {
    // 12 weeks back from Monday 26 October starts on Monday 10 August. A
    // Workout every other day from then through Thursday 29 October trains
    // on 41 of those 84 dates.
    final firstDay = _monday.addDays(-77);
    for (var offset = 0; offset <= 80; offset += 2) {
      final date = firstDay.addDays(offset);
      await workout(DateTime(date.year, date.month, date.day, 7));
    }
  }

  testWidgets('CUJ 6: 41 trained days over 12 weeks fill 41 cells', (
    tester,
  ) async {
    await tester.runAsync(trainEveryOtherDayFor12Weeks);

    await pumpOverview(tester, _at(6, 18));

    expect(text(tester, TrainedDaysCard.countKey), '41 trained days');
    expect(cells('trained'), 41);
    expect(cells('untrained'), 84 - 41);
    expect(cells('future'), 0);
    await _unmount(tester);
  });

  testWidgets(
      'switching the period recounts the Trained Days and keeps '
      'This week', (tester) async {
    await tester.runAsync(trainEveryOtherDayFor12Weeks);

    // Thursday: the rest of the week is still ahead.
    await pumpOverview(tester, _at(3, 18));
    expect(cells('future'), 3);

    await tester
        .tap(find.byKey(ProgressOverview.periodKey(ProgressPeriod.weeks4)));
    // The period does not set This week, so it stays loaded through the
    // switch rather than falling back to its loading body.
    await tester.pump();
    expect(find.byKey(ThisWeekCard.daysKey), findsOneWidget);
    await _settle(tester);
    // 28 dates from Monday 5 October; even offsets from 10 August land on
    // 5, 7, ..., 29 October.
    expect(text(tester, TrainedDaysCard.countKey), '13 trained days');
    expect(cells('trained') + cells('untrained') + cells('future'), 28);
    expect(find.byKey(ThisWeekCard.daysKey), findsOneWidget);

    await tester
        .tap(find.byKey(ProgressOverview.periodKey(ProgressPeriod.year)));
    await tester.pump();
    expect(find.byKey(ThisWeekCard.daysKey), findsOneWidget);
    await _settle(tester);
    expect(text(tester, TrainedDaysCard.countKey), '41 trained days');
    expect(cells('trained') + cells('untrained') + cells('future'), 364);
    await _unmount(tester);
  });

  testWidgets('CUJ 7: time by Focus stacks this week per Focus on one scale',
      (tester) async {
    await tester.runAsync(() async {
      await workout(
        _at(0, 7),
        length: const Duration(minutes: 100),
        focusId: starterFocusWeightsId,
      );
      await workout(
        _at(3, 7),
        length: const Duration(minutes: 60),
        focusId: starterFocusWeightsId,
      );
      await workout(
        _at(1, 7),
        length: const Duration(minutes: 190),
        focusId: starterFocusEnduranceId,
      );
      await workout(
        _at(2, 7),
        length: const Duration(minutes: 35),
        focusId: starterFocusMobilityId,
      );
      await workout(_at(4, 7), length: const Duration(minutes: 20));
      // An earlier week, so bars share the scale.
      await workout(
        _at(-7, 7),
        length: const Duration(minutes: 90),
        focusId: starterFocusEnduranceId,
      );
    });

    await pumpOverview(tester, _at(6, 18));

    String legend(String key) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(FocusTimeCard.legendKey(key)),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(legend(starterFocusWeightsId), 'Weights 2h 40m');
    expect(legend(starterFocusEnduranceId), 'Endurance 3h 10m');
    expect(legend(starterFocusMobilityId), 'Mobility 35m');
    expect(legend(noFocusKey), 'No Focus 20m');
    // Legend order: Focus sort order, then No Focus.
    final xs = <String>[
      starterFocusWeightsId,
      starterFocusEnduranceId,
      starterFocusMobilityId,
      noFocusKey,
    ].map((key) => tester.getTopLeft(find.byKey(FocusTimeCard.legendKey(key))));
    expect(
      xs.toList(),
      orderedEquals(xs.toList()
        ..sort((a, b) {
          final byRow = a.dy.compareTo(b.dy);
          return byRow != 0 ? byRow : a.dx.compareTo(b.dx);
        })),
    );

    final chart = tester.widget<BarChart>(find.byType(BarChart)).data;
    expect(chart.barGroups, hasLength(12));
    // 6 h 45 min tallest: a 2-hour step, ending at 8 hours.
    expect(chart.maxY, 8);
    final thisWeek = chart.barGroups.last.barRods.single;
    expect(thisWeek.rodStackItems, hasLength(4));
    expect(thisWeek.toY, closeTo(405 / 60, 1e-9));
    expect(
      tester.getSemantics(find.byKey(FocusTimeCard.chartKey)),
      matchesSemantics(
        label: 'Time by Focus, this week: Weights 2 hours 40 minutes, '
            'Endurance 3 hours 10 minutes, Mobility 35 minutes, '
            'No Focus 20 minutes',
      ),
    );
    await _unmount(tester);
  });

  testWidgets('CUJ 8: a recolored Focus is drawn in its new color', (
    tester,
  ) async {
    late String climbingId;
    await tester.runAsync(() async {
      climbingId = await repositories.focuses.create('Climbing');
      await workout(_at(2, 7), focusId: climbingId);
    });

    await pumpOverview(tester, _at(6, 18));

    Color dotColor() {
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(FocusTimeCard.legendKey(climbingId)),
          matching: find.byType(DecoratedBox),
        ),
      );
      return (box.decoration as BoxDecoration).color!;
    }

    Color segmentColor() => tester
        .widget<BarChart>(find.byType(BarChart))
        .data
        .barGroups
        .last
        .barRods
        .single
        .rodStackItems
        .single
        .color;

    final defaultColor =
        DesignTokens.category[focusDefaultColorToken(climbingId)]!;
    expect(dotColor(), defaultColor);
    expect(segmentColor(), defaultColor);

    final pick =
        focusDefaultColorToken(climbingId) == 'legs' ? 'chest' : 'legs';
    final picked = DesignTokens.category[pick]!;
    await _write(
      tester,
      () => repositories.focuses.recolor(
        climbingId,
        colorHex: colorToHex(picked),
      ),
    );
    expect(dotColor(), picked);
    expect(segmentColor(), picked);

    // Reordering never recolors.
    final order = await tester.runAsync(repositories.focuses.listActive);
    await _write(
      tester,
      () => repositories.focuses.reorder(
        order!.map((focus) => focus.id).toList().reversed.toList(),
      ),
    );

    expect(dotColor(), picked);
    expect(segmentColor(), picked);
    await _unmount(tester);
  });

  /// A Favorite "5 km run" with Record Profile fastest pace.
  Future<String> fiveKmRun() async {
    final id = await repositories.exercises.create(
      ExerciseDraft(
        name: '5 km run',
        type: ExerciseType(const <DimensionId>[
          DimensionId.distance,
          DimensionId.duration,
        ]),
        recordProfile: RecordProfile.fastestPace,
      ),
    );
    await repositories.exercises.setFavorite(id, isFavorite: true);
    return id;
  }

  /// A Workout at [startedAt] with one 5 km Set of [seconds] on [runId].
  Future<String> run(
    String runId,
    DateTime startedAt,
    int seconds, {
    bool isCompleted = true,
  }) async {
    final workoutId = await repositories.workoutSessions.create(
      WorkoutSessionDraft(
        startedAt: startedAt,
        timezone: startedAt.timeZoneName,
        localDate: TrainingDayDate.fromDateTime(startedAt),
        endedAt: startedAt.add(Duration(seconds: seconds)),
      ),
    );
    await repositories.sets.create(
      LoggedSetDraft(
        workoutId: workoutId,
        exerciseId: runId,
        position: 0,
        isCompleted: isCompleted,
        values: LoggedSet.fromValues(<SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.distance,
            entered: '5',
            unit: TrainingUnit.kilometer,
          ),
          SetDimensionValue(
            dimension: DimensionId.duration,
            entered: '$seconds',
            unit: TrainingUnit.second,
          ),
        ]),
      ),
    );
    return workoutId;
  }

  testWidgets(
      'CUJ 9: a new best on a run shows on its tile and tops New '
      'bests', (tester) async {
    late String runId;
    late String saturday;
    await tester.runAsync(() async {
      runId = await fiveKmRun();
      // Before the 12-week period from 10 August: 5:22 and 5:30 per km.
      await run(runId, DateTime(2026, 7, 20, 7), 1610);
      await run(runId, DateTime(2026, 8, 3, 7), 1650);
      // In the period: 5:40, then 5:04 on Saturday.
      await run(runId, DateTime(2026, 10, 17, 7), 1700);
      saturday = await run(runId, _at(5, 7), 1520);
    });

    await pumpOverview(tester, _at(6, 18));

    expect(
      text(tester, KeyExercisesCard.bestKey(runId)),
      'Best 5:04 /km',
    );
    expect(
      text(tester, KeyExercisesCard.comparisonKey(runId)),
      '18 s faster than before',
    );
    final sparkline = tester.widget<ProgressSparkline>(
      find.descendant(
        of: find.byKey(KeyExercisesCard.tileKey(runId)),
        matching: find.byType(ProgressSparkline),
      ),
    );
    expect(sparkline.points.map((point) => point.y), <double>[340, 304]);
    expect(sparkline.markedIndexes, <int>{1});

    final rows = find.descendant(
      of: find.ancestor(
        of: find.text('New bests · 1'),
        matching: find.byType(Material),
      ),
      matching: find.byType(InkWell),
    );
    final top = rows.first;
    final best = NewBest(
      exerciseId: runId,
      measure: ProgressMeasureKind.fastestPace,
      workoutId: saturday,
      localDate: _monday.addDays(5),
      startedAt: _at(5, 7),
      setId: '',
      value: 304,
      unit: TrainingUnit.second,
    );
    expect(tester.widget(top).key, NewBestsCard.rowKey(best));
    expect(
      find.descendant(of: top, matching: find.text('5 km run · 5:04 /km')),
      findsOneWidget,
    );
    expect(find.descendant(of: top, matching: find.text('Sat')), findsOneWidget);
    expect(
      find.descendant(
        of: top,
        matching: find.byIcon(Icons.emoji_events_outlined),
      ),
      findsOneWidget,
    );

    // The row opens the exercise.
    await tester.tap(top);
    await _settle(tester);
    expect(
      tester
          .widget<ExerciseOverviewScreen>(find.byType(ExerciseOverviewScreen))
          .exerciseId,
      runId,
    );
    await _unmount(tester);
  });

  testWidgets(
      'CUJ 10: with no Favorites, Key exercises asks for one, with no '
      'action', (tester) async {
    await tester.runAsync(() async {
      // History, but nothing marked as a Favorite.
      await workout(_at(0, 7));
    });

    await pumpOverview(tester, _at(6, 18));

    expect(
      find.text('Mark exercises as favorites to chart them here'),
      findsOneWidget,
    );
    final card = find
        .ancestor(
          of: find.text('Key exercises'),
          matching: find.byType(Material),
        )
        .first;
    expect(
      find.descendant(of: card, matching: find.byType(TextButton)),
      findsNothing,
    );
    await _unmount(tester);
  });

  testWidgets(
      'an abandoned planned workout adds no New Best, however far its '
      'unfinished Set would go', (tester) async {
    await tester.runAsync(() async {
      final runId = await fiveKmRun();
      final plan = await hybridBlock();
      await run(runId, _at(-14, 7), 1650);
      // Started from Up next and abandoned: its Set was never completed.
      final abandoned = await startFrom(
        plan.run,
        _at(1, 7),
        routineId: plan.routine,
        slot: DateTime.tuesday,
        performed: false,
      );
      await repositories.sets.create(
        LoggedSetDraft(
          workoutId: abandoned,
          exerciseId: runId,
          position: 0,
          isCompleted: false,
          values: LoggedSet.fromValues(<SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.distance,
              entered: '5',
              unit: TrainingUnit.kilometer,
            ),
            SetDimensionValue(
              dimension: DimensionId.duration,
              entered: '1400',
              unit: TrainingUnit.second,
            ),
          ]),
        ),
      );
    });

    await pumpOverview(tester, _at(2, 12));

    expect(find.text('No new bests in this period'), findsOneWidget);
    expect(find.textContaining('New bests ·'), findsNothing);
    await _unmount(tester);
  });

  testWidgets(
      'CUJ 12: locked Protocols show only the lock; unlocking lists '
      'each Compound, which opens its Consistency view', (tester) async {
    late List<CompoundConsistencySummary> expected;
    await tester.runAsync(() async {
      lockStore
        ..enabled = true
        ..pinHash = await const ProtocolsPinHasher(iterations: 10).hash('1234');
      final created = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Creatine',
          defaultUnit: DoseUnit.gram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      final start = ProtocolDayDate(year: 2026, month: 10, day: 1);
      await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Daily creatine',
          startLocalDate: start,
          compoundIds: <String>[created.compoundId],
          schedulesByCompoundId: <String, ScheduleDraft?>{
            created.compoundId: ScheduleDraft(
              rule: TimedScheduleRule(
                days: const DailyScheduleDays(),
                times: const <String>['08:00'],
              ),
              doseAmountValue: 5,
              doseAmountEntered: '5',
              doseUnit: DoseUnit.gram,
              route: DoseRoute.oral,
            ),
          },
        ),
        today: start,
      );
      for (var day = 1; day <= 31; day += 1) {
        if (day == 6 || day == 20) {
          continue;
        }
        await repositories.protocols.logDose(
          DoseSnapshotDraft(
            compoundId: created.compoundId,
            compoundName: 'Creatine',
            amountValue: 5,
            amountEntered: '5',
            unit: DoseUnit.gram,
            route: DoseRoute.oral,
            tookAt: DateTime(2026, 10, day, 8, 5),
          ),
        );
      }
      expected = await repositories.protocolPlan
          .watchConsistencySummary(
            const ProtocolDayDate(year: 2026, month: 8, day: 10),
            const ProtocolDayDate(year: 2026, month: 11, day: 1),
            today: const ProtocolDayDate(year: 2026, month: 11, day: 1),
          )
          .first;
    });

    await pumpOverview(tester, _at(6, 18));

    expect(find.byKey(ProtocolsProgressCard.lockedRowKey), findsOneWidget);
    expect(find.textContaining('Creatine'), findsNothing);

    await tester.tap(find.byKey(ProtocolsProgressCard.unlockButtonKey));
    await _settle(tester);
    await tester.enterText(find.byKey(ProtocolsUnlockForm.pinFieldKey), '1234');
    await tester.tap(find.byKey(ProtocolsUnlockForm.unlockPinButtonKey));
    await _settle(tester);

    final creatine = expected.single;
    expect(creatine.notLogged, greaterThan(0));
    expect(find.text('Creatine'), findsOneWidget);
    expect(
      find.text(
        <String>[
          if (creatine.logged > 0) '${creatine.logged} logged',
          if (creatine.partlyLogged > 0)
            '${creatine.partlyLogged} partly logged',
          if (creatine.notLogged > 0) '${creatine.notLogged} not logged',
          if (creatine.paused > 0) '${creatine.paused} paused',
        ].join(' · '),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ProtocolsProgressCard.rowKey(creatine.compoundId)),
    );
    await _settle(tester);
    expect(find.byType(ConsistencyScreen), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'CUJ 14: a first run shows each empty state with at most one '
      'action, and no Protocols card', (tester) async {
    await pumpOverview(tester, _at(6, 18));

    expect(find.text('Plan your week with a Routine'), findsOneWidget);
    expect(find.text('Logged workouts show here'), findsOneWidget);
    expect(find.text('Finished workouts show here'), findsOneWidget);
    expect(
      find.text('Mark exercises as favorites to chart them here'),
      findsOneWidget,
    );
    expect(find.text('No new bests in this period'), findsOneWidget);
    expect(find.byKey(ProtocolsProgressCard.cardKey), findsNothing);

    int actionsIn(String title) {
      final card = find
          .ancestor(
            of: find.text(title),
            matching: find.byType(Material),
          )
          .first;
      return find
          .descendant(of: card, matching: find.byType(TextButton))
          .evaluate()
          .length;
    }

    expect(actionsIn('This week'), 1);
    expect(actionsIn('Trained days'), 0);
    expect(actionsIn('Time by Focus'), 1);
    expect(actionsIn('Key exercises'), 0);
    expect(actionsIn('New bests'), 0);
    expect(find.byKey(ProgressOverview.bodyTrackerTileKey), findsOneWidget);
    expect(find.byKey(ProgressOverview.healthMetricsTileKey), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('Progress keeps its scroll position across tab switches', (
    tester,
  ) async {
    await tester.runAsync(trainEveryOtherDayFor12Weeks);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...overrides(_at(6, 18)),
          homeRepositoryProvider.overrideWith((ref) => StubHomeRepository()),
          upNextFeatureRepositoryProvider.overrideWith(
            (ref) => const StubUpNextFeatureRepository(),
          ),
          templatePickerFeatureRepositoryProvider.overrideWith(
            (ref) => const StubTemplatePickerFeatureRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(HomeScreen.progressDestinationKey));
    await _settle(tester);
    final list = find.descendant(
      of: find.byKey(ProgressOverview.listKey),
      matching: find.byType(Scrollable),
    );
    await tester.drag(list, const Offset(0, -300));
    await _settle(tester);
    final offset = tester.state<ScrollableState>(list).position.pixels;
    expect(offset, greaterThan(0));

    await tester.tap(find.byKey(HomeScreen.todayDestinationKey));
    await _settle(tester);
    // Off Progress, its cards are not built.
    expect(find.byType(ProgressOverview), findsNothing);
    expect(
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
          .read(selectedHomeDestinationProvider),
      HomeDestination.today,
    );

    await tester.tap(find.byKey(HomeScreen.progressDestinationKey));
    await _settle(tester);
    expect(tester.state<ScrollableState>(list).position.pixels, offset);
    await _unmount(tester);
  });
}

/// Lets the database's real-async work (the seed wait, stream queries,
/// writes) finish, then settles the frames it caused.
Future<void> _settle(WidgetTester tester) async {
  for (var pass = 0; pass < 4; pass += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

/// Runs one database write in real time while the screen listens, then
/// settles the queries it woke. A second write in the same step would wait
/// on a woken query that only runs when the test pumps.
Future<void> _write(WidgetTester tester, Future<void> Function() write) async {
  await tester.runAsync(write);
  await _settle(tester);
}

/// Closes the screen's database streams; drift schedules their cleanup on a
/// zero-length timer that must run before the test ends. A query the unmount
/// cancelled then finishes in real time; until it does, closing the database
/// waits on it.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(milliseconds: 1));
}

class _StarterFocusSeedSource implements PlatformExerciseSeedSource {
  const _StarterFocusSeedSource();

  @override
  Future<PlatformExerciseSeed> load() async {
    SeedFocus focus(String id, String name, int sortOrder) => SeedFocus(
          id: id,
          name: name,
          sortOrder: sortOrder,
          updatedAt: DateTime.utc(2026, 10, 1),
        );
    return PlatformExerciseSeed(
      categories: const <SeedExerciseCategory>[],
      focuses: <SeedFocus>[
        focus(starterFocusWeightsId, 'Weights', 0),
        focus(starterFocusEnduranceId, 'Endurance', 1),
        focus(starterFocusMobilityId, 'Mobility', 2),
      ],
      exercises: const <SeedExercise>[],
    );
  }
}

class _LockStore implements ProtocolsLockStore {
  bool enabled = false;
  String? pinHash;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }

  @override
  Future<String?> readPinHash() async => pinHash;

  @override
  Future<void> writePinHash(String hash) async {
    pinHash = hash;
  }

  @override
  Future<void> clearPin() async {
    pinHash = null;
  }
}

class _NoBiometrics implements BiometricAuthenticator {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> authenticate({required String reason}) async => false;
}
