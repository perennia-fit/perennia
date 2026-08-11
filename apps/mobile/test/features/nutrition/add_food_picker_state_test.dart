import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/nutrition/nutrition.dart';
import 'package:perennia/features/nutrition/controllers/add_food_controller.dart';
import 'package:perennia/features/nutrition/repositories/add_food_repository.dart';

void main() {
  group('AddFoodPickerState', () {
    test('defensively copies result inputs and exposes immutable views', () {
      final sourceResults = <FoodPickerItem>[_food('recent-chicken')];

      final state = AddFoodPickerState(
        query: 'chicken',
        filter: AddFoodPickerFilter.recent,
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
        filter: AddFoodPickerFilter.user,
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
}

FoodPickerItem _food(String id) {
  return FoodPickerItem(
    id: id,
    name: id,
    filter: AddFoodPickerFilter.recent,
    foodSource: FoodSource.user,
    nutrientsPer100: NutrientVector.energyAndMacros(
      energy: _amount(NutrientId.energy, 100),
      protein: _amount(NutrientId.protein, 10),
      carbohydrate: _amount(NutrientId.carbohydrate, 0),
      fat: _amount(NutrientId.fat, 0),
    ),
    isLiquid: false,
  );
}

NutrientAmount _amount(NutrientId id, double value) {
  return NutrientAmount.complete(
    value: value,
    entered: value.toStringAsFixed(0),
    unit: id.defaultUnit,
  );
}
