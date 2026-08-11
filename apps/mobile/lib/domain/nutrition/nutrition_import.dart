import 'nutrition.dart';

/// Provider-neutral, canonical-shaped nutrition-import payload and result
/// types. These live in the domain so both the edge adapters (feature layer)
/// and the landing path (data/repository layer) can depend on them without
/// inverting the architecture's layering. This is the seam (more
/// providers) and (the shared contract) reuse.

/// Outcome of resolving an import provider to a `Food Source` registry value
/// (the cross-cutting provenance rule every importer obeys, NUTRITION.md §9):
///
/// - a **recognised** provider resolves to its **specific** [FoodSource] enum
///   case ([preservedProvider] is null — the enum value already names it), and
/// - an **unrecognised** provider resolves to the **generic** [FoodSource.imported]
///   origin while [preservedProvider] keeps the **exact provider string** for
///   display and later promotion, mirroring INTEGRATIONS.md §6's
///   preserved-vendor-string rule.
///
/// [importSource] is the stable, normalised idempotency-key `source` (the first
/// half of the `(source, externalId)` dedup key) — distinct from the
/// human-facing [preservedProvider].
class FoodSourceResolution {
  const FoodSourceResolution({
    required this.foodSource,
    required this.importSource,
    this.preservedProvider,
  });

  final FoodSource foodSource;
  final String importSource;
  final String? preservedProvider;
}

/// The recognised-provider registry: a normalised provider id -> its specific
/// [FoodSource]. A provider not in this map lands as the generic
/// [FoodSource.imported] origin with its provider string preserved. New
/// recognised providers extend this map rather than the call sites.
const Map<String, FoodSource> _recognisedProviders = <String, FoodSource>{
  'cronometer': FoodSource.cronometer,
  'myfitnesspal': FoodSource.myFitnessPal,
  'yazio': FoodSource.yazio,
  'lifesum': FoodSource.lifesum,
};

/// Normalise a free-text provider string to a stable id usable as the import
/// dedup `source` and for recognition lookup: lower-cased, trimmed, runs of
/// non-alphanumerics collapsed to a single hyphen.
String normalizeImportProvider(String provider) {
  return provider
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Resolve an import [provider] string to a [FoodSourceResolution]. A
/// recognised provider takes its specific [FoodSource]; an unrecognised one
/// takes [FoodSource.imported] with the exact (trimmed) provider string
/// preserved (NUTRITION.md §9; INTEGRATIONS.md §6). Throws [ArgumentError] for
/// a blank provider — an import always originates from some provider.
FoodSourceResolution resolveImportedFoodSource(String provider) {
  final trimmed = provider.trim();
  final normalized = normalizeImportProvider(provider);
  if (trimmed.isEmpty || normalized.isEmpty) {
    throw ArgumentError.value(
      provider,
      'provider',
      'An import provider string must not be blank.',
    );
  }
  final recognised = _recognisedProviders[normalized];
  if (recognised != null) {
    return FoodSourceResolution(
      foodSource: recognised,
      importSource: normalized,
      preservedProvider: null,
    );
  }
  return FoodSourceResolution(
    foodSource: FoodSource.imported,
    importSource: normalized,
    preservedProvider: trimmed,
  );
}

/// A provider-neutral import payload: ordered [meals], each grouped by the
/// provider's own meal grouping, each carrying ordered read-only
/// [NutritionImportFoodEntry] rows.
class NutritionImportBatch {
  NutritionImportBatch({
    required Iterable<NutritionImportMeal> meals,
  }) : meals = List<NutritionImportMeal>.unmodifiable(meals);

  static final empty = NutritionImportBatch(meals: <NutritionImportMeal>[]);

  final List<NutritionImportMeal> meals;

  bool get isEmpty => meals.every((meal) => meal.entries.isEmpty);

  int get entryCount =>
      meals.fold<int>(0, (total, meal) => total + meal.entries.length);
}

/// One imported `Meal` grouping: a meal-type label, the local day/time it
/// occurred, and its read-only entries.
class NutritionImportMeal {
  NutritionImportMeal({
    required this.mealType,
    required this.startedAt,
    required this.localDate,
    required Iterable<NutritionImportFoodEntry> entries,
  }) : entries = List<NutritionImportFoodEntry>.unmodifiable(entries);

  final String mealType;
  final DateTime startedAt;
  final NutritionDayDate localDate;
  final List<NutritionImportFoodEntry> entries;
}

/// One imported `Food Entry`: a self-describing nutrient snapshot at import
/// time (NUTRITION.md §1.1), plus the stable [externalId] that — with the
/// adapter's `importSource` — keys idempotent re-import (NUTRITION.md §7).
class NutritionImportFoodEntry {
  const NutritionImportFoodEntry({
    required this.externalId,
    required this.name,
    required this.nutrientsPer100,
    required this.isLiquid,
    required this.portion,
    this.servingLabel,
    this.servingSize,
    this.packageSize,
  });

  /// Stable per-row identity within the provider's export. Combined with the
  /// adapter's `importSource` it forms the `(source, externalId)` dedup key:
  /// re-importing the same/overlapping export updates rather than duplicates.
  final String externalId;
  final String name;

  /// Per-100 nutrient vector; a column the provider did not report is an
  /// *unknown* amount, never a zero (`0 != unknown`, NUTRITION.md §4).
  final NutrientVector nutrientsPer100;
  final bool isLiquid;
  final Portion portion;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;
}

/// Raised by the landing path when nutrition import is not consented on this
/// device. The importer refuses to run and lands nothing (NUTRITION.md §9;
/// INTEGRATIONS.md §2 placement rule).
class NutritionImportConsentRequiredException implements Exception {
  const NutritionImportConsentRequiredException();

  @override
  String toString() =>
      'NutritionImportConsentRequiredException: nutrition import is not '
      'consented on this device.';
}

/// Raised when something tries to edit an imported `Food Entry` in place.
/// Imported entries are **read-only immutable observations** (NUTRITION.md §7,
/// mirroring `Reading` editability per): the correction path is
/// delete-and-add-a-manual-entry, never an in-place edit. Re-importing refreshes
/// the observation idempotently; it does not "edit" it.
class ImportedEntryImmutableException implements Exception {
  const ImportedEntryImmutableException(this.foodEntryId);

  final String foodEntryId;

  @override
  String toString() =>
      'ImportedEntryImmutableException: imported Food Entry $foodEntryId is a '
      'read-only observation; delete it and add a manual entry to correct it.';
}

/// Outcome of landing a [NutritionImportBatch] as one reversible Activity Log
/// batch. [importedCount] new + [updatedCount] updated entries landed;
/// [skippedTombstoned] is entries skipped because a prior delete tombstone must
/// not be resurrected; [rejectedCount] is rows dropped by the shared
/// validator's hard-reject caps while the rest still landed (NUTRITION.md §6).
class NutritionImportResult {
  NutritionImportResult({
    required this.batchId,
    required Iterable<String> mealIds,
    required Iterable<String> foodEntryIds,
    required this.importedCount,
    required this.updatedCount,
    required this.skippedTombstoned,
    required this.rejectedCount,
    this.reviewFlagCount = 0,
  })  : mealIds = List<String>.unmodifiable(mealIds),
        foodEntryIds = List<String>.unmodifiable(foodEntryIds);

  final String batchId;
  final List<String> mealIds;
  final List<String> foodEntryIds;
  final int importedCount;
  final int updatedCount;
  final int skippedTombstoned;
  final int rejectedCount;
  final int reviewFlagCount;

  int get landedCount => importedCount + updatedCount;
}
