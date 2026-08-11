import '../../../domain/nutrition/nutrition.dart';
import 'cronometer_csv_import_adapter.dart' show NutritionImportFormatException;
import 'csv_parser.dart';
import 'nutrition_import.dart';

/// Parses a MyFitnessPal "Nutrition" CSV export (the premium-gated, ToS-safe
/// file path, NUTRITION.md §9) into a provider-neutral [NutritionImportBatch].
/// Pure: no storage, no network, no native picker.
///
/// MyFitnessPal reports each row as the **already-totalled** value for the
/// quantity the user logged — there is no separate amount/serving column. To
/// land a self-describing snapshot (NUTRITION.md §1.1) without fabricating a
/// gram weight the provider never reported, each row becomes a single
/// `serving` portion whose base quantity is 100, so the reported totals are the
/// per-100 vector verbatim. Provider quirks (the column set, meal names, the
/// `MM/DD/YYYY` date) are quarantined here; the downstream pipeline never
/// reshapes per provider (INTEGRATIONS.md §14).
///
/// The free export reports far fewer micronutrient columns than Cronometer, so
/// most micros are simply absent and land *unknown* — rendered "—", never zero
/// (`0 != unknown`, NUTRITION.md §4).
class MyFitnessPalCsvImportAdapter implements NutritionImportAdapter {
  const MyFitnessPalCsvImportAdapter();

  @override
  String get provider => 'MyFitnessPal';

  /// MyFitnessPal column header -> nutrient registry id. Headers are matched
  /// case-insensitively and unit-suffix-tolerantly. A column not in this map is
  /// ignored; a registry nutrient with no column is left *unknown*. The export
  /// covers macros plus only a handful of micros (sodium, potassium,
  /// cholesterol, and the legacy %DV pair vitamin A / vitamin C / calcium /
  /// iron — which MFP exports as milligram/microgram amounts in newer exports);
  /// the rest of the registry stays unknown.
  static const _columnToNutrient = <String, NutrientId>{
    'calories': NutrientId.energy,
    'energy (kcal)': NutrientId.energy,
    'protein (g)': NutrientId.protein,
    'protein': NutrientId.protein,
    'carbohydrates (g)': NutrientId.carbohydrate,
    'carbohydrates': NutrientId.carbohydrate,
    'carbs (g)': NutrientId.carbohydrate,
    'fat (g)': NutrientId.fat,
    'fat': NutrientId.fat,
    'saturated fat (g)': NutrientId.saturatedFat,
    'saturated fat': NutrientId.saturatedFat,
    'polyunsaturated fat (g)': NutrientId.polyunsaturatedFat,
    'polyunsaturated fat': NutrientId.polyunsaturatedFat,
    'monounsaturated fat (g)': NutrientId.monounsaturatedFat,
    'monounsaturated fat': NutrientId.monounsaturatedFat,
    'fiber (g)': NutrientId.fiber,
    'fiber': NutrientId.fiber,
    'sugar (g)': NutrientId.sugar,
    'sugar': NutrientId.sugar,
    'sodium (mg)': NutrientId.sodium,
    'sodium': NutrientId.sodium,
    'cholesterol (mg)': NutrientId.cholesterol,
    'cholesterol': NutrientId.cholesterol,
    'potassium (mg)': NutrientId.potassium,
    'potassium': NutrientId.potassium,
  };

  @override
  NutritionImportBatch parse(String content) {
    final rows = parseCsv(content);
    if (rows.isEmpty) {
      return NutritionImportBatch.empty;
    }

    final header = rows.first.map(_normalizeHeader).toList(growable: false);
    final headerIndex = <String, int>{};
    for (var i = 0; i < header.length; i += 1) {
      headerIndex.putIfAbsent(header[i], () => i);
    }

    final foodColumn = _firstColumn(headerIndex, const [
      'food',
      'food name',
      'name',
    ]);
    final caloriesColumn = _firstColumn(headerIndex, const [
      'calories',
      'energy (kcal)',
    ]);
    if (foodColumn == null || caloriesColumn == null) {
      throw const NutritionImportFormatException(
        'Not a recognized MyFitnessPal export: missing a Food / Calories '
        'column.',
      );
    }
    final mealColumn = _firstColumn(headerIndex, const ['meal']);
    final dateColumn = _firstColumn(headerIndex, const ['date']);

    final nutrientColumns = <int, NutrientId>{};
    for (final entry in headerIndex.entries) {
      final id = _columnToNutrient[entry.key];
      if (id != null) {
        nutrientColumns[entry.value] = id;
      }
    }

    final mealsByKey = <String, _MealAccumulator>{};
    final orderedKeys = <String>[];

    for (var rowNumber = 1; rowNumber < rows.length; rowNumber += 1) {
      final cells = rows[rowNumber];
      final name = _cell(cells, foodColumn).trim();
      if (name.isEmpty) {
        continue;
      }

      final mealName = mealColumn == null
          ? 'Imported'
          : _orDefault(_cell(cells, mealColumn).trim(), 'Imported');
      final dateText = dateColumn == null ? '' : _cell(cells, dateColumn).trim();
      final startedAt = _parseDate(dateText);
      final localDate = NutritionDayDate.fromDateTime(startedAt);
      final mealType = _canonicalMealType(mealName);
      final mealKey = '${localDate.storageValue}|$mealType';

      final perHundred = <NutrientId, NutrientAmount>{};
      for (final column in nutrientColumns.entries) {
        final id = column.value;
        if (perHundred[id]?.isComplete ?? false) {
          continue;
        }
        final raw = _cell(cells, column.key).trim();
        final value = _parseNumber(raw);
        if (value == null) {
          perHundred.putIfAbsent(id, () => NutrientAmount.unknown(id.defaultUnit));
          continue;
        }
        perHundred[id] = NutrientAmount.complete(
          value: value,
          entered: _formatNumber(value),
          unit: id.defaultUnit,
        );
      }

      final entry = NutritionImportFoodEntry(
        externalId: _externalId(
          dateText: dateText,
          meal: mealType,
          name: name,
          rowNumber: rowNumber,
        ),
        name: name,
        nutrientsPer100: NutrientVector.full(perHundred),
        isLiquid: false,
        // The reported values are the per-serving total; a 1-serving portion
        // whose base quantity is 100 lands them verbatim (see class doc).
        portion: Portion(
          value: 1,
          entered: '1',
          unit: PortionUnit.serving,
        ),
        servingLabel: 'serving',
        servingSize: 100,
      );

      final accumulator = mealsByKey.putIfAbsent(mealKey, () {
        orderedKeys.add(mealKey);
        return _MealAccumulator(
          mealType: mealType,
          startedAt: startedAt,
          localDate: localDate,
        );
      });
      accumulator.entries.add(entry);
    }

    final meals = <NutritionImportMeal>[
      for (final key in orderedKeys) mealsByKey[key]!.toMeal(),
    ];
    return NutritionImportBatch(meals: meals);
  }

  static String _normalizeHeader(String value) => value.trim().toLowerCase();

  static int? _firstColumn(Map<String, int> headerIndex, List<String> names) {
    for (final name in names) {
      final index = headerIndex[name];
      if (index != null) {
        return index;
      }
    }
    return null;
  }

  static String _cell(List<String> cells, int index) {
    if (index < 0 || index >= cells.length) {
      return '';
    }
    return cells[index];
  }

  static String _orDefault(String value, String fallback) =>
      value.isEmpty ? fallback : value;

  /// MyFitnessPal meal names are free text but conventionally Breakfast /
  /// Lunch / Dinner / Snacks. Title-case them so the canonical meal grouping is
  /// stable regardless of the export's casing.
  static String _canonicalMealType(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'Imported';
    }
    return trimmed
        .split(RegExp(r'\s+'))
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }

  static double? _parseNumber(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    return double.tryParse(raw.replaceAll(',', ''));
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    final fixed = value.toStringAsFixed(6);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// MyFitnessPal exports dates as `MM/DD/YYYY` (US) or ISO `YYYY-MM-DD`.
  /// Normalise both into the canonical local day (INTEGRATIONS.md §14).
  static DateTime _parseDate(String dateText) {
    final text = dateText.trim();
    if (text.isEmpty) {
      return DateTime(1970);
    }
    final iso = DateTime.tryParse(text);
    if (iso != null) {
      return DateTime(iso.year, iso.month, iso.day);
    }
    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
    if (slash != null) {
      final month = int.parse(slash.group(1)!);
      final day = int.parse(slash.group(2)!);
      final year = int.parse(slash.group(3)!);
      return DateTime(year, month, day);
    }
    return DateTime(1970);
  }

  static String _externalId({
    required String dateText,
    required String meal,
    required String name,
    required int rowNumber,
  }) {
    return [dateText, meal, name, rowNumber.toString()]
        .map((part) => part.replaceAll('|', r'\|'))
        .join('|');
  }
}

class _MealAccumulator {
  _MealAccumulator({
    required this.mealType,
    required this.startedAt,
    required this.localDate,
  });

  final String mealType;
  final DateTime startedAt;
  final NutritionDayDate localDate;
  final List<NutritionImportFoodEntry> entries = <NutritionImportFoodEntry>[];

  NutritionImportMeal toMeal() {
    return NutritionImportMeal(
      mealType: mealType,
      startedAt: startedAt,
      localDate: localDate,
      entries: List<NutritionImportFoodEntry>.unmodifiable(entries),
    );
  }
}
