import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schema 61 drops the old Open Food Facts cache from the user database; the
/// products now live in the rebuildable reference database. Nothing else
/// changes (docs/designs/open-food-facts.md, "Installing the bundle on the
/// device").
void main() {
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning,
  );

  test('a version-60 database with cache rows opens at 61 without the table',
      () async {
    final directory = await Directory.systemTemp.createTemp('prn_off_cache_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/v60.sqlite');

    // Schema 60 is schema 61 plus the cache table: build 61, add the table
    // and its rows, and mark the file as version 60.
    final current = AppDatabase.openFile(file);
    await current.customSelect('SELECT 1').get();
    final expectedTables = await _tableNames(current);
    await current.close();
    final raw = sqlite.sqlite3.open(file.path);
    raw
      ..execute('''
        CREATE TABLE open_food_facts_cache (
          lookup_key TEXT NOT NULL PRIMARY KEY,
          food_id TEXT NOT NULL,
          name TEXT NOT NULL,
          nutrient_values_json TEXT NOT NULL,
          is_liquid INTEGER NOT NULL DEFAULT 0,
          serving_label TEXT,
          serving_size REAL,
          package_size REAL,
          fetched_at INTEGER NOT NULL,
          last_accessed_at INTEGER NOT NULL
        )''')
      ..execute('''
        CREATE INDEX open_food_facts_cache_last_accessed_at_index
        ON open_food_facts_cache (last_accessed_at)''')
      ..execute('''
        INSERT INTO open_food_facts_cache VALUES
          ('barcode:3017620422003', '3017620422003', 'Spread', '{}', 0,
           NULL, NULL, NULL, 1, 1),
          ('search:oats', '9300652010411', 'Oats', '{}', 0,
           NULL, NULL, NULL, 2, 2)''')
      ..execute(
        'INSERT INTO meal_types (id, name, sort_order, updated_at) '
        "VALUES ('meal-type-kept', 'Second breakfast', 9, 0)",
      )
      ..execute('PRAGMA user_version = 60');
    raw.close();

    final migrated = AppDatabase.openFile(file);
    addTearDown(migrated.close);
    await migrated.customSelect('SELECT 1').get();

    expect(migrated.schemaVersion, 61);
    final tables = await _tableNames(migrated);
    expect(tables, isNot(contains('open_food_facts_cache')));
    expect(tables, expectedTables);
    final mealType = await migrated
        .customSelect(
          "SELECT name FROM meal_types WHERE id = 'meal-type-kept'",
        )
        .getSingle();
    expect(mealType.read<String>('name'), 'Second breakfast');
    final indexes = await migrated
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name LIKE 'open_food_facts%'",
        )
        .get();
    expect(indexes, isEmpty);
  });
}

Future<Set<String>> _tableNames(AppDatabase database) async {
  final rows = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      )
      .get();
  return {for (final row in rows) row.read<String>('name')};
}
