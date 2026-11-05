import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/open_food_facts_repository.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/nutrition/controllers/meal_screen_controller.dart';
import 'package:perennia/features/nutrition/repositories/add_food_repository.dart';
import 'package:perennia/features/nutrition/widgets/add_food_picker.dart';
import 'package:perennia/features/nutrition/widgets/log_portion_screen.dart';
import 'package:perennia/features/nutrition/widgets/meal_screen.dart';
import 'package:perennia/features/nutrition/widgets/meal_time_sheet.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

import 'add_food_repository_fakes.dart';

/// The Meal screen over a real in-memory database
/// (docs/designs/meal-logging.md §6, CUJs 1-5, 9 and 10).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  const today = NutritionDayDate(year: 2026, month: 6, day: 26);
  const yesterday = NutritionDayDate(year: 2026, month: 6, day: 25);

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

  /// Opens [screen] from a home route, so a pop or a replacement shows.
  Future<void> open(
    WidgetTester tester,
    Widget screen, {
    DateTime? now,
    ThemeData? theme,
    bool alwaysUse24HourFormat = false,
    double textScale = 1,
    List<FoodPickerItem> yourFoods = const <FoodPickerItem>[],
  }) async {
    final clock = now ?? DateTime(2026, 6, 26, 12, 40);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
          mealScreenClockProvider.overrideWith((ref) => () => clock),
          addFoodRepositoryProvider.overrideWith(
            (ref) => _YourFoodsRepository(yourFoods),
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
          theme: theme ?? AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                alwaysUse24HourFormat: alwaysUse24HourFormat,
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            );
          },
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: _openKey,
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => screen),
                    );
                  },
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(_openKey));
    await tester.pumpAndSettle();
  }

  /// A Meal on [startedAt] with [mealType], and the given entries.
  Future<String> seedMeal(
    DateTime startedAt,
    String mealType, {
    List<FoodPickerItem> foods = const <FoodPickerItem>[],
  }) async {
    final mealId = await repositories.nutrition.createMeal(
      PendingMeal(
        id: repositories.nutrition.newMealId(),
        startedAt: startedAt,
        mealTypeName: mealType,
      ),
    );
    for (final food in foods) {
      await repositories.nutrition.logFoodEntrySnapshot(
        target: ExistingMealTarget(mealId),
        entry: _draft(mealId, food),
      );
    }
    return mealId;
  }

  /// Yesterday's lunch of chicken and rice: one Your meals row.
  Future<String> seedHistory() {
    return seedMeal(
      DateTime(2026, 6, 25, 12, 30),
      'Lunch',
      foods: <FoodPickerItem>[
        _food('usda-rice', 'Rice'),
        _food('usda-chicken', 'Chicken')
      ],
    );
  }

  /// A Lunch at 12:30 today with a Food-backed entry (Rice), an imported
  /// entry and a Quick Entry (CUJ 10).
  Future<
      ({
        String mealId,
        FoodEntryRecord food,
        FoodEntryRecord imported,
        FoodEntryRecord quick,
      })> seedLunch() async {
    final mealId = await seedMeal(
      DateTime(2026, 6, 26, 12, 30),
      'Lunch',
      foods: <FoodPickerItem>[_food('usda-rice', 'Rice')],
    );
    await repositories.nutrition.logFoodEntrySnapshot(
      target: ExistingMealTarget(mealId),
      entry: FoodEntrySnapshotDraft(
        mealId: mealId,
        foodId: null,
        name: 'Imported chicken',
        foodSource: FoodSource.imported,
        nutrientsPer100: _energy(200),
        isLiquid: false,
        portion: Portion(value: 100, entered: '100', unit: PortionUnit.gram),
        importSource: 'acme-diet-tracker',
        importExternalId: 'row-1',
      ),
    );
    await repositories.nutrition.logQuickEntry(
      target: ExistingMealTarget(mealId),
      entry: QuickFoodEntryDraft(name: 'Dessert', nutrients: _energy(300)),
    );
    final entries =
        await repositories.nutrition.listActiveEntriesForMeal(mealId);
    return (
      mealId: mealId,
      food: entries.singleWhere((entry) => entry.name == 'Rice'),
      imported: entries.singleWhere((entry) => entry.isImported),
      quick: entries.singleWhere(
        (entry) => entry.kind == FoodEntryKind.quickEntry,
      ),
    );
  }

  String headerText(WidgetTester tester) {
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(MealScreen.headerKey),
        matching: find.byType(Text),
      ),
    );
    return text.data!;
  }

  bool addFoodsLaterEnabled(WidgetTester tester) {
    return tester
            .widget<FilledButton>(find.byKey(MealScreen.addFoodsLaterKey))
            .onPressed !=
        null;
  }

  bool pickingIgnored(WidgetTester tester) {
    return tester
        .widget<IgnorePointer>(
          find
              .ancestor(
                of: find.byType(AddFoodPicker),
                matching: find.byType(IgnorePointer),
              )
              .first,
        )
        .ignoring;
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(MealScreen.headerKey));
    await tester.pumpAndSettle();
    expect(find.byType(MealTimeSheet), findsOneWidget);
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(MealTimeSheet), findsNothing);
  }

  /// Picks [hour]:[minute] in the time picker's text input (24-hour).
  Future<void> pickTime(
    WidgetTester tester,
    int hour,
    int minute,
  ) async {
    await tester.tap(find.byKey(MealTimeSheet.timeRowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '$hour');
    await tester.enterText(fields.at(1), minute.toString().padLeft(2, '0'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<List<ActivityLogEntry>> batch(String batchId) async {
    return (await repositories.activityLog.listEntries())
        .where((entry) => entry.batchId == batchId)
        .toList(growable: false);
  }

  group('the §6 states', () {
    testWidgets(
        'new, today: now and the proposed type, Your meals, and Add foods '
        'later enabled', (tester) async {
      final sourceId = await seedHistory();
      final semantics = tester.ensureSemantics();

      await open(tester, const MealScreen.newMeal(day: today));

      expect(headerText(tester), 'now · Lunch');
      expect(
        find.bySemanticsLabel('now, Lunch. Change time or meal type'),
        findsOneWidget,
      );
      expect(find.byType(MealTimeSheet), findsNothing);
      expect(find.byKey(MealScreen.yourMealsSectionKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(MealScreen.yourMealRowKey(sourceId)),
          matching: find.text('Chicken, Rice'),
        ),
        findsOneWidget,
      );
      expect(find.byType(AddFoodPicker), findsOneWidget);
      expect(pickingIgnored(tester), isFalse);
      expect(addFoodsLaterEnabled(tester), isTrue);
      expect(find.byKey(MealScreen.overflowMenuKey), findsNothing);
      expect(find.byKey(MealScreen.recentShortcutKey), findsNothing);
      expect(
        await database.select(database.meals).get(),
        hasLength(1),
        reason: 'opening the screen writes nothing',
      );

      semantics.dispose();
      await _unmount(tester);
    });

    testWidgets(
        'new, past day: the time sheet opens, the header stays at Choose time '
        'and picking waits for a time', (tester) async {
      final sourceId = await seedHistory();

      await open(
        tester,
        const MealScreen.newMeal(day: yesterday),
        alwaysUse24HourFormat: true,
      );

      expect(find.byType(MealTimeSheet), findsOneWidget);
      expect(headerText(tester), 'Choose time');
      expect(addFoodsLaterEnabled(tester), isFalse);
      expect(pickingIgnored(tester), isTrue);
      expect(
        tester
            .widget<ListTile>(
              find.descendant(
                of: find.byKey(MealScreen.yourMealRowKey(sourceId)),
                matching: find.byType(ListTile),
              ),
            )
            .enabled,
        isFalse,
      );
      expect(find.byKey(MealTimeSheet.shiftButtonKey(15)), findsNothing);
      expect(find.byKey(MealTimeSheet.shiftButtonKey(30)), findsNothing);
      expect(find.byKey(MealTimeSheet.shiftButtonKey(60)), findsNothing);
      expect(find.byKey(MealTimeSheet.dateHeaderKey), findsNothing);

      // A date alone moves the day but chooses no time.
      await tester.tap(find.byKey(MealTimeSheet.dateRowKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('24'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.byKey(MealTimeSheet.dateHeaderKey), findsOneWidget);
      expect(headerText(tester), 'Choose time');
      expect(addFoodsLaterEnabled(tester), isFalse);
      expect(pickingIgnored(tester), isTrue);
      expect(await database.select(database.meals).get(), hasLength(1));

      await pickTime(tester, 7, 30);

      expect(headerText(tester), '07:30 · Breakfast');
      expect(addFoodsLaterEnabled(tester), isTrue);
      expect(pickingIgnored(tester), isFalse);

      await closeSheet(tester);
      await tester.tap(find.byKey(MealScreen.addFoodsLaterKey));
      await tester.pumpAndSettle();

      final meals = await database.select(database.meals).get();
      final created = meals.singleWhere((meal) => meal.id != sourceId);
      expect(created.localDate, '2026-06-24');
      expect(created.startedAt.toUtc(), DateTime(2026, 6, 24, 7, 30).toUtc());
      expect(created.mealType, 'Breakfast');
      expect(headerText(tester), '07:30 · Breakfast · add foods');
      expect(find.byKey(MealScreen.addFoodsLaterKey), findsNothing);

      await _unmount(tester);
    });

    testWidgets(
        'saved, with entries: the Meal\'s time and type, its entries, and '
        'Delete meal; no Your meals', (tester) async {
      await seedHistory();
      final mealId = await seedMeal(
        DateTime(2026, 6, 26, 12, 30),
        'Lunch',
        foods: <FoodPickerItem>[_food('usda-yogurt', 'Greek yogurt')],
      );
      final entry =
          (await repositories.nutrition.listActiveEntriesForMeal(mealId))
              .single;

      await open(tester, MealScreen.existing(mealId: mealId));

      expect(headerText(tester), '12:30 PM · Lunch');
      expect(find.byKey(MealScreen.entryRowKey(entry.id)), findsOneWidget);
      expect(find.byKey(MealScreen.removeEntryKey(entry.id)), findsOneWidget);
      expect(find.byKey(MealScreen.yourMealsSectionKey), findsNothing);
      expect(find.byKey(MealScreen.overflowMenuKey), findsOneWidget);
      expect(find.byKey(MealScreen.addFoodsLaterKey), findsNothing);
      expect(find.byType(MealTimeSheet), findsNothing);

      await _unmount(tester);
    });

    testWidgets('saved, no entries: add foods, Your meals, Delete meal', (
      tester,
    ) async {
      final sourceId = await seedHistory();
      final mealId = await seedMeal(DateTime(2026, 6, 26, 13, 10), 'Lunch');

      await open(tester, MealScreen.existing(mealId: mealId));

      expect(headerText(tester), '1:10 PM · Lunch · add foods');
      expect(find.byKey(MealScreen.yourMealRowKey(sourceId)), findsOneWidget);
      expect(find.byKey(MealScreen.overflowMenuKey), findsOneWidget);
      expect(find.byKey(MealScreen.addFoodsLaterKey), findsNothing);

      await _unmount(tester);
    });

    testWidgets('a saved date Meal reads time not recorded, never 00:00', (
      tester,
    ) async {
      final mealId = await seedMeal(DateTime(2026, 6, 26), 'Lunch');
      await (database.update(database.meals)
            ..where((row) => row.id.equals(mealId)))
          .write(
        MealsCompanion(
          timePrecision: Value<String>(MealTimePrecision.date.name),
        ),
      );

      await open(tester, MealScreen.existing(mealId: mealId));

      expect(headerText(tester), 'time not recorded · Lunch · add foods');
      expect(find.textContaining('12:00 AM'), findsNothing);

      await _unmount(tester);
    });
  });

  group('the time sheet', () {
    testWidgets('the time-shift buttons replace rather than stack', (
      tester,
    ) async {
      await open(tester, const MealScreen.newMeal(day: today));
      await openSheet(tester);

      expect(find.bySemanticsLabel('15 minutes ago'), findsOneWidget);
      expect(find.bySemanticsLabel('30 minutes ago'), findsOneWidget);
      expect(find.bySemanticsLabel('1 hour ago'), findsOneWidget);

      await tester.tap(find.byKey(MealTimeSheet.shiftButtonKey(15)));
      await tester.pumpAndSettle();
      expect(headerText(tester), '12:25 PM · Lunch');

      await tester.tap(find.byKey(MealTimeSheet.shiftButtonKey(30)));
      await tester.pumpAndSettle();
      expect(headerText(tester), '12:10 PM · Lunch');

      await tester.tap(find.byKey(MealTimeSheet.shiftButtonKey(60)));
      await tester.pumpAndSettle();
      expect(headerText(tester), '11:40 AM · Lunch');
      expect(
        await database.select(database.meals).get(),
        isEmpty,
        reason: 'a new Meal\'s choices stay on screen until the first write',
      );

      await _unmount(tester);
    });

    testWidgets('a shift across midnight moves the new Meal to the day before',
        (tester) async {
      await open(
        tester,
        const MealScreen.newMeal(day: today),
        now: DateTime(2026, 6, 26, 0, 10),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(MealTimeSheet.shiftButtonKey(15)));
      await tester.pumpAndSettle();

      expect(headerText(tester), '11:55 PM · Snack');
      expect(find.byKey(MealTimeSheet.dateHeaderKey), findsOneWidget);
      expect(
        find.byKey(MealTimeSheet.shiftButtonKey(15)),
        findsNothing,
        reason: 'the shift buttons show only while the Meal is on today',
      );

      await closeSheet(tester);
      await tester.tap(find.byKey(MealScreen.addFoodsLaterKey));
      await tester.pumpAndSettle();

      final meal = (await database.select(database.meals).get()).single;
      expect(meal.localDate, '2026-06-25');
      expect(meal.startedAt.toUtc(), DateTime(2026, 6, 25, 23, 55).toUtc());

      await _unmount(tester);
    });

    testWidgets(
        'the future-time confirmation shows exactly when validateMealTime '
        'warns, and Cancel applies nothing', (tester) async {
      final now = DateTime(2026, 6, 26, 12, 40);
      bool warns(DateTime start) {
        return validateMealTime(
          MealTimeInput(startedAt: start, mealType: 'Lunch'),
          now: now,
        ).warnings.isNotEmpty;
      }

      expect(warns(DateTime(2026, 6, 26, 12, 45)), isFalse);
      expect(warns(DateTime(2026, 6, 26, 12, 46)), isTrue);

      await open(
        tester,
        const MealScreen.newMeal(day: today),
        now: now,
        alwaysUse24HourFormat: true,
      );
      await openSheet(tester);

      await pickTime(tester, 12, 46);
      expect(find.text('Time is in the future'), findsOneWidget);
      expect(find.text('Save 12:46 anyway?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(headerText(tester), 'now · Lunch');

      await pickTime(tester, 12, 45);
      expect(find.text('Time is in the future'), findsNothing);
      expect(headerText(tester), '12:45 · Lunch');

      await pickTime(tester, 12, 50);
      expect(find.text('Time is in the future'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(headerText(tester), '12:50 · Lunch');

      await _unmount(tester);
    });

    testWidgets(
        'on a saved Meal, a type choice and a time choice are one write each',
        (tester) async {
      final mealId = await seedMeal(DateTime(2026, 6, 26, 12, 30), 'Lunch');
      final before = await repositories.activityLog.listEntries();

      await open(
        tester,
        MealScreen.existing(mealId: mealId),
        alwaysUse24HourFormat: true,
      );
      await openSheet(tester);

      await tester.tap(find.byKey(MealTimeSheet.mealTypeKey('Snack')));
      await tester.pumpAndSettle();
      await pickTime(tester, 11, 15);

      expect(headerText(tester), '11:15 · Snack · add foods');
      final meal = (await repositories.nutrition.getMealById(mealId))!;
      expect(meal.mealType, 'Snack');
      expect(meal.startedAt, DateTime(2026, 6, 26, 11, 15).toUtc());
      final after = await repositories.activityLog.listEntries();
      final newBatches = after
          .where((entry) => !before.any((old) => old.id == entry.id))
          .map((entry) => entry.batchId)
          .toSet();
      expect(newBatches, hasLength(2));

      await _unmount(tester);
    });
  });

  group('logging', () {
    testWidgets(
        'a Your meals row logs the Meal with an announced Undo bar, and Undo '
        'returns the screen to a new Meal', (tester) async {
      final sourceId = await seedHistory();
      final semantics = tester.ensureSemantics();

      await open(tester, const MealScreen.newMeal(day: today));
      await tester.tap(find.byKey(MealScreen.yourMealRowKey(sourceId)));
      await tester.pumpAndSettle();

      expect(find.text('Meal logged'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Meal logged')),
        isSemantics(isLiveRegion: true),
      );
      final created = (await database.select(database.meals).get())
          .singleWhere((meal) => meal.id != sourceId);
      final entries =
          await repositories.nutrition.listActiveEntriesForMeal(created.id);
      expect(entries, hasLength(2));
      for (final entry in entries) {
        expect(find.byKey(MealScreen.entryRowKey(entry.id)), findsOneWidget);
      }
      expect(find.byKey(MealScreen.yourMealsSectionKey), findsNothing);
      expect(find.byKey(MealScreen.addFoodsLaterKey), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(headerText(tester), 'now · Lunch');
      expect(find.byKey(MealScreen.addFoodsLaterKey), findsOneWidget);
      expect(find.byKey(MealScreen.yourMealsSectionKey), findsOneWidget);
      final undone = (await repositories.nutrition.getMealById(created.id))!;
      expect(undone.deletedAt, isNotNull);
      expect(
        await repositories.nutrition.listActiveEntriesForMeal(created.id),
        isEmpty,
      );

      semantics.dispose();
      await _unmount(tester);
    });

    testWidgets(
        'a refused undo shows the dependent message when foods were added '
        'afterwards', (tester) async {
      final sourceId = await seedHistory();

      await open(tester, const MealScreen.newMeal(day: today));
      await tester.tap(find.byKey(MealScreen.yourMealRowKey(sourceId)));
      await tester.pumpAndSettle();
      final created = (await database.select(database.meals).get())
          .singleWhere((meal) => meal.id != sourceId);
      await repositories.nutrition.logQuickEntry(
        target: ExistingMealTarget(created.id),
        entry: QuickFoodEntryDraft(name: 'Dessert', nutrients: _energy(300)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(
        find.text("Can't undo: foods were added to this meal afterwards."),
        findsOneWidget,
      );
      expect(
        (await repositories.nutrition.getMealById(created.id))!.deletedAt,
        isNull,
      );

      await _unmount(tester);
    });

    testWidgets(
        'picking a food opens Log Portion, and its Save writes the Meal and '
        'shows it saved', (tester) async {
      final yogurt = _food('usda-yogurt', 'Greek yogurt');

      await open(
        tester,
        const MealScreen.newMeal(day: today),
        yourFoods: <FoodPickerItem>[yogurt],
      );
      await tester.tap(find.byKey(AddFoodPicker.resultKey(yogurt)));
      await tester.pumpAndSettle();

      expect(find.byType(LogPortionScreen), findsOneWidget);
      expect(find.text('now · Lunch'), findsOneWidget);
      await tester.tap(find.byKey(LogPortionScreen.saveButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(LogPortionScreen), findsNothing);
      final meal = (await database.select(database.meals).get()).single;
      final entry =
          (await repositories.nutrition.listActiveEntriesForMeal(meal.id))
              .single;
      expect(find.byKey(MealScreen.entryRowKey(entry.id)), findsOneWidget);
      expect(find.byKey(MealScreen.addFoodsLaterKey), findsNothing);
      expect(find.byKey(MealScreen.overflowMenuKey), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('the recent-Meal shortcut replaces the screen with that Meal',
        (tester) async {
      final mealId = await seedMeal(DateTime(2026, 6, 26, 12, 20), 'Lunch');

      await open(tester, const MealScreen.newMeal(day: today));

      expect(find.text('Add to 12:20 PM · Lunch'), findsOneWidget);
      await tester.tap(find.byKey(MealScreen.recentShortcutKey));
      await tester.pumpAndSettle();

      expect(find.byType(MealScreen), findsOneWidget);
      expect(headerText(tester), '12:20 PM · Lunch · add foods');
      expect(find.byKey(MealScreen.recentShortcutKey), findsNothing);
      expect(find.byKey(MealScreen.addFoodsLaterKey), findsNothing);

      // The screen was replaced, not stacked: back returns home.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(MealScreen), findsNothing);
      expect(await database.select(database.meals).get(), hasLength(1));
      expect(mealId, isNotEmpty);

      await _unmount(tester);
    });
  });

  group('entries', () {
    testWidgets(
        'a Food-backed entry edits its Portion with Undo; imported entries '
        'and Quick Entries are remove-only', (tester) async {
      final (:mealId, :food, :imported, :quick) = await seedLunch();

      await open(tester, MealScreen.existing(mealId: mealId));

      await tester.tap(find.byKey(MealScreen.entryRowKey(imported.id)));
      await tester.pumpAndSettle();
      expect(find.byType(LogPortionScreen), findsNothing);
      await tester.tap(find.byKey(MealScreen.entryRowKey(quick.id)));
      await tester.pumpAndSettle();
      expect(find.byType(LogPortionScreen), findsNothing);
      for (final entry in <FoodEntryRecord>[food, imported, quick]) {
        expect(find.byKey(MealScreen.removeEntryKey(entry.id)), findsOneWidget);
      }

      await tester.tap(find.byKey(MealScreen.entryRowKey(food.id)));
      await tester.pumpAndSettle();
      expect(find.byType(LogPortionScreen), findsOneWidget);
      await tester.enterText(
        find.byKey(LogPortionScreen.amountFieldKey),
        '150',
      );
      await tester.pump();
      await tester.tap(find.byKey(LogPortionScreen.saveButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(LogPortionScreen), findsNothing);
      expect(find.text('Portion updated'), findsOneWidget);
      Future<double?> ricePortion() async {
        final entries =
            await repositories.nutrition.listActiveEntriesForMeal(mealId);
        return entries
            .singleWhere((entry) => entry.id == food.id)
            .portion
            ?.value;
      }

      expect(await ricePortion(), 150);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await ricePortion(), 100);

      await _unmount(tester);
    });

    testWidgets(
        'removing entries shows Food removed with Undo, and removing the last '
        'one keeps the Meal as add foods', (tester) async {
      final (:mealId, :food, :imported, :quick) = await seedLunch();
      await seedHistory();

      await open(tester, MealScreen.existing(mealId: mealId));

      await tester.tap(find.byKey(MealScreen.removeEntryKey(quick.id)));
      await tester.pumpAndSettle();
      expect(find.text('Food removed'), findsOneWidget);
      expect(find.byKey(MealScreen.entryRowKey(quick.id)), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.byKey(MealScreen.entryRowKey(quick.id)), findsOneWidget);

      for (final entry in <FoodEntryRecord>[quick, imported, food]) {
        await tester.tap(find.byKey(MealScreen.removeEntryKey(entry.id)));
        await tester.pumpAndSettle();
      }

      expect(headerText(tester), '12:30 PM · Lunch · add foods');
      expect(find.byKey(MealScreen.yourMealsSectionKey), findsOneWidget);
      final meal = (await repositories.nutrition.getMealById(mealId))!;
      expect(meal.deletedAt, isNull);
      expect(
        await repositories.nutrition.listActiveEntriesForMeal(mealId),
        isEmpty,
      );

      await _unmount(tester);
    });

    testWidgets(
        'Delete meal is in the overflow menu, confirms, archives the Meal and '
        'its entries in one Batch, and closes the screen', (tester) async {
      final (:mealId, food: _, imported: _, quick: _) = await seedLunch();
      final before = await repositories.activityLog.listEntries();

      await open(tester, MealScreen.existing(mealId: mealId));

      await tester.tap(find.byKey(MealScreen.overflowMenuKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MealScreen.deleteMealKey));
      await tester.pumpAndSettle();

      expect(find.text('Delete this meal?'), findsOneWidget);
      expect(
        find.text('The meal and its foods are removed from the day.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(MealScreen), findsOneWidget);
      expect((await repositories.nutrition.getMealById(mealId))!.deletedAt,
          isNull);

      await tester.tap(find.byKey(MealScreen.overflowMenuKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MealScreen.deleteMealKey));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(MealScreen), findsNothing);
      expect(
        (await repositories.nutrition.getMealById(mealId))!.deletedAt,
        isNotNull,
      );
      expect(
        await repositories.nutrition.listActiveEntriesForMeal(mealId),
        isEmpty,
      );
      final added = (await repositories.activityLog.listEntries())
          .where((entry) => !before.any((old) => old.id == entry.id))
          .toList();
      final batchIds = added.map((entry) => entry.batchId).toSet();
      expect(batchIds, hasLength(1));
      expect(await batch(batchIds.single), hasLength(4));

      await _unmount(tester);
    });
  });

  group('accessibility', () {
    for (final (name, theme) in <(String, ThemeData)>[
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('a new Meal meets the guidelines in the $name theme', (
        tester,
      ) async {
        await seedHistory();
        await seedMeal(DateTime(2026, 6, 26, 12, 20), 'Lunch');
        final semantics = tester.ensureSemantics();

        await open(tester, const MealScreen.newMeal(day: today), theme: theme);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        semantics.dispose();
        await _unmount(tester);
      });

      testWidgets(
          'a saved Meal and its time sheet meet the guidelines in the $name '
          'theme', (tester) async {
        final (:mealId, food: _, imported: _, quick: _) = await seedLunch();
        final semantics = tester.ensureSemantics();

        await open(tester, MealScreen.existing(mealId: mealId), theme: theme);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await openSheet(tester);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        semantics.dispose();
        await _unmount(tester);
      });
    }

    testWidgets(
        'at 200% text, the header and Add foods later are shown unclipped', (
      tester,
    ) async {
      await seedHistory();

      await open(
        tester,
        const MealScreen.newMeal(day: today),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      final screen = tester.getRect(find.byType(MealScreen));
      for (final key in <Key>[
        MealScreen.headerKey,
        MealScreen.addFoodsLaterKey,
      ]) {
        final finder = find.byKey(key);
        expect(finder, findsOneWidget);
        final rect = tester.getRect(finder);
        expect(screen.contains(rect.topLeft), isTrue);
        expect(screen.contains(rect.bottomRight - const Offset(1, 1)), isTrue);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: finder, matching: find.byType(RichText)).first,
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          paragraph.size.height,
          lessThanOrEqualTo(rect.height),
        );
      }
      expect(headerText(tester), 'now · Lunch');

      await _unmount(tester);
    });
  });
}

const _openKey = Key('test.openMealScreen');

/// Your foods holding [items], found by any query.
class _YourFoodsRepository with NoOnlineLookups implements AddFoodRepository {
  const _YourFoodsRepository(this.items);

  final List<FoodPickerItem> items;

  @override
  Future<YourFoods> loadYourFoods({DateTime? now}) async => YourFoods(items);

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    required YourFoods yourFoods,
  }) async {
    return yourFoods.items;
  }
}

/// Disposes the ProviderScope inside the test body, so the database streams'
/// closing timers run before the binding checks for pending timers.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

FoodPickerItem _food(String id, String name) {
  return FoodPickerItem(
    id: id,
    name: name,
    origin: FoodPickerOrigin.usda,
    foodSource: FoodSource.usda,
    nutrientsPer100: _energy(200),
    isLiquid: false,
  );
}

FoodEntrySnapshotDraft _draft(String mealId, FoodPickerItem food) {
  return FoodEntrySnapshotDraft(
    mealId: mealId,
    foodId: food.id,
    name: food.name,
    foodSource: food.foodSource,
    nutrientsPer100: food.nutrientsPer100,
    isLiquid: food.isLiquid,
    portion: Portion(value: 100, entered: '100', unit: PortionUnit.gram),
  );
}

NutrientVector _energy(double kilocalories) {
  NutrientAmount grams(double value) {
    return NutrientAmount.complete(
      value: value,
      entered: formatNutritionNumber(value),
      unit: NutrientUnit.gram,
    );
  }

  return NutrientVector.energyAndMacros(
    energy: NutrientAmount.complete(
      value: kilocalories,
      entered: formatNutritionNumber(kilocalories),
      unit: NutrientUnit.kilocalorie,
    ),
    protein: grams(10),
    carbohydrate: grams(20),
    fat: grams(5),
  );
}
