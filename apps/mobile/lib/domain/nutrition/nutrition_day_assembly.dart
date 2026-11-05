/// Assembles Nutrition Days from Meal, Food Entry, and Meal Type records.
///
/// The repository maps its rows to records and hands them here, so the
/// ordering rules are testable without a database.
library;

import 'nutrition.dart';

/// Sort order for a Meal whose Meal Type is not among the active ones: after
/// every known type.
const _unknownMealTypeSortOrder = 1 << 30;

/// [meal]'s clock as wall-clock fields, comparable across Meals.
///
/// [MealRecord.clock] is a UTC value shifted by the frozen offset, or a
/// device-local value for a Meal without one; comparing those as instants
/// would mix the two. Rebuilding the fields as UTC compares what the cards
/// show.
DateTime _wallClock(MealRecord meal) {
  final clock = meal.clock;
  return DateTime.utc(
    clock.year,
    clock.month,
    clock.day,
    clock.hour,
    clock.minute,
    clock.second,
    clock.millisecond,
    clock.microsecond,
  );
}

/// The Nutrition Day for [localDate] built from [meals], each carrying its
/// [entries] in the order given.
///
/// The order is docs/designs/meal-logging.md §6, "The Nutrition Day order":
///
/// 1. `date` Meals first, by their Meal Type's sort order (unknown types
///    last). They have no clock time, so the Meal Type is all there is.
/// 2. Then `instant` Meals by [MealRecord.clock], the local clock at each
///    Meal's frozen offset. Never by `startedAt`: two Meals eaten in
///    different zones read in the order their clocks show, as the cards do.
/// 3. Ties break by id.
///
/// [entries] whose Meal is not in [meals] are ignored.
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
  int dateMealSortOrder(MealRecord meal) =>
      mealTypeSortOrders[meal.mealType] ?? _unknownMealTypeSortOrder;
  final sortedMeals = List<MealRecord>.of(meals)
    ..sort((left, right) {
      final leftIsDate = left.timePrecision == MealTimePrecision.date;
      final rightIsDate = right.timePrecision == MealTimePrecision.date;
      if (leftIsDate != rightIsDate) {
        return leftIsDate ? -1 : 1;
      }
      final comparison = leftIsDate
          ? dateMealSortOrder(left).compareTo(dateMealSortOrder(right))
          : _wallClock(left).compareTo(_wallClock(right));
      if (comparison != 0) {
        return comparison;
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
