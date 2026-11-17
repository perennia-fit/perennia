import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/template_materialize_controller.dart';
import '../repositories/template_materialize_feature_repository.dart';

/// The linked Template's notes, read-only, on a materialized Workout.
///
/// Materialize deliberately never copies notes (ROUTINES.md §1.5), which
/// left a plan written in a Template's notes invisible exactly when the
/// athlete needed it. This shows them live from the Template instead of
/// copying, so the Workout's own history stays untouched. Collapsed to a few
/// lines so a long plan never pushes the exercise list off the screen; renders
/// nothing for an unlinked Workout or a Template without notes.
class TemplateGuidanceCard extends ConsumerWidget {
  const TemplateGuidanceCard({super.key, required this.workoutId});

  final String workoutId;

  static Key cardKey(String workoutId) => Key('workout.$workoutId.planNotes');

  static Key toggleKey(String workoutId) =>
      Key('workout.$workoutId.planNotes.toggle');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guidance = ref
        .watch(workoutTemplateGuidanceProvider(workoutId))
        .value;
    if (guidance == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.base),
      child: _GuidanceBody(
        key: cardKey(workoutId),
        workoutId: workoutId,
        guidance: guidance,
      ),
    );
  }
}

class _GuidanceBody extends StatefulWidget {
  const _GuidanceBody({
    super.key,
    required this.workoutId,
    required this.guidance,
  });

  final String workoutId;
  final WorkoutTemplateGuidance guidance;

  @override
  State<_GuidanceBody> createState() => _GuidanceBodyState();
}

class _GuidanceBodyState extends State<_GuidanceBody> {
  static const _collapsedLines = 4;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final notesStyle = context.textStyles.body;
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.workoutTemplateNotesTitle, style: context.textStyles.h2),
            Text(
              l10n.workoutTemplateNotesSource(widget.guidance.templateName),
              style: context.textStyles.label.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            LayoutBuilder(
              builder: (context, constraints) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: widget.guidance.notes,
                    style: notesStyle,
                  ),
                  maxLines: _collapsedLines,
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout(maxWidth: constraints.maxWidth);
                final overflows = painter.didExceedMaxLines;
                painter.dispose();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.guidance.notes,
                      style: notesStyle,
                      maxLines: _expanded ? null : _collapsedLines,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                    ),
                    if (overflows)
                      TextButton(
                        key: TemplateGuidanceCard.toggleKey(widget.workoutId),
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.textPrimary,
                          minimumSize: const Size(0, AppDimens.touchTarget),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(
                          _expanded
                              ? l10n.workoutTemplateNotesShowLess
                              : l10n.workoutTemplateNotesShowMore,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
