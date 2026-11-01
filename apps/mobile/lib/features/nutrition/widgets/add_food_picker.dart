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
import 'portion_text.dart';
import 'quick_entry_dialog.dart';

// The causes a barcode miss and the online slot share.
const _offlineLine = "You're offline. Showing foods on this device.";
const _unavailableLine =
    'Open Food Facts is unavailable. Try again in a minute.';
const _lookupsOffLine =
    'Online lookups are off. Turn them on in Settings > Food data.';

const _visibleFoodPickerFilters = <AddFoodPickerFilter>[
  AddFoodPickerFilter.all,
  AddFoodPickerFilter.yours,
  AddFoodPickerFilter.usda,
  AddFoodPickerFilter.openFoodFacts,
];

const _noMatchLine = 'No foods match.';

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

  /// The Open Food Facts filter's blank-query line.
  static const emptyQueryLineKey = Key('nutrition.addFood.emptyQueryLine');
  static const yourFoodsLabelKey = Key('nutrition.addFood.yourFoodsLabel');

  /// The blank-query line when there is nothing to list: All with no Your
  /// foods, or the Your foods filter with none.
  static const emptyStateKey = Key('nutrition.addFood.emptyState');
  static const noMatchLineKey = Key('nutrition.addFood.noMatch');
  static const attributionFooterKey =
      Key('nutrition.addFood.attributionFooter');
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

  static Key resultKey(FoodPickerItem item) {
    return Key('nutrition.addFood.result-${item.foodSource.name}-${item.id}');
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
              selected: AddFoodPickerFilter.all,
            ),
            error: (_, __) => const _FoodSourceChips(
              selected: AddFoodPickerFilter.all,
            ),
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
    await _openFound(
      context,
      ref,
      ref.read(addFoodPickerControllerProvider.notifier).lookupBarcode(barcode),
    );
  }

  /// The keyboard's search action and the online search row. A typed barcode
  /// that is found opens the log-portion screen through the scan's path.
  Future<void> _submit(BuildContext context, WidgetRef ref, String query) {
    return _openFound(
      context,
      ref,
      ref.read(addFoodPickerControllerProvider.notifier).submitQuery(query),
    );
  }

  /// Opens the item a scan or a submit found, if the picker is still shown.
  Future<void> _openFound(
    BuildContext context,
    WidgetRef ref,
    Future<FoodPickerItem?> lookup,
  ) async {
    final food = await lookup;
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

/// The list under the chips, per filter and query
/// (docs/designs/unified-food-search.md § The picker, top to bottom).
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
    final blank = buildFoodSearchMatch(state.query) == null &&
        barcodeCandidates(state.query).isEmpty;
    final children = switch (state.filter) {
      AddFoodPickerFilter.all when blank => [
          if (state.results.isEmpty)
            const _StatusLine(
              key: AddFoodPicker.emptyStateKey,
              text: 'Search by name or brand, or scan a barcode.',
            )
          else ...[
            Semantics(
              header: true,
              child: Padding(
                key: AddFoodPicker.yourFoodsLabelKey,
                padding: const EdgeInsets.only(bottom: AppDimens.dense),
                child: Text(
                  'Your foods',
                  style: context.textStyles.label.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
            ..._rows(context, state.results),
          ],
        ],
      AddFoodPickerFilter.all => [
          ..._rows(context, state.results),
          if (state.results.isEmpty)
            const _StatusLine(
              key: AddFoodPicker.noMatchLineKey,
              text: _noMatchLine,
            ),
          ..._bundleLine(),
          ..._online(context),
        ],
      AddFoodPickerFilter.yours => [
          ..._rows(context, state.results),
          if (state.results.isEmpty)
            blank
                ? const _StatusLine(
                    key: AddFoodPicker.emptyStateKey,
                    text: 'Foods you log or create appear here.',
                  )
                : const _StatusLine(
                    key: AddFoodPicker.noMatchLineKey,
                    text: _noMatchLine,
                  ),
        ],
      AddFoodPickerFilter.usda => [
          ..._rows(context, state.results),
          if (state.results.isEmpty)
            const _StatusLine(
              key: AddFoodPicker.noMatchLineKey,
              text: _noMatchLine,
            ),
        ],
      AddFoodPickerFilter.openFoodFacts => [
          ..._bundleLine(),
          if (blank)
            const _StatusLine(
              key: AddFoodPicker.emptyQueryLineKey,
              text: 'Search Open Food Facts by product name, brand or '
                  'barcode.',
            )
          else ...[
            ..._rows(context, state.results),
            ..._online(context),
          ],
        ],
    };
    // One rule: any Open Food Facts row in the list, from the device or a
    // live search, puts the compact notice after the last list item.
    final hasOpenFoodFactsRow = [
      ...state.results,
      ...state.onlineResults,
    ].any((item) => item.foodSource == FoodSource.openFoodFacts);

    return ListView(
      children: [
        ...children,
        if (hasOpenFoodFactsRow)
          const Padding(
            key: AddFoodPicker.attributionFooterKey,
            padding: EdgeInsets.only(top: AppDimens.base),
            child: OpenFoodFactsAttributionNotice(compact: true),
          ),
      ],
    );
  }

  List<Widget> _rows(BuildContext context, List<FoodPickerItem> items) {
    return [
      for (final item in items) ...[
        _FoodResultRow(item: item, onOpen: onOpen),
        Divider(height: 1, color: context.colors.divider),
      ],
    ];
  }

  List<Widget> _bundleLine() {
    final line = switch (state.bundleStatus) {
      BundleStatus.installing => 'Preparing the offline food list.',
      BundleStatus.failed => 'The offline food list could not be prepared. '
          'It will try again next time the app opens.',
      BundleStatus.unknown || BundleStatus.ready => null,
    };
    return [
      if (line != null)
        _StatusLine(key: AddFoodPicker.bundleStatusLineKey, text: line),
    ];
  }

  /// The online slot, then the live-only results.
  List<Widget> _online(BuildContext context) {
    return [
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
            ..._rows(context, state.onlineResults),
          ],
        ),
    ];
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
        ? _lookupsOffLine
        : switch (state.onlineStatus) {
            OnlinePickerStatus.offline => _offlineLine,
            OnlinePickerStatus.unavailable => _unavailableLine,
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
                padding: EdgeInsets.all(AppDimens.dense / 4),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Icon(Icons.search, color: context.colors.textPrimary),
      title: Text(
        'Search Open Food Facts online for "${state.query.trim()}"',
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
    final status = state.barcodeLookupStatus;
    if (status == BarcodeLookupStatus.idle) {
      return null;
    }
    if (status == BarcodeLookupStatus.loading) {
      return const _LookupStatus(
        key: AddFoodPicker.barcodeStatusKey,
        isLoading: true,
        message: 'Looking up barcode in Open Food Facts',
      );
    }
    // Every miss shows the not-found state, with one line for its cause.
    return _LookupStatus(
      key: AddFoodPicker.barcodeStatusKey,
      message: 'Barcode not found. USDA foods stay fully offline, or use '
          'Quick add.',
      line: switch (status) {
        BarcodeLookupStatus.needsNetwork => _offlineLine,
        BarcodeLookupStatus.unavailable => _unavailableLine,
        BarcodeLookupStatus.disabled => _lookupsOffLine,
        _ => null,
      },
    );
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
    final onTap = onOpen == null ? null : () => onOpen!(item);
    final secondary = context.textStyles.label.copyWith(
      color: context.colors.textSecondary,
    );
    final energy = _energyLabel(item);
    final lastPortion = switch (item.lastPortion) {
      final portion? => formatPortionAmount(portion),
      null => null,
    };
    // One label, read once: the child texts are not separate nodes.
    return Semantics(
      button: true,
      label: [
        item.name,
        if (item.brand case final brand?) brand,
        item.foodSourceLabel,
        energy,
        if (lastPortion != null) 'Last $lastPortion',
      ].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: ListTile(
        key: AddFoodPicker.resultKey(item),
        minTileHeight: AppDimens.touchTarget,
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
                  padding: const EdgeInsets.only(bottom: AppDimens.dense / 2),
                  child: Text(brand, style: secondary),
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
                  Text(energy, style: secondary),
                  if (lastPortion != null)
                    Text('Last: $lastPortion', style: secondary),
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
        onTap: onTap,
      ),
    );
  }
}

/// Decorative: names why the row is listed; the source is always named by
/// the text badge.
IconData _sourceIcon(FoodPickerItem item) {
  return switch (item.origin) {
    FoodPickerOrigin.history => Icons.history,
    FoodPickerOrigin.userFood => Icons.person_outline,
    FoodPickerOrigin.usda => Icons.public,
    FoodPickerOrigin.openFoodFacts => Icons.qr_code_scanner,
  };
}

String _energyLabel(FoodPickerItem item) {
  final energy = item.nutrientsPer100[NutrientId.energy];
  if (!energy.isComplete) {
    return 'calories unknown';
  }
  return '${formatNutritionNumber(energy.value!)} kcal per 100';
}
