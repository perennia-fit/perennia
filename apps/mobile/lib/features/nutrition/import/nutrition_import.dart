import '../../../domain/nutrition/nutrition.dart';
import '../../../domain/nutrition/nutrition_import.dart';

export '../../../domain/nutrition/nutrition_import.dart';

/// The on-device ("edge") nutrition-import seam (NUTRITION.md §9; the
/// Acquisition → Ingestion seam of INTEGRATIONS.md §1). An [NutritionImportAdapter]
/// only *acquires + maps* — it parses a provider export and produces a
/// provider-neutral [NutritionImportBatch] of canonical-shaped draft rows. The
/// repository is the only layer that *lands* them, so the adapter is pure and
/// unit-testable without Drift or a native file picker.
///
/// This interface is the reuse point: (more providers) adds new
/// adapters, and (the shared contract) hooks onto [NutritionImportBatch].
abstract interface class NutritionImportAdapter {
  /// The originating provider's human-facing name (e.g. `Cronometer`). The
  /// landing path resolves it to a `Food Source`: a recognised provider takes
  /// its specific [FoodSource], an unrecognised one takes the generic
  /// [FoodSource.imported] PRESERVING this exact string (NUTRITION.md §9;
  /// INTEGRATIONS.md §6 preserved-vendor-string rule). This single [provider]
  /// is the cross-cutting provenance input every importer supplies.
  String get provider;

  /// Parse + map a picked file's raw [content] into a provider-neutral batch.
  /// Pure: never touches storage, the network, or the native picker.
  NutritionImportBatch parse(String content);
}

/// Abstraction over the native file picker so the parse + map + land path is
/// exercised in `flutter test` without the platform plugin (§5 of the brief).
/// A real implementation returns the picked file's decoded text; tests provide
/// a canned string.
abstract interface class NutritionImportFilePicker {
  /// Returns the decoded text of a file the user picked, or null if cancelled.
  Future<String?> pickTextFile();
}

/// Whether an exported [dateText] parses as an ISO date-time carrying a time
/// of day (`2024-03-05T08:30`, `2024-03-05 08:30`), not a bare date. An
/// importer gives a Meal `instant` time precision only when it does; a bare
/// date only knows its day (docs/designs/meal-logging.md §1, time precision).
bool importTextHasTimeOfDay(String dateText) {
  final text = dateText.trim();
  return DateTime.tryParse(text) != null &&
      RegExp(r'^\S+?[Tt ]\d').hasMatch(text);
}
