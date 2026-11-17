/// The Meal Type a new Meal is proposed from its local clock time
/// (docs/designs/meal-logging.md §4).
library;

import 'nutrition.dart';

/// The seeded Meal Type ids that carry a proposal window. A window is keyed by
/// the seed's id, not its name, so a renamed seed keeps its window and the
/// proposal stores its current name.
const String breakfastMealTypeSeedId = 'meal-type-breakfast';
const String lunchMealTypeSeedId = 'meal-type-lunch';
const String dinnerMealTypeSeedId = 'meal-type-dinner';
const String snackMealTypeSeedId = 'meal-type-snack';

/// The label proposed when no Meal Type is active at all.
const String fallbackProposedMealTypeLabel = 'Snack';

/// The proposal windows, as inclusive minute-of-day ranges. Every minute
/// outside them belongs to [snackMealTypeSeedId].
const List<({String seedId, int firstMinute, int lastMinute})>
    _mealTypeProposalWindows = <({
  String seedId,
  int firstMinute,
  int lastMinute,
})>[
  // 04:00–10:29
  (seedId: breakfastMealTypeSeedId, firstMinute: 4 * 60, lastMinute: 629),
  // 10:30–14:59
  (seedId: lunchMealTypeSeedId, firstMinute: 630, lastMinute: 899),
  // 17:00–21:59
  (seedId: dinnerMealTypeSeedId, firstMinute: 17 * 60, lastMinute: 1319),
];

/// Proposes a Meal Type name for a Meal whose local clock reads [localClock]
/// (the Meal's time at its frozen offset), from the active [mealTypes].
///
/// - The clock is compared by minute of day; seconds are ignored.
/// - The window's seeded type is proposed under its current name.
/// - If that type is archived (absent from [mealTypes]), the proposal falls
///   back to the active Snack seed, then to the first active type by
///   `sortOrder` (then id), then to the label `Snack`.
/// - Custom Meal Types have no window, so they are never proposed.
///
/// The result is stored in `meals.meal_type` at the Meal's first write,
/// exactly as a hand-picked type is, and is never recomputed after that: a
/// stored proposal is a label the user saw and could change, not a cached
/// derived value (§4 lifecycle, §11).
String proposeMealType(DateTime localClock, List<MealTypeRecord> mealTypes) {
  final minuteOfDay = localClock.hour * 60 + localClock.minute;
  var seedId = snackMealTypeSeedId;
  for (final window in _mealTypeProposalWindows) {
    if (minuteOfDay >= window.firstMinute && minuteOfDay <= window.lastMinute) {
      seedId = window.seedId;
      break;
    }
  }

  final active =
      mealTypes.where((type) => type.deletedAt == null).toList(growable: false);
  MealTypeRecord? activeById(String id) {
    for (final type in active) {
      if (type.id == id) {
        return type;
      }
    }
    return null;
  }

  final proposed = activeById(seedId) ?? activeById(snackMealTypeSeedId);
  if (proposed != null) {
    return proposed.name;
  }
  if (active.isEmpty) {
    return fallbackProposedMealTypeLabel;
  }
  final ordered = active.toList()
    ..sort((left, right) {
      final bySortOrder = left.sortOrder.compareTo(right.sortOrder);
      return bySortOrder != 0 ? bySortOrder : left.id.compareTo(right.id);
    });
  return ordered.first.name;
}
