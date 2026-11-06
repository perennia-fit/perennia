import 'package:flutter/material.dart';

import '../../../domain/analytics/progress_measure.dart';
import '../../../domain/training/training_day.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../analytics/widgets/exercise_overview_screen.dart';
import '../../settings/repositories/settings_repository.dart';
import '../controllers/progress_controller.dart';
import 'progress_format.dart';

/// One New Best: the Trophy Gold glyph beside its exercise, value and date,
/// so gold is never the only signal. A tap opens Exercise Overview.
///
/// [today] is what the date reads relative to. Null hides the date, for a
/// list where every row is from the same Workout.
class NewBestRow extends StatelessWidget {
  const NewBestRow({
    super.key,
    required this.row,
    required this.unitSystem,
    this.today,
  });

  /// The row's tap target, keyed by the New Best's exercise and Workout.
  static Key rowKey(NewBest best) =>
      Key('progress.newBests.row.${best.exerciseId}.${best.workoutId}');

  final ProgressNewBestRow row;
  final UnitSystem unitSystem;
  final TrainingDayDate? today;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final best = row.best;
    final today = this.today;
    final value = formatProgressValue(
      best.measure,
      best.value,
      unitSystem,
      l10n,
    );
    return InkWell(
      key: rowKey(best),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExerciseOverviewScreen(exerciseId: best.exerciseId),
          ),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.dense / 2),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Icon(Icons.emoji_events_outlined, color: colors.record),
              ),
              const SizedBox(width: AppDimens.dense),
              // A name has no length limit: two lines, then an ellipsis.
              Expanded(
                child: Text(
                  l10n.progressNewBestRow(
                    row.exerciseName,
                    best.measure == ProgressMeasureKind.estimatedOneRepMax
                        ? l10n.progressNewBestEstimated(value)
                        : value,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.body.copyWith(
                    color: colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (today != null) ...[
                const SizedBox(width: AppDimens.dense),
                Text(
                  formatProgressDate(
                    best.localDate,
                    today,
                    Localizations.localeOf(context).toString(),
                  ),
                  style: context.textStyles.caption.copyWith(
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
