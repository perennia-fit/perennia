import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../focus/widgets/focus_visuals.dart';
import '../controllers/protocols_day_controller.dart';
import 'consistency_screen.dart';
import 'protocols_day_view.dart';
import 'protocols_lock_screen.dart';
import 'purpose_filter_row.dart';
import 'purpose_manager_screen.dart';

/// The discreet "Supplements" surface's landing screen (PROTOCOLS.md
/// §5): the `Compound` list — the User library + the OTC seed, whose built-in
/// Compounds alone arrive tagged with Purposes
/// (docs/designs/compound-purposes.md, the neutral-instrument rule) — with a
/// search field, a Purpose filter, a "+" to create a Compound, and a
/// favourites/recents shortlist. A tap on a row logs a Dose; a long-press, or
/// the row's **Edit** accessibility action, opens [CompoundEditorSheet] to edit
/// the Compound. Reached from the Home overflow menu and
/// Settings; deliberately NOT on the primary `Training | Nutrition` domain
/// toggle. Neutral capsule iconography throughout — never a syringe.
/// Tokens come through the theme, never hardcoded.
///
/// **Which day a Dose logs on (file 38).** Opened from the Protocol Day
/// view's add button, [protocolDay] is that view's selected Protocol Day, and
/// the log sheet opens on it. Opened from Library or Settings, it is null and
/// the sheet opens on today. That list is the 2-tap repeat path, and the
/// selected Protocol Day outlives the view that set it: logging on whatever
/// day was last browsed would back-date a Dose the user means to log now.
class CompoundListScreen extends ConsumerStatefulWidget {
  const CompoundListScreen({super.key, this.protocolDay});

  /// The Protocol Day the log sheet opens on, or null for today.
  final ProtocolDayDate? protocolDay;

  static const routeName = '/supplements';

  static const searchFieldKey = Key('protocols.compoundList.search');
  static const addCompoundButtonKey = Key('protocols.compoundList.add');
  static const viewDayButtonKey = Key('protocols.compoundList.viewDay');
  static const menuButtonKey = Key('protocols.compoundList.menu');
  static const purposesMenuKey = Key('protocols.compoundList.menu.purposes');
  static const emptyStateKey = Key('protocols.compoundList.empty');
  static const listKey = Key('protocols.compoundList.list');
  static const favoritesSectionHeaderKey = Key(
    'protocols.compoundList.section.favorites',
  );
  static const recentsSectionHeaderKey = Key(
    'protocols.compoundList.section.recents',
  );
  static const allSectionHeaderKey = Key('protocols.compoundList.section.all');

  static Key compoundRowKey(String id) => Key('protocols.compoundList.row-$id');

  static Key favoriteButtonKey(String id) =>
      Key('protocols.compoundList.favorite-$id');

  static Key consistencyButtonKey(String id) =>
      Key('protocols.compoundList.consistency-$id');

  @override
  ConsumerState<CompoundListScreen> createState() => _CompoundListScreenState();
}

enum _CompoundListMenuAction { purposes }

class _CompoundListScreenState extends ConsumerState<CompoundListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  /// The Purpose filter as last tapped, or null for All. [build] reads it through
  /// the active Purposes: one archived while selected shows All.
  String? _purposeFilterId;

  @override
  void initState() {
    super.initState();
    // Idempotent OTC seed load (PROTOCOLS.md §3), same as the day view: never
    // blocks the surface, safe to call repeatedly (stable ids).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        ref
            .read(protocolDayControllerProvider.notifier)
            .ensureOtcLibrarySeeded(),
      );
    });
    _searchController.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    setState(() => _query = _searchController.text.trim().toLowerCase());
  }

  @override
  void dispose() {
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final compounds =
        ref.watch(compoundListProvider).value ?? const <CompoundRecord>[];
    final recentCompoundIds =
        ref.watch(recentCompoundIdsProvider).value ?? const <String>[];

    final purposes =
        ref.watch(activePurposesProvider).value ?? const <PurposeRecord>[];
    final filterId = purposes.any((purpose) => purpose.id == _purposeFilterId)
        ? _purposeFilterId
        : null;
    final lowerPurposeNames = <String, String>{
      for (final purpose in purposes) purpose.id: purpose.name.toLowerCase(),
    };

    // Search matches the name or any active Purpose's name, and the filter one
    // Purpose — never a substance type/legality field, which the model never
    // carries.
    final matches = compounds.where((compound) {
      if (filterId != null && !compound.purposeIds.contains(filterId)) {
        return false;
      }
      return _query.isEmpty ||
          compound.name.toLowerCase().contains(_query) ||
          compound.purposeIds.any(
            (id) => lowerPurposeNames[id]?.contains(_query) ?? false,
          );
    }).toList(growable: false);
    final matchedIds = matches.map((compound) => compound.id).toSet();
    final compoundById = <String, CompoundRecord>{
      for (final compound in compounds) compound.id: compound,
    };

    // Favourites hoist to a virtual top section (mirrors the exercise catalog
    // pattern); recents is a small shortlist DERIVED from Dose history
    // (nothing stored). Both are convenience duplicates of rows
    // that also appear in the full library below.
    final favorites = matches
        .where((compound) => compound.isFavorite)
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    final recentMatches = <CompoundRecord>[
      for (final id in recentCompoundIds)
        if (matchedIds.contains(id) && compoundById[id] != null)
          compoundById[id]!,
    ];
    final all = List<CompoundRecord>.of(matches)
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: Text(l10n.navCompounds),
        actions: [
          IconButton(
            key: CompoundListScreen.viewDayButtonKey,
            tooltip: l10n.compoundListViewByDay,
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  // Also gated: if the app re-locks while this
                  // sub-screen is on top of the stack, THIS Gate instance
                  // reacts to the same shared lock state independently of the
                  // Gate below it on the Navigator stack.
                  builder: (_) => const ProtocolsLockGate(
                    child: ProtocolsDayView(),
                  ),
                ),
              );
            },
          ),
          PopupMenuButton<_CompoundListMenuAction>(
            key: CompoundListScreen.menuButtonKey,
            tooltip: l10n.compoundListMenuTooltip,
            onSelected: (_) => unawaited(_openPurposeManager()),
            itemBuilder: (_) => [
              PopupMenuItem<_CompoundListMenuAction>(
                key: CompoundListScreen.purposesMenuKey,
                value: _CompoundListMenuAction.purposes,
                child: Text(l10n.purposeManagerTitle),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: CompoundListScreen.searchFieldKey,
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.compoundListSearchHint,
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: AppRadii.cardMd,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.base),
            if (purposes.isNotEmpty) ...[
              PurposeFilterRow(
                purposes: purposes,
                selectedId: filterId,
                onSelected: (id) => setState(() => _purposeFilterId = id),
              ),
              const SizedBox(height: AppDimens.dense),
            ],
            Expanded(
              child: all.isEmpty
                  ? Center(
                      key: CompoundListScreen.emptyStateKey,
                      child: Text(
                        _query.isNotEmpty
                            ? l10n.compoundListNoMatches
                            : filterId != null
                                ? l10n.purposeFilterEmpty
                                : l10n.compoundListEmpty,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    )
                  : ListView(
                      key: CompoundListScreen.listKey,
                      children: [
                        if (favorites.isNotEmpty) ...[
                          _SectionHeader(
                            key: CompoundListScreen.favoritesSectionHeaderKey,
                            title: l10n.compoundListFavorites,
                          ),
                          for (final compound in favorites)
                            _CompoundRow(
                              compound: compound,
                              protocolDay: widget.protocolDay,
                            ),
                          const SizedBox(height: AppDimens.base),
                        ],
                        if (recentMatches.isNotEmpty) ...[
                          _SectionHeader(
                            key: CompoundListScreen.recentsSectionHeaderKey,
                            title: l10n.compoundListRecent,
                          ),
                          for (final compound in recentMatches)
                            _CompoundRow(
                              compound: compound,
                              protocolDay: widget.protocolDay,
                            ),
                          const SizedBox(height: AppDimens.base),
                        ],
                        _SectionHeader(
                          key: CompoundListScreen.allSectionHeaderKey,
                          title: l10n.compoundListAll,
                        ),
                        for (final compound in all)
                          _CompoundRow(
                            compound: compound,
                            protocolDay: widget.protocolDay,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: CompoundListScreen.addCompoundButtonKey,
        backgroundColor: colors.save,
        tooltip: l10n.compoundListAdd,
        onPressed: () => unawaited(showCompoundEditorSheet(context)),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// The Purpose manager, behind the same lock as this list: if the app locks
  /// while it is on top, its own gate reacts, as the view-by-day button's does.
  Future<void> _openPurposeManager() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ProtocolsLockGate(child: PurposeManagerScreen()),
      ),
    );
  }
}

/// Opens [CompoundEditorSheet]: edits [compound] when given, otherwise creates
/// a Compound with the name field holding [initialName] and the Purpose chips
/// holding [initialPurposeIds]. Completes with the saved Compound's id, even for
/// an edit that changed nothing, or null when the sheet was dismissed or the
/// Compound archived.
Future<String?> showCompoundEditorSheet(
  BuildContext context, {
  CompoundRecord? compound,
  String? initialName,
  List<String>? initialPurposeIds,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: ProtocolsLockSheetGuard(
        child: CompoundEditorSheet(
          compound: compound,
          initialName: initialName,
          initialPurposeIds: initialPurposeIds,
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: Text(
        title,
        style: context.textStyles.label.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

/// One Compound. A tap logs a Dose, the 2-tap repeat path. A long-press edits
/// the Compound, and the **Edit** accessibility action does the same for anyone
/// who can't long-press.
class _CompoundRow extends ConsumerWidget {
  const _CompoundRow({required this.compound, required this.protocolDay});

  final CompoundRecord compound;

  /// The Protocol Day the log sheet opens on, or null for today.
  final ProtocolDayDate? protocolDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = context.l10n;
    void edit() {
      unawaited(showCompoundEditorSheet(context, compound: compound));
    }

    final subtitleParts = <String>[
      doseUnitLabel(compound.defaultUnit),
      doseRouteLabel(compound.defaultRoute),
      if (compound.strength != null) compound.strength!.storageValue,
    ];

    return ConstrainedBox(
      key: CompoundListScreen.compoundRowKey(compound.id),
      constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
      child: Semantics(
        container: true,
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          CustomSemanticsAction(label: l10n.compoundListEditAction): edit,
        },
        child: InkWell(
          // The ≤2-tap "repeat dose" entry point (PROTOCOLS.md §5):
          // tapping the row opens the Track-tab analog, prefilled from this
          // Compound's last logged Dose — Save is the second and final tap.
          onTap: () => unawaited(_logDose(context, ref, compound)),
          onLongPress: edit,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppDimens.dense),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        compound.name,
                        style: context.textStyles.body.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        // Route/unit are always paired with text — colour is
                        // never the sole signal (DESIGN.md).
                        subtitleParts.join(' · '),
                        style: context.textStyles.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Opens the Compound's Consistency view (file 45). An
              // IconButton keeps the 48 dp target, and its tooltip is its label.
              IconButton(
                key: CompoundListScreen.consistencyButtonKey(compound.id),
                tooltip: context.l10n.consistencyButton,
                color: colors.textSecondary,
                icon: const Icon(Icons.timeline),
                onPressed: () => unawaited(_openConsistency(context)),
              ),
              IconButton(
                key: CompoundListScreen.favoriteButtonKey(compound.id),
                tooltip: compound.isFavorite
                    ? l10n.compoundListRemoveFavorite
                    : l10n.compoundListAddFavorite,
                color:
                    compound.isFavorite ? colors.record : colors.textSecondary,
                icon:
                    Icon(compound.isFavorite ? Icons.star : Icons.star_border),
                onPressed: () {
                  unawaited(
                    ref
                        .read(protocolDayControllerProvider.notifier)
                        .setFavorite(
                          compound.id,
                          isFavorite: !compound.isFavorite,
                        ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Compound's Consistency view, behind the same lock as this list:
  /// if the app locks while it is on top, its own gate reacts.
  Future<void> _openConsistency(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProtocolsLockGate(
          child: ConsistencyScreen.compound(
            compoundId: compound.id,
            compoundName: compound.name,
          ),
        ),
      ),
    );
  }

  /// Resolves the Compound's last Dose (a fast local read — no network) BEFORE
  /// opening the sheet, so it renders already prefilled with no loading state:
  /// local writes never block on the network, and neither does this read.
  Future<void> _logDose(
    BuildContext context,
    WidgetRef ref,
    CompoundRecord compound,
  ) async {
    final controller = ref.read(protocolDayControllerProvider.notifier);
    final lastDose = await controller.lastDoseFor(compound.id);
    if (!context.mounted) {
      return;
    }
    // The sheet logs on the Protocol Day this list was opened for, or today
    // when it was opened from Library or Settings, so a past day defaults to
    // 12:00 on that date and today to now (D6, file 38).
    await showLogDoseSheet(
      context,
      LogDoseSheet(
        compound: compound,
        lastDose: lastDose,
        initialDate: protocolDay,
      ),
    );
  }
}

/// The Compound form: name, default unit/route from the curated registries, an
/// optional structured strength, and the Purposes the user tags it with. It
/// NEVER classifies a Compound: there is no substance type or legality field, and
/// a Purpose only says why this user takes it (docs/designs/compound-purposes.md,
/// the neutral-instrument rule). Open it with [showCompoundEditorSheet], which
/// sits it behind [ProtocolsLockSheetGuard].
///
/// With [compound] it edits that Compound and offers **Archive**; without, it
/// creates one, with the name field holding [initialName] and the chips holding
/// [initialPurposeIds]. An empty name or a strength that doesn't parse shows
/// inline and doesn't save.
class CompoundEditorSheet extends ConsumerStatefulWidget {
  const CompoundEditorSheet({
    super.key,
    this.compound,
    this.initialName,
    this.initialPurposeIds,
  });

  /// The Compound to edit, or null to create one.
  final CompoundRecord? compound;

  /// The name a new Compound starts with. Ignored when editing.
  final String? initialName;

  /// The Purposes a new Compound starts tagged with. Ignored when editing.
  final List<String>? initialPurposeIds;

  static const nameFieldKey = Key('protocols.compoundEditor.name');
  static const unitFieldKey = Key('protocols.compoundEditor.unit');
  static const routeFieldKey = Key('protocols.compoundEditor.route');
  static const strengthFieldKey = Key('protocols.compoundEditor.strength');
  static const saveButtonKey = Key('protocols.compoundEditor.save');
  static const archiveButtonKey = Key('protocols.compoundEditor.archive');
  static const archiveConfirmButtonKey = Key(
    'protocols.compoundEditor.archiveConfirm',
  );

  static Key purposeChipKey(String id) =>
      Key('protocols.compoundEditor.purpose.$id');

  @override
  ConsumerState<CompoundEditorSheet> createState() =>
      _CompoundEditorSheetState();
}

class _CompoundEditorSheetState extends ConsumerState<CompoundEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _strengthController;
  late DoseUnit _unit;
  late DoseRoute _route;

  /// The tags in the order the user tapped them. It starts from the stored list
  /// and a chip's tap removes or appends only that chip's id, so an id with no
  /// chip here, an archived Purpose or one not synced yet, stays where it is and
  /// is saved with the rest (D2).
  late final List<String> _purposeIds;
  String? _nameError;
  String? _strengthError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final compound = widget.compound;
    _nameController = TextEditingController(
      text: compound?.name ?? widget.initialName ?? '',
    );
    _strengthController = TextEditingController(
      text: compound?.strength?.storageValue ?? '',
    );
    _unit = compound?.defaultUnit ?? DoseUnit.milligram;
    _route = compound?.defaultRoute ?? DoseRoute.oral;
    _purposeIds = List<String>.of(
      compound?.purposeIds ?? widget.initialPurposeIds ?? const <String>[],
    );
  }

  void _togglePurpose(String id) {
    setState(() {
      if (!_purposeIds.remove(id)) {
        _purposeIds.add(id);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _strengthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final purposes =
        ref.watch(activePurposesProvider).value ?? const <PurposeRecord>[];

    return SafeArea(
      // Scrolls so the sheet still fits with the keyboard up on a small phone
      // at large text.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.compound == null
                  ? l10n.compoundEditorNewTitle
                  : l10n.compoundEditorEditTitle,
              style: context.textStyles.h2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppDimens.base),
            TextField(
              key: CompoundEditorSheet.nameFieldKey,
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.compoundEditorName,
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
            ),
            const SizedBox(height: AppDimens.dense),
            TextField(
              key: CompoundEditorSheet.strengthFieldKey,
              controller: _strengthController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.compoundEditorStrength,
                errorText: _strengthError,
              ),
              onChanged: (_) {
                if (_strengthError != null) {
                  setState(() => _strengthError = null);
                }
              },
            ),
            const SizedBox(height: AppDimens.dense),
            DropdownButtonFormField<DoseUnit>(
              key: CompoundEditorSheet.unitFieldKey,
              initialValue: _unit,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.compoundEditorDefaultUnit,
              ),
              items: <DropdownMenuItem<DoseUnit>>[
                for (final unit in DoseUnit.values)
                  DropdownMenuItem<DoseUnit>(
                    value: unit,
                    child: Text(doseUnitLabel(unit)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _unit = value);
                }
              },
            ),
            const SizedBox(height: AppDimens.dense),
            DropdownButtonFormField<DoseRoute>(
              key: CompoundEditorSheet.routeFieldKey,
              initialValue: _route,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.compoundEditorDefaultRoute,
              ),
              items: <DropdownMenuItem<DoseRoute>>[
                for (final route in DoseRoute.values)
                  DropdownMenuItem<DoseRoute>(
                    value: route,
                    child: Text(doseRouteLabel(route)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _route = value);
                }
              },
            ),
            if (purposes.isNotEmpty) ...[
              const SizedBox(height: AppDimens.base),
              Text(
                l10n.compoundEditorPurposes,
                style: context.textStyles.label.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              Wrap(
                spacing: AppDimens.dense / 2,
                children: [
                  for (final purpose in purposes)
                    FocusChip(
                      key: CompoundEditorSheet.purposeChipKey(purpose.id),
                      label: purpose.name,
                      icon: null,
                      selected: _purposeIds.contains(purpose.id),
                      onSelected: (_) => _togglePurpose(purpose.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppDimens.base),
            SizedBox(
              height: AppDimens.touchTarget,
              child: FilledButton(
                key: CompoundEditorSheet.saveButtonKey,
                style: FilledButton.styleFrom(backgroundColor: colors.save),
                onPressed: _busy ? null : _save,
                child: Text(l10n.compoundEditorSave),
              ),
            ),
            if (widget.compound != null) ...[
              const SizedBox(height: AppDimens.dense),
              OutlinedButton(
                key: CompoundEditorSheet.archiveButtonKey,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  minimumSize: const Size.fromHeight(AppDimens.touchTarget),
                ),
                onPressed: _busy ? null : _archive,
                child: Text(l10n.compoundEditorArchive),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    CompoundStrength? strength;
    String? strengthError;
    try {
      strength = CompoundStrength.tryParse(_strengthController.text);
    } on FormatException {
      strengthError = l10n.compoundEditorStrengthInvalid;
    }
    final nameError = name.isEmpty ? l10n.compoundEditorNameRequired : null;
    if (nameError != null || strengthError != null) {
      setState(() {
        _nameError = nameError;
        _strengthError = strengthError;
      });
      return;
    }

    final draft = CompoundDraft(
      name: name,
      defaultUnit: _unit,
      defaultRoute: _route,
      strength: strength,
      purposeIds: _purposeIds,
    );
    final controller = ref.read(protocolDayControllerProvider.notifier);
    final compound = widget.compound;

    setState(() => _busy = true);
    try {
      final String savedId;
      if (compound == null) {
        savedId = (await controller.createCompound(draft)).compoundId;
      } else {
        await controller.editCompound(compound.id, draft);
        savedId = compound.id;
      }
      if (mounted) {
        Navigator.of(context).pop(savedId);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Confirms, naming what archiving does to the Protocols that hold this
  /// Compound, then archives it and closes the sheet (D4). The dialog is guarded
  /// too: it names the Compound, and sits above this sheet when the app locks.
  Future<void> _archive() async {
    final compound = widget.compound!;
    final controller = ref.read(protocolDayControllerProvider.notifier);

    setState(() => _busy = true);
    try {
      final protocolCount = await controller.countProtocolsWithCompound(
        compound.id,
      );
      if (!mounted) {
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => ProtocolsLockSheetGuard(
          child: _ArchiveCompoundDialog(
            compoundName: compound.name,
            protocolCount: protocolCount,
          ),
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
      await controller.archiveCompound(compound.id);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _ArchiveCompoundDialog extends StatelessWidget {
  const _ArchiveCompoundDialog({
    required this.compoundName,
    required this.protocolCount,
  });

  final String compoundName;
  final int protocolCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.compoundArchiveTitle(compoundName)),
      content: Text(
        protocolCount > 0
            ? l10n.compoundArchiveInProtocols(protocolCount, compoundName)
            : l10n.compoundArchiveUnused(compoundName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelAction),
        ),
        TextButton(
          key: CompoundEditorSheet.archiveConfirmButtonKey,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.compoundArchiveConfirm),
        ),
      ],
    );
  }
}
