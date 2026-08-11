import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../theme/theme.dart';
import '../controllers/protocol_controller.dart';
import '../controllers/protocols_day_controller.dart';
import 'compound_list_screen.dart';
import 'protocol_screen.dart';

/// The Protocol Day view (walking skeleton): a derived
/// `Protocol Day` list. Its FAB hands off to the Compound list
/// (`CompoundListScreen`) — the ≤2-tap "repeat dose" entry point —
/// rather than duplicating a picker here; logging always starts from an
/// existing `Compound`.
///
/// The PIN/biometric lock is a later M27 slice. DESIGN tokens come through the
/// theme, never hardcoded.
class ProtocolsDayView extends ConsumerStatefulWidget {
  const ProtocolsDayView({super.key});

  static const routeName = '/supplements/day';

  static const dayHeaderKey = Key('protocols.day.header');
  static const previousDayButtonKey = Key('protocols.day.previousDay');
  static const nextDayButtonKey = Key('protocols.day.nextDay');
  static const doseListKey = Key('protocols.day.doseList');
  static const emptyStateKey = Key('protocols.day.empty');
  static const logDoseButtonKey = Key('protocols.day.logDose');
  static const protocolsButtonKey = Key('protocols.day.protocols');

  static Key doseRowKey(String id) => Key('protocols.day.dose-$id');

  @override
  ConsumerState<ProtocolsDayView> createState() => _ProtocolsDayViewState();
}

class _ProtocolsDayViewState extends ConsumerState<ProtocolsDayView> {
  @override
  void initState() {
    super.initState();
    // Idempotently load the OTC seed library so the picker has neutral starter
    // Compounds on a first run (PROTOCOLS.md §3). Local-first: this never blocks
    // the logging path, and re-running is a no-op (stable ids).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        ref.read(protocolDayControllerProvider.notifier).ensureOtcLibrarySeeded(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dayState = ref.watch(protocolDayControllerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: const Text('Supplements'),
        actions: [
          IconButton(
            key: ProtocolsDayView.protocolsButtonKey,
            tooltip: 'Protocols',
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: () => _openProtocolList(context),
          ),
        ],
      ),
      body: dayState.when(
        data: (state) => _ProtocolDayBody(day: state.day),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              'Could not load the Protocol Day.',
              style: TextStyle(color: colors.textPrimary),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: ProtocolsDayView.logDoseButtonKey,
        backgroundColor: colors.save,
        onPressed: () => _openCompoundList(context),
        icon: const Icon(Icons.add),
        label: const Text('Log a Dose'),
      ),
    );
  }

  /// Logging a Dose always starts from an existing `Compound` ( moves
  /// Compound creation exclusively to `CompoundEditorSheet`) — so the
  /// Day view's FAB hands off to the Compound list, whose rows are the ≤2-tap
  /// entry point (tap a Compound → the prefilled sheet → Save). Reuses the
  /// existing discreet surface rather than duplicating a picker here.
  void _openCompoundList(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CompoundListScreen(),
      ),
    );
  }

  /// Opens the `Protocol` list (PROTOCOLS.md §1.4, §5) — the Routine
  /// analog: named, time-bounded courses grouping one or more Compounds (a
  /// stack). A secondary surface reached from the app bar, never primary
  /// navigation.
  void _openProtocolList(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ProtocolListScreen(),
      ),
    );
  }
}

class _ProtocolDayBody extends StatelessWidget {
  const _ProtocolDayBody({required this.day});

  final ProtocolDayRecord day;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProtocolDayHeader(localDate: day.localDate),
        Expanded(
          child: day.isEmpty
              ? Center(
                  key: ProtocolsDayView.emptyStateKey,
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimens.base),
                    child: Text(
                      'No doses logged for this day.',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
                )
              : ListView.separated(
                  key: ProtocolsDayView.doseListKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.base,
                  ),
                  itemCount: day.doses.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: colors.divider),
                  itemBuilder: (context, index) =>
                      _DoseRow(dose: day.doses[index]),
                ),
        ),
      ],
    );
  }
}

/// The date header: a swipe/arrow-navigable strip mirroring
/// `NutritionDayView`'s `_NutritionDayHeader` and the Training Day
/// Home's date navigation. Moves the derived `Protocol Day` — never a stored
/// day-bucket — one day at a time.
class _ProtocolDayHeader extends ConsumerWidget {
  const _ProtocolDayHeader({required this.localDate});

  final ProtocolDayDate localDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final dateLabel =
        DateFormat.yMMMMEEEEd().format(localDate.toLocalDateTime());

    return GestureDetector(
      key: ProtocolsDayView.dayHeaderKey,
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final controller =
            ref.read(protocolDayControllerProvider.notifier);
        if (velocity > 0) {
          controller.showPreviousDay();
        } else if (velocity < 0) {
          controller.showNextDay();
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Row(
          children: [
            IconButton(
              key: ProtocolsDayView.previousDayButtonKey,
              tooltip: 'Previous day',
              onPressed: () => ref
                  .read(protocolDayControllerProvider.notifier)
                  .showPreviousDay(),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                dateLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: ProtocolsDayView.nextDayButtonKey,
              tooltip: 'Next day',
              onPressed: () => ref
                  .read(protocolDayControllerProvider.notifier)
                  .showNextDay(),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose});

  final DoseRecord dose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final timeLabel = DateFormat.jm().format(dose.tookAt.toLocal());
    // Every part of the detail line reads from the Dose's OWN snapshot — the
    // amount, the route (always paired with text; color is never the sole
    // signal), the frozen Compound strength when captured (§1.1), and the
    // resolved active mass derived on read from amount x unit x strength
    // (PROTOCOLS.md §1.3, — never stored). Nothing here joins the live
    // Compound row.
    final strength = dose.compoundStrength;
    final activeMass = dose.resolvedActiveMass;
    final detail = <String>[
      dose.amountLabel,
      if (activeMass != null) '≈ ${activeMass.label}',
      if (strength != null) strength.storageValue,
      doseRouteLabel(dose.route),
      timeLabel,
    ].join(' · ');

    return ConstrainedBox(
      key: ProtocolsDayView.doseRowKey(dose.id),
      constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
      child: InkWell(
        // Tapping a Dose row opens it for edit/delete — the review
        // surface's only write entry point besides the FAB's ≤2-tap repeat
        // log.
        onTap: () => unawaited(_openDoseEditor(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dose.compoundName,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDoseEditor(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: LogDoseSheet.edit(dose: dose),
      ),
    );
  }
}

/// The Track-tab analog for logging a `Dose` against a KNOWN `Compound`
/// (PROTOCOLS.md §5): an amount stepper (`components.stepper-button`,
/// `numeral-hero` readout), unit + route chips drawn ONLY from the curated
/// registries (off-registry is impossible by construction, since
/// the chips are generated from the enums themselves), and a time defaulting
/// to now with a picker to adjust.
///
/// Always logs against an existing `Compound` — Compound creation lives
/// exclusively in `CompoundEditorSheet` — so opening this sheet for
/// a Compound and tapping Save is the ≤2-tap "repeat dose" path. [lastDose] is
/// the Compound's most recently logged `Dose` (already resolved by the
/// caller, e.g. via `ProtocolDayController.lastDoseFor`): its
/// amount/unit/route seed the draft on top of `DoseSnapshotDraft.fromCompound`
/// when present; a Compound with no prior Dose falls back to its default
/// unit/route. Local-first: `Save` confirms within one frame — no spinner, no
/// network on the logging path.
///
/// The [LogDoseSheet.edit] constructor reuses this SAME entry surface as the
/// Protocol Day review surface's tap-to-edit/delete: it seeds every
/// field straight from the tapped [DoseRecord] (never a live `Compound`
/// lookup — a Dose is self-describing, PROTOCOLS.md §1.1), preserves the
/// Dose's already-frozen local date/timezone/provenance untouched,
/// and adds a Delete action that routes through
/// `ProtocolsRepository.deleteDose` (tombstone + undo-recoverable, no
/// cascade) — never bypassing the Activity Log.
class LogDoseSheet extends ConsumerStatefulWidget {
  const LogDoseSheet({super.key, required this.compound, this.lastDose})
      : editingDose = null;

  const LogDoseSheet.edit({super.key, required DoseRecord dose})
      : compound = null,
        lastDose = null,
        editingDose = dose;

  /// The Compound this Dose logs against. Null in edit mode (a Dose reads its
  /// own frozen snapshot, never a live Compound row).
  final CompoundRecord? compound;

  /// The Compound's most recently logged (non-deleted) Dose, or null when it
  /// has never been logged — the first-time fallback to the Compound's
  /// default unit/route. Always null in edit mode.
  final DoseRecord? lastDose;

  /// The Dose being edited ('s tap-to-edit), or null when logging a
  /// new Dose against [compound].
  final DoseRecord? editingDose;

  static const amountFieldKey = Key('protocols.logDose.amount');
  static const decrementButtonKey = Key('protocols.logDose.decrement');
  static const incrementButtonKey = Key('protocols.logDose.increment');
  static const timeFieldKey = Key('protocols.logDose.time');

  /// The OPTIONAL `Protocol` tag picker (PROTOCOLS.md §1.4): tags a
  /// Dose at log time or after (this SAME sheet is the edit surface too,
  ///). Defaults to "None (ad-hoc)" — an untagged Dose is fully
  /// first-class.
  static const protocolFieldKey = Key('protocols.logDose.protocol');
  static const saveButtonKey = Key('protocols.logDose.save');
  static const deleteButtonKey = Key('protocols.logDose.delete');
  static const confirmDeleteButtonKey = Key('protocols.logDose.confirmDelete');

  static Key unitChipKey(DoseUnit unit) =>
      Key('protocols.logDose.unit-${unit.name}');

  static Key routeChipKey(DoseRoute route) =>
      Key('protocols.logDose.route-${route.name}');

  @override
  ConsumerState<LogDoseSheet> createState() => _LogDoseSheetState();
}

class _LogDoseSheetState extends ConsumerState<LogDoseSheet> {
  late final TextEditingController _amountController;
  late DoseUnit _unit;
  late DoseRoute _route;
  late DateTime _tookAt;

  /// The OPTIONAL `Protocol` tag — null means untagged/ad-hoc.
  /// Seeded from the tapped [DoseRecord] in edit mode; null when logging a
  /// fresh Dose (an ad-hoc Dose is the default, PROTOCOLS.md §1.4).
  String? _protocolId;

  /// The tagged Protocol's frozen name from the [DoseRecord]'s OWN snapshot
  /// (self-description, §1.1) — the fallback label if the Protocol has since
  /// been archived and dropped from the active picker list.
  String? _protocolName;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final seed = _seedDraft();
    _amountController = TextEditingController(text: seed.amountEntered);
    _unit = seed.unit;
    _route = seed.route;
    _tookAt = _seedTookAt();
    _protocolId = widget.editingDose?.protocolId;
    _protocolName = widget.editingDose?.protocolName;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  /// In edit mode, the draft reads straight from the tapped [DoseRecord] — its
  /// OWN frozen snapshot (compound id/name/strength, timezone, local date,
  /// provenance) carries over untouched; only amount/unit/route/time are
  /// editable. Otherwise `DoseSnapshotDraft.fromCompound` is the
  /// seed (the Compound's default unit/route + a placeholder amount); the
  /// last Dose's amount/unit/route overlay it when present (prefill-from-last,
  /// PROTOCOLS.md §5). A Compound with no prior Dose keeps the Compound's
  /// defaults (first-time fallback).
  DoseSnapshotDraft _seedDraft() {
    final editingDose = widget.editingDose;
    if (editingDose != null) {
      return DoseSnapshotDraft(
        compoundId: editingDose.compoundId,
        compoundName: editingDose.compoundName,
        compoundStrength: editingDose.compoundStrength,
        amountValue: editingDose.amountValue,
        amountEntered: editingDose.amountEntered,
        unit: editingDose.unit,
        route: editingDose.route,
        tookAt: editingDose.tookAt,
        timezone: editingDose.timezone,
        localDate: editingDose.localDate,
        provenance: editingDose.provenance,
      );
    }
    final compound = widget.compound!;
    final lastDose = widget.lastDose;
    return DoseSnapshotDraft.fromCompound(
      compound: compound,
      amountValue: lastDose?.amountValue ?? 1,
      amountEntered: lastDose?.amountEntered ?? '1',
      unit: lastDose?.unit ?? compound.defaultUnit,
      route: lastDose?.route ?? compound.defaultRoute,
      tookAt: DateTime.now(),
    );
  }

  /// The dose instant always defaults to NOW when logging a new Dose — the
  /// moment actually being logged — never a stale absolute timestamp copied
  /// from history. When a last Dose exists its LOCAL time-of-day (the
  /// Compound's usual dosing time) prefills onto today's date, which is still
  /// "now" enough to save untouched while remaining adjustable via the time
  /// picker. In edit mode the instant seeds from the Dose being edited
  /// (its own date, not "today") so an untouched Save cannot silently move it.
  DateTime _seedTookAt() {
    final editingDose = widget.editingDose;
    if (editingDose != null) {
      return editingDose.tookAt.toLocal();
    }
    final now = DateTime.now();
    final lastDose = widget.lastDose;
    if (lastDose == null) {
      return now;
    }
    final lastLocal = lastDose.tookAt.toLocal();
    return DateTime(
        now.year, now.month, now.day, lastLocal.hour, lastLocal.minute);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final editingDose = widget.editingDose;
    final title = widget.compound?.name ?? editingDose!.compoundName;
    final protocolOptions = ref.watch(protocolOptionListProvider).value ??
        const <ProtocolOptionRecord>[];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: context.textStyles.h1
                        .copyWith(color: colors.textPrimary),
                  ),
                ),
                if (editingDose != null)
                  IconButton(
                    key: LogDoseSheet.deleteButtonKey,
                    tooltip: 'Delete dose',
                    onPressed: _saving ? null : _confirmDelete,
                    icon: Icon(Icons.delete_outline, color: colors.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.base),
            _AmountStepper(
              controller: _amountController,
              unit: _unit,
              onChanged: () => setState(() {}),
              onDecrement: () => _stepAmount(-_stepForUnit(_unit)),
              onIncrement: () => _stepAmount(_stepForUnit(_unit)),
            ),
            const SizedBox(height: AppDimens.base),
            Text(
              'Unit',
              style: context.textStyles.label.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense,
              children: [
                for (final unit in DoseUnit.values)
                  ChoiceChip(
                    key: LogDoseSheet.unitChipKey(unit),
                    label: Text(doseUnitLabel(unit)),
                    selected: _unit == unit,
                    onSelected: (_) => setState(() => _unit = unit),
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.base),
            Text(
              'Route',
              style: context.textStyles.label.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense,
              children: [
                for (final route in DoseRoute.values)
                  ChoiceChip(
                    key: LogDoseSheet.routeChipKey(route),
                    label: Text(doseRouteLabel(route)),
                    selected: _route == route,
                    onSelected: (_) => setState(() => _route = route),
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.base),
            InkWell(
              key: LogDoseSheet.timeFieldKey,
              borderRadius: AppRadii.cardMd,
              onTap: _pickTime,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppDimens.touchTarget,
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time, color: colors.textSecondary),
                    const SizedBox(width: AppDimens.dense),
                    Expanded(
                      child: Text(
                        'Time',
                        style: context.textStyles.body.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      TimeOfDay.fromDateTime(_tookAt).format(context),
                      style: context.textStyles.body.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimens.base),
            DropdownButtonFormField<String?>(
              key: LogDoseSheet.protocolFieldKey,
              initialValue: _protocolId,
              decoration: const InputDecoration(labelText: 'Protocol'),
              items: _protocolDropdownItems(protocolOptions),
              onChanged: (value) {
                setState(() {
                  _protocolId = value;
                  _protocolName = value == null
                      ? null
                      : _protocolNameFor(value, protocolOptions);
                });
              },
            ),
            const SizedBox(height: AppDimens.base),
            SizedBox(
              height: AppDimens.touchTarget,
              child: FilledButton(
                key: LogDoseSheet.saveButtonKey,
                style: FilledButton.styleFrom(backgroundColor: colors.save),
                onPressed: _saving || _amountOrNull() == null ? null : _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_tookAt),
    );
    if (picked != null && mounted) {
      setState(() {
        _tookAt = DateTime(
          _tookAt.year,
          _tookAt.month,
          _tookAt.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  void _stepAmount(double delta) {
    final current = _amountOrNull() ?? 0;
    final next = current + delta;
    final clamped = next <= 0 ? _stepForUnit(_unit) : next;
    _amountController.text = _formatAmount(clamped);
    setState(() {});
  }

  double? _amountOrNull() {
    final value = double.tryParse(_amountController.text.trim());
    if (value == null || !value.isFinite || value <= 0) {
      return null;
    }
    return value;
  }

  /// A sensible ± step per unit: fine-grained for potent mass/activity units,
  /// whole units for countable dosage forms.
  double _stepForUnit(DoseUnit unit) {
    return switch (unit) {
      DoseUnit.milligram => 5,
      DoseUnit.microgram => 25,
      DoseUnit.gram => 0.5,
      DoseUnit.internationalUnit => 100,
      DoseUnit.milliliter => 0.5,
      DoseUnit.tablet ||
      DoseUnit.capsule ||
      DoseUnit.drop ||
      DoseUnit.spray ||
      DoseUnit.puff ||
      DoseUnit.patch ||
      DoseUnit.unit =>
        1,
    };
  }

  /// The `Protocol` picker items: "None (ad-hoc)" first, then each
  /// active Protocol. If the currently-tagged Protocol has since been
  /// archived (dropped from [protocols]), a synthetic entry using the Dose's
  /// OWN frozen [_protocolName] snapshot is appended so the dropdown never
  /// breaks on a value it doesn't recognize (self-description holds, §1.1).
  List<DropdownMenuItem<String?>> _protocolDropdownItems(
    List<ProtocolOptionRecord> protocols,
  ) {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('None (ad-hoc)'),
      ),
      for (final protocol in protocols)
        DropdownMenuItem<String?>(
          value: protocol.id,
          child: Text(protocol.name),
        ),
    ];
    final protocolId = _protocolId;
    if (protocolId != null &&
        !protocols.any((protocol) => protocol.id == protocolId)) {
      items.add(
        DropdownMenuItem<String?>(
          value: protocolId,
          child: Text(_protocolName ?? 'Protocol'),
        ),
      );
    }
    return items;
  }

  String _protocolNameFor(
    String protocolId,
    List<ProtocolOptionRecord> protocols,
  ) {
    for (final protocol in protocols) {
      if (protocol.id == protocolId) {
        return protocol.name;
      }
    }
    return _protocolName ?? 'Protocol';
  }

  /// Resolves the currently-selected [ProtocolOptionRecord] to snapshot into a
  /// FRESH Dose's tag — null when untagged. Reads the provider
  /// directly rather than a stale `build()` local, since this runs from the
  /// Save action.
  ProtocolOptionRecord? _selectedProtocol() {
    final protocolId = _protocolId;
    if (protocolId == null) {
      return null;
    }
    final protocols = ref.read(protocolOptionListProvider).value ??
        const <ProtocolOptionRecord>[];
    return protocols.firstWhere(
      (protocol) => protocol.id == protocolId,
      orElse: () => ProtocolOptionRecord(
        id: protocolId,
        name: _protocolName ?? 'Protocol',
      ),
    );
  }

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    final fixed = value.toStringAsFixed(3);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// Logs (or, in edit mode, edits) the Dose through the repository's
  /// Activity Log write path (`ProtocolsRepository.logDose`/`editDose`,
  /// unchanged) — never reimplemented here. The write is a local SQLite
  /// transaction: it confirms within one frame, no spinner, no network on the
  /// logging path.
  Future<void> _save() async {
    final amountValue = _amountOrNull();
    if (amountValue == null) {
      return;
    }
    final amountEntered = _amountController.text.trim();

    setState(() => _saving = true);
    final controller = ref.read(protocolDayControllerProvider.notifier);
    try {
      final editingDose = widget.editingDose;
      if (editingDose != null) {
        // The Dose's own frozen compound identity/timezone/local
        // date/provenance carry over untouched — an edit only ever changes
        // amount/unit/route/time-of-day, and NEVER re-derives the local date
        // from the device's current timezone.
        await controller.editDose(
          editingDose.id,
          DoseSnapshotDraft(
            compoundId: editingDose.compoundId,
            compoundName: editingDose.compoundName,
            compoundStrength: editingDose.compoundStrength,
            amountValue: amountValue,
            amountEntered: amountEntered,
            unit: _unit,
            route: _route,
            tookAt: _tookAt,
            timezone: editingDose.timezone,
            localDate: editingDose.localDate,
            provenance: editingDose.provenance,
            protocolId: _protocolId,
            protocolName: _protocolName,
          ),
        );
      } else {
        await controller.logDose(
          DoseSnapshotDraft.fromCompound(
            compound: widget.compound!,
            amountValue: amountValue,
            amountEntered: amountEntered,
            unit: _unit,
            route: _route,
            tookAt: _tookAt,
            protocol: _selectedProtocol(),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }

    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  /// Confirms before deleting a Dose: the delete is a tombstone,
  /// undo-recoverable through the Activity Log, and never cascades to the
  /// Compound — but it is still a destructive-feeling action from the review
  /// surface, so a confirmation dialog guards the tap (mirrors the Meal Type
  /// archive confirmation in `NutritionDayView`).
  Future<void> _confirmDelete() async {
    final editingDose = widget.editingDose;
    if (editingDose == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Delete ${editingDose.compoundName} dose?'),
            content: const Text(
              'This removes the dose from your log. It can still be '
              'recovered from the Activity Log.',
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: LogDoseSheet.confirmDeleteButtonKey,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(protocolDayControllerProvider.notifier)
          .deleteDose(editingDose.id);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }

    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }
}

class _AmountStepper extends StatelessWidget {
  const _AmountStepper({
    required this.controller,
    required this.unit,
    required this.onChanged,
    required this.onDecrement,
    required this.onIncrement,
  });

  final TextEditingController controller;
  final DoseUnit unit;
  final VoidCallback onChanged;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.outlined(
          key: LogDoseSheet.decrementButtonKey,
          tooltip: 'Decrease amount',
          onPressed: onDecrement,
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: AppDimens.dense),
        Expanded(
          child: TextField(
            key: LogDoseSheet.amountFieldKey,
            controller: controller,
            textAlign: TextAlign.center,
            style: context.textStyles.numeralHero,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              suffixText: doseUnitLabel(unit),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: AppDimens.dense),
        IconButton.filled(
          key: LogDoseSheet.incrementButtonKey,
          tooltip: 'Increase amount',
          onPressed: onIncrement,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
