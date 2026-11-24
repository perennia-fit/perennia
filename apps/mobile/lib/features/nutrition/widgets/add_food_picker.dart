import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/open_food_facts_repository.dart';
import '../../../domain/nutrition/food_aisle.dart';
import '../../../domain/nutrition/nutrition.dart';
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

/// The add-food picker, embedded in the Meal screen
/// (docs/designs/meal-logging.md §6; docs/designs/unified-food-search.md;
/// docs/designs/food-aisles.md § The picker).
///
/// The picker never writes on its own: the caller owns every write, through
/// [onFoodSelected] and [onQuickEntry], so the Meal screen's in-flight guard
/// and its switch to the saved Meal cover them. Its results area is an
/// [Expanded], so the caller must give it a bounded height.
class AddFoodPicker extends ConsumerStatefulWidget {
  const AddFoodPicker({
    super.key,
    this.onFoodSelected,
    required this.onQuickEntry,
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

  /// The "Browse" label over the Aisle rows.
  static const browseLabelKey = Key('nutrition.addFood.browseLabel');

  /// The Aisle view's header: its back button and its title.
  static const aisleBackKey = Key('nutrition.addFood.aisleBack');
  static const aisleTitleKey = Key('nutrition.addFood.aisleTitle');

  /// The line after a blank-query Aisle list cut at [aisleBrowseLimit].
  static const aisleMoreLineKey = Key('nutrition.addFood.aisleMoreLine');

  /// The line for a typed query with no match in the open Aisle.
  static const aisleNoMatchKey = Key('nutrition.addFood.aisleNoMatch');
  static const searchDebounceDuration =
      AddFoodPickerController.searchDebounceDuration;

  /// Opens a picked Food. Null makes the picker browse-only: its results
  /// don't open.
  final ValueChanged<FoodPickerItem>? onFoodSelected;

  /// Makes the Quick add write for the draft the Quick Entry dialog returns.
  final Future<void> Function(QuickFoodEntryDraft draft) onQuickEntry;

  static Key filterChipKey(AddFoodPickerFilter filter) {
    return Key('nutrition.addFood.filter-${filter.name}');
  }

  static Key resultKey(FoodPickerItem item) {
    return Key('nutrition.addFood.result-${item.foodSource.name}-${item.id}');
  }

  static Key aisleRowKey(FoodAisle aisle) {
    return Key('nutrition.addFood.aisle-${aisle.name}');
  }

  @override
  ConsumerState<AddFoodPicker> createState() => _AddFoodPickerState();
}

class _AddFoodPickerState extends ConsumerState<AddFoodPicker> {
  /// The search field's text. Opening or closing an Aisle clears it, so the
  /// field never shows a query the controller has dropped.
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  AddFoodPickerController get _controller =>
      ref.read(addFoodPickerControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addFoodPickerControllerProvider);
    final aisle = state.value?.aisle;

    // With an Aisle open, a back closes the Aisle and the Meal screen stays:
    // the system back and the Meal screen's app-bar back both pop through
    // Navigator.maybePop, which this blocks while canPop is false. The next
    // back, with no Aisle open, leaves the Meal screen as before
    // (docs/designs/food-aisles.md § The picker, CUJ 3).
    return PopScope(
      canPop: aisle == null,
      onPopInvokedWithResult: (didPop, _) {
        final open = ref.read(addFoodPickerControllerProvider).value?.aisle;
        if (!didPop && open != null) {
          unawaited(_closeAisle());
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Embedded under the Meal screen's header, so no title of its own.
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton.outlined(
                  key: AddFoodPicker.scanBarcodeButtonKey,
                  tooltip: 'Scan barcode',
                  onPressed: () {
                    unawaited(_scanBarcode());
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                ),
                const SizedBox(width: AppDimens.dense),
                FilledButton.icon(
                  key: AddFoodPicker.quickAddButtonKey,
                  onPressed: () {
                    unawaited(_quickAdd());
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Quick add'),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.base),
            TextField(
              key: AddFoodPicker.searchFieldKey,
              controller: _searchController,
              decoration: InputDecoration(
                hintText:
                    aisle == null ? 'Search foods' : 'Search ${aisle.label}',
                prefixIcon: const Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (value) {
                unawaited(_controller.setQuery(value));
              },
              onSubmitted: (value) {
                unawaited(_submit(value));
              },
            ),
            const SizedBox(height: AppDimens.base),
            if (aisle != null)
              _AisleHeader(
                aisle: aisle,
                onBack: () {
                  unawaited(_closeAisle());
                },
              )
            else
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
                  unawaited(_quickAdd());
                },
                onUseUsda: () {
                  unawaited(_controller.selectFilter(AddFoodPickerFilter.usda));
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
                  onOpen: widget.onFoodSelected == null ? null : _open,
                  onSearchOnline: () {
                    unawaited(_submit(value.query));
                  },
                  onOpenAisle: (aisle) {
                    unawaited(_openAisle(aisle));
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
      ),
    );
  }

  /// Every Aisle opening goes through here: the field is cleared first, so
  /// it matches the empty query the controller opens the Aisle with.
  Future<void> _openAisle(FoodAisle aisle) {
    _searchController.clear();
    return _controller.openAisle(aisle);
  }

  /// Every Aisle closing (the header's back button, a back the PopScope
  /// blocks, a scanned barcode) goes through here, clearing the field first.
  Future<void> _closeAisle() {
    _searchController.clear();
    return _controller.closeAisle();
  }

  Future<void> _quickAdd() async {
    final draft = await showDialog<QuickFoodEntryDraft>(
      context: context,
      builder: (context) => const QuickEntryDialog(),
    );
    if (draft == null) {
      return;
    }
    await widget.onQuickEntry(draft);
  }

  Future<void> _scanBarcode() async {
    final barcode = await ref.read(barcodeScannerProvider).scan(context);
    if (!mounted || barcode == null || barcode.trim().isEmpty) {
      return;
    }
    // A barcode names one product wherever it is, and inside an Aisle the
    // controller makes no barcode lookup or live request. So the Aisle
    // closes first, and the lookup then runs as it does with no Aisle open,
    // a live request included (docs/designs/food-aisles.md § The picker).
    if (ref.read(addFoodPickerControllerProvider).value?.aisle != null) {
      await _closeAisle();
      if (!mounted) {
        return;
      }
    }
    await _openFound(_controller.lookupBarcode(barcode));
  }

  /// The keyboard's search action and the online search row. A typed barcode
  /// that is found opens the log-portion screen through the scan's path.
  Future<void> _submit(String query) {
    return _openFound(_controller.submitQuery(query));
  }

  /// Opens the item a scan or a submit found, if the picker is still shown.
  Future<void> _openFound(Future<FoodPickerItem?> lookup) async {
    final food = await lookup;
    if (!mounted || food == null) {
      return;
    }
    _open(food);
  }

  /// Every opened item goes through the controller first, which stores a live
  /// copy in the background.
  void _open(FoodPickerItem item) {
    final onSelected = widget.onFoodSelected;
    if (onSelected == null) {
      return;
    }
    _controller.openItem(item);
    onSelected(item);
  }
}

/// Replaces the filter chips while an Aisle is open: a back button that
/// closes the Aisle, then the Aisle's label as the view's title.
class _AisleHeader extends StatelessWidget {
  const _AisleHeader({required this.aisle, required this.onBack});

  final FoodAisle aisle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: AddFoodPicker.aisleBackKey,
          tooltip: 'Back',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: AppDimens.dense),
        // Expanded, so a long label wraps at large text instead of
        // overflowing.
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              aisle.label,
              key: AddFoodPicker.aisleTitleKey,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ],
    );
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
/// (docs/designs/unified-food-search.md § The picker, top to bottom), or the
/// open Aisle's list (docs/designs/food-aisles.md § The picker).
class _FoodResults extends StatelessWidget {
  const _FoodResults({
    required this.state,
    required this.onOpen,
    required this.onSearchOnline,
    required this.onOpenAisle,
  });

  final AddFoodPickerState state;
  final ValueChanged<FoodPickerItem>? onOpen;
  final VoidCallback onSearchOnline;
  final ValueChanged<FoodAisle> onOpenAisle;

  @override
  Widget build(BuildContext context) {
    final blank = isBlankFoodQuery(state.query);
    final aisle = state.aisle;
    final entries = <_Entry>[
      ...switch (state.filter) {
        // An Aisle's rows only: the bundle line and the online slot are for
        // the filters, and live results carry no Aisle.
        _ when aisle != null => [
            ..._rows(state.results),
            if (blank && state.results.length == aisleBrowseLimit)
              (_) => const _StatusLine(
                    key: AddFoodPicker.aisleMoreLineKey,
                    text: 'Showing the $aisleBrowseLimit most scanned. '
                        'Search to find more.',
                  )
            else if (!blank && state.results.isEmpty)
              (_) => _StatusLine(
                    key: AddFoodPicker.aisleNoMatchKey,
                    text: 'No foods match in ${aisle.label}.',
                  ),
          ],
        AddFoodPickerFilter.all when blank => [
            if (state.results.isEmpty)
              (_) => const _StatusLine(
                    key: AddFoodPicker.emptyStateKey,
                    text: 'Search by name or brand, or scan a barcode.',
                  )
            else ...[
              (context) => Semantics(
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
              ..._rows(state.results),
            ],
            ..._browse(),
          ],
        AddFoodPickerFilter.all => [
            ..._rowsOrNoMatch(),
            ..._bundleLine(),
            ..._online(),
          ],
        AddFoodPickerFilter.yours when blank && state.results.isEmpty => [
            (_) => const _StatusLine(
                  key: AddFoodPicker.emptyStateKey,
                  text: 'Foods you log or create appear here.',
                ),
          ],
        AddFoodPickerFilter.yours ||
        AddFoodPickerFilter.usda =>
          _rowsOrNoMatch(),
        AddFoodPickerFilter.openFoodFacts => [
            ..._bundleLine(),
            if (blank)
              (_) => const _StatusLine(
                    key: AddFoodPicker.emptyQueryLineKey,
                    text: 'Search Open Food Facts by product name, brand or '
                        'barcode.',
                  ),
            if (blank)
              ..._browse()
            else ...[
              ..._rows(state.results),
              ..._online(),
            ],
          ],
      },
      // One rule: any Open Food Facts row in the list, from the device or a
      // live search, puts the compact notice after the last list item.
      if (state.results.any(_isOpenFoodFacts) ||
          state.onlineResults.any(_isOpenFoodFacts))
        (_) => const Padding(
              key: AddFoodPicker.attributionFooterKey,
              padding: EdgeInsets.only(top: AppDimens.base),
              child: OpenFoodFactsAttributionNotice(compact: true),
            ),
    ];

    // Built on demand: Your foods alone can hold 200 rows.
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => entries[index](context),
    );
  }

  static bool _isOpenFoodFacts(FoodPickerItem item) {
    return item.foodSource == FoodSource.openFoodFacts;
  }

  List<_Entry> _rows(List<FoodPickerItem> items) {
    return [
      for (final item in items) ...[
        (_) => _FoodResultRow(item: item, onOpen: onOpen),
        (context) => Divider(height: 1, color: context.colors.divider),
      ],
    ];
  }

  /// The Browse section: a label, then one row per Aisle in order. Only on
  /// a blank query (the callers' cases), and only once the bundle, which
  /// holds the Aisles, is ready.
  List<_Entry> _browse() {
    if (state.bundleStatus != BundleStatus.ready) {
      return const <_Entry>[];
    }
    return [
      (context) => Semantics(
            header: true,
            child: Padding(
              key: AddFoodPicker.browseLabelKey,
              padding: const EdgeInsets.only(
                top: AppDimens.base,
                bottom: AppDimens.dense,
              ),
              child: Text(
                'Browse',
                style: context.textStyles.label.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
      for (final (index, aisle) in FoodAisle.values.indexed) ...[
        if (index > 0)
          (context) => Divider(height: 1, color: context.colors.divider),
        (_) => _AisleRow(aisle: aisle, onOpen: onOpenAisle),
      ],
    ];
  }

  List<_Entry> _rowsOrNoMatch() {
    return [
      ..._rows(state.results),
      if (state.results.isEmpty)
        (_) => const _StatusLine(
              key: AddFoodPicker.noMatchLineKey,
              text: _noMatchLine,
            ),
    ];
  }

  List<_Entry> _bundleLine() {
    final line = switch (state.bundleStatus) {
      BundleStatus.installing => 'Preparing the offline food list.',
      BundleStatus.failed => 'The offline food list could not be prepared. '
          'It will try again next time the app opens.',
      BundleStatus.unknown || BundleStatus.ready => null,
    };
    return [
      if (line != null)
        (_) => _StatusLine(key: AddFoodPicker.bundleStatusLineKey, text: line),
    ];
  }

  /// The online slot, then the live-only results as one group: a live search
  /// returns one page, so the group is built whole.
  List<_Entry> _online() {
    return [
      (_) => _OnlineSlot(state: state, onSearchOnline: onSearchOnline),
      if (state.onlineResults.isNotEmpty)
        (context) => Column(
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
                for (final entry in _rows(state.onlineResults)) entry(context),
              ],
            ),
    ];
  }
}

/// One Aisle in the Browse section. No colour or icon per Aisle: category
/// colours belong to exercise Categories, and the label names the Aisle.
class _AisleRow extends StatelessWidget {
  const _AisleRow({required this.aisle, required this.onOpen});

  final FoodAisle aisle;
  final ValueChanged<FoodAisle> onOpen;

  @override
  Widget build(BuildContext context) {
    void onTap() => onOpen(aisle);
    return Semantics(
      button: true,
      label: '${aisle.label}, aisle',
      excludeSemantics: true,
      onTap: onTap,
      child: ListTile(
        key: AddFoodPicker.aisleRowKey(aisle),
        minTileHeight: AppDimens.touchTarget,
        contentPadding: EdgeInsets.zero,
        title: Text(aisle.label, style: context.textStyles.body),
        trailing: Icon(
          Icons.chevron_right,
          color: context.colors.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }
}

/// One list item of [_FoodResults], built when it scrolls into view.
typedef _Entry = Widget Function(BuildContext context);

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
          padding: const EdgeInsets.only(top: AppDimens.dense / 2),
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
                runSpacing: AppDimens.dense / 2,
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
