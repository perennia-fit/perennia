import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/open_food_facts_repository.dart';
import '../../../domain/nutrition/nutrition.dart';
import '../../../domain/nutrition/open_food_facts.dart';
import '../../settings/repositories/settings_repository.dart';
import '../repositories/add_food_repository.dart';
import 'nutrition_day_controller.dart';

/// Auto-disposed: the picker sheet is its only listener, so each opening
/// builds a fresh controller with filter All, an empty query and a fresh
/// Your foods read (docs/designs/unified-food-search.md § Controller
/// lifecycle).
final addFoodPickerControllerProvider = AsyncNotifierProvider.autoDispose<
    AddFoodPickerController, AddFoodPickerState>(
  AddFoodPickerController.new,
);

final class AddFoodPickerState {
  AddFoodPickerState({
    required this.query,
    required this.filter,
    required List<FoodPickerItem> results,
    this.barcodeLookupStatus = BarcodeLookupStatus.idle,
    this.barcode,
    List<FoodPickerItem> onlineResults = const <FoodPickerItem>[],
    this.onlineStatus = OnlinePickerStatus.idle,
    this.onlineLookupsEnabled = true,
    this.bundleStatus = BundleStatus.unknown,
  })  : results = List<FoodPickerItem>.unmodifiable(results),
        onlineResults = List<FoodPickerItem>.unmodifiable(onlineResults);

  final String query;
  final AddFoodPickerFilter filter;

  /// The device's own matches, for every filter.
  final List<FoodPickerItem> results;
  final BarcodeLookupStatus barcodeLookupStatus;
  final String? barcode;

  /// Live Open Food Facts results whose picker key is not among [results].
  final List<FoodPickerItem> onlineResults;

  /// The last live search's state; cleared when the query changes.
  final OnlinePickerStatus onlineStatus;

  /// The device setting "Look up foods online".
  final bool onlineLookupsEnabled;
  final BundleStatus bundleStatus;

  AddFoodPickerState copyWith({
    String? query,
    AddFoodPickerFilter? filter,
    List<FoodPickerItem>? results,
    BarcodeLookupStatus? barcodeLookupStatus,
    String? barcode,
    bool clearBarcode = false,
    List<FoodPickerItem>? onlineResults,
    OnlinePickerStatus? onlineStatus,
    bool? onlineLookupsEnabled,
    BundleStatus? bundleStatus,
  }) {
    return AddFoodPickerState(
      query: query ?? this.query,
      filter: filter ?? this.filter,
      results: results ?? this.results,
      barcodeLookupStatus: barcodeLookupStatus ?? this.barcodeLookupStatus,
      barcode: clearBarcode ? null : barcode ?? this.barcode,
      onlineResults: onlineResults ?? this.onlineResults,
      onlineStatus: onlineStatus ?? this.onlineStatus,
      onlineLookupsEnabled: onlineLookupsEnabled ?? this.onlineLookupsEnabled,
      bundleStatus: bundleStatus ?? this.bundleStatus,
    );
  }
}

enum BarcodeLookupStatus {
  idle,
  loading,
  notFound,
  needsNetwork,

  /// Open Food Facts answered but could not serve the lookup.
  unavailable,

  /// Online lookups are off and the product is not on the device.
  disabled;
}

/// The online slot of the All and Open Food Facts filters.
enum OnlinePickerStatus { idle, loading, ok, noResults, offline, unavailable }

class AddFoodPickerController extends AsyncNotifier<AddFoodPickerState> {
  static const searchDebounceDuration = Duration(milliseconds: 300);

  String _query = '';
  AddFoodPickerFilter _filter = AddFoodPickerFilter.all;

  /// Read once per opening; every search in it filters this in memory.
  YourFoods _yourFoods = YourFoods.empty;

  /// Every item the last live search returned, kept until the live results
  /// are cleared, so a device reload can merge them again in full.
  List<FoodPickerItem> _liveItems = const <FoodPickerItem>[];
  Timer? _searchDebounceTimer;
  var _searchGeneration = 0;
  bool _onlineLookupsEnabled = true;

  @override
  Future<AddFoodPickerState> build() async {
    ref.onDispose(() {
      _searchDebounceTimer?.cancel();
      _searchGeneration += 1;
    });
    ref.listen(settingsControllerProvider, (_, next) {
      final enabled = next.asData?.value.onlineFoodLookups;
      if (enabled == null || enabled == _onlineLookupsEnabled) {
        return;
      }
      _onlineLookupsEnabled = enabled;
      _updateCurrent((current) {
        return current.copyWith(onlineLookupsEnabled: enabled);
      });
    });
    ref.listen(bundleStatusProvider, (previous, next) {
      final status = next.asData?.value;
      final was = previous?.asData?.value;
      if (status == null || status == was) {
        return;
      }
      _updateCurrent((current) => current.copyWith(bundleStatus: status));
      // The install writes on another connection, so stream queries here do
      // not see it: search the device again when an install finishes. Not on
      // the first value (the bundle was already there), and without touching
      // a live search that is shown or running.
      if (was == BundleStatus.installing && status == BundleStatus.ready) {
        unawaited(_reloadDeviceMatches());
      }
    });
    final repository = ref.read(addFoodRepositoryProvider);
    final (onlineLookupsEnabled, yourFoods) = await (
      // Settings that fail to load must not take the picker down with them;
      // online lookups default to on.
      repository.onlineLookupsEnabled().catchError((Object _) => true),
      // A failed Food History read leaves the Catalogue searchable.
      repository.loadYourFoods().catchError((Object _) => YourFoods.empty),
    ).wait;
    _onlineLookupsEnabled = onlineLookupsEnabled;
    _yourFoods = yourFoods;
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

  /// The online search row or the keyboard's search action. Runs the local
  /// search at once; in the All and Open Food Facts filters it then returns
  /// the item to open (a stored barcode match, or a live barcode hit), sets
  /// the barcode line for a barcode miss, or runs one live search. In Your
  /// foods and USDA it returns `null`.
  Future<FoodPickerItem?> submitQuery(String query) async {
    if (query != _query) {
      _query = query;
      _showPendingQuery(query);
    }
    _searchDebounceTimer?.cancel();
    await _refresh(generation: ++_searchGeneration, keepShown: true);
    if (_filter != AddFoodPickerFilter.all &&
        _filter != AddFoodPickerFilter.openFoodFacts) {
      return null;
    }
    if (barcodeCandidates(query).isNotEmpty) {
      return lookupBarcode(query);
    }
    if (buildFoodSearchMatch(query) == null) {
      return null;
    }
    await _searchOnline(query);
    return null;
  }

  Future<void> _searchOnline(String query) async {
    final generation = _searchGeneration;
    // Loading is set on the current data, never as AsyncLoading, so the
    // device's matches stay on screen while the request runs.
    _updateCurrent(
      (current) => current.copyWith(onlineStatus: OnlinePickerStatus.loading),
    );
    ({OnlineSearchStatus status, List<FoodPickerItem> items}) result;
    try {
      result = await ref
          .read(addFoodRepositoryProvider)
          .searchOnline(query, yourFoods: _yourFoods);
    } on Object {
      // An unexpected failure reads as unavailable.
      result = (
        status: OnlineSearchStatus.unavailable,
        items: const <FoodPickerItem>[],
      );
    }
    if (generation != _searchGeneration) {
      return;
    }
    _liveItems = result.items;
    _updateCurrent((current) {
      final (:results, :onlineResults) = _mergeLiveResults(
        current.results,
        result.items,
      );
      return current.copyWith(
        results: results,
        onlineResults: onlineResults,
        onlineStatus: switch (result.status) {
          OnlineSearchStatus.ok => OnlinePickerStatus.ok,
          OnlineSearchStatus.noResults => OnlinePickerStatus.noResults,
          OnlineSearchStatus.offline => OnlinePickerStatus.offline,
          OnlineSearchStatus.unavailable => OnlinePickerStatus.unavailable,
          OnlineSearchStatus.disabled => OnlinePickerStatus.idle,
        },
      );
    });
  }

  /// A live result whose picker key matches an Open Food Facts Catalogue row
  /// and whose change date is later takes that row's place; the rest whose
  /// key is not listed follow the device's matches, in the order Open Food
  /// Facts returned them. A Your foods row is never replaced: its facts
  /// already come from the current device copy, and a live copy is stored on
  /// the device when the user opens it.
  static ({List<FoodPickerItem> results, List<FoodPickerItem> onlineResults})
      _mergeLiveResults(
    List<FoodPickerItem> local,
    List<FoodPickerItem> live,
  ) {
    final liveByKey = {for (final item in live) item.key: item};
    final localKeys = {for (final item in local) item.key};
    return (
      results: [
        for (final item in local)
          if (liveByKey[item.key] case final newer?
              when item.origin == FoodPickerOrigin.openFoodFacts &&
                  _isNewer(newer, than: item))
            newer
          else
            item,
      ],
      onlineResults: [
        for (final item in live)
          if (!localKeys.contains(item.key)) item,
      ],
    );
  }

  static bool _isNewer(FoodPickerItem item, {required FoodPickerItem than}) {
    final changed = item.sourceModifiedAt;
    final stored = than.sourceModifiedAt;
    return changed != null && (stored == null || changed.isAfter(stored));
  }

  Future<void> selectFilter(AddFoodPickerFilter filter) async {
    if (filter == _filter) {
      return;
    }
    _filter = filter;
    _searchDebounceTimer?.cancel();
    await _refresh(generation: ++_searchGeneration);
  }

  /// A scanned or submitted barcode: a stored product is used as it is; else
  /// one live product request when online lookups are on.
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
    ({BarcodeLookupOutcome status, FoodPickerItem? item}) result;
    try {
      result = await ref
          .read(addFoodRepositoryProvider)
          .lookupBarcode(normalizedBarcode, yourFoods: _yourFoods);
    } on Object {
      // An unexpected failure reads as unavailable.
      result = (status: BarcodeLookupOutcome.unavailable, item: null);
    }
    if (generation != _searchGeneration) {
      return null;
    }
    final item = result.item;
    if (result.status == BarcodeLookupOutcome.found && item != null) {
      state = AsyncData<AddFoodPickerState>(
        _currentState().copyWith(
          barcodeLookupStatus: BarcodeLookupStatus.idle,
          clearBarcode: true,
        ),
      );
      return item;
    }
    state = AsyncData<AddFoodPickerState>(
      _currentState().copyWith(
        barcodeLookupStatus: switch (result.status) {
          BarcodeLookupOutcome.found ||
          BarcodeLookupOutcome.notFound ||
          BarcodeLookupOutcome.notABarcode =>
            BarcodeLookupStatus.notFound,
          BarcodeLookupOutcome.offline => BarcodeLookupStatus.needsNetwork,
          BarcodeLookupOutcome.unavailable => BarcodeLookupStatus.unavailable,
          BarcodeLookupOutcome.disabled => BarcodeLookupStatus.disabled,
        },
        barcode: normalizedBarcode,
      ),
    );
    return null;
  }

  /// Called before an item opens: a live copy is stored in the background.
  void openItem(FoodPickerItem item) {
    if (item.isLiveResult) {
      unawaited(ref.read(addFoodRepositoryProvider).keepOpenedProduct(item));
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

  /// Re-runs the device search for the current query and filter, keeping
  /// the online slot and any live search in flight.
  Future<void> _reloadDeviceMatches() async {
    // Not a new generation: a reload must not cancel a live search. Any newer
    // query, filter, submit or disposal moves the generation on, and the
    // reload's results are then dropped.
    final generation = _searchGeneration;
    final List<FoodPickerItem> results;
    try {
      results = await ref.read(addFoodRepositoryProvider).search(
            filter: _filter,
            query: _query,
            yourFoods: _yourFoods,
          );
    } on Object {
      return;
    }
    if (generation != _searchGeneration) {
      return;
    }
    // The device may now hold products the live search returned: merge the
    // whole live list again, so none is listed twice and a newer live copy
    // keeps the place it took.
    final (results: merged, :onlineResults) =
        _mergeLiveResults(results, _liveItems);
    _updateCurrent(
      (current) =>
          current.copyWith(results: merged, onlineResults: onlineResults),
    );
  }

  /// Searches the device again. With [keepShown], the current data stays on
  /// screen while the search runs instead of going through `AsyncLoading`:
  /// a submit must never blank the device's matches, the online row or the
  /// bundle line before its live request starts.
  Future<void> _refresh({
    required int generation,
    bool keepShown = false,
  }) async {
    final filter = _filter;
    final query = _query;
    if (!keepShown || !state.hasValue) {
      state = const AsyncLoading<AddFoodPickerState>();
    }
    final next = await AsyncValue.guard(
      () => _load(filter: filter, query: query),
    );
    if (generation != _searchGeneration) {
      return;
    }
    // A new device search starts with no live results.
    _liveItems = const <FoodPickerItem>[];
    state = next;
  }

  Future<AddFoodPickerState> _load({
    required AddFoodPickerFilter filter,
    required String query,
  }) async {
    final results = await ref.read(addFoodRepositoryProvider).search(
          filter: filter,
          query: query,
          yourFoods: _yourFoods,
        );
    return AddFoodPickerState(
      query: query,
      filter: filter,
      results: results,
      onlineLookupsEnabled: _onlineLookupsEnabled,
      bundleStatus: _bundleStatus(),
    );
  }

  BundleStatus _bundleStatus() {
    return ref.read(bundleStatusProvider).asData?.value ?? BundleStatus.unknown;
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
      onlineLookupsEnabled: _onlineLookupsEnabled,
      bundleStatus: _bundleStatus(),
    );
  }

  void _updateCurrent(
    AddFoodPickerState Function(AddFoodPickerState current) update,
  ) {
    final current = state.asData?.value;
    if (current != null) {
      state = AsyncData<AddFoodPickerState>(update(current));
    }
  }

  void _showPendingQuery(String query) {
    _liveItems = const <FoodPickerItem>[];
    _updateCurrent(
      (current) => current.copyWith(
        query: query,
        barcodeLookupStatus: BarcodeLookupStatus.idle,
        clearBarcode: true,
        onlineResults: const <FoodPickerItem>[],
        onlineStatus: OnlinePickerStatus.idle,
      ),
    );
  }
}
