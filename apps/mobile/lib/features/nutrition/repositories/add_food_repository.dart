import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/open_food_facts_repository.dart';
import '../../../data/repositories/training_repositories.dart';
import '../../../domain/nutrition/open_food_facts.dart';
import '../../settings/repositories/settings_repository.dart';

export '../../../data/repositories/open_food_facts_repository.dart'
    show BarcodeLookupOutcome, OnlineSearchStatus;

final addFoodRepositoryProvider = Provider<AddFoodRepository>((ref) {
  return RepositoryAddFoodRepository(
    ref.watch(trainingRepositoriesProvider),
    openFoodFacts: ref.watch(openFoodFactsRepositoryProvider),
    onlineLookupsEnabled: () async =>
        (await ref.read(settingsControllerProvider.future)).onlineFoodLookups,
  );
});

/// Rows of Your foods on a blank All query and in the Your foods filter.
const yourFoodsLimit = 200;

/// Your foods rows in a typed All search.
const yourFoodsInSearchLimit = 20;

/// Total rows in a typed All search; rows in the USDA and Open Food Facts
/// filters.
const searchResultLimit = 50;

/// The picker's chips, in the order shown. All is the default.
enum AddFoodPickerFilter {
  all,
  yours,
  usda,
  openFoodFacts;

  String get label {
    return switch (this) {
      AddFoodPickerFilter.all => 'All',
      AddFoodPickerFilter.yours => 'Your foods',
      AddFoodPickerFilter.usda => 'USDA',
      AddFoodPickerFilter.openFoodFacts => 'Open Food Facts',
    };
  }
}

/// Why a row is in the picker's list. [FoodPickerItem.foodSource] names
/// where its data comes from; the live merge depends on this instead.
enum FoodPickerOrigin {
  /// A Food History row, from any Food Source.
  history,

  /// A User Food never logged.
  userFood,

  /// A USDA Catalogue row.
  usda,

  /// An Open Food Facts Catalogue row, from the device or a live search.
  openFoodFacts,
}

class FoodPickerItem {
  const FoodPickerItem({
    required this.id,
    required this.name,
    required this.origin,
    required this.foodSource,
    required this.nutrientsPer100,
    required this.isLiquid,
    this.servingLabel,
    this.servingSize,
    this.packageSize,
    this.lastPortion,
    this.lastLoggedAt,
    this.brand,
    this.sourceModifiedAt,
    this.scans,
    this.isLiveResult = false,
  });

  final String id;
  final String name;
  final FoodPickerOrigin origin;
  final FoodSource foodSource;
  final NutrientVector nutrientsPer100;
  final bool isLiquid;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;
  final Portion? lastPortion;

  /// The Food History record's last Meal start, for [FoodPickerOrigin.history]
  /// rows only.
  final DateTime? lastLoggedAt;

  /// The product's first brand, for Open Food Facts foods.
  final String? brand;

  /// When the source last changed the product, for Open Food Facts foods.
  final DateTime? sourceModifiedAt;

  /// The source's scan count, used only to rank.
  final int? scans;

  /// A live Open Food Facts copy that is not stored on the device; opening it
  /// stores it.
  final bool isLiveResult;

  /// The picker's one identity for a Food: deduplication, live-result
  /// exclusion and widget keys all use it.
  String get key => '${foodSource.name}:$id';

  String get foodSourceLabel {
    return switch (foodSource) {
      FoodSource.usda => 'USDA',
      FoodSource.openFoodFacts => 'Open Food Facts',
      FoodSource.user => 'Your Food',
      FoodSource.cronometer => 'Cronometer',
      FoodSource.myFitnessPal => 'MyFitnessPal',
      FoodSource.yazio => 'Yazio',
      FoodSource.lifesum => 'Lifesum',
      FoodSource.imported => 'Imported',
    };
  }

  List<PortionUnit> get availablePortionUnits {
    return availablePortionUnitsForFood(
      isLiquid: isLiquid,
      servingLabel: servingLabel,
      servingSize: servingSize,
      packageSize: packageSize,
    );
  }
}

/// The resolved, ordered Your foods list, loaded once per picker opening
/// (docs/designs/unified-food-search.md § Your foods). Every search in that
/// opening filters it in memory.
final class YourFoods {
  factory YourFoods(List<FoodPickerItem> items) {
    return YourFoods._(
      List<FoodPickerItem>.unmodifiable(items),
      <String, Portion>{
        for (final item in items)
          if (item.lastPortion case final portion?) item.key: portion,
      },
    );
  }

  const YourFoods._(this.items, this._lastPortions);

  /// Food History rows first, in Food History order, then never-logged
  /// User Foods by lower-cased name. Not capped.
  final List<FoodPickerItem> items;

  final Map<String, Portion> _lastPortions;

  static const empty = YourFoods._(<FoodPickerItem>[], <String, Portion>{});

  /// The Last Portion for (foodSource, id), for Catalogue rows. A Catalogue
  /// Food with a Last Portion has been logged, so it is in Food History.
  Portion? lastPortionFor(FoodSource foodSource, String id) {
    return _lastPortions['${foodSource.name}:$id'];
  }
}

abstract interface class AddFoodRepository {
  /// Your foods for one picker opening.
  Future<YourFoods> loadYourFoods({DateTime? now});

  /// The device's rows for [filter] and [query]. Never sends anything; Your
  /// foods come from the loaded [yourFoods], never from a new read.
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    required YourFoods yourFoods,
  });

  /// The device setting "Look up foods online".
  Future<bool> onlineLookupsEnabled();

  /// One live Open Food Facts search; its items have `isLiveResult: true`.
  Future<({OnlineSearchStatus status, List<FoodPickerItem> items})>
      searchOnline(String query, {required YourFoods yourFoods});

  /// A scanned or typed barcode: a stored product, else one live request.
  Future<({BarcodeLookupOutcome status, FoodPickerItem? item})> lookupBarcode(
    String raw, {
    required YourFoods yourFoods,
  });

  /// Stores a live Open Food Facts product the user opened.
  Future<void> keepOpenedProduct(FoodPickerItem item);
}

class RepositoryAddFoodRepository implements AddFoodRepository {
  /// With no [openFoodFacts], the Open Food Facts filter finds nothing and the
  /// online methods return `disabled`. With no [onlineLookupsEnabled], online
  /// lookups count as on.
  const RepositoryAddFoodRepository(
    this._repositories, {
    OpenFoodFactsRepository? openFoodFacts,
    Future<bool> Function()? onlineLookupsEnabled,
  })  : _openFoodFacts = openFoodFacts ?? const StubOpenFoodFactsRepository(),
        _onlineLookupsEnabled = onlineLookupsEnabled;

  final TrainingRepositories _repositories;
  final OpenFoodFactsRepository _openFoodFacts;
  final Future<bool> Function()? _onlineLookupsEnabled;

  @override
  Future<bool> onlineLookupsEnabled() async {
    return await _onlineLookupsEnabled?.call() ?? true;
  }

  /// Food History resolved to each Food as it is now, then the never-logged
  /// User Foods. A record whose Food is not on the device (a User Food row
  /// not synced yet, a product dropped from the bundle, a Food Source with no
  /// catalogue) falls back to its latest Food Entry's snapshot, so it stays
  /// loggable.
  @override
  Future<YourFoods> loadYourFoods({DateTime? now}) async {
    final nutrition = _repositories.nutrition;
    final history = await nutrition.listFoodHistory(now: now);
    final userFoods = await nutrition.listActiveUserFoods();
    final userFoodsById = {for (final food in userFoods) food.id: food};
    final products = {
      for (final product in await _openFoodFacts.localProductsByCodes([
        for (final record in history)
          if (record.foodSource == FoodSource.openFoodFacts) record.foodId,
      ]))
        product.id: product,
    };

    final resolved = <String, FoodPickerItem>{};
    final unresolved = <FoodHistoryRecord>[];
    for (final record in history) {
      final item = switch (record.foodSource) {
        FoodSource.user => switch (userFoodsById[record.foodId]) {
            final food? => _historyItem(
                record,
                name: food.name,
                nutrientsPer100: food.nutrientsPer100,
                isLiquid: food.isLiquid,
                servingLabel: food.servingLabel,
                servingSize: food.servingSize,
                packageSize: food.packageSize,
              ),
            null => null,
          },
        FoodSource.usda => switch (await _repositories.platformFoods
              .getUsdaFoodById(record.foodId)) {
            final food? => _platformHistoryItem(record, food),
            null => null,
          },
        FoodSource.openFoodFacts => switch (products[record.foodId]) {
            final product? => _platformHistoryItem(record, product),
            null => null,
          },
        _ => null,
      };
      if (item == null) {
        unresolved.add(record);
      } else {
        resolved[item.key] = item;
      }
    }

    final latestEntries = {
      for (final entry in await nutrition.listFoodEntriesByIds([
        for (final record in unresolved) record.latestEntryId,
      ]))
        entry.id: entry,
    };
    for (final record in unresolved) {
      final entry = latestEntries[record.latestEntryId];
      final isLiquid = entry?.isLiquid;
      if (entry == null || isLiquid == null) {
        continue;
      }
      final item = _historyItem(
        record,
        name: entry.name,
        nutrientsPer100: entry.nutrients,
        isLiquid: isLiquid,
        servingLabel: entry.servingLabel,
        servingSize: entry.servingSize,
        packageSize: entry.packageSize,
      );
      resolved[item.key] = item;
    }

    final neverLogged = [
      for (final food in userFoods)
        if (!resolved.containsKey('${FoodSource.user.name}:${food.id}')) food,
    ]..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });

    return YourFoods([
      for (final record in history)
        if (resolved['${record.foodSource.name}:${record.foodId}']
            case final item?)
          item,
      for (final food in neverLogged)
        FoodPickerItem(
          id: food.id,
          name: food.name,
          origin: FoodPickerOrigin.userFood,
          foodSource: food.foodSource,
          nutrientsPer100: food.nutrientsPer100,
          isLiquid: food.isLiquid,
          servingLabel: food.servingLabel,
          servingSize: food.servingSize,
          packageSize: food.packageSize,
        ),
    ]);
  }

  FoodPickerItem _platformHistoryItem(
    FoodHistoryRecord record,
    PlatformFoodRecord food,
  ) {
    return _historyItem(
      record,
      name: food.name,
      nutrientsPer100: food.nutrientsPer100,
      isLiquid: food.isLiquid,
      servingLabel: food.servingLabel,
      servingSize: food.servingSize,
      packageSize: food.packageSize,
      brand: food.brand,
    );
  }

  FoodPickerItem _historyItem(
    FoodHistoryRecord record, {
    required String name,
    required NutrientVector nutrientsPer100,
    required bool isLiquid,
    required String? servingLabel,
    required double? servingSize,
    required double? packageSize,
    String? brand,
  }) {
    return FoodPickerItem(
      id: record.foodId,
      name: name,
      origin: FoodPickerOrigin.history,
      foodSource: record.foodSource,
      nutrientsPer100: nutrientsPer100,
      isLiquid: isLiquid,
      servingLabel: servingLabel,
      servingSize: servingSize,
      packageSize: packageSize,
      brand: brand,
      lastPortion: record.lastPortion,
      lastLoggedAt: record.lastLoggedAt,
    );
  }

  @override
  Future<({OnlineSearchStatus status, List<FoodPickerItem> items})>
      searchOnline(String query, {required YourFoods yourFoods}) async {
    final result = await _openFoodFacts.searchOnline(
      query,
      allowOnline: await onlineLookupsEnabled(),
    );
    return (
      status: result.status,
      items: _openFoodFactsItems(
        result.products,
        yourFoods,
        isLiveResult: true,
      ),
    );
  }

  @override
  Future<({BarcodeLookupOutcome status, FoodPickerItem? item})> lookupBarcode(
    String raw, {
    required YourFoods yourFoods,
  }) async {
    final result = await _openFoodFacts.lookupBarcode(
      raw,
      allowOnline: await onlineLookupsEnabled(),
    );
    final product = result.product;
    return (
      status: result.status,
      item: product == null
          ? null
          : _openFoodFactsItems(<PlatformFoodRecord>[product], yourFoods)
              .single,
    );
  }

  @override
  Future<void> keepOpenedProduct(FoodPickerItem item) async {
    await _openFoodFacts.keepOpenedProduct(
      PlatformFoodRecord(
        id: item.id,
        name: item.name,
        foodSource: item.foodSource,
        nutrientsPer100: item.nutrientsPer100,
        isLiquid: item.isLiquid,
        servingLabel: item.servingLabel,
        servingSize: item.servingSize,
        packageSize: item.packageSize,
        brand: item.brand,
        sourceModifiedAt: item.sourceModifiedAt,
        scans: item.scans,
      ),
    );
  }

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    required YourFoods yourFoods,
  }) async {
    final blank = _isBlank(query);
    return switch (filter) {
      AddFoodPickerFilter.all => blank
          ? yourFoods.items.take(yourFoodsLimit).toList(growable: false)
          : await _searchAll(query, yourFoods),
      AddFoodPickerFilter.yours =>
        _matchYourFoods(query, yourFoods).take(yourFoodsLimit).toList(),
      AddFoodPickerFilter.usda => await _searchUsdaFoods(query, yourFoods),
      AddFoodPickerFilter.openFoodFacts => blank
          ? const <FoodPickerItem>[]
          : _openFoodFactsItems(
              await _openFoodFacts.searchLocal(
                query,
                limit: searchResultLimit,
              ),
              yourFoods,
            ),
    };
  }

  /// A typed All search: Your foods matches (Y), then barcode matches (B),
  /// then USDA (U), then the remaining Open Food Facts matches (F), keeping
  /// the first copy of each Food. A source that fails leaves its groups
  /// empty instead of failing the search, as a failed device reload shows no
  /// error today.
  Future<List<FoodPickerItem>> _searchAll(
    String query,
    YourFoods yourFoods,
  ) async {
    final candidates = barcodeCandidates(query).toSet();
    final (local, usda) = await (
      _openFoodFacts
          .searchLocal(query, limit: searchResultLimit)
          .then<List<PlatformFoodRecord>?>((value) => value)
          .catchError((Object _) => null),
      _searchUsdaFoods(query, yourFoods)
          .then<List<FoodPickerItem>?>((value) => value)
          .catchError((Object _) => null),
    ).wait;
    final offItems = _openFoodFactsItems(local ?? const [], yourFoods);
    final seen = <String>{};
    return [
      for (final item in [
        ..._matchYourFoods(query, yourFoods).take(yourFoodsInSearchLimit),
        ...offItems.where((item) => candidates.contains(item.id)),
        ...?usda,
        ...offItems.where((item) => !candidates.contains(item.id)),
      ])
        if (seen.add(item.key)) item,
    ].take(searchResultLimit).toList(growable: false);
  }

  /// Your foods matching [query] by name, or for an Open Food Facts Food by
  /// barcode; every item on a blank query.
  Iterable<FoodPickerItem> _matchYourFoods(String query, YourFoods yourFoods) {
    if (_isBlank(query)) {
      return yourFoods.items;
    }
    final candidates = barcodeCandidates(query).toSet();
    return yourFoods.items.where(
      (item) =>
          foodNameMatchesQuery(item.name, query) ||
          (item.foodSource == FoodSource.openFoodFacts &&
              candidates.contains(item.id)),
    );
  }

  Future<List<FoodPickerItem>> _searchUsdaFoods(
    String query,
    YourFoods yourFoods,
  ) async {
    final foods = await _repositories.platformFoods.searchUsdaFoods(
      query,
      limit: searchResultLimit,
    );
    return [
      for (final food in foods)
        FoodPickerItem(
          id: food.id,
          name: food.name,
          origin: FoodPickerOrigin.usda,
          foodSource: food.foodSource,
          nutrientsPer100: food.nutrientsPer100,
          isLiquid: food.isLiquid,
          servingLabel: food.servingLabel,
          servingSize: food.servingSize,
          packageSize: food.packageSize,
          lastPortion: yourFoods.lastPortionFor(food.foodSource, food.id),
        ),
    ];
  }

  /// Picker items for Open Food Facts records, with their Last Portions from
  /// the loaded Your foods rather than a query.
  List<FoodPickerItem> _openFoodFactsItems(
    List<PlatformFoodRecord> foods,
    YourFoods yourFoods, {
    bool isLiveResult = false,
  }) {
    return [
      for (final food in foods)
        FoodPickerItem(
          id: food.id,
          name: food.name,
          origin: FoodPickerOrigin.openFoodFacts,
          foodSource: food.foodSource,
          nutrientsPer100: food.nutrientsPer100,
          isLiquid: food.isLiquid,
          servingLabel: food.servingLabel,
          servingSize: food.servingSize,
          packageSize: food.packageSize,
          lastPortion: yourFoods.lastPortionFor(food.foodSource, food.id),
          brand: food.brand,
          sourceModifiedAt: food.sourceModifiedAt,
          scans: food.scans,
          isLiveResult: isLiveResult,
        ),
    ];
  }
}

/// A query with nothing to search by: no name terms and no barcode
/// candidates. An empty query, spaces and punctuation alone are all blank.
bool _isBlank(String query) {
  return buildFoodSearchMatch(query) == null &&
      barcodeCandidates(query).isEmpty;
}
