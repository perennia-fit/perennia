import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/training/training_day.dart';
import '../../../domain/training/training_progress.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../routine_plans/widgets/routine_plan_list_screen.dart';
import '../controllers/progress_controller.dart';
import 'progress_card.dart';

/// This week against the weekly Routines (D1, D8 card 1): one column per day
/// with its Training Day Status icon, the counted statuses, a legend that
/// names every status shown, and which Routines were compared. Statuses and
/// counts only, never a score.
class ThisWeekCard extends ConsumerWidget {
  const ThisWeekCard({super.key});

  static const daysKey = Key('progress.thisWeek.days');
  static const summaryKey = Key('progress.thisWeek.summary');
  static const comparedKey = Key('progress.thisWeek.compared');
  static const routinesButtonKey = Key('progress.thisWeek.routines');

  static Key dayKey(TrainingDayDate date) =>
      Key('progress.thisWeek.day.${date.storageValue}');

  static Key legendKey(TrainingDayStatus status) =>
      Key('progress.thisWeek.legend.${status.wireName}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final title = l10n.progressThisWeekTitle;
    final state = ref.watch(progressThisWeekProvider);
    if (state.hasError) {
      return ProgressCard.empty(
        title: title,
        message: l10n.progressCardUnavailable,
      );
    }
    final data = state.value;
    if (data == null) {
      return ProgressCard.loading(title: title);
    }
    final routines = ProgressCardAction(
      key: routinesButtonKey,
      label: l10n.progressRoutinesAction,
      onPressed: () {
        Navigator.of(context).pushNamed(RoutinePlanListScreen.routeName);
      },
    );
    if (data.isEmpty) {
      return ProgressCard.empty(
        title: title,
        message: l10n.progressThisWeekEmpty,
        emptyAction: routines,
      );
    }

    final colors = context.colors;
    final secondary = context.textStyles.caption.copyWith(
      color: colors.textSecondary,
    );
    final present = <TrainingDayStatus>{
      for (final day in data.week.days) day.status,
    };
    final compared = _comparedLine(l10n, data);
    return ProgressCard(
      title: title,
      action: routines,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            key: daysKey,
            container: true,
            label: _daysSemanticsLabel(context, data.week),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  for (final day in data.week.days)
                    Expanded(
                      child: _DayColumn(
                        key: dayKey(day.localDate),
                        day: day,
                        isToday: day.localDate == data.today,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppDimens.dense),
          Text(
            _summary(l10n, data.counts),
            key: summaryKey,
            style: context.textStyles.body.copyWith(
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppDimens.dense / 2),
          Wrap(
            spacing: AppDimens.dense,
            runSpacing: AppDimens.dense / 2,
            children: [
              for (final status in TrainingDayStatus.values)
                if (present.contains(status))
                  Row(
                    key: legendKey(status),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (trainingDayStatusIcon(status) case final icon?) ...[
                        Icon(icon, size: 16, color: colors.textSecondary),
                        const SizedBox(width: AppDimens.dense / 3),
                      ],
                      Text(trainingDayStatusLabel(l10n, status),
                          style: secondary),
                    ],
                  ),
            ],
          ),
          if (compared != null) ...[
            const SizedBox(height: AppDimens.dense / 2),
            Text(compared, key: comparedKey, style: secondary),
          ],
        ],
      ),
    );
  }

  static String _summary(AppLocalizations l10n, TrainingWeekCounts counts) {
    final parts = <String>[
      if (counts.done > 0) l10n.progressCountDone(counts.done),
      if (counts.partlyDone > 0)
        l10n.progressCountPartlyDone(counts.partlyDone),
      if (counts.doneDifferently > 0)
        l10n.progressCountDoneDifferently(counts.doneDifferently),
      if (counts.notDone > 0) l10n.progressCountNotDone(counts.notDone),
      if (counts.trained > 0) l10n.progressCountTrained(counts.trained),
    ];
    return parts.isEmpty
        ? l10n.progressThisWeekNothingLogged
        : parts.join(progressSeparator);
  }

  static String? _comparedLine(AppLocalizations l10n, ProgressThisWeek data) {
    final names = data.comparedRoutineNames.join(progressSeparator);
    return switch ((names.isNotEmpty, data.hasRotatingRoutine)) {
      (true, false) => l10n.progressThisWeekComparing(names),
      (true, true) => l10n.progressThisWeekComparingWeeklyOnly(names),
      (false, true) => l10n.progressThisWeekWeeklyOnly,
      (false, false) => null,
    };
  }

  static String _daysSemanticsLabel(BuildContext context, TrainingWeek week) {
    final l10n = context.l10n;
    final weekday = DateFormat.EEEE(Localizations.localeOf(context).toString());
    return l10n.progressThisWeekSemantics(
      week.days
          .map(
            (day) => l10n.progressThisWeekDaySemantics(
              weekday.format(day.localDate.toLocalDateTime()),
              l10n.progressStatusSpoken(day.status.wireName),
            ),
          )
          .join(', '),
    );
  }
}

/// The separator between the parts of a Progress summary line.
const String progressSeparator = ' · ';

/// The icon a status is drawn with; Rest and No plan have none (D8).
IconData? trainingDayStatusIcon(TrainingDayStatus status) {
  return switch (status) {
    TrainingDayStatus.done => Icons.check_circle,
    TrainingDayStatus.partlyDone => Icons.timelapse,
    TrainingDayStatus.doneDifferently => Icons.swap_horiz,
    TrainingDayStatus.notDone => Icons.radio_button_unchecked,
    TrainingDayStatus.pending => Icons.schedule,
    TrainingDayStatus.planned => Icons.event,
    TrainingDayStatus.trained => Icons.add_circle_outline,
    TrainingDayStatus.rest || TrainingDayStatus.noPlan => null,
  };
}

String trainingDayStatusLabel(AppLocalizations l10n, TrainingDayStatus status) {
  return switch (status) {
    TrainingDayStatus.done => l10n.progressStatusDone,
    TrainingDayStatus.partlyDone => l10n.progressStatusPartlyDone,
    TrainingDayStatus.doneDifferently => l10n.progressStatusDoneDifferently,
    TrainingDayStatus.notDone => l10n.progressStatusNotDone,
    TrainingDayStatus.pending => l10n.progressStatusPending,
    TrainingDayStatus.planned => l10n.progressStatusPlanned,
    TrainingDayStatus.trained => l10n.progressStatusTrained,
    TrainingDayStatus.rest => l10n.progressStatusRest,
    TrainingDayStatus.noPlan => l10n.progressStatusNoPlan,
  };
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({super.key, required this.day, required this.isToday});

  final TrainingWeekDay day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final locale = Localizations.localeOf(context).toString();
    final date = day.localDate.toLocalDateTime();
    final icon = trainingDayStatusIcon(day.status);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: isToday
            ? Border.all(color: colors.textPrimary)
            : Border.all(color: Colors.transparent),
        borderRadius: const BorderRadius.all(AppRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: AppDimens.dense / 3),
        child: Column(
          children: [
            Text(
              DateFormat('EEEEE', locale).format(date),
              style: context.textStyles.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
            Text(
              '${day.localDate.day}',
              style: context.textStyles.label.copyWith(
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(
              height: AppDimens.touchTarget,
              child: Center(
                child: icon == null
                    ? null
                    : Icon(icon, size: 24, color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
