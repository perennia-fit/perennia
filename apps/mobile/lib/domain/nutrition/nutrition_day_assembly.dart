/// Assembles Nutrition Days from Meal, Food Entry, and Meal Type records.
///
/// The repository maps its rows to records and hands them here, so the
/// ordering rules are testable without a database.
library;

import 'nutrition.dart';

/// Sort order for a Meal whose Meal Type is not among the active ones: after
/// every known type.
const _unknownMealTypeSortOrder = 1 << 30;

/// The Nutrition Day for [localDate] built from [meals], each carrying its
/// [entries] in the order given.
///
/// Meals sort by their Meal Type's sort order (unknown types last), then by
/// start time, Meal Type name, and id. [entries] whose Meal is not in [meals]
/// are ignored.
NutritionDayRecord assembleNutritionDay({
  required NutritionDayDate localDate,
  required List<MealRecord> meals,
  required List<FoodEntryRecord> entries,
  required List<MealTypeRecord> mealTypes,
}) {
  final entriesByMealId = <String, List<FoodEntryRecord>>{};
  for (final entry in entries) {
    entriesByMealId
        .putIfAbsent(entry.mealId, () => <FoodEntryRecord>[])
        .add(entry);
  }
  final mealTypeSortOrders = <String, int>{
    for (final mealType in mealTypes) mealType.name: mealType.sortOrder,
  };
  final sortedMeals = List<MealRecord>.of(meals)
    ..sort((left, right) {
      final leftSortOrder =
          mealTypeSortOrders[left.mealType] ?? _unknownMealTypeSortOrder;
      final rightSortOrder =
          mealTypeSortOrders[right.mealType] ?? _unknownMealTypeSortOrder;
      final orderComparison = leftSortOrder.compareTo(rightSortOrder);
      if (orderComparison != 0) {
        return orderComparison;
      }
      final startedComparison = left.startedAt.compareTo(right.startedAt);
      if (startedComparison != 0) {
        return startedComparison;
      }
      final typeComparison = left.mealType.compareTo(right.mealType);
      if (typeComparison != 0) {
        return typeComparison;
      }
      return left.id.compareTo(right.id);
    });

  return NutritionDayRecord(
    localDate: localDate,
    meals: List<NutritionDayMealRecord>.unmodifiable(
      sortedMeals.map(
        (meal) => NutritionDayMealRecord(
          meal: meal,
          entries: List<FoodEntryRecord>.unmodifiable(
            entriesByMealId[meal.id] ?? const <FoodEntryRecord>[],
          ),
        ),
      ),
    ),
  );
}

/// One Nutrition Day per day of [range], in order, each assembled by
/// [assembleNutritionDay] from the [meals] on that day. A day with no Meals
/// is still present, empty.
List<NutritionDayRecord> assembleNutritionDaysInRange({
  required NutritionDayRange range,
  required List<MealRecord> meals,
  required List<FoodEntryRecord> entries,
  required List<MealTypeRecord> mealTypes,
}) {
  final mealsByDate = <NutritionDayDate, List<MealRecord>>{};
  for (final meal in meals) {
    mealsByDate.putIfAbsent(meal.localDate, () => <MealRecord>[]).add(meal);
  }

  return List<NutritionDayRecord>.unmodifiable(
    range.days.map(
      (date) => assembleNutritionDay(
        localDate: date,
        meals: mealsByDate[date] ?? const <MealRecord>[],
        entries: entries,
        mealTypes: mealTypes,
      ),
    ),
  );
}
