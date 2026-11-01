import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';

// The server runs the same vectors through buildFoodHistory
// (apps/server/test/food-history.golden.test.mjs), so an agent and the
// add-food picker see the user's Foods in the same order.
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

  test('Food History matches the shared food-history golden vectors', () async {
    final vector = jsonDecode(
      await _vectorFile('m37-food-history.json').readAsString(),
    ) as Map<String, Object?>;
    expect(vector['domain'], 'food-history');
    expect(vector['schemaVersion'], 1);
    expect(vector['schema'], 'm37-food-history.schema.json');

    final cases = vector['cases']! as List<Object?>;
    expect(cases, isNotEmpty);
    for (final caseObject in cases) {
      final caseData = caseObject! as Map<String, Object?>;
      final input = caseData['input']! as Map<String, Object?>;
      final database = AppDatabase.inMemory();
      try {
        await _insertCase(database, input);
        final history = await TrainingRepositories(database)
            .nutrition
            .listFoodHistory(now: DateTime.parse(input['now']! as String));
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
            name: entry['id']! as String,
            nutrientValuesJson: noNutrients,
            foodId: Value(entry['foodId'] as String?),
            foodSource: Value(entry['foodSource'] as String?),
            isLiquid: Value(entry['isLiquid'] as bool?),
            portionJson: Value(
              portion == null ? null : Portion.fromJson(portion).toJsonString(),
            ),
            updatedAt: DateTime.parse(entry['updatedAt']! as String),
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

Map<String, Object?> _recordToJson(FoodHistoryRecord record) {
  return <String, Object?>{
    'foodSource': record.foodSource.name,
    'foodId': record.foodId,
    'recentCount': record.recentCount,
    'lastLoggedAt': record.lastLoggedAt.toUtc().toIso8601String(),
    'lastPortion': record.lastPortion?.toJson(),
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
