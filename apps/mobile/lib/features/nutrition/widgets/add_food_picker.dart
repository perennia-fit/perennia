import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/open_food_facts_repository.dart';
import '../../../domain/nutrition/nutrition.dart';
import '../../../domain/nutrition/open_food_facts.dart';
import '../../../theme/theme.dart';
import '../controllers/add_food_controller.dart';
import '../repositories/add_food_repository.dart';
import 'barcode_scanner.dart';
import 'nutrition_attribution.dart';
import 'quick_entry_dialog.dart';

const _visibleFoodPickerFilters = <AddFoodPickerFilter>[
  AddFoodPickerFilter.recent,
  AddFoodPickerFilter.user,
  AddFoodPickerFilter.usda,
  AddFoodPickerFilter.openFoodFacts,
];

class AddFoodPicker extends ConsumerWidget {
  const AddFoodPicker({
    super.key,
    required this.meal,
    this.onFoodSelected,
    this.onQuickEntry,
  });

  static const searchFieldKey = Key('nutrition.addFood.search');
  static const quickAddButtonKey = Key('nutrition.addFood.quickAdd');
  static const scanBarcodeButtonKey = Key('nutrition.addFood.scanBarcode');
  static const barcodeStatusKey = Key('nutrition.addFood.barcodeStatus');

  /// The one line under a barcode miss (offline, unavailable or lookups off).
  static const barcodeStatusLineKey =
      Key('nutrition.addFood.barcodeStatusLine');
  static const onlineSearchRowKey = Key('nutrition.addFood.onlineSearch');
  static const onlineGroupKey = Key('nutrition.addFood.onlineGroup');
  static const onlineStatusLineKey = Key('nutrition.addFood.onlineStatusLine');
  static const bundleStatusLineKey = Key('nutrition.addFood.bundleStatusLine');
  static const emptyQueryLineKey = Key('nutrition.addFood.emptyQueryLine');
  static const barcodeQuickAddButtonKey =
      Key('nutrition.addFood.barcodeQuickAdd');
  static const lookupUsdaButtonKey = Key('nutrition.addFood.lookupUsda');
  static const searchDebounceDuration =
      AddFoodPickerController.searchDebounceDuration;

  final MealRecord meal;
  final ValueChanged<FoodPickerItem>? onFoodSelected;
  final Future<void> Function(QuickFoodEntryDraft draft)? onQuickEntry;

  static Key filterChipKey(AddFoodPickerFilter filter) {
    return Key('nutrition.addFood.filter-${filter.name}');
  }

  static Key resultKey(AddFoodPickerFilter filter, String id) {
    return Key('nutrition.addFood.result-${filter.name}-$id');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(addFoodPickerControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(AppDimens.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Add Food',
                  style: context.textStyles.h1,
                ),
              ),
              IconButton.outlined(
                key: scanBarcodeButtonKey,
                tooltip: 'Scan barcode',
                onPressed: () {
                  unawaited(_scanBarcode(context, ref));
                },
                icon: const Icon(Icons.qr_code_scanner),
              ),
              const SizedBox(width: AppDimens.dense),
              FilledButton.icon(
                key: quickAddButtonKey,
                onPressed: () {
                  unawaited(_quickAdd(context, ref));
                },
                icon: const Icon(Icons.add),
                label: const Text('Quick add'),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.base),
          TextField(
            key: searchFieldKey,
            decoration: const InputDecoration(
              hintText: 'Search foods',
              prefixIcon: Icon(Icons.search),
            ),
            textInputAction: TextInputAction.search,
            onChanged: (value) {
              unawaited(
                ref
                    .read(addFoodPickerControllerProvider.notifier)
                    .setQuery(value),
              );
            },
            onSubmitted: (value) {
              unawaited(_submit(context, ref, value));
            },
          ),
          const SizedBox(height: AppDimens.base),
          state.when(
            data: (value) => _FoodSourceChips(selected: value.filter),
            loading: () => const _FoodSourceChips(
              selected: AddFoodPickerFilter.recent,
            ),
            error: (_, __) => const _FoodSourceChips(
              selected: AddFoodPickerFilter.recent,
            ),
          ),
          state.maybeWhen(
            data: (value) => value.filter == AddFoodPickerFilter.openFoodFacts
                ? const Padding(
                    padding: EdgeInsets.only(top: AppDimens.base),
                    child: OpenFoodFactsAttributionNotice(compact: true),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppDimens.base),
          state.when(
            data: (value) => _LookupBoundaryBanner(
              state: value,
              onQuickAdd: () {
                unawaited(_quickAdd(context, ref));
              },
              onUseUsda: () {
                unawaited(
                  ref
                      .read(addFoodPickerControllerProvider.notifier)
                      .selectFilter(AddFoodPickerFilter.usda),
                );
              },
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          state.maybeWhen(
            data: (value) =>
                value.barcodeLookupStatus == BarcodeLookupStatus.idle
                    ? const SizedBox.shrink()
                    : const SizedBox(height: AppDimens.base),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: state.when(
              data: (value) => _FoodResults(
                state: value,
                onOpen:
                    onFoodSelected == null ? null : (item) => _open(ref, item),
                onSearchOnline: () {
                  unawaited(_submit(context, ref, value.query));
                },
              ),
              loading: () => const SizedBox.expand(),
              error: (_, __) => Center(
                child: Text(
                  'Food picker unavailable',
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _quickAdd(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<QuickFoodEntryDraft>(
      context: context,
      builder: (context) => QuickEntryDialog(mealType: meal.mealType),
    );
    if (draft == null) {
      return;
    }
    if (onQuickEntry != null) {
      await onQuickEntry!(draft);
      return;
    }
    await ref
        .read(addFoodPickerControllerProvider.notifier)
        .logQuickEntryForMeal(
          mealId: meal.id,
          entry: draft,
        );
  }

  Future<void> _scanBarcode(BuildContext context, WidgetRef ref) async {
    final barcode = await ref.read(barcodeScannerProvider).scan(context);
    if (!context.mounted || barcode == null || barcode.trim().isEmpty) {
      return;
    }
    final food = await ref
        .read(addFoodPickerControllerProvider.notifier)
        .lookupBarcode(barcode);
    if (!context.mounted || food == null) {
      return;
    }
    _open(ref, food);
  }

  /// The keyboard's search action and the online search row. A typed barcode
  /// that is found opens the log-portion screen through the scan's path.
  Future<void> _submit(
      BuildContext context, WidgetRef ref, String query) async {
    final food = await ref
        .read(addFoodPickerControllerProvider.notifier)
        .submitQuery(query);
    if (!context.mounted || food == null) {
      return;
    }
    _open(ref, food);
  }

  /// Every opened item goes through the controller first, which stores a live
  /// copy in the background.
  void _open(WidgetRef ref, FoodPickerItem item) {
    final onSelected = onFoodSelected;
    if (onSelected == null) {
      return;
    }
    ref.read(addFoodPickerControllerProvider.notifier).openItem(item);
    onSelected(item);
  }
}

class _FoodSourceChips extends ConsumerWidget {
  const _FoodSourceChips({
    required this.selected,
  });

  final AddFoodPickerFilter selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: AppDimens.dense,
      runSpacing: AppDimens.dense,
      children: [
        for (final filter in _visibleFoodPickerFilters)
          ChoiceChip(
            key: AddFoodPicker.filterChipKey(filter),
            label: Text(filter.label),
            selected: selected == filter,
            onSelected: (_) {
              unawaited(
                ref
                    .read(addFoodPickerControllerProvider.notifier)
                    .selectFilter(filter),
              );
            },
          ),
      ],
    );
  }
}

class _FoodResults extends StatelessWidget {
  const _FoodResults({
    required this.state,
    required this.onOpen,
    required this.onSearchOnline,
  });

  final AddFoodPickerState state;
  final ValueChanged<FoodPickerItem>? onOpen;
  final VoidCallback onSearchOnline;

  @override
  Widget build(BuildContext context) {
    if (state.filter != AddFoodPickerFilter.openFoodFacts) {
      if (state.results.isEmpty) {
        return const Align(
          alignment: Alignment.topLeft,
          child: _StatusLine(text: 'No foods found'),
        );
      }
      return ListView.separated(
        itemCount: state.results.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: context.colors.divider,
        ),
        itemBuilder: (context, index) => _FoodResultRow(
          item: state.results[index],
          onOpen: onOpen,
        ),
      );
    }

    // The Open Food Facts filter, top to bottom: the bundle line, the
    // device's matches, the online slot, and the live-only results.
    final bundleLine = switch (state.bundleStatus) {
      BundleStatus.installing => 'Preparing the offline food list.',
      BundleStatus.failed => 'The offline food list could not be prepared. '
          'It will try again next time the app opens.',
      BundleStatus.unknown || BundleStatus.ready => null,
    };
    final hasSearchParts = buildFoodSearchMatch(state.query) != null ||
        barcodeCandidates(state.query).isNotEmpty;

    return ListView(
      children: [
        if (bundleLine != null)
          _StatusLine(key: AddFoodPicker.bundleStatusLineKey, text: bundleLine),
        if (!hasSearchParts)
          const _StatusLine(
            key: AddFoodPicker.emptyQueryLineKey,
            text: 'Type a product or brand name.',
          )
        else ...[
          for (final item in state.results) ...[
            _FoodResultRow(item: item, onOpen: onOpen),
            Divider(height: 1, color: context.colors.divider),
          ],
          _OnlineSlot(state: state, onSearchOnline: onSearchOnline),
          if (state.onlineResults.isNotEmpty)
            Column(
              key: AddFoodPicker.onlineGroupKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppDimens.base,
                    bottom: AppDimens.dense,
                  ),
                  child: Text(
                    'From Open Food Facts',
                    style: context.textStyles.label.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
                for (final item in state.onlineResults) ...[
                  _FoodResultRow(item: item, onOpen: onOpen),
                  Divider(height: 1, color: context.colors.divider),
                ],
              ],
            ),
        ],
      ],
    );
  }
}

/// Exactly one of: the lookups-off line, the online search row (with a
/// progress indicator while a live request runs), the last live request's
/// offline, unavailable or no-results line, or the online search row.
class _OnlineSlot extends StatelessWidget {
  const _OnlineSlot({required this.state, required this.onSearchOnline});

  final AddFoodPickerState state;
  final VoidCallback onSearchOnline;

  @override
  Widget build(BuildContext context) {
    final line = !state.onlineLookupsEnabled
        ? 'Online lookups are off. Turn them on in Settings > Food data.'
        : switch (state.onlineStatus) {
            OnlinePickerStatus.offline =>
              "You're offline. Showing foods on this device.",
            OnlinePickerStatus.unavailable =>
              'Open Food Facts is unavailable. Try again in a minute.',
            OnlinePickerStatus.noResults => 'No matches on Open Food Facts.',
            OnlinePickerStatus.idle ||
            OnlinePickerStatus.loading ||
            OnlinePickerStatus.ok =>
              null,
          };
    if (line != null) {
      return _StatusLine(key: AddFoodPicker.onlineStatusLineKey, text: line);
    }
    final loading = state.onlineStatus == OnlinePickerStatus.loading;
    return ListTile(
      key: AddFoodPicker.onlineSearchRowKey,
      minTileHeight: AppDimens.touchTarget,
      contentPadding: EdgeInsets.zero,
      leading: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: Padding(
                padding: EdgeInsets.all(3),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Icon(Icons.search, color: context.colors.textPrimary),
      title: Text(
        'Search Open Food Facts for "${state.query.trim()}"',
        style: context.textStyles.body.copyWith(
          color: context.colors.textPrimary,
        ),
      ),
      onTap: loading ? null : onSearchOnline,
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: Text(
        text,
        style: context.textStyles.body.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _LookupBoundaryBanner extends StatelessWidget {
  const _LookupBoundaryBanner({
    required this.state,
    required this.onQuickAdd,
    required this.onUseUsda,
  });

  final AddFoodPickerState state;
  final VoidCallback onQuickAdd;
  final VoidCallback onUseUsda;

  @override
  Widget build(BuildContext context) {
    final status = _lookupStatus();
    final message = status?.message;
    if (message == null) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      key: status!.key,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.dense),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (status.isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                Icons.info_outline,
                color: context.colors.textSecondary,
              ),
            const SizedBox(width: AppDimens.dense),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: context.textStyles.body,
                  ),
                  if (status.line case final line?) ...[
                    const SizedBox(height: AppDimens.dense),
                    Text(
                      line,
                      key: AddFoodPicker.barcodeStatusLineKey,
                      style: context.textStyles.body.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                  if (!status.isLoading) ...[
                    const SizedBox(height: AppDimens.dense),
                    Wrap(
                      spacing: AppDimens.dense,
                      runSpacing: AppDimens.dense,
                      children: [
                        SizedBox(
                          height: AppDimens.touchTarget,
                          child: OutlinedButton.icon(
                            key: AddFoodPicker.lookupUsdaButtonKey,
                            onPressed: onUseUsda,
                            icon: const Icon(Icons.public),
                            label: const Text('USDA'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.colors.textPrimary,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: AppDimens.touchTarget,
                          child: TextButton.icon(
                            key: AddFoodPicker.barcodeQuickAddButtonKey,
                            style: TextButton.styleFrom(
                              foregroundColor: context.colors.textPrimary,
                            ),
                            onPressed: onQuickAdd,
                            icon: const Icon(Icons.add),
                            label: const Text('Quick add'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _LookupStatus? _lookupStatus() {
    const notFound = 'Barcode not found. USDA foods stay fully offline, or use '
        'Quick add.';
    return switch (state.barcodeLookupStatus) {
      BarcodeLookupStatus.idle => null,
      BarcodeLookupStatus.loading => const _LookupStatus(
          key: AddFoodPicker.barcodeStatusKey,
          isLoading: true,
          message: 'Looking up barcode in Open Food Facts',
        ),
      BarcodeLookupStatus.notFound => const _LookupStatus(
          key: AddFoodPicker.barcodeStatusKey,
          message: notFound,
        ),
      BarcodeLookupStatus.needsNetwork => const _LookupStatus(
          key: AddFoodPicker.barcodeStatusKey,
          message: notFound,
          line: "You're offline. Showing foods on this device.",
        ),
      BarcodeLookupStatus.unavailable => const _LookupStatus(
          key: AddFoodPicker.barcodeStatusKey,
          message: notFound,
          line: 'Open Food Facts is unavailable. Try again in a minute.',
        ),
      BarcodeLookupStatus.disabled => const _LookupStatus(
          key: AddFoodPicker.barcodeStatusKey,
          message: notFound,
          line: 'Online lookups are off. Turn them on in Settings > Food data.',
        ),
    };
  }
}

class _LookupStatus {
  const _LookupStatus({
    required this.key,
    required this.message,
    this.line,
    this.isLoading = false,
  });

  final Key key;
  final String message;

  /// The one line under the not-found state, when the miss has a cause.
  final String? line;
  final bool isLoading;
}

class _FoodResultRow extends StatelessWidget {
  const _FoodResultRow({
    required this.item,
    required this.onOpen,
  });

  final FoodPickerItem item;
  final ValueChanged<FoodPickerItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: AddFoodPicker.resultKey(item.filter, item.id),
      minVerticalPadding: AppDimens.dense,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        _sourceIcon(item),
        color: context.colors.textSecondary,
      ),
      title: Text(
        item.name,
        style: context.textStyles.body,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.brand case final brand?)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  brand,
                  style: context.textStyles.label.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FoodSourceBadge(
                  source: item.foodSource,
                  showLicense: item.foodSource == FoodSource.openFoodFacts,
                ),
                Text(
                  _energyLabel(item),
                  style: context.textStyles.label.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      trailing: onOpen == null
          ? null
          : Icon(
              Icons.chevron_right,
              color: context.colors.textSecondary,
            ),
      onTap: onOpen == null ? null : () => onOpen!(item),
    );
  }
}

IconData _sourceIcon(FoodPickerItem item) {
  return switch (item.filter) {
    AddFoodPickerFilter.recent => Icons.history,
    AddFoodPickerFilter.user => Icons.person_outline,
    AddFoodPickerFilter.usda => Icons.public,
    AddFoodPickerFilter.openFoodFacts => Icons.qr_code_scanner,
  };
}

String _energyLabel(FoodPickerItem item) {
  final energy = item.nutrientsPer100[NutrientId.energy];
  if (!energy.isComplete) {
    return 'calories unknown';
  }
  return '${formatNutritionNumber(energy.value!)} kcal per 100';
}
