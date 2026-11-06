import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/protocols_day_controller.dart';
import 'compound_list_screen.dart';
import 'protocols_lock_screen.dart';
import 'purpose_filter_row.dart';

/// Picks a Protocol's Compounds. Completes with the new selection, or null when
/// the sheet was dismissed or the app locked.
///
/// [selectedIds] are the members' Compound ids, in member order. The result
/// keeps the ones still selected in that order, then the new ones in the order
/// they were picked. An id the list doesn't hold stays in the result, so a
/// member the picker doesn't know is never dropped.
Future<List<String>?> showCompoundPickerSheet(
  BuildContext context, {
  required List<String> selectedIds,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: ProtocolsLockSheetGuard(
        child: FractionallySizedBox(
          heightFactor: _sheetHeightFactor,
          child: CompoundPickerSheet(selectedIds: selectedIds),
        ),
      ),
    ),
  );
}

/// Nearly full height, leaving a strip of the screen below visible to tap.
const double _sheetHeightFactor = 0.92;

/// The sections of the Compound picker's list. A Compound can be in all three
/// at once.
enum CompoundPickerSection { favorites, recent, all }

/// The Compound picker's content. Open it with [showCompoundPickerSheet], which
/// sits it behind [ProtocolsLockSheetGuard].
///
/// **Filtering stays within a frame at 200 Compounds.** The library and the
/// active Purposes are read once when the sheet opens, and their names
/// lowercased once. A keystroke filters that in memory into a flat item list, and
/// [ListView.builder] builds only the rows on screen. A stream or a
/// `ListView(children:)` here would be a dropped frame per keystroke.
class CompoundPickerSheet extends ConsumerStatefulWidget {
  const CompoundPickerSheet({super.key, required this.selectedIds});

  final List<String> selectedIds;

  static const searchFieldKey = Key('protocols.compoundPicker.search');
  static const doneButtonKey = Key('protocols.compoundPicker.done');
  static const createRowKey = Key('protocols.compoundPicker.create');
  static const emptyStateKey = Key('protocols.compoundPicker.empty');
  static const listKey = Key('protocols.compoundPicker.list');

  static Key sectionHeaderKey(CompoundPickerSection section) =>
      Key('protocols.compoundPicker.section.${section.name}');

  /// Includes the section: one Compound can be in Favorites, Recent and All at
  /// once, and duplicate keys in one list assert.
  static Key rowKey(CompoundPickerSection section, String id) =>
      Key('protocols.compoundPicker.row.${section.name}-$id');

  @override
  ConsumerState<CompoundPickerSheet> createState() =>
      _CompoundPickerSheetState();
}

class _CompoundPickerSheetState extends ConsumerState<CompoundPickerSheet> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  /// Every selected id, listed or not. Search and the filter never clear it.
  late final Set<String> _selected = <String>{...widget.selectedIds};

  /// Listed Compounds by id, the ids behind [_selected]'s count on Done.
  final _listedById = <String, _PickerRow>{};
  final _recentIds = <String>[];

  /// [_listedById]'s rows, A-Z the way the Compound list sorts them.
  var _sorted = <_PickerRow>[];

  /// The active Purposes, for the filter row.
  var _purposes = const <PurposeRecord>[];

  /// Each of [_purposes]' ids to its lowercased name, for search.
  var _lowerPurposeNames = const <String, String>{};

  /// The active filter, or null for All.
  String? _purposeFilterId;

  var _items = const <_PickerItem>[];
  var _loaded = false;

  /// The trimmed search as typed; the Create row keeps its case.
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Reads the library fresh on every open. Between opens nothing may listen to
  /// these providers, so Riverpod has paused them with Drift's newer rows still
  /// buffered, and `.future` would answer with the last value: a Compound created
  /// here earlier would have no row, and one archived by sync would still have
  /// one. Invalidating drops that value.
  ///
  /// Starts after this frame's build, which [initState] runs inside: invalidating
  /// tells any other listener the provider is reloading.
  Future<void> _load() async {
    await Future<void>.value();
    if (!mounted) {
      return;
    }
    ref
      ..invalidate(compoundListProvider)
      ..invalidate(recentCompoundIdsProvider)
      ..invalidate(activePurposesProvider);
    final compounds = await _readOnce(compoundListProvider.future);
    if (!mounted) {
      return;
    }
    final recentIds = await _readOnce(recentCompoundIdsProvider.future);
    if (!mounted) {
      return;
    }
    final purposes = await _readOnce(activePurposesProvider.future);
    if (!mounted) {
      return;
    }
    _purposes = purposes;
    _lowerPurposeNames = <String, String>{
      for (final purpose in purposes) purpose.id: purpose.name.toLowerCase(),
    };
    for (final compound in compounds) {
      _listedById[compound.id] = _PickerRow(
        id: compound.id,
        name: compound.name,
        unit: compound.defaultUnit,
        route: compound.defaultRoute,
        isFavorite: compound.isFavorite,
        purposeIds: compound.purposeIds,
      );
    }
    _recentIds.addAll(recentIds);
    _sortListed();
    setState(() {
      _loaded = true;
      _items = _buildItems();
    });
  }

  void _sortListed() {
    _sorted = _listedById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void _onSearchChanged() {
    final search = _searchController.text.trim();
    // The listener also fires for cursor moves, which change nothing here.
    if (search == _search) {
      return;
    }
    _search = search;
    _showItems();
  }

  void _onPurposeFilterSelected(String? id) {
    if (id == _purposeFilterId) {
      return;
    }
    _purposeFilterId = id;
    _showItems();
  }

  void _showItems() {
    setState(() => _items = _buildItems());
    // A narrower list shouldn't open at wherever the longer one was scrolled to.
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  List<_PickerItem> _buildItems() {
    if (!_loaded) {
      return const <_PickerItem>[];
    }
    final query = _search.toLowerCase();
    final filterId = _purposeFilterId;
    bool matches(_PickerRow row) => compoundMatchesFilter(
          lowerName: row.lowerName,
          purposeIds: row.purposeIds,
          lowerPurposeNames: _lowerPurposeNames,
          lowerQuery: query,
          filterId: filterId,
        );

    final sections = <(CompoundPickerSection, Iterable<_PickerRow>)>[
      (CompoundPickerSection.favorites, _sorted.where((r) => r.isFavorite)),
      (
        CompoundPickerSection.recent,
        _recentIds.map((id) => _listedById[id]).nonNulls,
      ),
      (CompoundPickerSection.all, _sorted),
    ];

    final items = <_PickerItem>[];
    for (final (section, rows) in sections) {
      final matched = rows.where(matches).toList(growable: false);
      if (matched.isEmpty) {
        continue;
      }
      items.add(_HeaderItem(section, isFirst: items.isEmpty));
      items.addAll(matched.map((row) => _RowItem(section, row)));
    }

    // "Create" is offered unless that exact name already exists: a partial
    // match isn't the Compound the user typed. This ignores the filter, because
    // an active Compound with that name exists whichever Purpose is showing.
    if (query.isNotEmpty && !_sorted.any((r) => r.lowerName == query)) {
      items.add(_CreateItem(_search));
    }
    return items;
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) {
        _selected.add(id);
      }
    });
  }

  /// Members still selected first, in member order, even one unticked and
  /// ticked again, then the rest in the order they were picked.
  List<String> _result() {
    final members = widget.selectedIds.toSet();
    return <String>[
      ...members.where(_selected.contains),
      ..._selected.where((id) => !members.contains(id)),
    ];
  }

  Future<void> _create(String name) async {
    final filterId = _purposeFilterId;
    final id = await showCompoundEditorSheet(
      context,
      initialName: name,
      initialPurposeIds: filterId == null ? null : <String>[filterId],
    );
    if (id == null || !mounted) {
      return;
    }
    final created = await _readCreated(id);
    if (!mounted) {
      return;
    }
    if (created != null && !_listedById.containsKey(id)) {
      _listedById[id] = created;
      _sortListed();
    }
    _selected.add(id);
    // Set first, so clearing the field doesn't filter twice.
    _search = '';
    _searchController.clear();
    _showItems();
  }

  /// The Compound just created. The list read in [_load] predates it, and the
  /// sheet keeps that one list (the class's docstring says why), so this reads
  /// it by id.
  Future<_PickerRow?> _readCreated(String id) async {
    final List<CompoundScheduleOptionRecord> compounds;
    try {
      compounds = await _readOnce(
        compoundsByIdsProvider(
          CompoundNameLookupRequest(<String>[id]),
        ).future,
      );
    } on StateError {
      // Leaving the tree closes the subscription, which fails a read of this
      // autoDispose provider while it is loading. The app locked and nobody is
      // waiting for this.
      if (mounted) {
        rethrow;
      }
      return null;
    }
    for (final compound in compounds) {
      if (compound.id == id) {
        return _PickerRow(
          id: compound.id,
          name: compound.name,
          unit: compound.defaultUnit,
          route: compound.defaultRoute,
          isFavorite: false,
          purposeIds: compound.purposeIds,
        );
      }
    }
    return null;
  }

  /// A provider's next value, with a subscription held until it arrives. A bare
  /// `ref.read(provider.future)` leaves the provider with no listener, and
  /// Riverpod then pauses a stream provider, so the read never completes, and
  /// disposes an autoDispose one. Nothing else listens to these providers when
  /// the sheet opens from the Protocol editor.
  Future<T> _readOnce<T>(ProviderListenable<Future<T>> provider) async {
    final subscription = ref.listenManual(provider, (_, __) {});
    try {
      return await subscription.read();
    } finally {
      subscription.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final doneCount = _selected.where(_listedById.containsKey).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppDimens.base,
            right: AppDimens.dense,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.compoundPickerTitle,
                  style: context.textStyles.h2.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                key: CompoundPickerSheet.doneButtonKey,
                style: TextButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  minimumSize: const Size(
                    AppDimens.touchTarget,
                    AppDimens.touchTarget,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(_result()),
                child: Text(
                  doneCount > 0
                      ? l10n.compoundPickerDoneCount(doneCount)
                      : l10n.compoundPickerDone,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: TextField(
            key: CompoundPickerSheet.searchFieldKey,
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.compoundListSearchHint,
              filled: true,
              fillColor: colors.surface,
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.cardMd,
                borderSide: BorderSide(color: colors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadii.cardMd,
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        if (_purposes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.base,
              0,
              AppDimens.base,
              AppDimens.dense,
            ),
            child: PurposeFilterRow(
              purposes: _purposes,
              selectedId: _purposeFilterId,
              onSelected: _onPurposeFilterSelected,
            ),
          ),
        Expanded(
          child: _loaded && _items.isEmpty
              ? Center(
                  key: CompoundPickerSheet.emptyStateKey,
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimens.base),
                    child: Text(
                      compoundFilterEmptyMessage(
                        l10n,
                        hasQuery: _search.isNotEmpty,
                        hasFilter: _purposeFilterId != null,
                      ),
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
                )
              : ListView.builder(
                  key: CompoundPickerSheet.listKey,
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: _items.length,
                  itemBuilder: _buildItem,
                ),
        ),
      ],
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    return switch (_items[index]) {
      _HeaderItem(:final section, :final isFirst) => _SectionHeader(
          key: CompoundPickerSheet.sectionHeaderKey(section),
          section: section,
          isFirst: isFirst,
          purposeName: _filterPurposeName(),
        ),
      _RowItem(:final section, :final row) => _buildRow(section, row),
      _CreateItem(:final name) => _CreateRow(
          key: CompoundPickerSheet.createRowKey,
          name: name,
          onTap: () => unawaited(_create(name)),
        ),
    };
  }

  /// The active filter's name, which heads the All compounds section.
  String? _filterPurposeName() {
    for (final purpose in _purposes) {
      if (purpose.id == _purposeFilterId) {
        return purpose.name;
      }
    }
    return null;
  }

  /// The checkbox is the primary text color, not cyan: DESIGN.md keeps cyan for
  /// one selection per screen, which is the selected filter chip. The
  /// check is the surface color because the theme's `onPrimary` is near-black,
  /// which is invisible on the light theme's near-black box.
  Widget _buildRow(CompoundPickerSection section, _PickerRow row) {
    final colors = context.colors;
    return CheckboxListTile(
      key: CompoundPickerSheet.rowKey(section, row.id),
      value: _selected.contains(row.id),
      onChanged: (_) => _toggle(row.id),
      activeColor: colors.textPrimary,
      checkColor: colors.surface,
      minTileHeight: AppDimens.touchTarget,
      title: Text(
        row.name,
        style: context.textStyles.body.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${doseUnitLabel(row.unit)} · ${doseRouteLabel(row.route)}',
        style: context.textStyles.caption.copyWith(
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// One listed Compound, with its name lowercased once so a keystroke doesn't
/// lowercase 200 names.
class _PickerRow {
  _PickerRow({
    required this.id,
    required this.name,
    required this.unit,
    required this.route,
    required this.isFavorite,
    required this.purposeIds,
  }) : lowerName = name.toLowerCase();

  final String id;
  final String name;
  final String lowerName;
  final DoseUnit unit;
  final DoseRoute route;
  final bool isFavorite;
  final List<String> purposeIds;
}

sealed class _PickerItem {
  const _PickerItem();
}

final class _HeaderItem extends _PickerItem {
  const _HeaderItem(this.section, {required this.isFirst});

  final CompoundPickerSection section;
  final bool isFirst;
}

final class _RowItem extends _PickerItem {
  const _RowItem(this.section, this.row);

  final CompoundPickerSection section;
  final _PickerRow row;
}

final class _CreateItem extends _PickerItem {
  const _CreateItem(this.name);

  final String name;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required super.key,
    required this.section,
    required this.isFirst,
    required this.purposeName,
  });

  final CompoundPickerSection section;
  final bool isFirst;

  /// The active filter's name, or null with no filter.
  final String? purposeName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppDimens.base,
        isFirst ? 0 : AppDimens.base,
        AppDimens.base,
        AppDimens.dense,
      ),
      child: Semantics(
        header: true,
        child: Text(
          switch (section) {
            CompoundPickerSection.favorites => l10n.compoundListFavorites,
            CompoundPickerSection.recent => l10n.compoundListRecent,
            CompoundPickerSection.all => purposeName ?? l10n.compoundListAll,
          },
          style: context.textStyles.label.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _CreateRow extends StatelessWidget {
  const _CreateRow({
    required super.key,
    required this.name,
    required this.onTap,
  });

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      minTileHeight: AppDimens.touchTarget,
      leading: Icon(Icons.add, color: colors.textPrimary),
      title: Text(
        context.l10n.compoundPickerCreate(name),
        style: context.textStyles.body.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }
}
