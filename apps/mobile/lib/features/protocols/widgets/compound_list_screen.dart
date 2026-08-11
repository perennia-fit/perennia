import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/protocols_day_controller.dart';
import 'protocols_day_view.dart';
import 'protocols_lock_screen.dart';

/// The discreet "Supplements" surface's landing screen (PROTOCOLS.md
/// §5): the `Compound` list — the User library + the neutral OTC seed
/// (PROTOCOLS.md §3) — with a search field, a "+" to create a Compound, and a
/// favourites/recents shortlist. Reached from the Home overflow menu and
/// Settings; deliberately NOT on the primary `Training | Nutrition` domain
/// toggle. Neutral capsule iconography throughout — never a syringe.
/// Tokens come through the theme, never hardcoded.
class CompoundListScreen extends ConsumerStatefulWidget {
  const CompoundListScreen({super.key});

  static const routeName = '/supplements';

  static const searchFieldKey = Key('protocols.compoundList.search');
  static const addCompoundButtonKey = Key('protocols.compoundList.add');
  static const viewDayButtonKey = Key('protocols.compoundList.viewDay');
  static const emptyStateKey = Key('protocols.compoundList.empty');
  static const listKey = Key('protocols.compoundList.list');
  static const favoritesSectionHeaderKey = Key(
    'protocols.compoundList.section.favorites',
  );
  static const recentsSectionHeaderKey = Key(
    'protocols.compoundList.section.recents',
  );
  static const allSectionHeaderKey = Key('protocols.compoundList.section.all');

  static Key compoundRowKey(String id) =>
      Key('protocols.compoundList.row-$id');

  static Key favoriteButtonKey(String id) =>
      Key('protocols.compoundList.favorite-$id');

  @override
  ConsumerState<CompoundListScreen> createState() =>
      _CompoundListScreenState();
}

class _CompoundListScreenState extends ConsumerState<CompoundListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

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

    // Search filters by name only (PROTOCOLS.md §5) — never by a substance
    // type/legality field, which the model never carries.
    final matches = _query.isEmpty
        ? compounds
        : compounds
            .where((compound) => compound.name.toLowerCase().contains(_query))
            .toList(growable: false);
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
        title: Text(l10n.navSupplements),
        actions: [
          IconButton(
            key: CompoundListScreen.viewDayButtonKey,
            tooltip: 'View by day',
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
                hintText: 'Search compounds',
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: AppRadii.cardMd,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.base),
            Expanded(
              child: all.isEmpty
                  ? Center(
                      key: CompoundListScreen.emptyStateKey,
                      child: Text(
                        _query.isEmpty
                            ? 'No compounds yet.'
                            : 'No compounds match your search.',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    )
                  : ListView(
                      key: CompoundListScreen.listKey,
                      children: [
                        if (favorites.isNotEmpty) ...[
                          _SectionHeader(
                            key: CompoundListScreen.favoritesSectionHeaderKey,
                            title: 'Favorites',
                          ),
                          for (final compound in favorites)
                            _CompoundRow(compound: compound),
                          const SizedBox(height: AppDimens.base),
                        ],
                        if (recentMatches.isNotEmpty) ...[
                          _SectionHeader(
                            key: CompoundListScreen.recentsSectionHeaderKey,
                            title: 'Recent',
                          ),
                          for (final compound in recentMatches)
                            _CompoundRow(compound: compound),
                          const SizedBox(height: AppDimens.base),
                        ],
                        _SectionHeader(
                          key: CompoundListScreen.allSectionHeaderKey,
                          title: 'All compounds',
                        ),
                        for (final compound in all)
                          _CompoundRow(compound: compound),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: CompoundListScreen.addCompoundButtonKey,
        backgroundColor: colors.save,
        tooltip: 'Add a compound',
        onPressed: () => _openCreateCompoundSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _openCreateCompoundSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: const CompoundEditorSheet(),
      ),
    );
  }
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

class _CompoundRow extends ConsumerWidget {
  const _CompoundRow({required this.compound});

  final CompoundRecord compound;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final subtitleParts = <String>[
      doseUnitLabel(compound.defaultUnit),
      doseRouteLabel(compound.defaultRoute),
      if (compound.strength != null) compound.strength!.storageValue,
    ];

    return ConstrainedBox(
      key: CompoundListScreen.compoundRowKey(compound.id),
      constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
      child: InkWell(
        // The ≤2-tap "repeat dose" entry point (PROTOCOLS.md §5):
        // tapping the row opens the Track-tab analog, prefilled from this
        // Compound's last logged Dose — Save is the second and final tap.
        onTap: () => unawaited(_logDose(context, ref, compound)),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
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
            IconButton(
              key: CompoundListScreen.favoriteButtonKey(compound.id),
              tooltip: compound.isFavorite ? 'Remove favorite' : 'Add favorite',
              color: compound.isFavorite ? colors.record : colors.textSecondary,
              icon: Icon(compound.isFavorite ? Icons.star : Icons.star_border),
              onPressed: () {
                unawaited(
                  ref.read(protocolDayControllerProvider.notifier).setFavorite(
                        compound.id,
                        isFavorite: !compound.isFavorite,
                      ),
                );
              },
            ),
          ],
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: LogDoseSheet(compound: compound, lastDose: lastDose),
      ),
    );
  }
}

/// The Compound creation form: name + default unit/route from the
/// curated registries, and an optional structured strength. NEVER carries a
/// substance type/legality field.
class CompoundEditorSheet extends ConsumerStatefulWidget {
  const CompoundEditorSheet({super.key});

  static const nameFieldKey = Key('protocols.compoundEditor.name');
  static const unitFieldKey = Key('protocols.compoundEditor.unit');
  static const routeFieldKey = Key('protocols.compoundEditor.route');
  static const strengthFieldKey = Key('protocols.compoundEditor.strength');
  static const saveButtonKey = Key('protocols.compoundEditor.save');

  @override
  ConsumerState<CompoundEditorSheet> createState() =>
      _CompoundEditorSheetState();
}

class _CompoundEditorSheetState extends ConsumerState<CompoundEditorSheet> {
  final _nameController = TextEditingController();
  final _strengthController = TextEditingController();
  DoseUnit _unit = DoseUnit.milligram;
  DoseRoute _route = DoseRoute.oral;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _strengthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New compound',
              style: context.textStyles.h2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppDimens.base),
            TextField(
              key: CompoundEditorSheet.nameFieldKey,
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: AppDimens.dense),
            TextField(
              key: CompoundEditorSheet.strengthFieldKey,
              controller: _strengthController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Strength (optional, e.g. 5 mg/capsule)',
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            DropdownButtonFormField<DoseUnit>(
              key: CompoundEditorSheet.unitFieldKey,
              initialValue: _unit,
              decoration: const InputDecoration(labelText: 'Default unit'),
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
              decoration: const InputDecoration(labelText: 'Default route'),
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
            const SizedBox(height: AppDimens.base),
            SizedBox(
              height: AppDimens.touchTarget,
              child: FilledButton(
                key: CompoundEditorSheet.saveButtonKey,
                style: FilledButton.styleFrom(backgroundColor: colors.save),
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }
    final strength = _tryParseStrength(_strengthController.text);

    setState(() => _saving = true);
    try {
      await ref.read(protocolDayControllerProvider.notifier).createCompound(
            CompoundDraft(
              name: name,
              defaultUnit: _unit,
              defaultRoute: _route,
              strength: strength,
            ),
          );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Leniently parses the optional strength field, mirroring `LogDoseSheet` —
  /// a blank/unparseable entry simply omits the strength (non-blocking).
  CompoundStrength? _tryParseStrength(String raw) {
    try {
      return CompoundStrength.tryParse(raw);
    } on FormatException {
      return null;
    }
  }
}
