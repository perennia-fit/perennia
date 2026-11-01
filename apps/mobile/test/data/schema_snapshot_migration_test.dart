import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../generated_migrations/app_database/schema.dart';

/// The schemaVersion of release 0.0.1, the first build installed on a device.
///
/// Its snapshot is the oldest one committed: every later release has to
/// migrate a database at this version forward without losing a row
/// (docs/releasing.md, "Rules that keep installs updatable").
const _firstReleasedSchemaVersion = 62;

/// Upgrades databases built from the committed snapshots in
/// `drift_schemas/app_database/` with the app's real [MigrationStrategy], and
/// checks the result against the snapshot of the current schemaVersion.
///
/// The snapshots and `test/generated_migrations/` are regenerated with
/// drift_dev; docs/releasing.md says how.
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  late SchemaVerifier verifier;
  late int currentVersion;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    verifier = SchemaVerifier(GeneratedHelper());
    final database = AppDatabase.inMemory();
    currentVersion = database.schemaVersion;
    await database.close();
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  test('a snapshot is committed for every version from the first release on',
      () {
    expect(GeneratedHelper.versions.first, _firstReleasedSchemaVersion);
    expect(
      GeneratedHelper.versions.last,
      currentVersion,
      reason: 'AppDatabase.schemaVersion has no committed snapshot; '
          'see docs/releasing.md',
    );
  });

  test('a fresh install matches the current snapshot', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await verifier.migrateAndValidate(
      database,
      currentVersion,
      options: const ValidationOptions(validateDropped: true),
    );
  });

  // AppDatabase's onUpgrade always migrates to its own schemaVersion, so every
  // snapshot is upgraded to the current one rather than to the next snapshot.
  for (final fromVersion in GeneratedHelper.versions) {
    test('upgrades a v$fromVersion database to the current snapshot', () async {
      final connection = await verifier.startAt(fromVersion);
      final database = AppDatabase(connection);
      addTearDown(database.close);

      await verifier.migrateAndValidate(
        database,
        currentVersion,
        options: const ValidationOptions(validateDropped: true),
      );
    });
  }

  test('rows written at the first release survive to the current version',
      () async {
    final schema = await verifier.schemaAt(_firstReleasedSchemaVersion);
    addTearDown(schema.close);
    _seedFirstReleaseRows(schema.rawDatabase);

    final database = AppDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, currentVersion);

    final category =
        await database.select(database.exerciseCategories).getSingle();
    expect(category.id, 'category-1');
    expect(category.name, 'Legs');
    expect(category.colorHex, '#4CAF50');
    expect(category.syncPreviouslySynced, isTrue);

    // v63 added Focus colors; an existing Focus keeps its default (null).
    final focus = await database.select(database.focuses).getSingle();
    expect(focus.id, 'focus-1');
    expect(focus.name, 'Climbing');
    expect(focus.sortOrder, 3);
    expect(focus.colorHex, isNull);

    final exercise = await database.select(database.exercises).getSingle();
    expect(exercise.id, 'exercise-1');
    expect(exercise.name, 'Back Squat');
    expect(exercise.categoryId, 'category-1');
    expect(exercise.dimensionIds, '["load","reps"]');
    expect(exercise.isFavorite, isTrue);
    expect(exercise.notes, 'High bar');

    final workout = await database.select(database.workoutSessions).getSingle();
    expect(workout.id, 'workout-1');
    expect(workout.startedAt, _at(1_767_250_800));
    expect(workout.endedAt, _at(1_767_254_400));
    expect(workout.timezone, 'Australia/Sydney');
    expect(workout.localDate, '2026-01-01');
    expect(workout.comment, 'Felt strong');

    final workoutExercise =
        await database.select(database.workoutExercises).getSingle();
    expect(workoutExercise.workoutId, 'workout-1');
    expect(workoutExercise.exerciseId, 'exercise-1');

    final set = await database.select(database.loggedSets).getSingle();
    expect(set.id, 'set-1');
    expect(set.workoutId, 'workout-1');
    expect(set.exerciseId, 'exercise-1');
    expect(set.loadValue, 102.5);
    expect(set.loadUnit, 'kg');
    expect(set.loadEntered, '102.5');
    expect(set.repsValue, 5);
    expect(set.repsUnit, 'reps');
    expect(set.repsEntered, '5');
    expect(set.performedAt, _at(1_767_251_100));
    expect(set.comment, 'Belt on');
    expect(set.isCompleted, isTrue);

    final meal = await database.select(database.meals).getSingle();
    expect(meal.id, 'meal-1');
    expect(meal.mealType, 'breakfast');
    final foodEntry = await database.select(database.foodEntries).getSingle();
    expect(foodEntry.mealId, 'meal-1');
    expect(foodEntry.name, 'Oats');
    expect(foodEntry.nutrientValuesJson, '{"energy_kcal":389}');

    final compound = await database.select(database.compounds).getSingle();
    expect(compound.name, 'Creatine');
    final dose = await database.select(database.doses).getSingle();
    expect(dose.compoundId, 'compound-1');
    expect(dose.amountValue, 5);
    expect(dose.amountEntered, '5');
    expect(dose.unit, 'g');
    expect(dose.tookAt, _at(1_767_247_200));

    final metric = await database.select(database.metrics).getSingle();
    expect(metric.name, 'Body weight');
    final reading = await database.select(database.metricReadings).getSingle();
    expect(reading.metricId, 'metric-1');
    expect(reading.scalarValue, 81.4);
    expect(reading.scalarEntered, '81.4');

    final logEntry = await database.select(database.activityLog).getSingle();
    expect(logEntry.entityTable, AppDatabase.loggedSetsTable);
    expect(logEntry.entityId, 'set-1');
    expect(logEntry.afterImage, '{"reps_entered":"5"}');
  });
}

DateTime _at(int unixSeconds) =>
    DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);

/// Writes one row graph per authored domain in the SQL of the first released
/// schema. That schema never changes, so neither does this SQL.
void _seedFirstReleaseRows(sqlite.Database database) {
  const updatedAt = 1_767_254_400;
  for (final (sql, parameters) in <(String, List<Object?>)>[
    (
      'INSERT INTO exercise_categories '
          '(id, name, sort_order, color_hex, sync_previously_synced, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
      ['category-1', 'Legs', 0, '#4CAF50', 1, updatedAt],
    ),
    (
      'INSERT INTO focuses (id, name, sort_order, updated_at) '
          'VALUES (?, ?, ?, ?)',
      ['focus-1', 'Climbing', 3, updatedAt],
    ),
    (
      'INSERT INTO exercises '
          '(id, name, dimension_ids, is_favorite, category_id, notes, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        'exercise-1',
        'Back Squat',
        '["load","reps"]',
        1,
        'category-1',
        'High bar',
        updatedAt,
      ],
    ),
    (
      'INSERT INTO workout_sessions '
          '(id, started_at, timezone, local_date, ended_at, comment, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        'workout-1',
        1_767_250_800,
        'Australia/Sydney',
        '2026-01-01',
        1_767_254_400,
        'Felt strong',
        updatedAt,
      ],
    ),
    (
      'INSERT INTO workout_exercises '
          '(id, workout_id, exercise_id, position, updated_at) '
          'VALUES (?, ?, ?, ?, ?)',
      ['workout-exercise-1', 'workout-1', 'exercise-1', 0, updatedAt],
    ),
    (
      'INSERT INTO logged_sets '
          '(id, workout_id, exercise_id, position, performed_at, '
          'load_value, load_unit, load_entered, '
          'reps_value, reps_unit, reps_entered, comment, is_completed, '
          'updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'set-1',
        'workout-1',
        'exercise-1',
        0,
        1_767_251_100,
        102.5,
        'kg',
        '102.5',
        5.0,
        'reps',
        '5',
        'Belt on',
        1,
        updatedAt,
      ],
    ),
    (
      'INSERT INTO meals '
          '(id, meal_type, started_at, timezone, local_date, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
      [
        'meal-1',
        'breakfast',
        1_767_247_200,
        'Australia/Sydney',
        '2026-01-01',
        updatedAt,
      ],
    ),
    (
      'INSERT INTO food_entries '
          '(id, meal_id, position, name, nutrient_values_json, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
      ['food-entry-1', 'meal-1', 0, 'Oats', '{"energy_kcal":389}', updatedAt],
    ),
    (
      'INSERT INTO compounds '
          '(id, name, default_unit, default_route, updated_at) '
          'VALUES (?, ?, ?, ?, ?)',
      ['compound-1', 'Creatine', 'g', 'oral', updatedAt],
    ),
    (
      'INSERT INTO doses '
          '(id, compound_id, compound_name, amount_value, amount_entered, '
          'unit, route, took_at, timezone, local_date, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'dose-1',
        'compound-1',
        'Creatine',
        5.0,
        '5',
        'g',
        'oral',
        1_767_247_200,
        'Australia/Sydney',
        '2026-01-01',
        updatedAt,
      ],
    ),
    (
      'INSERT INTO metrics '
          '(id, name, unit, value_shape, metric_group, sort_order, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
      ['metric-1', 'Body weight', 'kg', 'scalar', 'body', 0, updatedAt],
    ),
    (
      'INSERT INTO metric_readings '
          '(id, metric_id, value_json, scalar_value, scalar_entered, at_time, '
          'provenance, source, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'reading-1',
        'metric-1',
        '{"value":81.4}',
        81.4,
        '81.4',
        1_767_247_200,
        'manual',
        'app',
        updatedAt,
      ],
    ),
    (
      'INSERT INTO activity_log '
          '(id, actor, batch_id, entity_table, entity_id, after_image, '
          'occurred_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'log-1',
        'user',
        'batch-1',
        'logged_sets',
        'set-1',
        '{"reps_entered":"5"}',
        1_767_251_100,
        updatedAt,
      ],
    ),
  ]) {
    database.execute(sql, parameters);
  }
}
