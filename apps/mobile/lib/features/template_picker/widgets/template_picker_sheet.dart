import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/training/routine_cadence.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../routine_plans/widgets/localized_cadence_slot_label.dart';
import '../../up_next/controllers/up_next_controller.dart';
import '../../up_next/repositories/up_next_feature_repository.dart';
import '../../workout_templates/controllers/workout_template_controller.dart';
import '../controllers/template_picker_controller.dart';
import '../repositories/template_picker_feature_repository.dart';

/// One materialize request picked from the sheet: the default tap and the
/// "customize" preview gesture both resolve to this same shape, because
/// both start the whole Template the same way (ROUTINES.md §3.2) —
/// customize only adds a look-before-you-start step, never a different
/// materialize call. `routineId`/`slot` are set only when the pick was
/// reached through a Routine (Up next or the Routines group); a bare
/// All Templates pick leaves both null.
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

/// Opens the "Load a Template" browse sheet (ROUTINES.md §3.2;).
///
/// Returns the picked [TemplatePickerResult], or `null` when dismissed
/// without picking. The caller performs the actual materialize + navigate,
/// mirroring the existing `RoutineStartSheet`/`WorkoutTemplateListScreen`
/// convention — this sheet is a pure picker.
Future<TemplatePickerResult?> showTemplatePickerSheet(BuildContext context) {
  return showModalBottomSheet<TemplatePickerResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => const TemplatePickerSheet(),
  );
}

class TemplatePickerSheet extends ConsumerWidget {
  const TemplatePickerSheet({super.key});

  static const emptyStateKey = Key('templatePicker.empty');
  static const upNextSectionKey = Key('templatePicker.upNext');
  static const routinesSectionKey = Key('templatePicker.routines');
  static const allTemplatesSectionKey = Key('templatePicker.allTemplates');
  static const searchFieldKey = Key('templatePicker.search');

  static Key upNextTileKey(String routineId, String workoutTemplateId) =>
      Key('templatePicker.upNext.tile.$routineId.$workoutTemplateId');
  static Key upNextDoneKey(String routineId, String workoutTemplateId) =>
      Key('templatePicker.upNext.done.$routineId.$workoutTemplateId');
  static Key upNextCustomizeKey(String routineId, String workoutTemplateId) =>
      Key('templatePicker.upNext.customize.$routineId.$workoutTemplateId');

  static Key routineHeaderKey(String routineId) =>
      Key('templatePicker.routine.$routineId');
  static Key routineEntryTileKey(String routineEntryId) =>
      Key('templatePicker.routineEntry.tile.$routineEntryId');
  static Key routineEntryCustomizeKey(String routineEntryId) =>
      Key('templatePicker.routineEntry.customize.$routineEntryId');

  static Key allTemplateTileKey(String templateId) =>
      Key('templatePicker.allTemplates.tile.$templateId');
  static Key allTemplateCustomizeKey(String templateId) =>
      Key('templatePicker.allTemplates.customize.$templateId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final upNext = ref.watch(upNextSuggestionsProvider);
    final routines = ref.watch(templatePickerRoutinesProvider);
    final templates = ref.watch(templatePickerFilteredTemplatesProvider);
    final searchQuery = ref.watch(templatePickerSearchQueryProvider);

    final upNextCards = upNext.asData?.value ?? const <UpNextSuggestionView>[];
    final routineViews =
        routines.asData?.value ?? const <TemplatePickerRoutineView>[];
    final templateViews =
        templates.asData?.value ?? const <TemplatePickerTemplateView>[];
    final everythingLoadedEmpty = upNext.hasValue &&
        routines.hasValue &&
        templates.hasValue &&
        upNextCards.isEmpty &&
        routineViews.isEmpty &&
        templateViews.isEmpty &&
        searchQuery.isEmpty;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.base,
                AppDimens.base,
                AppDimens.base,
                AppDimens.dense,
              ),
              child:
                  Text(l10n.templatePickerTitle, style: context.textStyles.h1),
            ),
            Expanded(
              child: everythingLoadedEmpty
                  ? _EmptyState(l10n: l10n)
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.base,
                      ),
                      children: [
                        if (upNextCards.isNotEmpty) ...[
                          KeyedSubtree(
                            key: TemplatePickerSheet.upNextSectionKey,
                            child: _SectionHeading(
                              title: l10n.templatePickerTodayUpNextHeading,
                            ),
                          ),
                          const SizedBox(height: AppDimens.dense),
                          for (final suggestion in upNextCards) ...[
                            _UpNextGroup(suggestion: suggestion),
                            const SizedBox(height: AppDimens.dense),
                          ],
                          const SizedBox(height: AppDimens.base),
                        ],
                        if (routineViews.isNotEmpty) ...[
                          KeyedSubtree(
                            key: TemplatePickerSheet.routinesSectionKey,
                            child: _SectionHeading(
                              title: l10n.templatePickerRoutinesHeading,
                            ),
                          ),
                          const SizedBox(height: AppDimens.dense),
                          for (final routine in routineViews)
                            _RoutineGroup(routine: routine),
                          const SizedBox(height: AppDimens.base),
                        ],
                        KeyedSubtree(
                          key: TemplatePickerSheet.allTemplatesSectionKey,
                          child: _SectionHeading(
                            title: l10n.templatePickerAllTemplatesHeading,
                          ),
                        ),
                        const SizedBox(height: AppDimens.dense),
                        TextField(
                          key: TemplatePickerSheet.searchFieldKey,
                          onChanged: (value) {
                            ref
                                .read(
                                  templatePickerSearchQueryProvider.notifier,
                                )
                                .changed(value);
                          },
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: l10n.templatePickerSearchHint,
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: AppDimens.dense),
                        if (templateViews.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppDimens.base,
                            ),
                            child: Text(
                              l10n.templatePickerNoSearchResults,
                              style: context.textStyles.body.copyWith(
                                color: context.colors.textSecondary,
                              ),
                            ),
                          )
                        else
                          for (final template in templateViews)
                            _PickableTemplateTile(
                              templateId: template.id,
                              templateName: template.name,
                              subtitle: null,
                              tileKey: TemplatePickerSheet.allTemplateTileKey(
                                template.id,
                              ),
                              customizeKey:
                                  TemplatePickerSheet.allTemplateCustomizeKey(
                                template.id,
                              ),
                              result: TemplatePickerResult(
                                workoutTemplateId: template.id,
                              ),
                            ),
                        const SizedBox(height: AppDimens.base),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: TemplatePickerSheet.emptyStateKey,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.playlist_add_check,
              size: 40,
              color: context.colors.textSecondary,
            ),
            const SizedBox(height: AppDimens.dense),
            Text(
              l10n.templatePickerEmptyTitle,
              style: context.textStyles.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.dense),
            Text(
              l10n.templatePickerEmptyMessage,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: context.textStyles.label.copyWith(
        color: context.colors.textSecondary,
      ),
    );
  }
}

class _UpNextGroup extends StatelessWidget {
  const _UpNextGroup({required this.suggestion});

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
        borderRadius: AppRadii.cardMd,
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
              card.isDone
                  ? _DoneUpNextRow(routineId: suggestion.routineId, card: card)
                  : _PickableTemplateTile(
                      templateId: card.workoutTemplateId,
                      templateName: card.templateName,
                      subtitle: null,
                      tileKey: TemplatePickerSheet.upNextTileKey(
                        suggestion.routineId,
                        card.workoutTemplateId,
                      ),
                      customizeKey: TemplatePickerSheet.upNextCustomizeKey(
                        suggestion.routineId,
                        card.workoutTemplateId,
                      ),
                      result: TemplatePickerResult(
                        workoutTemplateId: card.workoutTemplateId,
                        routineId: suggestion.routineId,
                        slot: suggestion.slot,
                      ),
                    ),
          ],
        ),
      ),
    );
  }
}

class _DoneUpNextRow extends StatelessWidget {
  const _DoneUpNextRow({required this.routineId, required this.card});

  final String routineId;
  final UpNextCardView card;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      key: TemplatePickerSheet.upNextDoneKey(routineId, card.workoutTemplateId),
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
}

class _RoutineGroup extends StatelessWidget {
  const _RoutineGroup({required this.routine});

  final TemplatePickerRoutineView routine;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cadenceKind = routine.cadenceKind;
    final subtitle = switch (cadenceKind) {
      CadenceKind.weekly => l10n.routinePlansCadenceWeekly,
      CadenceKind.rotating => l10n.routinePlansCadenceRotating,
      null => l10n.routinePlansCadenceNone,
    };
    return Card(
      key: TemplatePickerSheet.routineHeaderKey(routine.routineId),
      margin: const EdgeInsets.only(bottom: AppDimens.dense),
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
      child: ExpansionTile(
        title: Text(routine.routineName, style: context.textStyles.h2),
        subtitle: Text(
          subtitle,
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        children: [
          for (final entry in routine.entries)
            _PickableTemplateTile(
              templateId: entry.workoutTemplateId,
              templateName: entry.templateName,
              subtitle: entry.slot == null || cadenceKind == null
                  ? null
                  : localizedCadenceSlotLabel(
                      l10n,
                      kind: cadenceKind,
                      slot: entry.slot!,
                    ),
              tileKey:
                  TemplatePickerSheet.routineEntryTileKey(entry.routineEntryId),
              customizeKey: TemplatePickerSheet.routineEntryCustomizeKey(
                entry.routineEntryId,
              ),
              result: TemplatePickerResult(
                workoutTemplateId: entry.workoutTemplateId,
                routineId: routine.routineId,
                slot: entry.slot,
              ),
            ),
        ],
      ),
    );
  }
}

/// One row that can materialize a Template: the default tap pops the sheet
/// immediately with [result]; the trailing "customize" affordance opens a
/// read-only preview first and only pops the sheet if the athlete confirms
/// Start there — both paths resolve the exact same [result], so both
/// produce a Template Link identically (ROUTINES.md §3.2).
class _PickableTemplateTile extends StatelessWidget {
  const _PickableTemplateTile({
    required this.templateId,
    required this.templateName,
    required this.subtitle,
    required this.tileKey,
    required this.customizeKey,
    required this.result,
  });

  final String templateId;
  final String templateName;
  final String? subtitle;
  final Key tileKey;
  final Key customizeKey;
  final TemplatePickerResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        key: tileKey,
        minTileHeight: AppDimens.rowHeight,
        title: Text(templateName, style: context.textStyles.h2),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: context.textStyles.body.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
        onTap: () => Navigator.of(context).pop(result),
        trailing: IconButton(
          key: customizeKey,
          tooltip: l10n.templatePickerCustomizeTooltip(templateName),
          icon: const Icon(Icons.tune),
          onPressed: () => _customize(context),
        ),
      ),
    );
  }

  Future<void> _customize(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirmed = await showTemplatePickerPreviewSheet(
      context,
      templateId: templateId,
      templateName: templateName,
    );
    if (confirmed == true) {
      navigator.pop(result);
    }
  }
}

/// Opens a read-only "look before you start" preview of one Workout
/// Template's exercises (ROUTINES.md §3.2's "customize (preview/trim)"
/// gesture). Trimming itself happens in-session, in the ordinary Workout
/// screen, once materialized — this preview never edits the Template or the
/// future Workout, it only lets the athlete confirm before committing.
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
