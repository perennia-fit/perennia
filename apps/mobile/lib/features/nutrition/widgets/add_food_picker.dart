import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/nutrition/nutrition.dart';
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
  static const brandedSearchStatusKey =
      Key('nutrition.addFood.brandedSearchStatus');
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
              unawaited(
                ref
                    .read(addFoodPickerControllerProvider.notifier)
                    .submitQuery(value),
              );
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
                value.barcodeLookupStatus == BarcodeLookupStatus.idle &&
                        !value.brandedSearchNeedsNetwork
                    ? const SizedBox.shrink()
                    : const SizedBox(height: AppDimens.base),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: state.when(
              data: (value) => _FoodResults(
                state: value,
                onFoodSelected: onFoodSelected,
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
    if (!context.mounted || food == null || onFoodSelected == null) {
      return;
    }
    onFoodSelected!(food);
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
    required this.onFoodSelected,
  });

  final AddFoodPickerState state;
  final ValueChanged<FoodPickerItem>? onFoodSelected;

  @override
  Widget build(BuildContext context) {
    if (state.results.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          'No foods found',
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: state.results.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: context.colors.divider,
      ),
      itemBuilder: (context, index) {
        final item = state.results[index];
        return _FoodResultRow(
          item: item,
          onFoodSelected: onFoodSelected,
        );
      },
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
    if (state.barcodeLookupStatus == BarcodeLookupStatus.loading) {
      return const _LookupStatus(
        key: AddFoodPicker.barcodeStatusKey,
        isLoading: true,
        message: 'Looking up barcode in Open Food Facts',
      );
    }
    if (state.barcodeLookupStatus == BarcodeLookupStatus.notFound) {
      return const _LookupStatus(
        key: AddFoodPicker.barcodeStatusKey,
        message:
            'Barcode not found. USDA foods stay fully offline, or use Quick add.',
      );
    }
    if (state.barcodeLookupStatus == BarcodeLookupStatus.needsNetwork) {
      return const _LookupStatus(
        key: AddFoodPicker.barcodeStatusKey,
        message:
            'Open Food Facts barcode lookup needs network the first time. USDA foods stay fully offline, or use Quick add.',
      );
    }
    if (state.brandedSearchNeedsNetwork) {
      return const _LookupStatus(
        key: AddFoodPicker.brandedSearchStatusKey,
        message:
            'Open Food Facts branded search needs network the first time. USDA foods stay fully offline, or use Quick add.',
      );
    }
    return null;
  }
}

class _LookupStatus {
  const _LookupStatus({
    required this.key,
    required this.message,
    this.isLoading = false,
  });

  final Key key;
  final String message;
  final bool isLoading;
}

class _FoodResultRow extends StatelessWidget {
  const _FoodResultRow({
    required this.item,
    required this.onFoodSelected,
  });

  final FoodPickerItem item;
  final ValueChanged<FoodPickerItem>? onFoodSelected;

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
        child: Wrap(
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
      ),
      trailing: onFoodSelected == null
          ? null
          : Icon(
              Icons.chevron_right,
              color: context.colors.textSecondary,
            ),
      onTap: onFoodSelected == null ? null : () => onFoodSelected!(item),
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
