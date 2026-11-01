import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/local/food_reference_database.dart';
import 'package:perennia/data/open_food_facts/open_food_facts_client.dart';
import 'package:perennia/data/repositories/open_food_facts_repository.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/nutrition/controllers/add_food_controller.dart';
import 'package:perennia/features/nutrition/repositories/add_food_repository.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';

import '../../data/open_food_facts_fixtures.dart';

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

  group('AddFoodPickerState', () {
    test('defensively copies result inputs and exposes immutable views', () {
      final sourceResults = <FoodPickerItem>[_food('recent-chicken')];

      final state = AddFoodPickerState(
        query: 'chicken',
        filter: AddFoodPickerFilter.all,
        results: sourceResults,
      );

      sourceResults.add(_food('recent-yogurt'));

      expect(state.results.map((food) => food.id), <String>['recent-chicken']);
      expect(
        () => state.results.add(_food('recent-rice')),
        throwsUnsupportedError,
      );

      final nextResults = <FoodPickerItem>[_food('user-tuna')];
      final copied = state.copyWith(
        filter: AddFoodPickerFilter.yours,
        results: nextResults,
      );

      nextResults.clear();

      expect(copied.results.map((food) => food.id), <String>['user-tuna']);
      expect(
        () => copied.results.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('AddFoodPickerController', () {
    test('starts on All with an empty query and reads Your foods once',
        () async {
      final yourFoods = YourFoods([_food('user-oats')]);
      final repository = _FakeAddFoodRepository(yourFoods: yourFoods);
      final container = _container(repository);
      container.listen(addFoodPickerControllerProvider, (_, __) {});

      final first =
          await container.read(addFoodPickerControllerProvider.future);
      final notifier = container.read(addFoodPickerControllerProvider.notifier);
      await notifier.setQuery('oat');
      await Future<void>.delayed(
        AddFoodPickerController.searchDebounceDuration * 2,
      );
      await notifier.selectFilter(AddFoodPickerFilter.usda);
      await notifier.selectFilter(AddFoodPickerFilter.all);
      await notifier.submitQuery('oats');

      expect(first.filter, AddFoodPickerFilter.all);
      expect(first.query, '');
      expect(first.results.map((item) => item.id), ['user-oats']);
      expect(repository.loadCalls, 1);
      expect(repository.searches.length, greaterThan(3));
      expect(
        repository.searches.map((search) => search.yourFoods),
        everyElement(same(yourFoods)),
      );
    });

    test('a failing Your foods read still serves Catalogue results', () async {
      final repository = _FakeAddFoodRepository(
        failLoad: true,
        catalogue: [_food('usda-chicken', origin: FoodPickerOrigin.usda)],
      );
      final container = _container(repository);
      container.listen(addFoodPickerControllerProvider, (_, __) {});
      await container.read(addFoodPickerControllerProvider.future);

      await container
          .read(addFoodPickerControllerProvider.notifier)
          .submitQuery('chicken');

      final state = container.read(addFoodPickerControllerProvider).value!;
      expect(state.results.map((item) => item.id), ['usda-chicken']);
      expect(
        repository.searches.map((search) => search.yourFoods),
        everyElement(same(YourFoods.empty)),
      );
    });

    test('submitting in All sends one live search, or looks a barcode up',
        () async {
      final repository = _FakeAddFoodRepository();
      final container = _container(repository);
      container.listen(addFoodPickerControllerProvider, (_, __) {});
      await container.read(addFoodPickerControllerProvider.future);
      final notifier = container.read(addFoodPickerControllerProvider.notifier);

      await notifier.submitQuery('hazel');
      await notifier.submitQuery('3017620422003');

      expect(repository.onlineQueries, ['hazel']);
      expect(repository.barcodes, ['3017620422003']);
    });

    test('submitting in Your foods or USDA sends nothing', () async {
      final repository = _FakeAddFoodRepository();
      final container = _container(repository);
      container.listen(addFoodPickerControllerProvider, (_, __) {});
      await container.read(addFoodPickerControllerProvider.future);
      final notifier = container.read(addFoodPickerControllerProvider.notifier);

      for (final filter in [
        AddFoodPickerFilter.yours,
        AddFoodPickerFilter.usda,
      ]) {
        await notifier.selectFilter(filter);
        expect(await notifier.submitQuery('hazel'), isNull);
        expect(await notifier.submitQuery('3017620422003'), isNull);
      }

      expect(repository.onlineQueries, isEmpty);
      expect(repository.barcodes, isEmpty);
    });

    test('submitting in All with online lookups off sends no request',
        () async {
      for (final enabled in [true, false]) {
        final requests = <http.Request>[];
        final database = AppDatabase.inMemory();
        final referenceDatabase = FoodReferenceDatabase.memory();
        final openFoodFacts = DriftOpenFoodFactsRepository.forTesting(
          database: referenceDatabase,
          asset: const ThrowingBundleAsset(),
          client: OpenFoodFactsClient(
            baseUrl: Uri.parse('https://off.test/'),
            httpClient: MockClient((request) async {
              requests.add(request);
              return http.Response(
                jsonEncode(<String, Object?>{'products': <Object?>[]}),
                200,
                headers: const {'content-type': 'application/json'},
              );
            }),
          ),
        );
        final container = _container(
          RepositoryAddFoodRepository(
            TrainingRepositories(database),
            openFoodFacts: openFoodFacts,
            onlineLookupsEnabled: () async => enabled,
          ),
        );
        container.listen(addFoodPickerControllerProvider, (_, __) {});
        await container.read(addFoodPickerControllerProvider.future);
        final notifier =
            container.read(addFoodPickerControllerProvider.notifier);

        await notifier.submitQuery('hazel');
        await notifier.submitQuery('3017620422003');

        expect(requests, hasLength(enabled ? 2 : 0), reason: '$enabled');
        container.dispose();
        await referenceDatabase.close();
        await database.close();
      }
    });

    test('a live result never replaces a Your foods row', () async {
      final repository = _FakeAddFoodRepository(
        catalogue: [
          _food(
            '3017620422003',
            origin: FoodPickerOrigin.history,
            foodSource: FoodSource.openFoodFacts,
            name: 'Your spread',
            changedAt: DateTime.utc(2026),
          ),
          _food(
            '8000500310427',
            origin: FoodPickerOrigin.openFoodFacts,
            foodSource: FoodSource.openFoodFacts,
            name: 'Wafers',
            changedAt: DateTime.utc(2026),
          ),
          _food(
            '5000112637922',
            origin: FoodPickerOrigin.usda,
            foodSource: FoodSource.usda,
            name: 'Generic cola',
          ),
        ],
        live: [
          _food(
            '3017620422003',
            origin: FoodPickerOrigin.openFoodFacts,
            foodSource: FoodSource.openFoodFacts,
            name: 'Live spread',
            changedAt: DateTime.utc(2026, 10),
            live: true,
          ),
          _food(
            '8000500310427',
            origin: FoodPickerOrigin.openFoodFacts,
            foodSource: FoodSource.openFoodFacts,
            name: 'Wafers (new)',
            changedAt: DateTime.utc(2026, 10),
            live: true,
          ),
          _food(
            '5000112637922',
            origin: FoodPickerOrigin.openFoodFacts,
            foodSource: FoodSource.openFoodFacts,
            name: 'Cola',
            live: true,
          ),
        ],
      );
      final container = _container(repository);
      container.listen(addFoodPickerControllerProvider, (_, __) {});
      await container.read(addFoodPickerControllerProvider.future);

      await container
          .read(addFoodPickerControllerProvider.notifier)
          .submitQuery('spread');

      final state = container.read(addFoodPickerControllerProvider).value!;
      expect(state.results.map((item) => item.name), [
        'Your spread',
        'Wafers (new)',
        'Generic cola',
      ]);
      // Already listed by picker key; the same id under another Food Source
      // is a different Food.
      expect(state.onlineResults.map((item) => item.name), ['Cola']);
    });

    test(
        'a bundle install after a live search lists each product once and '
        'keeps the newer live copy', () async {
      final bundle = StreamController<BundleStatus>();
      addTearDown(bundle.close);
      final repository = _FakeAddFoodRepository(
        live: [
          _food(
            '8000500310427',
            origin: FoodPickerOrigin.openFoodFacts,
            foodSource: FoodSource.openFoodFacts,
            name: 'Wafers (new)',
            changedAt: DateTime.utc(2026, 10),
            live: true,
          ),
          _food(
            '5000112637922',
            origin: FoodPickerOrigin.openFoodFacts,
            foodSource: FoodSource.openFoodFacts,
            name: 'Cola',
            live: true,
          ),
        ],
      );
      final container =
          _container(repository, bundleStatus: bundle.stream);
      container.listen(addFoodPickerControllerProvider, (_, __) {});
      bundle.add(BundleStatus.installing);
      await container.read(addFoodPickerControllerProvider.future);
      await container
          .read(addFoodPickerControllerProvider.notifier)
          .submitQuery('wafers');
      expect(
        container
            .read(addFoodPickerControllerProvider)
            .value!
            .onlineResults
            .map((item) => item.name),
        ['Wafers (new)', 'Cola'],
      );

      // The install brings both products onto the device, wafers as an
      // older copy.
      repository.catalogue = [
        _food(
          '8000500310427',
          origin: FoodPickerOrigin.openFoodFacts,
          foodSource: FoodSource.openFoodFacts,
          name: 'Wafers',
          changedAt: DateTime.utc(2026),
        ),
        _food(
          '5000112637922',
          origin: FoodPickerOrigin.openFoodFacts,
          foodSource: FoodSource.openFoodFacts,
          name: 'Cola',
        ),
      ];
      bundle.add(BundleStatus.ready);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(addFoodPickerControllerProvider).value!;
      expect(state.results.map((item) => item.name), ['Wafers (new)', 'Cola']);
      expect(state.onlineResults, isEmpty);
      final keys = [
        for (final item in [...state.results, ...state.onlineResults])
          item.key,
      ];
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('closing the picker starts the next opening on All, empty', () async {
      final repository = _FakeAddFoodRepository();
      final container = _container(repository);
      final subscription =
          container.listen(addFoodPickerControllerProvider, (_, __) {});
      await container.read(addFoodPickerControllerProvider.future);
      final notifier = container.read(addFoodPickerControllerProvider.notifier);
      await notifier.selectFilter(AddFoodPickerFilter.usda);
      await notifier.submitQuery('chicken');
      expect(
        container.read(addFoodPickerControllerProvider).value!.filter,
        AddFoodPickerFilter.usda,
      );

      subscription.close();
      await container.pump();
      container.listen(addFoodPickerControllerProvider, (_, __) {});
      final reopened =
          await container.read(addFoodPickerControllerProvider.future);

      expect(reopened.filter, AddFoodPickerFilter.all);
      expect(reopened.query, '');
      expect(repository.loadCalls, 2);
    });
  });
}

ProviderContainer _container(
  AddFoodRepository repository, {
  Stream<BundleStatus>? bundleStatus,
}) {
  final container = ProviderContainer(
    overrides: [
      addFoodRepositoryProvider.overrideWith((ref) => repository),
      settingsRepositoryProvider.overrideWith(
        (ref) => InMemorySettingsRepository(),
      ),
      bundleStatusProvider.overrideWith(
        (ref) => bundleStatus ?? Stream<BundleStatus>.value(BundleStatus.ready),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

typedef _Search = ({
  AddFoodPickerFilter filter,
  String query,
  YourFoods yourFoods,
});

/// Serves Your foods on a blank query and [catalogue] on a typed one,
/// recording every call.
class _FakeAddFoodRepository implements AddFoodRepository {
  _FakeAddFoodRepository({
    this.yourFoods = YourFoods.empty,
    this.failLoad = false,
    this.catalogue = const <FoodPickerItem>[],
    this.live = const <FoodPickerItem>[],
  });

  final YourFoods yourFoods;
  final bool failLoad;
  /// What a typed device search returns; a test may change it, as a
  /// finished bundle install does.
  List<FoodPickerItem> catalogue;
  final List<FoodPickerItem> live;

  var loadCalls = 0;
  final searches = <_Search>[];
  final onlineQueries = <String>[];
  final barcodes = <String>[];

  @override
  Future<YourFoods> loadYourFoods({DateTime? now}) async {
    loadCalls += 1;
    if (failLoad) {
      throw StateError('Food History is unavailable.');
    }
    return yourFoods;
  }

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    required YourFoods yourFoods,
  }) async {
    searches.add((filter: filter, query: query, yourFoods: yourFoods));
    return query.trim().isEmpty ? yourFoods.items : catalogue;
  }

  @override
  Future<bool> onlineLookupsEnabled() async => true;

  @override
  Future<({OnlineSearchStatus status, List<FoodPickerItem> items})>
      searchOnline(String query, {required YourFoods yourFoods}) async {
    onlineQueries.add(query);
    return (status: OnlineSearchStatus.ok, items: live);
  }

  @override
  Future<({BarcodeLookupOutcome status, FoodPickerItem? item})> lookupBarcode(
    String raw, {
    required YourFoods yourFoods,
  }) async {
    barcodes.add(raw);
    return (status: BarcodeLookupOutcome.notFound, item: null);
  }

  @override
  Future<void> keepOpenedProduct(FoodPickerItem item) async {}
}

FoodPickerItem _food(
  String id, {
  FoodPickerOrigin origin = FoodPickerOrigin.history,
  FoodSource foodSource = FoodSource.user,
  String? name,
  DateTime? changedAt,
  bool live = false,
}) {
  return FoodPickerItem(
    id: id,
    name: name ?? id,
    origin: origin,
    foodSource: foodSource,
    nutrientsPer100: NutrientVector.energyAndMacros(
      energy: _amount(NutrientId.energy, 100),
      protein: _amount(NutrientId.protein, 10),
      carbohydrate: _amount(NutrientId.carbohydrate, 0),
      fat: _amount(NutrientId.fat, 0),
    ),
    isLiquid: false,
    sourceModifiedAt: changedAt,
    isLiveResult: live,
  );
}

NutrientAmount _amount(NutrientId id, double value) {
  return NutrientAmount.complete(
    value: value,
    entered: value.toStringAsFixed(0),
    unit: id.defaultUnit,
  );
}
