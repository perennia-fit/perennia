import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';

// The server runs the same vectors through buildMealHistory
// (apps/server/test/meal-history.golden.test.mjs), so an agent and Your meals
// see the user's repeated meals in the same order.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  // listMealHistory builds the canonical string with
  // `group_concat(key, '|' ORDER BY key)`, which SQLite added in 3.44.0.
  test('the bundled SQLite supports ordered group_concat', () async {
    final database = AppDatabase.inMemory();
    try {
      final version = (await database
              .customSelect('SELECT sqlite_version() AS version')
              .getSingle())
          .read<String>('version');
      final [major, minor, ...] =
          version.split('.').map(int.parse).toList(growable: false);
      expect(
        major > 3 || (major == 3 && minor >= 44),
        isTrue,
        reason: 'SQLite $version is older than 3.44.0.',
      );
      final joined = await database
          .customSelect(
            "SELECT group_concat(k, '|' ORDER BY k) AS joined "
            "FROM (SELECT 'b' AS k UNION ALL SELECT 'a' UNION ALL SELECT 'B')",
          )
          .getSingle();
      expect(joined.read<String>('joined'), 'B|a|b');
    } finally {
      await database.close();
    }
  });

  test('Meal History matches the shared meal-history golden vectors', () async {
    final vector = jsonDecode(
      await _vectorFile('m38-meal-history.json').readAsString(),
    ) as Map<String, Object?>;
    expect(vector['domain'], 'meal-history');
    expect(vector['schemaVersion'], 1);
    expect(vector['schema'], 'm38-meal-history.schema.json');

    final cases = vector['cases']! as List<Object?>;
    expect(cases, isNotEmpty);
    for (final caseObject in cases) {
      final caseData = caseObject! as Map<String, Object?>;
      final input = caseData['input']! as Map<String, Object?>;
      final database = AppDatabase.inMemory();
      try {
        await _insertCase(database, input);
        final history =
            await TrainingRepositories(database).nutrition.listMealHistory(
                  now: DateTime.parse(input['now']! as String),
                  limit: input['limit']! as int,
                );
        expect(
          [for (final record in history) _recordToJson(record)],
          caseData['expected'],
          reason: caseData['name']! as String,
        );
      } finally {
        await database.close();
      }
    }
  });
}

Future<void> _insertCase(
  AppDatabase database,
  Map<String, Object?> input,
) async {
  final noNutrients = NutrientVector.full(const {}).toJsonString();
  for (final raw in input['meals']! as List<Object?>) {
    final meal = raw! as Map<String, Object?>;
    final startedAt = DateTime.parse(meal['startedAt']! as String);
    await database.into(database.meals).insert(
          MealsCompanion.insert(
            id: meal['id']! as String,
            mealType: 'Breakfast',
            startedAt: startedAt,
            timezone: 'UTC',
            timezoneOffsetMinutes: const Value(0),
            timePrecision: Value(meal['timePrecision']! as String),
            updatedAt: startedAt,
            deletedAt: Value(_instant(meal['deletedAt'])),
          ),
        );
  }
  for (final raw in input['entries']! as List<Object?>) {
    final entry = raw! as Map<String, Object?>;
    final portion = entry['portion'] as Map<String, Object?>?;
    await database.into(database.foodEntries).insert(
          FoodEntriesCompanion.insert(
            id: entry['id']! as String,
            mealId: entry['mealId']! as String,
            entryKind: Value(entry['kind']! as String),
            position: entry['position']! as int,
            name: entry['name']! as String,
            nutrientValuesJson: noNutrients,
            foodId: Value(entry['foodId'] as String?),
            foodSource: Value(entry['foodSource'] as String?),
            isLiquid: Value(entry['isLiquid'] as bool?),
            portionJson: Value(
              portion == null ? null : Portion.fromJson(portion).toJsonString(),
            ),
            updatedAt: DateTime.parse(input['now']! as String),
            deletedAt: Value(_instant(entry['deletedAt'])),
          ),
        );
  }
  for (final id
      in (input['archivedUserFoodIds']! as List<Object?>).cast<String>()) {
    final archivedAt = DateTime.utc(2026);
    await database.into(database.foods).insert(
          FoodsCompanion.insert(
            id: id,
            name: id,
            nutrientValuesJson: noNutrients,
            updatedAt: archivedAt,
            deletedAt: Value(archivedAt),
          ),
        );
  }
}

DateTime? _instant(Object? value) {
  return value == null ? null : DateTime.parse(value as String);
}

Map<String, Object?> _recordToJson(MealHistoryRecord record) {
  return <String, Object?>{
    'foods': [
      for (final food in record.foods)
        <String, Object?>{
          'foodSource': food.foodSource.name,
          'foodId': food.foodId,
          'name': food.name,
        },
    ],
    'count': record.count,
    'lastMealId': record.lastMealId,
    'lastStartedAt': record.lastStartedAt.toUtc().toIso8601String(),
  };
}

File _vectorFile(String name) {
  var directory = Directory.current;
  for (var depth = 0; depth < 6; depth += 1) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}packages'
      '${Platform.pathSeparator}golden-vectors'
      '${Platform.pathSeparator}vectors'
      '${Platform.pathSeparator}$name',
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Golden vector not found: $name.');
}
