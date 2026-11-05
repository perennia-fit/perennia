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
    int offsetMinutes = 0,
    MealTimePrecision timePrecision = MealTimePrecision.instant,
  }) {
    // [hour] is the UTC hour; the clock reads it at [offsetMinutes].
    return MealRecord(
      id: id,
      mealType: mealType,
      startedAt: DateTime.utc(2026, 6, 16, hour),
      timezone: 'UTC',
      timezoneOffsetMinutes: offsetMinutes,
      timePrecision: timePrecision,
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

  test('orders instant Meals by clock time, whatever their Meal Type', () {
    final day = assembleNutritionDay(
      localDate: day1,
      meals: <MealRecord>[
        meal('dinner', 'Dinner', hour: 19),
        meal('late-breakfast', 'Breakfast', hour: 15),
        meal('lunch', 'Lunch', hour: 12),
        meal('unknown', 'Zeta', hour: 6),
      ],
      entries: const <FoodEntryRecord>[],
      mealTypes: mealTypes,
    );

    expect(day.localDate, day1);
    expect(mealIds(day), <String>[
      'unknown',
      'lunch',
      'late-breakfast',
      'dinner',
    ]);
  });

  test('puts date Meals first, ordered among themselves by sort order', () {
    const date = MealTimePrecision.date;
    final day = assembleNutritionDay(
      localDate: day1,
      meals: <MealRecord>[
        meal('instant-early', 'Dinner', hour: 1),
        meal('date-unknown', 'Zeta', hour: 0, timePrecision: date),
        meal('date-dinner', 'Dinner', hour: 0, timePrecision: date),
        meal('date-breakfast', 'Breakfast', hour: 23, timePrecision: date),
        meal('instant-late', 'Breakfast', hour: 9),
      ],
      entries: const <FoodEntryRecord>[],
      mealTypes: mealTypes,
    );

    expect(mealIds(day), <String>[
      'date-breakfast',
      'date-dinner',
      'date-unknown',
      'instant-early',
      'instant-late',
    ]);
  });

  test('orders Meals with different frozen offsets by clock, not instant', () {
    // 'abroad' is the earlier instant (10:00 UTC) but reads 12:00 at +02:00;
    // 'home' is the later instant (11:00 UTC) and reads 11:00 at UTC.
    final day = assembleNutritionDay(
      localDate: day1,
      meals: <MealRecord>[
        meal('abroad', 'Lunch', hour: 10, offsetMinutes: 120),
        meal('home', 'Lunch', hour: 11),
      ],
      entries: const <FoodEntryRecord>[],
      mealTypes: mealTypes,
    );

    expect(mealIds(day), <String>['home', 'abroad']);
  });

  test('breaks ties by id', () {
    const date = MealTimePrecision.date;
    final day = assembleNutritionDay(
      localDate: day1,
      meals: <MealRecord>[
        meal('instant-b', 'Dinner', hour: 12),
        meal('instant-a', 'Breakfast', hour: 12),
        meal('date-b', 'Lunch', timePrecision: date),
        meal('date-a', 'Lunch', hour: 20, timePrecision: date),
      ],
      entries: const <FoodEntryRecord>[],
      mealTypes: mealTypes,
    );

    expect(mealIds(day), <String>[
      'date-a',
      'date-b',
      'instant-a',
      'instant-b',
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
