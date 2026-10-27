import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart' show SqliteException;
// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/local/food_reference_database.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';

import 'open_food_facts_fixtures.dart';

/// The reference database's rules: the FTS5 search, one row per barcode with
/// newer-copy values, `origin` as why a row is kept, and the one-transaction
/// install (docs/designs/open-food-facts.md, "One product, one row").
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
      warnAboutMultipleDatabases);

  late FoodReferenceDatabase database;

  setUp(() => database = FoodReferenceDatabase.memory());
  tearDown(() => database.close());

  Future<void> install(
    List<MappedOpenFoodFactsProduct> products, {
    String hash = 'hash-1',
  }) {
    return database.replaceBundle(
      bundleLines(products),
      bundleHeader(contentHash: hash, productCount: products.length),
    );
  }

  Future<List<String>> search(String query) async {
    final rows =
        await database.searchProducts(buildFoodSearchMatch(query)!, 50);
    return [for (final row in rows) row.code];
  }

  group('search', () {
    test('FTS5 is available and matches word prefixes of name and brand',
        () async {
      await install([
        offProduct('1001', 'Greek Yogurt Plain', brand: 'Chobani'),
        offProduct('1002', 'Crème brûlée', brand: 'Gü'),
        offProduct('1003', 'Rolled oats', brand: 'Uncle Tobys'),
      ]);

      expect(await search('greek yog'), ['1001']);
      expect(await search('chob'), ['1001']);
      expect(await search('creme'), ['1002'], reason: 'diacritics fold');
      expect(await search('gu'), ['1002']);
      expect(await search('ogurt'), isEmpty, reason: 'prefixes only');
      expect(await search('oats tobys'), ['1003']);
      expect(await search('oats chobani'), isEmpty, reason: 'all parts');
    });

    test('orders by bm25 with name weighted over brand, then scans, then code',
        () async {
      await install([
        offProduct('2003', 'Peanut butter smooth', scans: 5),
        offProduct('2002', 'Peanut butter smooth', scans: 50),
        offProduct('2001', 'Peanut butter smooth', scans: 50),
        offProduct('2004', 'Crackers', brand: 'Peanut Co', scans: 900),
      ]);

      expect(await search('peanut'), ['2001', '2002', '2003', '2004']);
    });

    test('productsByCodes returns rows in the given order', () async {
      await install([offProduct('1', 'A'), offProduct('2', 'B')]);

      final rows = await database.productsByCodes(['2', 'missing', '1']);

      expect([for (final row in rows) row.code], ['2', '1']);
    });
  });

  group('keepProduct', () {
    OpenFoodFactsProductsCompanion kept(String name, int modifiedAt) {
      return productCompanion(
        offProduct('3001', name, modifiedAt: modifiedAt),
        origin: originOnline,
      );
    }

    test('keeps stored values for an older copy and always sets online',
        () async {
      await install([offProduct('3001', 'Bundled', modifiedAt: 200)]);

      await database.keepProduct(kept('Older', 100));

      final row = (await allProducts(database)).single;
      expect(row.name, 'Bundled');
      expect(row.modifiedAt, 200);
      expect(row.origin, originOnline);
    });

    test('takes the values of a newer copy', () async {
      await install([offProduct('3001', 'Bundled', modifiedAt: 200)]);

      await database.keepProduct(kept('Newer', 300));

      final row = (await allProducts(database)).single;
      expect(row.name, 'Newer');
      expect(row.modifiedAt, 300);
      expect(row.origin, originOnline);
      expect(await search('newer'), ['3001'], reason: 'the index follows');
      expect(await search('bundled'), isEmpty);
    });

    test('inserts a product the device did not have', () async {
      await database.keepProduct(kept('Fresh', 100));

      final row = (await allProducts(database)).single;
      expect(row.origin, originOnline);
      expect(row.name, 'Fresh');
    });
  });

  group('install', () {
    test('keeps a newer online row, replaces an older one, both stay online',
        () async {
      await database.keepProduct(productCompanion(
        offProduct('4001', 'Kept newer', modifiedAt: 500),
        origin: originOnline,
      ));
      await database.keepProduct(productCompanion(
        offProduct('4002', 'Kept older', modifiedAt: 100),
        origin: originOnline,
      ));

      await install([
        offProduct('4001', 'Bundle copy', modifiedAt: 300),
        offProduct('4002', 'Bundle copy', modifiedAt: 300),
      ]);

      final rows = await allProducts(database);
      expect([for (final row in rows) row.name], ['Kept newer', 'Bundle copy']);
      expect(
          [for (final row in rows) row.origin], [originOnline, originOnline]);
    });

    test('a reinstall deletes only bundle rows', () async {
      await install([offProduct('5001', 'Old'), offProduct('5002', 'Kept')]);
      await database.keepProduct(productCompanion(
        offProduct('5002', 'Kept'),
        origin: originOnline,
      ));

      await install([offProduct('5003', 'New')], hash: 'hash-2');

      final rows = await allProducts(database);
      expect([for (final row in rows) row.code], ['5002', '5003']);
      expect(rows.first.origin, originOnline);
      expect(rows.last.origin, originBundle);
      expect(await database.metaValue(bundleContentHashKey), 'hash-2');
    });

    test('resetAll then an install leaves the full bundle and no online rows',
        () async {
      await install([offProduct('6001', 'A'), offProduct('6002', 'B')]);
      await database.keepProduct(productCompanion(
        offProduct('6001', 'A', modifiedAt: 1760000500),
        origin: originOnline,
      ));
      await database.keepProduct(productCompanion(
        offProduct('6999', 'Opened'),
        origin: originOnline,
      ));

      await database.resetAll();
      expect(await database.metaValue(bundleContentHashKey), isNull);
      await install([offProduct('6001', 'A'), offProduct('6002', 'B')]);

      final rows = await allProducts(database);
      expect([for (final row in rows) row.code], ['6001', '6002']);
      expect(
        rows.every((row) => row.origin == originBundle),
        isTrue,
      );
    });

    test('a failure inside the install rolls back to the previous state',
        () async {
      await install([offProduct('7001', 'Before')]);

      await expectLater(
        database.replaceBundle(
          bundleLines([offProduct('7002', 'After')]),
          bundleHeader(contentHash: 'hash-2', productCount: 1),
          beforeCommitForTesting: () async => throw StateError('killed'),
        ),
        throwsStateError,
      );

      final rows = await allProducts(database);
      expect([for (final row in rows) row.code], ['7001']);
      expect(await database.metaValue(bundleContentHashKey), 'hash-1');
      expect(await search('before'), ['7001']);
    });

    test('stores nutrient text in the compact form', () async {
      await install([
        offProduct('8001', 'Bar', nutrients: const <NutrientId, String>{
          NutrientId.energy: '512',
          NutrientId.saturatedFat: '15.6',
        }),
      ]);

      final row = (await allProducts(database)).single;
      expect(row.nutrientsJson, '{"energy":"512","saturated_fat":"15.6"}');
      expect(decodeNutrientsJson(row.nutrientsJson), <NutrientId, String>{
        NutrientId.energy: '512',
        NutrientId.saturatedFat: '15.6',
      });
    });
  });

  test('isSqliteBusy sees SQLITE_BUSY directly and through the remote wrapper',
      () async {
    expect(
      isSqliteBusy(
        SqliteException(extendedResultCode: 5, message: 'database is locked'),
      ),
      isTrue,
    );
    expect(
      isSqliteBusy(
        SqliteException(extendedResultCode: 1, message: 'no such table'),
      ),
      isFalse,
    );
    expect(isSqliteBusy(StateError('other')), isFalse);

    // A real error from a background connection arrives wrapped.
    final directory = await Directory.systemTemp.createTemp('busy_');
    addTearDown(() => directory.delete(recursive: true));
    final background = FoodReferenceDatabase.connect(
      File('${directory.path}/r.sqlite'),
    );
    addTearDown(background.close);
    Object? caught;
    try {
      await background.customStatement('SELECT * FROM no_such_table');
    } on Object catch (error) {
      caught = error;
    }
    expect(caught, isA<DriftRemoteException>());
    expect(isSqliteBusy(caught!), isFalse, reason: 'not a busy error');
  });

  test('the user database has no Open Food Facts table', () {
    expect(
      AppDatabase.schemaTableNames.where(
        (table) => table.contains('open_food_facts'),
      ),
      isEmpty,
    );
  });

  test('keepProduct leaves a row the user opened online after an update',
      () async {
    await database.keepProduct(
      productCompanion(offProduct('9001', 'A'), origin: originBundle)
          .copyWith(brand: const Value('Brand')),
    );

    expect((await allProducts(database)).single.origin, originOnline);
  });
}
