import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/nutrition/nutrition_day_assembly.dart';

void main() {
  final day1 = NutritionDayDate.parse('2026-06-16');
  final day2 = NutritionDayDate.parse('2026-06-17');
  final day3 = NutritionDayDate.parse('2026-06-18');
  final updatedAt = DateTime.utc(2026, 6, 16);

  MealRecord meal(
    String id,
    String mealType, {
    NutritionDayDate? localDate,
    int hour = 8,
  }) {
    return MealRecord(
      id: id,
      mealType: mealType,
      startedAt: DateTime.utc(2026, 6, 16, hour),
      timezone: 'UTC',
      localDate: localDate ?? day1,
      updatedAt: updatedAt,
    );
  }

  FoodEntryRecord entry(String id, String mealId, int position) {
    return FoodEntryRecord(
      id: id,
      mealId: mealId,
      kind: FoodEntryKind.quickEntry,
      position: position,
      name: id,
      nutrients: NutrientVector.full(const <NutrientId, NutrientAmount>{}),
      updatedAt: updatedAt,
    );
  }

  MealTypeRecord mealType(String name, int sortOrder) {
    return MealTypeRecord(
      id: 'type-$name',
      name: name,
      sortOrder: sortOrder,
      updatedAt: updatedAt,
    );
  }

  final mealTypes = <MealTypeRecord>[
    mealType('Dinner', 2),
    mealType('Breakfast', 0),
    mealType('Lunch', 1),
  ];

  List<String> mealIds(NutritionDayRecord day) =>
      day.meals.map((dayMeal) => dayMeal.meal.id).toList();

  test('orders Meals by Meal Type, start time, type name, then id', () {
    final day = assembleNutritionDay(
      localDate: day1,
      meals: <MealRecord>[
        meal('unknown-b', 'Zeta', hour: 6),
        meal('unknown-a', 'Alpha', hour: 6),
        meal('dinner', 'Dinner', hour: 19),
        meal('lunch-late', 'Lunch', hour: 13),
        meal('lunch-b', 'Lunch', hour: 12),
        meal('lunch-a', 'Lunch', hour: 12),
        meal('breakfast', 'Breakfast', hour: 20),
      ],
      entries: const <FoodEntryRecord>[],
      mealTypes: mealTypes,
    );

    expect(day.localDate, day1);
    expect(mealIds(day), <String>[
      'breakfast',
      'lunch-a',
      'lunch-b',
      'lunch-late',
      'dinner',
      'unknown-a',
      'unknown-b',
    ]);
  });

  test('attaches entries to their Meal in the order given', () {
    final day = assembleNutritionDay(
      localDate: day1,
      meals: <MealRecord>[meal('m1', 'Breakfast'), meal('m2', 'Lunch')],
      entries: <FoodEntryRecord>[
        entry('e3', 'm1', 2),
        entry('e1', 'm1', 0),
        entry('stray', 'other-meal', 0),
      ],
      mealTypes: mealTypes,
    );

    expect(
      day.meals.map((m) => m.entries.map((e) => e.id).toList()).toList(),
      <List<String>>[
        <String>['e3', 'e1'],
        <String>[],
      ],
    );
  });

  test('builds one day per range day, empty days included', () {
    final days = assembleNutritionDaysInRange(
      range: NutritionDayRange(start: day1, end: day3),
      meals: <MealRecord>[
        meal('d3-lunch', 'Lunch', localDate: day3),
        meal('d1-dinner', 'Dinner', localDate: day1),
        meal('d1-breakfast', 'Breakfast', localDate: day1),
      ],
      entries: <FoodEntryRecord>[
        entry('e-d1', 'd1-dinner', 0),
        entry('e-d3', 'd3-lunch', 0),
      ],
      mealTypes: mealTypes,
    );

    expect(days.map((day) => day.localDate), <NutritionDayDate>[
      day1,
      day2,
      day3,
    ]);
    expect(days.map(mealIds), <List<String>>[
      <String>['d1-breakfast', 'd1-dinner'],
      <String>[],
      <String>['d3-lunch'],
    ]);
    expect(days[0].meals[1].entries.single.id, 'e-d1');
    expect(days[2].meals.single.entries.single.id, 'e-d3');
  });
}
