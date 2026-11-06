import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/protocols/protocol_plan_days.dart'
    show
        endDateForDoseCount,
        maxDoseCountForEndDate,
        minDoseCountForEndDate,
        protocolCycleFromStart,
        scheduleDaysFromStart;
import '../../../domain/protocols/protocol_plan_validation.dart'
    show validateProtocolPeriod, validateScheduleRule;
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../training/services/timer_background_scheduler.dart';
import '../controllers/protocol_controller.dart';
import '../controllers/protocols_day_controller.dart';
import '../services/protocol_reminder_scheduler.dart';
import 'compound_picker_sheet.dart';
import 'consistency_screen.dart';
import 'effect_screen.dart';
import 'plan_labels.dart';
import 'protocol_reminders_settings.dart';
import 'protocols_lock_screen.dart';

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
        builder: (_) => ProtocolsLockGate(
          child: ProtocolFormScreen(protocol: protocol),
        ),
      ),
    );
  }

  Future<void> _openEffectView(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ProtocolsLockGate(child: EffectScreen()),
      ),
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
        return ProtocolRow(
          protocol: protocol,
          compoundNameById: compoundNameById,
        );
      },
    );
  }
}

/// One Protocol: its name, how many Compounds over what window, and their
/// names; tapping opens it for editing. Used by the Protocols list and by
/// Today's Protocols tab, which passes no name map and lets the row look
/// its own Compounds up.
class ProtocolRow extends ConsumerWidget {
  const ProtocolRow({
    super.key,
    required this.protocol,
    this.compoundNameById,
  });

  final ProtocolSummaryRecord protocol;
  final Map<String, String>? compoundNameById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final windowLabel = protocolWindowLabel(protocol);
    final compoundNameById = this.compoundNameById ??
        ref
            .watch(
              protocolMemberCompoundNamesProvider(
                CompoundNameLookupRequest(protocol.compoundIds),
              ),
            )
            .value ??
        const <String, String>{};
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
        builder: (_) => ProtocolsLockGate(
          child: ProtocolFormScreen(protocol: detail),
        ),
      ),
    );
  }
}

/// Opens a new Protocol's form, gated like every Protocols route.
Future<void> openProtocolForm(BuildContext context, WidgetRef ref) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const ProtocolsLockGate(child: ProtocolFormScreen()),
    ),
  );
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
  static const deleteButtonKey = Key('protocols.form.delete');
  static const confirmArchiveButtonKey = Key('protocols.form.confirmArchive');
  static const confirmDeleteButtonKey = Key('protocols.form.confirmDelete');
  static const errorTextKey = Key('protocols.form.error');
  static const consistencyButtonKey = Key('protocols.form.consistency');
  static const remindersSwitchKey = Key('protocols.form.reminders');
  static const remindersDeniedKey = Key('protocols.form.reminders.denied');
  static const remindersOpenSettingsKey =
      Key('protocols.form.reminders.openSettings');
  static const remindersHorizonKey = Key('protocols.form.reminders.horizon');

  static const addCompoundsKey = Key('protocols.form.addCompounds');

  /// The When section's row: its summary, which expands the period controls.
  static const periodSummaryKey = Key('protocols.form.periodSummary');
  static const discardKeepEditingKey =
      Key('protocols.form.discard.keepEditing');
  static const discardConfirmKey = Key('protocols.form.discard.confirm');

  static Key memberRowKey(String id) => Key('protocols.form.member-$id');

  static Key removeMemberKey(String id) =>
      Key('protocols.form.member.remove-$id');

  /// The line under a member's row when its Schedule has hard rejects.
  static Key memberFixKey(String id) => Key('protocols.form.member.fix-$id');

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

/// A member's Schedule sheet stops short of full height, leaving a strip of the
/// form to tap to close it.
const double _scheduleSheetMaxHeightFactor = 0.92;

/// The form's values as they would be saved, compared to tell whether leaving
/// loses anything (D5). `canPop` compares one of these on every build.
///
/// Every field is a string or a bool, because a record compares its fields with
/// `==`: a List or Set here compares by identity and would always read dirty.
/// Values the form holds but wouldn't save are left out, so turning something on
/// and off again reads clean: a cycle's fields while it is off, and in
/// [_ScheduleFieldState.snapshotValue] whatever its rule doesn't carry.
typedef _FormSnapshot = ({
  String name,
  String start,
  String? end,
  String cycle,
  String pauses,
  String members,
  bool reminders,
  String metricIds,
  bool performance,
});

/// What a Schedule summary reads (D5), detached from the editor's controllers.
/// A value the editor can't parse yet is null, and the summary leaves it out or
/// names the kind of days instead.
class ScheduleSummaryInput {
  const ScheduleSummaryInput({
    required this.choice,
    this.daysChoice = ProtocolScheduleDaysChoice.daily,
    this.weekdays = const <int>[],
    this.everyN,
    this.times = const <String>[],
    this.countPerDay,
    this.amount,
    this.unit,
  });

  final ProtocolScheduleRuleChoice choice;
  final ProtocolScheduleDaysChoice daysChoice;

  /// ISO weekdays, 1 = Monday, in the order to show them.
  final List<int> weekdays;
  final int? everyN;

  /// Stored `HH:MM` local times.
  final List<String> times;
  final int? countPerDay;

  /// The planned amount as entered, or null when there is none. The form never
  /// holds one for "As needed" (D7 `amount_absent`).
  final String? amount;
  final DoseUnit? unit;
}

/// One member's Schedule as the single line its row shows (D5), such as "Every
/// day · 9:00 AM · 5 g". An empty amount on a rule that plans one reads "Add an
/// amount". Times use the device's format, so callers pass
/// `MediaQuery.alwaysUse24HourFormatOf(context)`.
String protocolScheduleSummary(
  AppLocalizations l10n,
  ScheduleSummaryInput input, {
  required MaterialLocalizations material,
  required String localeName,
  bool alwaysUse24HourFormat = false,
}) {
  final amount = input.amount;
  final amountText = amount == null || amount.isEmpty
      ? null
      : _plannedAmountText(l10n, amount, input.unit);
  final daysText = switch (input.daysChoice) {
    ProtocolScheduleDaysChoice.daily => l10n.protocolEditorDaysDaily,
    ProtocolScheduleDaysChoice.weekdays => input.weekdays.isEmpty
        ? l10n.protocolEditorDaysWeekdays
        : input.weekdays
            .map((weekday) => _shortWeekdayName(localeName, weekday))
            .join(', '),
    ProtocolScheduleDaysChoice.everyNDays => switch (input.everyN) {
        final n? => l10n.protocolScheduleSummaryEveryNDays(n),
        null => l10n.protocolEditorDaysEveryN,
      },
  };
  final count = input.countPerDay;
  final parts = switch (input.choice) {
    ProtocolScheduleRuleChoice.none => <String>[l10n.protocolEditorRuleNone],
    ProtocolScheduleRuleChoice.asNeeded => <String>[
        l10n.protocolEditorRuleAsNeeded,
        if (amountText != null) amountText,
      ],
    ProtocolScheduleRuleChoice.timed => <String>[
        daysText,
        if (input.times.isNotEmpty)
          input.times
              .map(
                (time) => isPlanLocalTime(time)
                    ? material.formatTimeOfDay(
                        planTimeOfDay(time),
                        alwaysUse24HourFormat: alwaysUse24HourFormat,
                      )
                    : time,
              )
              .join(', '),
        amountText ?? l10n.protocolScheduleSummaryAddAmount,
      ],
    ProtocolScheduleRuleChoice.untimed => <String>[
        daysText,
        if (count != null) l10n.protocolScheduleSummaryPerDay(count),
        amountText ?? l10n.protocolScheduleSummaryAddAmount,
      ],
  };
  return parts.join(' · ');
}

/// A planned amount with its unit. [doseUnitLabel] is singular, so the countable
/// units take their ICU plurals here; an amount that doesn't parse reads as
/// plural. Mass and volume units don't change.
String _plannedAmountText(
  AppLocalizations l10n,
  String amount,
  DoseUnit? unit,
) {
  final count = double.tryParse(amount) ?? 0;
  return switch (unit) {
    null => amount,
    DoseUnit.tablet => l10n.protocolScheduleSummaryTablets(count, amount),
    DoseUnit.capsule => l10n.protocolScheduleSummaryCapsules(count, amount),
    DoseUnit.drop => l10n.protocolScheduleSummaryDrops(count, amount),
    DoseUnit.spray => l10n.protocolScheduleSummarySprays(count, amount),
    DoseUnit.puff => l10n.protocolScheduleSummaryPuffs(count, amount),
    DoseUnit.patch => l10n.protocolScheduleSummaryPatches(count, amount),
    DoseUnit.unit => l10n.protocolScheduleSummaryUnits(count, amount),
    DoseUnit.milligram ||
    DoseUnit.microgram ||
    DoseUnit.gram ||
    DoseUnit.internationalUnit ||
    DoseUnit.milliliter =>
      '$amount ${doseUnitLabel(unit)}',
  };
}

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
    // A default anchor is the Protocol's start, whatever date it stores
    // (D4): the core plans from the start, so the editor shows it.
    days = scheduleDaysFromStart(days, protocolStart);
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

  /// Seeds the editor for a Compound added in this editor session (D5): At set
  /// times, Every day, at the default time, in the Compound's default unit and
  /// route. Its amount is the Compound's latest Dose's, when that Dose used the
  /// default unit; otherwise it is empty, and the row asks for one.
  factory _ScheduleFieldState.forNewMember(
    CompoundScheduleOptionRecord compound,
    ({double amount, DoseUnit unit})? lastDose, {
    required ProtocolDayDate protocolStart,
  }) {
    return _ScheduleFieldState(
      choice: ProtocolScheduleRuleChoice.timed,
      daysChoice: ProtocolScheduleDaysChoice.daily,
      weekdays: const <int>[],
      everyN: '${ProtocolPlanValidationLimits.minEveryNDays}',
      everyNAnchor: protocolStart,
      everyNAnchorIsDefault: true,
      times: const <String>[_defaultPlannedTime],
      count: '1',
      amountEntered: lastDose != null && lastDose.unit == compound.defaultUnit
          ? '${lastDose.amount}'.replaceFirst(RegExp(r'\.0$'), '')
          : '',
      unit: compound.defaultUnit,
      route: compound.defaultRoute,
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

  /// A rule that plans an amount with none entered yet.
  bool get needsAmount => plansAmount && _amountEntered == null;

  /// This editor's values as its row's summary reads them.
  ScheduleSummaryInput summaryInput() {
    return ScheduleSummaryInput(
      choice: choice,
      daysChoice: daysChoice,
      weekdays: weekdays.toList()..sort(),
      everyN: int.tryParse(everyNController.text.trim()),
      times: times,
      countPerDay: int.tryParse(countController.text.trim()),
      amount: _amountEntered,
      unit: plansAmount ? unit : null,
    );
  }

  /// This editor's values as [_FormSnapshot] compares them: the rule, plus the
  /// amount, unit and route only when the rule carries them. Without that gate,
  /// removing and re-adding a stored member with no Schedule would read as a
  /// change, since its unit is reseeded from the Compound's default.
  String snapshotValue() {
    return jsonEncode(<String, Object?>{
      'rule': ruleJson(),
      'amount': _amountEntered,
      'unit': plansAmount ? unit.name : null,
      'route': plansAmount ? route.name : null,
    });
  }

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

  /// Every member Compound resolved so far, archived ones included. Read before
  /// the active list wherever this form names a member, and kept across the
  /// lookup's key changes.
  final Map<String, CompoundScheduleOptionRecord> _memberOptions =
      <String, CompoundScheduleOptionRecord>{};

  /// The in-progress declared target outcomes: the selected `Metric` ids and
  /// whether `performance` is selected. A Protocol MAY declare them, never
  /// must.
  final Set<String> _selectedMetricIds = <String>{};
  bool _performanceSelected = false;

  /// The Reminders switch (D5): off until the user turns it on.
  late bool _remindersEnabled;

  /// Hard rejects show once the user has tried to save, so a half-filled
  /// Schedule doesn't open with errors; warnings show as soon as they apply.
  bool _showErrors = false;
  String? _errorText;
  bool _saving = false;

  /// The When section's state: collapsed on open, and expanded by a save attempt
  /// that finds a period issue.
  bool _periodExpanded = false;

  /// What the form held when it opened, the baseline for Unsaved changes (D5).
  late final _FormSnapshot _initialSnapshot;

  /// Set just before a successful save closes the form, which never asks.
  bool _saved = false;

  bool get _isEditing => widget.protocol != null;

  @override
  void initState() {
    super.initState();
    final protocol = widget.protocol;
    _nameController = TextEditingController(text: protocol?.name ?? '');
    _startDate = protocol?.startLocalDate ??
        ProtocolDayDate.fromDateTime(DateTime.now());
    _endDate = protocol?.endLocalDate;
    _remindersEnabled = protocol?.remindersEnabled ?? false;

    final cycle = protocol?.period?.cycle;
    _cycleEnabled = cycle != null;
    _cycleOnController =
        TextEditingController(text: cycle == null ? '' : '${cycle.onDays}');
    _cycleOffController =
        TextEditingController(text: cycle == null ? '' : '${cycle.offDays}');
    // A default anchor is the start, whatever date it stores (D4): the core
    // plans from the start, so the editor shows it.
    _cycleAnchor =
        protocolCycleFromStart(cycle, _startDate)?.anchor ?? _startDate;
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
    _initialSnapshot = _snapshot();
  }

  _FormSnapshot _snapshot() {
    return (
      name: _nameController.text.trim(),
      start: _startDate.storageValue,
      end: _endDate?.storageValue,
      cycle: _cycleEnabled
          ? jsonEncode(<Object?>[
              _cycleOnController.text.trim(),
              _cycleOffController.text.trim(),
              _cycleAnchor.storageValue,
              _cycleAnchorIsDefault,
            ])
          : '',
      pauses: jsonEncode(<Object?>[for (final p in _pauses) p.toJson()]),
      // Ordered: a member's position is saved.
      members: jsonEncode(<Object?>[
        for (final compoundId in _compoundIds)
          <Object?>[compoundId, _scheduleFields[compoundId]?.snapshotValue()],
      ]),
      reminders: _remindersEnabled,
      metricIds: jsonEncode(_selectedMetricIds.toList()..sort()),
      performance: _performanceSelected,
    );
  }

  /// Back on a dirty form (D5). A save or end still running blocks it instead:
  /// its `Navigator.pop` would close this dialog and leave the form open, ready
  /// to save a second Protocol.
  void _onPopInvoked(bool didPop, Object? result) {
    if (didPop || _saving) {
      return;
    }
    unawaited(_confirmDiscard());
  }

  /// The dialog sits inside [ProtocolsLockSheetGuard] for the same reason the
  /// Schedule sheet does: nothing of a Protocol's stays up over the lock.
  Future<void> _confirmDiscard() async {
    final l10n = context.l10n;
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ProtocolsLockSheetGuard(
        child: AlertDialog(
          title: Text(
            _isEditing
                ? l10n.protocolEditorDiscardChangesTitle
                : l10n.protocolEditorDiscardNewTitle,
          ),
          actions: <Widget>[
            TextButton(
              key: ProtocolFormScreen.discardKeepEditingKey,
              style: TextButton.styleFrom(
                foregroundColor: colors.textPrimary,
                minimumSize: const Size(0, AppDimens.touchTarget),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.protocolEditorKeepEditing),
            ),
            FilledButton(
              key: ProtocolFormScreen.discardConfirmKey,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppDimens.touchTarget),
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.protocolEditorDiscard),
            ),
          ],
        ),
      ),
    );
    if ((discard ?? false) && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Opens the stored Protocol's Consistency view, with a tab per member in
  /// the Protocol's member order, behind the Protocols lock like the rest of
  /// the section. It reads the members as saved, not this form's edits.
  Future<void> _openConsistency(
    ProtocolRecord protocol,
    List<CompoundScheduleOptionRecord> compounds,
  ) {
    final members = List<ProtocolMemberRecord>.of(protocol.members)
      ..sort((a, b) => a.position.compareTo(b.position));
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProtocolsLockGate(
          child: ConsistencyScreen.protocol(
            protocolName: protocol.name,
            members: <ConsistencyTab>[
              for (final member in members)
                ConsistencyTab(
                  compoundId: member.compoundId,
                  label: _compoundOption(member.compoundId, compounds).name,
                ),
            ],
          ),
        ),
      ),
    );
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
    final periodValidation = _validatePeriod();
    final headingStyle = TextStyle(color: colors.textPrimary);
    // The key changes with the members and a new key starts loading, so every
    // resolved value is kept: a row doesn't blink as members come and go.
    final memberLookup = ref.watch(
      compoundsByIdsProvider(CompoundNameLookupRequest(_compoundIds)),
    );
    for (final option
        in memberLookup.value ?? const <CompoundScheduleOptionRecord>[]) {
      _memberOptions[option.id] = option;
    }

    return PopScope<Object?>(
      canPop: _saved || _snapshot() == _initialSnapshot,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.chrome,
          title: Text(
            _isEditing
                ? l10n.protocolEditorEditTitle
                : l10n.protocolEditorNewTitle,
          ),
          actions: <Widget>[
            // A saved Protocol's Consistency view, a tab per member (file 45).
            // A new one has nothing stored to show yet.
            if (widget.protocol case final protocol?
                when protocol.members.isNotEmpty)
              TextButton.icon(
                key: ProtocolFormScreen.consistencyButtonKey,
                style: TextButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  minimumSize: const Size(0, AppDimens.touchTarget),
                ),
                onPressed: () =>
                    unawaited(_openConsistency(protocol, compounds)),
                icon: const Icon(Icons.timeline),
                label: Text(l10n.consistencyButton),
              ),
          ],
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
                // PopScope's canPop is read at build.
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppDimens.base),
              Text(l10n.protocolEditorCompoundsHeading, style: headingStyle),
              const SizedBox(height: AppDimens.dense),
              for (final compoundId in _compoundIds)
                _MemberRow(
                  key: ProtocolFormScreen.memberRowKey(compoundId),
                  compoundId: compoundId,
                  name: _memberOptions[compoundId]?.name ??
                      (memberLookup.isLoading
                          ? ''
                          : l10n.protocolEditorCompoundFallback),
                  isArchived: _isKnownArchived(compoundId),
                  field: _fieldFor(compoundId, compounds),
                  showErrors: _showErrors,
                  // Not before its defaults and name are known: the sheet would
                  // open titled and seeded from a placeholder.
                  onTap: _memberOptions.containsKey(compoundId) ||
                          !memberLookup.isLoading
                      ? () => unawaited(_openScheduleSheet(compoundId))
                      : null,
                  onRemove: () => _toggleCompound(compoundId, selected: false),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: ProtocolFormScreen.addCompoundsKey,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textPrimary,
                    minimumSize: const Size(0, AppDimens.touchTarget),
                  ),
                  onPressed: () => unawaited(_addCompounds()),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.protocolEditorAddCompounds),
                ),
              ),
              const SizedBox(height: AppDimens.base),
              Text(l10n.protocolEditorWhenHeading, style: headingStyle),
              _PeriodSection(
                summary: _periodSummary(l10n),
                expanded: _periodExpanded,
                onToggle: () =>
                    setState(() => _periodExpanded = !_periodExpanded),
                children: _periodExpanded
                    ? _periodControls(compounds, periodValidation)
                    : const <Widget>[],
              ),
              const SizedBox(height: AppDimens.base),
              _RemindersField(
                enabled: _remindersEnabled,
                savedEnabled: widget.protocol?.remindersEnabled ?? false,
                onChanged: (enabled) =>
                    unawaited(_setRemindersEnabled(enabled)),
              ),
              const SizedBox(height: AppDimens.base),
              Text(l10n.protocolEditorTargetOutcomesHeading,
                  style: headingStyle),
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
              if (widget.protocol case final protocol?) ..._endButton(protocol),
            ],
          ),
        ),
      ),
    );
  }

  /// The When section's row (D5), such as "Starts Nov 4 · until Dec 31 · 5 on, 2
  /// off · 2 Pauses", from the form's current values. An end date already passed
  /// says only that: nothing else about the period is still ahead.
  String _periodSummary(AppLocalizations l10n) {
    final format = DateFormat.MMMd(l10n.localeName);
    final end = _endDate;
    final today =
        ProtocolDayDate.fromDateTime(ref.watch(protocolsClockProvider)());
    if (end != null && end.compareTo(today) < 0) {
      return l10n.protocolEditorPeriodEnded(
        format.format(end.toLocalDateTime()),
      );
    }
    final onDays = int.tryParse(_cycleOnController.text.trim());
    final offDays = int.tryParse(_cycleOffController.text.trim());
    return <String>[
      l10n.protocolEditorPeriodStarts(
        format.format(_startDate.toLocalDateTime()),
      ),
      if (end == null)
        l10n.protocolEditorPeriodOngoing
      else
        l10n.protocolEditorPeriodUntil(format.format(end.toLocalDateTime())),
      if (_cycleEnabled && onDays != null && offDays != null)
        l10n.protocolEditorPeriodCycle(onDays, offDays),
      if (_pauses.isNotEmpty) l10n.protocolEditorPeriodPauses(_pauses.length),
    ].join(' · ');
  }

  /// The start date and Protocol Period controls: until, the "N doses" helper,
  /// cycle and Pauses, with the Period's issues under them.
  List<Widget> _periodControls(
    List<CompoundScheduleOptionRecord> compounds,
    DoseValidationResult periodValidation,
  ) {
    final colors = context.colors;
    final l10n = context.l10n;
    final dateFormat = DateFormat.yMMMd();
    final headingStyle = TextStyle(color: colors.textPrimary);
    return <Widget>[
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
        style: context.textStyles.label.copyWith(color: colors.textSecondary),
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
    ];
  }

  CompoundScheduleOptionRecord _compoundOption(
    String compoundId, [
    List<CompoundScheduleOptionRecord>? compounds,
  ]) {
    final known = _memberOptions[compoundId];
    if (known != null) {
      return known;
    }
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

  void _toggleCompound(String compoundId, {required bool selected}) {
    setState(() {
      if (selected) {
        if (!_compoundIds.contains(compoundId)) {
          _compoundIds = <String>[..._compoundIds, compoundId];
        }
        _fieldFor(compoundId);
      } else {
        _compoundIds = _compoundIds.where((id) => id != compoundId).toList(
              growable: true,
            );
        // Dropping the Compound drops its in-progress Schedule too: the
        // repository archives the member, which keeps its versions.
        _scheduleFields.remove(compoundId)?.dispose();
      }
    });
  }

  bool _isKnownArchived(String compoundId) =>
      _memberOptions[compoundId]?.isArchived ?? false;

  /// Opens one member's Schedule editor in a sheet, bound to the same
  /// [_ScheduleFieldState] as the row: closing it keeps every change, and
  /// nothing is saved inside it.
  ///
  /// The content must stay inside [ProtocolsLockSheetGuard]. On lock the gate
  /// disposes this State and with it the field controllers the sheet is bound
  /// to, so the sheet must not survive that frame.
  Future<void> _openScheduleSheet(String compoundId) {
    final compound = _compoundOption(compoundId);
    final field = _fieldFor(compoundId);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: ProtocolsLockSheetGuard(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height *
                  _scheduleSheetMaxHeightFactor,
            ),
            child: StatefulBuilder(
              builder: (_, setSheetState) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.base,
                ),
                child: _ScheduleEditor(
                  key: ProtocolFormScreen.scheduleEditorKey(compoundId),
                  compound: compound,
                  field: field,
                  protocolStart: _startDate,
                  showErrors: _showErrors,
                  onChanged: () {
                    setState(() {});
                    setSheetState(() {});
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the picker and applies its result (D6): members still selected and
  /// members whose Compounds are archived, which the picker never sees, keep
  /// their places, and the rest follow in the order picked.
  ///
  /// Only a Compound new to this Protocol gets the added-member default (D5). A
  /// stored member re-added goes through [_fieldFor], which restores its
  /// version, so this tests membership: a member with no Schedule Version is
  /// still one, and comes back to "No schedule".
  Future<void> _addCompounds() async {
    final result = await showCompoundPickerSheet(
      context,
      selectedIds: _compoundIds
          .where((compoundId) => !_isKnownArchived(compoundId))
          .toList(growable: false),
    );
    if (result == null || !mounted) {
      return;
    }

    final added = result
        .where((compoundId) => !_compoundIds.contains(compoundId))
        .toList(growable: false);
    final storedIds = <String>{
      for (final member
          in widget.protocol?.members ?? const <ProtocolMemberRecord>[])
        member.compoundId,
    };
    final newIds =
        added.where((compoundId) => !storedIds.contains(compoundId)).toSet();
    if (newIds.isNotEmpty) {
      final lastDoses = await ref
          .read(protocolDayControllerProvider.notifier)
          .latestDoseAmounts(newIds);
      if (!mounted) {
        return;
      }
      final options = await _readCompoundsByIds(newIds);
      if (options == null || !mounted) {
        return;
      }
      for (final option in options) {
        _memberOptions[option.id] = option;
      }
      // Seeded first, so _fieldFor's putIfAbsent keeps them.
      for (final compoundId in newIds) {
        _scheduleFields[compoundId] = _ScheduleFieldState.forNewMember(
          _compoundOption(compoundId),
          lastDoses[compoundId],
          protocolStart: _startDate,
        );
      }
    }

    final kept = result.toSet();
    for (final compoundId in List<String>.of(_compoundIds)) {
      if (!kept.contains(compoundId) && !_isKnownArchived(compoundId)) {
        _toggleCompound(compoundId, selected: false);
      }
    }
    for (final compoundId in added) {
      _toggleCompound(compoundId, selected: true);
    }
  }

  /// [ids]' Compounds, read once by id, or null when the app locked first.
  /// `compoundScheduleOptionListProvider` may not yet hold a Compound just
  /// created in the picker.
  ///
  /// A subscription is held across the read: with no listener Riverpod pauses a
  /// stream provider and disposes an autoDispose one, and the read never
  /// completes.
  Future<List<CompoundScheduleOptionRecord>?> _readCompoundsByIds(
    Set<String> ids,
  ) async {
    final subscription = ref.listenManual(
      compoundsByIdsProvider(CompoundNameLookupRequest(ids)).future,
      (_, __) {},
    );
    try {
      return await subscription.read();
    } on StateError {
      // Leaving the tree closes the subscription, which fails a read of this
      // autoDispose provider while it is loading. Nobody is waiting for this.
      if (mounted) {
        rethrow;
      }
      return null;
    } finally {
      subscription.close();
    }
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

  Future<ProtocolDayDate?> _pickDate(ProtocolDayDate initial) =>
      _pickProtocolDay(context, initial);

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
    final periodRejected = !_validatePeriod().accepted;
    final rejected = periodRejected ||
        fields.values.any((field) => !field.validate().accepted);
    if (rejected) {
      setState(() {
        _showErrors = true;
        _errorText = l10n.protocolEditorFixIssues;
        // The issue lives among the period controls, so they must be showing.
        if (periodRejected) {
          _periodExpanded = true;
        }
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
      remindersEnabled: _remindersEnabled,
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
      setState(() {
        _saving = false;
        _saved = true;
      });
      Navigator.of(context).pop();
    }
  }

  /// Turns the Reminders switch. Turning it on asks for the notification
  /// permission the first time, while it has never been asked (CUJ 10),
  /// through the one permission path the rest timer also uses (D5). A
  /// denial leaves the switch on and shows the denied state beside it.
  Future<void> _setRemindersEnabled(bool enabled) async {
    setState(() => _remindersEnabled = enabled);
    if (!enabled) {
      return;
    }
    await ref
        .read(protocolReminderSchedulerProvider)
        .requestPermissionIfNotAsked();
  }

  /// A saved Protocol's one way out (D8): Archive when it has history, or
  /// Delete when it has none, read from [protocolHasHistoryProvider]. While
  /// that read loads, neither shows. Both are full-width 48 dp targets with
  /// text, so the destructive color is never the only signal.
  List<Widget> _endButton(ProtocolRecord protocol) {
    final hasHistory = ref.watch(protocolHasHistoryProvider(protocol.id)).value;
    if (hasHistory == null) {
      return const <Widget>[];
    }
    final colors = context.colors;
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return <Widget>[
      const SizedBox(height: AppDimens.dense),
      SizedBox(
        height: AppDimens.touchTarget,
        child: hasHistory
            ? OutlinedButton.icon(
                key: ProtocolFormScreen.archiveButtonKey,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  side: BorderSide(color: colors.divider),
                ),
                onPressed: _saving ? null : () => _archive(protocol),
                icon: const Icon(Icons.archive_outlined),
                label: Text(l10n.protocolEditorArchive),
              )
            // DESIGN.md `button-destructive`: the theme's error color, which
            // is the destructive token, with its on-color text.
            : FilledButton.icon(
                key: ProtocolFormScreen.deleteButtonKey,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed: _saving ? null : () => _delete(protocol),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.protocolEditorDelete),
              ),
      ),
    ];
  }

  /// Asks before archiving (D8), because archiving also closes today: its
  /// planned doses no Dose filled are no longer expected.
  Future<void> _archive(ProtocolRecord protocol) async {
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.protocolArchiveConfirmTitle(protocol.name),
      message: l10n.protocolArchiveConfirmMessage,
      confirmKey: ProtocolFormScreen.confirmArchiveButtonKey,
      confirmLabel: l10n.protocolEditorArchive,
      destructive: false,
    );
    if (!confirmed || !mounted) {
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

  /// Asks before deleting (D8). The repository checks history again inside
  /// its transaction: a Dose synced in since the editor read "no history"
  /// refuses the delete, and the button then follows the fresh read.
  ///
  /// A Protocol already deleted, or removed by undo, on another device and
  /// synced in while the editor was open makes the repository throw a
  /// [StateError]. The user asked for it gone and it is, so the editor
  /// closes, as the Agent path answers `already_deleted`. Any other failure
  /// re-enables the buttons and says why, as a failed Save does.
  Future<void> _delete(ProtocolRecord protocol) async {
    final l10n = context.l10n;
    final confirmed = await _confirm(
      title: l10n.protocolDeleteConfirmTitle(protocol.name),
      message: l10n.protocolDeleteConfirmMessage,
      confirmKey: ProtocolFormScreen.confirmDeleteButtonKey,
      confirmLabel: l10n.protocolEditorDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(protocolListControllerProvider.notifier)
          .deleteProtocol(protocol.id);
    } on ProtocolHasHistoryException {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.protocolOnlyArchivable)),
        );
      }
      return;
    } on StateError {
      // Already deleted elsewhere: nothing left to do but close.
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = l10n.protocolEditorDeleteFailed('$error');
        });
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required Key confirmKey,
    required String confirmLabel,
    required bool destructive,
  }) async {
    final l10n = context.l10n;
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: colors.textPrimary,
              minimumSize: const Size(0, AppDimens.touchTarget),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.protocolEditorCancel),
          ),
          FilledButton(
            key: confirmKey,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppDimens.touchTarget),
              backgroundColor: destructive ? scheme.error : null,
              foregroundColor: destructive ? scheme.onError : null,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
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

/// The Reminders switch, bound to the Protocol's `remindersEnabled` (D5,
/// file 56), with what the phone does about it beside the switch: the
/// denied state with a way to the system settings (CUJ 10), or how far
/// ahead reminders are scheduled (CUJ 11). The horizon shows only for a
/// saved Protocol whose reminders are on, because it describes what is
/// stored, not this form's edits.
class _RemindersField extends ConsumerWidget {
  const _RemindersField({
    required this.enabled,
    required this.savedEnabled,
    required this.onChanged,
  });

  final bool enabled;
  final bool savedEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = context.l10n;
    final status = ref.watch(protocolReminderStatusProvider).value ??
        ProtocolReminderStatus.unknown;
    final denied = status.permission == TimerBackgroundPermissionStatus.denied;
    final horizonEnd = status.horizonEnd;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: ProtocolFormScreen.remindersSwitchKey,
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.protocolRemindersSwitchLabel,
            style: TextStyle(color: colors.textPrimary),
          ),
          subtitle: Text(
            l10n.protocolRemindersSwitchSubtitle,
            style: TextStyle(color: colors.textSecondary),
          ),
          value: enabled,
          onChanged: onChanged,
        ),
        if (enabled && denied)
          ProtocolReminderNotice(
            key: ProtocolFormScreen.remindersDeniedKey,
            message: l10n.protocolRemindersPermissionDenied,
            actionLabel: l10n.protocolRemindersOpenSettings,
            actionKey: ProtocolFormScreen.remindersOpenSettingsKey,
            onAction: () => unawaited(
              ref
                  .read(protocolReminderSchedulerProvider)
                  .openNotificationSettings(),
            ),
          )
        else if (enabled && savedEnabled && horizonEnd != null)
          Text(
            protocolRemindersScheduledThroughLabel(l10n, horizonEnd),
            key: ProtocolFormScreen.remindersHorizonKey,
            style: TextStyle(color: colors.textSecondary),
          ),
      ],
    );
  }
}

/// One Protocol Member in the editor: its name, **Archived** when its Compound
/// is, its one-line Schedule summary and a remove button; tapping the row opens
/// its Schedule editor. Once a save has been tried, a missing amount shows in
/// the error color and a Schedule with hard rejects says so under the row, each
/// as text, so color is never the only signal.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    super.key,
    required this.compoundId,
    required this.name,
    required this.isArchived,
    required this.field,
    required this.showErrors,
    required this.onTap,
    required this.onRemove,
  });

  final String compoundId;
  final String name;
  final bool isArchived;
  final _ScheduleFieldState field;
  final bool showErrors;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    final summary = protocolScheduleSummary(
      l10n,
      field.summaryInput(),
      material: MaterialLocalizations.of(context),
      localeName: Localizations.localeOf(context).toLanguageTag(),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final addAmount = l10n.protocolScheduleSummaryAddAmount;
    final amountMarked =
        showErrors && field.needsAmount && summary.endsWith(addAmount);

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppDimens.dense / 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppDimens.dense,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isArchived)
                          Text(
                            l10n.protocolEditorMemberArchived,
                            style: context.textStyles.label
                                .copyWith(color: colors.textSecondary),
                          ),
                      ],
                    ),
                    Text.rich(
                      amountMarked
                          ? TextSpan(
                              children: <InlineSpan>[
                                TextSpan(
                                  text: summary.substring(
                                    0,
                                    summary.length - addAmount.length,
                                  ),
                                ),
                                TextSpan(
                                  text: addAmount,
                                  style: TextStyle(color: errorColor),
                                ),
                              ],
                            )
                          : TextSpan(text: summary),
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    if (showErrors && !field.validate().accepted)
                      Text(
                        l10n.protocolEditorFixSchedule,
                        key: ProtocolFormScreen.memberFixKey(compoundId),
                        style: TextStyle(color: errorColor),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              key: ProtocolFormScreen.removeMemberKey(compoundId),
              tooltip: l10n.protocolEditorRemoveMember(name),
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled date row that opens a date picker; at least 48 dp tall.
/// The When section (D5): a row with the period's summary, and today's controls
/// in place under it while expanded.
class _PeriodSection extends StatelessWidget {
  const _PeriodSection({
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final String summary;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          container: true,
          button: true,
          expanded: expanded,
          child: InkWell(
            key: ProtocolFormScreen.periodSummaryKey,
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppDimens.touchTarget,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      summary,
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: AppDimens.dense),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

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
                value: _anchorLabel(
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
              isExpanded: true,
              decoration:
                  InputDecoration(labelText: l10n.protocolEditorUnitLabel),
              items: <DropdownMenuItem<DoseUnit>>[
                for (final unit in DoseUnit.values)
                  DropdownMenuItem<DoseUnit>(
                    value: unit,
                    child: Text(
                      doseUnitLabel(unit),
                      overflow: TextOverflow.ellipsis,
                    ),
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
              isExpanded: true,
              decoration:
                  InputDecoration(labelText: l10n.protocolEditorRouteLabel),
              items: <DropdownMenuItem<DoseRoute>>[
                for (final route in DoseRoute.values)
                  DropdownMenuItem<DoseRoute>(
                    value: route,
                    child: Text(
                      doseRouteLabel(route),
                      overflow: TextOverflow.ellipsis,
                    ),
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

  Future<void> _pickAnchor(BuildContext context) async {
    final picked = await _pickProtocolDay(context, field.everyNAnchor);
    if (picked == null) {
      return;
    }
    field
      ..everyNAnchor = picked
      ..everyNAnchorIsDefault = false;
    onChanged();
  }

  /// Edits the time at [index], or adds one. A new time is suggested an hour
  /// after the last one; times are kept sorted, as they are stored.
  Future<void> _pickTime(BuildContext context, {int? index}) async {
    final TimeOfDay initial;
    if (index != null) {
      initial = planTimeOfDay(field.times[index]);
    } else if (field.times.isEmpty) {
      initial = planTimeOfDay(_defaultPlannedTime);
    } else {
      final last = planTimeOfDay(field.times.last);
      initial = TimeOfDay(hour: (last.hour + 1) % 24, minute: last.minute);
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !context.mounted) {
      return;
    }
    final value = planLocalTime(picked.hour, picked.minute);
    if (index == null) {
      field.times.add(value);
    } else {
      field.times[index] = value;
    }
    field.times.sort();
    onChanged();
  }
}

/// A cycle or every-N anchor as the editor shows it, marked when it is the
/// default (the Protocol's start).
String _anchorLabel(
  AppLocalizations l10n,
  ProtocolDayDate anchor, {
  required bool isDefault,
}) {
  final formatted = DateFormat.yMMMd().format(anchor.toLocalDateTime());
  return isDefault ? l10n.protocolEditorAnchorIsStart(formatted) : formatted;
}

/// The date picker every Protocol date in the editor uses; null when it is
/// dismissed or [context] is gone.
Future<ProtocolDayDate?> _pickProtocolDay(
  BuildContext context,
  ProtocolDayDate initial,
) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: initial.toLocalDateTime(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (picked == null || !context.mounted) {
    return null;
  }
  return ProtocolDayDate.fromDateTime(picked);
}

String _formatTime(BuildContext context, String localTime) {
  if (!isPlanLocalTime(localTime)) {
    return localTime;
  }
  return planTimeOfDay(localTime).format(context);
}

/// The locale's short weekday name for ISO [weekday] (1 = Monday).
/// 2024-01-01 was a Monday.
String _weekdayLabel(BuildContext context, int weekday) {
  return _shortWeekdayName(
    Localizations.localeOf(context).toLanguageTag(),
    weekday,
  );
}

String _shortWeekdayName(String localeName, int weekday) {
  return DateFormat.E(localeName).format(DateTime.utc(2024, 1, weekday));
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
