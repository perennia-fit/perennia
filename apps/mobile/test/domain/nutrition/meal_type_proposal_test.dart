import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/meal_type_proposal.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';

/// docs/designs/meal-logging.md §4.
void main() {
  MealTypeRecord mealType(String id, String name, int sortOrder) {
    return MealTypeRecord(
      id: id,
      name: name,
      sortOrder: sortOrder,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
  }

  final breakfast = mealType('meal-type-breakfast', 'Breakfast', 0);
  final lunch = mealType('meal-type-lunch', 'Lunch', 1);
  final dinner = mealType('meal-type-dinner', 'Dinner', 2);
  final snack = mealType('meal-type-snack', 'Snack', 3);
  final seeds = <MealTypeRecord>[breakfast, lunch, dinner, snack];

  DateTime clock(int hour, int minute) =>
      DateTime.utc(2026, 6, 26, hour, minute);

  group('proposeMealType windows', () {
    final edges = <(int, int, String)>[
      (4, 0, 'Breakfast'),
      (10, 29, 'Breakfast'),
      (10, 30, 'Lunch'),
      (14, 59, 'Lunch'),
      (15, 0, 'Snack'),
      (16, 59, 'Snack'),
      (17, 0, 'Dinner'),
      (21, 59, 'Dinner'),
      (22, 0, 'Snack'),
      (3, 59, 'Snack'),
    ];
    for (final (hour, minute, expected) in edges) {
      final label = '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}';
      test('$label proposes $expected', () {
        expect(proposeMealType(clock(hour, minute), seeds), expected);
      });
    }

    test('compares by minute, ignoring seconds', () {
      expect(
        proposeMealType(DateTime.utc(2026, 6, 26, 10, 29, 59), seeds),
        'Breakfast',
      );
    });

    test('reads the clock fields as given, local or UTC', () {
      expect(proposeMealType(DateTime(2026, 6, 26, 12, 30), seeds), 'Lunch');
    });
  });

  test('a renamed seeded type is proposed under its new name', () {
    final renamed = <MealTypeRecord>[
      mealType('meal-type-breakfast', 'First meal', 0),
      lunch,
      dinner,
      snack,
    ];

    expect(proposeMealType(clock(7, 30), renamed), 'First meal');
  });

  test('custom Meal Types are never proposed', () {
    final withCustom = <MealTypeRecord>[
      mealType('custom-pre-workout', 'Pre-workout', -1),
      ...seeds,
    ];

    expect(proposeMealType(clock(16, 0), withCustom), 'Snack');
    expect(proposeMealType(clock(7, 0), withCustom), 'Breakfast');
  });

  group('archived seeds fall back', () {
    test('to the Snack seed', () {
      expect(
        proposeMealType(clock(12, 0), <MealTypeRecord>[breakfast, snack]),
        'Snack',
      );
    });

    test('to the renamed Snack seed under its current name', () {
      expect(
        proposeMealType(
          clock(19, 0),
          <MealTypeRecord>[mealType('meal-type-snack', 'Bites', 3)],
        ),
        'Bites',
      );
    });

    test('then to the first active type by sort order, then id', () {
      final custom = <MealTypeRecord>[
        mealType('custom-b', 'Second', 5),
        mealType('custom-z', 'Zebra', 4),
        mealType('custom-a', 'First', 4),
      ];

      expect(proposeMealType(clock(12, 0), custom), 'First');
    });

    test('then to the label Snack with no active type', () {
      expect(proposeMealType(clock(12, 0), const <MealTypeRecord>[]), 'Snack');
    });

    test('treats a type passed with deletedAt as archived', () {
      final archivedLunch = MealTypeRecord(
        id: 'meal-type-lunch',
        name: 'Lunch',
        sortOrder: 1,
        updatedAt: DateTime.utc(2026, 1, 1),
        deletedAt: DateTime.utc(2026, 2, 1),
      );

      expect(
        proposeMealType(
          clock(12, 0),
          <MealTypeRecord>[breakfast, archivedLunch, dinner, snack],
        ),
        'Snack',
      );
    });
  });
}
