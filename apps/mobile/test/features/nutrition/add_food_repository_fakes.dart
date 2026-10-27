import 'package:perennia/features/nutrition/repositories/add_food_repository.dart';

/// The online methods for `AddFoodRepository` fakes that do not exercise
/// them: lookups on, no live results, every barcode not found.
mixin NoOnlineLookups implements AddFoodRepository {
  @override
  Future<bool> onlineLookupsEnabled() async => true;

  @override
  Future<({OnlineSearchStatus status, List<FoodPickerItem> items})>
      searchOnline(String query) async {
    return (status: OnlineSearchStatus.noResults, items: <FoodPickerItem>[]);
  }

  @override
  Future<({BarcodeLookupOutcome status, FoodPickerItem? item})> lookupBarcode(
    String raw,
  ) async {
    return (status: BarcodeLookupOutcome.notFound, item: null);
  }

  @override
  Future<void> keepOpenedProduct(FoodPickerItem item) async {}
}
