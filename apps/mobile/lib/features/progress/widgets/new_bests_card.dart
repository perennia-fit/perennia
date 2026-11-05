import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/analytics/progress_measure.dart';
import '../../../l10n/l10n.dart';
import '../controllers/progress_controller.dart';
import 'new_best_row.dart';
import 'progress_card.dart';

/// The period's most recent New Bests (D4, D8 card 5), each a [NewBestRow].
/// The title counts every New Best in the period.
class NewBestsCard extends ConsumerWidget {
  const NewBestsCard({super.key});

  /// A row, keyed by the New Best's exercise and Workout.
  static Key rowKey(NewBest best) => NewBestRow.rowKey(best);

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
          for (final row in data.rows)
            NewBestRow(
              row: row,
              unitSystem: data.unitSystem,
              today: data.today,
            ),
        ],
      ),
    );
  }
}
