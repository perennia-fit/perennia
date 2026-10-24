import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../catalog/controllers/exercise_catalog_controller.dart';
import '../controllers/focus_providers.dart';
import 'grouped_rows.dart';

/// The first exercises a Workout under a Focus offers: the ones the user has
/// logged under that Focus, most recent first, then the rest of the Focus's
/// catalog. Shown in place of an empty Workout's exercise list, so the first
/// exercise is one tap away instead of a search through the whole library.
class FocusedExerciseList extends ConsumerWidget {
  const FocusedExerciseList({
    super.key,
    required this.focus,
    required this.onExerciseSelected,
    required this.onBrowseFocus,
    required this.onSearchAll,
    this.historyLimit = 8,
    this.catalogLimit = 6,
  });

  static const historySectionKey = Key('focused-exercises.history');
  static const catalogSectionKey = Key('focused-exercises.catalog');
  static const browseFocusButtonKey = Key('focused-exercises.browse');
  static const searchAllButtonKey = Key('focused-exercises.search-all');

  static Key exerciseRowKey(String exerciseId) =>
      Key('focused-exercises.exercise.$exerciseId');

  final FocusRecord focus;
  final ValueChanged<ExerciseRecord> onExerciseSelected;
  final VoidCallback onBrowseFocus;
  final VoidCallback onSearchAll;
  final int historyLimit;
  final int catalogLimit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final catalog = ref.watch(exerciseCatalogControllerProvider).value;
    final uses = ref.watch(focusExerciseUsesProvider(focus.id)).value;
    final starterIds =
        ref.watch(focusStarterExerciseIdsProvider).value?[focus.id] ??
            const <String>[];
    if (catalog == null || uses == null) {
      // Local reads resolve within a frame; holding the layout empty avoids a
      // spinner on the logging path.
      return const SizedBox(height: AppDimens.touchTarget);
    }

    final exerciseById = <String, ExerciseRecord>{
      for (final section in catalog.sections)
        if (!section.isVirtual)
          for (final exercise in section.exercises) exercise.id: exercise,
    };
    final history = <(ExerciseRecord, FocusExerciseUse)>[
      for (final use in uses)
        if (exerciseById[use.exerciseId] case final exercise?) (exercise, use),
    ].take(historyLimit).toList(growable: false);
    final historyIds = {for (final (exercise, _) in history) exercise.id};
    final hasStaples = starterIds.any(
      (id) => !historyIds.contains(id) && exerciseById.containsKey(id),
    );
    final focusCatalog = exerciseById.values
        .where(
          (exercise) =>
              exercise.focusIds.contains(focus.id) &&
              !historyIds.contains(exercise.id),
        )
        .toList()
      ..sort(_staplesThenFavoritesThenName(starterIds));

    // Suggestions, not logged work: the region names itself as the way to
    // add the first exercise, and with no history the staples lead instead
    // of an empty "recent" label.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.focusLibraryHeading, style: context.textStyles.h2),
        const SizedBox(height: AppDimens.dense),
        if (history.isNotEmpty) ...[
          _SectionLabel(
            key: historySectionKey,
            text: l10n.focusLibraryYourExercises(focus.name),
          ),
          const SizedBox(height: AppDimens.dense),
          GroupedRows(
            children: [
              for (final (exercise, use) in history)
                _ExerciseRow(
                  exercise: exercise,
                  subtitle: _useSubtitle(context, use),
                  onTap: () => onExerciseSelected(exercise),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.base + AppDimens.dense),
        ],
        if (focusCatalog.isNotEmpty) ...[
          _SectionLabel(
            key: catalogSectionKey,
            text: hasStaples
                ? l10n.focusLibraryStaples(focus.name)
                : l10n.focusLibraryCatalog(focus.name),
          ),
          const SizedBox(height: AppDimens.dense),
          GroupedRows(
            children: [
              for (final exercise in focusCatalog.take(catalogLimit))
                _ExerciseRow(
                  exercise: exercise,
                  subtitle: null,
                  onTap: () => onExerciseSelected(exercise),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppDimens.dense),
        OutlinedButton.icon(
          key: browseFocusButtonKey,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(AppDimens.touchTarget),
            foregroundColor: context.colors.textPrimary,
          ),
          onPressed: onBrowseFocus,
          icon: const Icon(Icons.list),
          label: Text(l10n.focusLibraryBrowseAll(focus.name)),
        ),
        const SizedBox(height: AppDimens.dense / 2),
        TextButton.icon(
          key: searchAllButtonKey,
          // Signal Cyan text fails AA on the light ground; the accent stays on
          // the icon.
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(AppDimens.touchTarget),
            foregroundColor: context.colors.textPrimary,
            iconColor: Theme.of(context).colorScheme.primary,
          ),
          onPressed: onSearchAll,
          icon: const Icon(Icons.search),
          label: Text(l10n.focusLibrarySearchAll),
        ),
      ],
    );
  }
}

/// Staples in their curated order, then favorites, then the rest by name.
Comparator<ExerciseRecord> _staplesThenFavoritesThenName(
  List<String> starterIds,
) {
  final rank = <String, int>{
    for (var index = 0; index < starterIds.length; index += 1)
      starterIds[index]: index,
  };
  return (left, right) {
    final leftRank = rank[left.id];
    final rightRank = rank[right.id];
    if (leftRank != null || rightRank != null) {
      if (leftRank == null) return 1;
      if (rightRank == null) return -1;
      return leftRank.compareTo(rightRank);
    }
    if (left.isFavorite != right.isFavorite) {
      return left.isFavorite ? -1 : 1;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  };
}

String _useSubtitle(BuildContext context, FocusExerciseUse use) {
  final l10n = context.l10n;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final performed = use.lastPerformedAt.toLocal();
  final performedDay = DateTime(performed.year, performed.month, performed.day);
  final days = today.difference(performedDay).inDays;
  final when = switch (days) {
    <= 0 => l10n.focusUseToday,
    1 => l10n.focusUseYesterday,
    < 30 => l10n.focusUseDaysAgo(days),
    _ => MaterialLocalizations.of(context).formatMediumDate(performed),
  };
  return l10n.focusUseSubtitle(
      when, l10n.focusUseWorkoutCount(use.workoutCount));
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: context.textStyles.label.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.exercise,
    required this.subtitle,
    required this.onTap,
  });

  final ExerciseRecord exercise;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return InkWell(
      key: FocusedExerciseList.exerciseRowKey(exercise.id),
      onTap: onTap,
      child: Semantics(
        button: true,
        label: context.l10n.focusLibraryAddExerciseTooltip(exercise.name),
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppDimens.touchTarget + AppDimens.dense,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.base,
              vertical: AppDimens.dense / 2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(exercise.name, style: context.textStyles.body),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: context.textStyles.caption.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.dense),
                // Neutral, so the screen keeps one cyan action: Add exercise.
                Icon(
                  Icons.add_circle_outline,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
