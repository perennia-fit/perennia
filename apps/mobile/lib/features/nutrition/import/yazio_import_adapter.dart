import 'dart:convert';

import '../../../domain/nutrition/nutrition.dart';
import 'cronometer_csv_import_adapter.dart' show NutritionImportFormatException;
import 'nutrition_import.dart';

/// Parses a Yazio GDPR data export into a provider-neutral
/// [NutritionImportBatch]. Yazio's "consumed items" export is JSON: a list of
/// records (or an object wrapping one under `consumed_items` / `items` /
/// `data`), each with a date, a daytime/meal, a product name, an `amount` in
/// grams, and a `nutrients` map keyed by Yazio's nutrient ids. Pure: no
/// storage, no network, no native picker.
///
/// Provider quirks quarantined here (INTEGRATIONS.md §14):
/// - **Energy is reported in kilojoules**, normalised to kcal.
/// - Nutrient ids use Yazio's dotted naming (`energy.energy`,
///   `nutrient.protein`, …) and grams/milligrams per Yazio's conventions.
/// - The `daytime` enum (`breakfast` / `lunch` / `dinner` / `snack`) maps to a
///   canonical meal name; the ISO date maps to the local day.
///
/// Each record's absolute nutrient amounts (for its `amount`-gram serving) are
/// normalised to a per-100 vector so the snapshot is self-describing
/// (NUTRITION.md §1.1). A nutrient Yazio does not report is left *unknown*,
/// never zero (`0 != unknown`, NUTRITION.md §4).
class YazioImportAdapter implements NutritionImportAdapter {
  const YazioImportAdapter();

  @override
  String get provider => 'Yazio';

  static const double _kjPerKcal = 4.184;

  /// Yazio nutrient id -> registry id. A key not present is ignored; a registry
  /// nutrient with no key is left unknown.
  static const _keyToNutrient = <String, NutrientId>{
    'nutrient.protein': NutrientId.protein,
    'nutrient.carb': NutrientId.carbohydrate,
    'nutrient.fat': NutrientId.fat,
    'nutrient.saturatedfat': NutrientId.saturatedFat,
    'nutrient.monounsaturatedfat': NutrientId.monounsaturatedFat,
    'nutrient.polyunsaturatedfat': NutrientId.polyunsaturatedFat,
    'nutrient.dietaryfiber': NutrientId.fiber,
    'nutrient.fiber': NutrientId.fiber,
    'nutrient.sugar': NutrientId.sugar,
    'nutrient.sodium': NutrientId.sodium,
    'nutrient.cholesterol': NutrientId.cholesterol,
    'nutrient.potassium': NutrientId.potassium,
    'nutrient.calcium': NutrientId.calcium,
    'nutrient.iron': NutrientId.iron,
    'mineral.sodium': NutrientId.sodium,
    'mineral.potassium': NutrientId.potassium,
    'mineral.calcium': NutrientId.calcium,
    'mineral.iron': NutrientId.iron,
    'vitamin.c': NutrientId.vitaminC,
    'vitamin.a': NutrientId.vitaminA,
  };

  @override
  NutritionImportBatch parse(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return NutritionImportBatch.empty;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (error) {
      throw NutritionImportFormatException(
        'Not a recognized Yazio export: invalid JSON (${error.message}).',
      );
    }

    final records = _extractRecords(decoded);
    if (records == null) {
      throw const NutritionImportFormatException(
        'Not a recognized Yazio export: expected a list of consumed items.',
      );
    }

    final mealsByKey = <String, _MealAccumulator>{};
    final orderedKeys = <String>[];

    for (var rowNumber = 0; rowNumber < records.length; rowNumber += 1) {
      final record = records[rowNumber];
      if (record is! Map) {
        continue;
      }
      final map = record.cast<String, Object?>();
      final name = _string(map, const ['name', 'product_name', 'title']).trim();
      if (name.isEmpty) {
        continue;
      }
      final amount = _double(map, const ['amount', 'serving_quantity']);
      if (amount == null || amount <= 0) {
        // Without a positive gram amount we cannot normalise to per-100.
        continue;
      }

      final dateText =
          _string(map, const ['date', 'consumed_at', 'datetime']).trim();
      final startedAt = _parseDate(dateText);
      final localDate = NutritionDayDate.fromDateTime(startedAt);
      final mealType = _canonicalMealType(
        _string(map, const ['daytime', 'meal', 'meal_type']),
      );
      final mealKey = '${localDate.storageValue}|$mealType';

      final nutrients = _nutrientMap(map);
      final perHundred = <NutrientId, NutrientAmount>{};

      // Energy: kJ -> kcal, normalised to per-100.
      final energyKj = _nutrientValue(nutrients, const [
        'energy.energy',
        'energy',
      ]);
      if (energyKj != null) {
        final kcalPer100 = (energyKj / _kjPerKcal) / (amount / 100);
        perHundred[NutrientId.energy] = NutrientAmount.complete(
          value: kcalPer100,
          entered: _formatNumber(kcalPer100),
          unit: NutrientId.energy.defaultUnit,
        );
      }

      for (final entry in _keyToNutrient.entries) {
        final id = entry.value;
        if (perHundred[id]?.isComplete ?? false) {
          continue;
        }
        final value = _nutrientValue(nutrients, [entry.key]);
        if (value == null) {
          perHundred.putIfAbsent(id, () => NutrientAmount.unknown(id.defaultUnit));
          continue;
        }
        final per100 = value / (amount / 100);
        perHundred[id] = NutrientAmount.complete(
          value: per100,
          entered: _formatNumber(per100),
          unit: id.defaultUnit,
        );
      }

      final isLiquid = _bool(map, const ['is_liquid', 'liquid']) ?? false;
      final entry = NutritionImportFoodEntry(
        externalId: _externalId(map, dateText, mealType, name, rowNumber),
        name: name,
        nutrientsPer100: NutrientVector.full(perHundred),
        isLiquid: isLiquid,
        portion: Portion(
          value: amount,
          entered: _formatNumber(amount),
          unit: isLiquid ? PortionUnit.milliliter : PortionUnit.gram,
        ),
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

  static List<Object?>? _extractRecords(Object? decoded) {
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map) {
      final map = decoded.cast<String, Object?>();
      for (final key in const ['consumed_items', 'items', 'data', 'entries']) {
        final value = map[key];
        if (value is List) {
          return value;
        }
      }
    }
    return null;
  }

  /// Yazio nests nutrients either under a `nutrients` map or inline on the
  /// record; normalise to a single lower-cased key -> number map.
  static Map<String, num> _nutrientMap(Map<String, Object?> record) {
    final result = <String, num>{};
    final nested = record['nutrients'];
    if (nested is Map) {
      nested.forEach((key, value) {
        if (value is num) {
          result[key.toString().toLowerCase()] = value;
        }
      });
    }
    return result;
  }

  static double? _nutrientValue(Map<String, num> nutrients, List<String> keys) {
    for (final key in keys) {
      final value = nutrients[key.toLowerCase()];
      if (value != null) {
        return value.toDouble();
      }
    }
    return null;
  }

  static String _string(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String) {
        return value;
      }
    }
    return '';
  }

  static double? _double(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  static bool? _bool(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is bool) {
        return value;
      }
    }
    return null;
  }

  static String _canonicalMealType(String raw) {
    final normalized = raw.trim().toLowerCase();
    return switch (normalized) {
      'breakfast' => 'Breakfast',
      'lunch' => 'Lunch',
      'dinner' => 'Dinner',
      'snack' || 'snacks' => 'Snack',
      '' => 'Imported',
      _ => '${normalized[0].toUpperCase()}${normalized.substring(1)}',
    };
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

  static DateTime _parseDate(String dateText) {
    final text = dateText.trim();
    if (text.isEmpty) {
      return DateTime(1970);
    }
    final parsed = DateTime.tryParse(text);
    if (parsed != null) {
      final local = parsed.isUtc ? parsed.toLocal() : parsed;
      return DateTime(local.year, local.month, local.day, local.hour,
          local.minute);
    }
    return DateTime(1970);
  }

  static String _externalId(
    Map<String, Object?> map,
    String dateText,
    String meal,
    String name,
    int rowNumber,
  ) {
    // Prefer the provider's own stable id when present.
    final providerId = _string(map, const ['id', 'uuid', 'consumed_item_id']);
    if (providerId.trim().isNotEmpty) {
      return providerId.trim();
    }
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
