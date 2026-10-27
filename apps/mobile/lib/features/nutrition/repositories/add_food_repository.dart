import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/open_food_facts_repository.dart';
import '../../../data/repositories/training_repositories.dart';
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

enum AddFoodPickerFilter {
  recent,
  user,
  usda,
  openFoodFacts;

  String get label {
    return switch (this) {
      AddFoodPickerFilter.recent => 'Recent',
      AddFoodPickerFilter.user => 'Your Food',
      AddFoodPickerFilter.usda => 'USDA',
      AddFoodPickerFilter.openFoodFacts => 'Open Food Facts',
    };
  }
}

class FoodPickerItem {
  const FoodPickerItem({
    required this.id,
    required this.name,
    required this.filter,
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
  final AddFoodPickerFilter filter;
  final FoodSource foodSource;
  final NutrientVector nutrientsPer100;
  final bool isLiquid;
  final String? servingLabel;
  final double? servingSize;
  final double? packageSize;
  final Portion? lastPortion;
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

abstract interface class AddFoodRepository {
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    int limit = 50,
  });

  /// The device setting "Look up foods online".
  Future<bool> onlineLookupsEnabled();

  /// One live Open Food Facts search; its items have `isLiveResult: true`.
  Future<({OnlineSearchStatus status, List<FoodPickerItem> items})>
      searchOnline(String query);

  /// A scanned or typed barcode: a stored product, else one live request.
  Future<({BarcodeLookupOutcome status, FoodPickerItem? item})> lookupBarcode(
    String raw,
  );

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

  @override
  Future<({OnlineSearchStatus status, List<FoodPickerItem> items})>
      searchOnline(String query) async {
    final result = await _openFoodFacts.searchOnline(
      query,
      allowOnline: await onlineLookupsEnabled(),
    );
    return (
      status: result.status,
      items: await _openFoodFactsItems(result.products, isLiveResult: true),
    );
  }

  @override
  Future<({BarcodeLookupOutcome status, FoodPickerItem? item})> lookupBarcode(
    String raw,
  ) async {
    final result = await _openFoodFacts.lookupBarcode(
      raw,
      allowOnline: await onlineLookupsEnabled(),
    );
    final product = result.product;
    return (
      status: result.status,
      item: product == null
          ? null
          : (await _openFoodFactsItems(<PlatformFoodRecord>[product])).single,
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
    int limit = 50,
  }) {
    if (limit <= 0) {
      return Future<List<FoodPickerItem>>.value(const <FoodPickerItem>[]);
    }
    return switch (filter) {
      AddFoodPickerFilter.recent => _searchRecent(query, limit: limit),
      AddFoodPickerFilter.user => _searchUserFoods(query, limit: limit),
      AddFoodPickerFilter.usda => _searchUsdaFoods(query, limit: limit),
      AddFoodPickerFilter.openFoodFacts => _searchOpenFoodFacts(
          query,
          limit: limit,
        ),
    };
  }

  Future<List<FoodPickerItem>> _searchRecent(
    String query, {
    required int limit,
  }) async {
    final entries = await _repositories.nutrition.listRecentFoodEntries(
      limit: limit * 4,
    );
    final seen = <String>{};
    final items = <FoodPickerItem>[];

    for (final entry in entries) {
      final foodId = entry.foodId;
      final foodSource = entry.foodSource;
      final isLiquid = entry.isLiquid;
      if (foodId == null || foodSource == null || isLiquid == null) {
        continue;
      }
      if (!foodNameMatchesQuery(entry.name, query)) {
        continue;
      }
      final key = '${foodSource.name}:$foodId';
      if (!seen.add(key)) {
        continue;
      }
      items.add(
        FoodPickerItem(
          id: foodId,
          name: entry.name,
          filter: AddFoodPickerFilter.recent,
          foodSource: foodSource,
          nutrientsPer100: entry.nutrients,
          isLiquid: isLiquid,
          servingLabel: entry.servingLabel,
          servingSize: entry.servingSize,
          packageSize: entry.packageSize,
          lastPortion: entry.portion,
          lastLoggedAt: entry.updatedAt,
        ),
      );
      if (items.length >= limit) {
        break;
      }
    }

    return items;
  }

  Future<List<FoodPickerItem>> _searchUserFoods(
    String query, {
    required int limit,
  }) async {
    final matched = await _repositories.nutrition.searchActiveUserFoods(
      query,
      limit: limit,
    );
    final items = <FoodPickerItem>[];
    for (final food in matched) {
      items.add(
        FoodPickerItem(
          id: food.id,
          name: food.name,
          filter: AddFoodPickerFilter.user,
          foodSource: food.foodSource,
          nutrientsPer100: food.nutrientsPer100,
          isLiquid: food.isLiquid,
          servingLabel: food.servingLabel,
          servingSize: food.servingSize,
          packageSize: food.packageSize,
          lastPortion: await _repositories.nutrition.lastPortionForFood(
            foodId: food.id,
            foodSource: food.foodSource,
          ),
        ),
      );
    }
    return items;
  }

  Future<List<FoodPickerItem>> _searchUsdaFoods(
    String query, {
    required int limit,
  }) async {
    final foods = await _repositories.platformFoods.searchUsdaFoods(
      query,
      limit: limit,
    );
    final items = <FoodPickerItem>[];
    for (final food in foods) {
      items.add(
        FoodPickerItem(
          id: food.id,
          name: food.name,
          filter: AddFoodPickerFilter.usda,
          foodSource: food.foodSource,
          nutrientsPer100: food.nutrientsPer100,
          isLiquid: food.isLiquid,
          servingLabel: food.servingLabel,
          servingSize: food.servingSize,
          packageSize: food.packageSize,
          lastPortion: await _repositories.nutrition.lastPortionForFood(
            foodId: food.id,
            foodSource: food.foodSource,
          ),
        ),
      );
    }
    return items;
  }

  Future<List<FoodPickerItem>> _searchOpenFoodFacts(
    String query, {
    required int limit,
  }) async {
    final foods = await _openFoodFacts.searchLocal(query, limit: limit);
    return _openFoodFactsItems(foods);
  }

  /// Picker items for Open Food Facts records, with their Last Portions read
  /// in one query rather than one per row.
  Future<List<FoodPickerItem>> _openFoodFactsItems(
    List<PlatformFoodRecord> foods, {
    bool isLiveResult = false,
  }) async {
    final lastPortions = await _repositories.nutrition.lastPortionsForFoods(
      foodIds: [for (final food in foods) food.id],
      foodSource: FoodSource.openFoodFacts,
    );
    return [
      for (final food in foods)
        _openFoodFactsItem(
          food,
          lastPortion: lastPortions[food.id],
          isLiveResult: isLiveResult,
        ),
    ];
  }

  FoodPickerItem _openFoodFactsItem(
    PlatformFoodRecord food, {
    required Portion? lastPortion,
    required bool isLiveResult,
  }) {
    return FoodPickerItem(
      id: food.id,
      name: food.name,
      filter: AddFoodPickerFilter.openFoodFacts,
      foodSource: food.foodSource,
      nutrientsPer100: food.nutrientsPer100,
      isLiquid: food.isLiquid,
      servingLabel: food.servingLabel,
      servingSize: food.servingSize,
      packageSize: food.packageSize,
      lastPortion: lastPortion,
      brand: food.brand,
      sourceModifiedAt: food.sourceModifiedAt,
      scans: food.scans,
      isLiveResult: isLiveResult,
    );
  }
}
