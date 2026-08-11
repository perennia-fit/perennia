import '../../../domain/nutrition/nutrition.dart';
import 'csv_parser.dart';
import 'nutrition_import.dart';

/// Raised when a provider export cannot be parsed/mapped. Hard-stops the whole
/// import (nothing lands) — distinct from a single row failing the shared
/// validator's hard-reject caps, which only drops that row (NUTRITION.md §6).
class NutritionImportFormatException implements Exception {
  const NutritionImportFormatException(this.message);

  final String message;

  @override
  String toString() => 'NutritionImportFormatException: $message';
}

/// Parses a Cronometer "Food Entries" / "Servings" CSV export (the free, rich,
/// ToS-safe path, NUTRITION.md §9) into a provider-neutral
/// [NutritionImportBatch]. Pure: no storage, no network, no native picker.
///
/// Cronometer reports each nutrient as the *absolute* amount for the row's
/// `Amount` serving. To land a self-describing snapshot (NUTRITION.md §1.1) we
/// normalize to a per-100 vector and carry the serving as the entry `Portion`,
/// so later catalogue changes can never rewrite the logged value.
class CronometerCsvImportAdapter implements NutritionImportAdapter {
  const CronometerCsvImportAdapter();

  @override
  String get provider => 'Cronometer';

  /// Cronometer column header -> nutrient registry id. Headers are matched
  /// case-insensitively and unit-suffix-tolerantly; a column not in this map is
  /// ignored, and a registry nutrient with no column is left *unknown*.
  static const _columnToNutrient = <String, NutrientId>{
    'energy (kcal)': NutrientId.energy,
    'energy': NutrientId.energy,
    'protein (g)': NutrientId.protein,
    'carbs (g)': NutrientId.carbohydrate,
    'net carbs (g)': NutrientId.carbohydrate,
    'fat (g)': NutrientId.fat,
    'saturated (g)': NutrientId.saturatedFat,
    'monounsaturated (g)': NutrientId.monounsaturatedFat,
    'polyunsaturated (g)': NutrientId.polyunsaturatedFat,
    'fiber (g)': NutrientId.fiber,
    'sugars (g)': NutrientId.sugar,
    'sodium (mg)': NutrientId.sodium,
    'cholesterol (mg)': NutrientId.cholesterol,
    'vitamin a (µg)': NutrientId.vitaminA,
    'vitamin a (mcg)': NutrientId.vitaminA,
    'vitamin c (mg)': NutrientId.vitaminC,
    'vitamin d (iu)': NutrientId.vitaminD,
    'vitamin d (µg)': NutrientId.vitaminD,
    'vitamin e (mg)': NutrientId.vitaminE,
    'vitamin k (µg)': NutrientId.vitaminK,
    'vitamin k (mcg)': NutrientId.vitaminK,
    'thiamine (mg)': NutrientId.thiamin,
    'thiamin (mg)': NutrientId.thiamin,
    'riboflavin (mg)': NutrientId.riboflavin,
    'niacin (mg)': NutrientId.niacin,
    'vitamin b6 (mg)': NutrientId.vitaminB6,
    'folate (µg)': NutrientId.folate,
    'folate (mcg)': NutrientId.folate,
    'vitamin b12 (µg)': NutrientId.vitaminB12,
    'vitamin b12 (mcg)': NutrientId.vitaminB12,
    'calcium (mg)': NutrientId.calcium,
    'iron (mg)': NutrientId.iron,
    'magnesium (mg)': NutrientId.magnesium,
    'phosphorus (mg)': NutrientId.phosphorus,
    'potassium (mg)': NutrientId.potassium,
    'zinc (mg)': NutrientId.zinc,
    'copper (mg)': NutrientId.copper,
    'manganese (mg)': NutrientId.manganese,
    'selenium (µg)': NutrientId.selenium,
    'selenium (mcg)': NutrientId.selenium,
    'caffeine (mg)': NutrientId.caffeine,
    'water (g)': NutrientId.water,
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

    final foodNameColumn = _firstColumn(headerIndex, const [
      'food name',
      'food',
      'name',
    ]);
    final amountColumn = _firstColumn(headerIndex, const [
      'amount',
      'quantity',
    ]);
    if (foodNameColumn == null || amountColumn == null) {
      throw const NutritionImportFormatException(
        'Not a recognized Cronometer export: missing a Food Name / Amount '
        'column.',
      );
    }
    final groupColumn = _firstColumn(headerIndex, const ['group', 'category']);
    final dayColumn = _firstColumn(headerIndex, const ['day', 'date']);
    final timeColumn = _firstColumn(headerIndex, const ['time']);

    // Map each present nutrient column to its registry id once.
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
      final name = _cell(cells, foodNameColumn).trim();
      if (name.isEmpty) {
        continue;
      }
      final amount = _parseAmount(_cell(cells, amountColumn));
      if (amount == null) {
        // A row whose serving cannot be parsed cannot be normalized to per-100.
        continue;
      }

      final group = groupColumn == null
          ? 'Imported'
          : _orDefault(_cell(cells, groupColumn).trim(), 'Imported');
      final dayText = dayColumn == null ? '' : _cell(cells, dayColumn).trim();
      final timeText = timeColumn == null ? '' : _cell(cells, timeColumn).trim();
      final startedAt = _parseTimestamp(dayText, timeText);
      final localDate = NutritionDayDate.fromDateTime(startedAt);
      final mealKey = '${localDate.storageValue}|$group';

      final perHundred = <NutrientId, NutrientAmount>{};
      for (final column in nutrientColumns.entries) {
        final id = column.value;
        // Last-writer-wins if two columns map to the same id and one is blank.
        if (perHundred[id]?.isComplete ?? false) {
          continue;
        }
        final raw = _cell(cells, column.key).trim();
        final value = _parseNumber(raw);
        if (value == null) {
          perHundred.putIfAbsent(id, () => NutrientAmount.unknown(id.defaultUnit));
          continue;
        }
        final per100 = value / (amount.value / 100);
        perHundred[id] = NutrientAmount.complete(
          value: per100,
          entered: _formatNumber(per100),
          unit: id.defaultUnit,
        );
      }

      final entry = NutritionImportFoodEntry(
        externalId: _externalId(
          dayText: dayText,
          timeText: timeText,
          group: group,
          name: name,
          amountText: _cell(cells, amountColumn).trim(),
          rowNumber: rowNumber,
        ),
        name: name,
        nutrientsPer100: NutrientVector.full(perHundred),
        isLiquid: amount.isLiquid,
        portion: Portion(
          value: amount.value,
          entered: _formatNumber(amount.value),
          unit: amount.isLiquid ? PortionUnit.milliliter : PortionUnit.gram,
        ),
      );

      final accumulator = mealsByKey.putIfAbsent(mealKey, () {
        orderedKeys.add(mealKey);
        return _MealAccumulator(
          mealType: group,
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

  static String _normalizeHeader(String value) {
    return value.trim().toLowerCase().replaceAll('µ', 'µ');
  }

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

  static String _orDefault(String value, String fallback) {
    return value.isEmpty ? fallback : value;
  }

  static _ParsedAmount? _parseAmount(String raw) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) {
      return null;
    }
    final match = RegExp(r'^([0-9]*\.?[0-9]+)\s*([a-z]*)$').firstMatch(text);
    if (match == null) {
      return null;
    }
    final value = double.tryParse(match.group(1)!);
    if (value == null || !value.isFinite || value <= 0) {
      return null;
    }
    final unit = match.group(2) ?? '';
    final isLiquid = unit == 'ml' || unit == 'milliliter' || unit == 'l';
    final scaled = unit == 'l' ? value * 1000 : value;
    return _ParsedAmount(value: scaled, isLiquid: isLiquid);
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

  static DateTime _parseTimestamp(String dayText, String timeText) {
    final day = DateTime.tryParse(dayText.trim());
    if (day == null) {
      return DateTime(1970);
    }
    final timeMatch =
        RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(timeText.trim());
    final hour = timeMatch == null ? 0 : int.parse(timeMatch.group(1)!);
    final minute = timeMatch == null ? 0 : int.parse(timeMatch.group(2)!);
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  static String _externalId({
    required String dayText,
    required String timeText,
    required String group,
    required String name,
    required String amountText,
    required int rowNumber,
  }) {
    // Stable across re-imports of the same export: identity is the row's
    // semantic content, not its file position. Row number disambiguates true
    // duplicate lines so they don't collapse into one.
    return [dayText, timeText, group, name, amountText, rowNumber.toString()]
        .map((part) => part.replaceAll('|', r'\|'))
        .join('|');
  }
}

class _ParsedAmount {
  const _ParsedAmount({required this.value, required this.isLiquid});

  final double value;
  final bool isLiquid;
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
