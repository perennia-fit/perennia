import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../focus/controllers/focus_providers.dart';
import '../../focus/widgets/focus_manager_screen.dart';
import '../../focus/widgets/focus_visuals.dart';
import '../../../widgets/grouped_rows.dart';

/// What the user chose to start in [showStartWorkoutSheet]: an empty
/// Workout under a Focus or, with null, under none.
final class StartWorkoutChoice {
  const StartWorkoutChoice(this.focusId);

  final String? focusId;
}

/// The unplanned start: say what today is, or start empty. Picking a Focus
/// is what lets the empty Workout open on the exercises that matter instead
/// of the whole library; "Empty workout" starts exactly as before. Planned
/// workouts are not offered here: Today's Up next strip and its Routines
/// button own that path, and repeating them here made one decision look
/// like three.
Future<StartWorkoutChoice?> showStartWorkoutSheet(BuildContext context) {
  return showModalBottomSheet<StartWorkoutChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const StartWorkoutSheet(),
  );
}

class StartWorkoutSheet extends ConsumerWidget {
  const StartWorkoutSheet({super.key});

  static const sheetKey = Key('start-workout.sheet');
  static const editFocusesKey = Key('start-workout.edit-focuses');
  static const emptyWorkoutKey = Key('start-workout.empty');

  static Key focusTileKey(String focusId) =>
      Key('start-workout.focus.$focusId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
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
              onSelected: (focus) => choose(StartWorkoutChoice(focus.id)),
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
                  onTap: () => choose(const StartWorkoutChoice(null)),
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
    // `excludeSemantics` drops the InkWell's own tap, so the node carries it.
    return Semantics(
      container: true,
      button: true,
      label: context.l10n.startWorkoutFocusTileLabel(focus.name),
      onTap: onTap,
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
                  // Neutral icons: the Focus name is the signal, the icon
                  // only helps recognition.
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
