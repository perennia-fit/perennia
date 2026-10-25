import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../focus/controllers/focus_providers.dart';
import '../../focus/widgets/focus_manager_screen.dart';
import '../../focus/widgets/focus_visuals.dart';
import '../../routine_plans/widgets/routine_plan_list_screen.dart';
import '../../routine_plans/widgets/localized_cadence_slot_label.dart';
import '../../template_picker/repositories/template_picker_feature_repository.dart';
import '../../up_next/controllers/up_next_controller.dart';
import '../../../widgets/grouped_rows.dart';

/// What the user chose to start in [showStartWorkoutSheet].
sealed class StartWorkoutChoice {
  const StartWorkoutChoice();
}

/// Materialize one Workout Template, from an Up next card.
final class StartFromTemplate extends StartWorkoutChoice {
  const StartFromTemplate({
    required this.workoutTemplateId,
    this.routineId,
    this.slot,
  });

  final String workoutTemplateId;
  final String? routineId;
  final int? slot;
}

/// Open the routine and template picker.
final class BrowsePlans extends StartWorkoutChoice {
  const BrowsePlans();
}

/// Start an empty Workout, under a Focus or, with null, under none: the path
/// that existed before.
final class StartWithFocus extends StartWorkoutChoice {
  const StartWithFocus(this.focusId);

  final String? focusId;
}

/// The single decision point for a Workout: follow the plan, or say what
/// today is. Programmed days come first and start in one tap; an unplanned
/// day picks a Focus, which is what lets the empty Workout open on the
/// exercises that matter instead of the whole library. Nothing here is
/// required: "Empty workout" starts exactly as before.
Future<StartWorkoutChoice?> showStartWorkoutSheet(BuildContext context) {
  return showModalBottomSheet<StartWorkoutChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const StartWorkoutSheet(),
  );
}

final _hasAnyTemplateProvider = StreamProvider.autoDispose<bool>((ref) {
  return ref
      .watch(templatePickerFeatureRepositoryProvider)
      .watchAllTemplates()
      .map((templates) => templates.isNotEmpty);
});

class StartWorkoutSheet extends ConsumerWidget {
  const StartWorkoutSheet({super.key});

  static const sheetKey = Key('start-workout.sheet');
  static const browsePlansKey = Key('start-workout.browse-plans');
  static const setUpRoutineKey = Key('start-workout.set-up-routine');
  static const editFocusesKey = Key('start-workout.edit-focuses');
  static const emptyWorkoutKey = Key('start-workout.empty');

  static Key upNextKey(String routineId, String workoutTemplateId) =>
      Key('start-workout.up-next.$routineId.$workoutTemplateId');

  static Key focusTileKey(String focusId) =>
      Key('start-workout.focus.$focusId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final suggestions = ref.watch(upNextSuggestionsProvider).value ?? const [];
    final pending = [
      for (final suggestion in suggestions)
        for (final card in suggestion.cards)
          if (!card.isDone) (suggestion, card),
    ];
    final hasTemplates = ref.watch(_hasAnyTemplateProvider).value ?? false;
    final focuses =
        ref.watch(activeFocusesProvider).value ?? const <FocusRecord>[];

    void choose(StartWorkoutChoice choice) => Navigator.of(context).pop(choice);

    return SafeArea(
      key: sheetKey,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            AppDimens.base,
            0,
            AppDimens.base,
            AppDimens.base,
          ),
          children: [
            Text(l10n.startWorkoutSheetTitle, style: context.textStyles.h1),
            const SizedBox(height: AppDimens.base),
            if (pending.isNotEmpty) ...[
              SectionLabel(text: l10n.homeUpNextTitle),
              const SizedBox(height: AppDimens.dense),
              GroupedRows(
                children: [
                  for (final (suggestion, card) in pending)
                    _UpNextRow(
                      key: upNextKey(
                        suggestion.routineId,
                        card.workoutTemplateId,
                      ),
                      templateName: card.templateName,
                      subtitle: l10n.homeUpNextRoutineSubtitle(
                        suggestion.routineName,
                        localizedCadenceSlotLabel(
                          l10n,
                          kind: suggestion.cadenceKind,
                          slot: suggestion.slot,
                        ),
                      ),
                      onTap: () => choose(
                        StartFromTemplate(
                          workoutTemplateId: card.workoutTemplateId,
                          routineId: suggestion.routineId,
                          slot: suggestion.slot,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.dense),
            ],
            if (pending.isNotEmpty || hasTemplates)
              GroupedRows(
                children: [
                  ListTile(
                    key: browsePlansKey,
                    minTileHeight: AppDimens.touchTarget + AppDimens.dense,
                    leading: const Icon(Icons.playlist_add_check),
                    title: Text(
                      l10n.startWorkoutFromPlan,
                      style: context.textStyles.body,
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: context.colors.textSecondary,
                    ),
                    onTap: () => choose(const BrowsePlans()),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: setUpRoutineKey,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, AppDimens.touchTarget),
                    foregroundColor: context.colors.textSecondary,
                  ),
                  onPressed: () => Navigator.of(context).pushNamed(
                    RoutinePlanListScreen.routeName,
                  ),
                  icon: const Icon(Icons.assignment_outlined),
                  label: Text(l10n.startWorkoutSetUpRoutine),
                ),
              ),
            const SizedBox(height: AppDimens.base),
            Row(
              children: [
                Expanded(
                  child: SectionLabel(text: l10n.startWorkoutFocusSection),
                ),
                IconButton(
                  key: editFocusesKey,
                  tooltip: l10n.startWorkoutEditFocusesTooltip,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FocusManagerScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.dense / 2),
            _FocusGrid(
              focuses: focuses,
              onSelected: (focus) => choose(StartWithFocus(focus.id)),
            ),
            const SizedBox(height: AppDimens.base),
            GroupedRows(
              children: [
                ListTile(
                  key: emptyWorkoutKey,
                  minTileHeight: AppDimens.touchTarget + AppDimens.dense,
                  leading: const Icon(Icons.add),
                  title: Text(
                    l10n.startWorkoutEmpty,
                    style: context.textStyles.body,
                  ),
                  subtitle: Text(
                    l10n.startWorkoutEmptySubtitle,
                    style: context.textStyles.caption.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  onTap: () => choose(const StartWithFocus(null)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Focus tiles, two to a row on a phone: large enough to hit with a thumb on
/// the gym floor, labelled with the Focus's name (the icon only helps
/// recognition).
class _FocusGrid extends StatelessWidget {
  const _FocusGrid({required this.focuses, required this.onSelected});

  final List<FocusRecord> focuses;
  final ValueChanged<FocusRecord> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final gap = AppDimens.dense;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final focus in focuses)
              SizedBox(
                width: width,
                child: _FocusTile(
                  focus: focus,
                  onTap: () => onSelected(focus),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FocusTile extends StatelessWidget {
  const _FocusTile({required this.focus, required this.onTap});

  final FocusRecord focus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.startWorkoutFocusTileLabel(focus.name),
      excludeSemantics: true,
      child: Material(
        key: StartWorkoutSheet.focusTileKey(focus.id),
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: context.colors.divider),
          borderRadius: AppRadii.cardMd,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.dense),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Neutral icons: on this sheet the one cyan mark is the
                  // Up next start, so the programmed day reads first.
                  Icon(
                    focusIcon(focus.id),
                    color: context.colors.textSecondary,
                    size: 28,
                  ),
                  const SizedBox(height: AppDimens.dense),
                  Text(
                    focus.name,
                    style: context.textStyles.h2,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

class _UpNextRow extends StatelessWidget {
  const _UpNextRow({
    super.key,
    required this.templateName,
    required this.subtitle,
    required this.onTap,
  });

  final String templateName;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: AppDimens.touchTarget + AppDimens.dense,
      leading: Icon(
        Icons.play_circle_outline,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(templateName, style: context.textStyles.h2),
      subtitle: Text(
        subtitle,
        style: context.textStyles.caption.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: context.colors.textSecondary,
      ),
      onTap: onTap,
    );
  }
}

