import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../home/widgets/workout_screen.dart';
import '../../routine_plans/widgets/localized_cadence_slot_label.dart';
import '../../template_materialize/controllers/template_materialize_controller.dart';
import '../controllers/up_next_controller.dart';
import '../repositories/up_next_feature_repository.dart';

/// Home's "Up next" strip (ROUTINES.md §3.1).
///
/// One-tap suggestion cards for every cadenced Routine's derived position on
/// the selected Training Day: the remaining sessions of a half-done slot
/// first, done sessions shown ticked. One tap materializes the whole
/// Template and lands in the Workout — the ≤ 2-taps covenant holds.
/// Renders nothing when there is nothing to suggest: with no cadenced
/// Routines, Home looks exactly as it did before this slice.
class UpNextStrip extends ConsumerWidget {
  const UpNextStrip({super.key});

  static const sectionKey = Key('home.upNext');

  static Key cardKey(String routineId, String workoutTemplateId) =>
      Key('home.upNext.card.$routineId.$workoutTemplateId');

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

class _UpNextCardTile extends ConsumerWidget {
  const _UpNextCardTile({
    required this.routineId,
    required this.slot,
    required this.card,
  });

  final String routineId;
  final int slot;
  final UpNextCardView card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: UpNextStrip.cardKey(routineId, card.workoutTemplateId),
        onTap: () => unawaited(_start(context, ref)),
        child: Semantics(
          button: true,
          label: l10n.homeUpNextStartTooltip(card.templateName),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDimens.touchTarget,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.play_circle_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppDimens.dense),
                Expanded(
                  child: Text(
                    card.templateName,
                    style: context.textStyles.body,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: context.colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final failureMessage = context.l10n.homeUpNextStartFailed;
    try {
      final workoutId =
          await ref.read(templateMaterializeControllerProvider).start(
                workoutTemplateId: card.workoutTemplateId,
                routineId: routineId,
                slot: slot,
              );
      if (!context.mounted) {
        return;
      }
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutScreen(workoutId: workoutId),
        ),
      );
    } on Object {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
      }
    }
  }
}
