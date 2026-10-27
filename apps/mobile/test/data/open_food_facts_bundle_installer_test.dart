import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/food_reference_database.dart';
import 'package:perennia/data/open_food_facts/open_food_facts_bundle_installer.dart';

import 'open_food_facts_fixtures.dart';

/// The installer: installs when the content hash changes, never throws, runs
/// one install at a time, and gives a new listener the current status first
/// (docs/designs/open-food-facts.md, "Installing the bundle on the device").
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
      warnAboutMultipleDatabases);

  late FoodReferenceDatabase database;

  setUp(() => database = FoodReferenceDatabase.memory());
  tearDown(() => database.close());

  OpenFoodFactsBundleInstaller installerFor(BundleAssetSource asset) {
    return OpenFoodFactsBundleInstaller(database: database, asset: asset);
  }

  test('installs a small fixture bundle', () async {
    final installer = installerFor(FixtureBundleAsset(bundleBytes([
      offProduct('1', 'Oats', brand: 'Uncle Tobys'),
      offProduct('2', 'Milk'),
    ])));

    await installer.ensureInstalled();

    expect(installer.currentStatus, BundleStatus.ready);
    final rows = await allProducts(database);
    expect([for (final row in rows) row.code], ['1', '2']);
    expect(rows.first.brand, 'Uncle Tobys');
    expect(rows.every((row) => row.origin == originBundle), isTrue);
    expect(await database.metaValue(bundleContentHashKey), 'hash-1');
  });

  test('skips a bundle whose hash matches and reinstalls when it differs',
      () async {
    final asset = FixtureBundleAsset(bundleBytes([offProduct('1', 'Oats')]));
    final installer = installerFor(asset);
    await installer.ensureInstalled();
    await database.into(database.openFoodFactsProducts).insert(
          productCompanion(offProduct('9', 'Planted'), origin: originBundle),
        );

    await installer.ensureInstalled();
    expect(
      [for (final row in await allProducts(database)) row.code],
      ['1', '9'],
      reason: 'a matching hash leaves the rows alone',
    );

    asset.bytes = bundleBytes([offProduct('2', 'Milk')], contentHash: 'hash-2');
    await installer.ensureInstalled();
    expect(
      [for (final row in await allProducts(database)) row.code],
      ['2'],
    );
    expect(installer.currentStatus, BundleStatus.ready);
  });

  test('reports failed, without throwing, for a corrupt or unknown bundle',
      () async {
    for (final asset in <BundleAssetSource>[
      FixtureBundleAsset(Uint8List.fromList(<int>[1, 2, 3])),
      FixtureBundleAsset(
          bundleBytes([offProduct('1', 'Oats')], formatVersion: 2)),
      const ThrowingBundleAsset(),
    ]) {
      final installer = installerFor(asset);

      await installer.ensureInstalled();

      expect(installer.currentStatus, BundleStatus.failed);
      expect(await allProducts(database), isEmpty);
    }
  });

  test('a second call during an install returns the same future', () async {
    final loads = Completer<Uint8List>();
    final asset = _DeferredAsset(loads.future);
    final installer = installerFor(asset);

    final first = installer.ensureInstalled();
    final second = installer.ensureInstalled();
    expect(identical(first, second), isTrue);

    loads.complete(bundleBytes([offProduct('1', 'Oats')]));
    await Future.wait([first, second]);
    expect(asset.loads, 1);
    expect(installer.currentStatus, BundleStatus.ready);
  });

  test('a new status listener receives the current status first', () async {
    final installer = installerFor(
      FixtureBundleAsset(bundleBytes([offProduct('1', 'Oats')])),
    );
    final early = <BundleStatus>[];
    final subscription = installer.watchStatus().listen(early.add);

    await installer.ensureInstalled();
    await pumpEventQueue();
    final late = await installer.watchStatus().first;

    expect(early, [
      BundleStatus.unknown,
      BundleStatus.installing,
      BundleStatus.ready,
    ]);
    expect(late, BundleStatus.ready);
    await subscription.cancel();
  });

  test('bundleHeader reads the asset header', () async {
    final installer = installerFor(
      FixtureBundleAsset(bundleBytes([offProduct('1', 'Oats')])),
    );

    final header = await installer.bundleHeader();

    expect(header?.datasetVersion, '2026-10-26');
    expect(header?.productCount, 1);
  });
}

class _DeferredAsset implements BundleAssetSource {
  _DeferredAsset(this._bytes);

  final Future<Uint8List> _bytes;
  int loads = 0;

  @override
  Future<Uint8List> load() {
    loads += 1;
    return _bytes;
  }
}
