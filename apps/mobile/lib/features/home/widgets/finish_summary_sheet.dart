import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../../widgets/grouped_rows.dart';
import '../../progress/controllers/progress_controller.dart';
import '../../progress/widgets/new_best_row.dart';
import '../../settings/repositories/settings_repository.dart';
import '../../template_divergence/repositories/template_divergence_feature_repository.dart';
import '../../template_divergence/widgets/template_divergence_diff_text.dart';
import '../controllers/home_controller.dart';
import '../repositories/home_repository.dart';
import 'copy_workout_summary.dart';
import 'workout_duration.dart';

/// How long the Copy row reads "Copied" before its label returns.
const _copiedFeedbackDuration = Duration(seconds: 2);

/// Opens the Finish summary over the screen that finished the Workout, and
/// completes when it closes, however it closes.
///
/// The drag handle keeps a swipe-down working when the body scrolls at 2x
/// text, where a drag on the body moves the scroll view rather than the sheet.
Future<void> showFinishSummarySheet(
  BuildContext context, {
  required String workoutId,
  required TemplateDivergenceSummary? divergenceSummary,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (_) => FinishSummarySheet(
      workoutId: workoutId,
      divergenceSummary: divergenceSummary,
    ),
  );
}

/// What the Workout came to: its facts, its New Bests, the offer to update
/// its template when it drifted, Copy summary and Done. It reports and offers,
/// with no dialog, message or celebration.
class FinishSummarySheet extends ConsumerStatefulWidget {
  const FinishSummarySheet({
    super.key,
    required this.workoutId,
    required this.divergenceSummary,
  });

  static const sheetKey = Key('finish-summary.sheet');
  static const updateTemplateKey = Key('finish-summary.update-template');
  static const copySummaryKey = Key('finish-summary.copy-summary');
  static const doneKey = Key('finish-summary.done');

  final String workoutId;

  /// Read before the Workout finished, by the caller. Null when the Workout
  /// has no live Template Link.
  final TemplateDivergenceSummary? divergenceSummary;

  @override
  ConsumerState<FinishSummarySheet> createState() => _FinishSummarySheetState();
}

class _FinishSummarySheetState extends ConsumerState<FinishSummarySheet> {
  // A guard, not display state: the row keeps its label while the write runs.
  bool _updating = false;
  bool _updated = false;
  bool _updateFailed = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _updateTemplate() async {
    if (_updating) {
      return;
    }
    _updating = true;
    var updated = false;
    try {
      final result = await ref
          .read(templateDivergenceFeatureRepositoryProvider)
          .updateTemplateFromWorkout(widget.workoutId);
      // Null means the template is gone.
      updated = result != null;
    } catch (_) {
      // Reported by the row's failure text, which the user can tap to retry.
      updated = false;
    }
    _updating = false;
    if (!mounted) {
      return;
    }
    setState(() {
      _updated = updated;
      _updateFailed = !updated;
    });
  }

  Future<void> _copySummary() async {
    await copyWorkoutSummary(
      ref.read(homeControllerProvider.notifier),
      widget.workoutId,
    );
    if (!mounted) {
      return;
    }
    _copiedTimer?.cancel();
    setState(() {
      _copied = true;
    });
    _copiedTimer = Timer(_copiedFeedbackDuration, () {
      setState(() {
        _copied = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final summary = ref.watch(workoutSummaryProvider(widget.workoutId)).value;
    final divergence = widget.divergenceSummary;

    return SafeArea(
      key: FinishSummarySheet.sheetKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.base,
          0,
          AppDimens.base,
          AppDimens.base,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (summary != null) ...[
              Text(
                summary.templateName ?? l10n.workoutTitle,
                style: context.textStyles.h1,
              ),
              const SizedBox(height: AppDimens.dense / 2),
              Text(
                l10n.finishSummaryFacts(
                  formatWorkoutDuration(l10n, summary.duration),
                  l10n.workoutPerformedSetsOfTotal(
                    summary.performedSetCount,
                    summary.setCount,
                  ),
                  summary.workoutExercises.length,
                ),
                style: context.textStyles.body.copyWith(
                  color: context.colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: AppDimens.base),
              _NewBestsSection(summary: summary),
              const SizedBox(height: AppDimens.base),
              GroupedRows(
                children: [
                  if (divergence != null && divergence.hasDivergence)
                    _ActionRow(
                      inkKey: FinishSummarySheet.updateTemplateKey,
                      label: _updated
                          ? l10n.finishSummaryUpdated(divergence.templateName)
                          : _updateFailed
                              ? l10n.finishSummaryUpdateFailed(
                                  divergence.templateName,
                                )
                              : l10n.finishSummaryUpdate(
                                  divergence.templateName,
                                ),
                      lines: templateDivergenceLines(
                        divergence.divergence,
                        l10n,
                      ),
                      onTap: _updated ? null : _updateTemplate,
                    ),
                  _ActionRow(
                    inkKey: FinishSummarySheet.copySummaryKey,
                    label: _copied
                        ? l10n.finishSummaryCopied
                        : l10n.finishSummaryCopy,
                    onTap: _copySummary,
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.base),
            ],
            FilledButton(
              key: FinishSummarySheet.doneKey,
              style: _doneButtonStyle(context),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.finishSummaryDone),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Training Screen's save button style, from the same tokens.
ButtonStyle _doneButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    backgroundColor: context.colors.save,
    foregroundColor: Theme.of(context).colorScheme.onSecondary,
    minimumSize: const Size.fromHeight(AppDimens.rowHeight),
  );
}

/// The section always shows its header and at least one 48 dp row, because
/// the New Bests read covers each exercise's whole history and can take a
/// moment: the sheet doesn't jump when it returns.
class _NewBestsSection extends ConsumerWidget {
  const _NewBestsSection({required this.summary});

  final HomeWorkoutSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final day = workoutLocalDate(summary);
    final bests = ref.watch(progressNewBestsBetweenProvider((day, day))).value;
    // A failed settings load reads as the defaults, as Progress's does.
    final settingsValue = ref.watch(settingsControllerProvider);
    final settings = settingsValue.value ??
        (settingsValue.hasError ? AppSettings.defaults : null);

    final namesByExerciseId = <String, String>{
      for (final exercise in summary.workoutExercises)
        exercise.exerciseId: exercise.name,
    };
    final rows = bests == null || settings == null
        ? null
        : <ProgressNewBestRow>[
            for (final best in bests)
              if (best.workoutId == summary.id)
                if (namesByExerciseId[best.exerciseId] case final name?)
                  ProgressNewBestRow(best: best, exerciseName: name),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(text: l10n.finishSummaryNewBests),
        if (rows == null)
          const _NewBestsNote(text: '—')
        else if (rows.isEmpty)
          _NewBestsNote(text: l10n.finishSummaryNoNewBests)
        else
          for (final row in rows)
            NewBestRow(row: row, unitSystem: settings!.unitSystem),
      ],
    );
  }
}

/// The New Bests section's one row when it has none to list.
class _NewBestsNote extends StatelessWidget {
  const _NewBestsNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A tappable row of the sheet: a label, with [lines] one per line under it.
/// Null [onTap] disables it.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.inkKey,
    required this.label,
    this.lines = const <String>[],
    required this.onTap,
  });

  final Key inkKey;
  final String label;
  final List<String> lines;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      child: InkWell(
        key: inkKey,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.base,
                vertical: AppDimens.dense / 2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: context.textStyles.body.copyWith(
                      color: onTap == null
                          ? colors.textSecondary
                          : colors.textPrimary,
                    ),
                  ),
                  for (final line in lines)
                    Text(
                      line,
                      style: context.textStyles.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
