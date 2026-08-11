import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../theme/theme.dart';
import '../controllers/protocol_controller.dart';
import '../controllers/protocols_day_controller.dart';
import 'effect_screen.dart';

/// The `Protocol` list (PROTOCOLS.md §1.4, §5): the Routine analog. Lists the
/// active named, time-bounded Protocols (a multi-Compound Protocol is a
/// "stack") and their member Compounds; "+" creates a new one; tapping a row
/// opens it for editing. Schedules and target outcomes
/// have landed on the form screen below; the app-bar chart icon opens the
/// `Effect` view (§4) — the payoff screen.
class ProtocolListScreen extends ConsumerWidget {
  const ProtocolListScreen({super.key});

  static const emptyStateKey = Key('protocols.list.empty');
  static const listKey = Key('protocols.list.list');
  static const createButtonKey = Key('protocols.list.create');
  static const effectButtonKey = Key('protocols.list.effect');

  static Key rowKey(String id) => Key('protocols.list.row-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final protocolsAsync = ref.watch(protocolListControllerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: const Text('Protocols'),
        actions: <Widget>[
          IconButton(
            key: ProtocolListScreen.effectButtonKey,
            tooltip: 'Effect',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => _openEffectView(context),
          ),
        ],
      ),
      body: protocolsAsync.when(
        data: (protocols) => _ProtocolListBody(protocols: protocols),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              'Could not load Protocols.',
              style: TextStyle(color: colors.textPrimary),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: ProtocolListScreen.createButtonKey,
        backgroundColor: colors.save,
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('New Protocol'),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {ProtocolRecord? protocol}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProtocolFormScreen(protocol: protocol),
      ),
    );
  }

  Future<void> _openEffectView(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EffectScreen()),
    );
  }
}

class _ProtocolListBody extends ConsumerWidget {
  const _ProtocolListBody({required this.protocols});

  final List<ProtocolSummaryRecord> protocols;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    if (protocols.isEmpty) {
      return Center(
        key: ProtocolListScreen.emptyStateKey,
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: Text(
            'No Protocols yet. Create one to group Compounds into a stack.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
      );
    }

    final memberCompoundIds =
        protocols.expand((protocol) => protocol.compoundIds);
    final compoundNameById = ref
            .watch(
              protocolMemberCompoundNamesProvider(
                CompoundNameLookupRequest(memberCompoundIds),
              ),
            )
            .value ??
        const <String, String>{};

    return ListView.separated(
      key: ProtocolListScreen.listKey,
      padding: const EdgeInsets.all(AppDimens.base),
      itemCount: protocols.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: colors.divider),
      itemBuilder: (context, index) {
        final protocol = protocols[index];
        return _ProtocolRow(
          protocol: protocol,
          compoundNameById: compoundNameById,
        );
      },
    );
  }
}

class _ProtocolRow extends ConsumerWidget {
  const _ProtocolRow({
    required this.protocol,
    required this.compoundNameById,
  });

  final ProtocolSummaryRecord protocol;
  final Map<String, String> compoundNameById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final windowLabel = protocolWindowLabel(protocol);
    final memberNames = protocol.compoundIds
        .map((compoundId) => compoundNameById[compoundId] ?? 'Compound')
        .join(', ');
    // Always paired with text — color is never the sole signal.
    final memberCountLabel = protocol.isStack
        ? '${protocol.compoundIds.length} Compounds'
        : '1 Compound';

    return InkWell(
      key: ProtocolListScreen.rowKey(protocol.id),
      onTap: () => unawaited(_openForm(context, ref)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                protocol.name,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$memberCountLabel · $windowLabel',
                style: TextStyle(color: colors.textSecondary),
              ),
              if (memberNames.isNotEmpty)
                Text(
                  memberNames,
                  style: TextStyle(color: colors.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref) async {
    final detail = await ref
        .read(protocolListControllerProvider.notifier)
        .loadProtocolDetail(protocol.id);
    if (!context.mounted || detail == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProtocolFormScreen(protocol: detail),
      ),
    );
  }
}

/// The human-facing Protocol window label (e.g. "1 Jul 2026 – ongoing").
String protocolWindowLabel(ProtocolSummaryRecord protocol) {
  final format = DateFormat.yMMMd();
  final start = format.format(protocol.startDate.toLocal());
  final end = protocol.endDate;
  return end == null
      ? '$start – ongoing'
      : '$start – ${format.format(end.toLocal())}';
}

/// The `Protocol` create/edit screen (PROTOCOLS.md §1.4, §5): the Routine
/// analog. Names a time-bounded course and associates one or more Compounds
/// (a stack), each with an OPTIONAL `Schedule` (planned dose · frequency ·
/// route) surfaced for edit right here, plus its declared target
/// outcomes (PROTOCOLS.md §1.4, §4) — which Metrics/performance to
/// correlate, seeding the later Effect view (no analysis happens here). A
/// `Protocol` is a MUTABLE PLAN — this screen never reads or writes a logged
/// `Dose`, and a Schedule is purely prescriptive: dose-response is always
/// derived from the actual logged Doses, never a Schedule. Pass [protocol]
/// to edit an existing one; omit to create a new one.
class ProtocolFormScreen extends ConsumerStatefulWidget {
  const ProtocolFormScreen({super.key, this.protocol});

  final ProtocolRecord? protocol;

  static const nameFieldKey = Key('protocols.form.name');
  static const startDateFieldKey = Key('protocols.form.startDate');
  static const endDateFieldKey = Key('protocols.form.endDate');
  static const ongoingToggleKey = Key('protocols.form.ongoing');
  static const saveButtonKey = Key('protocols.form.save');
  static const archiveButtonKey = Key('protocols.form.archive');

  static Key compoundChipKey(String id) => Key('protocols.form.compound-$id');

  /// The per-Compound "Add a Schedule" toggle (off by default — a
  /// Protocol/Compound with no Schedule is still fully valid).
  static Key scheduleToggleKey(String compoundId) =>
      Key('protocols.form.schedule.toggle-$compoundId');

  static Key scheduleAmountFieldKey(String compoundId) =>
      Key('protocols.form.schedule.amount-$compoundId');

  static Key scheduleUnitFieldKey(String compoundId) =>
      Key('protocols.form.schedule.unit-$compoundId');

  static Key scheduleFrequencyFieldKey(String compoundId) =>
      Key('protocols.form.schedule.frequency-$compoundId');

  static Key scheduleRouteFieldKey(String compoundId) =>
      Key('protocols.form.schedule.route-$compoundId');

  /// A `metric` target-outcome chip (PROTOCOLS.md §1.4, §4).
  static Key targetOutcomeMetricChipKey(String metricId) =>
      Key('protocols.form.targetOutcome.metric-$metricId');

  /// The `performance` target-outcome chip — no Metric row backs it.
  static const targetOutcomePerformanceChipKey =
      Key('protocols.form.targetOutcome.performance');

  @override
  ConsumerState<ProtocolFormScreen> createState() => _ProtocolFormScreenState();
}

/// The mutable in-progress `Schedule` form state for one member Compound:
/// kept only while the Compound's Schedule toggle is ON. Purely a
/// UI-layer staging area — nothing here is a logged `Dose`.
class _ScheduleFieldState {
  _ScheduleFieldState({
    required String amountEntered,
    required this.unit,
    required this.frequency,
    required this.route,
  }) : amountController = TextEditingController(text: amountEntered);

  final TextEditingController amountController;
  DoseUnit unit;
  ScheduleFrequency frequency;
  DoseRoute route;

  void dispose() {
    amountController.dispose();
  }
}

class _ProtocolFormScreenState extends ConsumerState<ProtocolFormScreen> {
  late final TextEditingController _nameController;
  late DateTime _startDate;
  DateTime? _endDate;
  late List<String> _compoundIds;
  String? _errorText;
  bool _saving = false;

  /// The in-progress `Schedule` form per member Compound, keyed by
  /// compound id. Absence means "no Schedule" — off by default, and a
  /// Protocol/Compound with no Schedule stays fully valid.
  final Map<String, _ScheduleFieldState> _scheduleFields =
      <String, _ScheduleFieldState>{};

  /// The in-progress declared target outcomes (PROTOCOLS.md §1.4,
  /// §4): the selected `Metric` ids + whether `performance` is selected.
  /// Empty/false by default — a Protocol MAY declare target outcomes, never
  /// must.
  final Set<String> _selectedMetricIds = <String>{};
  bool _performanceSelected = false;

  bool get _isEditing => widget.protocol != null;

  @override
  void initState() {
    super.initState();
    final protocol = widget.protocol;
    _nameController = TextEditingController(text: protocol?.name ?? '');
    _startDate = protocol?.startDate.toLocal() ?? DateTime.now();
    _endDate = protocol?.endDate?.toLocal();
    _compoundIds = protocol?.members
            .map((member) => member.compoundId)
            .toList(growable: true) ??
        <String>[];
    for (final member in protocol?.members ?? const <ProtocolMemberRecord>[]) {
      final schedule = member.schedule;
      if (schedule != null) {
        _scheduleFields[member.compoundId] = _ScheduleFieldState(
          amountEntered: schedule.doseAmountEntered,
          unit: schedule.doseUnit,
          frequency: schedule.frequency,
          route: schedule.route,
        );
      }
    }
    for (final outcome
        in protocol?.targetOutcomes ?? const <ProtocolTargetOutcomeRecord>[]) {
      switch (outcome.kind) {
        case ProtocolOutcomeKind.metric:
          final metricId = outcome.metricId;
          if (metricId != null) {
            _selectedMetricIds.add(metricId);
          }
        case ProtocolOutcomeKind.performance:
          _performanceSelected = true;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final field in _scheduleFields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compounds = ref.watch(compoundScheduleOptionListProvider).value ??
        const <CompoundScheduleOptionRecord>[];
    final metrics = ref.watch(metricOptionListProvider).value ??
        const <MetricOptionRecord>[];
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: Text(_isEditing ? 'Edit Protocol' : 'New Protocol'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: ProtocolFormScreen.nameFieldKey,
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: AppDimens.base),
            ListTile(
              key: ProtocolFormScreen.startDateFieldKey,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Start date',
                style: TextStyle(color: colors.textSecondary),
              ),
              subtitle: Text(
                dateFormat.format(_startDate),
                style: TextStyle(color: colors.textPrimary),
              ),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickStartDate,
            ),
            SwitchListTile(
              key: ProtocolFormScreen.ongoingToggleKey,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Ongoing (no end date)',
                style: TextStyle(color: colors.textPrimary),
              ),
              value: _endDate == null,
              onChanged: (ongoing) {
                setState(() => _endDate = ongoing ? null : _startDate);
              },
            ),
            if (_endDate != null)
              ListTile(
                key: ProtocolFormScreen.endDateFieldKey,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'End date',
                  style: TextStyle(color: colors.textSecondary),
                ),
                subtitle: Text(
                  dateFormat.format(_endDate!),
                  style: TextStyle(color: colors.textPrimary),
                ),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickEndDate,
              ),
            const SizedBox(height: AppDimens.base),
            Text('Compounds', style: TextStyle(color: colors.textPrimary)),
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense,
              children: [
                for (final compound in compounds)
                  FilterChip(
                    key: ProtocolFormScreen.compoundChipKey(compound.id),
                    label: Text(compound.name),
                    selected: _compoundIds.contains(compound.id),
                    onSelected: (selected) => _toggleCompound(
                      compound,
                      selected: selected,
                    ),
                  ),
              ],
            ),
            if (_compoundIds.isNotEmpty) ...[
              const SizedBox(height: AppDimens.base),
              Text(
                'Schedules (optional)',
                style: TextStyle(color: colors.textPrimary),
              ),
              const SizedBox(height: AppDimens.dense),
              for (final compoundId in _compoundIds)
                _ScheduleEditor(
                  compound: compounds.firstWhere(
                    (compound) => compound.id == compoundId,
                    orElse: () => CompoundScheduleOptionRecord(
                      id: compoundId,
                      name: 'Compound',
                      defaultUnit: DoseUnit.milligram,
                      defaultRoute: DoseRoute.oral,
                    ),
                  ),
                  field: _scheduleFields[compoundId],
                  onToggle: (enabled) => _toggleSchedule(
                    compoundId,
                    enabled: enabled,
                  ),
                  onChanged: () => setState(() {}),
                ),
            ],
            const SizedBox(height: AppDimens.base),
            Text(
              'Target outcomes (optional)',
              style: TextStyle(color: colors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              'Which Metrics or performance to correlate — seeds the later '
              'Effect view; no analysis happens here.',
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense,
              children: [
                for (final metric in metrics)
                  FilterChip(
                    key: ProtocolFormScreen.targetOutcomeMetricChipKey(
                      metric.id,
                    ),
                    label: Text(metric.name),
                    selected: _selectedMetricIds.contains(metric.id),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _selectedMetricIds.add(metric.id);
                      } else {
                        _selectedMetricIds.remove(metric.id);
                      }
                    }),
                  ),
                FilterChip(
                  key: ProtocolFormScreen.targetOutcomePerformanceChipKey,
                  label: const Text('Performance'),
                  selected: _performanceSelected,
                  onSelected: (selected) => setState(() {
                    _performanceSelected = selected;
                  }),
                ),
              ],
            ),
            if (_errorText != null) ...[
              const SizedBox(height: AppDimens.dense),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppDimens.base),
            SizedBox(
              height: AppDimens.touchTarget,
              child: FilledButton(
                key: ProtocolFormScreen.saveButtonKey,
                style: FilledButton.styleFrom(backgroundColor: colors.save),
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ),
            if (_isEditing) ...[
              const SizedBox(height: AppDimens.dense),
              OutlinedButton.icon(
                key: ProtocolFormScreen.archiveButtonKey,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  side: BorderSide(color: colors.divider),
                ),
                onPressed: _saving ? null : _archive,
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _toggleCompound(
    CompoundScheduleOptionRecord compound, {
    required bool selected,
  }) {
    setState(() {
      if (selected) {
        if (!_compoundIds.contains(compound.id)) {
          _compoundIds = <String>[..._compoundIds, compound.id];
        }
      } else {
        _compoundIds = _compoundIds.where((id) => id != compound.id).toList(
              growable: true,
            );
        // Dropping the Compound drops its in-progress Schedule form too — no
        // orphaned plan data to save (mirrors the repository's
        // membership-removal reconciliation).
        _scheduleFields.remove(compound.id)?.dispose();
      }
    });
  }

  /// Turns a member Compound's OPTIONAL `Schedule` on/off. Off by
  /// default: a Protocol/Compound with no Schedule is still fully valid.
  /// Enabling seeds sensible curated defaults from the Compound's own
  /// default unit/route.
  void _toggleSchedule(String compoundId, {required bool enabled}) {
    setState(() {
      if (enabled) {
        final compounds = ref.read(compoundScheduleOptionListProvider).value ??
            const <CompoundScheduleOptionRecord>[];
        final compound = compounds.firstWhere(
          (compound) => compound.id == compoundId,
          orElse: () => CompoundScheduleOptionRecord(
            id: compoundId,
            name: 'Compound',
            defaultUnit: DoseUnit.milligram,
            defaultRoute: DoseRoute.oral,
          ),
        );
        _scheduleFields[compoundId] = _ScheduleFieldState(
          amountEntered: '',
          unit: compound.defaultUnit,
          frequency: ScheduleFrequency.onceDaily,
          route: compound.defaultRoute,
        );
      } else {
        _scheduleFields.remove(compoundId)?.dispose();
      }
    });
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Name is required.');
      return;
    }
    if (_compoundIds.isEmpty) {
      setState(
        () => _errorText = 'A Protocol requires at least one Compound.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    final schedulesByCompoundId = <String, ScheduleDraft?>{
      for (final compoundId in _compoundIds)
        compoundId: _scheduleDraftFor(_scheduleFields[compoundId]),
    };

    final draft = ProtocolDraft(
      name: name,
      startDate: _startDate,
      endDate: _endDate,
      compoundIds: _compoundIds,
      schedulesByCompoundId: schedulesByCompoundId,
      targetOutcomes: _targetOutcomeDrafts(),
    );
    final controller = ref.read(protocolListControllerProvider.notifier);

    try {
      final protocol = widget.protocol;
      if (protocol == null) {
        await controller.createProtocol(draft);
      } else {
        await controller.editProtocol(protocol.id, draft);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = 'Could not save the Protocol: $error';
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop();
    }
  }

  Future<void> _archive() async {
    final protocol = widget.protocol;
    if (protocol == null) {
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(protocolListControllerProvider.notifier)
        .archiveProtocol(protocol.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Builds the [ScheduleDraft] for one member Compound from its in-progress
  /// form state, or null when the toggle is off (a Compound with no
  /// Schedule is fully valid).
  ScheduleDraft? _scheduleDraftFor(_ScheduleFieldState? field) {
    if (field == null) {
      return null;
    }
    return ScheduleDraft(
      doseAmountValue: double.tryParse(field.amountController.text.trim()) ?? 0,
      doseAmountEntered: field.amountController.text.trim(),
      doseUnit: field.unit,
      frequency: field.frequency,
      route: field.route,
    );
  }

  /// Builds the declared target outcomes (PROTOCOLS.md §1.4, §4)
  /// from the in-progress chip selection — empty when none are selected
  /// (fully valid; a Protocol MAY declare target outcomes, never must).
  List<ProtocolTargetOutcomeDraft> _targetOutcomeDrafts() {
    return <ProtocolTargetOutcomeDraft>[
      for (final metricId in _selectedMetricIds)
        ProtocolTargetOutcomeDraft.metric(metricId),
      if (_performanceSelected) ProtocolTargetOutcomeDraft.performance,
    ];
  }
}

/// One member Compound's optional `Schedule` editor: a toggle plus
/// (when on) the planned dose amount + unit + frequency + route fields, all
/// from the curated registries. Purely plan-layer — never reads
/// or writes a logged `Dose`.
class _ScheduleEditor extends StatelessWidget {
  const _ScheduleEditor({
    required this.compound,
    required this.field,
    required this.onToggle,
    required this.onChanged,
  });

  final CompoundScheduleOptionRecord compound;
  final _ScheduleFieldState? field;
  final ValueChanged<bool> onToggle;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final field = this.field;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.dense),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: ProtocolFormScreen.scheduleToggleKey(compound.id),
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${compound.name} Schedule',
              style: TextStyle(color: colors.textPrimary),
            ),
            subtitle: Text(
              'Optional planned dose, frequency, and route',
              style: TextStyle(color: colors.textSecondary),
            ),
            value: field != null,
            onChanged: onToggle,
          ),
          if (field != null) ...[
            TextField(
              key: ProtocolFormScreen.scheduleAmountFieldKey(compound.id),
              controller: field.amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Planned dose'),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: AppDimens.dense),
            DropdownButtonFormField<DoseUnit>(
              key: ProtocolFormScreen.scheduleUnitFieldKey(compound.id),
              initialValue: field.unit,
              decoration: const InputDecoration(labelText: 'Unit'),
              items: <DropdownMenuItem<DoseUnit>>[
                for (final unit in DoseUnit.values)
                  DropdownMenuItem<DoseUnit>(
                    value: unit,
                    child: Text(doseUnitLabel(unit)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  field.unit = value;
                  onChanged();
                }
              },
            ),
            const SizedBox(height: AppDimens.dense),
            DropdownButtonFormField<ScheduleFrequency>(
              key: ProtocolFormScreen.scheduleFrequencyFieldKey(compound.id),
              initialValue: field.frequency,
              decoration: const InputDecoration(labelText: 'Frequency'),
              items: <DropdownMenuItem<ScheduleFrequency>>[
                for (final frequency in ScheduleFrequency.values)
                  DropdownMenuItem<ScheduleFrequency>(
                    value: frequency,
                    child: Text(scheduleFrequencyLabel(frequency)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  field.frequency = value;
                  onChanged();
                }
              },
            ),
            const SizedBox(height: AppDimens.dense),
            DropdownButtonFormField<DoseRoute>(
              key: ProtocolFormScreen.scheduleRouteFieldKey(compound.id),
              initialValue: field.route,
              decoration: const InputDecoration(labelText: 'Route'),
              items: <DropdownMenuItem<DoseRoute>>[
                for (final route in DoseRoute.values)
                  DropdownMenuItem<DoseRoute>(
                    value: route,
                    child: Text(doseRouteLabel(route)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  field.route = value;
                  onChanged();
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
