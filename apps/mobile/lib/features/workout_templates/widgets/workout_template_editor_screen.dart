import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/training/plan_validation.dart';
import '../../../domain/training/training_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../catalog/widgets/exercise_catalog_picker.dart';
import '../../settings/repositories/settings_repository.dart';
import '../controllers/workout_template_controller.dart';
import '../repositories/workout_template_feature_repository.dart';
import 'template_group_editor_sheet.dart';

class WorkoutTemplateEditorScreen extends ConsumerStatefulWidget {
  const WorkoutTemplateEditorScreen({
    required this.templateId,
    super.key,
  });

  static const routeName = '/library/training/workout-templates/edit';
  static const nameFieldKey = Key('workoutTemplateEditor.name');
  static const notesFieldKey = Key('workoutTemplateEditor.notes');
  static const saveDetailsButtonKey = Key('workoutTemplateEditor.saveDetails');
  static const addExerciseButtonKey = Key('workoutTemplateEditor.addExercise');
  static const exercisePickerKey = Key('workoutTemplateEditor.exercisePicker');
  static const exerciseNotesFieldKey =
      Key('workoutTemplateEditor.exerciseNotes');
  static const saveExerciseNotesButtonKey =
      Key('workoutTemplateEditor.exerciseNotes.save');
  static const prescriptionModeKey =
      Key('workoutTemplateEditor.prescription.mode');
  static const prescriptionRepeatFieldKey =
      Key('workoutTemplateEditor.prescription.repeat');
  static const prescriptionRestFieldKey =
      Key('workoutTemplateEditor.prescription.rest');
  static const savePrescriptionButtonKey =
      Key('workoutTemplateEditor.prescription.save');
  static const addGroupButtonKey = Key('workoutTemplateEditor.group.add');

  static Key exerciseCardKey(String id) =>
      Key('workoutTemplateEditor.exercise.$id');
  static Key reorderExerciseHandleKey(String id) =>
      Key('workoutTemplateEditor.exercise.reorder.$id');
  static Key editExerciseNotesButtonKey(String id) =>
      Key('workoutTemplateEditor.exercise.notes.$id');
  static Key removeExerciseButtonKey(String id) =>
      Key('workoutTemplateEditor.exercise.remove.$id');
  static Key addPrescriptionButtonKey(String id) =>
      Key('workoutTemplateEditor.exercise.prescription.add.$id');
  static Key prescriptionTileKey(String id) =>
      Key('workoutTemplateEditor.prescription.$id');
  static Key reorderPrescriptionHandleKey(String id) =>
      Key('workoutTemplateEditor.prescription.reorder.$id');
  static Key removePrescriptionButtonKey(String id) =>
      Key('workoutTemplateEditor.prescription.remove.$id');
  static Key prescriptionDimensionFieldKey(DimensionId dimension) =>
      Key('workoutTemplateEditor.prescription.${dimension.name}');
  static Key groupTileKey(String id) => Key('workoutTemplateEditor.group.$id');
  static Key reorderGroupHandleKey(String id) =>
      Key('workoutTemplateEditor.group.reorder.$id');
  static Key groupMenuButtonKey(String id) =>
      Key('workoutTemplateEditor.group.menu.$id');
  static Key moveGroupEarlierKey(String id) =>
      Key('workoutTemplateEditor.group.moveEarlier.$id');
  static Key moveGroupLaterKey(String id) =>
      Key('workoutTemplateEditor.group.moveLater.$id');
  static Key editGroupKey(String id) =>
      Key('workoutTemplateEditor.group.edit.$id');
  static Key dissolveGroupKey(String id) =>
      Key('workoutTemplateEditor.group.dissolve.$id');
  static Key groupColorKey(String id) =>
      Key('workoutTemplateEditor.group.color.$id');

  final String templateId;

  @override
  ConsumerState<WorkoutTemplateEditorScreen> createState() =>
      _WorkoutTemplateEditorScreenState();
}

class _WorkoutTemplateEditorScreenState
    extends ConsumerState<WorkoutTemplateEditorScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  bool _detailsBound = false;
  bool _savingDetails = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(
      workoutTemplateDetailControllerProvider(widget.templateId),
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.workoutTemplateEditorTitle)),
      body: SafeArea(
        child: detail.when(
          data: (template) {
            if (template == null) {
              return _UnavailableMessage();
            }
            _bindDetails(template);
            return _buildEditor(template);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _UnavailableMessage(),
        ),
      ),
    );
  }

  void _bindDetails(WorkoutTemplateDetail template) {
    if (_detailsBound) {
      return;
    }
    _detailsBound = true;
    _nameController.text = template.name;
    _notesController.text = template.notes ?? '';
  }

  Widget _buildEditor(WorkoutTemplateDetail template) {
    final l10n = context.l10n;
    final groupByExerciseId = <String, TemplateGroupDetail>{
      for (final group in template.groups)
        for (final member in group.members) member.templateExerciseId: group,
    };
    return ListView(
      padding: const EdgeInsets.all(AppDimens.base),
      children: [
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.cardMd,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: WorkoutTemplateEditorScreen.nameFieldKey,
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.workoutTemplatesNameLabel,
                  ),
                ),
                const SizedBox(height: AppDimens.base),
                TextField(
                  key: WorkoutTemplateEditorScreen.notesFieldKey,
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l10n.workoutTemplatesNotesLabel,
                  ),
                ),
                const SizedBox(height: AppDimens.base),
                FilledButton.icon(
                  key: WorkoutTemplateEditorScreen.saveDetailsButtonKey,
                  onPressed:
                      _savingDetails ? null : () => unawaited(_saveDetails()),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.workoutTemplateSaveDetails),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppDimens.base),
        _TemplateGroupsSection(
          template: template,
          onAdd: () => unawaited(_editTemplateGroup(template)),
          onEdit: (group) => unawaited(_editTemplateGroup(template, group)),
          onDissolve: (group) =>
              unawaited(_confirmDissolveTemplateGroup(group)),
          onReorder: (oldIndex, newIndex) =>
              _reorderTemplateGroups(template, oldIndex, newIndex),
          onMove: (oldIndex, newIndex) =>
              _moveTemplateGroup(template, oldIndex, newIndex),
        ),
        const SizedBox(height: AppDimens.base),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppDimens.dense,
          runSpacing: AppDimens.dense,
          children: [
            Text(
              l10n.workoutTemplateExercisesHeading,
              style: context.textStyles.h2,
            ),
            TextButton.icon(
              key: WorkoutTemplateEditorScreen.addExerciseButtonKey,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.textPrimary,
              ),
              onPressed: () => unawaited(_openExercisePicker()),
              icon: const Icon(Icons.add),
              label: Text(l10n.workoutTemplateAddExercise),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.dense),
        if (template.exercises.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.base),
            child: Text(
              l10n.workoutTemplateNoExercises,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: template.exercises.length,
            onReorderItem: (oldIndex, newIndex) =>
                _reorderExercises(template, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final exercise = template.exercises[index];
              return Padding(
                key: ValueKey<String>(exercise.id),
                padding: EdgeInsets.only(
                  bottom: index == template.exercises.length - 1
                      ? 0
                      : AppDimens.dense,
                ),
                child: _TemplateExerciseCard(
                  key: WorkoutTemplateEditorScreen.exerciseCardKey(exercise.id),
                  exercise: exercise,
                  group: groupByExerciseId[exercise.id],
                  reorderIndex: index,
                  onEditNotes: () => unawaited(_editExerciseNotes(exercise)),
                  onRemove: () => unawaited(
                    _confirmRemoveExercise(
                      exercise,
                      group: groupByExerciseId[exercise.id],
                    ),
                  ),
                  onAddPrescription: () =>
                      unawaited(_editPrescription(exercise)),
                  onEditPrescription: (prescription) =>
                      unawaited(_editPrescription(exercise, prescription)),
                  onRemovePrescription: (prescription) =>
                      unawaited(_removePrescription(prescription)),
                  onReorderPrescriptions: (oldIndex, newIndex) =>
                      _reorderPrescriptions(exercise, oldIndex, newIndex),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _saveDetails() async {
    if (_nameController.text.trim().isEmpty) {
      _showFailure();
      return;
    }
    setState(() => _savingDetails = true);
    try {
      await ref
          .read(workoutTemplateListControllerProvider.notifier)
          .updateTemplate(
            templateId: widget.templateId,
            name: _nameController.text,
            notes: _notesController.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.workoutTemplateDetailsSaved)),
        );
      }
    } on Object {
      if (mounted) {
        _showFailure();
      }
    } finally {
      if (mounted) {
        setState(() => _savingDetails = false);
      }
    }
  }

  Future<void> _openExercisePicker() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (pickerContext) => Scaffold(
          appBar: AppBar(
            title: Text(
              pickerContext.l10n.workoutTemplateExercisePickerTitle,
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.base),
              child: ExerciseCatalogPicker(
                key: WorkoutTemplateEditorScreen.exercisePickerKey,
                onExerciseSelected: (exercise) {
                  unawaited(() async {
                    try {
                      await ref
                          .read(
                            workoutTemplateListControllerProvider.notifier,
                          )
                          .addExercise(
                            templateId: widget.templateId,
                            exerciseId: exercise.id,
                          );
                      if (pickerContext.mounted) {
                        Navigator.of(pickerContext).pop();
                      }
                    } on Object {
                      if (pickerContext.mounted) {
                        ScaffoldMessenger.of(pickerContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              pickerContext.l10n.workoutTemplatesActionFailed,
                            ),
                          ),
                        );
                      }
                    }
                  }());
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editExerciseNotes(TemplateExerciseDetail exercise) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ExerciseNotesSheet(
        initialNotes: exercise.notes,
        onSave: (notes) async {
          await ref
              .read(workoutTemplateListControllerProvider.notifier)
              .updateExerciseNotes(
                templateExerciseId: exercise.id,
                notes: notes,
              );
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop();
          }
        },
      ),
    );
  }

  Future<void> _confirmRemoveExercise(
    TemplateExerciseDetail exercise, {
    TemplateGroupDetail? group,
  }) async {
    if (group != null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            dialogContext.l10n.workoutTemplateGroupedExerciseRemoveTitle(
              group.name,
            ),
          ),
          content: Text(
            dialogContext.l10n.workoutTemplateGroupedExerciseRemoveMessage,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child:
                  Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.workoutTemplateRemoveExerciseTitle),
        content: Text(dialogContext.l10n.workoutTemplateRemoveExerciseMessage),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: dialogContext.colors.textPrimary,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.workoutTemplatesCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              minimumSize: const Size(0, AppDimens.rowHeight),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.workoutTemplateRemoveExercise),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref
          .read(workoutTemplateListControllerProvider.notifier)
          .removeExercise(exercise.id);
    } on Object {
      if (mounted) {
        _showFailure();
      }
    }
  }

  void _reorderExercises(
    WorkoutTemplateDetail template,
    int oldIndex,
    int newIndex,
  ) {
    final adjustedNewIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (adjustedNewIndex == oldIndex) {
      return;
    }
    final reordered = List<TemplateExerciseDetail>.of(template.exercises);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(adjustedNewIndex, moved);
    unawaited(
      ref
          .read(workoutTemplateListControllerProvider.notifier)
          .reorderExercises(
            templateId: template.id,
            orderedIds: reordered
                .map((exercise) => exercise.id)
                .toList(growable: false),
          )
          .catchError((Object _) {
        if (mounted) {
          _showFailure();
        }
      }),
    );
  }

  Future<void> _editTemplateGroup(
    WorkoutTemplateDetail template, [
    TemplateGroupDetail? group,
  ]) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => TemplateGroupEditorSheet(
        exercises: template.exercises,
        groups: template.groups,
        group: group,
        defaultColorHex: _colorToHex(
          sheetContext.colors.categoryColor('other'),
        ),
        onSave: (input) async {
          final controller = ref.read(
            workoutTemplateListControllerProvider.notifier,
          );
          if (group == null) {
            await controller.createTemplateGroup(
              templateId: template.id,
              input: input,
            );
          } else {
            await controller.updateTemplateGroup(
              groupId: group.id,
              input: input,
            );
          }
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop();
          }
        },
      ),
    );
  }

  void _reorderTemplateGroups(
    WorkoutTemplateDetail template,
    int oldIndex,
    int newIndex,
  ) {
    final adjustedNewIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _moveTemplateGroup(template, oldIndex, adjustedNewIndex);
  }

  void _moveTemplateGroup(
    WorkoutTemplateDetail template,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex == oldIndex ||
        newIndex < 0 ||
        newIndex >= template.groups.length) {
      return;
    }
    final reordered = List<TemplateGroupDetail>.of(template.groups);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    unawaited(
      ref
          .read(workoutTemplateListControllerProvider.notifier)
          .reorderTemplateGroups(
            templateId: template.id,
            orderedIds:
                reordered.map((group) => group.id).toList(growable: false),
          )
          .catchError((Object _) {
        if (mounted) {
          _showGroupFailure();
        }
      }),
    );
  }

  Future<void> _confirmDissolveTemplateGroup(
    TemplateGroupDetail group,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.l10n.workoutTemplateDissolveGroupTitle(group.name),
        ),
        content: Text(
          dialogContext.l10n.workoutTemplateDissolveGroupMessage,
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: dialogContext.colors.textPrimary,
              minimumSize: const Size(0, AppDimens.rowHeight),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.workoutTemplatesCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              minimumSize: const Size(0, AppDimens.rowHeight),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.workoutTemplateDissolveGroup),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref
          .read(workoutTemplateListControllerProvider.notifier)
          .dissolveTemplateGroup(group.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.workoutTemplateDissolveGroupSuccess),
          ),
        );
      }
    } on Object {
      if (mounted) {
        _showGroupFailure();
      }
    }
  }

  Future<void> _editPrescription(
    TemplateExerciseDetail exercise, [
    PrescriptionDetail? prescription,
  ]) {
    final unitSystem = ref.read(settingsControllerProvider).value?.unitSystem ??
        AppSettings.defaults.unitSystem;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => PrescriptionEditorSheet(
        exercise: exercise,
        prescription: prescription,
        unitSystem: unitSystem,
        onSave: (input) async {
          if (prescription == null) {
            await ref
                .read(workoutTemplateListControllerProvider.notifier)
                .addPrescription(
                  templateExerciseId: exercise.id,
                  input: input,
                );
          } else {
            await ref
                .read(workoutTemplateListControllerProvider.notifier)
                .updatePrescription(
                  prescriptionId: prescription.id,
                  input: input,
                );
          }
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop();
          }
        },
      ),
    );
  }

  Future<void> _removePrescription(PrescriptionDetail prescription) async {
    try {
      await ref
          .read(workoutTemplateListControllerProvider.notifier)
          .removePrescription(prescription.id);
    } on Object {
      if (mounted) {
        _showFailure();
      }
    }
  }

  void _reorderPrescriptions(
    TemplateExerciseDetail exercise,
    int oldIndex,
    int newIndex,
  ) {
    final adjustedNewIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (adjustedNewIndex == oldIndex) {
      return;
    }
    final reordered = List<PrescriptionDetail>.of(exercise.prescriptions);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(adjustedNewIndex, moved);
    unawaited(
      ref
          .read(workoutTemplateListControllerProvider.notifier)
          .reorderPrescriptions(
            templateExerciseId: exercise.id,
            orderedIds: reordered
                .map((prescription) => prescription.id)
                .toList(growable: false),
          )
          .catchError((Object _) {
        if (mounted) {
          _showFailure();
        }
      }),
    );
  }

  void _showFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.workoutTemplatesActionFailed)),
    );
  }

  void _showGroupFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.workoutTemplateGroupActionFailed)),
    );
  }
}

class _UnavailableMessage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Text(
          context.l10n.workoutTemplateUnavailable,
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _TemplateGroupsSection extends StatelessWidget {
  const _TemplateGroupsSection({
    required this.template,
    required this.onAdd,
    required this.onEdit,
    required this.onDissolve,
    required this.onReorder,
    required this.onMove,
  });

  final WorkoutTemplateDetail template;
  final VoidCallback onAdd;
  final ValueChanged<TemplateGroupDetail> onEdit;
  final ValueChanged<TemplateGroupDetail> onDissolve;
  final ReorderCallback onReorder;
  final void Function(int oldIndex, int newIndex) onMove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final groupedIds = <String>{
      for (final group in template.groups)
        for (final member in group.members) member.templateExerciseId,
    };
    final canAdd = template.exercises
            .where((exercise) => !groupedIds.contains(exercise.id))
            .length >=
        2;
    final exerciseNames = <String, String>{
      for (final exercise in template.exercises) exercise.id: exercise.name,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppDimens.dense,
          runSpacing: AppDimens.dense,
          children: [
            Text(l10n.workoutTemplateGroupsHeading,
                style: context.textStyles.h2),
            Tooltip(
              message: canAdd
                  ? l10n.workoutTemplateAddGroup
                  : l10n.workoutTemplateGroupNeedsExercises,
              child: TextButton.icon(
                key: WorkoutTemplateEditorScreen.addGroupButtonKey,
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                ),
                onPressed: canAdd ? onAdd : null,
                icon: const Icon(Icons.add),
                label: Text(l10n.workoutTemplateAddGroup),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.dense),
        if (template.groups.isEmpty)
          Text(
            canAdd
                ? l10n.workoutTemplateNoGroups
                : l10n.workoutTemplateGroupNeedsExercises,
            style: context.textStyles.body.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: template.groups.length,
            onReorderItem: onReorder,
            itemBuilder: (context, index) {
              final group = template.groups[index];
              final memberNames = group.members
                  .map((member) => exerciseNames[member.templateExerciseId])
                  .whereType<String>()
                  .toList(growable: false);
              return Padding(
                key: ValueKey<String>(group.id),
                padding: EdgeInsets.only(
                  bottom:
                      index == template.groups.length - 1 ? 0 : AppDimens.dense,
                ),
                child: _TemplateGroupTile(
                  key: WorkoutTemplateEditorScreen.groupTileKey(group.id),
                  group: group,
                  memberNames: memberNames,
                  reorderIndex: index,
                  canMoveEarlier: index > 0,
                  canMoveLater: index < template.groups.length - 1,
                  onEdit: () => onEdit(group),
                  onMoveEarlier: () => onMove(index, index - 1),
                  onMoveLater: () => onMove(index, index + 1),
                  onDissolve: () => onDissolve(group),
                ),
              );
            },
          ),
      ],
    );
  }
}

enum _TemplateGroupMenuAction { edit, moveEarlier, moveLater, dissolve }

class _TemplateGroupTile extends StatelessWidget {
  const _TemplateGroupTile({
    required this.group,
    required this.memberNames,
    required this.reorderIndex,
    required this.canMoveEarlier,
    required this.canMoveLater,
    required this.onEdit,
    required this.onMoveEarlier,
    required this.onMoveLater,
    required this.onDissolve,
    super.key,
  });

  final TemplateGroupDetail group;
  final List<String> memberNames;
  final int reorderIndex;
  final bool canMoveEarlier;
  final bool canMoveLater;
  final VoidCallback onEdit;
  final VoidCallback onMoveEarlier;
  final VoidCallback onMoveLater;
  final VoidCallback onDissolve;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rounds = l10n.workoutTemplateGroupRoundsCount(group.rounds);
    final members = l10n.workoutTemplateGroupMemberCount(memberNames.length);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
      child: ListTile(
        contentPadding: const EdgeInsets.only(
          left: AppDimens.dense,
          right: AppDimens.dense,
        ),
        minTileHeight: AppDimens.rowHeight,
        leading: Semantics(
          button: true,
          label: l10n.workoutTemplateReorderGroup(group.name),
          child: ReorderableDragStartListener(
            key: WorkoutTemplateEditorScreen.reorderGroupHandleKey(group.id),
            index: reorderIndex,
            child: const SizedBox.square(
              dimension: AppDimens.touchTarget,
              child: Icon(Icons.drag_handle),
            ),
          ),
        ),
        title: Row(
          children: [
            Semantics(
              container: true,
              label: l10n.workoutTemplateGroupColorIndicator(group.name),
              child: Container(
                key: WorkoutTemplateEditorScreen.groupColorKey(group.id),
                width: AppDimens.dense,
                height: AppDimens.touchTarget,
                decoration: BoxDecoration(
                  color: colorFromHex(
                    group.colorHex,
                    fallback: context.colors.categoryColor('other'),
                  ),
                  border: Border.all(color: context.colors.textSecondary),
                  borderRadius: AppRadii.chipFull,
                ),
              ),
            ),
            const SizedBox(width: AppDimens.dense),
            Expanded(child: Text(group.name, style: context.textStyles.h2)),
          ],
        ),
        subtitle: Text(
          memberNames.isEmpty
              ? '$rounds · $members'
              : '$rounds · $members\n${memberNames.join(', ')}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onEdit,
        trailing: PopupMenuButton<_TemplateGroupMenuAction>(
          key: WorkoutTemplateEditorScreen.groupMenuButtonKey(group.id),
          tooltip: l10n.workoutTemplateGroupActions(group.name),
          onSelected: (action) {
            switch (action) {
              case _TemplateGroupMenuAction.edit:
                onEdit();
              case _TemplateGroupMenuAction.moveEarlier:
                onMoveEarlier();
              case _TemplateGroupMenuAction.moveLater:
                onMoveLater();
              case _TemplateGroupMenuAction.dissolve:
                onDissolve();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<_TemplateGroupMenuAction>(
              key: WorkoutTemplateEditorScreen.editGroupKey(group.id),
              value: _TemplateGroupMenuAction.edit,
              child: Text(l10n.workoutTemplateEditGroup),
            ),
            PopupMenuItem<_TemplateGroupMenuAction>(
              key: WorkoutTemplateEditorScreen.moveGroupEarlierKey(group.id),
              value: _TemplateGroupMenuAction.moveEarlier,
              enabled: canMoveEarlier,
              child: Text(l10n.workoutTemplateMoveGroupEarlier),
            ),
            PopupMenuItem<_TemplateGroupMenuAction>(
              key: WorkoutTemplateEditorScreen.moveGroupLaterKey(group.id),
              value: _TemplateGroupMenuAction.moveLater,
              enabled: canMoveLater,
              child: Text(l10n.workoutTemplateMoveGroupLater),
            ),
            PopupMenuItem<_TemplateGroupMenuAction>(
              key: WorkoutTemplateEditorScreen.dissolveGroupKey(group.id),
              value: _TemplateGroupMenuAction.dissolve,
              child: Text(
                l10n.workoutTemplateDissolveGroup,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateExerciseCard extends StatelessWidget {
  const _TemplateExerciseCard({
    required this.exercise,
    required this.group,
    required this.reorderIndex,
    required this.onEditNotes,
    required this.onRemove,
    required this.onAddPrescription,
    required this.onEditPrescription,
    required this.onRemovePrescription,
    required this.onReorderPrescriptions,
    super.key,
  });

  final TemplateExerciseDetail exercise;
  final TemplateGroupDetail? group;
  final int reorderIndex;
  final VoidCallback onEditNotes;
  final VoidCallback onRemove;
  final VoidCallback onAddPrescription;
  final ValueChanged<PrescriptionDetail> onEditPrescription;
  final ValueChanged<PrescriptionDetail> onRemovePrescription;
  final ReorderCallback onReorderPrescriptions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.cardMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          if (group != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: AppDimens.supersetBar,
              child: ExcludeSemantics(
                child: ColoredBox(
                  color: colorFromHex(
                    group!.colorHex,
                    fallback: context.colors.categoryColor('other'),
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppDimens.base + (group == null ? 0 : AppDimens.supersetBar),
              AppDimens.base,
              AppDimens.base,
              AppDimens.base,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Semantics(
                      button: true,
                      label: l10n.workoutTemplateReorderExercise,
                      child: ReorderableDragStartListener(
                        key: WorkoutTemplateEditorScreen
                            .reorderExerciseHandleKey(
                          exercise.id,
                        ),
                        index: reorderIndex,
                        child: const SizedBox.square(
                          dimension: AppDimens.touchTarget,
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(exercise.name, style: context.textStyles.h2),
                    ),
                    IconButton(
                      key: WorkoutTemplateEditorScreen
                          .editExerciseNotesButtonKey(
                        exercise.id,
                      ),
                      tooltip: l10n.workoutTemplateEditExerciseNotes,
                      onPressed: onEditNotes,
                      icon: const Icon(Icons.notes_outlined),
                    ),
                    IconButton(
                      key: WorkoutTemplateEditorScreen.removeExerciseButtonKey(
                        exercise.id,
                      ),
                      tooltip: l10n.workoutTemplateRemoveExercise,
                      onPressed: onRemove,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
                if (group != null) ...[
                  const SizedBox(height: AppDimens.dense),
                  Text(
                    l10n.workoutTemplateGroupMembership(
                      group!.name,
                      group!.rounds,
                    ),
                    style: context.textStyles.label.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
                if (exercise.notes != null) ...[
                  const SizedBox(height: AppDimens.dense),
                  Text(
                    exercise.notes!,
                    style: context.textStyles.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppDimens.dense),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppDimens.dense,
                  runSpacing: AppDimens.dense,
                  children: [
                    Text(
                      l10n.workoutTemplatePrescriptionsHeading,
                      style: context.textStyles.label,
                    ),
                    TextButton.icon(
                      key: WorkoutTemplateEditorScreen.addPrescriptionButtonKey(
                        exercise.id,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: context.colors.textPrimary,
                      ),
                      onPressed: onAddPrescription,
                      icon: const Icon(Icons.add),
                      label: Text(l10n.workoutTemplateAddPrescription),
                    ),
                  ],
                ),
                if (exercise.prescriptions.isEmpty)
                  Text(
                    l10n.workoutTemplateNoPrescriptions,
                    style: context.textStyles.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  )
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: exercise.prescriptions.length,
                    onReorderItem: onReorderPrescriptions,
                    itemBuilder: (context, index) {
                      final prescription = exercise.prescriptions[index];
                      return ListTile(
                        key: ValueKey<String>(prescription.id),
                        minTileHeight: AppDimens.rowHeight,
                        contentPadding: EdgeInsets.zero,
                        leading: Semantics(
                          button: true,
                          label: l10n.workoutTemplateReorderPrescription,
                          child: ReorderableDragStartListener(
                            key: WorkoutTemplateEditorScreen
                                .reorderPrescriptionHandleKey(prescription.id),
                            index: index,
                            child: const SizedBox.square(
                              dimension: AppDimens.touchTarget,
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ),
                        title: Text(
                          _prescriptionSummary(context, exercise, prescription),
                          key: WorkoutTemplateEditorScreen.prescriptionTileKey(
                            prescription.id,
                          ),
                        ),
                        onTap: () => onEditPrescription(prescription),
                        trailing: IconButton(
                          key: WorkoutTemplateEditorScreen
                              .removePrescriptionButtonKey(prescription.id),
                          tooltip: l10n.workoutTemplateRemovePrescription,
                          onPressed: () => onRemovePrescription(prescription),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseNotesSheet extends StatefulWidget {
  const _ExerciseNotesSheet({
    required this.initialNotes,
    required this.onSave,
  });

  final String? initialNotes;
  final Future<void> Function(String notes) onSave;

  @override
  State<_ExerciseNotesSheet> createState() => _ExerciseNotesSheetState();
}

class _ExerciseNotesSheetState extends State<_ExerciseNotesSheet> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNotes ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppDimens.base,
          top: AppDimens.base,
          right: AppDimens.base,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppDimens.base,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.workoutTemplateEditExerciseNotes,
                style: context.textStyles.h2,
              ),
              const SizedBox(height: AppDimens.base),
              TextField(
                key: WorkoutTemplateEditorScreen.exerciseNotesFieldKey,
                controller: _controller,
                minLines: 3,
                maxLines: 6,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.l10n.workoutTemplateExerciseNotes,
                ),
              ),
              const SizedBox(height: AppDimens.base),
              FilledButton.icon(
                key: WorkoutTemplateEditorScreen.saveExerciseNotesButtonKey,
                onPressed: _saving
                    ? null
                    : () {
                        final messenger = ScaffoldMessenger.of(context);
                        final failureMessage =
                            context.l10n.workoutTemplatesActionFailed;
                        setState(() => _saving = true);
                        unawaited(
                          widget
                              .onSave(_controller.text)
                              .catchError((Object _) {
                            if (mounted) {
                              setState(() => _saving = false);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(failureMessage),
                                ),
                              );
                            }
                          }),
                        );
                      },
                icon: const Icon(Icons.save_outlined),
                label: Text(context.l10n.workoutTemplateSaveExerciseNotes),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class PrescriptionEditorSheet extends StatefulWidget {
  const PrescriptionEditorSheet({
    required this.exercise,
    required this.onSave,
    this.prescription,
    this.unitSystem = UnitSystem.metric,
    super.key,
  });

  final TemplateExerciseDetail exercise;
  final PrescriptionDetail? prescription;
  final UnitSystem unitSystem;
  final Future<void> Function(PrescriptionInput input) onSave;

  @override
  State<PrescriptionEditorSheet> createState() =>
      _PrescriptionEditorSheetState();
}

class _PrescriptionEditorSheetState extends State<PrescriptionEditorSheet> {
  late TemplatePrescriptionMode _mode;
  late final Map<DimensionId, TextEditingController> _valueControllers;
  late final TextEditingController _repeatController;
  late final TextEditingController _restController;
  String? _errorText;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final prescription = widget.prescription;
    _mode = prescription?.mode ?? TemplatePrescriptionMode.fixed;
    _valueControllers = <DimensionId, TextEditingController>{
      for (final dimension in widget.exercise.type.dimensions)
        dimension: TextEditingController(
          text: prescription?.values.valueFor(dimension)?.entered ?? '',
        ),
    };
    _repeatController = TextEditingController(
      text: '${prescription?.repeat ?? 1}',
    );
    _restController = TextEditingController(
      text: prescription?.restAfter?.inSeconds.toString() ?? '',
    );
  }

  @override
  void dispose() {
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    _repeatController.dispose();
    _restController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppDimens.base,
          top: AppDimens.base,
          right: AppDimens.base,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppDimens.base,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.prescription == null
                    ? l10n.workoutTemplateAddPrescription
                    : l10n.workoutTemplateEditPrescription,
                style: context.textStyles.h2,
              ),
              const SizedBox(height: AppDimens.base),
              Semantics(
                label: l10n.workoutTemplatePrescriptionMode,
                child: SegmentedButton<TemplatePrescriptionMode>(
                  key: WorkoutTemplateEditorScreen.prescriptionModeKey,
                  segments: <ButtonSegment<TemplatePrescriptionMode>>[
                    ButtonSegment<TemplatePrescriptionMode>(
                      value: TemplatePrescriptionMode.fixed,
                      label: Text(l10n.workoutTemplatePrescriptionFixed),
                    ),
                    ButtonSegment<TemplatePrescriptionMode>(
                      value: TemplatePrescriptionMode.copyPrevious,
                      label: Text(l10n.workoutTemplatePrescriptionCopyPrevious),
                    ),
                  ],
                  selected: <TemplatePrescriptionMode>{_mode},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _mode = selection.single;
                      _errorText = null;
                    });
                  },
                ),
              ),
              const SizedBox(height: AppDimens.base),
              if (_mode == TemplatePrescriptionMode.copyPrevious)
                Text(
                  l10n.workoutTemplatePrescriptionCopyPreviousHelp,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                )
              else if (widget.exercise.type.isCompletionOnly)
                Text(
                  l10n.workoutTemplatePrescriptionCompletion,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                )
              else
                for (final dimension in widget.exercise.type.dimensions) ...[
                  TextField(
                    key: WorkoutTemplateEditorScreen
                        .prescriptionDimensionFieldKey(dimension),
                    controller: _valueControllers[dimension],
                    decoration: InputDecoration(
                      labelText: _dimensionLabel(context, dimension),
                      suffixText: _unitLabel(
                        context,
                        _unitForDimension(dimension),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: AppDimens.base),
                ],
              if (_mode == TemplatePrescriptionMode.copyPrevious ||
                  widget.exercise.type.isCompletionOnly)
                const SizedBox(height: AppDimens.base),
              TextField(
                key: WorkoutTemplateEditorScreen.prescriptionRepeatFieldKey,
                controller: _repeatController,
                decoration: InputDecoration(
                  labelText: l10n.workoutTemplatePrescriptionRepeat,
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppDimens.base),
              TextField(
                key: WorkoutTemplateEditorScreen.prescriptionRestFieldKey,
                controller: _restController,
                decoration: InputDecoration(
                  labelText: l10n.workoutTemplatePrescriptionRestAfter,
                  suffixText: l10n.workoutTemplatePrescriptionSeconds,
                ),
                keyboardType: TextInputType.number,
              ),
              if (_errorText != null) ...[
                const SizedBox(height: AppDimens.dense),
                Text(
                  _errorText!,
                  style: context.textStyles.body.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppDimens.base),
              FilledButton.icon(
                key: WorkoutTemplateEditorScreen.savePrescriptionButtonKey,
                onPressed: _saving ? null : () => unawaited(_save()),
                icon: const Icon(Icons.save_outlined),
                label: Text(l10n.workoutTemplateSavePrescription),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final input = _buildInput();
    if (input == null) {
      setState(() {
        _errorText = context.l10n.workoutTemplatePrescriptionInvalid;
      });
      return;
    }
    final result = validatePrescription(
      mode: input.mode == TemplatePrescriptionMode.fixed
          ? 'fixed'
          : 'copyPrevious',
      dimensions: widget.exercise.type.dimensions,
      loadMode: widget.exercise.loadMode,
      repeat: input.repeat,
      restAfterSeconds: input.restAfter?.inSeconds,
      values: input.values.values.values,
    );
    if (!result.accepted) {
      setState(() {
        _errorText = result.errors.first.message;
      });
      return;
    }
    if (result.warnings.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            dialogContext.l10n.workoutTemplatePrescriptionWarningTitle,
          ),
          content: Text(result.warnings.first.message),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: dialogContext.colors.textPrimary,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.l10n.workoutTemplatesCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                dialogContext.l10n.workoutTemplatePrescriptionSaveAnyway,
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.onSave(input);
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = context.l10n.workoutTemplatesActionFailed;
        });
      }
    }
  }

  PrescriptionInput? _buildInput() {
    final repeat = int.tryParse(_repeatController.text.trim());
    if (repeat == null || repeat < 1) {
      return null;
    }
    final restText = _restController.text.trim();
    final restSeconds = restText.isEmpty ? null : int.tryParse(restText);
    if (restText.isNotEmpty && (restSeconds == null || restSeconds < 0)) {
      return null;
    }

    LoggedSet values;
    if (_mode == TemplatePrescriptionMode.copyPrevious ||
        widget.exercise.type.isCompletionOnly) {
      values = LoggedSet.completion();
    } else {
      final dimensionValues = <SetDimensionValue>[];
      for (final dimension in widget.exercise.type.dimensions) {
        final entered = _valueControllers[dimension]?.text.trim() ?? '';
        final numeric = double.tryParse(entered);
        if (entered.isEmpty ||
            numeric == null ||
            !numeric.isFinite ||
            numeric < 0) {
          return null;
        }
        dimensionValues.add(
          SetDimensionValue(
            dimension: dimension,
            entered: entered,
            unit: _unitForDimension(dimension),
          ),
        );
      }
      values = LoggedSet.fromValues(dimensionValues);
    }

    return PrescriptionInput(
      mode: _mode,
      repeat: repeat,
      restAfter: restSeconds == null ? null : Duration(seconds: restSeconds),
      values: values,
    );
  }

  TrainingUnit _unitForDimension(DimensionId dimension) {
    return widget.prescription?.values.valueFor(dimension)?.unit ??
        _defaultUnit(widget.exercise, dimension, widget.unitSystem);
  }
}

String _prescriptionSummary(
  BuildContext context,
  TemplateExerciseDetail exercise,
  PrescriptionDetail prescription,
) {
  final l10n = context.l10n;
  final valueSummary =
      prescription.mode == TemplatePrescriptionMode.copyPrevious
          ? l10n.workoutTemplatePrescriptionCopyPreviousSummary
          : exercise.type.isCompletionOnly
              ? l10n.workoutTemplatePrescriptionCompletion
              : exercise.type.dimensions
                  .map((dimension) {
                    final value = prescription.values.valueFor(dimension);
                    if (value == null) {
                      return '';
                    }
                    return '${value.entered} ${_unitLabel(context, value.unit)}';
                  })
                  .where((segment) => segment.isNotEmpty)
                  .join(' · ');
  final details = <String>[valueSummary];
  if (prescription.restAfter != null) {
    details.add(
      '${l10n.workoutTemplatePrescriptionRestAfter} '
      '${prescription.restAfter!.inSeconds} '
      '${l10n.workoutTemplatePrescriptionSeconds}',
    );
  }
  return '${prescription.repeat} × (${details.join(', ')})';
}

TrainingUnit _defaultUnit(
  TemplateExerciseDetail exercise,
  DimensionId dimension,
  UnitSystem unitSystem,
) {
  return switch (dimension) {
    DimensionId.load => exercise.defaultLoadUnit,
    DimensionId.reps => TrainingUnit.repetition,
    DimensionId.duration => TrainingUnit.second,
    DimensionId.distance => switch (unitSystem) {
        UnitSystem.metric => TrainingUnit.kilometer,
        UnitSystem.imperial => TrainingUnit.mile,
      },
  };
}

String _dimensionLabel(BuildContext context, DimensionId dimension) {
  final l10n = context.l10n;
  return switch (dimension) {
    DimensionId.load => l10n.trainingDimensionLoad,
    DimensionId.reps => l10n.trainingDimensionReps,
    DimensionId.duration => l10n.trainingDimensionDuration,
    DimensionId.distance => l10n.trainingDimensionDistance,
  };
}

String _unitLabel(BuildContext context, TrainingUnit unit) {
  final l10n = context.l10n;
  return switch (unit) {
    TrainingUnit.kilogram => l10n.trainingUnitKilogram,
    TrainingUnit.pound => l10n.trainingUnitPound,
    TrainingUnit.repetition => l10n.trainingUnitRepetition,
    TrainingUnit.second => l10n.trainingUnitSecond,
    TrainingUnit.kilometer => l10n.trainingUnitKilometer,
    TrainingUnit.mile => l10n.trainingUnitMile,
  };
}

String _colorToHex(Color color) {
  final rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
