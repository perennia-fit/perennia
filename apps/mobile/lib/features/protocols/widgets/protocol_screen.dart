import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/protocols/protocol_plan_days.dart'
    show endDateForDoseCount, maxDoseCountForEndDate, minDoseCountForEndDate;
import '../../../domain/protocols/protocol_plan_validation.dart'
    show validateProtocolPeriod, validateScheduleRule;
import '../../../l10n/l10n.dart';
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
  final start = format.format(protocol.startLocalDate.toLocalDateTime());
  final end = protocol.endLocalDate;
  return end == null
      ? '$start – ongoing'
      : '$start – ${format.format(end.toLocalDateTime())}';
}

/// Which kind of Schedule Rule a Protocol Member's Schedule editor is set to
/// (CONTEXT.md `Schedule Rule`): clock times, a count of untimed doses, "as
/// needed", or no Schedule at all.
enum ProtocolScheduleRuleChoice { timed, untimed, asNeeded, none }

/// Which days a timed or untimed Schedule Rule plans on.
enum ProtocolScheduleDaysChoice { daily, weekdays, everyNDays }

/// The `Protocol` create/edit screen: names a course, sets its local-date
/// bounds and Protocol Period (an end date, an on/off cycle and Pauses), and
/// gives each Protocol Member an optional Schedule (its Schedule Rule plus the
/// planned amount, unit and route), plus the declared target outcomes that
/// seed the Effect view.
///
/// A `Protocol` is the user's own plan: this screen never reads or writes a
/// logged `Dose`. Every member's Schedule is sent on every save; the
/// repository inserts a new Schedule Version only for one that changed, so
/// the editor shows each member's `currentVersion` (the latest one, even when
/// it applies only from a future start), never an older version.
///
/// Plan values are judged before saving by the shared two-tier plan
/// validators (`validateScheduleRule`, `validateProtocolPeriod`), the same
/// module the repository and the Agent API run: hard rejects block the save
/// and show inline under the section they belong to; soft warnings show
/// inline and never block. Pass [protocol] to edit an existing one; omit it to
/// create a new one.
class ProtocolFormScreen extends ConsumerStatefulWidget {
  const ProtocolFormScreen({super.key, this.protocol});

  final ProtocolRecord? protocol;

  static const nameFieldKey = Key('protocols.form.name');
  static const startDateFieldKey = Key('protocols.form.startDate');
  static const untilToggleKey = Key('protocols.form.until');
  static const endDateFieldKey = Key('protocols.form.endDate');
  static const doseCountHelperKey = Key('protocols.form.doseCount');
  static const doseCountMemberFieldKey = Key('protocols.form.doseCount.member');
  static const doseCountFieldKey = Key('protocols.form.doseCount.count');
  static const doseCountResultKey = Key('protocols.form.doseCount.result');
  static const doseCountApplyKey = Key('protocols.form.doseCount.apply');
  static const cycleToggleKey = Key('protocols.form.cycle');
  static const cycleOnDaysFieldKey = Key('protocols.form.cycle.onDays');
  static const cycleOffDaysFieldKey = Key('protocols.form.cycle.offDays');
  static const cycleAnchorFieldKey = Key('protocols.form.cycle.anchor');
  static const addPauseKey = Key('protocols.form.pause.add');
  static const saveButtonKey = Key('protocols.form.save');
  static const archiveButtonKey = Key('protocols.form.archive');
  static const errorTextKey = Key('protocols.form.error');

  static Key compoundChipKey(String id) => Key('protocols.form.compound-$id');

  static Key pauseRowKey(int index) => Key('protocols.form.pause-$index');

  static Key removePauseKey(int index) =>
      Key('protocols.form.pause.remove-$index');

  /// One inline Protocol Period issue, by its stable check id (D7).
  static Key periodIssueKey(String rule) =>
      Key('protocols.form.period.issue-$rule');

  static Key scheduleEditorKey(String compoundId) =>
      Key('protocols.form.schedule-$compoundId');

  static Key scheduleCurrentVersionKey(String compoundId) =>
      Key('protocols.form.schedule.currentVersion-$compoundId');

  static Key scheduleRuleChipKey(
    String compoundId,
    ProtocolScheduleRuleChoice choice,
  ) =>
      Key('protocols.form.schedule.rule-$compoundId-${choice.name}');

  static Key scheduleDaysChipKey(
    String compoundId,
    ProtocolScheduleDaysChoice choice,
  ) =>
      Key('protocols.form.schedule.days-$compoundId-${choice.name}');

  /// An ISO weekday chip, 1 = Monday through 7 = Sunday.
  static Key scheduleWeekdayChipKey(String compoundId, int weekday) =>
      Key('protocols.form.schedule.weekday-$compoundId-$weekday');

  static Key scheduleEveryNFieldKey(String compoundId) =>
      Key('protocols.form.schedule.everyN-$compoundId');

  static Key scheduleEveryNAnchorKey(String compoundId) =>
      Key('protocols.form.schedule.everyNAnchor-$compoundId');

  static Key scheduleTimeKey(String compoundId, int index) =>
      Key('protocols.form.schedule.time-$compoundId-$index');

  static Key scheduleRemoveTimeKey(String compoundId, int index) =>
      Key('protocols.form.schedule.removeTime-$compoundId-$index');

  static Key scheduleAddTimeKey(String compoundId) =>
      Key('protocols.form.schedule.addTime-$compoundId');

  static Key scheduleCountFieldKey(String compoundId) =>
      Key('protocols.form.schedule.count-$compoundId');

  static Key scheduleAmountFieldKey(String compoundId) =>
      Key('protocols.form.schedule.amount-$compoundId');

  static Key scheduleUnitFieldKey(String compoundId) =>
      Key('protocols.form.schedule.unit-$compoundId');

  static Key scheduleRouteFieldKey(String compoundId) =>
      Key('protocols.form.schedule.route-$compoundId');

  /// One inline Schedule issue for a member, by its stable check id (D7).
  static Key scheduleIssueKey(String compoundId, String rule) =>
      Key('protocols.form.schedule.issue-$compoundId-$rule');

  /// A `metric` target-outcome chip.
  static Key targetOutcomeMetricChipKey(String metricId) =>
      Key('protocols.form.targetOutcome.metric-$metricId');

  /// The `performance` target-outcome chip — no Metric row backs it.
  static const targetOutcomePerformanceChipKey =
      Key('protocols.form.targetOutcome.performance');

  @override
  ConsumerState<ProtocolFormScreen> createState() => _ProtocolFormScreenState();
}

/// The time a new timed Schedule starts with, and the first suggestion when a
/// time is added to an empty list. Only a starting point: the user edits it.
const String _defaultPlannedTime = '09:00';

/// The mutable in-progress Schedule editor state for one Protocol Member.
/// Purely a UI staging area: it becomes a [ScheduleDraft] on save, and
/// nothing here is a logged `Dose`.
///
/// The editor judges the stored rule JSON ([ruleJson]) rather than a decoded
/// [ScheduleRule], because the plan types refuse to hold values validation
/// must report (an every-N of 1, a count of 0): the validator sees exactly
/// what would be stored, and the rule is decoded only once it is accepted.
class _ScheduleFieldState {
  _ScheduleFieldState({
    required this.choice,
    required this.daysChoice,
    required Iterable<int> weekdays,
    required String everyN,
    required this.everyNAnchor,
    required this.everyNAnchorIsDefault,
    required Iterable<String> times,
    required String count,
    required String amountEntered,
    required this.unit,
    required this.route,
    this.currentVersion,
  })  : weekdays = <int>{...weekdays},
        times = <String>[...times],
        everyNController = TextEditingController(text: everyN),
        countController = TextEditingController(text: count),
        amountController = TextEditingController(text: amountEntered);

  /// Seeds the editor from a member's [currentVersion] (null for a member
  /// with no Schedule Version yet, which starts at "No schedule").
  factory _ScheduleFieldState.fromVersion(
    ScheduleRecord? currentVersion, {
    required ProtocolDayDate protocolStart,
    required DoseUnit defaultUnit,
    required DoseRoute defaultRoute,
  }) {
    final rule = currentVersion?.rule;
    var choice = ProtocolScheduleRuleChoice.none;
    ScheduleDays days = const DailyScheduleDays();
    var times = const <String>[_defaultPlannedTime];
    var count = 1;
    switch (rule) {
      case TimedScheduleRule():
        choice = ProtocolScheduleRuleChoice.timed;
        days = rule.days;
        times = rule.times;
      case UntimedScheduleRule():
        choice = ProtocolScheduleRuleChoice.untimed;
        days = rule.days;
        count = rule.count;
      case AsNeededScheduleRule():
        choice = ProtocolScheduleRuleChoice.asNeeded;
      case UnscheduledScheduleRule() || null:
        choice = ProtocolScheduleRuleChoice.none;
    }

    var daysChoice = ProtocolScheduleDaysChoice.daily;
    var weekdays = const <int>[];
    var everyN = ProtocolPlanValidationLimits.minEveryNDays;
    var anchor = protocolStart;
    var anchorIsDefault = true;
    switch (days) {
      case DailyScheduleDays():
        daysChoice = ProtocolScheduleDaysChoice.daily;
      case WeekdayScheduleDays():
        daysChoice = ProtocolScheduleDaysChoice.weekdays;
        weekdays = days.weekdays;
      case EveryNDaysScheduleDays():
        daysChoice = ProtocolScheduleDaysChoice.everyNDays;
        everyN = days.n;
        anchor = days.anchor;
        anchorIsDefault = days.anchorIsDefault;
    }

    return _ScheduleFieldState(
      choice: choice,
      daysChoice: daysChoice,
      weekdays: weekdays,
      everyN: '$everyN',
      everyNAnchor: anchor,
      everyNAnchorIsDefault: anchorIsDefault,
      times: times,
      count: '$count',
      amountEntered: currentVersion?.doseAmountEntered ?? '',
      unit: currentVersion?.doseUnit ?? defaultUnit,
      route: currentVersion?.route ?? defaultRoute,
      currentVersion: currentVersion,
    );
  }

  ProtocolScheduleRuleChoice choice;
  ProtocolScheduleDaysChoice daysChoice;
  final Set<int> weekdays;
  final TextEditingController everyNController;
  ProtocolDayDate everyNAnchor;

  /// An anchor the editor set to the Protocol's start, which moves with the
  /// start until the user picks another date (D1).
  bool everyNAnchorIsDefault;
  final List<String> times;
  final TextEditingController countController;
  final TextEditingController amountController;
  DoseUnit unit;
  DoseRoute route;

  /// The version the editor was seeded from, shown so the user knows which
  /// Schedule Version they are editing.
  final ScheduleRecord? currentVersion;

  /// Only `timed` and `untimed` rules carry a planned amount, unit and route.
  bool get plansAmount =>
      choice == ProtocolScheduleRuleChoice.timed ||
      choice == ProtocolScheduleRuleChoice.untimed;

  String? get _amountEntered {
    final text = amountController.text.trim();
    return plansAmount && text.isNotEmpty ? text : null;
  }

  double? get _amountValue =>
      plansAmount ? double.tryParse(amountController.text.trim()) : null;

  /// Switches the rule kind. "As needed" and "No schedule" clear the amount,
  /// unit and route (D7 `amount_absent`: those rules carry none); a timed or
  /// untimed rule entered from one of them starts from the Compound's default
  /// unit and route, as a new Dose does.
  void choose(
    ProtocolScheduleRuleChoice next, {
    required DoseUnit defaultUnit,
    required DoseRoute defaultRoute,
  }) {
    if (next == choice) {
      return;
    }
    final plannedAmount = plansAmount;
    choice = next;
    if (!plansAmount) {
      amountController.clear();
    } else if (!plannedAmount) {
      unit = defaultUnit;
      route = defaultRoute;
    }
  }

  /// Keeps a default every-N anchor on the Protocol's start (D1).
  void startMoved(ProtocolDayDate start) {
    if (everyNAnchorIsDefault) {
      everyNAnchor = start;
    }
  }

  /// The rule JSON as it would be stored.
  Map<String, Object?> ruleJson() {
    return switch (choice) {
      ProtocolScheduleRuleChoice.asNeeded =>
        const AsNeededScheduleRule().toJson(),
      ProtocolScheduleRuleChoice.none =>
        const UnscheduledScheduleRule().toJson(),
      ProtocolScheduleRuleChoice.timed => <String, Object?>{
          'v': protocolPlanJsonVersion,
          'kind': 'timed',
          'days': _daysJson(),
          'times': List<String>.of(times),
        },
      ProtocolScheduleRuleChoice.untimed => <String, Object?>{
          'v': protocolPlanJsonVersion,
          'kind': 'untimed',
          'days': _daysJson(),
          'count': int.tryParse(countController.text.trim()),
        },
    };
  }

  Map<String, Object?> _daysJson() {
    return switch (daysChoice) {
      ProtocolScheduleDaysChoice.daily => const DailyScheduleDays().toJson(),
      ProtocolScheduleDaysChoice.weekdays => <String, Object?>{
          'kind': 'weekdays',
          'weekdays': weekdays.toList()..sort(),
        },
      ProtocolScheduleDaysChoice.everyNDays => <String, Object?>{
          'kind': 'every_n_days',
          'n': int.tryParse(everyNController.text.trim()),
          'anchor': everyNAnchor.storageValue,
          'anchor_is_default': everyNAnchorIsDefault,
        },
    };
  }

  /// Judges this Schedule with the shared plan validator (D7), exactly as the
  /// repository will on save.
  DoseValidationResult validate() {
    return validateScheduleRule(
      ruleJson(),
      amountValue: _amountValue,
      amountEntered: _amountEntered,
      unit: plansAmount ? unit.name : null,
      route: plansAmount ? route.name : null,
    );
  }

  /// The decoded rule, or null when the editor holds one the codec refuses
  /// (which [validate] reports).
  ScheduleRule? decodedRule() {
    try {
      return ScheduleRule.fromJson(ruleJson());
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// The draft to save: null for "No schedule" (the repository then records
  /// an `unscheduled` version for a member that had one), and no amount for
  /// "As needed". Call only once [validate] accepts.
  ScheduleDraft? toDraft() {
    if (choice == ProtocolScheduleRuleChoice.none) {
      return null;
    }
    final rule = decodedRule()!;
    if (!plansAmount) {
      return ScheduleDraft(rule: rule);
    }
    return ScheduleDraft(
      rule: rule,
      doseAmountValue: _amountValue,
      doseAmountEntered: _amountEntered,
      doseUnit: unit,
      route: route,
    );
  }

  void dispose() {
    everyNController.dispose();
    countController.dispose();
    amountController.dispose();
  }
}

class _ProtocolFormScreenState extends ConsumerState<ProtocolFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _cycleOnController;
  late final TextEditingController _cycleOffController;

  // Date-only: the Protocol's bounds are local dates (D2).
  late ProtocolDayDate _startDate;

  /// The inclusive end date, or null for an ongoing Protocol ("Until" off).
  ProtocolDayDate? _endDate;

  bool _cycleEnabled = false;
  late ProtocolDayDate _cycleAnchor;

  /// A cycle anchor the editor set to the start, which moves with it (D1).
  bool _cycleAnchorIsDefault = true;
  final List<ProtocolPause> _pauses = <ProtocolPause>[];

  late List<String> _compoundIds;

  /// The in-progress Schedule editor per member Compound, keyed by compound
  /// id. Every member has one; "No schedule" is a choice inside it.
  final Map<String, _ScheduleFieldState> _scheduleFields =
      <String, _ScheduleFieldState>{};

  /// The in-progress declared target outcomes: the selected `Metric` ids and
  /// whether `performance` is selected. A Protocol MAY declare them, never
  /// must.
  final Set<String> _selectedMetricIds = <String>{};
  bool _performanceSelected = false;

  /// Hard rejects show once the user has tried to save, so a half-filled
  /// Schedule doesn't open with errors; warnings show as soon as they apply.
  bool _showErrors = false;
  String? _errorText;
  bool _saving = false;

  bool get _isEditing => widget.protocol != null;

  @override
  void initState() {
    super.initState();
    final protocol = widget.protocol;
    _nameController = TextEditingController(text: protocol?.name ?? '');
    _startDate = protocol?.startLocalDate ??
        ProtocolDayDate.fromDateTime(DateTime.now());
    _endDate = protocol?.endLocalDate;

    final cycle = protocol?.period?.cycle;
    _cycleEnabled = cycle != null;
    _cycleOnController =
        TextEditingController(text: cycle == null ? '' : '${cycle.onDays}');
    _cycleOffController =
        TextEditingController(text: cycle == null ? '' : '${cycle.offDays}');
    _cycleAnchor = cycle?.anchor ?? _startDate;
    _cycleAnchorIsDefault = cycle?.anchorIsDefault ?? true;
    _pauses.addAll(protocol?.period?.pauses ?? const <ProtocolPause>[]);

    _compoundIds = protocol?.members
            .map((member) => member.compoundId)
            .toList(growable: true) ??
        <String>[];
    for (final member in protocol?.members ?? const <ProtocolMemberRecord>[]) {
      _scheduleFields[member.compoundId] = _ScheduleFieldState.fromVersion(
        member.currentVersion,
        protocolStart: _startDate,
        defaultUnit: DoseUnit.milligram,
        defaultRoute: DoseRoute.oral,
      );
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
    _cycleOnController.dispose();
    _cycleOffController.dispose();
    for (final field in _scheduleFields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final compounds = ref.watch(compoundScheduleOptionListProvider).value ??
        const <CompoundScheduleOptionRecord>[];
    final metrics = ref.watch(metricOptionListProvider).value ??
        const <MetricOptionRecord>[];
    final dateFormat = DateFormat.yMMMd();
    final periodValidation = _validatePeriod();
    final headingStyle = TextStyle(color: colors.textPrimary);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: Text(
          _isEditing
              ? l10n.protocolEditorEditTitle
              : l10n.protocolEditorNewTitle,
        ),
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
              decoration:
                  InputDecoration(labelText: l10n.protocolEditorNameLabel),
            ),
            const SizedBox(height: AppDimens.base),
            _DateTile(
              key: ProtocolFormScreen.startDateFieldKey,
              label: l10n.protocolEditorStartDateLabel,
              value: dateFormat.format(_startDate.toLocalDateTime()),
              onTap: _pickStartDate,
            ),
            const SizedBox(height: AppDimens.base),
            Text(l10n.protocolEditorPeriodHeading, style: headingStyle),
            SwitchListTile(
              key: ProtocolFormScreen.untilToggleKey,
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.protocolEditorUntilLabel,
                style: TextStyle(color: colors.textPrimary),
              ),
              subtitle: _endDate == null
                  ? Text(
                      l10n.protocolEditorOngoing,
                      style: TextStyle(color: colors.textSecondary),
                    )
                  : null,
              value: _endDate != null,
              onChanged: (until) {
                setState(() => _endDate = until ? _startDate : null);
              },
            ),
            if (_endDate != null)
              _DateTile(
                key: ProtocolFormScreen.endDateFieldKey,
                label: l10n.protocolEditorEndDateLabel,
                value: dateFormat.format(_endDate!.toLocalDateTime()),
                onTap: _pickEndDate,
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ProtocolFormScreen.doseCountHelperKey,
                style: TextButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  minimumSize: const Size(0, AppDimens.touchTarget),
                ),
                onPressed: _compoundIds.isEmpty
                    ? null
                    : () => unawaited(_openDoseCountHelper(compounds)),
                icon: const Icon(Icons.event_available_outlined),
                label: Text(l10n.protocolEditorDoseCountButton),
              ),
            ),
            SwitchListTile(
              key: ProtocolFormScreen.cycleToggleKey,
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.protocolEditorCycleLabel,
                style: TextStyle(color: colors.textPrimary),
              ),
              subtitle: Text(
                l10n.protocolEditorCycleSubtitle,
                style: TextStyle(color: colors.textSecondary),
              ),
              value: _cycleEnabled,
              onChanged: (enabled) => setState(() => _cycleEnabled = enabled),
            ),
            if (_cycleEnabled) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ProtocolFormScreen.cycleOnDaysFieldKey,
                      controller: _cycleOnController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.protocolEditorCycleOnDaysLabel,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppDimens.dense),
                  Expanded(
                    child: TextField(
                      key: ProtocolFormScreen.cycleOffDaysFieldKey,
                      controller: _cycleOffController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.protocolEditorCycleOffDaysLabel,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              _DateTile(
                key: ProtocolFormScreen.cycleAnchorFieldKey,
                label: l10n.protocolEditorCycleAnchorLabel,
                value: _anchorLabel(
                  l10n,
                  _cycleAnchor,
                  isDefault: _cycleAnchorIsDefault,
                ),
                onTap: _pickCycleAnchor,
              ),
            ],
            const SizedBox(height: AppDimens.dense),
            Text(
              l10n.protocolEditorPausesHeading,
              style: context.textStyles.label
                  .copyWith(color: colors.textSecondary),
            ),
            if (_pauses.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppDimens.dense / 3),
                child: Text(
                  l10n.protocolEditorPausesEmpty,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            for (final (index, pause) in _pauses.indexed)
              ListTile(
                key: ProtocolFormScreen.pauseRowKey(index),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  l10n.protocolEditorDateRange(
                    dateFormat.format(pause.from.toLocalDateTime()),
                    dateFormat.format(pause.to.toLocalDateTime()),
                  ),
                  style: TextStyle(color: colors.textPrimary),
                ),
                onTap: () => unawaited(_pickPause(index: index)),
                trailing: IconButton(
                  key: ProtocolFormScreen.removePauseKey(index),
                  tooltip: l10n.protocolEditorRemovePause,
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _pauses.removeAt(index)),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ProtocolFormScreen.addPauseKey,
                style: TextButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  minimumSize: const Size(0, AppDimens.touchTarget),
                ),
                onPressed: () => unawaited(_pickPause()),
                icon: const Icon(Icons.add),
                label: Text(l10n.protocolEditorAddPause),
              ),
            ),
            _PlanIssueList(
              issues: _showErrors
                  ? periodValidation.errors
                  : const <DoseValidationIssue>[],
              warnings: periodValidation.warnings,
              keyFor: ProtocolFormScreen.periodIssueKey,
            ),
            const SizedBox(height: AppDimens.base),
            Text(l10n.protocolEditorCompoundsHeading, style: headingStyle),
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
              Text(l10n.protocolEditorSchedulesHeading, style: headingStyle),
              const SizedBox(height: AppDimens.dense),
              for (final compoundId in _compoundIds)
                _ScheduleEditor(
                  key: ProtocolFormScreen.scheduleEditorKey(compoundId),
                  compound: _compoundOption(compoundId, compounds),
                  field: _fieldFor(compoundId, compounds),
                  protocolStart: _startDate,
                  showErrors: _showErrors,
                  onChanged: () => setState(() {}),
                ),
            ],
            const SizedBox(height: AppDimens.base),
            Text(l10n.protocolEditorTargetOutcomesHeading, style: headingStyle),
            const SizedBox(height: 2),
            Text(
              l10n.protocolEditorTargetOutcomesHelp,
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
                  label: Text(l10n.protocolEditorPerformance),
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
                key: ProtocolFormScreen.errorTextKey,
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
                child: Text(l10n.protocolEditorSave),
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
                label: Text(l10n.protocolEditorArchive),
              ),
            ],
          ],
        ),
      ),
    );
  }

  CompoundScheduleOptionRecord _compoundOption(
    String compoundId, [
    List<CompoundScheduleOptionRecord>? compounds,
  ]) {
    final options = compounds ??
        ref.read(compoundScheduleOptionListProvider).value ??
        const <CompoundScheduleOptionRecord>[];
    return options.firstWhere(
      (compound) => compound.id == compoundId,
      orElse: () => CompoundScheduleOptionRecord(
        id: compoundId,
        name: context.l10n.protocolEditorCompoundFallback,
        defaultUnit: DoseUnit.milligram,
        defaultRoute: DoseRoute.oral,
      ),
    );
  }

  /// The member's editor state, seeding one for a member that has none yet.
  _ScheduleFieldState _fieldFor(
    String compoundId, [
    List<CompoundScheduleOptionRecord>? compounds,
  ]) {
    return _scheduleFields.putIfAbsent(compoundId, () {
      final compound = _compoundOption(compoundId, compounds);
      return _ScheduleFieldState.fromVersion(
        _existingVersion(compoundId),
        protocolStart: _startDate,
        defaultUnit: compound.defaultUnit,
        defaultRoute: compound.defaultRoute,
      );
    });
  }

  /// The current Schedule Version of [compoundId]'s member in the Protocol
  /// being edited, so deselecting and reselecting a member restores it.
  ScheduleRecord? _existingVersion(String compoundId) {
    for (final member
        in widget.protocol?.members ?? const <ProtocolMemberRecord>[]) {
      if (member.compoundId == compoundId) {
        return member.currentVersion;
      }
    }
    return null;
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
        _fieldFor(compound.id);
      } else {
        _compoundIds = _compoundIds.where((id) => id != compound.id).toList(
              growable: true,
            );
        // Dropping the Compound drops its in-progress Schedule too: the
        // repository archives the member, which keeps its versions.
        _scheduleFields.remove(compound.id)?.dispose();
      }
    });
  }

  /// The Protocol Period JSON as it would be stored: null when there is no
  /// cycle and no Pause, as writers store it.
  Map<String, Object?>? _periodJson() {
    if (!_cycleEnabled && _pauses.isEmpty) {
      return null;
    }
    return <String, Object?>{
      'v': protocolPlanJsonVersion,
      'cycle': _cycleEnabled
          ? <String, Object?>{
              'on_days': int.tryParse(_cycleOnController.text.trim()),
              'off_days': int.tryParse(_cycleOffController.text.trim()),
              'anchor': _cycleAnchor.storageValue,
              'anchor_is_default': _cycleAnchorIsDefault,
            }
          : null,
      'pauses': <Object?>[for (final pause in _pauses) pause.toJson()],
    };
  }

  DoseValidationResult _validatePeriod() {
    return validateProtocolPeriod(
      startLocalDate: _startDate,
      endLocalDate: _endDate,
      period: _periodJson(),
    );
  }

  /// The decoded Protocol Period, or null when there is none or the editor
  /// holds one the codec refuses (which [_validatePeriod] reports).
  ProtocolPeriod? _decodedPeriod() {
    try {
      return ProtocolPeriod.fromJson(_periodJson());
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  String _anchorLabel(
    AppLocalizations l10n,
    ProtocolDayDate anchor, {
    required bool isDefault,
  }) {
    final formatted = DateFormat.yMMMd().format(anchor.toLocalDateTime());
    return isDefault ? l10n.protocolEditorAnchorIsStart(formatted) : formatted;
  }

  Future<ProtocolDayDate?> _pickDate(ProtocolDayDate initial) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.toLocalDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return null;
    }
    return ProtocolDayDate.fromDateTime(picked);
  }

  Future<void> _pickStartDate() async {
    final picked = await _pickDate(_startDate);
    if (picked == null) {
      return;
    }
    setState(() {
      _startDate = picked;
      // A default anchor moves with the start (D1); one the user set stays.
      if (_cycleAnchorIsDefault) {
        _cycleAnchor = picked;
      }
      for (final field in _scheduleFields.values) {
        field.startMoved(picked);
      }
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await _pickDate(_endDate ?? _startDate);
    if (picked == null) {
      return;
    }
    setState(() => _endDate = picked);
  }

  Future<void> _pickCycleAnchor() async {
    final picked = await _pickDate(_cycleAnchor);
    if (picked == null) {
      return;
    }
    setState(() {
      _cycleAnchor = picked;
      _cycleAnchorIsDefault = false;
    });
  }

  /// Adds a Pause, or edits the one at [index]. A Pause always has both
  /// dates, inclusive (D4).
  Future<void> _pickPause({int? index}) async {
    final existing = index == null ? null : _pauses[index];
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: existing == null
          ? null
          : DateTimeRange(
              start: existing.from.toLocalDateTime(),
              end: existing.to.toLocalDateTime(),
            ),
    );
    if (picked == null || !mounted) {
      return;
    }
    final pause = ProtocolPause(
      from: ProtocolDayDate.fromDateTime(picked.start),
      to: ProtocolDayDate.fromDateTime(picked.end),
    );
    setState(() {
      if (index == null) {
        _pauses.add(pause);
      } else {
        _pauses[index] = pause;
      }
      _pauses.sort((a, b) => a.from.compareTo(b.from));
    });
  }

  /// The "N doses" helper (D6): asks which member to count and how many
  /// doses, and fills the end date from `endDateForDoseCount`, which counts
  /// from the start under the member's rule as it stands in the editor,
  /// skipping off-cycle and paused days. It sets only the end date.
  Future<void> _openDoseCountHelper(
    List<CompoundScheduleOptionRecord> compounds,
  ) async {
    final periodJson = _periodJson();
    final period = _decodedPeriod();
    final periodUsable =
        periodJson == null || (period != null && _validatePeriod().accepted);
    final members = <_DoseCountMember>[
      for (final compoundId in _compoundIds)
        _DoseCountMember(
          compoundId: compoundId,
          name: _compoundOption(compoundId, compounds).name,
          rule: _fieldFor(compoundId, compounds).validate().accepted
              ? _fieldFor(compoundId, compounds).decodedRule()
              : null,
        ),
    ];
    final endDate = await showDialog<ProtocolDayDate>(
      context: context,
      builder: (_) => _DoseCountDialog(
        members: members,
        startLocalDate: _startDate,
        period: periodUsable ? period : null,
        periodUsable: periodUsable,
      ),
    );
    if (endDate == null || !mounted) {
      return;
    }
    setState(() => _endDate = endDate);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = l10n.protocolEditorNameRequired);
      return;
    }
    if (_compoundIds.isEmpty) {
      setState(() => _errorText = l10n.protocolEditorCompoundRequired);
      return;
    }

    final fields = <String, _ScheduleFieldState>{
      for (final compoundId in _compoundIds) compoundId: _fieldFor(compoundId),
    };
    final rejected = !_validatePeriod().accepted ||
        fields.values.any((field) => !field.validate().accepted);
    if (rejected) {
      setState(() {
        _showErrors = true;
        _errorText = l10n.protocolEditorFixIssues;
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    final draft = ProtocolDraft(
      name: name,
      startLocalDate: _startDate,
      endLocalDate: _endDate,
      period: _decodedPeriod(),
      // Reminders get their own switch in a later phase; a save keeps the
      // flag as it was.
      remindersEnabled: widget.protocol?.remindersEnabled ?? false,
      compoundIds: _compoundIds,
      schedulesByCompoundId: <String, ScheduleDraft?>{
        for (final entry in fields.entries) entry.key: entry.value.toDraft(),
      },
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
          _errorText = l10n.protocolEditorSaveFailed('$error');
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

  /// The declared target outcomes from the chip selection; empty is valid.
  List<ProtocolTargetOutcomeDraft> _targetOutcomeDrafts() {
    return <ProtocolTargetOutcomeDraft>[
      for (final metricId in _selectedMetricIds)
        ProtocolTargetOutcomeDraft.metric(metricId),
      if (_performanceSelected) ProtocolTargetOutcomeDraft.performance,
    ];
  }
}

/// A labelled date row that opens a date picker; at least 48 dp tall.
class _DateTile extends StatelessWidget {
  const _DateTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: TextStyle(color: colors.textSecondary)),
      subtitle: Text(value, style: TextStyle(color: colors.textPrimary)),
      trailing: const Icon(Icons.edit_calendar_outlined),
      onTap: onTap,
    );
  }
}

/// One Protocol Member's Schedule editor: the rule kind (at set times, any
/// time, as needed, or no schedule); for a timed or untimed rule its days
/// (every day, chosen weekdays, or every N days from an anchor), its times or
/// untimed count, and the planned amount, unit and route; then the shared
/// validator's issues for it. Purely plan-layer: never reads or writes a
/// logged `Dose`.
class _ScheduleEditor extends StatelessWidget {
  const _ScheduleEditor({
    super.key,
    required this.compound,
    required this.field,
    required this.protocolStart,
    required this.showErrors,
    required this.onChanged,
  });

  final CompoundScheduleOptionRecord compound;
  final _ScheduleFieldState field;
  final ProtocolDayDate protocolStart;
  final bool showErrors;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final compoundId = compound.id;
    final validation = field.validate();
    final currentVersion = field.currentVersion;
    final labelStyle =
        context.textStyles.label.copyWith(color: colors.textSecondary);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.protocolEditorScheduleTitle(compound.name),
            style: context.textStyles.h2.copyWith(color: colors.textPrimary),
          ),
          if (currentVersion != null)
            Text(
              l10n.protocolEditorScheduleCurrentVersion(
                DateFormat.yMMMd()
                    .format(currentVersion.effectiveFrom.toLocalDateTime()),
              ),
              key: ProtocolFormScreen.scheduleCurrentVersionKey(compoundId),
              style: TextStyle(color: colors.textSecondary),
            ),
          const SizedBox(height: AppDimens.dense / 2),
          Wrap(
            spacing: AppDimens.dense,
            runSpacing: AppDimens.dense / 2,
            children: [
              for (final choice in ProtocolScheduleRuleChoice.values)
                ChoiceChip(
                  key: ProtocolFormScreen.scheduleRuleChipKey(
                    compoundId,
                    choice,
                  ),
                  label: Text(_ruleChoiceLabel(l10n, choice)),
                  selected: field.choice == choice,
                  onSelected: (_) {
                    field.choose(
                      choice,
                      defaultUnit: compound.defaultUnit,
                      defaultRoute: compound.defaultRoute,
                    );
                    onChanged();
                  },
                ),
            ],
          ),
          if (field.plansAmount) ...[
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense / 2,
              children: [
                for (final choice in ProtocolScheduleDaysChoice.values)
                  ChoiceChip(
                    key: ProtocolFormScreen.scheduleDaysChipKey(
                      compoundId,
                      choice,
                    ),
                    label: Text(_daysChoiceLabel(l10n, choice)),
                    selected: field.daysChoice == choice,
                    onSelected: (_) {
                      field.daysChoice = choice;
                      if (choice == ProtocolScheduleDaysChoice.weekdays &&
                          field.weekdays.isEmpty) {
                        field.weekdays.add(protocolStart.isoWeekday);
                      }
                      onChanged();
                    },
                  ),
              ],
            ),
            if (field.daysChoice == ProtocolScheduleDaysChoice.weekdays) ...[
              const SizedBox(height: AppDimens.dense / 2),
              Wrap(
                spacing: AppDimens.dense / 2,
                runSpacing: AppDimens.dense / 2,
                children: [
                  for (var weekday = DateTime.monday;
                      weekday <= DateTime.sunday;
                      weekday += 1)
                    FilterChip(
                      key: ProtocolFormScreen.scheduleWeekdayChipKey(
                        compoundId,
                        weekday,
                      ),
                      label: Text(_weekdayLabel(context, weekday)),
                      selected: field.weekdays.contains(weekday),
                      onSelected: (selected) {
                        if (selected) {
                          field.weekdays.add(weekday);
                        } else {
                          field.weekdays.remove(weekday);
                        }
                        onChanged();
                      },
                    ),
                ],
              ),
            ],
            if (field.daysChoice == ProtocolScheduleDaysChoice.everyNDays) ...[
              const SizedBox(height: AppDimens.dense / 2),
              TextField(
                key: ProtocolFormScreen.scheduleEveryNFieldKey(compoundId),
                controller: field.everyNController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.protocolEditorEveryNLabel,
                ),
                onChanged: (_) => onChanged(),
              ),
              _DateTile(
                key: ProtocolFormScreen.scheduleEveryNAnchorKey(compoundId),
                label: l10n.protocolEditorEveryNAnchorLabel,
                value: _formatAnchor(
                  l10n,
                  field.everyNAnchor,
                  isDefault: field.everyNAnchorIsDefault,
                ),
                onTap: () => unawaited(_pickAnchor(context)),
              ),
            ],
            const SizedBox(height: AppDimens.dense),
            if (field.choice == ProtocolScheduleRuleChoice.timed) ...[
              Text(l10n.protocolEditorTimesHeading, style: labelStyle),
              for (final (index, time) in field.times.indexed)
                ListTile(
                  key: ProtocolFormScreen.scheduleTimeKey(compoundId, index),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.access_time, color: colors.textSecondary),
                  title: Text(
                    _formatTime(context, time),
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  onTap: () => unawaited(_pickTime(context, index: index)),
                  trailing: IconButton(
                    key: ProtocolFormScreen.scheduleRemoveTimeKey(
                      compoundId,
                      index,
                    ),
                    tooltip: l10n.protocolEditorRemoveTime(
                      _formatTime(context, time),
                    ),
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      field.times.removeAt(index);
                      onChanged();
                    },
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: ProtocolFormScreen.scheduleAddTimeKey(compoundId),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textPrimary,
                    minimumSize: const Size(0, AppDimens.touchTarget),
                  ),
                  onPressed: field.times.length >=
                          ProtocolPlanValidationLimits.maxTimesPerDay
                      ? null
                      : () => unawaited(_pickTime(context)),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.protocolEditorAddTime),
                ),
              ),
            ] else
              TextField(
                key: ProtocolFormScreen.scheduleCountFieldKey(compoundId),
                controller: field.countController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.protocolEditorUntimedCountLabel,
                ),
                onChanged: (_) => onChanged(),
              ),
            const SizedBox(height: AppDimens.dense),
            TextField(
              key: ProtocolFormScreen.scheduleAmountFieldKey(compoundId),
              controller: field.amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.protocolEditorPlannedAmountLabel,
              ),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: AppDimens.dense),
            DropdownButtonFormField<DoseUnit>(
              key: ProtocolFormScreen.scheduleUnitFieldKey(compoundId),
              initialValue: field.unit,
              decoration:
                  InputDecoration(labelText: l10n.protocolEditorUnitLabel),
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
            DropdownButtonFormField<DoseRoute>(
              key: ProtocolFormScreen.scheduleRouteFieldKey(compoundId),
              initialValue: field.route,
              decoration:
                  InputDecoration(labelText: l10n.protocolEditorRouteLabel),
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
          _PlanIssueList(
            issues:
                showErrors ? validation.errors : const <DoseValidationIssue>[],
            warnings: validation.warnings,
            keyFor: (rule) =>
                ProtocolFormScreen.scheduleIssueKey(compoundId, rule),
          ),
        ],
      ),
    );
  }

  String _formatAnchor(
    AppLocalizations l10n,
    ProtocolDayDate anchor, {
    required bool isDefault,
  }) {
    final formatted = DateFormat.yMMMd().format(anchor.toLocalDateTime());
    return isDefault ? l10n.protocolEditorAnchorIsStart(formatted) : formatted;
  }

  Future<void> _pickAnchor(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: field.everyNAnchor.toLocalDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !context.mounted) {
      return;
    }
    field
      ..everyNAnchor = ProtocolDayDate.fromDateTime(picked)
      ..everyNAnchorIsDefault = false;
    onChanged();
  }

  /// Edits the time at [index], or adds one. A new time is suggested an hour
  /// after the last one; times are kept sorted, as they are stored.
  Future<void> _pickTime(BuildContext context, {int? index}) async {
    final TimeOfDay initial;
    if (index != null) {
      initial = _timeOfDay(field.times[index]);
    } else if (field.times.isEmpty) {
      initial = _timeOfDay(_defaultPlannedTime);
    } else {
      final last = _timeOfDay(field.times.last);
      initial = TimeOfDay(hour: (last.hour + 1) % 24, minute: last.minute);
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !context.mounted) {
      return;
    }
    final value = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    if (index == null) {
      field.times.add(value);
    } else {
      field.times[index] = value;
    }
    field.times.sort();
    onChanged();
  }
}

TimeOfDay _timeOfDay(String localTime) {
  final minutes = planLocalTimeMinutes(localTime);
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

String _formatTime(BuildContext context, String localTime) {
  if (!isPlanLocalTime(localTime)) {
    return localTime;
  }
  return _timeOfDay(localTime).format(context);
}

/// The locale's short weekday name for ISO [weekday] (1 = Monday).
/// 2024-01-01 was a Monday.
String _weekdayLabel(BuildContext context, int weekday) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.E(locale).format(DateTime.utc(2024, 1, weekday));
}

String _ruleChoiceLabel(
  AppLocalizations l10n,
  ProtocolScheduleRuleChoice choice,
) {
  return switch (choice) {
    ProtocolScheduleRuleChoice.timed => l10n.protocolEditorRuleTimed,
    ProtocolScheduleRuleChoice.untimed => l10n.protocolEditorRuleUntimed,
    ProtocolScheduleRuleChoice.asNeeded => l10n.protocolEditorRuleAsNeeded,
    ProtocolScheduleRuleChoice.none => l10n.protocolEditorRuleNone,
  };
}

String _daysChoiceLabel(
  AppLocalizations l10n,
  ProtocolScheduleDaysChoice choice,
) {
  return switch (choice) {
    ProtocolScheduleDaysChoice.daily => l10n.protocolEditorDaysDaily,
    ProtocolScheduleDaysChoice.weekdays => l10n.protocolEditorDaysWeekdays,
    ProtocolScheduleDaysChoice.everyNDays => l10n.protocolEditorDaysEveryN,
  };
}

/// The localized text for one plan validation issue, by its stable check id
/// (D7). An id this screen doesn't know falls back to the validator's own
/// message.
String protocolPlanIssueText(AppLocalizations l10n, DoseValidationIssue issue) {
  return switch (issue.rule) {
    'times_format' => l10n.protocolPlanIssueTimesFormat,
    'times_count' => l10n.protocolPlanIssueTimesCount(
        ProtocolPlanValidationLimits.maxTimesPerDay,
      ),
    'times_distinct' => l10n.protocolPlanIssueTimesDistinct,
    'untimed_count' => l10n.protocolPlanIssueUntimedCount(
        ProtocolPlanValidationLimits.maxUntimedCount,
      ),
    'weekdays_valid' => l10n.protocolPlanIssueWeekdaysValid,
    'every_n_range' => l10n.protocolPlanIssueEveryNRange(
        ProtocolPlanValidationLimits.minEveryNDays,
        ProtocolPlanValidationLimits.maxEveryNDays,
      ),
    'anchor_date' => l10n.protocolPlanIssueAnchorDate,
    'amount_required' => l10n.protocolPlanIssueAmountRequired,
    'amount_absent' => l10n.protocolPlanIssueAmountAbsent,
    'cycle_lengths' => l10n.protocolPlanIssueCycleLengths(
        ProtocolPlanValidationLimits.maxCycleLengthDays,
      ),
    'bounds_order' => l10n.protocolPlanIssueBoundsOrder,
    'pause_count' =>
      l10n.protocolPlanIssuePauseCount(ProtocolPlanValidationLimits.maxPauses),
    'pause_order' => l10n.protocolPlanIssuePauseOrder,
    'pause_bounds' => l10n.protocolPlanIssuePauseBounds,
    'pause_overlap' => l10n.protocolPlanIssuePauseOverlap,
    'times_many' => l10n.protocolPlanIssueTimesMany(
        ProtocolPlanValidationLimits.warnTimesPerDay,
      ),
    _ => issue.message,
  };
}

/// The shared validator's rejects and warnings, inline under the section they
/// belong to. Each carries an icon and text, so color is never the only
/// signal; red stays reserved for destructive actions.
class _PlanIssueList extends StatelessWidget {
  const _PlanIssueList({
    required this.issues,
    required this.warnings,
    required this.keyFor,
  });

  final List<DoseValidationIssue> issues;
  final List<DoseValidationIssue> warnings;
  final Key Function(String rule) keyFor;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty && warnings.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final l10n = context.l10n;
    Widget row(DoseValidationIssue issue, {required bool warning}) {
      final color = warning ? colors.textSecondary : colors.textPrimary;
      return Padding(
        key: keyFor(issue.rule),
        padding: const EdgeInsets.only(top: AppDimens.dense / 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              warning ? Icons.warning_amber_rounded : Icons.error_outline,
              color: color,
              size: 20,
            ),
            const SizedBox(width: AppDimens.dense / 2),
            Expanded(
              child: Text(
                protocolPlanIssueText(l10n, issue),
                style: context.textStyles.body.copyWith(color: color),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(top: AppDimens.dense / 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final issue in issues) row(issue, warning: false),
            for (final issue in warnings) row(issue, warning: true),
          ],
        ),
      ),
    );
  }
}

/// One member the "N doses" helper can count: its decoded rule as it stands
/// in the editor, or null when the editor holds no valid rule for it.
class _DoseCountMember {
  const _DoseCountMember({
    required this.compoundId,
    required this.name,
    required this.rule,
  });

  final String compoundId;
  final String name;
  final ScheduleRule? rule;
}

/// The "N doses" helper dialog (D6). It previews the end date as the user
/// types, reads "Unavailable" when the rule plans no countable dose (as
/// needed, no schedule, never on an on-cycle day, or past 9999-12-31), and
/// returns the date only through its apply button.
class _DoseCountDialog extends StatefulWidget {
  const _DoseCountDialog({
    required this.members,
    required this.startLocalDate,
    required this.period,
    required this.periodUsable,
  });

  final List<_DoseCountMember> members;
  final ProtocolDayDate startLocalDate;
  final ProtocolPeriod? period;

  /// False when the editor's cycle or Pauses don't validate, so a count
  /// against them would be wrong.
  final bool periodUsable;

  @override
  State<_DoseCountDialog> createState() => _DoseCountDialogState();
}

class _DoseCountDialogState extends State<_DoseCountDialog> {
  final TextEditingController _countController = TextEditingController();
  late String _compoundId;

  @override
  void initState() {
    super.initState();
    final countable = widget.members.where((member) => member.rule != null);
    _compoundId =
        (countable.isEmpty ? widget.members : countable).first.compoundId;
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final (endDate, message) = _preview(l10n);

    return AlertDialog(
      title: Text(l10n.protocolEditorDoseCountTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: ProtocolFormScreen.doseCountMemberFieldKey,
              initialValue: _compoundId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.protocolEditorDoseCountMemberLabel,
              ),
              items: <DropdownMenuItem<String>>[
                for (final member in widget.members)
                  DropdownMenuItem<String>(
                    value: member.compoundId,
                    child: Text(member.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _compoundId = value);
                }
              },
            ),
            const SizedBox(height: AppDimens.dense),
            TextField(
              key: ProtocolFormScreen.doseCountFieldKey,
              controller: _countController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.protocolEditorDoseCountLabel,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppDimens.dense),
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                key: ProtocolFormScreen.doseCountResultKey,
                style: TextStyle(
                  color: endDate == null
                      ? colors.textSecondary
                      : colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.protocolEditorCancel),
        ),
        FilledButton(
          key: ProtocolFormScreen.doseCountApplyKey,
          onPressed:
              endDate == null ? null : () => Navigator.of(context).pop(endDate),
          child: Text(l10n.protocolEditorDoseCountApply),
        ),
      ],
    );
  }

  (ProtocolDayDate?, String) _preview(AppLocalizations l10n) {
    final text = _countController.text.trim();
    final count = int.tryParse(text);
    if (count == null ||
        count < minDoseCountForEndDate ||
        count > maxDoseCountForEndDate) {
      return (
        null,
        l10n.protocolEditorDoseCountRange(
          minDoseCountForEndDate,
          maxDoseCountForEndDate,
        ),
      );
    }
    final rule = widget.members
        .firstWhere((member) => member.compoundId == _compoundId)
        .rule;
    if (rule == null || !widget.periodUsable) {
      return (null, l10n.protocolEditorDoseCountUnavailable);
    }
    final endDate = endDateForDoseCount(
      startLocalDate: widget.startLocalDate,
      rule: rule,
      doseCount: count,
      period: widget.period,
    );
    if (endDate == null) {
      return (null, l10n.protocolEditorDoseCountUnavailable);
    }
    return (
      endDate,
      l10n.protocolEditorDoseCountResult(
        DateFormat.yMMMd().format(endDate.toLocalDateTime()),
      ),
    );
  }
}
