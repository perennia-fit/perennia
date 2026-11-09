import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
// DriftRemoteException is how drift delivers an error from a background
// connection; isSqliteBusy needs its type to see the SQLite code inside.
// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;

import '../../domain/nutrition/food_aisle.dart';
import '../../domain/nutrition/nutrition.dart';
import '../../domain/nutrition/open_food_facts.dart';

part 'food_reference_database.g.dart';

/// Reference data the app can rebuild at any time: the Open Food Facts bundle
/// and the device cache of products the user opened or scanned. It lives in
/// its own file in the cache directory, so it stays out of `AppDatabase`, sync,
/// backups and the portable archive, and its install (about 41,000 rows, on
/// another isolate) can never hold a lock a Set or Food Entry save needs.
///
/// See docs/designs/open-food-facts.md, "Installing the bundle on the device",
/// and docs/designs/food-aisles.md, "On the device".
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

  /// The product's `FoodAisle` id, or `NULL` when it has none. Only the bundle
  /// install writes it: an `online` row has an Aisle only while the current
  /// bundle gives its code one. It is Perennia's label, not Open Food Facts
  /// data, so the newer-copy rule never writes or clears it.
  TextColumn get aisle => text().nullable()();
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
  static const aisleRankIndex = 'open_food_facts_products_aisle_rank';

  /// 2 added `aisle`, its index and the narrower update trigger.
  @override
  int get schemaVersion => 2;

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
    // Only a change to the indexed text rewrites the search entry, so writing
    // an Aisle or an `origin` leaves the FTS5 row alone.
    await customStatement('''
      CREATE TRIGGER open_food_facts_products_au
      AFTER UPDATE OF name, brand ON $productsTable BEGIN
        INSERT INTO $productsFtsTable($productsFtsTable, rowid, name, brand)
        VALUES ('delete', old.id, old.name, old.brand);
        INSERT INTO $productsFtsTable(rowid, name, brand)
        VALUES (new.id, new.name, new.brand);
      END''');
    // The Aisle list walks the first entries for one Aisle instead of
    // scanning and sorting every row.
    await customStatement(
      'CREATE INDEX $aisleRankIndex ON $productsTable (aisle, scans DESC, code)',
    );
  }

  /// Products matching an FTS5 [match] expression (from
  /// `buildFoodSearchMatch`): `bm25` ascending with name weighted 2 and brand
  /// 1, then scans descending (none counts as 0), then code ascending. With
  /// [aisle] (a `FoodAisle` id), only that Aisle's products; [limit] applies
  /// after the filter.
  Future<List<OpenFoodFactsProductRow>> searchProducts(
    String match,
    int limit, {
    String? aisle,
  }) {
    return customSelect(
      'SELECT p.* FROM $productsFtsTable '
      'JOIN $productsTable p ON p.id = $productsFtsTable.rowid '
      'WHERE $productsFtsTable MATCH ? '
      '${aisle == null ? '' : 'AND p.aisle = ? '}'
      'ORDER BY bm25($productsFtsTable, 2.0, 1.0), '
      'COALESCE(p.scans, 0) DESC, p.code ASC '
      'LIMIT ?',
      variables: [
        Variable.withString(match),
        if (aisle != null) Variable.withString(aisle),
        Variable.withInt(limit),
      ],
      readsFrom: {openFoodFactsProducts},
    ).map((row) => openFoodFactsProducts.map(row.data)).get();
  }

  /// An Aisle's products (by `FoodAisle` id), most scanned first, then code
  /// ascending. SQLite sorts `NULL` last in descending order, so `online` rows
  /// with no scan count come last. The order matches
  /// `open_food_facts_products_aisle_rank`, so the read walks the index.
  Future<List<OpenFoodFactsProductRow>> productsInAisle(
    String aisle,
    int limit,
  ) {
    return customSelect(
      'SELECT * FROM $productsTable WHERE aisle = ? '
      'ORDER BY scans DESC, code ASC LIMIT ?',
      variables: [Variable.withString(aisle), Variable.withInt(limit)],
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
  ///
  /// While the install holds the write lock this waits, within the same
  /// 5-second window as the busy timeout. The busy timeout alone is not
  /// enough: a writer that is waiting when the install commits gets
  /// SQLITE_BUSY at once (its snapshot went stale), which SQLite's busy
  /// handler does not retry, so the write is tried again here.
  Future<void> keepProduct(OpenFoodFactsProductsCompanion row) async {
    final deadline = DateTime.now().add(_busyWindow);
    while (true) {
      try {
        return await _keepOnce(row);
      } on Object catch (error) {
        if (!isSqliteBusy(error) || DateTime.now().isAfter(deadline)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  static const _busyWindow = Duration(seconds: 5);

  Future<void> _keepOnce(OpenFoodFactsProductsCompanion row) {
    final companion = row.copyWith(origin: const Value(originOnline));
    return transaction(() async {
      await into(openFoodFactsProducts).insert(
        companion,
        onConflict: _replaceWhenNewer(),
      );
      await (update(openFoodFactsProducts)
            ..where((table) => table.code.equals(companion.code.value)))
          .write(
        const OpenFoodFactsProductsCompanion(origin: Value(originOnline)),
      );
    });
  }

  /// The install, in one transaction so a killed install leaves the previous
  /// state, including the previous Aisles. In order:
  ///
  /// 1. read the codes of every `online` row;
  /// 2. delete every `bundle` row;
  /// 3. clear `aisle` on every `online` row, so an `online` row has an Aisle
  ///    only if the current bundle gives it one;
  /// 4. insert each product as `bundle` with its Aisle (a remaining row with
  ///    the same code can only be `online`; it takes the bundle's values only
  ///    when they are newer, and stays `online`; [_replaceWhenNewer] never
  ///    touches `aisle`);
  /// 5. for a code from step 1, set the row's `aisle` to the line's, whether
  ///    or not the row kept its newer values: the Aisle is Perennia's label,
  ///    not Open Food Facts data, so the change-date rule does not apply;
  /// 6. record the content hash.
  ///
  /// [beforeCommitForTesting] runs just before the transaction commits.
  /// See docs/designs/food-aisles.md, "On the device".
  Future<void> replaceBundle(
    Iterable<String> productLines,
    BundleHeader header, {
    Future<void> Function()? beforeCommitForTesting,
  }) {
    return transaction(() async {
      final onlineCodes = <String>{
        for (final row in await (selectOnly(openFoodFactsProducts)
              ..addColumns([openFoodFactsProducts.code])
              ..where(openFoodFactsProducts.origin.equals(originOnline)))
            .get())
          row.read(openFoodFactsProducts.code)!,
      };
      await (delete(openFoodFactsProducts)
            ..where((table) => table.origin.equals(originBundle)))
          .go();
      await customUpdate(
        "UPDATE $productsTable SET aisle = NULL WHERE origin = '$originOnline'",
        updates: {openFoodFactsProducts},
        updateKind: UpdateKind.update,
      );
      // Batches of a few thousand rows keep memory flat during the install.
      final lines = productLines.iterator;
      var more = lines.moveNext();
      while (more) {
        await batch((batch) {
          for (var count = 0; more && count < _installBatchSize; count += 1) {
            final line = decodeBundleProductLine(lines.current);
            batch.insert(
              openFoodFactsProducts,
              productCompanion(
                line.product,
                origin: originBundle,
                aisle: line.aisle,
              ),
              onConflict: _replaceWhenNewer(),
            );
            if (onlineCodes.contains(line.product.code)) {
              batch.update(
                openFoodFactsProducts,
                OpenFoodFactsProductsCompanion(aisle: Value(line.aisle?.name)),
                where: (table) => table.code.equals(line.product.code),
              );
            }
            more = lines.moveNext();
          }
        });
      }
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

  static const _installBatchSize = 2000;

  /// On a code that is already stored, take the incoming copy's values (never
  /// its `origin` or its `aisle`) only when it is newer.
  DoUpdate<$OpenFoodFactsProductsTable, OpenFoodFactsProductRow>
      _replaceWhenNewer() {
    return DoUpdate.withExcluded(
      (old, excluded) => OpenFoodFactsProductsCompanion.custom(
        name: excluded.name,
        brand: excluded.brand,
        isLiquid: excluded.isLiquid,
        servingLabel: excluded.servingLabel,
        servingSize: excluded.servingSize,
        packageSize: excluded.packageSize,
        nutrientsJson: excluded.nutrientsJson,
        modifiedAt: excluded.modifiedAt,
        scans: excluded.scans,
      ),
      target: [openFoodFactsProducts.code],
      where: (old, excluded) =>
          excluded.modifiedAt.isBiggerThan(old.modifiedAt),
    );
  }
}

/// The row for a mapped product, with [origin] `bundle` or `online`.
///
/// With `bundle`, `aisle` is [aisle]'s id (`NULL` when it is `null`). With
/// `online`, [aisle] must be `null` and `aisle` is left absent, so an insert
/// stores `NULL` and an update keeps the Aisle the row has: only the bundle
/// install gives a product an Aisle.
OpenFoodFactsProductsCompanion productCompanion(
  MappedOpenFoodFactsProduct product, {
  required String origin,
  FoodAisle? aisle,
}) {
  if (origin == originOnline && aisle != null) {
    throw ArgumentError.value(
      aisle,
      'aisle',
      'an online row is never given an Aisle',
    );
  }
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
    aisle: origin == originBundle ? Value(aisle?.name) : const Value.absent(),
  );
}

/// A stored row as the mapped product it was written from.
MappedOpenFoodFactsProduct productFromRow(OpenFoodFactsProductRow row) {
  return MappedOpenFoodFactsProduct(
    code: row.code,
    name: row.name,
    brand: row.brand,
    isLiquid: row.isLiquid,
    servingLabel: row.servingLabel,
    servingSize: row.servingSize,
    packageSize: row.packageSize,
    nutrientText: decodeNutrientsJson(row.nutrientsJson),
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(
      row.modifiedAt * 1000,
      isUtc: true,
    ),
    scans: row.scans,
  );
}

/// The compact nutrient form stored in `nutrients_json`: the same object a
/// bundle product line carries.
String encodeNutrientsJson(Map<NutrientId, String> text) {
  return jsonEncode(nutrientTextToJson(text));
}

Map<NutrientId, String> decodeNutrientsJson(String json) {
  return nutrientTextFromJson(jsonDecode(json) as Map<String, Object?>);
}

/// Whether [error] is SQLite's SQLITE_BUSY ("database is locked"). On the
/// app's background connection it arrives wrapped in a
/// [DriftRemoteException], whose message is the cause's, so check both.
bool isSqliteBusy(Object error) {
  final cause = error is DriftRemoteException ? error.remoteCause : error;
  return cause is SqliteException && cause.resultCode == _sqliteBusy;
}

const _sqliteBusy = 5;
