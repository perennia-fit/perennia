import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../domain/nutrition/nutrition.dart';
import '../../domain/nutrition/open_food_facts.dart';

part 'food_reference_database.g.dart';

/// Reference data the app can rebuild at any time: the Open Food Facts bundle
/// and the device cache of products the user opened or scanned. It lives in
/// its own file in the cache directory, so it stays out of `AppDatabase`, sync,
/// backups and the portable archive, and its install (about 41,000 rows, on
/// another isolate) can never hold a lock a Set or Food Entry save needs.
///
/// See docs/designs/open-food-facts.md, "Installing the bundle on the device".
@DataClassName('ReferenceMetaRow')
class ReferenceMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// One row per barcode. `origin` records why the row is kept (`bundle`: the
/// current bundle contains it; `online`: the user opened or scanned it), not
/// where its values came from; values are replaced only by a copy with a
/// later `modified_at`. See "One product, one row" in the spec.
@DataClassName('OpenFoodFactsProductRow')
class OpenFoodFactsProducts extends Table {
  /// The FTS5 row id. The database is never vacuumed, so ids stay stable.
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().unique()();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  BoolColumn get isLiquid => boolean()();
  TextColumn get servingLabel => text().nullable()();
  RealColumn get servingSize => real().nullable()();
  RealColumn get packageSize => real().nullable()();

  /// The compact form: Nutrient storage key → entered text, as in a bundle
  /// product line.
  TextColumn get nutrientsJson => text()();

  /// Unix seconds.
  IntColumn get modifiedAt => integer()();
  IntColumn get scans => integer().nullable()();
  TextColumn get origin => text()();
}

const originBundle = 'bundle';
const originOnline = 'online';
const bundleContentHashKey = 'bundle_content_hash';

@DriftDatabase(tables: [ReferenceMeta, OpenFoodFactsProducts])
class FoodReferenceDatabase extends _$FoodReferenceDatabase {
  FoodReferenceDatabase(super.executor);

  factory FoodReferenceDatabase.memory() {
    return FoodReferenceDatabase(NativeDatabase.memory(setup: _setup));
  }

  /// The app's connection, on a background isolate so queries never block
  /// the UI isolate.
  factory FoodReferenceDatabase.connect(File file) {
    return FoodReferenceDatabase(
      NativeDatabase.createInBackground(file, setup: _setup),
    );
  }

  /// The installer's connection, opened inside the install isolate.
  factory FoodReferenceDatabase.openInIsolate(File file) {
    return FoodReferenceDatabase(NativeDatabase(file, setup: _setup));
  }

  /// WAL keeps a reader on one connection unblocked by a writer on another;
  /// the busy timeout makes a second writer wait for the lock instead of
  /// failing at once.
  static void _setup(dynamic database) {
    database
      ..execute('PRAGMA journal_mode=WAL')
      ..execute('PRAGMA busy_timeout=5000');
  }

  static const productsTable = 'open_food_facts_products';
  static const productsFtsTable = 'open_food_facts_products_fts';

  @override
  int get schemaVersion => 1;

  /// No migrations: the data can be rebuilt, so a new schema drops everything
  /// and the missing content hash makes the installer run.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
          await _createSearchIndex();
        },
        onUpgrade: (migrator, from, to) async {
          for (final statement in const <String>[
            'DROP TRIGGER IF EXISTS open_food_facts_products_ai',
            'DROP TRIGGER IF EXISTS open_food_facts_products_ad',
            'DROP TRIGGER IF EXISTS open_food_facts_products_au',
            'DROP TABLE IF EXISTS $productsFtsTable',
            'DROP TABLE IF EXISTS $productsTable',
            'DROP TABLE IF EXISTS reference_meta',
          ]) {
            await customStatement(statement);
          }
          await migrator.createAll();
          await _createSearchIndex();
        },
      );

  Future<void> _createSearchIndex() async {
    await customStatement('''
      CREATE VIRTUAL TABLE $productsFtsTable USING fts5(
        name, brand,
        content='$productsTable', content_rowid='id',
        tokenize='unicode61 remove_diacritics 2'
      )''');
    await customStatement('''
      CREATE TRIGGER open_food_facts_products_ai
      AFTER INSERT ON $productsTable BEGIN
        INSERT INTO $productsFtsTable(rowid, name, brand)
        VALUES (new.id, new.name, new.brand);
      END''');
    await customStatement('''
      CREATE TRIGGER open_food_facts_products_ad
      AFTER DELETE ON $productsTable BEGIN
        INSERT INTO $productsFtsTable($productsFtsTable, rowid, name, brand)
        VALUES ('delete', old.id, old.name, old.brand);
      END''');
    await customStatement('''
      CREATE TRIGGER open_food_facts_products_au
      AFTER UPDATE ON $productsTable BEGIN
        INSERT INTO $productsFtsTable($productsFtsTable, rowid, name, brand)
        VALUES ('delete', old.id, old.name, old.brand);
        INSERT INTO $productsFtsTable(rowid, name, brand)
        VALUES (new.id, new.name, new.brand);
      END''');
  }

  /// Products matching an FTS5 [match] expression (from
  /// `buildFoodSearchMatch`): `bm25` ascending with name weighted 2 and brand
  /// 1, then scans descending (none counts as 0), then code ascending.
  Future<List<OpenFoodFactsProductRow>> searchProducts(
    String match,
    int limit,
  ) {
    return customSelect(
      'SELECT p.* FROM $productsFtsTable '
      'JOIN $productsTable p ON p.id = $productsFtsTable.rowid '
      'WHERE $productsFtsTable MATCH ? '
      'ORDER BY bm25($productsFtsTable, 2.0, 1.0), '
      'COALESCE(p.scans, 0) DESC, p.code ASC '
      'LIMIT ?',
      variables: [Variable.withString(match), Variable.withInt(limit)],
      readsFrom: {openFoodFactsProducts},
    ).map((row) => openFoodFactsProducts.map(row.data)).get();
  }

  /// The products with these [codes], in the given order.
  Future<List<OpenFoodFactsProductRow>> productsByCodes(
    List<String> codes,
  ) async {
    if (codes.isEmpty) {
      return const <OpenFoodFactsProductRow>[];
    }
    final rows = await (select(openFoodFactsProducts)
          ..where((table) => table.code.isIn(codes)))
        .get();
    final byCode = {for (final row in rows) row.code: row};
    return [
      for (final code in codes)
        if (byCode[code] case final row?) row,
    ];
  }

  /// Keeps a product the user opened or scanned. The row always becomes
  /// `online`; its values are replaced only by a copy with a later
  /// `modified_at`.
  Future<void> keepProduct(OpenFoodFactsProductsCompanion row) {
    final companion = row.copyWith(origin: const Value(originOnline));
    return transaction(() async {
      await _upsertNewer(companion);
      await (update(openFoodFactsProducts)
            ..where((table) => table.code.equals(companion.code.value)))
          .write(
        const OpenFoodFactsProductsCompanion(origin: Value(originOnline)),
      );
    });
  }

  /// The install, in one transaction so a killed install leaves the previous
  /// state: delete every `bundle` row, insert each product as `bundle` (a
  /// remaining row with the same code can only be `online`; it takes the
  /// bundle's values only when they are newer, and stays `online`), then
  /// record the content hash. [beforeCommitForTesting] runs just before the
  /// transaction commits.
  Future<void> replaceBundle(
    Iterable<String> productLines,
    BundleHeader header, {
    Future<void> Function()? beforeCommitForTesting,
  }) {
    return transaction(() async {
      await (delete(openFoodFactsProducts)
            ..where((table) => table.origin.equals(originBundle)))
          .go();
      await batch((batch) {
        for (final line in productLines) {
          final product = decodeBundleProductLine(line);
          batch.customStatement(
              _upsertNewerSql,
              _upsertVariables(
                productCompanion(product, origin: originBundle),
              ));
        }
      });
      await setMeta(bundleContentHashKey, header.contentHash);
      await beforeCommitForTesting?.call();
    });
  }

  /// Deletes every product row and the stored content hash; the next install
  /// then restores the full bundle with an empty device cache.
  Future<void> resetAll() {
    return transaction(() async {
      await delete(openFoodFactsProducts).go();
      await (delete(referenceMeta)
            ..where((table) => table.key.equals(bundleContentHashKey)))
          .go();
    });
  }

  Future<String?> metaValue(String key) async {
    final row = await (select(referenceMeta)
          ..where((table) => table.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setMeta(String key, String value) {
    return into(referenceMeta).insertOnConflictUpdate(
      ReferenceMetaCompanion.insert(key: key, value: value),
    );
  }

  Future<void> _upsertNewer(OpenFoodFactsProductsCompanion row) {
    return customStatement(_upsertNewerSql, _upsertVariables(row));
  }

  /// Inserts a product, or replaces an existing row's values (never its
  /// `origin`) when the incoming copy is newer.
  static const _upsertNewerSql = '''
    INSERT INTO $productsTable (
      code, name, brand, is_liquid, serving_label, serving_size, package_size,
      nutrients_json, modified_at, scans, origin
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(code) DO UPDATE SET
      name = excluded.name,
      brand = excluded.brand,
      is_liquid = excluded.is_liquid,
      serving_label = excluded.serving_label,
      serving_size = excluded.serving_size,
      package_size = excluded.package_size,
      nutrients_json = excluded.nutrients_json,
      modified_at = excluded.modified_at,
      scans = excluded.scans
    WHERE excluded.modified_at > $productsTable.modified_at''';

  static List<Object?> _upsertVariables(OpenFoodFactsProductsCompanion row) {
    return <Object?>[
      row.code.value,
      row.name.value,
      row.brand.present ? row.brand.value : null,
      row.isLiquid.value ? 1 : 0,
      row.servingLabel.present ? row.servingLabel.value : null,
      row.servingSize.present ? row.servingSize.value : null,
      row.packageSize.present ? row.packageSize.value : null,
      row.nutrientsJson.value,
      row.modifiedAt.value,
      row.scans.present ? row.scans.value : null,
      row.origin.value,
    ];
  }
}

/// The row for a mapped product, with [origin] `bundle` or `online`.
OpenFoodFactsProductsCompanion productCompanion(
  MappedOpenFoodFactsProduct product, {
  required String origin,
}) {
  return OpenFoodFactsProductsCompanion.insert(
    code: product.code,
    name: product.name,
    brand: Value(product.brand),
    isLiquid: product.isLiquid,
    servingLabel: Value(product.servingLabel),
    servingSize: Value(product.servingSize),
    packageSize: Value(product.packageSize),
    nutrientsJson: encodeNutrientsJson(product.nutrientText),
    modifiedAt: product.modifiedAt.millisecondsSinceEpoch ~/ 1000,
    scans: Value(product.scans),
    origin: origin,
  );
}

/// The compact nutrient form stored in `nutrients_json`, the same object a
/// bundle product line carries.
String encodeNutrientsJson(Map<NutrientId, String> text) {
  return jsonEncode(<String, String>{
    for (final id in NutrientId.values)
      if (text[id] case final entered?) id.storageKey: entered,
  });
}

Map<NutrientId, String> decodeNutrientsJson(String json) {
  final decoded = jsonDecode(json) as Map<String, Object?>;
  return <NutrientId, String>{
    for (final MapEntry(:key, :value) in decoded.entries)
      NutrientId.byStorageKey(key): value! as String,
  };
}
