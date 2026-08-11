import 'dart:convert';

class NutritionDayDate implements Comparable<NutritionDayDate> {
  const NutritionDayDate({
    required this.year,
    required this.month,
    required this.day,
  })  : assert(month >= 1 && month <= 12),
        assert(day >= 1 && day <= 31);

  factory NutritionDayDate.fromDateTime(DateTime value) {
    final local = value.toLocal();
    return NutritionDayDate(
      year: local.year,
      month: local.month,
      day: local.day,
    );
  }

  factory NutritionDayDate.parse(String value) {
    final match = _storagePattern.firstMatch(value);
    if (match == null) {
      throw FormatException('Expected a YYYY-MM-DD nutrition day.', value);
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw FormatException('Invalid nutrition day date.', value);
    }

    return NutritionDayDate(year: year, month: month, day: day);
  }

  static final _storagePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  String get storageValue {
    final paddedYear = year.toString().padLeft(4, '0');
    final paddedMonth = month.toString().padLeft(2, '0');
    final paddedDay = day.toString().padLeft(2, '0');
    return '$paddedYear-$paddedMonth-$paddedDay';
  }

  DateTime toLocalDateTime() => DateTime(year, month, day);

  NutritionDayDate addDays(int days) {
    final next = toLocalDateTime().add(Duration(days: days));
    return NutritionDayDate.fromDateTime(next);
  }

  @override
  int compareTo(NutritionDayDate other) {
    return storageValue.compareTo(other.storageValue);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is NutritionDayDate &&
            runtimeType == other.runtimeType &&
            year == other.year &&
            month == other.month &&
            day == other.day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => storageValue;
}

enum NutrientUnit {
  kilocalorie,
  gram,
  milligram,
  microgram,
  milliliter;
}

enum NutrientValueStatus {
  complete,
  unknown;
}

enum NutrientId {
  energy('energy', NutrientUnit.kilocalorie),
  protein('protein', NutrientUnit.gram),
  carbohydrate('carbohydrate', NutrientUnit.gram),
  sugar('sugar', NutrientUnit.gram),
  fat('fat', NutrientUnit.gram),
  saturatedFat('saturated_fat', NutrientUnit.gram),
  monounsaturatedFat('monounsaturated_fat', NutrientUnit.gram),
  polyunsaturatedFat('polyunsaturated_fat', NutrientUnit.gram),
  fiber('fiber', NutrientUnit.gram),
  sodium('sodium', NutrientUnit.milligram),
  cholesterol('cholesterol', NutrientUnit.milligram),
  vitaminA('vitamin_a', NutrientUnit.microgram),
  vitaminC('vitamin_c', NutrientUnit.milligram),
  vitaminD('vitamin_d', NutrientUnit.microgram),
  vitaminE('vitamin_e', NutrientUnit.milligram),
  vitaminK('vitamin_k', NutrientUnit.microgram),
  thiamin('thiamin', NutrientUnit.milligram),
  riboflavin('riboflavin', NutrientUnit.milligram),
  niacin('niacin', NutrientUnit.milligram),
  vitaminB6('vitamin_b6', NutrientUnit.milligram),
  folate('folate', NutrientUnit.microgram),
  vitaminB12('vitamin_b12', NutrientUnit.microgram),
  calcium('calcium', NutrientUnit.milligram),
  iron('iron', NutrientUnit.milligram),
  magnesium('magnesium', NutrientUnit.milligram),
  phosphorus('phosphorus', NutrientUnit.milligram),
  potassium('potassium', NutrientUnit.milligram),
  zinc('zinc', NutrientUnit.milligram),
  copper('copper', NutrientUnit.milligram),
  manganese('manganese', NutrientUnit.milligram),
  selenium('selenium', NutrientUnit.microgram),
  caffeine('caffeine', NutrientUnit.milligram),
  water('water', NutrientUnit.milliliter);

  const NutrientId(this.storageKey, this.defaultUnit);

  final String storageKey;
  final NutrientUnit defaultUnit;

  static NutrientId byStorageKey(String storageKey) {
    return NutrientId.values.firstWhere(
      (id) => id.storageKey == storageKey,
      orElse: () => throw ArgumentError.value(
        storageKey,
        'storageKey',
        'Unknown Nutrient id.',
      ),
    );
  }
}

enum NutrientDisplayTier {
  core,
  common,
  detail;
}

/// The `Nutrient`s a nutrition `Goal` can target in v1: energy plus the three
/// macros, each a fixed target value (NUTRITION.md §4). The list is left open
/// so distribution, per-weekday, and micronutrient goals can be added later
/// without reshaping the stored target (NUTRITION.md §12).
const goalableNutrientIds = <NutrientId>[
  NutrientId.energy,
  NutrientId.protein,
  NutrientId.carbohydrate,
  NutrientId.fat,
];

bool isGoalableNutrient(NutrientId id) => goalableNutrientIds.contains(id);

const _coreNutrientIds = <NutrientId>[
  NutrientId.energy,
  NutrientId.protein,
  NutrientId.carbohydrate,
  NutrientId.fat,
];

const _commonNutrientIds = <NutrientId>[
  NutrientId.saturatedFat,
  NutrientId.sugar,
  NutrientId.fiber,
  NutrientId.sodium,
];

List<NutrientId> nutrientIdsForDisplayTier(NutrientDisplayTier tier) {
  return switch (tier) {
    NutrientDisplayTier.core => _coreNutrientIds,
    NutrientDisplayTier.common => _commonNutrientIds,
    NutrientDisplayTier.detail => NutrientId.values
        .where((id) =>
            !_coreNutrientIds.contains(id) && !_commonNutrientIds.contains(id))
        .toList(growable: false),
  };
}

NutrientDisplayTier nutrientDisplayTier(NutrientId id) {
  if (_coreNutrientIds.contains(id)) {
    return NutrientDisplayTier.core;
  }
  if (_commonNutrientIds.contains(id)) {
    return NutrientDisplayTier.common;
  }
  return NutrientDisplayTier.detail;
}

String nutrientDisplayLabel(NutrientId id) {
  return switch (id) {
    NutrientId.energy => 'Calories',
    NutrientId.protein => 'Protein',
    NutrientId.carbohydrate => 'Carbs',
    NutrientId.sugar => 'Sugar',
    NutrientId.fat => 'Fat',
    NutrientId.saturatedFat => 'Saturated fat',
    NutrientId.monounsaturatedFat => 'Monounsaturated fat',
    NutrientId.polyunsaturatedFat => 'Polyunsaturated fat',
    NutrientId.fiber => 'Fiber',
    NutrientId.sodium => 'Sodium',
    NutrientId.cholesterol => 'Cholesterol',
    NutrientId.vitaminA => 'Vitamin A',
    NutrientId.vitaminC => 'Vitamin C',
    NutrientId.vitaminD => 'Vitamin D',
    NutrientId.vitaminE => 'Vitamin E',
    NutrientId.vitaminK => 'Vitamin K',
    NutrientId.thiamin => 'Thiamin',
    NutrientId.riboflavin => 'Riboflavin',
    NutrientId.niacin => 'Niacin',
    NutrientId.vitaminB6 => 'Vitamin B6',
    NutrientId.folate => 'Folate',
    NutrientId.vitaminB12 => 'Vitamin B12',
    NutrientId.calcium => 'Calcium',
    NutrientId.iron => 'Iron',
    NutrientId.magnesium => 'Magnesium',
    NutrientId.phosphorus => 'Phosphorus',
    NutrientId.potassium => 'Potassium',
    NutrientId.zinc => 'Zinc',
    NutrientId.copper => 'Copper',
    NutrientId.manganese => 'Manganese',
    NutrientId.selenium => 'Selenium',
    NutrientId.caffeine => 'Caffeine',
    NutrientId.water => 'Water',
  };
}

class NutrientAmount {
  const NutrientAmount._({
    required this.status,
    required this.unit,
    this.value,
    this.entered,
  });

  factory NutrientAmount.complete({
    required double value,
    required String entered,
    required NutrientUnit unit,
  }) {
    if (!value.isFinite) {
      throw ArgumentError.value(
          value, 'value', 'Nutrient value must be finite.');
    }
    final normalizedEntered = entered.trim();
    if (normalizedEntered.isEmpty) {
      throw ArgumentError.value(
        entered,
        'entered',
        'Entered Nutrient value must not be empty.',
      );
    }
    return NutrientAmount._(
      status: NutrientValueStatus.complete,
      value: value,
      entered: normalizedEntered,
      unit: unit,
    );
  }

  factory NutrientAmount.unknown(NutrientUnit unit) {
    return NutrientAmount._(
      status: NutrientValueStatus.unknown,
      unit: unit,
    );
  }

  factory NutrientAmount.fromJson(Map<String, Object?> json) {
    final status = NutrientValueStatus.values.byName(
      _requiredString(json, 'status'),
    );
    final unit = NutrientUnit.values.byName(_requiredString(json, 'unit'));
    return switch (status) {
      NutrientValueStatus.complete => NutrientAmount.complete(
          value: _requiredDouble(json, 'value'),
          entered: _requiredString(json, 'entered'),
          unit: unit,
        ),
      NutrientValueStatus.unknown => NutrientAmount.unknown(unit),
    };
  }

  final NutrientValueStatus status;
  final double? value;
  final String? entered;
  final NutrientUnit unit;

  bool get isComplete => status == NutrientValueStatus.complete;

  NutrientAmount scale(double factor) {
    if (status == NutrientValueStatus.unknown) {
      return NutrientAmount.unknown(unit);
    }
    final scaled = value! * factor;
    return NutrientAmount.complete(
      value: scaled,
      entered: _formatDerivedValue(scaled),
      unit: unit,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'value': value,
      'entered': entered,
      'unit': unit.name,
    };
  }
}

class NutrientVector {
  factory NutrientVector.full(Map<NutrientId, NutrientAmount> amounts) {
    return NutrientVector._(
      <NutrientId, NutrientAmount>{
        for (final id in NutrientId.values)
          id: amounts[id] ?? NutrientAmount.unknown(id.defaultUnit),
      },
    );
  }

  factory NutrientVector.energyAndMacros({
    required NutrientAmount energy,
    required NutrientAmount protein,
    required NutrientAmount carbohydrate,
    required NutrientAmount fat,
  }) {
    return NutrientVector.full(
      <NutrientId, NutrientAmount>{
        NutrientId.energy: energy,
        NutrientId.protein: protein,
        NutrientId.carbohydrate: carbohydrate,
        NutrientId.fat: fat,
      },
    );
  }

  factory NutrientVector.fromJsonString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('Expected Nutrient vector JSON object.', value);
    }
    return NutrientVector.fromJson(decoded);
  }

  factory NutrientVector.fromJson(Map<String, Object?> json) {
    final amounts = <NutrientId, NutrientAmount>{};
    for (final id in NutrientId.values) {
      final encoded = json[id.storageKey];
      if (encoded == null) {
        amounts[id] = NutrientAmount.unknown(id.defaultUnit);
        continue;
      }
      if (encoded is! Map<String, Object?>) {
        throw FormatException(
          'Nutrient ${id.storageKey} must be a JSON object.',
          encoded,
        );
      }
      amounts[id] = NutrientAmount.fromJson(encoded);
    }
    return NutrientVector.full(amounts);
  }

  const NutrientVector._(this._amounts);

  static const coreIds = <NutrientId>[
    NutrientId.energy,
    NutrientId.protein,
    NutrientId.carbohydrate,
    NutrientId.fat,
  ];

  final Map<NutrientId, NutrientAmount> _amounts;

  NutrientAmount operator [](NutrientId id) => _amounts[id]!;

  Map<NutrientId, NutrientAmount> get amounts {
    return Map<NutrientId, NutrientAmount>.unmodifiable(_amounts);
  }

  NutrientVector scale(double factor) {
    if (!factor.isFinite || factor < 0) {
      throw ArgumentError.value(
        factor,
        'factor',
        'Nutrient scale factor must be finite and non-negative.',
      );
    }
    return NutrientVector.full(
      <NutrientId, NutrientAmount>{
        for (final id in NutrientId.values) id: _amounts[id]!.scale(factor),
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      for (final id in NutrientId.values) id.storageKey: _amounts[id]!.toJson(),
    };
  }

  String toJsonString() => jsonEncode(toJson());
}

enum FoodSource {
  usda,
  openFoodFacts,
  user,

  /// A `Food Entry` materialized from a Cronometer CSV export at the edge
  /// (NUTRITION.md §9). The specific provider is recognised, so its registry
  /// value is the provider itself.
  cronometer,

  /// A `Food Entry` materialized from a MyFitnessPal CSV export at the edge
  /// (the premium-gated nutrition export, NUTRITION.md §9). A recognised
  /// provider, so its registry value is the provider itself.
  myFitnessPal,

  /// A `Food Entry` materialized from a Yazio GDPR export (CSV/JSON) at the
  /// edge (NUTRITION.md §9). A recognised provider.
  yazio,

  /// A `Food Entry` materialized from a Lifesum GDPR export (CSV/JSON) at the
  /// edge (NUTRITION.md §9). A recognised provider.
  lifesum,

  /// A `Food Entry` materialized from an import whose provider is not a
  /// recognised registry value. The originating provider string is preserved
  /// elsewhere on the entry rather than lost (mirrors INTEGRATIONS.md §6's
  /// preserved-vendor-string rule); this is the generic `Imported` bucket.
  imported;
}

enum FoodEntryKind {
  quickEntry,
  food;
}

enum PortionUnit {
  gram,
  milliliter,
  ounce,
  fluidOunce,
  serving,
  package;
}

class Portion {
  const Portion._({
    required this.value,
    required this.entered,
    required this.unit,
  });

  factory Portion({
    required double value,
    required String entered,
    required PortionUnit unit,
  }) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(
        value,
        'value',
        'Portion value must be positive.',
      );
    }
    final normalizedEntered = entered.trim();
    if (normalizedEntered.isEmpty) {
      throw ArgumentError.value(
        entered,
        'entered',
        'Entered Portion value must not be empty.',
      );
    }
    return Portion._(
      value: value,
      entered: normalizedEntered,
      unit: unit,
    );
  }

  factory Portion.fromJsonString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('Expected Portion JSON object.', value);
    }
    return Portion.fromJson(decoded);
  }

  factory Portion.fromJson(Map<String, Object?> json) {
    return Portion(
      value: _requiredDouble(json, 'value'),
      entered: _requiredString(json, 'entered'),
      unit: PortionUnit.values.byName(_requiredString(json, 'unit')),
    );
  }

  final double value;
  final String entered;
  final PortionUnit unit;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'value': value,
      'entered': entered,
      'unit': unit.name,
    };
  }

  String toJsonString() => jsonEncode(toJson());
}

class UserFoodDraft {
  const UserFoodDraft({
    required this.name,
    required this.nutrientsPer100,
    required this.isLiquid,
    this.servingLabel,
    this.servingSize,
    this.packageSize,
  });

  final String name;
  final NutrientVector nutrientsPer100;
  final bool isLiquid;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;
}

class UserFoodForkDraft {
  const UserFoodForkDraft({
    this.name,
    this.nutrientsPer100,
    this.isLiquid,
    this.servingLabel,
    this.servingSize,
    this.packageSize,
  });

  final String? name;
  final NutrientVector? nutrientsPer100;
  final bool? isLiquid;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;
}

class RecipeDraft {
  RecipeDraft({
    required this.name,
    required Iterable<RecipeIngredient> ingredients,
    required this.servingCount,
  }) : ingredients = List<RecipeIngredient>.unmodifiable(ingredients);

  final String name;
  final List<RecipeIngredient> ingredients;
  final double servingCount;
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.foodId,
    required this.name,
    required this.foodSource,
    required this.nutrientsPer100,
    required this.isLiquid,
    required this.portion,
    this.servingLabel,
    this.servingSize,
    this.packageSize,
  });

  factory RecipeIngredient.fromJson(Map<String, Object?> json) {
    final encodedNutrients = json['nutrient_values'];
    if (encodedNutrients is! Map<String, Object?>) {
      throw FormatException('Expected Recipe ingredient nutrients.', json);
    }
    final encodedPortion = json['portion'];
    if (encodedPortion is! Map<String, Object?>) {
      throw FormatException('Expected Recipe ingredient Portion.', json);
    }
    return RecipeIngredient(
      foodId: _requiredString(json, 'food_id'),
      name: _requiredString(json, 'name'),
      foodSource: FoodSource.values.byName(
        _requiredString(json, 'food_source'),
      ),
      nutrientsPer100: NutrientVector.fromJson(encodedNutrients),
      isLiquid: _requiredBool(json, 'is_liquid'),
      portion: Portion.fromJson(encodedPortion),
      servingLabel: _optionalString(json, 'serving_label'),
      servingSize: _optionalDouble(json, 'serving_size'),
      packageSize: _optionalDouble(json, 'package_size'),
    );
  }

  final String foodId;
  final String name;
  final FoodSource foodSource;
  final NutrientVector nutrientsPer100;
  final bool isLiquid;
  final Portion portion;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;

  double get resolvedBaseQuantity {
    return resolvePortionBaseQuantity(
      portion,
      servingSize: servingSize,
      packageSize: packageSize,
    );
  }

  NutrientVector get resolvedNutrients {
    return nutrientsPer100.scale(resolvedBaseQuantity / 100);
  }

  List<PortionUnit> get availablePortionUnits {
    return availablePortionUnitsForFood(
      isLiquid: isLiquid,
      servingLabel: servingLabel,
      servingSize: servingSize,
      packageSize: packageSize,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'food_id': foodId,
      'name': name,
      'food_source': foodSource.name,
      'nutrient_values': nutrientsPer100.toJson(),
      'is_liquid': isLiquid,
      'serving_label': servingLabel,
      'serving_size': servingSize,
      'package_size': packageSize,
      'portion': portion.toJson(),
    };
  }
}

class RecipeNutrition {
  const RecipeNutrition({
    required this.nutrientsPer100,
    required this.totalBaseQuantity,
    required this.servingSize,
  });

  final NutrientVector nutrientsPer100;
  final double totalBaseQuantity;
  final double servingSize;
}

RecipeNutrition deriveRecipeNutrition({
  required List<RecipeIngredient> ingredients,
  required double servingCount,
}) {
  if (ingredients.isEmpty) {
    throw ArgumentError.value(
      ingredients,
      'ingredients',
      'Recipe requires at least one ingredient.',
    );
  }
  if (!servingCount.isFinite || servingCount <= 0) {
    throw ArgumentError.value(
      servingCount,
      'servingCount',
      'Recipe serving count must be positive.',
    );
  }

  final totalBaseQuantity = ingredients.fold<double>(
    0,
    (total, ingredient) => total + ingredient.resolvedBaseQuantity,
  );
  if (!totalBaseQuantity.isFinite || totalBaseQuantity <= 0) {
    throw ArgumentError.value(
      totalBaseQuantity,
      'ingredients',
      'Recipe ingredients must resolve to a positive quantity.',
    );
  }

  return RecipeNutrition(
    nutrientsPer100: NutrientVector.full(
      <NutrientId, NutrientAmount>{
        for (final id in NutrientId.values)
          id: _deriveRecipeNutrientPer100(
            id: id,
            ingredients: ingredients,
            totalBaseQuantity: totalBaseQuantity,
          ),
      },
    ),
    totalBaseQuantity: totalBaseQuantity,
    servingSize: totalBaseQuantity / servingCount,
  );
}

NutrientAmount _deriveRecipeNutrientPer100({
  required NutrientId id,
  required List<RecipeIngredient> ingredients,
  required double totalBaseQuantity,
}) {
  var total = 0.0;
  for (final ingredient in ingredients) {
    final amount = ingredient.nutrientsPer100[id];
    if (!amount.isComplete) {
      return NutrientAmount.unknown(id.defaultUnit);
    }
    total += amount.value! * ingredient.resolvedBaseQuantity / 100;
  }
  final per100 = total / totalBaseQuantity * 100;
  return NutrientAmount.complete(
    value: per100,
    entered: _formatDerivedValue(per100),
    unit: id.defaultUnit,
  );
}

class FoodEntryDraft {
  const FoodEntryDraft({
    required this.mealId,
    required this.foodId,
    required this.portion,
  });

  final String mealId;
  final String foodId;
  final Portion portion;
}

class FoodEntrySnapshotDraft {
  FoodEntrySnapshotDraft({
    required this.mealId,
    required this.foodId,
    required this.name,
    required this.foodSource,
    required this.nutrientsPer100,
    required this.isLiquid,
    required this.portion,
    this.servingLabel,
    this.servingSize,
    this.packageSize,
    this.importSource,
    this.importExternalId,
    this.importProvider,
    Iterable<NutritionReviewFlag> reviewFlags = const <NutritionReviewFlag>[],
  }) : reviewFlags = List<NutritionReviewFlag>.unmodifiable(reviewFlags);

  final String mealId;

  /// The catalogue `Food` this snapshot was taken from, or null for an
  /// imported observation that never references the User Library — an import
  /// must NEVER auto-create a User Food (NUTRITION.md §9; INTEGRATIONS.md §6).
  final String? foodId;
  final String name;
  final FoodSource foodSource;
  final NutrientVector nutrientsPer100;
  final bool isLiquid;
  final Portion portion;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;

  /// Import idempotency key parts. When [importSource] is set the entry lands
  /// read-only and is deduped by `(importSource, importExternalId)`.
  final String? importSource;
  final String? importExternalId;

  /// The **preserved provider string** for an entry whose [foodSource] is the
  /// generic [FoodSource.imported] — the exact, human-facing originating
  /// provider name kept alongside the generic origin (NUTRITION.md §9;
  /// INTEGRATIONS.md §6). Null when the provider resolved to a specific
  /// recognised [FoodSource] (the enum value already names it).
  final String? importProvider;

  /// Non-blocking soft-warn review flags to persist on the entry.
  final List<NutritionReviewFlag> reviewFlags;

  List<PortionUnit> get availablePortionUnits {
    return availablePortionUnitsForFood(
      isLiquid: isLiquid,
      servingLabel: servingLabel,
      servingSize: servingSize,
      packageSize: packageSize,
    );
  }
}

class MealTypeDraft {
  const MealTypeDraft({
    required this.name,
    required this.sortOrder,
  });

  final String name;
  final int sortOrder;
}

class MealDraft {
  const MealDraft({
    required this.mealType,
    required this.startedAt,
    this.localDate,
    this.timezone,
    this.endedAt,
  });

  final String mealType;
  final DateTime startedAt;
  final NutritionDayDate? localDate;
  final String? timezone;
  final DateTime? endedAt;
}

class MealTypeRecord {
  const MealTypeRecord({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final int sortOrder;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class QuickFoodEntryDraft {
  const QuickFoodEntryDraft({
    required this.name,
    required this.nutrients,
  });

  final String name;
  final NutrientVector nutrients;
}

class UserFoodRecord {
  UserFoodRecord({
    required this.id,
    required this.name,
    required this.foodSource,
    required this.nutrientsPer100,
    required this.isLiquid,
    required this.updatedAt,
    this.servingLabel,
    this.servingSize,
    this.packageSize,
    Iterable<RecipeIngredient> recipeIngredients = const <RecipeIngredient>[],
    this.recipeServingCount,
    this.deletedAt,
  }) : recipeIngredients =
            List<RecipeIngredient>.unmodifiable(recipeIngredients);

  final String id;
  final String name;
  final FoodSource foodSource;
  final NutrientVector nutrientsPer100;
  final bool isLiquid;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;
  final List<RecipeIngredient> recipeIngredients;
  final double? recipeServingCount;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isRecipe => recipeServingCount != null;

  List<PortionUnit> get availablePortionUnits {
    return availablePortionUnitsForFood(
      isLiquid: isLiquid,
      servingLabel: servingLabel,
      servingSize: servingSize,
      packageSize: packageSize,
    );
  }
}

class PlatformFoodRecord {
  const PlatformFoodRecord({
    required this.id,
    required this.name,
    required this.foodSource,
    required this.nutrientsPer100,
    required this.isLiquid,
    this.servingLabel,
    this.servingSize,
    this.packageSize,
  });

  final String id;
  final String name;
  final FoodSource foodSource;
  final NutrientVector nutrientsPer100;
  final bool isLiquid;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;

  List<PortionUnit> get availablePortionUnits {
    return availablePortionUnitsForFood(
      isLiquid: isLiquid,
      servingLabel: servingLabel,
      servingSize: servingSize,
      packageSize: packageSize,
    );
  }
}

class MealRecord {
  const MealRecord({
    required this.id,
    required this.mealType,
    required this.startedAt,
    required this.timezone,
    required this.localDate,
    required this.updatedAt,
    this.endedAt,
    this.deletedAt,
  });

  final String id;
  final String mealType;
  final DateTime startedAt;
  final String timezone;
  final NutritionDayDate localDate;
  final DateTime? endedAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class FoodEntryRecord {
  FoodEntryRecord({
    required this.id,
    required this.mealId,
    required this.kind,
    required this.position,
    required this.name,
    required this.nutrients,
    required this.updatedAt,
    this.foodId,
    this.portion,
    this.foodSource,
    this.isLiquid,
    this.servingLabel,
    this.servingSize,
    this.packageSize,
    this.importSource,
    this.importExternalId,
    this.importProvider,
    Iterable<NutritionReviewFlag> reviewFlags = const <NutritionReviewFlag>[],
    this.deletedAt,
  }) : reviewFlags = List<NutritionReviewFlag>.unmodifiable(reviewFlags);

  final String id;
  final String mealId;
  final FoodEntryKind kind;
  final int position;
  final String name;
  final NutrientVector nutrients;
  final String? foodId;
  final Portion? portion;
  final FoodSource? foodSource;
  final bool? isLiquid;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;

  /// The originating provider string when this entry was materialized by an
  /// import (e.g. `cronometer`); null for manually-authored entries. Together
  /// with [importExternalId] this forms the idempotency key (NUTRITION.md §7).
  final String? importSource;
  final String? importExternalId;

  /// The **preserved provider string** for a generic [FoodSource.imported]
  /// entry — the exact originating provider name kept alongside the generic
  /// origin (NUTRITION.md §9; INTEGRATIONS.md §6). Null for a recognised
  /// provider (the [foodSource] enum value names it) or a manual entry.
  final String? importProvider;

  /// Non-blocking soft-warn review flags carried by a materialized entry
  /// (NUTRITION.md §6; INTEGRATIONS.md §10).
  final List<NutritionReviewFlag> reviewFlags;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// An imported `Food Entry` is a read-only immutable observation — it is
  /// corrected by delete-and-re-add, never edited in place (NUTRITION.md §7).
  bool get isImported => importSource != null;

  /// Whether this materialized entry carries non-blocking review flags the
  /// user may want to look at (NUTRITION.md §6/§10). Surfaced, never blocking.
  bool get hasReviewFlags => reviewFlags.isNotEmpty;

  double? get resolvedBaseQuantity {
    final portion = this.portion;
    if (kind != FoodEntryKind.food || portion == null) {
      return null;
    }
    return _resolveBaseQuantity(
      portion,
      servingSize: servingSize,
      packageSize: packageSize,
    );
  }

  NutrientVector get resolvedNutrients {
    if (kind == FoodEntryKind.quickEntry) {
      return nutrients;
    }
    final baseQuantity = resolvedBaseQuantity;
    if (baseQuantity == null) {
      throw StateError('Food Entry is missing a resolvable Portion.');
    }
    return nutrients.scale(baseQuantity / 100);
  }
}

class NutritionDayMealRecord {
  NutritionDayMealRecord({
    required this.meal,
    required Iterable<FoodEntryRecord> entries,
  }) : entries = List<FoodEntryRecord>.unmodifiable(entries);

  final MealRecord meal;
  final List<FoodEntryRecord> entries;

  NutrientTotals get totals => NutrientTotals.fromEntries(entries);
}

class NutritionDayRecord {
  NutritionDayRecord({
    required this.localDate,
    required Iterable<NutritionDayMealRecord> meals,
  }) : meals = List<NutritionDayMealRecord>.unmodifiable(meals);

  final NutritionDayDate localDate;
  final List<NutritionDayMealRecord> meals;

  NutrientTotals get totals => NutrientTotals.fromEntries(
        meals.expand((meal) => meal.entries),
      );
}

class NutrientTotal {
  const NutrientTotal({
    required this.id,
    required this.value,
    required this.unit,
    required this.isComplete,
  });

  final NutrientId id;
  final double value;
  final NutrientUnit unit;
  final bool isComplete;

  bool get isIncomplete => !isComplete;
}

class NutrientTotals {
  const NutrientTotals._(this._totals);

  factory NutrientTotals.fromEntries(Iterable<FoodEntryRecord> entries) {
    final values = <NutrientId, double>{
      for (final id in NutrientId.values) id: 0,
    };
    final complete = <NutrientId, bool>{
      for (final id in NutrientId.values) id: true,
    };

    for (final entry in entries) {
      final nutrients = entry.resolvedNutrients;
      for (final id in NutrientId.values) {
        final amount = nutrients[id];
        if (amount.isComplete) {
          values[id] = values[id]! + amount.value!;
        } else {
          complete[id] = false;
        }
      }
    }

    return NutrientTotals._(
      <NutrientId, NutrientTotal>{
        for (final id in NutrientId.values)
          id: NutrientTotal(
            id: id,
            value: values[id]!,
            unit: id.defaultUnit,
            isComplete: complete[id]!,
          ),
      },
    );
  }

  final Map<NutrientId, NutrientTotal> _totals;

  NutrientTotal operator [](NutrientId id) => _totals[id]!;

  Map<NutrientId, NutrientTotal> get totals {
    return Map<NutrientId, NutrientTotal>.unmodifiable(_totals);
  }
}

/// Where a day's derived total sits relative to a configured `Goal` target.
///
/// The order matters: [unknown] outranks every value status because an
/// unknown-aware total can never be compared to a target (`0 ≠ unknown`,
/// NUTRITION.md §4); [noGoal] means no target is configured for the nutrient.
enum NutrientGoalStatus {
  noGoal,
  unknown,
  below,
  met,
  over;
}

/// Derived goal progress for one nutrient: the day's computed [total] measured
/// against the configured [target]. This is **itself derived analytics**
/// (computed total vs configured target) and is never stored or synced;
/// the [NutritionGoalTarget] it reads is configuration, never a
/// stored total (NUTRITION.md §2).
///
/// Unknown-aware: when the [total] is incomplete the progress is [isUnknown]
/// and exposes no [ratio]/[remaining] — a missing nutrient must never be
/// coerced to a misleadingly precise comparison (NUTRITION.md §4). A genuinely
/// zero complete total stays distinct, yielding a real `0.0` ratio.
class NutrientGoalProgress {
  const NutrientGoalProgress._({
    required this.nutrient,
    required this.total,
    required this.target,
    required this.status,
    required this.ratio,
    required this.remaining,
  });

  factory NutrientGoalProgress.derive({
    required NutrientTotal total,
    required NutritionGoalTarget? target,
  }) {
    if (target == null) {
      return NutrientGoalProgress._(
        nutrient: total.id,
        total: total,
        target: null,
        status: NutrientGoalStatus.noGoal,
        ratio: null,
        remaining: null,
      );
    }
    if (total.isIncomplete) {
      return NutrientGoalProgress._(
        nutrient: total.id,
        total: total,
        target: target,
        status: NutrientGoalStatus.unknown,
        ratio: null,
        remaining: null,
      );
    }

    final targetValue = target.value;
    final ratio = targetValue == 0 ? null : total.value / targetValue;
    final remaining = targetValue - total.value;
    final NutrientGoalStatus status;
    if (total.value > targetValue) {
      status = NutrientGoalStatus.over;
    } else if (total.value == targetValue) {
      status = NutrientGoalStatus.met;
    } else {
      status = NutrientGoalStatus.below;
    }

    return NutrientGoalProgress._(
      nutrient: total.id,
      total: total,
      target: target,
      status: status,
      ratio: ratio,
      remaining: remaining,
    );
  }

  final NutrientId nutrient;
  final NutrientTotal total;
  final NutritionGoalTarget? target;
  final NutrientGoalStatus status;

  /// `total / target` for a complete total against a non-zero target, else
  /// `null` (no goal, an unknown total, or a zero target).
  final double? ratio;

  /// `target - total` for a complete, goaled total (negative when over), else
  /// `null`. A positive value is the amount still left to reach the target.
  final double? remaining;

  bool get hasGoal => target != null;
  bool get isUnknown => status == NutrientGoalStatus.unknown;

  /// The [ratio] clamped to `[0, 1]` for a progress ring/bar fill fraction,
  /// or `null` when no comparable ratio exists.
  double? get fillFraction {
    final value = ratio;
    if (value == null) {
      return null;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }
}

/// A contiguous inclusive span of `Nutrition Day`s to read totals/trends over.
/// Pure value type — it only enumerates calendar days; it stores nothing.
class NutritionDayRange {
  NutritionDayRange({
    required this.start,
    required this.end,
  }) {
    if (start.compareTo(end) > 0) {
      throw ArgumentError.value(
        end,
        'end',
        'Nutrition day range end must not precede its start.',
      );
    }
  }

  /// A window of [days] calendar days ending on (and including) [anchor].
  factory NutritionDayRange.trailing(
    NutritionDayDate anchor, {
    required int days,
  }) {
    if (days < 1) {
      throw ArgumentError.value(days, 'days', 'A range spans at least one day.');
    }
    return NutritionDayRange(
      start: anchor.addDays(-(days - 1)),
      end: anchor,
    );
  }

  final NutritionDayDate start;
  final NutritionDayDate end;

  int get dayCount {
    final startMidnight = DateTime.utc(start.year, start.month, start.day);
    final endMidnight = DateTime.utc(end.year, end.month, end.day);
    return endMidnight.difference(startMidnight).inDays + 1;
  }

  List<NutritionDayDate> get days {
    return <NutritionDayDate>[
      for (var offset = 0; offset < dayCount; offset += 1) start.addDays(offset),
    ];
  }

  bool contains(NutritionDayDate date) {
    return date.compareTo(start) >= 0 && date.compareTo(end) <= 0;
  }
}

/// One day's derived total for a single nutrient on a trend line. Preserves the
/// unknown/complete distinction so a quick entry that only recorded energy is
/// never plotted as a `0 g` dip for the nutrients it omitted (NUTRITION.md §4).
class NutritionTrendPoint {
  const NutritionTrendPoint({
    required this.localDate,
    required this.total,
  });

  final NutritionDayDate localDate;
  final NutrientTotal total;

  bool get isUnknown => total.isIncomplete;
  double? get plottableValue => isUnknown ? null : total.value;
}

/// A derived per-day trend for one nutrient across a [NutritionDayRange], with
/// the configured [target] carried as a reference line. Computed on demand over
/// `Food Entry` snapshots; nothing here is stored or synced.
///
/// Every requested day yields a point — days with no logged meals are
/// genuinely-zero complete totals, while days whose entries omitted the
/// nutrient are flagged unknown and held out of [completePoints] (the rendered
/// line) so the line never dips to a false zero.
class NutritionTrend {
  const NutritionTrend._({
    required this.nutrient,
    required this.range,
    required this.target,
    required this.points,
  });

  factory NutritionTrend.forNutrient({
    required NutrientId nutrient,
    required NutritionDayRange range,
    required Iterable<NutritionDayRecord> days,
    required NutritionGoalTarget? target,
  }) {
    final totalsByDate = <String, NutrientTotal>{
      for (final day in days)
        day.localDate.storageValue: day.totals[nutrient],
    };

    final points = <NutritionTrendPoint>[
      for (final date in range.days)
        NutritionTrendPoint(
          localDate: date,
          total: totalsByDate[date.storageValue] ??
              NutrientTotal(
                id: nutrient,
                value: 0,
                unit: nutrient.defaultUnit,
                isComplete: true,
              ),
        ),
    ];

    return NutritionTrend._(
      nutrient: nutrient,
      range: range,
      target: target,
      points: List<NutritionTrendPoint>.unmodifiable(points),
    );
  }

  final NutrientId nutrient;
  final NutritionDayRange range;
  final NutritionGoalTarget? target;
  final List<NutritionTrendPoint> points;

  /// The points with a comparable (complete) value — what the rendered line is
  /// drawn from. Unknown days are excluded so they never read as a false zero.
  List<NutritionTrendPoint> get completePoints {
    return <NutritionTrendPoint>[
      for (final point in points)
        if (!point.isUnknown) point,
    ];
  }

  bool get hasCompletePoints => completePoints.isNotEmpty;
}

/// One configured nutrition `Goal` target: a goalable `Nutrient` key from the
/// fixed registry, the user's chosen numeric target, and its unit.
///
/// This is **configuration**, never a stored derived value: the row only ever
/// holds the target the user typed, never a computed total (
/// NUTRITION.md §2).
class NutritionGoalTarget {
  const NutritionGoalTarget._({
    required this.nutrient,
    required this.value,
    required this.entered,
    required this.unit,
  });

  factory NutritionGoalTarget({
    required NutrientId nutrient,
    required double value,
    required String entered,
    NutrientUnit? unit,
  }) {
    if (!isGoalableNutrient(nutrient)) {
      throw ArgumentError.value(
        nutrient,
        'nutrient',
        'Nutrient is not goalable in v1 (energy + protein/carb/fat only).',
      );
    }
    if (!value.isFinite) {
      throw ArgumentError.value(
        value,
        'value',
        'Goal target value must be finite.',
      );
    }
    final normalizedEntered = entered.trim();
    if (normalizedEntered.isEmpty) {
      throw ArgumentError.value(
        entered,
        'entered',
        'Entered Goal target value must not be empty.',
      );
    }
    return NutritionGoalTarget._(
      nutrient: nutrient,
      value: value,
      entered: normalizedEntered,
      unit: unit ?? nutrient.defaultUnit,
    );
  }

  final NutrientId nutrient;
  final double value;
  final String entered;
  final NutrientUnit unit;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is NutritionGoalTarget &&
            runtimeType == other.runtimeType &&
            nutrient == other.nutrient &&
            value == other.value &&
            entered == other.entered &&
            unit == other.unit;
  }

  @override
  int get hashCode => Object.hash(nutrient, value, entered, unit);
}

/// The user's requested set of nutrition `Goal` targets, ahead of persistence.
/// At most one target per goalable `Nutrient`; clearing one is simply omitting
/// it (a normal write, NUTRITION.md §7).
class NutritionGoalDraft {
  NutritionGoalDraft({
    required Iterable<NutritionGoalTarget> targets,
  }) : targets = _indexTargets(targets);

  final Map<NutrientId, NutritionGoalTarget> targets;

  NutritionGoalTarget? targetFor(NutrientId nutrient) => targets[nutrient];

  static Map<NutrientId, NutritionGoalTarget> _indexTargets(
    Iterable<NutritionGoalTarget> targets,
  ) {
    final indexed = <NutrientId, NutritionGoalTarget>{};
    for (final target in targets) {
      if (indexed.containsKey(target.nutrient)) {
        throw ArgumentError.value(
          target.nutrient,
          'targets',
          'A nutrition Goal has at most one target per Nutrient.',
        );
      }
      indexed[target.nutrient] = target;
    }
    return Map<NutrientId, NutritionGoalTarget>.unmodifiable(indexed);
  }
}

/// A persisted nutrition `Goal` for one goalable `Nutrient` — an ordinary LWW
/// row (UUIDv7 [id], [updatedAt], [deletedAt]) that syncs alongside the other
/// nutrition rows (NUTRITION.md §7). It attaches to the **derived** nutrition
/// analytics, never to a `Metric`.
class NutritionGoalRecord {
  const NutritionGoalRecord({
    required this.id,
    required this.target,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final NutritionGoalTarget target;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  NutrientId get nutrient => target.nutrient;
  bool get isActive => deletedAt == null;
}

class LogQuickEntryResult {
  LogQuickEntryResult({
    required this.batchId,
    required this.mealId,
    required this.foodEntryId,
    Iterable<NutrientValidationIssue> warnings =
        const <NutrientValidationIssue>[],
  }) : warnings = List<NutrientValidationIssue>.unmodifiable(warnings);

  final String batchId;
  final String mealId;
  final String foodEntryId;
  final List<NutrientValidationIssue> warnings;
}

class LogFoodEntryResult {
  LogFoodEntryResult({
    required this.batchId,
    required this.mealId,
    required this.foodEntryId,
    Iterable<NutrientValidationIssue> warnings =
        const <NutrientValidationIssue>[],
  }) : warnings = List<NutrientValidationIssue>.unmodifiable(warnings);

  final String batchId;
  final String mealId;
  final String foodEntryId;
  final List<NutrientValidationIssue> warnings;
}

class NutrientValidationIssue {
  const NutrientValidationIssue({
    required this.field,
    required this.nutrient,
    required this.rule,
    required this.message,
    required this.limit,
  });

  factory NutrientValidationIssue.fromJson(Map<String, Object?> json) {
    final nutrientKey = _optionalString(json, 'nutrient');
    return NutrientValidationIssue(
      field: _requiredString(json, 'field'),
      nutrient: nutrientKey == null
          ? null
          : NutrientId.byStorageKey(nutrientKey),
      rule: _requiredString(json, 'rule'),
      message: _requiredString(json, 'message'),
      limit: json['limit'],
    );
  }

  final String field;
  final NutrientId? nutrient;
  final String rule;
  final String message;
  final Object? limit;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'field': field,
      'nutrient': nutrient?.storageKey,
      'rule': rule,
      'message': message,
      'limit': limit,
    };
  }
}

/// A persisted, **non-blocking** review flag carried by a materialized (e.g.
/// imported) `Food Entry`. A soft-warn from the shared two-tier validator
/// (NUTRITION.md §6) never blocks the import — it lands here as a flag the user
/// can review, mirroring the materialized soft-warn review flags for Sets
/// (INTEGRATIONS.md §10). This is a first version; generalizes it.
class NutritionReviewFlag {
  const NutritionReviewFlag({
    required this.rule,
    required this.message,
    this.nutrient,
  });

  factory NutritionReviewFlag.fromValidationIssue(NutrientValidationIssue issue) {
    return NutritionReviewFlag(
      rule: issue.rule,
      message: issue.message,
      nutrient: issue.nutrient,
    );
  }

  factory NutritionReviewFlag.fromJson(Map<String, Object?> json) {
    final nutrientKey = _optionalString(json, 'nutrient');
    return NutritionReviewFlag(
      rule: _requiredString(json, 'rule'),
      message: _requiredString(json, 'message'),
      nutrient: nutrientKey == null
          ? null
          : NutrientId.byStorageKey(nutrientKey),
    );
  }

  final String rule;
  final String message;
  final NutrientId? nutrient;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'rule': rule,
      'message': message,
      'nutrient': nutrient?.storageKey,
    };
  }

  static String encode(List<NutritionReviewFlag> flags) {
    return jsonEncode(flags.map((flag) => flag.toJson()).toList());
  }

  static List<NutritionReviewFlag> decode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const <NutritionReviewFlag>[];
    }
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      throw FormatException('Expected review flag list.', value);
    }
    return List<NutritionReviewFlag>.unmodifiable(
      decoded.map((item) {
        if (item is! Map) {
          throw FormatException('Expected review flag object.', item);
        }
        return NutritionReviewFlag.fromJson(Map<String, Object?>.from(item));
      }),
    );
  }
}

bool foodNameMatchesQuery(String name, String query) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty);
  if (terms.isEmpty) {
    return true;
  }

  final searchableName = name.toLowerCase();
  return terms.every(searchableName.contains);
}

String formatNutritionNumber(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.000001) {
    return rounded.toInt().toString();
  }
  return value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}

String nutrientUnitLabel(NutrientUnit unit) {
  return switch (unit) {
    NutrientUnit.kilocalorie => 'kcal',
    NutrientUnit.gram => 'g',
    NutrientUnit.milligram => 'mg',
    NutrientUnit.microgram => 'mcg',
    NutrientUnit.milliliter => 'ml',
  };
}

String portionUnitLabel(PortionUnit unit) {
  return switch (unit) {
    PortionUnit.gram => 'g',
    PortionUnit.milliliter => 'ml',
    PortionUnit.ounce => 'oz',
    PortionUnit.fluidOunce => 'fl oz',
    PortionUnit.serving => 'serving',
    PortionUnit.package => 'package',
  };
}

List<PortionUnit> availablePortionUnitsForFood({
  required bool isLiquid,
  required String? servingLabel,
  required double? servingSize,
  required double? packageSize,
}) {
  final units = <PortionUnit>[
    if (isLiquid) PortionUnit.milliliter else PortionUnit.gram,
    if (isLiquid) PortionUnit.fluidOunce else PortionUnit.ounce,
  ];
  if (servingSize != null && servingLabel != null) {
    units.add(PortionUnit.serving);
  }
  if (packageSize != null) {
    units.add(PortionUnit.package);
  }
  return List<PortionUnit>.unmodifiable(units);
}

double resolvePortionBaseQuantity(
  Portion portion, {
  required double? servingSize,
  required double? packageSize,
}) {
  return _resolveBaseQuantity(
    portion,
    servingSize: servingSize,
    packageSize: packageSize,
  );
}

double _resolveBaseQuantity(
  Portion portion, {
  required double? servingSize,
  required double? packageSize,
}) {
  return switch (portion.unit) {
    PortionUnit.gram || PortionUnit.milliliter => portion.value,
    PortionUnit.ounce => portion.value * 28.349523125,
    PortionUnit.fluidOunce => portion.value * 29.5735295625,
    PortionUnit.serving => portion.value *
        _requiredPortionSize(
          servingSize,
          PortionUnit.serving,
        ),
    PortionUnit.package => portion.value *
        _requiredPortionSize(
          packageSize,
          PortionUnit.package,
        ),
  };
}

double _requiredPortionSize(double? value, PortionUnit unit) {
  if (value != null) {
    return value;
  }
  throw StateError('Portion unit ${unit.name} is not available.');
}

String _formatDerivedValue(double value) {
  final fixed = value.toStringAsFixed(6);
  return fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  throw FormatException('Expected string field $key.', json);
}

double _requiredDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected numeric field $key.', json);
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected bool field $key.', json);
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('Expected optional string field $key.', json);
}

double? _optionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected optional numeric field $key.', json);
}
