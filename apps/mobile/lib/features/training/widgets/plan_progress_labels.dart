/// The two plan-progress labels the Workout screen's exercise cards and the
/// Navigation Panel's rows share, so both show the same text: an exercise's
/// count against its plan, and **Now** on the Current Exercise. The design
/// record is `docs/designs/plan-guided-logging.md`.
library;

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';

/// A Workout Exercise's progress against its plan, the same text on its
/// Workout screen card and its Navigation Panel row: "No sets" with no Sets;
/// a check icon and "Done" when it has Sets and no Planned Set; otherwise
/// "*performed*/*total* sets", spoken "*performed* of *total* sets". The
/// state is always in the text, never only in the icon or a colour.
class ExerciseProgressCount extends StatelessWidget {
  const ExerciseProgressCount({
    super.key,
    required this.performed,
    required this.planned,
    this.style,
  });

  final int performed;
  final int planned;

  /// Defaults to the ambient text style (a ListTile subtitle's, say).
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = performed + planned;
    if (total == 0) {
      return Text(l10n.workoutNoSets, style: style);
    }
    if (planned == 0) {
      final color = style?.color ?? DefaultTextStyle.of(context).style.color;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: AppDimens.legendIcon, color: color),
          const SizedBox(width: AppDimens.dense / 3),
          Flexible(child: Text(l10n.workoutExerciseDone, style: style)),
        ],
      );
    }
    return Text(
      l10n.workoutPerformedSetFraction(performed, total),
      semanticsLabel: l10n.workoutPerformedSetsOfTotal(performed, total),
      style: style,
    );
  }
}

/// **Now**, on the Current Exercise (or its group's first card or row) of
/// an open Workout: text in the `label` style on a Signal Cyan (primary)
/// fill. Its ink is on-primary rather than cyan text on the card, because
/// cyan text on the light theme's white card falls below AA contrast.
class CurrentExerciseLabel extends StatelessWidget {
  const CurrentExerciseLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: AppRadii.chipFull,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.dense / 2),
        child: Text(
          context.l10n.workoutCurrentExercise,
          style: context.textStyles.label.copyWith(
            color: colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }
}
