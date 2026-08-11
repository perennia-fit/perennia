import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/nutrition/nutrition.dart';
import '../repositories/add_food_repository.dart';
import 'nutrition_day_controller.dart';

final addFoodPickerControllerProvider =
    AsyncNotifierProvider<AddFoodPickerController, AddFoodPickerState>(
  AddFoodPickerController.new,
);

final class AddFoodPickerState {
  AddFoodPickerState({
    required this.query,
    required this.filter,
    required List<FoodPickerItem> results,
    this.barcodeLookupStatus = BarcodeLookupStatus.idle,
    this.brandedSearchNeedsNetwork = false,
    this.barcode,
  }) : results = List<FoodPickerItem>.unmodifiable(results);

  final String query;
  final AddFoodPickerFilter filter;
  final List<FoodPickerItem> results;
  final BarcodeLookupStatus barcodeLookupStatus;
  final bool brandedSearchNeedsNetwork;
  final String? barcode;

  AddFoodPickerState copyWith({
    String? query,
    AddFoodPickerFilter? filter,
    List<FoodPickerItem>? results,
    BarcodeLookupStatus? barcodeLookupStatus,
    bool? brandedSearchNeedsNetwork,
    String? barcode,
    bool clearBarcode = false,
  }) {
    return AddFoodPickerState(
      query: query ?? this.query,
      filter: filter ?? this.filter,
      results: results ?? this.results,
      barcodeLookupStatus: barcodeLookupStatus ?? this.barcodeLookupStatus,
      brandedSearchNeedsNetwork:
          brandedSearchNeedsNetwork ?? this.brandedSearchNeedsNetwork,
      barcode: clearBarcode ? null : barcode ?? this.barcode,
    );
  }
}

enum BarcodeLookupStatus {
  idle,
  loading,
  notFound,
  needsNetwork;
}

class AddFoodPickerController extends AsyncNotifier<AddFoodPickerState> {
  static const searchDebounceDuration = Duration(milliseconds: 300);

  String _query = '';
  AddFoodPickerFilter _filter = AddFoodPickerFilter.recent;
  Timer? _searchDebounceTimer;
  var _searchGeneration = 0;

  @override
  Future<AddFoodPickerState> build() {
    ref.onDispose(() {
      _searchDebounceTimer?.cancel();
      _searchGeneration += 1;
    });
    return _load(filter: _filter, query: _query);
  }

  Future<void> setQuery(String query) async {
    if (query == _query) {
      return;
    }
    _query = query;
    _showPendingQuery(query);
    _searchDebounceTimer?.cancel();
    final generation = ++_searchGeneration;
    _searchDebounceTimer = Timer(searchDebounceDuration, () {
      unawaited(_refresh(generation: generation));
    });
  }

  Future<void> submitQuery(String query) async {
    if (query != _query) {
      _query = query;
      _showPendingQuery(query);
    }
    _searchDebounceTimer?.cancel();
    await _refresh(generation: ++_searchGeneration);
  }

  Future<void> selectFilter(AddFoodPickerFilter filter) async {
    if (filter == _filter) {
      return;
    }
    _filter = filter;
    _searchDebounceTimer?.cancel();
    await _refresh(generation: ++_searchGeneration);
  }

  Future<FoodPickerItem?> lookupBarcode(String barcode) async {
    final normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) {
      return null;
    }
    _searchDebounceTimer?.cancel();
    final generation = ++_searchGeneration;
    final current = _currentState();
    state = AsyncData<AddFoodPickerState>(
      current.copyWith(
        barcodeLookupStatus: BarcodeLookupStatus.loading,
        barcode: normalizedBarcode,
      ),
    );
    try {
      final results = await ref.read(addFoodRepositoryProvider).search(
            filter: AddFoodPickerFilter.openFoodFacts,
            query: normalizedBarcode,
            limit: 1,
          );
      if (generation != _searchGeneration) {
        return null;
      }
      if (results.isEmpty) {
        state = AsyncData<AddFoodPickerState>(
          _currentState().copyWith(
            barcodeLookupStatus: BarcodeLookupStatus.notFound,
            barcode: normalizedBarcode,
          ),
        );
        return null;
      }
      state = AsyncData<AddFoodPickerState>(
        _currentState().copyWith(
          barcodeLookupStatus: BarcodeLookupStatus.idle,
          clearBarcode: true,
        ),
      );
      return results.first;
    } catch (_) {
      if (generation != _searchGeneration) {
        return null;
      }
      state = AsyncData<AddFoodPickerState>(
        _currentState().copyWith(
          barcodeLookupStatus: BarcodeLookupStatus.needsNetwork,
          barcode: normalizedBarcode,
        ),
      );
      return null;
    }
  }

  Future<LogQuickEntryResult> logQuickEntryForMeal({
    required String mealId,
    required QuickFoodEntryDraft entry,
  }) {
    return ref.read(nutritionRepositoryProvider).logQuickEntryForMeal(
          mealId: mealId,
          entry: entry,
        );
  }

  Future<void> _refresh({required int generation}) async {
    final filter = _filter;
    final query = _query;
    state = const AsyncLoading<AddFoodPickerState>();
    final next = await AsyncValue.guard(
      () => _load(filter: filter, query: query),
    );
    if (generation != _searchGeneration) {
      return;
    }
    state = next;
  }

  Future<AddFoodPickerState> _load({
    required AddFoodPickerFilter filter,
    required String query,
  }) async {
    try {
      final results = await ref.read(addFoodRepositoryProvider).search(
            filter: filter,
            query: query,
          );
      return AddFoodPickerState(
        query: query,
        filter: filter,
        results: results,
      );
    } catch (_) {
      if (filter == AddFoodPickerFilter.openFoodFacts &&
          query.trim().isNotEmpty) {
        return AddFoodPickerState(
          query: query,
          filter: filter,
          results: const <FoodPickerItem>[],
          brandedSearchNeedsNetwork: true,
        );
      }
      rethrow;
    }
  }

  AddFoodPickerState _currentState() {
    final current = state.asData?.value;
    if (current != null) {
      return current;
    }
    return AddFoodPickerState(
      query: _query,
      filter: _filter,
      results: const <FoodPickerItem>[],
    );
  }

  void _showPendingQuery(String query) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData<AddFoodPickerState>(
      current.copyWith(
        query: query,
        barcodeLookupStatus: BarcodeLookupStatus.idle,
        brandedSearchNeedsNetwork: false,
        clearBarcode: true,
      ),
    );
  }
}
