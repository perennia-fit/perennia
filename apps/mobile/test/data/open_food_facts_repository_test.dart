import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/data/local/food_reference_database.dart';
import 'package:perennia/data/open_food_facts/open_food_facts_client.dart';
import 'package:perennia/data/repositories/open_food_facts_repository.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';

import 'open_food_facts_fixtures.dart';

/// The app's Open Food Facts repository over a real in-memory reference
/// database: device search, live lookups and what they store.
void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
      warnAboutMultipleDatabases);

  late FoodReferenceDatabase database;
  late List<http.Request> requests;
  late DriftOpenFoodFactsRepository repository;

  final liveProduct = <String, Object?>{
    'code': '9300633603427',
    'product_name': 'Weet-Bix',
    'brands': 'Sanitarium',
    'last_modified_t': 1760000900,
    'unique_scans_n': 30,
    'nutriments': <String, Object?>{'energy-kcal_100g': 352},
  };

  setUp(() async {
    database = FoodReferenceDatabase.memory();
    requests = <http.Request>[];
    repository = DriftOpenFoodFactsRepository.forTesting(
      database: database,
      asset: FixtureBundleAsset(bundleBytes([
        offProduct('0818290014313', 'Greek Yogurt Plain', brand: 'Chobani'),
        offProduct('5000159484695', 'Twix', brand: 'Mars'),
        offProduct('818290014313', 'Yogurt look-alike'),
      ])),
      client: OpenFoodFactsClient(
        baseUrl: Uri.parse('https://off.test/'),
        httpClient: MockClient((request) async {
          requests.add(request);
          final body = request.url.path.endsWith('search.pl')
              ? <String, Object?>{
                  'products': <Object?>[liveProduct]
                }
              : <String, Object?>{'status': 'success', 'product': liveProduct};
          return http.Response(jsonEncode(body), 200);
        }),
      ),
    );
    await repository.ensureBundleInstalled();
  });

  tearDown(() => repository.close());

  test('barcode candidates come first in local search', () async {
    final results = await repository.searchLocal('818290014313');

    // The 12-digit code as given, then with its leading zero; then the FTS5
    // search, without duplicates.
    expect(
      [for (final record in results) record.id],
      ['818290014313', '0818290014313'],
    );
    expect(results.last.brand, 'Chobani');
    expect(results.last.foodSource, FoodSource.openFoodFacts);
    expect(requests, isEmpty);
  });

  test('device search matches word prefixes and sends nothing', () async {
    final results = await repository.searchLocal('greek yog');

    expect(results.single.id, '0818290014313');
    expect(results.single.sourceModifiedAt, isNotNull);
    expect(requests, isEmpty);
  });

  test('a live search returns products and stores nothing', () async {
    final result = await repository.searchOnline('weet', allowOnline: true);

    expect(result.status, OnlineSearchStatus.ok);
    expect(result.products.single.id, '9300633603427');
    expect(result.products.single.brand, 'Sanitarium');
    expect(requests, hasLength(1));
    expect(
      await database.productsByCodes(<String>['9300633603427']),
      isEmpty,
    );
  });

  test('keepOpenedProduct stores the product as online', () async {
    final live = (await repository.searchOnline('weet', allowOnline: true))
        .products
        .single;

    await repository.keepOpenedProduct(live);

    final row =
        (await database.productsByCodes(<String>['9300633603427'])).single;
    expect(row.origin, originOnline);
    expect(row.name, 'Weet-Bix');
    expect(row.brand, 'Sanitarium');
    expect(row.modifiedAt, 1760000900);
    expect(decodeNutrientsJson(row.nutrientsJson), <NutrientId, String>{
      NutrientId.energy: '352',
    });
  });

  test('a live barcode hit is returned and stored as online', () async {
    final result = await repository.lookupBarcode(
      '9300633603427',
      allowOnline: true,
    );
    await pumpEventQueue();

    expect(result.status, BarcodeLookupOutcome.found);
    expect(result.product?.name, 'Weet-Bix');
    expect(
      requests.single.url.path,
      '/api/v3.6/product/9300633603427.json',
    );
    final row =
        (await database.productsByCodes(<String>['9300633603427'])).single;
    expect(row.origin, originOnline);

    // The next scan finds it on the device and sends nothing.
    final again = await repository.lookupBarcode(
      '9300633603427',
      allowOnline: true,
    );
    expect(again.status, BarcodeLookupOutcome.found);
    expect(requests, hasLength(1));
  });

  test('a stored barcode is found with nothing sent', () async {
    final result = await repository.lookupBarcode(
      '5000159484695',
      allowOnline: true,
    );

    expect(result.status, BarcodeLookupOutcome.found);
    expect(result.product?.name, 'Twix');
    expect(requests, isEmpty);
  });

  test('text that is not a barcode is not looked up', () async {
    final result = await repository.lookupBarcode('twix', allowOnline: true);

    expect(result.status, BarcodeLookupOutcome.notABarcode);
    expect(requests, isEmpty);
  });

  test('nothing is sent when allowOnline is false', () async {
    final search = await repository.searchOnline('weet', allowOnline: false);
    final barcode = await repository.lookupBarcode(
      '9300633603427',
      allowOnline: false,
    );

    expect(search.status, OnlineSearchStatus.disabled);
    expect(barcode.status, BarcodeLookupOutcome.disabled);
    expect(requests, isEmpty);
  });

  test('resetDeviceData leaves the full bundle and an empty device cache',
      () async {
    await repository.keepOpenedProduct(
      (await repository.searchOnline('weet', allowOnline: true))
          .products
          .single,
    );
    await repository.keepOpenedProduct(
      (await repository.searchLocal('twix')).single,
    );

    await repository.resetDeviceData();

    final rows = await allProducts(database);
    expect(
      [for (final row in rows) row.code],
      ['0818290014313', '5000159484695', '818290014313'],
    );
    expect(rows.every((row) => row.origin == originBundle), isTrue);
  });

  test('the status stream gives the current status first', () async {
    expect(await repository.watchBundleStatus().first, BundleStatus.ready);
    expect((await repository.bundleHeader())?.productCount, 3);
  });

  test('a repository whose cache directory fails reports failed', () async {
    final broken = DriftOpenFoodFactsRepository(
      databaseFile: () async => throw StateError('no cache directory'),
      client: OpenFoodFactsClient(
        httpClient: MockClient((_) async => http.Response('', 500)),
      ),
    );
    addTearDown(broken.close);

    await broken.ensureBundleInstalled();

    expect(await broken.watchBundleStatus().first, BundleStatus.failed);
    expect(await broken.searchLocal('twix'), isEmpty);
  });
}
