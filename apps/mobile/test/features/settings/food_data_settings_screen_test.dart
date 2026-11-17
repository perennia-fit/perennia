import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/settings/widgets/food_data_settings_screen.dart';
import 'package:perennia/theme/theme.dart';

/// Settings → Food data: the device setting that lets the add-food picker
/// look foods up on Open Food Facts.
void main() {
  Future<void> pump(
    WidgetTester tester,
    SettingsRepository repository, {
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: const FoodDataSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SwitchListTile switchTile(WidgetTester tester) {
    return tester.widget<SwitchListTile>(
      find.byKey(FoodDataSettingsScreen.onlineFoodLookupsSwitchKey),
    );
  }

  testWidgets('the switch reads and writes onlineFoodLookups', (tester) async {
    final repository = InMemorySettingsRepository();
    await pump(tester, repository);

    expect(find.text('Look up foods online'), findsOneWidget);
    expect(
      find.text(
        'Sends your search text or barcode to Open Food Facts. The offline '
        'food list works without it.',
      ),
      findsOneWidget,
    );
    expect(switchTile(tester).value, isTrue, reason: 'on by default');

    await tester.tap(
      find.byKey(FoodDataSettingsScreen.onlineFoodLookupsSwitchKey),
    );
    await tester.pumpAndSettle();

    expect(switchTile(tester).value, isFalse);
    expect((await repository.load()).onlineFoodLookups, isFalse);
  });

  testWidgets('a saved off value is shown off', (tester) async {
    final repository = InMemorySettingsRepository(
      const AppSettings(onlineFoodLookups: false),
    );
    await pump(tester, repository);

    expect(switchTile(tester).value, isFalse);
  });

  testWidgets('meets accessibility guidelines in both themes', (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      await pump(tester, InMemorySettingsRepository(), theme: theme);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
