import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/consistency_controller.dart';
import 'consistency_chart.dart';
import 'effect_screen.dart';
import 'plan_labels.dart';

/// One tab of the Consistency view: the Compound it shows, and the name its
/// tab starts with. Once the tab's read arrives, the tab shows the Compound's
/// name from it, which an archived Compound keeps.
final class ConsistencyTab {
  const ConsistencyTab({required this.compoundId, required this.label});

  final String compoundId;
  final String label;
}

/// The Consistency view (D6, Phase 4 file 41): for one Compound, or for each
/// member of a Protocol in a tab of its own, what was logged, when, and how
/// much, against what was planned, over a chosen date range.
///
/// Above, a range picker: the last 30 days, including today, by default; 7,
/// 90 or 365 days; or a custom range of up to [maxConsistencyRangeDays]
/// days. Then the chart (`ConsistencyChart`), and below it the day list:
/// each date's Day Status label, with its not-planned reason, the count of
/// extra Doses next to it, and each planned dose with the Dose that filled
/// it, so which slot a Dose filled is visible (D6). A Compound in no
/// Protocol has no Day Statuses; its Doses are listed by date with no label.
///
/// It mirrors the plan back and judges nothing: statuses and counts only,
/// never a ratio, a score or a streak, and none of the words D6 bans. Every
/// label is a word; color and icons only echo it. It carries the Effect
/// view's notice ([EffectScreen.disclaimerText]). Everything shown is
/// derived on read through `consistencyProvider`; nothing is stored.
class ConsistencyScreen extends StatelessWidget {
  const ConsistencyScreen._({
    super.key,
    required this.title,
    required this.tabs,
    required this.showTabs,
  });

  /// One Compound's view, opened from its row in the Compound list.
  factory ConsistencyScreen.compound({
    Key? key,
    required String compoundId,
    required String compoundName,
  }) {
    return ConsistencyScreen._(
      key: key,
      title: compoundName,
      tabs: <ConsistencyTab>[
        ConsistencyTab(compoundId: compoundId, label: compoundName),
      ],
      showTabs: false,
    );
  }

  /// A Protocol's view, opened from the Protocol screen, with a tab per
  /// member. Each tab is that Compound's Consistency: its Day Status sums
  /// every Protocol it is in, because a Day Status is one per Compound and
  /// date (D6).
  factory ConsistencyScreen.protocol({
    Key? key,
    required String protocolName,
    required List<ConsistencyTab> members,
  }) {
    return ConsistencyScreen._(
      key: key,
      title: protocolName,
      tabs: List<ConsistencyTab>.unmodifiable(members),
      showTabs: true,
    );
  }

  /// The Compound's or the Protocol's name, in the app bar.
  final String title;
  final List<ConsistencyTab> tabs;
  final bool showTabs;

  static const disclaimerKey = Key('consistency.disclaimer');
  static const rangeSummaryKey = Key('consistency.rangeSummary');
  static const customRangeChipKey = Key('consistency.range.custom');
  static const notInProtocolKey = Key('consistency.notInProtocol');
  static const noDosesKey = Key('consistency.noDoses');

  static Key rangeChipKey(ConsistencyRangePreset preset) =>
      Key('consistency.range.${preset.name}');

  static Key tabKey(String compoundId) => Key('consistency.tab-$compoundId');

  static Key dayKey(String compoundId, ProtocolDayDate date) =>
      Key('consistency.day-$compoundId-${date.storageValue}');

  static Key dayStatusKey(String compoundId, ProtocolDayDate date) =>
      Key('consistency.dayStatus-$compoundId-${date.storageValue}');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final appBarTitle = Text(l10n.consistencyScreenTitle(title));
    if (!showTabs) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(backgroundColor: colors.chrome, title: appBarTitle),
        body: _ConsistencyBody(compoundId: tabs.single.compoundId),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          backgroundColor: colors.chrome,
          title: appBarTitle,
          // The theme's default tab color is the primary, which fails WCAG
          // AA on the light chrome (about 2.4:1). The selected tab reads in
          // textPrimary over an indicator of the same color, whose shape,
          // not its hue, marks the selection; the others read in
          // textSecondary.
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: colors.textPrimary,
            unselectedLabelColor: colors.textSecondary,
            indicatorColor: colors.textPrimary,
            tabs: <Widget>[
              for (final tab in tabs)
                Tab(
                  key: ConsistencyScreen.tabKey(tab.compoundId),
                  child: _TabLabel(tab: tab),
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            for (final tab in tabs)
              _ConsistencyBody(compoundId: tab.compoundId),
          ],
        ),
      ),
    );
  }
}

/// A Protocol view's tab label: the Compound's name as its own read gives
/// it (the plan read joins every member's Compound, archived or not), or
/// the name the tab was opened with until that read arrives.
class _TabLabel extends ConsumerWidget {
  const _TabLabel({required this.tab});

  final ConsistencyTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(
      consistencyProvider(tab.compoundId)
          .select((range) => range.value?.compound?.name),
    );
    return Text(name ?? tab.label);
  }
}

class _ConsistencyBody extends ConsumerWidget {
  const _ConsistencyBody({required this.compoundId});

  final String compoundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = context.l10n;
    final rangeAsync = ref.watch(consistencyProvider(compoundId));
    // Only a settled read is shown. While a newly picked range loads (the
    // provider reloads, keeping the last range's value), or after a read
    // fails, the previous read's days never stand under the new dates or
    // hide the error. A Dose or plan change re-emits on the same stream, so
    // it never passes through loading.
    final range =
        rangeAsync.hasError || rangeAsync.isLoading ? null : rangeAsync.value;
    final secondary = TextStyle(color: colors.textSecondary);

    final header = <Widget>[
      Text(
        key: ConsistencyScreen.disclaimerKey,
        EffectScreen.disclaimerText,
        style: context.textStyles.caption.copyWith(color: colors.textSecondary),
      ),
      const SizedBox(height: AppDimens.dense),
      const _RangePicker(),
      const SizedBox(height: AppDimens.base),
    ];

    if (range == null) {
      return ListView(
        padding: const EdgeInsets.all(AppDimens.base),
        children: <Widget>[
          ...header,
          if (rangeAsync.hasError)
            Text(l10n.consistencyLoadError, style: secondary)
          else
            const Center(child: CircularProgressIndicator()),
        ],
      );
    }

    final days = range.days;
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.base,
            AppDimens.base,
            AppDimens.base,
            0,
          ),
          sliver: SliverList.list(
            children: <Widget>[
              ...header,
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadii.cardMd,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppDimens.base),
                  child: ConsistencyChart(range: range),
                ),
              ),
              const SizedBox(height: AppDimens.base),
              if (!range.isPlanned)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppDimens.dense),
                  child: Text(
                    key: ConsistencyScreen.notInProtocolKey,
                    l10n.consistencyNotInProtocol,
                    style: secondary,
                  ),
                ),
              if (days.isEmpty)
                Text(
                  key: ConsistencyScreen.noDosesKey,
                  l10n.consistencyNoDoses,
                  style: secondary,
                ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.base,
            0,
            AppDimens.base,
            AppDimens.base,
          ),
          sliver: SliverList.separated(
            itemCount: days.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: colors.divider),
            itemBuilder: (context, index) => _ConsistencyDayTile(
              range: range,
              day: days[index],
            ),
          ),
        ),
      ],
    );
  }
}

/// The range picker: the four fixed ranges, each ending today, and a custom
/// range, with the chosen dates written out.
class _RangePicker extends ConsumerWidget {
  const _RangePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = context.l10n;
    final selection = ref.watch(consistencyRangeControllerProvider);
    final controller = ref.read(consistencyRangeControllerProvider.notifier);
    final dateFormat = DateFormat.yMMMd();

    // No `labelStyle` override (as the Effect view's chips): the default chip
    // theme picks a contrast-safe label in both the selected and unselected
    // states.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: AppDimens.dense / 2,
          runSpacing: AppDimens.dense / 2,
          children: <Widget>[
            for (final preset in ConsistencyRangePreset.values)
              if (preset.days != null)
                ChoiceChip(
                  key: ConsistencyScreen.rangeChipKey(preset),
                  label: Text(l10n.consistencyRangeDays(preset.days!)),
                  selected: selection.preset == preset,
                  onSelected: (_) => controller.selectPreset(preset),
                ),
            ChoiceChip(
              key: ConsistencyScreen.customRangeChipKey,
              label: Text(l10n.consistencyRangeCustom),
              selected: selection.preset == ConsistencyRangePreset.custom,
              onSelected: (_) =>
                  unawaited(_pickCustomRange(context, ref, selection)),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.dense / 2),
        Text(
          key: ConsistencyScreen.rangeSummaryKey,
          l10n.protocolEditorDateRange(
            dateFormat.format(selection.from.toLocalDateTime()),
            dateFormat.format(selection.to.toLocalDateTime()),
          ),
          style: TextStyle(color: colors.textSecondary),
        ),
      ],
    );
  }

  /// A custom range ends today at the latest: the view never shows a day
  /// still to come. One longer than [maxConsistencyRangeDays] keeps its last
  /// [maxConsistencyRangeDays] days, and the summary shows the dates read.
  ///
  /// The controller is read before the picker opens, never through `ref`
  /// after it: while the picker is open the body can switch between its
  /// loading list and the chart's scroll view (a first read settling, say),
  /// which remounts this picker and disposes the
  /// `ref` that opened it. The Notifier outlives that remount, because
  /// `consistencyProvider` and the new picker both watch it; when the whole
  /// view was popped instead, the controller is no longer `mounted` and the
  /// pick is dropped.
  Future<void> _pickCustomRange(
    BuildContext context,
    WidgetRef ref,
    ConsistencyRangeSelection selection,
  ) async {
    final controller = ref.read(consistencyRangeControllerProvider.notifier);
    final today = selection.today.toLocalDateTime();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: selection.from.toLocalDateTime(),
        end: selection.to.toLocalDateTime(),
      ),
    );
    if (picked == null || !controller.mounted) {
      return;
    }
    controller.selectCustom(
      ProtocolDayDate.fromDateTime(picked.start),
      ProtocolDayDate.fromDateTime(picked.end),
    );
  }
}

/// One date of the day list: its date and Day Status label (with the reason
/// for "Not planned" and the count of extra Doses), each slot's planned time
/// and amount with the Dose that filled it, and the extra Doses. A date with
/// no Day Status lists its Doses with no label.
class _ConsistencyDayTile extends StatelessWidget {
  const _ConsistencyDayTile({required this.range, required this.day});

  final ConsistencyRange range;
  final ConsistencyDay day;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final status = day.status;
    final dateLabel =
        DateFormat.yMMMEd().format(day.localDate.toLocalDateTime());
    final secondary = TextStyle(color: colors.textSecondary);
    final detail = status == null ? null : _statusDetail(l10n, status);

    final lines = <Widget>[];
    if (status == null) {
      for (final dose in day.doses) {
        lines.add(_line(
            context,
            _join(<String>[
              _doseTime(context, dose),
              dose.amountLabel,
            ])));
      }
    } else {
      for (final slot in day.slots) {
        lines.addAll(_slotLines(context, status, slot));
      }
      for (final dose in day.extraDoses) {
        lines.add(_line(
            context,
            _join(<String>[
              l10n.consistencyExtra,
              _doseTime(context, dose),
              dose.amountLabel,
            ])));
      }
    }

    return Padding(
      key: ConsistencyScreen.dayKey(range.compoundId, day.localDate),
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  dateLabel,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (status != null)
                _DayStatusLabel(
                  key: ConsistencyScreen.dayStatusKey(
                    range.compoundId,
                    day.localDate,
                  ),
                  status: status,
                ),
            ],
          ),
          if (detail != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(detail, style: secondary),
            ),
          for (final line in lines) ...<Widget>[
            const SizedBox(height: 2),
            line,
          ],
        ],
      ),
    );
  }

  /// The reason a "Not planned" day plans nothing, and the count of extra
  /// Doses, which sits next to the status and never changes it (D6).
  String? _statusDetail(AppLocalizations l10n, DayStatus status) {
    final reason = status.notPlannedReason;
    final parts = <String>[
      if (reason != null) _reasonLabel(l10n, reason),
      if (status.extraCount > 0) l10n.consistencyExtraCount(status.extraCount),
    ];
    return parts.isEmpty ? null : _join(parts);
  }

  /// A slot's planned line, then the line of the Dose that filled it, or its
  /// unfilled label: "Pending" on today, "Not logged" before it. The planned
  /// and logged amounts read as entered; when both resolve to an active
  /// mass, both masses show too (D6). No verdict is drawn from them.
  List<Widget> _slotLines(
    BuildContext context,
    DayStatus status,
    ConsistencySlot slot,
  ) {
    final l10n = context.l10n;
    final fill = slot.fill;
    final dose = slot.dose;
    final plannedTime = fill.plannedLocalTime;
    final plannedAmount = plannedAmountLabel(fill.amount);
    final plannedMass = _plannedMass(fill.amount);
    final loggedMass = dose?.resolvedActiveMass;
    final showMasses = plannedMass != null && loggedMass != null;
    final protocolName = range.protocols[fill.protocolId]?.name;

    final planned = _line(
      context,
      _join(<String>[
        l10n.consistencyPlanned,
        plannedTime == null
            ? l10n.plannedListAnyTime
            : planTimeOfDay(plannedTime).format(context),
        if (plannedAmount.isNotEmpty) plannedAmount,
        if (showMasses) '≈ ${plannedMass.label}',
        if (protocolName != null) protocolName,
      ]),
    );
    final String logged;
    if (dose != null) {
      logged = _join(<String>[
        l10n.plannedListRowLogged,
        _doseTime(context, dose),
        dose.amountLabel,
        if (showMasses) '≈ ${loggedMass.label}',
      ]);
    } else {
      logged = status.localDate == range.today
          ? l10n.plannedListRowPending
          : l10n.plannedListRowNotLogged;
    }
    return <Widget>[
      planned,
      Padding(
        padding: const EdgeInsetsDirectional.only(start: AppDimens.dense),
        child: _line(context, logged, primary: true),
      ),
    ];
  }

  /// A planned amount's active mass: the amount times the Compound's
  /// strength, as `resolveDoseActiveMass` computes it; null when it doesn't
  /// resolve.
  ResolvedActiveMass? _plannedMass(PlanAmount amount) {
    final value = amount.amountValue;
    final unit = amount.unit;
    if (value == null || unit == null) {
      return null;
    }
    return resolveDoseActiveMass(
      amount: value,
      unit: unit,
      strength: range.compound?.strength,
    );
  }

  Widget _line(BuildContext context, String text, {bool primary = false}) {
    final colors = context.colors;
    return Text(
      text,
      style: TextStyle(
        color: primary ? colors.textPrimary : colors.textSecondary,
      ),
    );
  }
}

/// A Day Status as its word, with an icon that only echoes it (D6: color is
/// never the only signal).
class _DayStatusLabel extends StatelessWidget {
  const _DayStatusLabel({super.key, required this.status});

  final DayStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final (IconData icon, Color iconColor) = switch (status.status) {
      DayStatusKind.logged => (Icons.check_circle, colors.save),
      DayStatusKind.partlyLogged => (Icons.timelapse, colors.textSecondary),
      DayStatusKind.notLogged => (
          Icons.remove_circle_outline,
          colors.textSecondary,
        ),
      DayStatusKind.pending => (Icons.schedule, colors.textSecondary),
      DayStatusKind.paused => (
          Icons.pause_circle_outline,
          colors.textSecondary,
        ),
      DayStatusKind.offCycle => (Icons.sync_disabled, colors.textSecondary),
      DayStatusKind.notPlanned => (
          Icons.radio_button_unchecked,
          colors.textSecondary,
        ),
    };
    return StatusWordLabel(
      icon: icon,
      iconColor: iconColor,
      label: dayStatusLabel(l10n, status.status),
    );
  }
}

String _reasonLabel(AppLocalizations l10n, NotPlannedReason reason) =>
    switch (reason) {
      NotPlannedReason.notScheduledToday =>
        l10n.notPlannedReasonNotScheduledToday,
      NotPlannedReason.asNeeded => l10n.notPlannedReasonAsNeeded,
      NotPlannedReason.noSchedule => l10n.notPlannedReasonNoSchedule,
      NotPlannedReason.removed => l10n.notPlannedReasonRemoved,
      NotPlannedReason.outside => l10n.notPlannedReasonOutside,
    };

/// A Dose's clock time where it was taken: its frozen local time (D2).
String _doseTime(BuildContext context, DoseRecord dose) =>
    planTimeOfDay(dose.localTime).format(context);

String _join(List<String> parts) => parts.join(' · ');
