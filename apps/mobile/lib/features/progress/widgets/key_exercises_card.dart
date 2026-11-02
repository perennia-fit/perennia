import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/analytics/progress_measure.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../analytics/widgets/exercise_overview_screen.dart';
import '../../settings/repositories/settings_repository.dart';
import '../controllers/progress_controller.dart';
import 'progress_card.dart';
import 'progress_format.dart';
import 'progress_sparkline.dart';

/// The Favorites' Progress Measures (D4, D8 card 4): a two-column grid of
/// tiles, each with the period's points, its best and one comparison line
/// against the best before the period. New Bests are hollow rings, and the
/// tile says so in words, so the ring is never the only signal. The app has
/// no standalone exercise list to open, so the card has no trailing button.
class KeyExercisesCard extends ConsumerWidget {
  const KeyExercisesCard({super.key});

  static Key tileKey(String exerciseId) =>
      Key('progress.keyExercises.tile.$exerciseId');
  static Key bestKey(String exerciseId) =>
      Key('progress.keyExercises.best.$exerciseId');
  static Key comparisonKey(String exerciseId) =>
      Key('progress.keyExercises.comparison.$exerciseId');
  static Key sparklineKey(String exerciseId) =>
      Key('progress.keyExercises.sparkline.$exerciseId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final title = l10n.progressKeyExercisesTitle;
    final state = ref.watch(progressKeyExercisesProvider);
    final data = state.value;
    if (state.hasError || data == null) {
      return ProgressCard.pending(title: title, failed: state.hasError);
    }
    if (!data.hasFavorites) {
      return ProgressCard.empty(
        title: title,
        message: l10n.progressKeyExercisesEmpty,
      );
    }
    if (data.tiles.isEmpty) {
      return ProgressCard.empty(
        title: title,
        message: l10n.progressKeyExercisesNoCharted,
      );
    }
    const gap = SizedBox.square(dimension: AppDimens.dense);
    return ProgressCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < data.tiles.length; index += 2) ...[
            if (index > 0) gap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Tile(tile: data.tiles[index], data: data)),
                gap,
                Expanded(
                  child: index + 1 < data.tiles.length
                      ? _Tile(tile: data.tiles[index + 1], data: data)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.data});

  final ProgressKeyExercise tile;
  final ProgressKeyExercises data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final locale = Localizations.localeOf(context).toString();
    final best = tile.periodBest.best;
    final caption = context.textStyles.caption.copyWith(
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final measureLabel = progressMeasureLabel(tile.measure, l10n);
    final bestLine = best == null
        ? null
        : l10n.progressBest(
            formatProgressValue(
              tile.measure,
              best.value,
              data.unitSystem,
              l10n,
            ),
          );
    final comparison = best == null
        ? null
        : _comparisonLine(
            l10n,
            tile.measure,
            best.value,
            tile.periodBest.bestBefore,
            data.unitSystem,
          );
    final latestNewBest =
        tile.points.reversed.where((point) => point.isNewBest).firstOrNull;
    final label = <String>[
      tile.name,
      measureLabel,
      if (best == null) l10n.progressKeyExercisesNoSessions,
      if (bestLine != null) bestLine,
      if (comparison != null) comparison,
      if (latestNewBest != null)
        l10n.progressNewBestOn(
          formatProgressDate(latestNewBest.localDate, data.today, locale),
        ),
    ].join(', ');

    return Semantics(
      container: true,
      button: true,
      label: label,
      child: InkWell(
        key: KeyExercisesCard.tileKey(tile.exerciseId),
        borderRadius: AppRadii.cardMd,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ExerciseOverviewScreen(exerciseId: tile.exerciseId),
            ),
          );
        },
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDimens.touchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppDimens.dense / 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A name has no length limit: two lines, then an ellipsis,
                  // so a long one never overflows its column.
                  Text(
                    tile.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.body.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(measureLabel, style: caption),
                  const SizedBox(height: AppDimens.dense / 3),
                  if (best == null)
                    Text(l10n.progressKeyExercisesNoSessions, style: caption)
                  else ...[
                    SizedBox(
                      key: KeyExercisesCard.sparklineKey(tile.exerciseId),
                      height: AppDimens.progressSparklineHeight,
                      child: ProgressSparkline(
                        points: <ProgressSparklinePoint>[
                          for (final point in tile.points)
                            ProgressSparklinePoint(
                              x: point.startedAt,
                              y: point.value,
                            ),
                        ],
                        markedIndexes: <int>{
                          for (final (index, point) in tile.points.indexed)
                            if (point.isNewBest) index,
                        },
                        pointColor: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppDimens.dense / 3),
                    Text(
                      bestLine!,
                      key: KeyExercisesCard.bestKey(tile.exerciseId),
                      style: context.textStyles.body.copyWith(
                        color: colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      comparison!,
                      key: KeyExercisesCard.comparisonKey(tile.exerciseId),
                      style: caption,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// D8's comparison line for the period's [best] against [bestBefore].
  /// Lower-is-better measures say "faster" or "shorter" in words, never an
  /// arrow, and no line is colored.
  static String _comparisonLine(
    AppLocalizations l10n,
    ProgressMeasureKind measure,
    double best,
    double? bestBefore,
    UnitSystem unitSystem,
  ) {
    if (bestBefore == null) {
      return l10n.progressComparisonFirst;
    }
    if (best == bestBefore) {
      return l10n.progressComparisonSame;
    }
    if (!measure.betterIs.isBetter(best, bestBefore)) {
      return l10n.progressComparisonBestBefore(
        formatProgressValue(measure, bestBefore, unitSystem, l10n),
      );
    }
    final difference = formatProgressValue(
      measure,
      (best - bestBefore).abs(),
      unitSystem,
      l10n,
      isDifference: true,
    );
    return switch (measure) {
      ProgressMeasureKind.fastestPace =>
        l10n.progressComparisonFaster(difference),
      ProgressMeasureKind.minDuration =>
        l10n.progressComparisonShorter(difference),
      _ => l10n.progressComparisonHigher(difference),
    };
  }
}
