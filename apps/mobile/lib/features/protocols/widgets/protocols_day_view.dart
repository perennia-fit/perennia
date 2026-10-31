import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/protocol_controller.dart';
import '../controllers/protocols_day_controller.dart';
import '../services/protocol_reminder_scheduler.dart';
import 'compound_list_screen.dart';
import 'plan_labels.dart';
import 'protocol_reminders_settings.dart';
import 'protocol_screen.dart';
import 'protocols_lock_screen.dart';
import '../../../widgets/grouped_rows.dart';
import '../controllers/protocols_lock_controller.dart';

/// The Protocol Day view: a derived `Protocol Day` list, topped by the
/// Planned list (D6) when the day has anything planned. Its FAB hands off to
/// the Compound list
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
  static const plannedListKey = Key('protocols.day.plannedList');
  static const logAllPlannedButtonKey = Key('protocols.day.logAllPlanned');
  static const reminderPermissionBannerKey =
      Key('protocols.day.reminderPermissionBanner');
  static const reminderPermissionAllowKey =
      Key('protocols.day.reminderPermissionAllow');

  static Key doseRowKey(String id) => Key('protocols.day.dose-$id');

  static Key plannedGroupKey(String protocolId) =>
      Key('protocols.day.planned-$protocolId');

  static Key plannedRowKey(String protocolId, String compoundId, int slot) =>
      Key('protocols.day.planned-$protocolId-$compoundId-$slot');

  @override
  ConsumerState<ProtocolsDayView> createState() => _ProtocolsDayViewState();
}

class _ProtocolsDayViewState extends ConsumerState<ProtocolsDayView> {
  /// Checks once a minute whether local midnight has passed, so "today" (its
  /// row labels and "Log all planned") never sticks to yesterday.
  Timer? _dayBoundaryTimer;

  /// Checks on resume as well: a suspended app's timers may not run on time.
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _dayBoundaryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshIfDayChanged(),
    );
    _lifecycleListener = AppLifecycleListener(onResume: _refreshIfDayChanged);
    // Idempotently load the OTC seed library so the picker has neutral starter
    // Compounds on a first run (PROTOCOLS.md §3). Local-first: this never blocks
    // the logging path, and re-running is a no-op (stable ids).
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
  }

  @override
  void dispose() {
    _dayBoundaryTimer?.cancel();
    _lifecycleListener?.dispose();
    super.dispose();
  }

  void _refreshIfDayChanged() {
    if (!mounted) {
      return;
    }
    ref.read(protocolDayControllerProvider.notifier).refreshIfDayChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dayState = ref.watch(protocolDayControllerProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: Text(context.l10n.protocolsDomainTitle),
        actions: [
          IconButton(
            key: ProtocolsDayView.protocolsButtonKey,
            tooltip: context.l10n.protocolsYourProtocols,
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: () => _openProtocolList(context),
          ),
        ],
      ),
      body: dayState.when(
        data: (state) =>
            _ProtocolDayBody(day: state.day, plannedDay: state.plannedDay),
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
        label: Text(context.l10n.protocolsLogDose),
      ),
    );
  }

  /// Logging a Dose always starts from an existing `Compound` ( moves
  /// Compound creation exclusively to `CompoundEditorSheet`) — so the
  /// Day view's FAB hands off to the Compound list, whose rows are the ≤2-tap
  /// entry point (tap a Compound → the prefilled sheet → Save). Reuses the
  /// existing discreet surface rather than duplicating a picker here. The
  /// list logs on the selected Protocol Day (file 38).
  ///
  /// Gated like every Protocols route: the Gate below on the Navigator
  /// stack can't cover a route pushed over it, so without its own Gate the
  /// list stays visible when the app re-locks.
  void _openCompoundList(BuildContext context) {
    final protocolDay = ref.read(selectedProtocolDayProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProtocolsLockGate(
          child: CompoundListScreen(protocolDay: protocolDay),
        ),
      ),
    );
  }

  /// Opens the `Protocol` list (PROTOCOLS.md §1.4, §5) — the Routine
  /// analog: named, time-bounded courses grouping one or more Compounds (a
  /// stack). A secondary surface reached from the app bar, never primary
  /// navigation.
  void _openProtocolList(BuildContext context) {
    Navigator.of(
      context,
    ).push(
      MaterialPageRoute<void>(
        builder: (_) => const ProtocolsLockGate(child: ProtocolListScreen()),
      ),
    );
  }
}

/// The Protocols tab on Today: the selected day's planned doses and logged
/// Doses, then the user's Protocols, under Today's own date header.
///
/// Protocols used to sit behind Log → "Supplement" and an app-bar icon,
/// which hid the one part of the domain people come back to every day:
/// what is due now, and where to set up the plan that reminds them. It is
/// the same Planned list and log as the Protocol Day view, laid out inline
/// so Today's list scrolls it, and it keeps the domain's discretion: the
/// lock renders an unlock prompt in place of any Compound or Dose, and a
/// device setting hides the tab altogether.
class ProtocolsTodayBody extends ConsumerStatefulWidget {
  const ProtocolsTodayBody({super.key, required this.localDate});

  /// Today's selected date, which this tab follows instead of keeping a
  /// date of its own.
  final ProtocolDayDate localDate;

  static const bodyKey = Key('protocols.today.body');
  static const lockedKey = Key('protocols.today.locked');
  static const introKey = Key('protocols.today.intro');
  static const loggedKey = Key('protocols.today.logged');
  static const yourProtocolsKey = Key('protocols.today.yourProtocols');
  static const newProtocolButtonKey = Key('protocols.today.newProtocol');
  static const logDoseButtonKey = Key('protocols.today.logDose');

  @override
  ConsumerState<ProtocolsTodayBody> createState() => _ProtocolsTodayBodyState();
}

class _ProtocolsTodayBodyState extends ConsumerState<ProtocolsTodayBody> {
  Timer? _dayBoundaryTimer;
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _dayBoundaryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshIfDayChanged(),
    );
    _lifecycleListener = AppLifecycleListener(onResume: _refreshIfDayChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _followTodayDate();
      unawaited(
        ref
            .read(protocolDayControllerProvider.notifier)
            .ensureOtcLibrarySeeded(),
      );
    });
  }

  @override
  void didUpdateWidget(ProtocolsTodayBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localDate != widget.localDate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _followTodayDate();
        }
      });
    }
  }

  @override
  void dispose() {
    _dayBoundaryTimer?.cancel();
    _lifecycleListener?.dispose();
    super.dispose();
  }

  void _followTodayDate() {
    final selected = ref.read(selectedProtocolDayProvider);
    if (selected != widget.localDate) {
      ref.read(selectedProtocolDayProvider.notifier).select(widget.localDate);
    }
  }

  void _refreshIfDayChanged() {
    if (mounted) {
      ref.read(protocolDayControllerProvider.notifier).refreshIfDayChanged();
    }
  }

  void _logDose() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProtocolsLockGate(
          child: CompoundListScreen(protocolDay: widget.localDate),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lockState = ref.watch(protocolsLockControllerProvider).value;
    // Nothing until the lock state is known: never a frame of content ahead
    // of finding out a lock is set.
    if (lockState == null) {
      return const SizedBox.shrink(key: ProtocolsTodayBody.bodyKey);
    }
    if (lockState.isUnavailable || lockState.isLocked) {
      return _TodayLockedPanel(unavailable: lockState.isUnavailable);
    }

    final dayState = ref.watch(protocolDayControllerProvider).value;
    final protocols = ref.watch(protocolListControllerProvider).value ??
        const <ProtocolSummaryRecord>[];
    // Until the selected Protocol Day has caught up with Today's header,
    // show nothing rather than another day's doses under this date.
    if (dayState == null || dayState.day.localDate != widget.localDate) {
      return const SizedBox.shrink(key: ProtocolsTodayBody.bodyKey);
    }
    final day = dayState.day;
    final planned = dayState.plannedDay;
    final showPlanned = planned != null && planned.hasPlanned;
    final isFirstRun = protocols.isEmpty && !showPlanned && day.isEmpty;

    return Column(
      key: ProtocolsTodayBody.bodyKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ReminderPermissionBanner(
          padding: EdgeInsets.only(bottom: AppDimens.dense),
        ),
        if (isFirstRun)
          const _TodayIntro()
        else ...[
          if (showPlanned) _PlannedList(plannedDay: planned),
          if (!day.isEmpty) ...[
            SectionLabel(text: l10n.protocolsLoggedHeading),
            const SizedBox(height: AppDimens.dense),
            GroupedRows(
              key: ProtocolsTodayBody.loggedKey,
              children: [
                for (final dose in day.doses)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.base,
                    ),
                    child: _DoseRow(dose: dose),
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.base),
          ] else if (!showPlanned) ...[
            Text(
              l10n.protocolsNothingToday,
              key: ProtocolsDayView.emptyStateKey,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimens.base),
          ],
        ],
        // On first run the plan is the filled action; afterwards Your
        // protocols below carries New protocol, and logging stays here.
        Wrap(
          spacing: AppDimens.dense,
          runSpacing: AppDimens.dense,
          children: [
            if (isFirstRun)
              FilledButton.icon(
                key: ProtocolsTodayBody.newProtocolButtonKey,
                onPressed: () => openProtocolForm(context, ref),
                icon: const Icon(Icons.add),
                label: Text(l10n.protocolsNewProtocol),
              ),
            OutlinedButton.icon(
              key: ProtocolsTodayBody.logDoseButtonKey,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.textPrimary,
              ),
              onPressed: _logDose,
              icon: const Icon(Icons.medication_outlined),
              label: Text(l10n.protocolsLogDose),
            ),
          ],
        ),
        if (protocols.isNotEmpty) ...[
          const SizedBox(height: AppDimens.base),
          SectionLabel(text: l10n.protocolsYourProtocols),
          const SizedBox(height: AppDimens.dense),
          GroupedRows(
            key: ProtocolsTodayBody.yourProtocolsKey,
            children: [
              for (final protocol in protocols)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.base,
                  ),
                  child: ProtocolRow(protocol: protocol),
                ),
              ListTile(
                key: ProtocolsTodayBody.newProtocolButtonKey,
                minTileHeight: AppDimens.touchTarget,
                leading: const Icon(Icons.add),
                title: Text(l10n.protocolsNewProtocol),
                onTap: () => openProtocolForm(context, ref),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// First run of the tab: what a Protocol is for, in one line. Its actions
/// (New protocol, Log a dose) follow in the tab's one button row.
class _TodayIntro extends StatelessWidget {
  const _TodayIntro();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      key: ProtocolsTodayBody.introKey,
      padding: const EdgeInsets.only(bottom: AppDimens.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.protocolsIntroTitle, style: context.textStyles.h2),
          const SizedBox(height: AppDimens.dense),
          Text(
            l10n.protocolsIntroMessage,
            style: context.textStyles.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The tab's stand-in while Protocols are locked: no Compound or Dose, only
/// the shared unlock form, so a glance at a lent phone shows nothing.
class _TodayLockedPanel extends StatelessWidget {
  const _TodayLockedPanel({required this.unavailable});

  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    return Padding(
      key: ProtocolsTodayBody.lockedKey,
      padding: const EdgeInsets.symmetric(vertical: AppDimens.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.lock_outline, size: 40, color: colors.textSecondary),
          const SizedBox(height: AppDimens.dense),
          Text(
            unavailable
                ? l10n.protocolsLockUnavailableTitle
                : l10n.protocolsLockedTitle,
            textAlign: TextAlign.center,
            style: context.textStyles.h2,
          ),
          const SizedBox(height: AppDimens.base),
          if (unavailable)
            Text(
              l10n.protocolsLockUnavailableMessage,
              textAlign: TextAlign.center,
              style: context.textStyles.body.copyWith(
                color: colors.textSecondary,
              ),
            )
          else
            const ProtocolsUnlockForm(),
        ],
      ),
    );
  }
}

class _ProtocolDayBody extends StatelessWidget {
  const _ProtocolDayBody({required this.day, this.plannedDay});

  final ProtocolDayRecord day;
  final PlannedDay? plannedDay;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final planned = plannedDay;
    final showPlanned = planned != null && planned.hasPlanned;
    final emptyMessage = Text(
      'No doses logged for this day.',
      style: TextStyle(color: colors.textSecondary),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProtocolDayHeader(localDate: day.localDate),
        const _ReminderPermissionBanner(),
        Expanded(
          child: !showPlanned && day.isEmpty
              ? Center(
                  key: ProtocolsDayView.emptyStateKey,
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimens.base),
                    child: emptyMessage,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.base,
                  ),
                  children: [
                    // The Planned list sits at the top of the day, above
                    // the logged Doses, and is hidden when nothing is
                    // planned (D6).
                    if (showPlanned) _PlannedList(plannedDay: planned),
                    if (day.isEmpty)
                      Padding(
                        key: ProtocolsDayView.emptyStateKey,
                        padding: const EdgeInsets.all(AppDimens.base),
                        child: Center(child: emptyMessage),
                      )
                    else
                      Column(
                        key: ProtocolsDayView.doseListKey,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var index = 0;
                              index < day.doses.length;
                              index += 1) ...[
                            if (index > 0)
                              Divider(height: 1, color: colors.divider),
                            _DoseRow(dose: day.doses[index]),
                          ],
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// "Reminders are off on this device" with "Allow" (CUJ 12): shown while a
/// Protocol has reminders on, the device switch is on, and this phone has
/// never been asked for the notification permission, so it schedules
/// none. "Allow" asks through the one permission path (D5), and the
/// reconciler runs on the answer.
class _ReminderPermissionBanner extends ConsumerWidget {
  const _ReminderPermissionBanner({
    this.padding = const EdgeInsets.fromLTRB(
      AppDimens.base,
      0,
      AppDimens.base,
      AppDimens.dense,
    ),
  });

  /// The day view pads it to its edges; Today's list already has gutters.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(protocolReminderStatusProvider).value;
    if (status == null || !status.needsPermission) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final l10n = context.l10n;

    return Padding(
      key: ProtocolsDayView.reminderPermissionBannerKey,
      padding: padding,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.cardMd,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.base,
            vertical: AppDimens.dense / 2,
          ),
          child: ProtocolReminderNotice(
            message: l10n.protocolRemindersBanner,
            actionLabel: l10n.protocolRemindersAllow,
            actionKey: ProtocolsDayView.reminderPermissionAllowKey,
            onAction: () => unawaited(
              ref.read(protocolReminderSchedulerProvider).requestPermission(),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Planned list (D6): one row per planned dose of the day, grouped under
/// its Protocol, each with the Compound, the planned time (or "Any time"),
/// the amount, and one text label. Color is never the only signal: every
/// label is a word, and its icon only echoes it.
///
/// * Today: rows read "Logged" or "Pending"; tapping a "Pending" row opens
///   the log sheet, and "Log all planned" logs every due unfilled row in one
///   Batch.
/// * A past day: rows read "Logged" or "Not logged"; tapping a "Not logged"
///   row opens the log sheet on that date. There is no bulk action.
/// * On either, tapping a "Logged" row opens the Dose that fills it for
///   edit, never a new log: a second Dose of something already taken is the
///   duplicate the row exists to prevent.
/// * A future day: rows show their times and amounts only, with no label
///   and no log action.
class _PlannedList extends ConsumerStatefulWidget {
  const _PlannedList({required this.plannedDay});

  final PlannedDay plannedDay;

  @override
  ConsumerState<_PlannedList> createState() => _PlannedListState();
}

class _PlannedListState extends ConsumerState<_PlannedList> {
  /// True while "Log all planned" is writing. The button is disabled until
  /// the call finishes, so a second tap cannot log the same doses again.
  bool _loggingAll = false;

  Future<void> _logAllPlanned() async {
    if (_loggingAll) {
      return;
    }
    setState(() => _loggingAll = true);
    try {
      await ref.read(protocolDayControllerProvider.notifier).logAllPlanned();
    } finally {
      if (mounted) {
        setState(() => _loggingAll = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final plannedDay = widget.plannedDay;
    final groups = plannedDay.groups;
    final anyPending = groups.any(
      (group) =>
          group.rows.any((row) => row.status == PlannedRowStatus.pending),
    );

    return Padding(
      key: ProtocolsDayView.plannedListKey,
      padding: const EdgeInsets.only(bottom: AppDimens.base),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.cardMd,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < groups.length; index += 1) ...[
                if (index > 0) const SizedBox(height: AppDimens.dense),
                _PlannedGroup(plannedDay: plannedDay, group: groups[index]),
              ],
              // Only today's Protocol Day offers the bulk action (D6), and
              // only while something on it is still unfilled.
              if (plannedDay.isToday && anyPending) ...[
                const SizedBox(height: AppDimens.dense),
                SizedBox(
                  height: AppDimens.touchTarget,
                  child: FilledButton(
                    key: ProtocolsDayView.logAllPlannedButtonKey,
                    style: FilledButton.styleFrom(backgroundColor: colors.save),
                    onPressed:
                        _loggingAll ? null : () => unawaited(_logAllPlanned()),
                    child: Text(l10n.plannedListLogAll),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlannedGroup extends StatelessWidget {
  const _PlannedGroup({required this.plannedDay, required this.group});

  final PlannedDay plannedDay;
  final PlannedRowGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      key: ProtocolsDayView.plannedGroupKey(group.protocol.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          group.protocol.name,
          style: context.textStyles.label.copyWith(color: colors.textSecondary),
        ),
        for (final row in group.rows)
          _PlannedRowTile(
            plannedDay: plannedDay,
            protocol: group.protocol,
            row: row,
          ),
      ],
    );
  }
}

class _PlannedRowTile extends ConsumerWidget {
  const _PlannedRowTile({
    required this.plannedDay,
    required this.protocol,
    required this.row,
  });

  final PlannedDay plannedDay;
  final ProtocolOptionRecord protocol;
  final PlannedRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final compound = plannedDay.compounds[row.compoundId];
    final plannedTime = row.plannedLocalTime;
    final timeLabel = plannedTime == null
        ? l10n.plannedListAnyTime
        : planTimeOfDay(plannedTime).format(context);
    final amountLabel = plannedAmountLabel(row.amount);
    final detail = <String>[
      if (amountLabel.isNotEmpty) amountLabel,
      timeLabel,
    ].join(' · ');
    // A future day has no log action (D6); nor can a row whose Compound
    // row is missing, which no validated plan holds. A "Logged" row opens
    // the Dose that fills it for edit instead.
    final VoidCallback? onTap;
    if (row.status == PlannedRowStatus.logged) {
      final fillingDose = _fillingDose();
      onTap = fillingDose == null
          ? null
          : () => unawaited(
                showLogDoseSheet(context, LogDoseSheet.edit(dose: fillingDose)),
              );
    } else if (!plannedDay.isFuture && compound != null) {
      onTap = () => unawaited(_openLogSheet(context, compound));
    } else {
      onTap = null;
    }

    return InkWell(
      key: ProtocolsDayView.plannedRowKey(
        row.protocolId,
        row.compoundId,
        row.slot,
      ),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.dense / 2),
          child: Row(
            children: [
              Expanded(
                child: _DayRowText(
                  title: compound?.name ?? row.compoundId,
                  detail: detail,
                ),
              ),
              _PlannedRowLabel(status: row.status),
            ],
          ),
        ),
      ),
    );
  }

  /// The Dose that fills this row's slot (its `doseId` in the day's
  /// `fills`), found in the same emission's [PlannedDay.day], or null when
  /// the slot is unfilled. Both come from one read, so a filled slot's Dose
  /// is always there.
  DoseRecord? _fillingDose() {
    for (final status in plannedDay.dayStatuses) {
      if (status.compoundId != row.compoundId ||
          status.localDate != plannedDay.localDate) {
        continue;
      }
      for (final fill in status.fills) {
        if (fill.slot != row.slot || fill.protocolId != row.protocolId) {
          continue;
        }
        final doseId = fill.doseId;
        if (doseId == null) {
          return null;
        }
        for (final dose in plannedDay.day.doses) {
          if (dose.id == doseId) {
            return dose;
          }
        }
        return null;
      }
    }
    return null;
  }

  /// Opens the log sheet for this row (D6): prefilled with the planned
  /// amount, unit and route, tagged with the row's Protocol, on the row's
  /// date. The sheet decides the time: now on today; on a past day the
  /// planned time on that date, or 12:00 for an untimed row.
  Future<void> _openLogSheet(
    BuildContext context,
    CompoundRecord compound,
  ) async {
    final plannedTime = row.plannedLocalTime;
    await showLogDoseSheet(
      context,
      LogDoseSheet(
        compound: compound,
        initialDate: plannedDay.localDate,
        initialTime: plannedTime == null ? null : planTimeOfDay(plannedTime),
        plannedAmount: row.amount,
        plannedRoute: row.amount.route,
        protocol: protocol,
      ),
    );
  }
}

/// The one label of a Planned list row, as a word with an icon echoing it.
/// A future day's rows ([PlannedRowStatus.none]) have no label at all (D6),
/// so this is the one place that decides whether a label shows.
class _PlannedRowLabel extends StatelessWidget {
  const _PlannedRowLabel({required this.status});

  final PlannedRowStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    if (status == PlannedRowStatus.none) {
      return const SizedBox.shrink();
    }
    final (IconData icon, Color iconColor, String label) = switch (status) {
      PlannedRowStatus.logged => (
          Icons.check_circle,
          colors.save,
          l10n.plannedListRowLogged,
        ),
      PlannedRowStatus.pending => (
          Icons.schedule,
          colors.textSecondary,
          l10n.plannedListRowPending,
        ),
      PlannedRowStatus.notLogged => (
          Icons.remove_circle_outline,
          colors.textSecondary,
          l10n.plannedListRowNotLogged,
        ),
      PlannedRowStatus.none => throw StateError('A future row has no label.'),
    };

    return StatusWordLabel(icon: icon, iconColor: iconColor, label: label);
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
    final dateLabel = DateFormat.yMMMMEEEEd().format(
      localDate.toLocalDateTime(),
    );

    return GestureDetector(
      key: ProtocolsDayView.dayHeaderKey,
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final controller = ref.read(protocolDayControllerProvider.notifier);
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
    // The Dose's clock where it was taken (D2, D6), read from the one helper
    // the edit sheet reads too, so a row and its edit sheet agree and a Dose
    // logged abroad shows the time it was taken there.
    final timeLabel = DateFormat.jm().format(dose.clock);
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
          child: _DayRowText(title: dose.compoundName, detail: detail),
        ),
      ),
    );
  }

  Future<void> _openDoseEditor(BuildContext context) {
    return showLogDoseSheet(context, LogDoseSheet.edit(dose: dose));
  }
}

/// The two lines of a Protocol Day row: the Compound's name in bold, and its
/// detail line below. Shared by the Planned list's rows and the logged Doses,
/// so the same Compound reads the same in both.
class _DayRowText extends StatelessWidget {
  const _DayRowText({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(detail, style: TextStyle(color: colors.textSecondary)),
      ],
    );
  }
}

/// Shows [sheet] the one way every caller does: a scroll-controlled bottom
/// sheet lifted above the keyboard.
Future<void> showLogDoseSheet(BuildContext context, LogDoseSheet sheet) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: sheet,
    ),
  );
}

/// The Track-tab analog for logging a `Dose` against a KNOWN `Compound`
/// (PROTOCOLS.md §5): an amount stepper (`components.stepper-button`,
/// `numeral-hero` readout), unit + route chips drawn ONLY from the curated
/// registries (off-registry is impossible by construction, since
/// the chips are generated from the enums themselves), and a date and a time
/// with pickers to adjust them (CUJ 7).
///
/// **The time default (D6).** On today's Protocol Day the time is now. On a
/// past day ([initialDate] before today) it is [initialTime] on that date,
/// or 12:00 when there is none. A day after today is treated as today: the
/// sheet never defaults to a moment that hasn't happened. The time is never
/// prefilled from the last Dose, because that default recorded times that
/// never happened.
///
/// Always logs against an existing `Compound` — Compound creation lives
/// exclusively in `CompoundEditorSheet` — so opening this sheet for
/// a Compound and tapping Save is the ≤2-tap "repeat dose" path. [lastDose] is
/// the Compound's most recently logged `Dose` (already resolved by the
/// caller, e.g. via `ProtocolDayController.lastDoseFor`): its
/// amount/unit/route seed the draft on top of `DoseSnapshotDraft.fromCompound`
/// when present; a Compound with no prior Dose falls back to its default
/// unit/route. Opened from a Planned list row, [plannedAmount],
/// [plannedRoute] and [protocol] seed the draft instead: the row's planned
/// amount, unit and route, tagged with its Protocol. Local-first: `Save`
/// confirms within one frame — no spinner, no network on the logging path.
///
/// The [LogDoseSheet.edit] constructor reuses this SAME entry surface as the
/// Protocol Day review surface's tap-to-edit/delete: it seeds every
/// field straight from the tapped [DoseRecord] (never a live `Compound`
/// lookup — a Dose is self-describing, PROTOCOLS.md §1.1), preserves the
/// Dose's already-frozen local date/timezone/provenance untouched while its
/// time stands, and lets its date and time change. It shows and edits them at
/// the Dose's frozen UTC offset (D2, D6), as the day's Dose rows show them:
/// a changed time is read at that offset, which the Dose keeps, and only its
/// local date is frozen again. A Dose with a null offset reads in the
/// device's zone. It adds a Delete action that routes
/// through `ProtocolsRepository.deleteDose` (tombstone + undo-recoverable, no
/// cascade) — never bypassing the Activity Log.
class LogDoseSheet extends ConsumerStatefulWidget {
  const LogDoseSheet({
    super.key,
    required this.compound,
    this.lastDose,
    this.initialDate,
    this.initialTime,
    this.plannedAmount,
    this.plannedRoute,
    this.protocol,
  }) : editingDose = null;

  const LogDoseSheet.edit({super.key, required DoseRecord dose})
      : compound = null,
        lastDose = null,
        initialDate = null,
        initialTime = null,
        plannedAmount = null,
        plannedRoute = null,
        protocol = null,
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

  /// The Protocol Day the sheet logs on, or null for today. Decides the time
  /// default with [initialTime] (see the class docs).
  final ProtocolDayDate? initialDate;

  /// The time to default to on a past [initialDate]: a Planned list row's
  /// planned time. Null means 12:00 there; ignored on today.
  final TimeOfDay? initialTime;

  /// A Planned list row's planned amount and unit, which seed the draft over
  /// the last Dose's. Only complete amounts seed it.
  final PlanAmount? plannedAmount;

  /// A Planned list row's planned route, which seeds the draft over the last
  /// Dose's.
  final DoseRoute? plannedRoute;

  /// The Protocol a Planned list row belongs to, preselected as the Dose's
  /// tag. Null logs an untagged Dose by default.
  final ProtocolOptionRecord? protocol;

  static const amountFieldKey = Key('protocols.logDose.amount');
  static const decrementButtonKey = Key('protocols.logDose.decrement');
  static const incrementButtonKey = Key('protocols.logDose.increment');
  static const timeFieldKey = Key('protocols.logDose.time');
  static const dateFieldKey = Key('protocols.logDose.date');

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

  /// The date and clock time the fields show. In edit mode with a frozen
  /// offset ([_offsetMinutes]), a UTC `DateTime` whose fields are the clock
  /// at that offset; otherwise a device-local `DateTime`. [_instant] is the
  /// moment it names.
  late DateTime _tookAt;

  /// The edited Dose's frozen UTC offset, or null when logging a new Dose or
  /// editing one logged before offsets were recorded.
  late final int? _offsetMinutes;

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
    _offsetMinutes = widget.editingDose?.timezoneOffsetMinutes;
    _tookAt = _seedTookAt();
    _protocolId = widget.editingDose?.protocolId ?? widget.protocol?.id;
    _protocolName = widget.editingDose?.protocolName ?? widget.protocol?.name;
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
  /// PROTOCOLS.md §5), and a Planned list row's planned amount/unit/route
  /// overlay that (D6). A Compound with no prior Dose and no plan keeps the
  /// Compound's defaults (first-time fallback).
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
    final planned = widget.plannedAmount;
    final plannedValue = planned?.amountValue;
    final plannedEntered = planned?.amountEntered;
    final hasPlannedAmount = plannedValue != null && plannedEntered != null;
    return DoseSnapshotDraft.fromCompound(
      compound: compound,
      amountValue: hasPlannedAmount ? plannedValue : lastDose?.amountValue ?? 1,
      amountEntered:
          hasPlannedAmount ? plannedEntered : lastDose?.amountEntered ?? '1',
      unit: planned?.unit ?? lastDose?.unit ?? compound.defaultUnit,
      route: widget.plannedRoute ?? lastDose?.route ?? compound.defaultRoute,
      tookAt: _now(),
    );
  }

  DateTime _now() => ref.read(protocolsClockProvider)().toLocal();

  /// A clock reading for the fields, in [_tookAt]'s form: at the edited
  /// Dose's frozen offset when it has one, else in the device's zone.
  DateTime _clock(int year, int month, int day, int hour, int minute) {
    return _offsetMinutes == null
        ? DateTime(year, month, day, hour, minute)
        : DateTime.utc(year, month, day, hour, minute);
  }

  /// The moment [_tookAt] names: its clock read at the frozen offset, or in
  /// the device's zone.
  DateTime get _instant {
    final offset = _offsetMinutes;
    return offset == null
        ? _tookAt
        : _tookAt.subtract(Duration(minutes: offset));
  }

  /// The dose instant's default (D6). In edit mode it seeds from the Dose
  /// being edited (its own date, not "today"), so an untouched Save cannot
  /// silently move it. Otherwise: now on today; on a past [initialDate], its
  /// [initialTime], or 12:00 when there is none. A day after today reads as
  /// today, so the default is never a moment still to come.
  DateTime _seedTookAt() {
    final editingDose = widget.editingDose;
    if (editingDose != null) {
      return editingDose.clock;
    }
    final now = _now();
    final date = widget.initialDate;
    if (date == null ||
        date.compareTo(ProtocolDayDate.fromDateTime(now)) >= 0) {
      return now;
    }
    final time = widget.initialTime ?? const TimeOfDay(hour: 12, minute: 0);
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
                    style: context.textStyles.h1.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (editingDose != null)
                  IconButton(
                    key: LogDoseSheet.deleteButtonKey,
                    tooltip: 'Delete dose',
                    onPressed: _saving ? null : _confirmDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      color: colors.textSecondary,
                    ),
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
            _MomentField(
              fieldKey: LogDoseSheet.dateFieldKey,
              icon: Icons.calendar_today_outlined,
              label: context.l10n.logDoseDateLabel,
              value: DateFormat.yMMMd().format(_tookAt),
              onTap: _pickDate,
            ),
            _MomentField(
              fieldKey: LogDoseSheet.timeFieldKey,
              icon: Icons.access_time,
              label: 'Time',
              value: TimeOfDay.fromDateTime(_tookAt).format(context),
              onTap: _pickTime,
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

  /// Moves the Dose to another date, keeping its time of day (CUJ 7). The
  /// picker ends at today, or at the Dose's own date when that is later, so
  /// it never offers a day that hasn't happened. "Today" is read in the same
  /// frame as the fields: at the edited Dose's frozen offset when it has one,
  /// else in the device's zone. Read in the device's zone, a Dose logged far
  /// from it could be moved to a day that hasn't happened where it was taken,
  /// or kept from a day that has.
  Future<void> _pickDate() async {
    final current = DateTime(_tookAt.year, _tookAt.month, _tookAt.day);
    final now = clockAtOffset(_now(), _offsetMinutes);
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: current.isAfter(today) ? current : today,
    );
    if (picked != null && mounted) {
      setState(() {
        _tookAt = _clock(
          picked.year,
          picked.month,
          picked.day,
          _tookAt.hour,
          _tookAt.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_tookAt),
    );
    if (picked != null && mounted) {
      setState(() {
        _tookAt = _clock(
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
        // The Dose's own frozen compound identity and provenance carry over
        // untouched. While its moment stands, so do its frozen timezone and
        // local date: an edit NEVER re-derives them from the device's
        // current timezone. A new date or time is read at the Dose's frozen
        // offset, so both are left out: the repository keeps the offset and
        // label, and freezes the local date again from the new time (D6).
        final momentChanged = _instant.toUtc() != editingDose.tookAt.toUtc();
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
            tookAt: _instant,
            timezone: momentChanged ? null : editingDose.timezone,
            localDate: momentChanged ? null : editingDose.localDate,
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
            tookAt: _instant,
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

/// One labelled row of the log sheet that opens a picker: the date or the
/// time. A full-width 48 dp target.
class _MomentField extends StatelessWidget {
  const _MomentField({
    required this.fieldKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final Key fieldKey;
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      key: fieldKey,
      borderRadius: AppRadii.cardMd,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Row(
          children: [
            Icon(icon, color: colors.textSecondary),
            const SizedBox(width: AppDimens.dense),
            Expanded(
              child: Text(
                label,
                style: context.textStyles.body.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            Text(
              value,
              style: context.textStyles.body.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
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
