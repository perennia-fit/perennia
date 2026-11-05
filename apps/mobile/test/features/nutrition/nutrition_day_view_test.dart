import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/open_food_facts_repository.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart'
    show
        DuplicateMealTypeNameException,
        TrainingRepositories,
        trainingRepositoriesProvider;
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/controllers/meal_screen_controller.dart';
import 'package:perennia/features/nutrition/controllers/nutrition_day_controller.dart';
import 'package:perennia/features/nutrition/repositories/add_food_repository.dart';
import 'package:perennia/features/nutrition/widgets/meal_screen.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_attribution.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_day_view.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

import 'add_food_repository_fakes.dart';

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

  testWidgets('renders unknown macro totals as dash instead of zero', (
    tester,
  ) async {
    final totals = NutrientTotals.fromEntries(
      <FoodEntryRecord>[_foodEntryWithMissingCarbs()],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: NutritionDaySummary(totals: totals),
        ),
      ),
    );

    expect(find.byKey(NutritionDayView.daySummaryKey), findsOneWidget);
    expect(find.text('Calories'), findsOneWidget);
    expect(find.text('Protein'), findsOneWidget);
    expect(find.text('Carbs'), findsOneWidget);
    expect(find.text('Fat'), findsOneWidget);
    expect(
      _summaryValueText(tester, NutrientId.energy),
      '100 kcal',
    );
    expect(
      _summaryValueText(tester, NutrientId.protein),
      '10 g',
    );
    expect(
      _summaryValueText(tester, NutrientId.fat),
      '3 g',
    );
    expect(
      _summaryValueText(tester, NutrientId.carbohydrate),
      _unknownTotalLabel,
    );
    expect(
      find.byKey(
        NutritionDayView.incompleteMarkerKey(NutrientId.carbohydrate),
      ),
      findsOneWidget,
    );
    expect(find.text('0 g'), findsNothing);
  });

  testWidgets(
      'Nutrition Day view meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nutritionDayControllerProvider.overrideWith(
              () => _FakeNutritionDayController(
                _nutritionDayWithMissingCarbs(),
              ),
            ),
            mealTypeListProvider.overrideWith(
              (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NutritionDayView(),
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(
          NutritionDayView.incompleteMarkerKey(NutrientId.carbohydrate),
        ),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Meal cards list Food Entry rows with amount and derived energy',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(
            () => _FakeNutritionDayController(
              _nutritionDayWithFoodEntryRows(),
            ),
          ),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(NutritionDayView.mealCardKey('meal-breakfast')),
    );

    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('125 g'), findsOneWidget);
    expect(find.text('65 kcal'), findsWidgets);
    expect(find.text('Quick calories'), findsOneWidget);
    expect(find.text('Quick entry'), findsOneWidget);
    expect(find.text('90 kcal'), findsOneWidget);
    expect(find.text('Mystery bar'), findsOneWidget);
    expect(find.text('50 g'), findsOneWidget);
    expect(find.text(_unknownTotalLabel), findsNWidgets(3));
  });

  testWidgets(
      'imported entries surface the preserved provider string and a '
      'non-blocking review-flag marker', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(
            () => _FakeNutritionDayController(_nutritionDayWithImportedEntry()),
          ),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(NutritionDayView.mealCardKey('meal-breakfast')),
    );

    // Generic Imported origin shows the preserved provider string, not a bare
    // "Imported".
    expect(
      find.byKey(NutritionDayView.importedEntryBadgeKey('entry-imported')),
      findsOneWidget,
    );
    expect(find.textContaining('Acme Diet Tracker'), findsOneWidget);
    // The soft-warn review flag surfaces inline, never as a blocking dialog.
    expect(
      find.byKey(NutritionDayView.reviewFlagMarkerKey('entry-imported')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
      'an Open Food Facts entry shows its source badge without the licence',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(
            () => _FakeNutritionDayController(_nutritionDayWithOpenFoodFactsEntry()),
          ),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(NutritionDayView.mealCardKey('meal-breakfast')),
    );

    final badge = find.byKey(
      NutritionAttributionKeys.foodSourceBadge(FoodSource.openFoodFacts),
    );
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('Open Food Facts')),
      findsOneWidget,
    );
    expect(find.textContaining('ODbL'), findsNothing);
    expect(
      find.byKey(NutritionDayView.importedEntryBadgeKey('entry-off')),
      findsNothing,
    );
  });

  testWidgets(
      'imported-entry day view meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nutritionDayControllerProvider.overrideWith(
              () =>
                  _FakeNutritionDayController(_nutritionDayWithImportedEntry()),
            ),
            mealTypeListProvider.overrideWith(
              (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NutritionDayView(),
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(NutritionDayView.importedEntryBadgeKey('entry-imported')),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('date strip arrows and swipe move the selected Nutrition Day',
      (tester) async {
    final controller = _FakeNutritionDayController(
      _nutritionDayWithFoodEntryRows(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(() => controller),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(NutritionDayView.dayHeaderKey));

    await tester.tap(find.byKey(NutritionDayView.previousDayButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(NutritionDayView.nextDayButtonKey));
    await tester.pump();
    await tester.fling(
      find.byKey(NutritionDayView.dayHeaderKey),
      const Offset(400, 0),
      1000,
    );
    await tester.pump();
    await tester.fling(
      find.byKey(NutritionDayView.dayHeaderKey),
      const Offset(-400, 0),
      1000,
    );
    await tester.pump();

    expect(controller.previousDayCount, 2);
    expect(controller.nextDayCount, 2);
  });

  testWidgets('Meal Type manager adds renames archives and exposes reorder', (
    tester,
  ) async {
    final controller = _FakeNutritionDayController(_emptyNutritionDay());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(() => controller),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(NutritionDayView.daySummaryKey));

    final manageButton = find.byKey(NutritionDayView.manageMealTypesButtonKey);
    await tester.scrollUntilVisible(
      manageButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(manageButton);
    await tester.pumpAndSettle();

    expect(find.text('Manage Meal Types'), findsOneWidget);
    expect(
      find.byKey(
        NutritionDayView.mealTypeReorderHandleKey('meal-type-breakfast'),
      ),
      findsOneWidget,
    );
    final reorderableList = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    reorderableList.onReorderItem!(0, 2);
    await tester.pump();

    expect(
      controller.reorderedMealTypeIds,
      <List<String>>[
        <String>[
          'meal-type-lunch',
          'meal-type-dinner',
          'meal-type-breakfast',
          'meal-type-snack',
        ],
      ],
    );

    await tester.tap(find.byKey(NutritionDayView.addMealTypeButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(NutritionDayView.mealTypeNameFieldKey),
      'Pre-workout',
    );
    await tester.tap(find.byKey(NutritionDayView.saveMealTypeButtonKey));
    await tester.pumpAndSettle();

    expect(controller.createdMealTypeNames, <String>['Pre-workout']);

    await tester.tap(
      find.byKey(NutritionDayView.editMealTypeButtonKey('meal-type-snack')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(NutritionDayView.mealTypeNameFieldKey),
      'Mini meal',
    );
    await tester.tap(find.byKey(NutritionDayView.saveMealTypeButtonKey));
    await tester.pumpAndSettle();

    expect(
      controller.renamedMealTypes,
      <String>['meal-type-snack:Mini meal'],
    );

    await tester.tap(
      find.byKey(NutritionDayView.archiveMealTypeButtonKey('meal-type-snack')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(NutritionDayView.confirmArchiveMealTypeButtonKey),
    );
    await tester.pumpAndSettle();

    expect(controller.archivedMealTypeIds, <String>['meal-type-snack']);
  });

  testWidgets('Meal Type form shows duplicate-name errors inline', (
    tester,
  ) async {
    final controller = _FakeNutritionDayController(
      _emptyNutritionDay(),
      duplicateMealTypeNames: <String>{'snack'},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionDayControllerProvider.overrideWith(() => controller),
          mealTypeListProvider.overrideWith(
            (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NutritionDayView(),
        ),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(NutritionDayView.daySummaryKey));

    final manageButton = find.byKey(NutritionDayView.manageMealTypesButtonKey);
    await tester.scrollUntilVisible(
      manageButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(manageButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(NutritionDayView.addMealTypeButtonKey));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(NutritionDayView.mealTypeNameFieldKey),
      ' Snack ',
    );
    await tester.tap(find.byKey(NutritionDayView.saveMealTypeButtonKey));
    await tester.pump();

    expect(find.text('Meal Type already exists'), findsOneWidget);
    expect(find.text('New Meal Type'), findsOneWidget);
    expect(controller.createdMealTypeNames, isEmpty);
  });

  testWidgets(
      'Meal Type management surfaces meet accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final controller = _FakeNutritionDayController(_emptyNutritionDay());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nutritionDayControllerProvider.overrideWith(() => controller),
            mealTypeListProvider.overrideWith(
              (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NutritionDayView(),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.byKey(NutritionDayView.daySummaryKey));

      final manageButton =
          find.byKey(NutritionDayView.manageMealTypesButtonKey);
      await tester.scrollUntilVisible(
        manageButton,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(manageButton);
      await tester.pumpAndSettle();

      expect(find.byKey(NutritionDayView.mealTypeTileKey('meal-type-snack')),
          findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.byKey(NutritionDayView.addMealTypeButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('New Meal Type'), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          NutritionDayView.archiveMealTypeButtonKey('meal-type-snack'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Archive Snack?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  group('Meal cards (docs/designs/meal-logging.md §6)', () {
    Future<void> pumpDay(
      WidgetTester tester,
      NutritionDayRecord day, {
      DateTime? now,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nutritionDayControllerProvider.overrideWith(
              () => _FakeNutritionDayController(day),
            ),
            mealTypeListProvider.overrideWith(
              (ref) => Stream<List<MealTypeRecord>>.value(_mealTypes()),
            ),
            mealScreenClockProvider.overrideWith(
              (ref) => () => now ?? DateTime(2026, 6, 26, 16),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NutritionDayView(),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.byKey(NutritionDayView.daySummaryKey));
    }

    testWidgets(
        'a card leads with its time at the frozen offset and its type, '
        'then entries and totals', (tester) async {
      await pumpDay(tester, _nutritionDayWithHeaderForms());

      // 02:00 UTC read at +10:00 is 12:00 where it was eaten, whatever the
      // device's zone.
      final lunch = find.byKey(NutritionDayView.mealCardKey('meal-lunch'));
      expect(
        find.descendant(of: lunch, matching: find.text('12:00 PM · Lunch')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(
              find.descendant(
                  of: lunch, matching: find.text('12:00 PM · Lunch')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.descendant(of: lunch, matching: find.text('Rice')),
              )
              .dy,
        ),
      );
      expect(
        find.descendant(of: lunch, matching: find.text('100 kcal')),
        findsWidgets,
      );

      // A date Meal never shows a clock time.
      expect(
        find.descendant(
          of: find.byKey(NutritionDayView.mealCardKey('meal-imported')),
          matching: find.text('time not recorded · Breakfast'),
        ),
        findsOneWidget,
      );

      // A Meal with no Food Entries asks for foods, and has no totals row.
      final empty = find.byKey(NutritionDayView.mealCardKey('meal-empty'));
      expect(
        find.descendant(
          of: empty,
          matching: find.text('3:30 PM · Snack · add foods'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: empty, matching: find.textContaining('kcal')),
        findsNothing,
      );

      // One Log meal button replaces the per-Meal-Type chips, and cards
      // carry no Add food button: foods are added on the Meal screen.
      expect(find.text('Add food'), findsNothing);
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(NutritionDayView.logMealButtonKey),
        200,
        scrollable: scrollable,
      );
      await tester.scrollUntilVisible(
        find.byKey(NutritionDayView.editGoalsButtonKey),
        200,
        scrollable: scrollable,
      );
      expect(
        find.byKey(NutritionDayView.manageMealTypesButtonKey),
        findsOneWidget,
      );
    });

    testWidgets('lists same-type Meals as separate occasions', (tester) async {
      await pumpDay(tester, _nutritionDayWithThreeSnacks());

      for (final id in <String>['meal-snack-1', 'meal-snack-2']) {
        expect(find.byKey(NutritionDayView.mealCardKey(id)), findsOneWidget);
      }
      final thirdSnackCard = find.byKey(
        NutritionDayView.mealCardKey('meal-snack-3'),
      );
      await tester.scrollUntilVisible(
        thirdSnackCard,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(thirdSnackCard, findsOneWidget);
      expect(find.text('9:00 PM · Snack'), findsOneWidget);
    });

    testWidgets('a card is a labelled tap target of at least 48 dp',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpDay(tester, _nutritionDayWithHeaderForms());

      final empty = find.byKey(NutritionDayView.mealCardKey('meal-empty'));
      expect(tester.getSize(empty).height, greaterThanOrEqualTo(48));
      expect(
        find.bySemanticsLabel(
          RegExp(r'^3:30 PM, Snack · add foods\. Open meal'),
        ),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
    });

    testWidgets('Log meal is hidden on a future day, shown on today',
        (tester) async {
      await pumpDay(
        tester,
        _emptyNutritionDay(),
        now: DateTime(2026, 6, 25, 23, 50),
      );
      await tester.scrollUntilVisible(
        find.byKey(NutritionDayView.manageMealTypesButtonKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(NutritionDayView.logMealButtonKey), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpDay(
        tester,
        _emptyNutritionDay(),
        now: DateTime(2026, 6, 26, 0, 10),
      );
      await tester.scrollUntilVisible(
        find.byKey(NutritionDayView.logMealButtonKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Log meal'), findsOneWidget);
    });
  });

  group('the Nutrition Day over a real database', () {
    const day = NutritionDayDate(year: 2026, month: 6, day: 26);
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() async {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
      await repositories.nutrition.ensureDefaultMealTypes();
    });

    tearDown(() async {
      await database.close();
    });

    Future<void> pumpDay(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainingRepositoriesProvider.overrideWith((ref) => repositories),
            selectedNutritionDayProvider.overrideWith(
              () => _FixedNutritionDay(day),
            ),
            mealScreenClockProvider.overrideWith(
              (ref) => () => DateTime(2026, 6, 26, 16),
            ),
            addFoodRepositoryProvider.overrideWith(
              (ref) => const _NoFoodsRepository(),
            ),
            openFoodFactsRepositoryProvider.overrideWith(
              (ref) => const StubOpenFoodFactsRepository(),
            ),
            settingsRepositoryProvider.overrideWith(
              (ref) => InMemorySettingsRepository(),
            ),
            bundleStatusProvider.overrideWith(
              (ref) => Stream<BundleStatus>.value(BundleStatus.ready),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NutritionDayView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<String> seedMeal(DateTime startedAt, String mealType) {
      return repositories.nutrition.createMeal(
        PendingMeal(
          id: repositories.nutrition.newMealId(),
          startedAt: startedAt,
          mealTypeName: mealType,
        ),
      );
    }

    testWidgets(
        'lists Meals in time order: a 15:00 Breakfast after a 12:00 Lunch',
        (tester) async {
      final breakfastId = await seedMeal(
        DateTime(2026, 6, 26, 15),
        'Breakfast',
      );
      final lunchId = await seedMeal(DateTime(2026, 6, 26, 12), 'Lunch');

      await pumpDay(tester);

      final lunch = find.byKey(NutritionDayView.mealCardKey(lunchId));
      final breakfast = find.byKey(NutritionDayView.mealCardKey(breakfastId));
      expect(lunch, findsOneWidget);
      expect(breakfast, findsOneWidget);
      expect(
        tester.getTopLeft(lunch).dy,
        lessThan(tester.getTopLeft(breakfast).dy),
      );
      expect(find.text('12:00 PM · Lunch · add foods'), findsOneWidget);
      expect(find.text('3:00 PM · Breakfast · add foods'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('a card tap opens that Meal on the Meal screen',
        (tester) async {
      final mealId = await seedMeal(DateTime(2026, 6, 26, 12), 'Lunch');

      await pumpDay(tester);
      await tester.tap(find.byKey(NutritionDayView.mealCardKey(mealId)));
      await tester.pumpAndSettle();

      final screen = tester.widget<MealScreen>(find.byType(MealScreen));
      expect(screen.mealId, mealId);
      expect(
        find.descendant(
          of: find.byKey(MealScreen.headerKey),
          matching: find.text('12:00 PM · Lunch · add foods'),
        ),
        findsOneWidget,
      );

      await _unmount(tester);
    });

    testWidgets('Log meal opens a new Meal on the shown day', (tester) async {
      await pumpDay(tester);

      final logMeal = find.byKey(NutritionDayView.logMealButtonKey);
      await tester.scrollUntilVisible(
        logMeal,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(logMeal);
      await tester.pumpAndSettle();

      final screen = tester.widget<MealScreen>(find.byType(MealScreen));
      expect(screen.mealId, isNull);
      expect(screen.day, day);
      expect(
        await database.select(database.meals).get(),
        isEmpty,
        reason: 'opening the Meal screen writes nothing',
      );

      await _unmount(tester);
    });
  });
}

const _unknownTotalLabel = '\u2014';

class _FakeNutritionDayController extends NutritionDayController {
  _FakeNutritionDayController(
    this.day, {
    Set<String>? duplicateMealTypeNames,
  }) : duplicateMealTypeNames = duplicateMealTypeNames ?? const <String>{};

  final NutritionDayRecord day;
  final Set<String> duplicateMealTypeNames;
  final createdMealTypeNames = <String>[];
  final renamedMealTypes = <String>[];
  final reorderedMealTypeIds = <List<String>>[];
  final archivedMealTypeIds = <String>[];
  var previousDayCount = 0;
  var nextDayCount = 0;

  @override
  Stream<NutritionDayState> build() {
    return Stream<NutritionDayState>.value(NutritionDayState(day: day));
  }

  @override
  Future<String> createMealType({
    required String name,
  }) async {
    _throwIfDuplicateMealTypeName(name);
    createdMealTypeNames.add(name);
    return 'created-meal-type';
  }

  @override
  Future<void> renameMealType({
    required MealTypeRecord mealType,
    required String name,
  }) async {
    _throwIfDuplicateMealTypeName(name);
    renamedMealTypes.add('${mealType.id}:$name');
  }

  void _throwIfDuplicateMealTypeName(String name) {
    if (duplicateMealTypeNames.contains(name.trim().toLowerCase())) {
      throw DuplicateMealTypeNameException(name);
    }
  }

  @override
  Future<void> reorderMealTypes(List<String> orderedIds) async {
    reorderedMealTypeIds.add(List<String>.unmodifiable(orderedIds));
  }

  @override
  Future<void> archiveMealType(String id) async {
    archivedMealTypeIds.add(id);
  }

  @override
  void showPreviousDay() {
    previousDayCount += 1;
  }

  @override
  void showNextDay() {
    nextDayCount += 1;
  }
}

String? _summaryValueText(WidgetTester tester, NutrientId id) {
  return tester
      .widget<Text>(find.byKey(NutritionDayView.summaryValueKey(id)))
      .data;
}

NutritionDayRecord _emptyNutritionDay() {
  return NutritionDayRecord(
    localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
    meals: const <NutritionDayMealRecord>[],
  );
}

FoodEntryRecord _foodEntryWithMissingCarbs() {
  return FoodEntryRecord(
    id: 'food-entry-1',
    mealId: 'meal-1',
    kind: FoodEntryKind.quickEntry,
    position: 0,
    name: 'Known calories, missing carbs',
    nutrients: NutrientVector.full(<NutrientId, NutrientAmount>{
      NutrientId.energy: NutrientAmount.complete(
        value: 100,
        entered: '100',
        unit: NutrientUnit.kilocalorie,
      ),
      NutrientId.protein: NutrientAmount.complete(
        value: 10,
        entered: '10',
        unit: NutrientUnit.gram,
      ),
      NutrientId.fat: NutrientAmount.complete(
        value: 3,
        entered: '3',
        unit: NutrientUnit.gram,
      ),
    }),
    updatedAt: DateTime.utc(2026, 6, 26),
  );
}

NutritionDayRecord _nutritionDayWithMissingCarbs() {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-1',
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, 26, 7),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
          updatedAt: DateTime.utc(2026, 6, 26, 7),
        ),
        entries: [_foodEntryWithMissingCarbs()],
      ),
    ],
  );
}

NutritionDayRecord _nutritionDayWithThreeSnacks() {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      _snackMeal(
        id: 'meal-snack-1',
        startedAt: DateTime(2026, 6, 26, 10),
        entryName: 'Apple',
      ),
      _snackMeal(
        id: 'meal-snack-2',
        startedAt: DateTime(2026, 6, 26, 15),
        entryName: 'Yogurt',
      ),
      _snackMeal(
        id: 'meal-snack-3',
        startedAt: DateTime(2026, 6, 26, 21),
        entryName: 'Toast',
      ),
    ],
  );
}

NutritionDayRecord _nutritionDayWithFoodEntryRows() {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-breakfast',
          mealType: 'Breakfast',
          startedAt: DateTime(2026, 6, 26, 8),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
          updatedAt: DateTime.utc(2026, 6, 26, 8),
        ),
        entries: [
          FoodEntryRecord(
            id: 'entry-apple',
            mealId: 'meal-breakfast',
            kind: FoodEntryKind.food,
            position: 0,
            name: 'Apple',
            nutrients: NutrientVector.energyAndMacros(
              energy: NutrientAmount.complete(
                value: 52,
                entered: '52',
                unit: NutrientUnit.kilocalorie,
              ),
              protein: NutrientAmount.complete(
                value: 0.3,
                entered: '0.3',
                unit: NutrientUnit.gram,
              ),
              carbohydrate: NutrientAmount.complete(
                value: 14,
                entered: '14',
                unit: NutrientUnit.gram,
              ),
              fat: NutrientAmount.complete(
                value: 0.2,
                entered: '0.2',
                unit: NutrientUnit.gram,
              ),
            ),
            foodId: 'food-apple',
            portion: Portion(
              value: 125,
              entered: '125',
              unit: PortionUnit.gram,
            ),
            foodSource: FoodSource.user,
            isLiquid: false,
            updatedAt: DateTime.utc(2026, 6, 26, 8),
          ),
          FoodEntryRecord(
            id: 'entry-quick-calories',
            mealId: 'meal-breakfast',
            kind: FoodEntryKind.quickEntry,
            position: 1,
            name: 'Quick calories',
            nutrients: NutrientVector.energyAndMacros(
              energy: NutrientAmount.complete(
                value: 90,
                entered: '90',
                unit: NutrientUnit.kilocalorie,
              ),
              protein: NutrientAmount.complete(
                value: 0,
                entered: '0',
                unit: NutrientUnit.gram,
              ),
              carbohydrate: NutrientAmount.complete(
                value: 20,
                entered: '20',
                unit: NutrientUnit.gram,
              ),
              fat: NutrientAmount.complete(
                value: 1,
                entered: '1',
                unit: NutrientUnit.gram,
              ),
            ),
            updatedAt: DateTime.utc(2026, 6, 26, 8),
          ),
          FoodEntryRecord(
            id: 'entry-mystery-bar',
            mealId: 'meal-breakfast',
            kind: FoodEntryKind.food,
            position: 2,
            name: 'Mystery bar',
            nutrients: NutrientVector.energyAndMacros(
              energy: NutrientAmount.unknown(NutrientUnit.kilocalorie),
              protein: NutrientAmount.complete(
                value: 10,
                entered: '10',
                unit: NutrientUnit.gram,
              ),
              carbohydrate: NutrientAmount.complete(
                value: 20,
                entered: '20',
                unit: NutrientUnit.gram,
              ),
              fat: NutrientAmount.complete(
                value: 6,
                entered: '6',
                unit: NutrientUnit.gram,
              ),
            ),
            foodId: 'food-mystery-bar',
            portion: Portion(
              value: 50,
              entered: '50',
              unit: PortionUnit.gram,
            ),
            foodSource: FoodSource.user,
            isLiquid: false,
            updatedAt: DateTime.utc(2026, 6, 26, 8),
          ),
        ],
      ),
    ],
  );
}

NutritionDayMealRecord _snackMeal({
  required String id,
  required DateTime startedAt,
  required String entryName,
}) {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
  return NutritionDayMealRecord(
    meal: MealRecord(
      id: id,
      mealType: 'Snack',
      startedAt: startedAt,
      timezone: 'Australia/Brisbane',
      localDate: localDate,
      updatedAt: startedAt,
    ),
    entries: [
      FoodEntryRecord(
        id: 'entry-$id',
        mealId: id,
        kind: FoodEntryKind.quickEntry,
        position: 0,
        name: entryName,
        nutrients: NutrientVector.energyAndMacros(
          energy: NutrientAmount.complete(
            value: 100,
            entered: '100',
            unit: NutrientUnit.kilocalorie,
          ),
          protein: NutrientAmount.complete(
            value: 1,
            entered: '1',
            unit: NutrientUnit.gram,
          ),
          carbohydrate: NutrientAmount.complete(
            value: 20,
            entered: '20',
            unit: NutrientUnit.gram,
          ),
          fat: NutrientAmount.complete(
            value: 2,
            entered: '2',
            unit: NutrientUnit.gram,
          ),
        ),
        updatedAt: startedAt,
      ),
    ],
  );
}

NutritionDayRecord _nutritionDayWithImportedEntry() {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);

  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-breakfast',
          mealType: 'Breakfast',
          startedAt: DateTime(2026, 6, 26, 8),
          timezone: 'Australia/Brisbane',
          localDate: localDate,
          updatedAt: DateTime.utc(2026, 6, 26, 8),
        ),
        entries: [
          FoodEntryRecord(
            id: 'entry-imported',
            mealId: 'meal-breakfast',
            kind: FoodEntryKind.food,
            position: 0,
            name: 'Imported oats',
            nutrients: NutrientVector.energyAndMacros(
              energy: NutrientAmount.complete(
                value: 150,
                entered: '150',
                unit: NutrientUnit.kilocalorie,
              ),
              protein: NutrientAmount.complete(
                value: 5,
                entered: '5',
                unit: NutrientUnit.gram,
              ),
              carbohydrate: NutrientAmount.complete(
                value: 27,
                entered: '27',
                unit: NutrientUnit.gram,
              ),
              fat: NutrientAmount.complete(
                value: 3,
                entered: '3',
                unit: NutrientUnit.gram,
              ),
            ),
            portion: Portion(
              value: 40,
              entered: '40',
              unit: PortionUnit.gram,
            ),
            // Generic Imported origin with the exact provider string preserved.
            foodSource: FoodSource.imported,
            isLiquid: false,
            importSource: 'acme-diet-tracker',
            importExternalId: 'row-1',
            importProvider: 'Acme Diet Tracker',
            reviewFlags: const <NutritionReviewFlag>[
              NutritionReviewFlag(
                rule: 'portionImprobable',
                message: 'Portion is unusually large.',
              ),
            ],
            updatedAt: DateTime.utc(2026, 6, 26, 8),
          ),
        ],
      ),
    ],
  );
}

NutritionDayRecord _nutritionDayWithOpenFoodFactsEntry() {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
  final imported = _nutritionDayWithImportedEntry().meals.single;
  final template = imported.entries.single;
  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      NutritionDayMealRecord(
        meal: imported.meal,
        entries: [
          FoodEntryRecord(
            id: 'entry-off',
            mealId: 'meal-breakfast',
            kind: FoodEntryKind.food,
            position: 0,
            name: 'Weet-Bix',
            nutrients: template.nutrients,
            portion: template.portion,
            foodId: '9300652010411',
            foodSource: FoodSource.openFoodFacts,
            isLiquid: false,
            updatedAt: DateTime.utc(2026, 6, 26, 8),
          ),
        ],
      ),
    ],
  );
}

List<MealTypeRecord> _mealTypes() {
  return <MealTypeRecord>[
    MealTypeRecord(
      id: 'meal-type-breakfast',
      name: 'Breakfast',
      sortOrder: 0,
      updatedAt: DateTime.utc(2026, 6, 26),
    ),
    MealTypeRecord(
      id: 'meal-type-lunch',
      name: 'Lunch',
      sortOrder: 1,
      updatedAt: DateTime.utc(2026, 6, 26),
    ),
    MealTypeRecord(
      id: 'meal-type-dinner',
      name: 'Dinner',
      sortOrder: 2,
      updatedAt: DateTime.utc(2026, 6, 26),
    ),
    MealTypeRecord(
      id: 'meal-type-snack',
      name: 'Snack',
      sortOrder: 3,
      updatedAt: DateTime.utc(2026, 6, 26),
    ),
  ];
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Could not find $finder.');
}

/// Disposes the ProviderScope inside the test body, so the database streams'
/// closing timers run before the binding checks for pending timers.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

class _FixedNutritionDay extends SelectedNutritionDayController {
  _FixedNutritionDay(this.day);

  final NutritionDayDate day;

  @override
  NutritionDayDate build() => day;
}

class _NoFoodsRepository with NoOnlineLookups implements AddFoodRepository {
  const _NoFoodsRepository();

  @override
  Future<YourFoods> loadYourFoods({DateTime? now}) async => YourFoods.empty;

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    required YourFoods yourFoods,
  }) async {
    return const <FoodPickerItem>[];
  }
}

/// A Lunch at 12:00 at +10:00 with one entry, a `date` Breakfast and an
/// empty 15:30 Snack, in the order the assembly gives.
NutritionDayRecord _nutritionDayWithHeaderForms() {
  const localDate = NutritionDayDate(year: 2026, month: 6, day: 26);
  final updatedAt = DateTime.utc(2026, 6, 26);
  final snack = _snackMeal(
    id: 'meal-empty',
    startedAt: DateTime(2026, 6, 26, 15, 30),
    entryName: 'unused',
  ).meal;
  return NutritionDayRecord(
    localDate: localDate,
    meals: [
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-imported',
          mealType: 'Breakfast',
          startedAt: DateTime.utc(2026, 6, 26),
          timezone: 'UTC',
          timezoneOffsetMinutes: 0,
          timePrecision: MealTimePrecision.date,
          localDate: localDate,
          updatedAt: updatedAt,
        ),
        entries: [
          _snackMeal(
            id: 'meal-imported',
            startedAt: DateTime(2026, 6, 26),
            entryName: 'Imported oats',
          ).entries.single,
        ],
      ),
      NutritionDayMealRecord(
        meal: MealRecord(
          id: 'meal-lunch',
          mealType: 'Lunch',
          startedAt: DateTime.utc(2026, 6, 26, 2),
          timezone: 'Australia/Brisbane',
          timezoneOffsetMinutes: 600,
          localDate: localDate,
          updatedAt: updatedAt,
        ),
        entries: [
          _snackMeal(
            id: 'meal-lunch',
            startedAt: DateTime(2026, 6, 26, 12),
            entryName: 'Rice',
          ).entries.single,
        ],
      ),
      NutritionDayMealRecord(meal: snack, entries: const <FoodEntryRecord>[]),
    ],
  );
}
