import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/training/routine_cadence.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../../widgets/grouped_rows.dart';
import '../../routine_plans/widgets/localized_cadence_slot_label.dart';
import '../../routine_plans/widgets/routine_plan_editor_screen.dart';
import '../../routine_plans/widgets/routine_plan_list_screen.dart';
import '../../up_next/controllers/up_next_controller.dart';
import '../../up_next/repositories/up_next_feature_repository.dart';
import '../../workout_templates/controllers/workout_template_controller.dart';
import '../../workout_templates/widgets/workout_template_list_screen.dart';
import '../controllers/template_picker_controller.dart';
import '../repositories/template_picker_feature_repository.dart';

/// One materialize request picked from the sheet: the default tap and the
/// preview gesture both resolve to this same shape, because both start the
/// whole Template the same way — preview only adds a look-before-you-start
/// step, never a different materialize call. `routineId`/`slot` are set
/// when the pick was made inside a Routine; an "Other saved workouts" pick
/// leaves both null.
final class TemplatePickerResult {
  const TemplatePickerResult({
    required this.workoutTemplateId,
    this.routineId,
    this.slot,
  });

  final String workoutTemplateId;
  final String? routineId;
  final int? slot;
}

/// Opens the Routines sheet behind Today's Routines button.
///
/// Returns the picked [TemplatePickerResult], or `null` when dismissed
/// without picking. The caller performs the actual materialize + navigate;
/// this sheet is a pure picker.
Future<TemplatePickerResult?> showTemplatePickerSheet(BuildContext context) {
  return showModalBottomSheet<TemplatePickerResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => const TemplatePickerSheet(),
  );
}

/// Where the athlete is inside the sheet: one Routine's workouts, or the
/// saved workouts no Routine holds. The list of Routines is the null level.
sealed class _Level {
  const _Level();
}

final class _RoutineLevel extends _Level {
  const _RoutineLevel(this.routineId);

  final String routineId;

  @override
  bool operator ==(Object other) =>
      other is _RoutineLevel && other.routineId == routineId;

  @override
  int get hashCode => routineId.hashCode;
}

final class _OtherWorkoutsLevel extends _Level {
  const _OtherWorkoutsLevel();

  @override
  bool operator ==(Object other) => other is _OtherWorkoutsLevel;

  @override
  int get hashCode => 0;
}

/// The Routines sheet: pick a Routine, then one of its workouts.
///
/// Two levels instead of one long page, because the athlete's question
/// comes in that order: which plan am I on, then which day of it. Up next
/// is not repeated as a section here (Today's strip already offers it); it
/// marks the suggested workout inside its Routine instead. With a single
/// place to go (one Routine and no other saved workouts, or only other
/// saved workouts) the sheet opens straight onto it, so a one-Routine
/// athlete never sees a list of one. Editing lives one tap away (Manage,
/// Edit) without competing with starting.
class TemplatePickerSheet extends ConsumerStatefulWidget {
  const TemplatePickerSheet({super.key});

  static const emptyStateKey = Key('templatePicker.empty');
  static const createRoutineButtonKey = Key('templatePicker.createRoutine');
  static const manageButtonKey = Key('templatePicker.manage');
  static const editRoutineButtonKey = Key('templatePicker.editRoutine');
  static const backButtonKey = Key('templatePicker.back');
  static const otherWorkoutsRowKey = Key('templatePicker.otherWorkouts');

  static Key routineRowKey(String routineId) =>
      Key('templatePicker.routine.$routineId');
  static Key routineEntryTileKey(String routineEntryId) =>
      Key('templatePicker.routineEntry.tile.$routineEntryId');
  static Key routineEntryPreviewKey(String routineEntryId) =>
      Key('templatePicker.routineEntry.preview.$routineEntryId');

  static Key otherTemplateTileKey(String templateId) =>
      Key('templatePicker.otherTemplates.tile.$templateId');
  static Key otherTemplatePreviewKey(String templateId) =>
      Key('templatePicker.otherTemplates.preview.$templateId');

  @override
  ConsumerState<TemplatePickerSheet> createState() =>
      _TemplatePickerSheetState();
}

class _TemplatePickerSheetState extends ConsumerState<TemplatePickerSheet> {
  _Level? _level;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final routines = ref.watch(templatePickerRoutinesProvider);
    final others = ref.watch(templatePickerOtherTemplatesProvider);
    final exerciseCounts = ref.watch(templatePickerExerciseCountsProvider);
    final upNext = ref.watch(upNextSuggestionsProvider).value ??
        const <UpNextSuggestionView>[];

    final routineViews = routines.value ?? const <TemplatePickerRoutineView>[];
    final otherViews = others.value ?? const <TemplatePickerTemplateView>[];
    final loaded = routines.hasValue && others.hasValue;
    final destinations = <_Level>[
      for (final routine in routineViews) _RoutineLevel(routine.routineId),
      if (otherViews.isNotEmpty) const _OtherWorkoutsLevel(),
    ];
    final soleDestination =
        destinations.length == 1 ? destinations.single : null;
    // A level whose Routine disappeared (archived elsewhere) falls back.
    final chosen = destinations.contains(_level) ? _level : null;
    final level = chosen ?? soleDestination;
    final canGoBack = chosen != null && destinations.length > 1;
    final upNextByRoutine = {
      for (final suggestion in upNext) suggestion.routineId: suggestion,
    };

    final Widget header;
    final List<Widget> body;
    switch (level) {
      case null:
        header = _SheetHeader(
          title: l10n.routinesSheetTitle,
          action: _HeaderAction(
            key: TemplatePickerSheet.manageButtonKey,
            label: l10n.routinesSheetManage,
            onPressed: () => Navigator.of(context)
                .pushNamed(RoutinePlanListScreen.routeName),
          ),
        );
        body = !loaded
            ? const <Widget>[]
            : destinations.isEmpty
                ? [const _EmptyState()]
                : [
                    if (routineViews.isNotEmpty)
                      GroupedRows(
                        children: [
                          for (final routine in routineViews)
                            _NavigationRow(
                              key: TemplatePickerSheet.routineRowKey(
                                routine.routineId,
                              ),
                              title: routine.routineName,
                              subtitle: _routineSummary(
                                context,
                                routine,
                                upNextByRoutine[routine.routineId],
                              ),
                              onTap: () => setState(
                                () => _level = _RoutineLevel(routine.routineId),
                              ),
                            ),
                        ],
                      ),
                    if (routineViews.isNotEmpty && otherViews.isNotEmpty)
                      const SizedBox(height: AppDimens.base),
                    if (otherViews.isNotEmpty)
                      GroupedRows(
                        children: [
                          _NavigationRow(
                            key: TemplatePickerSheet.otherWorkoutsRowKey,
                            title: l10n.routinesSheetOtherWorkouts,
                            subtitle: [
                              l10n.routinesSheetNotInRoutine,
                              l10n.routinesSheetWorkoutCount(otherViews.length),
                            ].join(' · '),
                            onTap: () => setState(
                              () => _level = const _OtherWorkoutsLevel(),
                            ),
                          ),
                        ],
                      ),
                  ];
      case _RoutineLevel(:final routineId):
        final routine = routineViews.firstWhere(
          (candidate) => candidate.routineId == routineId,
        );
        final cadenceKind = routine.cadenceKind;
        header = _SheetHeader(
          title: routine.routineName,
          subtitle:
              cadenceKind == null ? null : _cadenceLabel(context, cadenceKind),
          onBack: canGoBack ? () => setState(() => _level = null) : null,
          action: _HeaderAction(
            key: TemplatePickerSheet.editRoutineButtonKey,
            label: l10n.routinesSheetEdit,
            onPressed: () => Navigator.of(context).pushNamed(
              RoutinePlanEditorScreen.routeName,
              arguments: routineId,
            ),
          ),
        );
        body = _routineBody(
          context,
          routine: routine,
          suggestion: upNextByRoutine[routineId],
          exerciseCounts: exerciseCounts,
        );
      case _OtherWorkoutsLevel():
        header = _SheetHeader(
          title: l10n.routinesSheetOtherWorkouts,
          subtitle: l10n.routinesSheetNotInRoutine,
          onBack: canGoBack ? () => setState(() => _level = null) : null,
          action: _HeaderAction(
            key: TemplatePickerSheet.manageButtonKey,
            label: l10n.routinesSheetManage,
            onPressed: () => Navigator.of(context)
                .pushNamed(WorkoutTemplateListScreen.routeName),
          ),
        );
        body = [
          GroupedRows(
            children: [
              for (final template in otherViews)
                _WorkoutRow(
                  templateId: template.id,
                  name: template.name,
                  exerciseCount: template.exerciseCount,
                  tileKey:
                      TemplatePickerSheet.otherTemplateTileKey(template.id),
                  previewKey:
                      TemplatePickerSheet.otherTemplatePreviewKey(template.id),
                  result: TemplatePickerResult(workoutTemplateId: template.id),
                ),
            ],
          ),
        ];
    }

    return PopScope(
      // System back steps out of a Routine before it closes the sheet.
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() => _level = null);
        }
      },
      child: SafeArea(
        top: false,
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
              header,
              const SizedBox(height: AppDimens.base),
              ...body,
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _routineBody(
    BuildContext context, {
    required TemplatePickerRoutineView routine,
    required UpNextSuggestionView? suggestion,
    required Map<String, int> exerciseCounts,
  }) {
    final l10n = context.l10n;
    final nextEntryIds = {
      for (final card in suggestion?.cards ?? const <UpNextCardView>[])
        if (!card.isDone) card.routineEntryId,
    };
    final doneEntryIds = {
      for (final card in suggestion?.cards ?? const <UpNextCardView>[])
        if (card.isDone) card.routineEntryId,
    };

    Widget row(TemplatePickerRoutineEntryView entry) {
      return _WorkoutRow(
        templateId: entry.workoutTemplateId,
        name: entry.templateName,
        exerciseCount: exerciseCounts[entry.workoutTemplateId],
        isNext: nextEntryIds.contains(entry.routineEntryId),
        isDone: doneEntryIds.contains(entry.routineEntryId),
        tileKey: TemplatePickerSheet.routineEntryTileKey(entry.routineEntryId),
        previewKey:
            TemplatePickerSheet.routineEntryPreviewKey(entry.routineEntryId),
        result: TemplatePickerResult(
          workoutTemplateId: entry.workoutTemplateId,
          routineId: routine.routineId,
          slot: entry.slot,
        ),
      );
    }

    final cadenceKind = routine.cadenceKind;
    if (cadenceKind == null) {
      return [
        GroupedRows(
            children: [for (final entry in routine.entries) row(entry)]),
      ];
    }
    // Grouped by day in slot order; empty slots (rest days) have no entries
    // and so no heading. An entry without a slot, if any, closes the list.
    final slots = <int?>[
      ...{for (final entry in routine.entries) entry.slot},
    ]..sort((a, b) => (a ?? 1 << 30).compareTo(b ?? 1 << 30));
    return [
      for (final slot in slots) ...[
        if (slot != null) ...[
          SectionLabel(
            text:
                localizedCadenceSlotLabel(l10n, kind: cadenceKind, slot: slot),
          ),
          const SizedBox(height: AppDimens.dense),
        ],
        GroupedRows(
          children: [
            for (final entry in routine.entries)
              if (entry.slot == slot) row(entry),
          ],
        ),
        const SizedBox(height: AppDimens.base),
      ],
    ];
  }

  String _routineSummary(
    BuildContext context,
    TemplatePickerRoutineView routine,
    UpNextSuggestionView? suggestion,
  ) {
    final l10n = context.l10n;
    final cadenceKind = routine.cadenceKind;
    final next = suggestion?.cards.where((card) => !card.isDone).firstOrNull;
    return [
      if (cadenceKind != null) _cadenceLabel(context, cadenceKind),
      if (next != null)
        l10n.routinesSheetNext(next.templateName)
      else
        l10n.routinesSheetWorkoutCount(routine.entries.length),
    ].join(' · ');
  }

  String _cadenceLabel(BuildContext context, CadenceKind kind) {
    final l10n = context.l10n;
    return switch (kind) {
      CadenceKind.weekly => l10n.routinePlansCadenceWeekly,
      CadenceKind.rotating => l10n.routinePlansCadenceRotating,
    };
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.action,
    this.subtitle,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Row(
      // A one-line title centres the action on it; with a subtitle the
      // action stays level with the title, not the pair.
      crossAxisAlignment: subtitle == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        if (onBack != null) ...[
          IconButton(
            key: TemplatePickerSheet.backButtonKey,
            tooltip: context.l10n.routinesSheetBack,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: AppDimens.dense / 2),
        ],
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: onBack == null ? 0 : 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textStyles.h1),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: context.textStyles.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppDimens.dense),
        action,
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: context.colors.textPrimary,
        minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _NavigationRow extends StatelessWidget {
  const _NavigationRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: AppDimens.touchTarget + AppDimens.dense,
      title: Text(title, style: context.textStyles.h2),
      subtitle: Text(
        subtitle,
        style: context.textStyles.caption.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: context.colors.textSecondary),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      key: TemplatePickerSheet.emptyStateKey,
      padding: const EdgeInsets.symmetric(vertical: AppDimens.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.routinesSheetEmptyTitle, style: context.textStyles.h2),
          const SizedBox(height: AppDimens.dense),
          Text(
            l10n.routinesSheetEmptyMessage,
            style: context.textStyles.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDimens.base),
          FilledButton.icon(
            key: TemplatePickerSheet.createRoutineButtonKey,
            onPressed: () => Navigator.of(context)
                .pushNamed(RoutinePlanListScreen.routeName),
            icon: const Icon(Icons.add),
            label: Text(l10n.routinesSheetEmptyAction),
          ),
        ],
      ),
    );
  }
}

/// One startable workout: the row tap pops the sheet with [result] at once;
/// the trailing preview opens a read-only look at its exercises and pops
/// with the same [result] only if the athlete confirms Start there, so both
/// paths record the same Template Link.
class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({
    required this.templateId,
    required this.name,
    required this.exerciseCount,
    required this.tileKey,
    required this.previewKey,
    required this.result,
    this.isNext = false,
    this.isDone = false,
  });

  final String templateId;
  final String name;

  /// Null while the counts are still loading; the row then just omits it.
  /// Zero is said out loud ("No exercises"): starting it gives an empty
  /// Workout, which should never come as a surprise.
  final int? exerciseCount;
  final Key tileKey;
  final Key previewKey;
  final TemplatePickerResult result;

  /// Today's Up next suggestion for its Routine, still to do.
  final bool isNext;

  /// Already done on the selected Training Day; still startable again.
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final exerciseCount = this.exerciseCount;
    final subtitle = [
      if (isNext) l10n.routinesSheetUpNext,
      if (isDone) l10n.routinesSheetDone,
      if (exerciseCount != null) l10n.routinesSheetExerciseCount(exerciseCount),
    ].join(' · ');
    return ListTile(
      key: tileKey,
      minTileHeight: AppDimens.touchTarget + AppDimens.dense,
      leading: isDone
          ? Icon(Icons.check_circle, color: context.colors.save)
          : Icon(
              Icons.play_circle_outline,
              color: isNext
                  ? Theme.of(context).colorScheme.primary
                  : context.colors.textSecondary,
            ),
      title: Text(name, style: context.textStyles.h2),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              style: context.textStyles.caption.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
      onTap: () => Navigator.of(context).pop(result),
      trailing: IconButton(
        key: previewKey,
        tooltip: l10n.routinesSheetPreviewTooltip(name),
        icon: Icon(
          Icons.visibility_outlined,
          color: context.colors.textSecondary,
        ),
        onPressed: () => _preview(context),
      ),
    );
  }

  Future<void> _preview(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirmed = await showTemplatePickerPreviewSheet(
      context,
      templateId: templateId,
      templateName: name,
    );
    if (confirmed == true) {
      navigator.pop(result);
    }
  }
}

/// Opens a read-only "look before you start" preview of one workout's
/// exercises. Trimming happens in the ordinary Workout screen once started;
/// this preview never edits the Template or the future Workout.
/// Returns `true` when the athlete taps Start, `null`/`false` otherwise.
Future<bool?> showTemplatePickerPreviewSheet(
  BuildContext context, {
  required String templateId,
  required String templateName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => TemplatePickerPreviewSheet(
      templateId: templateId,
      templateName: templateName,
    ),
  );
}

class TemplatePickerPreviewSheet extends ConsumerWidget {
  const TemplatePickerPreviewSheet({
    super.key,
    required this.templateId,
    required this.templateName,
  });

  final String templateId;
  final String templateName;

  static const startButtonKey = Key('templatePicker.preview.start');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final detail =
        ref.watch(workoutTemplateDetailControllerProvider(templateId));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimens.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(templateName, style: context.textStyles.h1),
              const SizedBox(height: AppDimens.base),
              Text(
                l10n.templatePickerPreviewExercisesHeading,
                style: context.textStyles.label.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppDimens.dense),
              detail.when(
                data: (template) {
                  final exercises = template?.exercises ?? const [];
                  if (exercises.isEmpty) {
                    return Text(
                      l10n.templatePickerPreviewEmptyExercises,
                      style: context.textStyles.body.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final exercise in exercises)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 2,
                          ),
                          child: Text(
                            exercise.name,
                            style: context.textStyles.body,
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Text(
                  l10n.workoutTemplateUnavailable,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: AppDimens.base),
              FilledButton.icon(
                key: TemplatePickerPreviewSheet.startButtonKey,
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.templatePickerPreviewStart),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
