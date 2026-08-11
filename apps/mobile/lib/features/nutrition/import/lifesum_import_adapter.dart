import 'dart:convert';

import '../../../domain/nutrition/nutrition.dart';
import 'cronometer_csv_import_adapter.dart' show NutritionImportFormatException;
import 'csv_parser.dart';
import 'nutrition_import.dart';

/// Parses a Lifesum GDPR data export into a provider-neutral
/// [NutritionImportBatch]. Lifesum exports as **either CSV or JSON**; this one
/// adapter sniffs the format (a leading `{`/`[` is JSON, otherwise CSV) and
/// normalises both into the same canonical shape — the format split is a
/// provider quirk quarantined here, the downstream pipeline never sees it
/// (INTEGRATIONS.md §14). Pure: no storage, no network, no native picker.
///
/// Lifesum reports absolute nutrient amounts for an explicit `amount` + `unit`
/// serving; the parser normalises to a per-100 vector so the snapshot is
/// self-describing (NUTRITION.md §1.1). A nutrient Lifesum does not report is
/// left *unknown*, never zero (`0 != unknown`, NUTRITION.md §4).
class LifesumImportAdapter implements NutritionImportAdapter {
  const LifesumImportAdapter();

  @override
  String get provider => 'Lifesum';

  /// Lifesum CSV header / JSON key -> registry id. Matched case-insensitively
  /// and unit-suffix-tolerantly. A column/key not in this map is ignored; a
  /// registry nutrient with no column/key is left unknown.
  static const _keyToNutrient = <String, NutrientId>{
    'calories (kcal)': NutrientId.energy,
    'calories': NutrientId.energy,
    'energy (kcal)': NutrientId.energy,
    'energy': NutrientId.energy,
    'protein (g)': NutrientId.protein,
    'protein': NutrientId.protein,
    'carbs (g)': NutrientId.carbohydrate,
    'carbohydrates (g)': NutrientId.carbohydrate,
    'carbs': NutrientId.carbohydrate,
    'carbohydrates': NutrientId.carbohydrate,
    'fat (g)': NutrientId.fat,
    'fat': NutrientId.fat,
    'saturated fat (g)': NutrientId.saturatedFat,
    'saturatedfat': NutrientId.saturatedFat,
    'unsaturated fat (g)': NutrientId.polyunsaturatedFat,
    'fiber (g)': NutrientId.fiber,
    'fibre (g)': NutrientId.fiber,
    'fiber': NutrientId.fiber,
    'sugar (g)': NutrientId.sugar,
    'sugars (g)': NutrientId.sugar,
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
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return NutritionImportBatch.empty;
    }
    final firstChar = trimmed[0];
    if (firstChar == '{' || firstChar == '[') {
      return _parseJson(trimmed);
    }
    return _parseCsv(content);
  }

  // ---- JSON path -----------------------------------------------------------

  NutritionImportBatch _parseJson(String content) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (error) {
      throw NutritionImportFormatException(
        'Not a recognized Lifesum export: invalid JSON (${error.message}).',
      );
    }
    final records = _extractRecords(decoded);
    if (records == null) {
      throw const NutritionImportFormatException(
        'Not a recognized Lifesum export: expected a list of food items.',
      );
    }

    final builder = _BatchBuilder();
    for (var rowNumber = 0; rowNumber < records.length; rowNumber += 1) {
      final record = records[rowNumber];
      if (record is! Map) {
        continue;
      }
      final map = record.cast<String, Object?>();
      final name = _string(map, const ['name', 'food', 'title']).trim();
      if (name.isEmpty) {
        continue;
      }
      final amount = _double(map, const ['amount', 'quantity', 'grams']);
      if (amount == null || amount <= 0) {
        continue;
      }
      final unit = _string(map, const ['unit', 'measurement']).trim();
      final isLiquid = _isLiquidUnit(unit) ||
          (_bool(map, const ['is_liquid', 'liquid']) ?? false);
      final dateText = _string(map, const ['date', 'logged_at', 'tracked_at']);
      final mealText = _string(map, const ['meal', 'meal_type', 'category']);

      final values = <String, double>{};
      final nested = map['nutrients'];
      if (nested is Map) {
        nested.forEach((key, value) {
          final parsed = _asDouble(value);
          if (parsed != null) {
            values[key.toString().toLowerCase()] = parsed;
          }
        });
      }
      // Lifesum also inlines macros directly on the record.
      for (final key in _keyToNutrient.keys) {
        if (values.containsKey(key)) {
          continue;
        }
        final inline = map[key] ?? map[key.split(' ').first];
        final parsed = _asDouble(inline);
        if (parsed != null) {
          values[key] = parsed;
        }
      }

      builder.add(
        dateText: dateText,
        mealText: mealText,
        name: name,
        amount: amount,
        isLiquid: isLiquid,
        rowNumber: rowNumber,
        absoluteByNutrient: _resolveAbsolute(values),
        externalId: _string(map, const ['id', 'uuid']).trim(),
      );
    }
    return builder.build();
  }

  static List<Object?>? _extractRecords(Object? decoded) {
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map) {
      final map = decoded.cast<String, Object?>();
      for (final key in const ['food_items', 'items', 'data', 'entries']) {
        final value = map[key];
        if (value is List) {
          return value;
        }
      }
    }
    return null;
  }

  // ---- CSV path ------------------------------------------------------------

  NutritionImportBatch _parseCsv(String content) {
    final rows = parseCsv(content);
    if (rows.isEmpty) {
      return NutritionImportBatch.empty;
    }
    final header = rows.first.map(_normalizeHeader).toList(growable: false);
    final headerIndex = <String, int>{};
    for (var i = 0; i < header.length; i += 1) {
      headerIndex.putIfAbsent(header[i], () => i);
    }

    final foodColumn = _firstColumn(headerIndex, const ['food', 'name']);
    final amountColumn =
        _firstColumn(headerIndex, const ['amount', 'quantity']);
    if (foodColumn == null || amountColumn == null) {
      throw const NutritionImportFormatException(
        'Not a recognized Lifesum export: missing a Food / Amount column.',
      );
    }
    final unitColumn = _firstColumn(headerIndex, const ['unit', 'measurement']);
    final mealColumn = _firstColumn(headerIndex, const ['meal', 'category']);
    final dateColumn = _firstColumn(headerIndex, const ['date', 'logged at']);

    final nutrientColumns = <int, NutrientId>{};
    for (final entry in headerIndex.entries) {
      final id = _keyToNutrient[entry.key];
      if (id != null) {
        nutrientColumns[entry.value] = id;
      }
    }

    final builder = _BatchBuilder();
    for (var rowNumber = 1; rowNumber < rows.length; rowNumber += 1) {
      final cells = rows[rowNumber];
      final name = _cell(cells, foodColumn).trim();
      if (name.isEmpty) {
        continue;
      }
      final amount = _asDouble(_cell(cells, amountColumn).trim());
      if (amount == null || amount <= 0) {
        continue;
      }
      final unit = unitColumn == null ? '' : _cell(cells, unitColumn).trim();
      final isLiquid = _isLiquidUnit(unit);
      final dateText = dateColumn == null ? '' : _cell(cells, dateColumn).trim();
      final mealText = mealColumn == null ? '' : _cell(cells, mealColumn).trim();

      final values = <String, double>{};
      for (final column in nutrientColumns.entries) {
        // Key by the registry storage key so _resolveAbsolute sees one value
        // per nutrient even when several columns map to the same id.
        final id = column.value;
        final parsed = _asDouble(_cell(cells, column.key).trim());
        if (parsed != null) {
          values.putIfAbsent(id.storageKey, () => parsed);
        }
      }

      builder.add(
        dateText: dateText,
        mealText: mealText,
        name: name,
        amount: amount,
        isLiquid: isLiquid,
        rowNumber: rowNumber,
        absoluteByNutrient: _resolveByStorageKey(values),
        externalId: '',
      );
    }
    return builder.build();
  }

  /// Map a raw key->value bag (header/JSON keys) to absolute amounts by
  /// [NutrientId], using the column/key registry. First writer wins per id.
  static Map<NutrientId, double> _resolveAbsolute(Map<String, double> values) {
    final result = <NutrientId, double>{};
    values.forEach((key, value) {
      final id = _keyToNutrient[key];
      if (id != null) {
        result.putIfAbsent(id, () => value);
      }
    });
    return result;
  }

  static Map<NutrientId, double> _resolveByStorageKey(
    Map<String, double> values,
  ) {
    final result = <NutrientId, double>{};
    values.forEach((storageKey, value) {
      result[NutrientId.byStorageKey(storageKey)] = value;
    });
    return result;
  }

  static bool _isLiquidUnit(String unit) {
    final normalized = unit.trim().toLowerCase();
    return normalized == 'ml' ||
        normalized == 'milliliter' ||
        normalized == 'millilitre' ||
        normalized == 'l';
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
      final parsed = _asDouble(map[key]);
      if (parsed != null) {
        return parsed;
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

  static double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final text = value.trim().replaceAll(',', '');
      if (text.isEmpty) {
        return null;
      }
      return double.tryParse(text);
    }
    return null;
  }
}

/// Accumulates parsed rows (from either the CSV or JSON path) into meals,
/// normalising absolute amounts to a per-100 vector. Shared so both Lifesum
/// formats land identically — the invariance that is the design.
class _BatchBuilder {
  final Map<String, _MealAccumulator> _mealsByKey = {};
  final List<String> _orderedKeys = [];

  void add({
    required String dateText,
    required String mealText,
    required String name,
    required double amount,
    required bool isLiquid,
    required int rowNumber,
    required Map<NutrientId, double> absoluteByNutrient,
    required String externalId,
  }) {
    final startedAt = _parseDate(dateText);
    final localDate = NutritionDayDate.fromDateTime(startedAt);
    final mealType = _canonicalMealType(mealText);
    final mealKey = '${localDate.storageValue}|$mealType';

    final perHundred = <NutrientId, NutrientAmount>{};
    for (final id in NutrientId.values) {
      final absolute = absoluteByNutrient[id];
      if (absolute == null) {
        perHundred[id] = NutrientAmount.unknown(id.defaultUnit);
        continue;
      }
      final per100 = absolute / (amount / 100);
      perHundred[id] = NutrientAmount.complete(
        value: per100,
        entered: _formatNumber(per100),
        unit: id.defaultUnit,
      );
    }

    final entry = NutritionImportFoodEntry(
      externalId: externalId.isNotEmpty
          ? externalId
          : _derivedExternalId(dateText, mealType, name, rowNumber),
      name: name,
      nutrientsPer100: NutrientVector.full(perHundred),
      isLiquid: isLiquid,
      portion: Portion(
        value: amount,
        entered: _formatNumber(amount),
        unit: isLiquid ? PortionUnit.milliliter : PortionUnit.gram,
      ),
    );

    final accumulator = _mealsByKey.putIfAbsent(mealKey, () {
      _orderedKeys.add(mealKey);
      return _MealAccumulator(
        mealType: mealType,
        startedAt: startedAt,
        localDate: localDate,
      );
    });
    accumulator.entries.add(entry);
  }

  NutritionImportBatch build() {
    final meals = <NutritionImportMeal>[
      for (final key in _orderedKeys) _mealsByKey[key]!.toMeal(),
    ];
    return NutritionImportBatch(meals: meals);
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
    final iso = DateTime.tryParse(text);
    if (iso != null) {
      final local = iso.isUtc ? iso.toLocal() : iso;
      return DateTime(
          local.year, local.month, local.day, local.hour, local.minute);
    }
    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
    if (slash != null) {
      // Lifesum CSV uses DD/MM/YYYY (its primary markets are metric/EU).
      final day = int.parse(slash.group(1)!);
      final month = int.parse(slash.group(2)!);
      final year = int.parse(slash.group(3)!);
      return DateTime(year, month, day);
    }
    return DateTime(1970);
  }

  static String _derivedExternalId(
    String dateText,
    String meal,
    String name,
    int rowNumber,
  ) {
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
