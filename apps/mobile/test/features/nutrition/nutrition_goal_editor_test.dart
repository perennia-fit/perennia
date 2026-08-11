import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/controllers/nutrition_day_controller.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_day_view.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  testWidgets('shows only energy + 3-macro goal fields (no deferred forms)',
      (tester) async {
    final controller = _FakeGoalController();

    await _pumpEditor(tester, controller: controller, goals: const []);

    for (final id in goalableNutrientIds) {
      expect(find.byKey(NutritionDayView.goalFieldKey(id)), findsOneWidget);
    }
    // Deferred: no per-weekday, distribution percent, or micronutrient fields.
    expect(
      find.byKey(NutritionDayView.goalFieldKey(NutrientId.sodium)),
      findsNothing,
    );
    expect(
      find.byKey(NutritionDayView.goalFieldKey(NutrientId.fiber)),
      findsNothing,
    );
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('weekday'), findsNothing);

    // Field labels carry the nutrient unit.
    expect(find.textContaining('Calories target (kcal)'), findsOneWidget);
    expect(find.textContaining('Protein target (g)'), findsOneWidget);
    expect(find.textContaining('Carbs target (g)'), findsOneWidget);
    expect(find.textContaining('Fat target (g)'), findsOneWidget);
  });

  testWidgets('prefills existing targets and saves edited energy + macros',
      (tester) async {
    final controller = _FakeGoalController();

    await _pumpEditor(
      tester,
      controller: controller,
      goals: <NutritionGoalRecord>[
        _goal(NutrientId.energy, 2400, '2400'),
        _goal(NutrientId.protein, 180, '180'),
      ],
    );

    final energyField = find.byKey(NutritionDayView.goalFieldKey(
      NutrientId.energy,
    ));
    expect(
      tester.widget<TextField>(energyField).controller!.text,
      '2400',
    );

    await tester.enterText(energyField, '2200');
    await tester.enterText(
      find.byKey(NutritionDayView.goalFieldKey(NutrientId.carbohydrate)),
      '250',
    );
    await tester.tap(find.byKey(NutritionDayView.saveGoalsButtonKey));
    await tester.pump();

    expect(controller.savedTargets, hasLength(3));
    final saved = <NutrientId, double>{
      for (final target in controller.savedTargets) target.nutrient: target.value,
    };
    expect(saved[NutrientId.energy], 2200);
    expect(saved[NutrientId.protein], 180);
    expect(saved[NutrientId.carbohydrate], 250);
    // Fat is left blank, so it is cleared rather than saved.
    expect(saved.containsKey(NutrientId.fat), isFalse);
    expect(controller.clearedNutrients, contains(NutrientId.fat));
  });

  testWidgets('hard-rejects an impossible target inline via the shared validator',
      (tester) async {
    final controller = _FakeGoalController();

    await _pumpEditor(tester, controller: controller, goals: const []);

    await tester.enterText(
      find.byKey(NutritionDayView.goalFieldKey(NutrientId.energy)),
      '10001',
    );
    await tester.tap(find.byKey(NutritionDayView.saveGoalsButtonKey));
    await tester.pump();

    expect(
      find.textContaining('Energy must be no more than 10000 kcal'),
      findsOneWidget,
    );
    // Nothing was saved because validation rejected the target.
    expect(controller.savedTargets, isEmpty);
  });

  testWidgets('Nutrition Goal editor meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final controller = _FakeGoalController();

      await _pumpEditor(
        tester,
        controller: controller,
        goals: <NutritionGoalRecord>[_goal(NutrientId.energy, 2400, '2400')],
        theme: theme,
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required _FakeGoalController controller,
  required List<NutritionGoalRecord> goals,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nutritionDayControllerProvider.overrideWith(() => controller),
        nutritionGoalListProvider.overrideWith(
          (ref) => Stream<List<NutritionGoalRecord>>.value(goals),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const _GoalEditorHost(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(NutritionDayView.editGoalsButtonKey));
  await tester.pumpAndSettle();
}

/// A tiny host that surfaces the goal editor exactly as the nutrition surface
/// does — from a secondary "Nutrition Goals" button, not primary navigation.
class _GoalEditorHost extends ConsumerWidget {
  const _GoalEditorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton.icon(
          key: NutritionDayView.editGoalsButtonKey,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const NutritionGoalEditorScreen(),
            ),
          ),
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Nutrition Goals'),
        ),
      ),
    );
  }
}

NutritionGoalRecord _goal(NutrientId nutrient, double value, String entered) {
  return NutritionGoalRecord(
    id: 'goal-${nutrient.name}',
    target: NutritionGoalTarget(
      nutrient: nutrient,
      value: value,
      entered: entered,
    ),
    updatedAt: DateTime.utc(2026, 6, 26),
  );
}

class _FakeGoalController extends NutritionDayController {
  final savedTargets = <NutritionGoalTarget>[];
  final clearedNutrients = <NutrientId>[];

  @override
  Stream<NutritionDayState> build() {
    return Stream<NutritionDayState>.value(
      NutritionDayState(day: _emptyDay()),
    );
  }

  @override
  Future<String> saveNutritionGoal(NutritionGoalTarget target) async {
    savedTargets.add(target);
    return 'goal-${target.nutrient.name}';
  }

  @override
  Future<void> clearNutritionGoal(NutrientId nutrient) async {
    clearedNutrients.add(nutrient);
  }
}

NutritionDayRecord _emptyDay() {
  return NutritionDayRecord(
    localDate: NutritionDayDate(year: 2026, month: 6, day: 26),
    meals: const <NutritionDayMealRecord>[],
  );
}
