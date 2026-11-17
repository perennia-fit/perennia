import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/nutrition/widgets/quick_entry_dialog.dart';
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

  testWidgets('is titled Quick add and returns the draft without writing',
      (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    QuickFoodEntryDraft? returned;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return FilledButton(
                  onPressed: () async {
                    returned = await showDialog<QuickFoodEntryDraft>(
                      context: context,
                      builder: (context) => const QuickEntryDialog(),
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Quick add'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(QuickEntryDialog.nameFieldKey),
      'Cafe latte',
    );
    await tester.enterText(find.byKey(QuickEntryDialog.energyFieldKey), '140');
    await tester.tap(find.byKey(QuickEntryDialog.saveButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(QuickEntryDialog), findsNothing);
    expect(returned?.name, 'Cafe latte');
    expect(returned?.nutrients[NutrientId.energy].value, 140);
    expect(returned?.nutrients[NutrientId.energy].entered, '140');
    // The dialog only returns the entered values: nothing is written.
    expect(await database.select(database.meals).get(), isEmpty);
    expect(await database.select(database.foodEntries).get(), isEmpty);
    expect(await repositories.activityLog.listEntries(), isEmpty);
  });

  testWidgets(
      'Quick Entry dialog meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return FilledButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => const QuickEntryDialog(),
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(QuickEntryDialog.nameFieldKey), findsOneWidget);
      expect(find.byKey(QuickEntryDialog.energyFieldKey), findsOneWidget);
      expect(find.byKey(QuickEntryDialog.saveButtonKey), findsOneWidget);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
