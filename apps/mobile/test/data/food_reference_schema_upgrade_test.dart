import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/food_reference_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schema 2 of the reference database adds `aisle`, its index and the narrower
/// update trigger. The upgrade drops everything and creates the schema, and
/// the missing content hash makes the installer run again
/// (docs/designs/food-aisles.md, "On the device"). This is the first time the
/// upgrade path runs.
void main() {
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning,
  );

  test('a version 1 database opens at version 2 with the Aisle schema',
      () async {
    final directory = await Directory.systemTemp.createTemp('prn_ref_v1_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/food_reference.sqlite');

    final raw = sqlite.sqlite3.open(file.path);
    for (final statement in _version1Schema) {
      raw.execute(statement);
    }
    raw
      ..execute(
        'INSERT INTO open_food_facts_products (code, name, brand, is_liquid, '
        'serving_label, serving_size, package_size, nutrients_json, '
        "modified_at, scans, origin) VALUES ('1001', 'Greek Yogurt', "
        "'Chobani', 0, NULL, NULL, NULL, '{\"energy\":\"53\"}', 1, 5, "
        "'online')",
      )
      ..execute(
        'INSERT INTO reference_meta (key, value) '
        "VALUES ('$bundleContentHashKey', 'hash-v1')",
      )
      ..execute('PRAGMA user_version = 1');
    raw.close();

    final database = FoodReferenceDatabase.openInIsolate(file);
    addTearDown(database.close);

    expect(await database.metaValue(bundleContentHashKey), isNull);
    expect(await allRows(database), isEmpty);

    final columns = await database
        .customSelect('PRAGMA table_info(open_food_facts_products)')
        .get();
    expect([for (final row in columns) row.read<String>('name')],
        contains('aisle'));

    final index = await database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' "
          "AND name = 'open_food_facts_products_aisle_rank'",
        )
        .getSingleOrNull();
    expect(index, isNotNull);
    expect(index!.read<String>('sql'), contains('(aisle, scans DESC, code)'));

    final trigger = await database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'trigger' "
          "AND name = 'open_food_facts_products_au'",
        )
        .getSingle();
    expect(
        trigger.read<String>('sql'), contains('AFTER UPDATE OF name, brand'));

    final version =
        await database.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 2);

    // The search index works on the new schema.
    await database.customStatement(
      'INSERT INTO open_food_facts_products (code, name, is_liquid, '
      "nutrients_json, modified_at, origin) VALUES ('2002', 'Rolled oats', 0, "
      "'{}', 1, 'online')",
    );
    final found = await database.searchProducts('"oats"*', 10);
    expect([for (final row in found) row.code], ['2002']);
  });
}

Future<List<OpenFoodFactsProductRow>> allRows(FoodReferenceDatabase database) {
  return database.select(database.openFoodFactsProducts).get();
}

/// The version 1 schema, as `FoodReferenceDatabase` created it before the
/// Aisle column: copied here as a fixture, because the code no longer makes it.
const _version1Schema = <String>[
  'CREATE TABLE "reference_meta" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, '
      'PRIMARY KEY ("key"))',
  'CREATE TABLE "open_food_facts_products" ("id" INTEGER NOT NULL PRIMARY KEY '
      'AUTOINCREMENT, "code" TEXT NOT NULL UNIQUE, "name" TEXT NOT NULL, '
      '"brand" TEXT NULL, "is_liquid" INTEGER NOT NULL CHECK ("is_liquid" IN '
      '(0, 1)), "serving_label" TEXT NULL, "serving_size" REAL NULL, '
      '"package_size" REAL NULL, "nutrients_json" TEXT NOT NULL, '
      '"modified_at" INTEGER NOT NULL, "scans" INTEGER NULL, '
      '"origin" TEXT NOT NULL)',
  '''
      CREATE VIRTUAL TABLE open_food_facts_products_fts USING fts5(
        name, brand,
        content='open_food_facts_products', content_rowid='id',
        tokenize='unicode61 remove_diacritics 2'
      )''',
  '''
      CREATE TRIGGER open_food_facts_products_ai
      AFTER INSERT ON open_food_facts_products BEGIN
        INSERT INTO open_food_facts_products_fts(rowid, name, brand)
        VALUES (new.id, new.name, new.brand);
      END''',
  '''
      CREATE TRIGGER open_food_facts_products_ad
      AFTER DELETE ON open_food_facts_products BEGIN
        INSERT INTO open_food_facts_products_fts(open_food_facts_products_fts, rowid, name, brand)
        VALUES ('delete', old.id, old.name, old.brand);
      END''',
  '''
      CREATE TRIGGER open_food_facts_products_au
      AFTER UPDATE ON open_food_facts_products BEGIN
        INSERT INTO open_food_facts_products_fts(open_food_facts_products_fts, rowid, name, brand)
        VALUES ('delete', old.id, old.name, old.brand);
        INSERT INTO open_food_facts_products_fts(rowid, name, brand)
        VALUES (new.id, new.name, new.brand);
      END''',
];
