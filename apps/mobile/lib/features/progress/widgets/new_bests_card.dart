import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/analytics/progress_measure.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../analytics/widgets/exercise_overview_screen.dart';
import '../controllers/progress_controller.dart';
import 'progress_card.dart';
import 'progress_format.dart';

/// The period's most recent New Bests (D4, D8 card 5), each with the
/// Trophy Gold glyph beside its exercise, value and date, so gold is never
/// the only signal. The title counts every New Best in the period.
class NewBestsCard extends ConsumerWidget {
  const NewBestsCard({super.key});

  /// A row, keyed by the New Best's exercise and Workout.
  static Key rowKey(NewBest best) =>
      Key('progress.newBests.row.${best.exerciseId}.${best.workoutId}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(progressNewBestsProvider);
    final data = state.value;
    if (state.hasError || data == null) {
      return ProgressCard.pending(
        title: l10n.progressNewBestsTitle,
        failed: state.hasError,
      );
    }
    if (data.rows.isEmpty) {
      return ProgressCard.empty(
        title: l10n.progressNewBestsTitle,
        message: l10n.progressNewBestsEmpty,
      );
    }
    return ProgressCard(
      title: l10n.progressNewBestsTitleCount(data.count),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in data.rows) _Row(row: row, data: data),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.data});

  final ProgressNewBestRow row;
  final ProgressNewBests data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final best = row.best;
    final value = formatProgressValue(
      best.measure,
      best.value,
      data.unitSystem,
      l10n,
    );
    return InkWell(
      key: NewBestsCard.rowKey(best),
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
              const SizedBox(width: AppDimens.dense),
              Text(
                formatProgressDate(
                  best.localDate,
                  data.today,
                  Localizations.localeOf(context).toString(),
                ),
                style: context.textStyles.caption.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
