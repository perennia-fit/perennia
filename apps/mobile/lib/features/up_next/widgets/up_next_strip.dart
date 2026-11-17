import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../home/widgets/workout_screen.dart';
import '../../routine_plans/widgets/localized_cadence_slot_label.dart';
import '../../template_materialize/controllers/template_materialize_controller.dart';
import '../../template_materialize/widgets/empty_template_start_dialog.dart';
import '../../template_picker/widgets/template_picker_sheet.dart';
import '../controllers/up_next_controller.dart';
import '../repositories/up_next_feature_repository.dart';

/// Home's "Up next" strip (ROUTINES.md §3.1).
///
/// Suggestion cards for every cadenced Routine's derived position on the
/// selected Training Day: the remaining sessions of a half-done slot first,
/// done sessions shown ticked. A card's body opens a read-only preview of
/// the Template, whose Start begins it; the card's ▶ starts at once,
/// materializing the whole Template and landing in the Workout — so the
/// ≤ 2-taps covenant holds without the preview in the way.
/// Renders nothing when there is nothing to suggest: with no cadenced
/// Routines, Home looks exactly as it did before this slice.
class UpNextStrip extends ConsumerWidget {
  const UpNextStrip({super.key});

  static const sectionKey = Key('home.upNext');

  /// A not-done card's body, which opens the preview.
  static Key cardKey(String routineId, String workoutTemplateId) =>
      Key('home.upNext.card.$routineId.$workoutTemplateId');

  /// The ▶ on a not-done card: starts without the preview.
  static Key startButtonKey(String routineId, String workoutTemplateId) =>
      Key('home.upNext.start.$routineId.$workoutTemplateId');

  static Key doneKey(String routineId, String workoutTemplateId) =>
      Key('home.upNext.done.$routineId.$workoutTemplateId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(upNextSuggestionsProvider);
    return suggestions.when(
      data: (list) {
        if (list.isEmpty) {
          return const SizedBox.shrink();
        }
        return KeyedSubtree(
          key: sectionKey,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppDimens.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.homeUpNextTitle,
                  style: context.textStyles.h2,
                ),
                const SizedBox(height: AppDimens.dense),
                for (var index = 0; index < list.length; index += 1) ...[
                  if (index > 0) const SizedBox(height: AppDimens.dense),
                  _RoutineUpNextGroup(suggestion: list[index]),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _RoutineUpNextGroup extends StatelessWidget {
  const _RoutineUpNextGroup({required this.suggestion});

  final UpNextSuggestionView suggestion;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final slotLabel = localizedCadenceSlotLabel(
      l10n,
      kind: suggestion.cadenceKind,
      slot: suggestion.slot,
    );
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.colors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.dense),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeUpNextRoutineSubtitle(suggestion.routineName, slotLabel),
              style: context.textStyles.label.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimens.dense),
            for (final card in suggestion.cards)
              _UpNextCardTile(
                routineId: suggestion.routineId,
                slot: suggestion.slot,
                card: card,
              ),
          ],
        ),
      ),
    );
  }
}

class _UpNextCardTile extends ConsumerStatefulWidget {
  const _UpNextCardTile({
    required this.routineId,
    required this.slot,
    required this.card,
  });

  final String routineId;
  final int slot;
  final UpNextCardView card;

  @override
  ConsumerState<_UpNextCardTile> createState() => _UpNextCardTileState();
}

class _UpNextCardTileState extends ConsumerState<_UpNextCardTile> {
  /// Set while a start is in flight. A quick double tap on ▶ (easy with
  /// gloves) would otherwise run [_start] twice and materialize two
  /// Workouts with the same Template Link. Not shown in the UI, so it is a
  /// plain field rather than state that rebuilds the tile.
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final card = widget.card;
    final routineId = widget.routineId;
    if (card.isDone) {
      return Semantics(
        key: UpNextStrip.doneKey(routineId, card.workoutTemplateId),
        label: l10n.homeUpNextDoneLabel(card.templateName),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: context.colors.save),
              const SizedBox(width: AppDimens.dense),
              Expanded(
                child: Text(
                  card.templateName,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isEmpty = ref
            .watch(emptyWorkoutTemplateIdsProvider)
            .value
            ?.contains(card.workoutTemplateId) ??
        false;
    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: UpNextStrip.cardKey(routineId, card.workoutTemplateId),
              onTap: () => unawaited(_preview()),
              child: Semantics(
                button: true,
                label: l10n.homeUpNextPreviewLabel(card.templateName),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppDimens.touchTarget,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.radio_button_unchecked,
                        color: context.colors.textSecondary,
                      ),
                      const SizedBox(width: AppDimens.dense),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card.templateName,
                              style: context.textStyles.body,
                            ),
                            if (isEmpty)
                              Text(
                                l10n.templateStartNoExercises,
                                style: context.textStyles.label.copyWith(
                                  color: context.colors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          key: UpNextStrip.startButtonKey(routineId, card.workoutTemplateId),
          tooltip: l10n.homeUpNextStartTooltip(card.templateName),
          constraints: const BoxConstraints(
            minWidth: AppDimens.touchTarget,
            minHeight: AppDimens.touchTarget,
          ),
          onPressed: () => unawaited(_start()),
          icon: Icon(
            Icons.play_arrow,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  /// The card body's look before starting: the preview's Start runs the
  /// same [_start] as the ▶ button, so both record the same Template Link
  /// and pass the same empty-Template prompt.
  Future<void> _preview() async {
    final confirmed = await showTemplatePickerPreviewSheet(
      context,
      templateId: widget.card.workoutTemplateId,
      templateName: widget.card.templateName,
    );
    if (confirmed == true && mounted) {
      await _start();
    }
  }

  Future<void> _start() async {
    if (_starting) {
      return;
    }
    _starting = true;
    try {
      await _startOnce();
    } finally {
      _starting = false;
    }
  }

  Future<void> _startOnce() async {
    final proceed = await confirmTemplateStart(
      context,
      ref,
      workoutTemplateId: widget.card.workoutTemplateId,
    );
    if (!proceed || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final failureMessage = context.l10n.homeUpNextStartFailed;
    try {
      final workoutId =
          await ref.read(templateMaterializeControllerProvider).start(
                workoutTemplateId: widget.card.workoutTemplateId,
                routineId: widget.routineId,
                slot: widget.slot,
              );
      if (!mounted) {
        return;
      }
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutScreen(workoutId: workoutId),
        ),
      );
    } on Object {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
      }
    }
  }
}
