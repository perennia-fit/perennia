import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/nutrition/controllers/nutrition_import_controller.dart';
import 'package:perennia/features/nutrition/import/nutrition_import.dart';
import 'package:perennia/features/nutrition/import/nutrition_import_consent_repository.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_import_screen.dart';
import 'package:perennia/theme/theme.dart';

class _FakePicker implements NutritionImportFilePicker {
  _FakePicker(this.content);

  final String? content;

  @override
  Future<String?> pickTextFile() async => content;
}

class _ImmediateParser implements NutritionImportParser {
  const _ImmediateParser();

  @override
  Future<NutritionImportBatch> parse({
    required NutritionImportProvider provider,
    required String content,
  }) async {
    return provider.adapter.parse(content);
  }
}

class _DeferredParser implements NutritionImportParser {
  final completer = Completer<NutritionImportBatch>();
  var calls = 0;

  @override
  Future<NutritionImportBatch> parse({
    required NutritionImportProvider provider,
    required String content,
  }) {
    calls += 1;
    return completer.future;
  }
}

/// A fake controller for the a11y test so no live Drift `watch()` keeps a
/// pending timer (which would hang `meetsGuideline`'s semantics wait).
class _FakeImportController extends NutritionImportController {
  _FakeImportController(this._state);

  final NutritionImportUiState _state;

  @override
  Future<NutritionImportUiState> build() async => _state;
}

const _csv = '''
Day,Time,Group,Food Name,Amount,Energy (kcal),Protein (g),Carbs (g),Fat (g)
2026-06-01,08:00,Breakfast,Oats,100 g,389,16.9,66.3,6.9
''';

const _mfpCsv = '''
Date,Meal,Food,Calories,Carbohydrates (g),Protein (g),Fat (g)
2026-06-01,Breakfast,Oats,389,66.3,16.9,6.9
''';

/// Pumps a bounded number of frames; the consent StreamProvider (a Drift watch)
/// keeps emitting, so `pumpAndSettle` would never return — pump fixed frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Disposes the widget tree so the Drift `watch()` subscription is cancelled
/// before the in-memory database is closed (otherwise a pending Timer leaks and
/// the test framework asserts).
Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

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

  late AppDatabase database;

  setUp(() {
    database = AppDatabase.inMemory();
  });

  tearDown(() async {
    await database.close();
  });

  Widget wrap({
    String? pickerContent = _csv,
    NutritionImportParser parser = const _ImmediateParser(),
    ThemeData? theme,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        nutritionImportFilePickerProvider
            .overrideWithValue(_FakePicker(pickerContent)),
        nutritionImportParserProvider.overrideWithValue(parser),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const NutritionImportScreen(),
      ),
    );
  }

  bool importEnabled(WidgetTester tester) {
    final button = tester.widget<FilledButton>(
      find.byKey(NutritionImportScreen.importButtonKey),
    );
    return button.onPressed != null;
  }

  testWidgets('import button is disabled until consent is granted',
      (tester) async {
    await tester.pumpWidget(wrap());
    await _settle(tester);

    expect(importEnabled(tester), isFalse);

    await tester.tap(find.byKey(NutritionImportScreen.consentToggleKey));
    await _settle(tester);

    expect(importEnabled(tester), isTrue);
    await _disposeTree(tester);
  });

  testWidgets('import button is disabled while parsing is pending',
      (tester) async {
    final parser = _DeferredParser();
    await tester.pumpWidget(wrap(parser: parser));
    await _settle(tester);

    await tester.tap(find.byKey(NutritionImportScreen.consentToggleKey));
    await _settle(tester);
    expect(importEnabled(tester), isTrue);

    await tester.tap(find.byKey(NutritionImportScreen.importButtonKey));
    await tester.pump();

    expect(parser.calls, 1);
    expect(importEnabled(tester), isFalse);

    await tester.tap(
      find.byKey(NutritionImportScreen.importButtonKey),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(parser.calls, 1);

    parser.completer.complete(
      NutritionImportProvider.cronometer.adapter.parse(_csv),
    );
    await _settle(tester);

    expect(importEnabled(tester), isTrue);
    expect(find.textContaining('Imported 1'), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('importing a CSV lands entries and shows a done status',
      (tester) async {
    await tester.pumpWidget(wrap());
    await _settle(tester);

    await tester.tap(find.byKey(NutritionImportScreen.consentToggleKey));
    await _settle(tester);
    await tester.tap(find.byKey(NutritionImportScreen.importButtonKey));
    await _settle(tester);

    expect(find.byKey(NutritionImportScreen.statusKey), findsOneWidget);
    expect(find.textContaining('Imported 1'), findsOneWidget);

    final repositories = TrainingRepositories(database);
    final day = await repositories.nutrition.nutritionDay(
      const NutritionDayDate(year: 2026, month: 6, day: 1),
    );
    expect(day.meals.single.entries.single.foodSource, FoodSource.cronometer);
    await _disposeTree(tester);
  });

  testWidgets(
      'selecting MyFitnessPal routes through its adapter and stamps its '
      'Food Source', (tester) async {
    await tester.pumpWidget(wrap(pickerContent: _mfpCsv));
    await _settle(tester);

    // Choose the MyFitnessPal provider, then consent and import.
    await tester.tap(
      find.byKey(NutritionImportScreen.providerChoiceKeyFor(
        NutritionImportProvider.myFitnessPal,
      )),
    );
    await _settle(tester);
    expect(find.text('Choose a MyFitnessPal file'), findsOneWidget);

    await tester.tap(find.byKey(NutritionImportScreen.consentToggleKey));
    await _settle(tester);
    await tester.tap(find.byKey(NutritionImportScreen.importButtonKey));
    await _settle(tester);

    expect(find.textContaining('Imported 1'), findsOneWidget);
    final repositories = TrainingRepositories(database);
    final day = await repositories.nutrition.nutritionDay(
      const NutritionDayDate(year: 2026, month: 6, day: 1),
    );
    expect(
      day.meals.single.entries.single.foodSource,
      FoodSource.myFitnessPal,
    );
    await _disposeTree(tester);
  });

  testWidgets('an unrecognized file surfaces a non-blocking error status',
      (tester) async {
    await tester.pumpWidget(wrap(pickerContent: 'Foo,Bar\n1,2\n'));
    await _settle(tester);

    await tester.tap(find.byKey(NutritionImportScreen.consentToggleKey));
    await _settle(tester);
    await tester.tap(find.byKey(NutritionImportScreen.importButtonKey));
    await _settle(tester);

    expect(find.byKey(NutritionImportScreen.statusKey), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('meets accessibility guidelines in both themes', (tester) async {
    final doneState = NutritionImportUiState(
      phase: NutritionImportPhase.done,
      result: NutritionImportResult(
        batchId: 'batch',
        mealIds: <String>['meal'],
        foodEntryIds: <String>['entry'],
        importedCount: 1,
        updatedCount: 0,
        skippedTombstoned: 0,
        rejectedCount: 1,
        reviewFlagCount: 1,
      ),
    );

    Widget a11yWrap(ThemeData theme) {
      return ProviderScope(
        overrides: [
          // Static overrides: no live Drift stream/timer that would hang the
          // semantics wait.
          nutritionImportConsentProvider
              .overrideWith((ref) => Stream<bool>.value(true)),
          nutritionImportControllerProvider
              .overrideWith(() => _FakeImportController(doneState)),
        ],
        child: MaterialApp(
          theme: theme,
          home: const NutritionImportScreen(),
        ),
      );
    }

    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(a11yWrap(theme));
      await _settle(tester);

      // The done state renders the consent tile, the import button, and the
      // status banner — covering every interactive + text element.
      expect(find.byKey(NutritionImportScreen.statusKey), findsOneWidget);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
