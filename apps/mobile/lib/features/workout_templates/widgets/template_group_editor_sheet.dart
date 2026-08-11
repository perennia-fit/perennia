import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/training/plan_validation.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../repositories/workout_template_feature_repository.dart';

/// Creates or edits one ordered superset/circuit Group in a Workout Template.
///
/// The sheet owns transient form state only. Its caller remains responsible for
/// routing the accepted input through the feature controller and repository.
@visibleForTesting
class TemplateGroupEditorSheet extends StatefulWidget {
  const TemplateGroupEditorSheet({
    required this.exercises,
    required this.groups,
    required this.defaultColorHex,
    required this.onSave,
    this.group,
    super.key,
  });

  static const nameFieldKey = Key('workoutTemplateGroup.name');
  static const colorFieldKey = Key('workoutTemplateGroup.color');
  static const colorPreviewKey = Key('workoutTemplateGroup.colorPreview');
  static const roundsFieldKey = Key('workoutTemplateGroup.rounds');
  static const saveButtonKey = Key('workoutTemplateGroup.save');
  static const memberErrorKey = Key('workoutTemplateGroup.members.error');
  static const actionErrorKey = Key('workoutTemplateGroup.action.error');
  static const selectedMemberListKey =
      Key('workoutTemplateGroup.members.selected');

  static Key memberCheckboxKey(String templateExerciseId) =>
      Key('workoutTemplateGroup.member.$templateExerciseId');
  static Key selectedMemberTileKey(String templateExerciseId) =>
      Key('workoutTemplateGroup.member.selected.$templateExerciseId');
  static Key reorderMemberHandleKey(String templateExerciseId) =>
      Key('workoutTemplateGroup.member.reorder.$templateExerciseId');
  static Key memberMenuButtonKey(String templateExerciseId) =>
      Key('workoutTemplateGroup.member.menu.$templateExerciseId');
  static Key moveMemberEarlierKey(String templateExerciseId) =>
      Key('workoutTemplateGroup.member.moveEarlier.$templateExerciseId');
  static Key moveMemberLaterKey(String templateExerciseId) =>
      Key('workoutTemplateGroup.member.moveLater.$templateExerciseId');
  static Key removeMemberKey(String templateExerciseId) =>
      Key('workoutTemplateGroup.member.remove.$templateExerciseId');

  final List<TemplateExerciseDetail> exercises;
  final List<TemplateGroupDetail> groups;
  final TemplateGroupDetail? group;
  final String defaultColorHex;
  final Future<void> Function(TemplateGroupInput input) onSave;

  @override
  State<TemplateGroupEditorSheet> createState() =>
      _TemplateGroupEditorSheetState();
}

class _TemplateGroupEditorSheetState extends State<TemplateGroupEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _colorController;
  late final TextEditingController _roundsController;
  late final Set<String> _selectedIds;
  late final List<String> _memberOrder;

  String? _nameError;
  String? _colorError;
  String? _roundsError;
  String? _membersError;
  String? _actionError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    _nameController = TextEditingController(text: group?.name ?? '');
    _colorController = TextEditingController(
      text: group?.colorHex ?? widget.defaultColorHex,
    )..addListener(_refreshColorPreview);
    _roundsController = TextEditingController(text: '${group?.rounds ?? 1}');

    if (group != null) {
      final activeExerciseIds =
          widget.exercises.map((exercise) => exercise.id).toSet();
      _memberOrder = group.members
          .map((member) => member.templateExerciseId)
          .where(activeExerciseIds.contains)
          .toList(growable: true);
      _selectedIds = _memberOrder.toSet();
    } else {
      final available = widget.exercises
          .where((exercise) => _otherGroupFor(exercise.id) == null)
          .map((exercise) => exercise.id)
          .toList(growable: false);
      _memberOrder =
          available.length == 2 ? List<String>.of(available) : <String>[];
      _selectedIds = _memberOrder.toSet();
    }
  }

  @override
  void dispose() {
    _colorController.removeListener(_refreshColorPreview);
    _nameController.dispose();
    _colorController.dispose();
    _roundsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorHex = _colorController.text.trim();
    final previewColor = colorFromHex(
      colorHex,
      fallback: context.colors.categoryColor('other'),
    );
    final exerciseById = <String, TemplateExerciseDetail>{
      for (final exercise in widget.exercises) exercise.id: exercise,
    };
    final selectedExercises = _memberOrder
        .map((id) => exerciseById[id])
        .whereType<TemplateExerciseDetail>()
        .toList(growable: false);
    final availableExercises = widget.exercises
        .where((exercise) => !_selectedIds.contains(exercise.id))
        .toList(growable: false);

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
                widget.group == null
                    ? l10n.workoutTemplateCreateGroup
                    : l10n.workoutTemplateEditGroup,
                style: context.textStyles.h2,
              ),
              const SizedBox(height: AppDimens.base),
              TextField(
                key: TemplateGroupEditorSheet.nameFieldKey,
                controller: _nameController,
                enabled: !_saving,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.workoutTemplateGroupName,
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: AppDimens.base),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: TemplateGroupEditorSheet.colorFieldKey,
                      controller: _colorController,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.workoutTemplateGroupColor,
                        errorText: _colorError,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimens.dense),
                  Semantics(
                    label: l10n.workoutTemplateGroupColorPreview(colorHex),
                    child: Container(
                      key: TemplateGroupEditorSheet.colorPreviewKey,
                      width: AppDimens.touchTarget,
                      height: AppDimens.touchTarget,
                      decoration: BoxDecoration(
                        color: previewColor,
                        border: Border.all(color: context.colors.textSecondary),
                        borderRadius: AppRadii.cardMd,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.base),
              TextField(
                key: TemplateGroupEditorSheet.roundsFieldKey,
                controller: _roundsController,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.workoutTemplateGroupRounds,
                  helperText: l10n.workoutTemplateGroupRoundsHelp,
                  errorText: _roundsError,
                ),
              ),
              const SizedBox(height: AppDimens.base),
              Text(
                l10n.workoutTemplateSelectedGroupMembers,
                style: context.textStyles.label,
              ),
              const SizedBox(height: AppDimens.dense),
              if (selectedExercises.isEmpty)
                Text(
                  l10n.workoutTemplateNoSelectedGroupMembers,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                )
              else
                ReorderableListView.builder(
                  key: TemplateGroupEditorSheet.selectedMemberListKey,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: selectedExercises.length,
                  onReorderItem: _reorderMembers,
                  itemBuilder: (context, index) {
                    final exercise = selectedExercises[index];
                    return _SelectedGroupMemberTile(
                      key: TemplateGroupEditorSheet.selectedMemberTileKey(
                        exercise.id,
                      ),
                      exercise: exercise,
                      reorderIndex: index,
                      canMoveEarlier: index > 0,
                      canMoveLater: index < selectedExercises.length - 1,
                      enabled: !_saving,
                      onMoveEarlier: () => _moveMember(index, index - 1),
                      onMoveLater: () => _moveMember(index, index + 1),
                      onRemove: () => _removeMember(exercise.id),
                    );
                  },
                ),
              if (availableExercises.isNotEmpty) ...[
                const SizedBox(height: AppDimens.base),
                Text(
                  l10n.workoutTemplateAvailableGroupMembers,
                  style: context.textStyles.label,
                ),
                const SizedBox(height: AppDimens.dense),
                for (final exercise in availableExercises)
                  _availableMemberTile(context, exercise),
              ],
              if (_membersError != null) ...[
                const SizedBox(height: AppDimens.dense),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _membersError!,
                    key: TemplateGroupEditorSheet.memberErrorKey,
                    style: context.textStyles.body.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (_actionError != null) ...[
                const SizedBox(height: AppDimens.dense),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _actionError!,
                    key: TemplateGroupEditorSheet.actionErrorKey,
                    style: context.textStyles.body.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppDimens.base),
              FilledButton.icon(
                key: TemplateGroupEditorSheet.saveButtonKey,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.save,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  minimumSize: const Size.fromHeight(AppDimens.rowHeight),
                ),
                onPressed: _saving ? null : () => unawaited(_submit()),
                icon: const Icon(Icons.save_outlined),
                label: Text(l10n.workoutTemplateSaveGroup),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _availableMemberTile(
    BuildContext context,
    TemplateExerciseDetail exercise,
  ) {
    final otherGroup = _otherGroupFor(exercise.id);
    return CheckboxListTile(
      key: TemplateGroupEditorSheet.memberCheckboxKey(exercise.id),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: false,
      title: Text(exercise.name),
      subtitle: otherGroup == null
          ? null
          : Text(
              context.l10n.workoutTemplateGroupInOtherGroup(otherGroup.name)),
      onChanged: otherGroup != null || _saving
          ? null
          : (selected) {
              setState(() {
                if (selected ?? false) {
                  _selectedIds.add(exercise.id);
                  if (!_memberOrder.contains(exercise.id)) {
                    _memberOrder.add(exercise.id);
                  }
                }
                _clearMemberErrors();
              });
            },
    );
  }

  void _reorderMembers(int oldIndex, int newIndex) {
    final adjustedNewIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _moveMember(oldIndex, adjustedNewIndex);
  }

  void _moveMember(int oldIndex, int newIndex) {
    if (_saving ||
        oldIndex == newIndex ||
        newIndex < 0 ||
        newIndex >= _memberOrder.length) {
      return;
    }
    setState(() {
      final moved = _memberOrder.removeAt(oldIndex);
      _memberOrder.insert(newIndex, moved);
      _clearMemberErrors();
    });
  }

  void _removeMember(String templateExerciseId) {
    if (_saving) {
      return;
    }
    setState(() {
      _selectedIds.remove(templateExerciseId);
      _memberOrder.remove(templateExerciseId);
      _clearMemberErrors();
    });
  }

  void _clearMemberErrors() {
    _membersError = null;
    _actionError = null;
  }

  TemplateGroupDetail? _otherGroupFor(String templateExerciseId) {
    for (final candidate in widget.groups) {
      if (candidate.id == widget.group?.id) {
        continue;
      }
      if (candidate.members.any(
        (member) => member.templateExerciseId == templateExerciseId,
      )) {
        return candidate;
      }
    }
    return null;
  }

  void _refreshColorPreview() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    final colorHex = _colorController.text.trim().toUpperCase();
    final rounds = num.tryParse(_roundsController.text.trim()) ?? double.nan;
    final orderedIds =
        _memberOrder.where(_selectedIds.contains).toList(growable: false);
    final validation = validateTemplateGroup(
      name: name,
      colorHex: colorHex,
      rounds: rounds,
      memberIds: orderedIds,
    );
    bool hasErrorFor(String field) =>
        validation.errors.any((issue) => issue.field == field);

    setState(() {
      _nameError =
          hasErrorFor('name') ? l10n.workoutTemplateGroupNameRequired : null;
      _colorError = hasErrorFor('colorHex')
          ? l10n.workoutTemplateGroupColorInvalid
          : null;
      _roundsError =
          hasErrorFor('rounds') ? l10n.workoutTemplateGroupRoundsInvalid : null;
      _membersError = hasErrorFor('memberIds')
          ? l10n.workoutTemplateGroupMembersInvalid
          : null;
      _actionError = null;
    });
    if (_nameError != null ||
        _colorError != null ||
        _roundsError != null ||
        _membersError != null) {
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onSave(
        TemplateGroupInput(
          name: name,
          colorHex: colorHex,
          rounds: rounds.toInt(),
          orderedTemplateExerciseIds: orderedIds,
        ),
      );
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _actionError = context.l10n.workoutTemplateGroupActionFailed;
        });
      }
    }
  }
}

enum _GroupMemberMenuAction { moveEarlier, moveLater, remove }

class _SelectedGroupMemberTile extends StatelessWidget {
  const _SelectedGroupMemberTile({
    required this.exercise,
    required this.reorderIndex,
    required this.canMoveEarlier,
    required this.canMoveLater,
    required this.enabled,
    required this.onMoveEarlier,
    required this.onMoveLater,
    required this.onRemove,
    super.key,
  });

  final TemplateExerciseDetail exercise;
  final int reorderIndex;
  final bool canMoveEarlier;
  final bool canMoveLater;
  final bool enabled;
  final VoidCallback onMoveEarlier;
  final VoidCallback onMoveLater;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: AppDimens.rowHeight,
      leading: Semantics(
        button: true,
        label: l10n.workoutTemplateReorderGroupMember(exercise.name),
        child: ReorderableDragStartListener(
          key: TemplateGroupEditorSheet.reorderMemberHandleKey(exercise.id),
          index: reorderIndex,
          enabled: enabled,
          child: const SizedBox.square(
            dimension: AppDimens.touchTarget,
            child: Icon(Icons.drag_handle),
          ),
        ),
      ),
      title: Text(exercise.name),
      trailing: PopupMenuButton<_GroupMemberMenuAction>(
        key: TemplateGroupEditorSheet.memberMenuButtonKey(exercise.id),
        enabled: enabled,
        tooltip: l10n.workoutTemplateGroupMemberActions(exercise.name),
        onSelected: (action) {
          switch (action) {
            case _GroupMemberMenuAction.moveEarlier:
              onMoveEarlier();
            case _GroupMemberMenuAction.moveLater:
              onMoveLater();
            case _GroupMemberMenuAction.remove:
              onRemove();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<_GroupMemberMenuAction>(
            key: TemplateGroupEditorSheet.moveMemberEarlierKey(exercise.id),
            value: _GroupMemberMenuAction.moveEarlier,
            enabled: canMoveEarlier,
            child: Text(l10n.workoutTemplateMoveGroupEarlier),
          ),
          PopupMenuItem<_GroupMemberMenuAction>(
            key: TemplateGroupEditorSheet.moveMemberLaterKey(exercise.id),
            value: _GroupMemberMenuAction.moveLater,
            enabled: canMoveLater,
            child: Text(l10n.workoutTemplateMoveGroupLater),
          ),
          PopupMenuItem<_GroupMemberMenuAction>(
            key: TemplateGroupEditorSheet.removeMemberKey(exercise.id),
            value: _GroupMemberMenuAction.remove,
            child: Text(l10n.workoutTemplateRemoveGroupMember),
          ),
        ],
      ),
    );
  }
}
