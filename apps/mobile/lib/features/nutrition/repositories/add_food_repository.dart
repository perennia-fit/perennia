import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

final addFoodRepositoryProvider = Provider<AddFoodRepository>((ref) {
  return RepositoryAddFoodRepository(ref.watch(trainingRepositoriesProvider));
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
}

class RepositoryAddFoodRepository implements AddFoodRepository {
  const RepositoryAddFoodRepository(this._repositories);

  final TrainingRepositories _repositories;

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
    final foods = await _repositories.openFoodFacts.search(
      query,
      limit: limit,
    );
    final items = <FoodPickerItem>[];
    for (final food in foods) {
      items.add(
        FoodPickerItem(
          id: food.id,
          name: food.name,
          filter: AddFoodPickerFilter.openFoodFacts,
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
}
