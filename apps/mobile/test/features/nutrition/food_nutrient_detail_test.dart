import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/widgets/food_nutrient_detail.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  testWidgets('tiers Food nutrients and renders unknown values as dash',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FoodNutrientDetail(
            foodName: 'Chicken breast',
            nutrientsPer100: _foodNutrients(),
          ),
        ),
      ),
    );

    expect(find.text('Chicken breast'), findsOneWidget);
    expect(_nutrientValueText(tester, NutrientId.energy), '165 kcal');
    expect(_nutrientValueText(tester, NutrientId.protein), '31 g');
    expect(_nutrientValueText(tester, NutrientId.carbohydrate), '0 g');
    expect(_nutrientValueText(tester, NutrientId.fat), '3.6 g');
    expect(_nutrientValueText(tester, NutrientId.fiber), '0 g');
    expect(_nutrientValueText(tester, NutrientId.sodium), '74 mg');
    expect(
      find.byKey(FoodNutrientDetail.nutrientValueKey(NutrientId.vitaminB6)),
      findsNothing,
    );

    await tester.tap(find.byKey(FoodNutrientDetail.detailExpansionKey));
    await tester.pumpAndSettle();

    expect(find.text('Vitamin B6'), findsOneWidget);
    expect(_nutrientValueText(tester, NutrientId.vitaminB6), '0.6 mg');
    expect(find.text('Caffeine'), findsOneWidget);
    expect(_nutrientValueText(tester, NutrientId.caffeine), _unknownLabel);
    expect(find.text('0 mg'), findsNothing);
  });

  testWidgets(
      'Food nutrient detail meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: FoodNutrientDetail(
              foodName: 'Chicken breast',
              nutrientsPer100: _foodNutrients(),
            ),
          ),
        ),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.byKey(FoodNutrientDetail.detailExpansionKey));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

const _unknownLabel = '\u2014';

String? _nutrientValueText(WidgetTester tester, NutrientId id) {
  return tester
      .widget<Text>(find.byKey(FoodNutrientDetail.nutrientValueKey(id)))
      .data;
}

NutrientVector _foodNutrients() {
  return NutrientVector.full(<NutrientId, NutrientAmount>{
    NutrientId.energy: _complete(
      NutrientId.energy,
      value: 165,
      entered: '165',
    ),
    NutrientId.protein: _complete(
      NutrientId.protein,
      value: 31.02,
      entered: '31.02',
    ),
    NutrientId.carbohydrate: _complete(
      NutrientId.carbohydrate,
      value: 0,
      entered: '0',
    ),
    NutrientId.fat: _complete(
      NutrientId.fat,
      value: 3.57,
      entered: '3.57',
    ),
    NutrientId.saturatedFat: _complete(
      NutrientId.saturatedFat,
      value: 1.01,
      entered: '1.01',
    ),
    NutrientId.sugar: _complete(
      NutrientId.sugar,
      value: 0,
      entered: '0',
    ),
    NutrientId.fiber: _complete(
      NutrientId.fiber,
      value: 0,
      entered: '0',
    ),
    NutrientId.sodium: _complete(
      NutrientId.sodium,
      value: 74,
      entered: '74',
    ),
    NutrientId.vitaminB6: _complete(
      NutrientId.vitaminB6,
      value: 0.6,
      entered: '0.6',
    ),
  });
}

NutrientAmount _complete(
  NutrientId id, {
  required double value,
  required String entered,
}) {
  return NutrientAmount.complete(
    value: value,
    entered: entered,
    unit: id.defaultUnit,
  );
}
