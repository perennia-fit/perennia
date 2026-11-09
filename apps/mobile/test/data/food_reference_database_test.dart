import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart' show SqliteException;
// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/local/food_reference_database.dart';
import 'package:perennia/domain/nutrition/food_aisle.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/domain/nutrition/open_food_facts.dart';

import 'open_food_facts_fixtures.dart';

/// The reference database's rules: the FTS5 search, one row per barcode with
/// newer-copy values, `origin` as why a row is kept, and the one-transaction
/// install (docs/designs/open-food-facts.md, "One product, one row"), and the
/// Aisle column (docs/designs/food-aisles.md, "On the device").
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
    Map<String, FoodAisle> aisles = const {},
  }) {
    return database.replaceBundle(
      bundleLines(products, aisles: aisles),
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

  group('Aisles', () {
    Future<Map<String, String?>> aislesByCode() async {
      return {
        for (final row in await allProducts(database)) row.code: row.aisle,
      };
    }

    OpenFoodFactsProductsCompanion online(
      String code,
      String name, {
      int modifiedAt = 1760000000,
    }) {
      return productCompanion(
        offProduct(code, name, modifiedAt: modifiedAt),
        origin: originOnline,
      );
    }

    test('the install writes each product line\'s Aisle', () async {
      await install(
        [
          offProduct('a1', 'Milk'),
          offProduct('a2', 'Oats'),
          offProduct('a3', 'X')
        ],
        aisles: {'a1': FoodAisle.dairyEggs, 'a2': FoodAisle.breakfastCereals},
      );

      expect(await aislesByCode(), {
        'a1': 'dairyEggs',
        'a2': 'breakfastCereals',
        'a3': null,
      });
    });

    test('an online row that keeps its newer values takes the bundle\'s Aisle',
        () async {
      await database.keepProduct(online('b1', 'Kept newer', modifiedAt: 500));
      await database.keepProduct(online('b2', 'Kept older', modifiedAt: 100));

      await install(
        [
          offProduct('b1', 'Bundle copy', modifiedAt: 300),
          offProduct('b2', 'Bundle copy', modifiedAt: 300),
        ],
        aisles: {'b1': FoodAisle.snacks, 'b2': FoodAisle.drinks},
      );

      final rows = await allProducts(database);
      expect([for (final row in rows) row.name], ['Kept newer', 'Bundle copy']);
      expect(
          [for (final row in rows) row.origin], [originOnline, originOnline]);
      expect([for (final row in rows) row.aisle], ['snacks', 'drinks']);
    });

    test('a new bundle changes and clears an online row\'s Aisle', () async {
      await install(
        [offProduct('c1', 'Milk'), offProduct('c2', 'Bread')],
        aisles: {'c1': FoodAisle.dairyEggs, 'c2': FoodAisle.breadBakery},
      );
      await database.keepProduct(online('c1', 'Milk'));
      await database.keepProduct(online('c2', 'Bread'));

      // c1 stays in the bundle with another Aisle, then with none; c2 leaves.
      await install(
        [offProduct('c1', 'Milk')],
        hash: 'hash-2',
        aisles: {'c1': FoodAisle.drinks},
      );
      expect(await aislesByCode(), {'c1': 'drinks', 'c2': null});

      await install([offProduct('c1', 'Milk')], hash: 'hash-3');
      expect(await aislesByCode(), {'c1': null, 'c2': null});
    });

    test('keepProduct leaves the Aisle, for a newer and an older copy',
        () async {
      await install(
        [offProduct('d1', 'Bundled', modifiedAt: 200)],
        aisles: {'d1': FoodAisle.pantry},
      );

      await database.keepProduct(online('d1', 'Older', modifiedAt: 100));
      expect((await allProducts(database)).single.aisle, 'pantry');
      expect((await allProducts(database)).single.name, 'Bundled');

      await database.keepProduct(online('d1', 'Newer', modifiedAt: 300));
      final row = (await allProducts(database)).single;
      expect(row.name, 'Newer');
      expect(row.origin, originOnline);
      expect(row.aisle, 'pantry');
    });

    test('keepProduct on a new code stores no Aisle', () async {
      await database.keepProduct(online('e1', 'Fresh'));

      expect((await allProducts(database)).single.aisle, isNull);
    });

    test('productCompanion rejects an Aisle on an online row', () {
      expect(
        () => productCompanion(
          offProduct('f1', 'A'),
          origin: originOnline,
          aisle: FoodAisle.snacks,
        ),
        throwsArgumentError,
      );
      expect(
        productCompanion(
          offProduct('f1', 'A'),
          origin: originOnline,
        ).aisle,
        const Value<String?>.absent(),
      );
      expect(
        productCompanion(
          offProduct('f1', 'A'),
          origin: originBundle,
          aisle: FoodAisle.snacks,
        ).aisle,
        const Value<String?>('snacks'),
      );
    });

    test(
        'productsInAisle orders by scans descending, NULL scans last, then code',
        () async {
      await install(
        [
          offProduct('g3', 'C', scans: 5),
          offProduct('g2', 'B', scans: 50),
          offProduct('g1', 'A', scans: 50),
          offProduct('g4', 'D', scans: 900),
          offProduct('g5', 'Other Aisle', scans: 1000),
        ],
        aisles: {
          'g1': FoodAisle.snacks,
          'g2': FoodAisle.snacks,
          'g3': FoodAisle.snacks,
          'g4': FoodAisle.snacks,
          'g5': FoodAisle.drinks,
        },
      );
      // An online row with no scan count that the bundle gives an Aisle.
      await database.keepProduct(
        productCompanion(
          MappedOpenFoodFactsProduct(
            code: 'g0',
            name: 'No scans',
            brand: null,
            isLiquid: false,
            servingLabel: null,
            servingSize: null,
            packageSize: null,
            nutrientText: const <NutrientId, String>{},
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            scans: null,
          ),
          origin: originOnline,
        ),
      );
      await database.customStatement(
        "UPDATE open_food_facts_products SET aisle = 'snacks' "
        "WHERE code = 'g0'",
      );

      final rows = await database.productsInAisle('snacks', 100);
      expect(
          [for (final row in rows) row.code], ['g4', 'g1', 'g2', 'g3', 'g0']);
      final limited = await database.productsInAisle('snacks', 2);
      expect([for (final row in limited) row.code], ['g4', 'g1']);
      expect(await database.productsInAisle('babyFood', 100), isEmpty);
    });

    test('searchProducts with an Aisle keeps only that Aisle, then the limit',
        () async {
      await install(
        [
          offProduct('h1', 'Greek yogurt', scans: 10),
          offProduct('h2', 'Greek yogurt bar', scans: 900),
          offProduct('h3', 'Greek yogurt plain', scans: 5),
        ],
        aisles: {
          'h1': FoodAisle.dairyEggs,
          'h2': FoodAisle.snacks,
          'h3': FoodAisle.dairyEggs,
        },
      );
      final match = buildFoodSearchMatch('greek yo')!;

      final dairy =
          await database.searchProducts(match, 50, aisle: 'dairyEggs');
      expect([for (final row in dairy) row.code], ['h1', 'h3']);
      final one = await database.searchProducts(match, 1, aisle: 'dairyEggs');
      expect([for (final row in one) row.code], ['h1']);
      final all = await database.searchProducts(match, 50);
      expect(all, hasLength(3));
    });

    test('the update trigger fires only on name and brand', () async {
      final sql = await database
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'trigger' "
            "AND name = 'open_food_facts_products_au'",
          )
          .getSingle();
      expect(sql.read<String>('sql'), contains('AFTER UPDATE OF name, brand'));

      await install(
        [offProduct('i1', 'Crackers')],
        aisles: {'i1': FoodAisle.snacks},
      );
      await database.customStatement(
        "UPDATE open_food_facts_products SET aisle = 'pantry' WHERE code = 'i1'",
      );
      expect(await search('crackers'), ['i1']);
    });

    test('a killed install keeps the previous bundle\'s Aisles', () async {
      await install(
        [offProduct('j1', 'Milk'), offProduct('j2', 'Bread')],
        aisles: {'j1': FoodAisle.dairyEggs, 'j2': FoodAisle.breadBakery},
      );
      await database.keepProduct(online('j2', 'Bread'));

      await expectLater(
        database.replaceBundle(
          bundleLines(
            [offProduct('j1', 'Milk')],
            aisles: {'j1': FoodAisle.drinks},
          ),
          bundleHeader(contentHash: 'hash-2', productCount: 1),
          beforeCommitForTesting: () async => throw StateError('killed'),
        ),
        throwsStateError,
      );

      expect(await aislesByCode(), {'j1': 'dairyEggs', 'j2': 'breadBakery'});
      expect(await database.metaValue(bundleContentHashKey), 'hash-1');
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
