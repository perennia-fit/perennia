import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/local/food_reference_database.dart';
import 'package:perennia/data/open_food_facts/open_food_facts_client.dart';
import 'package:perennia/data/repositories/open_food_facts_repository.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';
import 'package:perennia/domain/protocols/protocol_plan_days.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/domain/training/training_progress.dart';
import 'package:perennia/features/analytics/repositories/exercise_analytics_repository.dart';
import 'package:perennia/features/analytics/repositories/exercise_overview_repository.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';
import 'package:perennia/features/nutrition/repositories/add_food_repository.dart';
import 'package:perennia/features/training/widgets/training_screen.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

import '../data/open_food_facts_fixtures.dart';
import 'performance_budget_fixtures.dart';
import 'performance_budget_thresholds.dart';

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

  group('M5 performance budgets', () {
    test('Open Food Facts device search over 41k products stays under 100 ms',
        () async {
      final database = FoodReferenceDatabase.memory();
      addTearDown(database.close);
      await database.replaceBundle(
        _syntheticOpenFoodFactsLines(openFoodFactsLocalSearchRowCount),
        bundleHeader(
          contentHash: 'synthetic',
          productCount: openFoodFactsLocalSearchRowCount,
        ),
      );

      final stopwatch = Stopwatch()..start();
      final rows = await database.searchProducts(
        buildFoodSearchMatch('greek yo')!,
        50,
      );
      stopwatch.stop();

      expect(rows, hasLength(50));
      expect(
        stopwatch.elapsed,
        lessThan(openFoodFactsLocalSearchBudget),
        reason: 'A two-word prefix search must return within the typing '
            'budget.',
      );
    });

    test(
        'Food History over 20k Food Entries for 1,500 Foods stays under '
        '150 ms', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final now = DateTime.utc(2026, 10, 31, 12);
      await _seedFoodHistory(database, now: now);
      final repositories = TrainingRepositories(database);

      // The fastest of three full reads: the query's own cost, not a stall
      // from another test file running on the host at the same time. A
      // slower query still fails every one of the three.
      Duration? fastest;
      for (var run = 0; run < 3; run += 1) {
        final stopwatch = Stopwatch()..start();
        final history =
            await repositories.nutrition.listFoodHistory(now: now);
        stopwatch.stop();

        expect(history, hasLength(foodHistoryFoodCount));
        expect(history.first.recentCount, greaterThan(0));
        expect(history.every((record) => record.lastPortion != null), isTrue);
        if (fastest == null || stopwatch.elapsed < fastest) {
          fastest = stopwatch.elapsed;
        }
      }
      expect(
        fastest,
        lessThan(foodHistoryBudget),
        reason: 'Food History is read once per picker opening and must not '
            'hold the picker in its loading state.',
      );
    });

    test(
        'a typed All search over 1,500 Your foods and 41k products stays '
        'under 100 ms', () async {
      final referenceDatabase = FoodReferenceDatabase.memory();
      addTearDown(referenceDatabase.close);
      await referenceDatabase.replaceBundle(
        _syntheticOpenFoodFactsLines(openFoodFactsLocalSearchRowCount),
        bundleHeader(
          contentHash: 'synthetic',
          productCount: openFoodFactsLocalSearchRowCount,
        ),
      );
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = RepositoryAddFoodRepository(
        TrainingRepositories(database),
        openFoodFacts: DriftOpenFoodFactsRepository.forTesting(
          database: referenceDatabase,
          asset: const ThrowingBundleAsset(),
          client: OpenFoodFactsClient(
            baseUrl: Uri.parse('https://off.test/'),
            httpClient: MockClient(
              (request) async => fail('A typed search sent ${request.url}.'),
            ),
          ),
        ),
      );
      final yourFoods = YourFoods([
        for (var index = 0; index < foodHistoryFoodCount; index += 1)
          _yourFoodsItem(index),
      ]);
      // The USDA seed is in memory after its first load, as in the app.
      await repository.search(
        filter: AddFoodPickerFilter.usda,
        query: '',
        yourFoods: yourFoods,
      );

      final stopwatch = Stopwatch()..start();
      final items = await repository.search(
        filter: AddFoodPickerFilter.all,
        query: 'greek yo',
        yourFoods: yourFoods,
      );
      stopwatch.stop();

      expect(items, hasLength(searchResultLimit));
      expect(
        items.where((item) => item.origin == FoodPickerOrigin.history),
        hasLength(yourFoodsInSearchLimit),
      );
      expect(
        stopwatch.elapsed,
        lessThan(openFoodFactsLocalSearchBudget),
        reason: 'A typed All search must return within the typing budget.',
      );
    });

    test(
        'Consistency plans and matches 366 days for one Compound in 3 '
        'Protocols under 50 ms', () {
      final fixture = _consistencyFixture();
      final stopwatch = Stopwatch()..start();

      final days = planDays(fixture.protocols, fixture.from, fixture.to);
      final statuses = dayStatuses(days, fixture.doses, fixture.to);
      stopwatch.stop();

      expect(fixture.protocols, hasLength(protocolConsistencyProtocolCount));
      expect(
        fixture.protocols.every(
          (protocol) =>
              protocol.members.single.versions.length ==
              protocolConsistencyVersionsPerProtocol,
        ),
        isTrue,
      );
      expect(fixture.doses, hasLength(protocolConsistencyDoseCount));
      // The whole workload ran: a PlanDay per Protocol and date, a Day Status
      // per date, and every Dose matched into a slot or counted as an extra.
      expect(
        days,
        hasLength(
          protocolConsistencyRangeDays * protocolConsistencyProtocolCount,
        ),
      );
      expect(statuses, hasLength(protocolConsistencyRangeDays));
      expect(
        statuses.fold<int>(
          0,
          (sum, status) => sum + status.loggedCount + status.extraCount,
        ),
        protocolConsistencyDoseCount,
      );
      expect(statuses.any((status) => status.loggedCount > 0), isTrue);
      expect(
        stopwatch.elapsed,
        lessThan(protocolConsistencyBudget),
        reason: 'The Consistency view must plan and match its longest range '
            'within the budget the spec pins.',
      );
    });

    test(
        'Progress training cores over 366 days of five years of history stay '
        'under 50 ms', () async {
      final fixture = await buildProgressHistoryFixture();
      addTearDown(fixture.database.close);
      final today = fixture.today;
      final from = today.addDays(-(progressTrainingRangeDays - 1));
      final weekStart =
          today.addDays(-(today.toLocalDateTime().weekday - DateTime.monday));
      // The repository reads the cards wait on, outside the timed work.
      final workouts = await fixture.repositories.workoutSessions
          .watchProgressWorkoutsBetween(from, today)
          .first;
      final planFacts =
          await fixture.repositories.routineUpNext.watchWeeklyPlans().first;
      final plans = [for (final plan in planFacts) plan.toWeeklyPlan()];

      final stopwatch = Stopwatch()..start();
      final week = trainingWeek(
        plans: plans,
        workouts: workouts,
        weekStart: weekStart,
        today: today,
      );
      final days = trainingDays(workouts: workouts, from: from, to: today);
      stopwatch.stop();

      // The whole history is there, and the year's share of it was read.
      final setCount = await fixture.database
          .customSelect('SELECT COUNT(*) AS count FROM logged_sets')
          .getSingle();
      expect(setCount.read<int>('count'), progressHistorySetCount);
      expect(
        await fixture.repositories.workoutSessions.listActive(),
        hasLength(progressHistoryWorkoutCount),
      );
      expect(fixture.exerciseIds, hasLength(progressHistoryExerciseCount));
      expect(
        workouts.length,
        greaterThan(
          progressHistoryWorkoutCount ~/ progressHistoryYears - 10,
        ),
      );
      expect(workouts.every((workout) => workout.isLogged), isTrue);
      expect(week.comparedRoutineIds, hasLength(2));
      expect(days, hasLength(progressTrainingRangeDays));
      expect(
        days.where((day) => day.workoutCount > 0).length,
        workouts.map((workout) => workout.localDate).toSet().length,
      );
      expect(
        stopwatch.elapsed,
        lessThan(progressTrainingBudget),
        reason: 'This week and Trained days must compute the 1-year period '
            'within the budget the spec pins.',
      );
    });

    test(
        'Progress Measures over five years of history find the 1-year '
        'period\'s New Bests under 1 000 ms', () async {
      final fixture = await buildProgressHistoryFixture();
      addTearDown(fixture.database.close);
      final analytics = ExerciseAnalyticsRepository(fixture.database);
      final today = fixture.today;
      final from = today.addDays(-(progressTrainingRangeDays - 1));
      // The repository read the card waits on, outside the timed work.
      final history = await analytics.watchProgressHistory().first;

      final stopwatch = Stopwatch()..start();
      final bests = newBestsInHistory(
        (history: history, from: from, to: today),
      );
      stopwatch.stop();

      // Every exercise's Performed Sets were read, and the background path
      // the card uses agrees with the timed one.
      expect(history.profiles.keys, unorderedEquals(fixture.exerciseIds));
      expect(
        history.workoutsByExercise.values
            .expand((workouts) => workouts)
            .fold<int>(0, (sum, workout) => sum + workout.sets.length),
        progressHistorySetCount - progressHistorySetCount ~/ 20,
      );
      expect(bests, isNotEmpty);
      expect(
        bests.every(
          (best) =>
              best.localDate.compareTo(from) >= 0 &&
              best.localDate.compareTo(today) <= 0,
        ),
        isTrue,
      );
      expect(
        bests.map((best) => best.exerciseId).toSet(),
        hasLength(progressHistoryExerciseCount),
      );
      expect(
        (await analytics.watchNewBests(from, today).first)
            .map((best) => '${best.exerciseId}:${best.workoutId}'),
        bests.map((best) => '${best.exerciseId}:${best.workoutId}'),
      );
      expect(
        stopwatch.elapsed,
        lessThan(progressNewBestsBudget),
        reason: 'New bests must judge every exercise\'s whole history within '
            'the budget the spec pins.',
      );
    });

    test('Exercise Overview aggregates 50k-set fixture under 300 ms', () {
      final fixture = buildLargeExerciseOverviewHistoryFixture();
      final stopwatch = Stopwatch()..start();

      final overview = buildExerciseOverviewModel(
        exercise: fixture.exercise,
        workouts: fixture.workouts,
        sets: fixture.sets,
      );
      stopwatch.stop();

      expect(fixture.sets, hasLength(exerciseOverviewLargeHistorySetCount));
      expect(
        overview.setsById,
        hasLength(exerciseOverviewLargeHistorySetCount),
      );
      expect(
        stopwatch.elapsed,
        lessThan(exerciseOverviewAggregateBudget),
        reason:
            'Exercise Overview must stay under the documented M5 large-history '
            'budget.',
      );
    });

    test('50k-set fixture seeds persisted Exercise Overview history', () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repositories = TrainingRepositories(database);
      final fixture = await seedLargeExerciseOverviewHistoryFixture(database);

      final overview = await ExerciseOverviewRepository(
        repositories,
      ).getForExercise(fixture.exercise.id);

      expect(
        overview?.setsById,
        hasLength(exerciseOverviewLargeHistorySetCount),
      );
      expect(overview?.groups, hasLength(fixture.workouts.length));
    });

    testWidgets('set save confirms optimistically within one frame', (
      tester,
    ) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repositories = TrainingRepositories(database);
      final workoutExerciseId = await tester.runAsync(
        () => _createWorkoutExercise(repositories),
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
      await tester.pump(setSaveConfirmationFrameBudget);

      expect(
        find.byKey(TrainingScreen.saveSetConfirmationKey),
        findsOneWidget,
      );

      await _settleRepositoryWork(tester);
      final workoutExercise = await tester.runAsync(
        () => repositories.workoutExercises.getById(workoutExerciseId),
      );
      final sets = await tester.runAsync(
        () => repositories.sets.listActiveForWorkout(
          workoutExercise!.workoutId,
        ),
      );
      expect(sets, hasLength(1));
    });

    test('cold start Home data path stays under 2 s', () async {
      final database = AppDatabase.inMemory();
      final repositories = TrainingRepositories(database);
      try {
        const selectedDate = TrainingDayDate(year: 2026, month: 6, day: 21);
        final repository = RepositoryHomeRepository(repositories);
        final stopwatch = Stopwatch()..start();

        final summary = await repository
            .watchTrainingDay(selectedDate)
            .first
            .timeout(coldStartHomeInteractiveBudget);
        stopwatch.stop();

        expect(summary.exercises, isEmpty);
        expect(summary.workoutExercises, isEmpty);
        expect(summary.sets, isEmpty);
        expect(summary.status, 'No workout started');
        expect(
          stopwatch.elapsed,
          lessThan(coldStartHomeInteractiveBudget),
          reason: 'Cold start must load the first Home data needed for an '
              'interactive Home Screen before the M5 target.',
        );
      } finally {
        await database.close();
      }
    });
  });
}

Future<String> _createWorkoutExercise(TrainingRepositories repositories) async {
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Bench Press',
      type: ExerciseType(
        const <DimensionId>[DimensionId.load, DimensionId.reps],
      ),
    ),
  );
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 6, 21, 7),
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

Future<void> _pumpTrainingScreen(
  WidgetTester tester,
  TrainingRepositories repositories,
  String workoutExerciseId,
) async {
  final initialWorkoutExercise = await tester.runAsync(
    () => repositories.workoutExercises.getById(workoutExerciseId),
  );
  final initialExercise = await tester.runAsync(
    () => repositories.exercises.getById(initialWorkoutExercise!.exerciseId),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => repositories.database),
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TrainingScreen(
          workoutExerciseId: workoutExerciseId,
          initialWorkoutExercise: initialWorkoutExercise,
          initialExercise: initialExercise,
          setsStream: Stream<List<LoggedSetRecord>>.value(
            const <LoggedSetRecord>[],
          ),
          recordSetIdsStream: Stream<Set<String>>.value(const <String>{}),
          enableRestTimerTicker: false,
        ),
      ),
    ),
  );
  await _waitForFinder(tester, find.byKey(TrainingScreen.saveSetButtonKey));
}

Future<void> _settleRepositoryWork(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pump();
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

/// [foodHistoryEntryCount] Food Entries for [foodHistoryFoodCount] Foods
/// (a third each User Foods, USDA and Open Food Facts) in 3,400 Meals over
/// five years before [now], with a few Foods logged far more than the rest.
Future<void> _seedFoodHistory(
  AppDatabase database, {
  required DateTime now,
}) async {
  const mealCount = 3400;
  const span = Duration(days: 5 * 365);
  const sources = <String>['user', 'usda', 'openFoodFacts'];
  final nutrients = NutrientVector.full(const {}).toJsonString();
  final portion = Portion(
    value: 100,
    entered: '100',
    unit: PortionUnit.gram,
  ).toJsonString();
  await database.batch((batch) {
    batch.insertAll(database.foods, [
      for (var food = 0; food < foodHistoryFoodCount; food += 3)
        FoodsCompanion.insert(
          id: 'food-$food',
          name: 'Food $food',
          nutrientValuesJson: nutrients,
          updatedAt: now,
        ),
    ]);
    batch.insertAll(database.meals, [
      for (var meal = 0; meal < mealCount; meal += 1)
        MealsCompanion.insert(
          id: 'meal-$meal',
          mealType: 'Breakfast',
          startedAt: now.subtract(span * (meal / mealCount)),
          timezone: 'UTC',
          updatedAt: now,
        ),
    ]);
    batch.insertAll(database.foodEntries, [
      for (var entry = 0; entry < foodHistoryEntryCount; entry += 1)
        () {
          // Every Food at least once, then a skew towards low indexes.
          final food = entry < foodHistoryFoodCount
              ? entry
              : (entry * entry * 7919) %
                  foodHistoryFoodCount ~/
                  (1 + entry % 4);
          final meal = entry * mealCount ~/ foodHistoryEntryCount;
          return FoodEntriesCompanion.insert(
            id: 'entry-$entry',
            mealId: 'meal-$meal',
            entryKind: const Value('food'),
            position: entry % 6,
            name: 'Food $food',
            nutrientValuesJson: nutrients,
            foodId: Value('food-$food'),
            foodSource: Value(sources[food % 3]),
            isLiquid: const Value(false),
            portionJson: Value(portion),
            updatedAt: now,
          );
        }(),
    ]);
  });
}

/// A Your foods row; one in ten matches "greek yo".
FoodPickerItem _yourFoodsItem(int index) {
  return FoodPickerItem(
    id: 'food-$index',
    name: index % 10 == 0 ? 'Greek yoghurt $index' : 'Food $index',
    origin: FoodPickerOrigin.history,
    foodSource: FoodSource.user,
    nutrientsPer100: NutrientVector.full(const {}),
    isLiquid: false,
    lastPortion: Portion(value: 100, entered: '100', unit: PortionUnit.gram),
  );
}

/// Product lines with realistic names and brands; one in ten is a Greek
/// yoghurt, so a common prefix query has many matches to rank.
List<String> _syntheticOpenFoodFactsLines(int count) {
  const adjectives = <String>[
    'Greek', 'Organic', 'Light', 'Classic', 'Crunchy', 'Smooth', 'Wholegrain',
    'Roasted', 'Spicy', 'Original',
  ];
  const foods = <String>[
    'yogurt', 'oats', 'peanut butter', 'crackers', 'muesli', 'chips', 'bread',
    'cheese', 'juice', 'cereal', 'noodles', 'soup',
  ];
  const brands = <String>[
    'Chobani', 'Sanitarium', 'Arnotts', 'Kelloggs', 'Coles', 'Woolworths',
    'Tesco', 'Kirkland', 'Heinz', 'Uncle Tobys',
  ];
  return [
    for (var i = 0; i < count; i += 1)
      encodeBundleProductLine(
        offProduct(
          (9300000000000 + i).toString(),
          i % 10 == 0
              ? 'Greek yogurt ${foods[i % foods.length]} $i'
              : '${adjectives[i % adjectives.length]} '
                  '${foods[(i ~/ 3) % foods.length]} $i',
          brand: brands[(i ~/ 7) % brands.length],
          scans: i % 500,
        ),
      ),
  ];
}

/// The Consistency view's worst case: one Compound in 3 Protocols over 366
/// days, each Protocol with 5 Schedule Versions of mixed rules (several
/// times a day, chosen weekdays, every N days, untimed), one with a cycle
/// and Pauses, and 800 Doses spread over the range at varied times.
({
  List<PlanProtocol> protocols,
  List<PlanDose> doses,
  ProtocolDayDate from,
  ProtocolDayDate to,
}) _consistencyFixture() {
  const compoundId = 'compound-consistency';
  const from = ProtocolDayDate(year: 2025, month: 10, day: 28);
  final to = from.addDays(protocolConsistencyRangeDays - 1);
  const amount = PlanAmount(
    amountValue: 1,
    amountEntered: '1',
    unit: DoseUnit.milligram,
    route: DoseRoute.oral,
  );
  final rules = <ScheduleRule>[
    TimedScheduleRule(
      days: const DailyScheduleDays(),
      times: const <String>['07:00', '13:00', '21:00'],
    ),
    TimedScheduleRule(
      days: WeekdayScheduleDays(const <int>[1, 3, 5]),
      times: const <String>['08:30'],
    ),
    TimedScheduleRule(
      days: EveryNDaysScheduleDays(n: 3, anchor: from, anchorIsDefault: true),
      times: const <String>['06:00', '18:00'],
    ),
    UntimedScheduleRule(days: const DailyScheduleDays(), count: 2),
    TimedScheduleRule(
      days: const DailyScheduleDays(),
      times: const <String>['09:00', '12:00', '15:00', '18:00', '21:00'],
    ),
  ];
  final versionSpacing =
      protocolConsistencyRangeDays ~/ protocolConsistencyVersionsPerProtocol;
  final protocols = <PlanProtocol>[
    for (var p = 0; p < protocolConsistencyProtocolCount; p += 1)
      PlanProtocol(
        protocolId: 'protocol-$p',
        startLocalDate: from,
        period: p == 0
            ? ProtocolPeriod(
                cycle: ProtocolCycle(
                  onDays: 60,
                  offDays: 30,
                  anchor: from,
                  anchorIsDefault: true,
                ),
                pauses: <ProtocolPause>[
                  ProtocolPause(from: from.addDays(20), to: from.addDays(26)),
                  ProtocolPause(from: from.addDays(200), to: from.addDays(210)),
                ],
              )
            : null,
        members: <PlanMember>[
          PlanMember(
            memberId: 'member-$p',
            compoundId: compoundId,
            versions: <ScheduleVersion>[
              for (var v = 0; v < protocolConsistencyVersionsPerProtocol; v += 1)
                ScheduleVersion(
                  id: 'version-$p-$v',
                  effectiveFrom: from.addDays(v * versionSpacing),
                  rule: rules[(p + v) % rules.length],
                  amount: amount,
                ),
            ],
          ),
        ],
      ),
  ];

  final sequenceByDate = <ProtocolDayDate, int>{};
  final doses = <PlanDose>[];
  for (var index = 0; index < protocolConsistencyDoseCount; index += 1) {
    final date = from.addDays((index * 37) % protocolConsistencyRangeDays);
    final minutes = (index * 173) % (24 * 60);
    final sequence = sequenceByDate[date] ?? 0;
    sequenceByDate[date] = sequence + 1;
    doses.add(
      PlanDose(
        doseId: 'dose-${index.toString().padLeft(4, '0')}',
        compoundId: compoundId,
        localDate: date,
        localTime: planLocalTime(minutes ~/ 60, minutes % 60),
        sequence: sequence,
      ),
    );
  }
  return (protocols: protocols, doses: doses, from: from, to: to);
}
