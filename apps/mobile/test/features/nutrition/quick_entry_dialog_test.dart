import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/nutrition/widgets/quick_entry_dialog.dart';
import 'package:perennia/theme/theme.dart';

void main() {
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
                      builder: (context) => const QuickEntryDialog(
                        mealType: 'Snack',
                      ),
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
