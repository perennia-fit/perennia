import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_attribution.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  Widget host(Widget child, ThemeData theme) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('a recognised provider badge shows the registry label', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const FoodSourceBadge(source: FoodSource.cronometer),
        AppTheme.light(),
      ),
    );

    expect(find.text('Cronometer'), findsOneWidget);
  });

  for (final (source, label) in <(FoodSource, String)>[
    (FoodSource.myFitnessPal, 'MyFitnessPal'),
    (FoodSource.yazio, 'Yazio'),
    (FoodSource.lifesum, 'Lifesum'),
  ]) {
    testWidgets('the $label badge shows its registry label', (tester) async {
      await tester.pumpWidget(
        host(FoodSourceBadge(source: source), AppTheme.light()),
      );
      expect(find.text(label), findsOneWidget);
    });
  }

  testWidgets('a generic Imported badge surfaces the preserved provider string',
      (tester) async {
    await tester.pumpWidget(
      host(
        const FoodSourceBadge(
          source: FoodSource.imported,
          providerLabel: 'Acme Diet Tracker',
        ),
        AppTheme.light(),
      ),
    );

    // The exact provider string is visible, not just the generic "Imported".
    expect(find.textContaining('Acme Diet Tracker'), findsOneWidget);
  });

  testWidgets('an Imported badge without a preserved string falls back to '
      '"Imported"', (tester) async {
    await tester.pumpWidget(
      host(
        const FoodSourceBadge(source: FoodSource.imported),
        AppTheme.light(),
      ),
    );

    expect(find.text('Imported'), findsOneWidget);
  });

  group('accessibility', () {
    for (final theme in <(String, ThemeData)>[
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('FoodSourceBadge meets a11y guidelines (${theme.$1})', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            const FoodSourceBadge(
              source: FoodSource.imported,
              providerLabel: 'Acme Diet Tracker',
            ),
            theme.$2,
          ),
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));

        handle.dispose();
      });
    }
  });
}
