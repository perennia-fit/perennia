import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/training_dimensions.dart';
import '../../../theme/theme.dart';

class ExerciseEditorScreen extends ConsumerStatefulWidget {
  const ExerciseEditorScreen({
    super.key,
    this.exerciseId,
    this.platformExerciseId,
    this.initialName,
    this.returnCreatedExercise = false,
  })  : assert(
          exerciseId == null || platformExerciseId == null,
          'Pass either exerciseId or platformExerciseId, not both.',
        ),
        assert(
          initialName == null ||
              (exerciseId == null && platformExerciseId == null),
          'initialName is only supported when creating an exercise.',
        ),
        assert(
          !returnCreatedExercise ||
              (exerciseId == null && platformExerciseId == null),
          'returnCreatedExercise is only supported when creating an exercise.',
        );

  static const routeName = '/exercises/edit';
  static const nameFieldKey = Key('exercise-editor-name');
  static const notesFieldKey = Key('exercise-editor-notes');
  static const saveButtonKey = Key('exercise-editor-save');
  static const saveNewButtonKey = Key('exercise-editor-save-new');
  static const archiveButtonKey = Key('exercise-editor-archive');
  static const loadModeFieldKey = Key('exercise-editor-load-mode');
  static const recordProfileFieldKey = Key('exercise-editor-record-profile');
  static const unilateralToggleKey = Key('exercise-editor-unilateral');
  static const rpeToggleKey = Key('exercise-editor-rpe');

  static Key equipmentChipKey(String id) {
    return Key('exercise-editor-equipment-$id');
  }

  final String? exerciseId;
  final String? platformExerciseId;
  final String? initialName;
  final bool returnCreatedExercise;

  @override
  ConsumerState<ExerciseEditorScreen> createState() =>
      _ExerciseEditorScreenState();
}

class _ExerciseEditorScreenState extends ConsumerState<ExerciseEditorScreen> {
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();

  List<ExerciseCategoryRecord> _categories = const <ExerciseCategoryRecord>[];
  List<DimensionId> _dimensions = <DimensionId>[
    DimensionId.load,
    DimensionId.reps,
  ];
  TrainingUnit _defaultLoadUnit = TrainingUnit.kilogram;
  ExerciseLoadMode _loadMode = ExerciseLoadMode.added;
  RecordProfile _recordProfile = RecordProfile.repMax;
  bool _isUnilateral = false;
  bool _usesRpe = false;
  String? _categoryId;
  List<ExerciseEquipment> _equipment = <ExerciseEquipment>[];
  ExerciseRecord? _exercise;
  String? _errorText;
  bool _isLoading = true;
  bool _didLoad = false;

  bool get _isEditing =>
      widget.exerciseId != null || widget.platformExerciseId != null;
  bool get _isCustomizingPlatform => widget.platformExerciseId != null;
  bool get _hasLoadDimension => _dimensions.contains(DimensionId.load);
  ExerciseType get _currentType => ExerciseType(_dimensions);
  ExerciseLoadMode get _effectiveLoadMode {
    return _hasLoadDimension ? _loadMode : ExerciseLoadMode.added;
  }

  RecordProfile get _defaultRecordProfile {
    return defaultRecordProfileFor(
      type: _currentType,
      loadMode: _effectiveLoadMode,
    );
  }

  List<ExerciseEquipment> get _equipmentChoices {
    return <ExerciseEquipment>[
      ...ExerciseEquipment.known,
      for (final equipment in _equipment)
        if (!ExerciseEquipment.known.contains(equipment)) equipment,
    ];
  }

  bool get _canArchive {
    final exercise = _exercise;
    return _isEditing &&
        exercise != null &&
        !exercise.isReadOnly &&
        exercise.deletedAt == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) {
      return;
    }
    _didLoad = true;
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repositories = ref.read(trainingRepositoriesProvider);
    await repositories.catalog.ensurePlatformLibrarySeeded();
    final categories = await repositories.catalog.listCategories();
    final exerciseId = widget.exerciseId ?? widget.platformExerciseId;
    ExerciseRecord? exercise;
    if (exerciseId != null) {
      exercise = await repositories.exercises.getById(exerciseId);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _categories = categories;
      _exercise = exercise;
      if (exercise != null) {
        _nameController.text = exercise.name;
        _notesController.text = exercise.notes ?? '';
        _dimensions = exercise.type.dimensions.toList(growable: true);
        _defaultLoadUnit = exercise.defaultLoadUnit;
        _loadMode = exercise.loadMode;
        _recordProfile = exercise.recordProfile;
        _isUnilateral = exercise.isUnilateral;
        _usesRpe = exercise.usesRpe;
        _categoryId = exercise.categoryId;
        _equipment = exercise.equipment.toList(growable: true);
      } else {
        _nameController.text = widget.initialName?.trim() ?? '';
        _categoryId = categories.isEmpty ? null : categories.first.id;
      }
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isCustomizingPlatform
              ? 'Customize exercise'
              : _isEditing
                  ? 'Edit exercise'
                  : 'New exercise',
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const SizedBox.expand()
            : ListView(
                padding: const EdgeInsets.all(AppDimens.base),
                children: [
                  TextField(
                    key: ExerciseEditorScreen.nameFieldKey,
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      errorText: _errorText,
                    ),
                  ),
                  const SizedBox(height: AppDimens.base),
                  TextField(
                    key: ExerciseEditorScreen.notesFieldKey,
                    controller: _notesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  const SizedBox(height: AppDimens.base),
                  DropdownButtonFormField<String?>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Uncategorized'),
                      ),
                      for (final category in _categories)
                        DropdownMenuItem<String?>(
                          value: category.id,
                          child: Text(category.name),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _categoryId = value);
                    },
                  ),
                  const SizedBox(height: AppDimens.base),
                  Text('Equipment', style: context.textStyles.h2),
                  const SizedBox(height: AppDimens.dense),
                  Wrap(
                    spacing: AppDimens.dense,
                    runSpacing: AppDimens.dense,
                    children: [
                      for (final equipment in _equipmentChoices)
                        FilterChip(
                          key: ExerciseEditorScreen.equipmentChipKey(
                            equipment.id,
                          ),
                          label: Text(equipment.label),
                          selected: _equipment.contains(equipment),
                          onSelected: (selected) {
                            setState(() {
                              _equipment = selected
                                  ? _withEquipment(_equipment, equipment)
                                  : _withoutEquipment(_equipment, equipment);
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.base),
                  DropdownButtonFormField<TrainingUnit>(
                    initialValue: _defaultLoadUnit,
                    decoration: const InputDecoration(labelText: 'Weight unit'),
                    items: const [
                      DropdownMenuItem<TrainingUnit>(
                        value: TrainingUnit.kilogram,
                        child: Text('kg'),
                      ),
                      DropdownMenuItem<TrainingUnit>(
                        value: TrainingUnit.pound,
                        child: Text('lb'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _defaultLoadUnit = value);
                    },
                  ),
                  if (_hasLoadDimension) ...[
                    const SizedBox(height: AppDimens.base),
                    DropdownButtonFormField<ExerciseLoadMode>(
                      key: ExerciseEditorScreen.loadModeFieldKey,
                      initialValue: _effectiveLoadMode,
                      decoration: const InputDecoration(labelText: 'Load mode'),
                      items: const [
                        DropdownMenuItem<ExerciseLoadMode>(
                          value: ExerciseLoadMode.added,
                          child: Text('Added'),
                        ),
                        DropdownMenuItem<ExerciseLoadMode>(
                          value: ExerciseLoadMode.assisted,
                          child: Text('Assisted'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        _setLoadMode(value);
                      },
                    ),
                  ],
                  const SizedBox(height: AppDimens.base),
                  DropdownButtonFormField<RecordProfile>(
                    key: ExerciseEditorScreen.recordProfileFieldKey,
                    initialValue: _recordProfile,
                    decoration:
                        const InputDecoration(labelText: 'Record Profile'),
                    items: [
                      for (final profile in RecordProfile.values)
                        DropdownMenuItem<RecordProfile>(
                          value: profile,
                          child: Text(_recordProfileLabel(profile)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _recordProfile = value);
                    },
                  ),
                  const SizedBox(height: AppDimens.base),
                  SwitchListTile(
                    key: ExerciseEditorScreen.unilateralToggleKey,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Unilateral'),
                    value: _isUnilateral,
                    onChanged: (value) {
                      setState(() => _isUnilateral = value);
                    },
                  ),
                  SwitchListTile(
                    key: ExerciseEditorScreen.rpeToggleKey,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Track RPE'),
                    value: _usesRpe,
                    onChanged: (value) {
                      setState(() => _usesRpe = value);
                    },
                  ),
                  const SizedBox(height: AppDimens.base),
                  Text('Type', style: context.textStyles.h2),
                  const SizedBox(height: AppDimens.dense),
                  Wrap(
                    spacing: AppDimens.dense,
                    runSpacing: AppDimens.dense,
                    children: [
                      for (final preset in _presets)
                        ActionChip(
                          label: Text(preset.label),
                          onPressed: () {
                            _setDimensions(
                              preset.dimensions.toList(growable: true),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.dense),
                  Wrap(
                    spacing: AppDimens.dense,
                    runSpacing: AppDimens.dense,
                    children: [
                      for (final dimension in DimensionRegistry.ids)
                        FilterChip(
                          label: Text(_dimensionName(dimension)),
                          selected: _dimensions.contains(dimension),
                          onSelected: (selected) {
                            if (selected) {
                              _setDimensions([
                                ..._dimensions,
                                dimension,
                              ]);
                            } else {
                              _setDimensions(
                                _dimensions
                                    .where((item) => item != dimension)
                                    .toList(growable: true),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.base),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: ExerciseEditorScreen.saveButtonKey,
                          onPressed: () => _save(resetAfterSave: false),
                          icon: const Icon(Icons.save),
                          label: const Text('Save'),
                        ),
                      ),
                      if (!_isEditing) ...[
                        const SizedBox(width: AppDimens.dense),
                        Expanded(
                          child: OutlinedButton.icon(
                            key: ExerciseEditorScreen.saveNewButtonKey,
                            onPressed: () => _save(resetAfterSave: true),
                            icon: const Icon(Icons.add),
                            label: const Text('Save & New'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_canArchive) ...[
                    const SizedBox(height: AppDimens.dense),
                    OutlinedButton.icon(
                      key: ExerciseEditorScreen.archiveButtonKey,
                      onPressed: _archive,
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Archive'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _save({required bool resetAfterSave}) async {
    final repositories = ref.read(trainingRepositoriesProvider);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Name is required.');
      return;
    }

    final draft = ExerciseDraft(
      name: name,
      type: ExerciseType(_dimensions),
      defaultLoadUnit: _defaultLoadUnit,
      loadMode: _effectiveLoadMode,
      recordProfile: _recordProfile,
      isUnilateral: _isUnilateral,
      usesRpe: _usesRpe,
      categoryId: _categoryId,
      equipment: _equipment,
      notes: _emptyToNull(_notesController.text),
    );

    ExerciseRecord? createdExercise;
    try {
      final exerciseId = widget.exerciseId;
      final platformExerciseId = widget.platformExerciseId;
      if (exerciseId == null && platformExerciseId == null) {
        createdExercise = await repositories.exercises.createRecord(draft);
      } else if (platformExerciseId != null) {
        if (_exercise != null && !_differsFromExercise(_exercise!, draft)) {
          _popOrReload();
          return;
        }
        await repositories.exercises.customizePlatformExercise(
          platformExerciseId,
          draft: draft,
        );
      } else {
        if (_exercise != null && !_differsFromExercise(_exercise!, draft)) {
          _popOrReload();
          return;
        }
        await repositories.exercises.update(exerciseId!, draft);
      }
    } on DuplicateExerciseNameException {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = 'A user exercise with this name already exists.';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    if (resetAfterSave) {
      setState(() {
        _nameController.clear();
        _notesController.clear();
        _setDimensionsForReset();
        _defaultLoadUnit = TrainingUnit.kilogram;
        _isUnilateral = false;
        _usesRpe = false;
        _categoryId = _categories.isEmpty ? null : _categories.first.id;
        _equipment = <ExerciseEquipment>[];
        _errorText = null;
      });
      return;
    }

    _popOrReload(widget.returnCreatedExercise ? createdExercise : null);
  }

  Future<void> _archive() async {
    final exerciseId = widget.exerciseId;
    if (exerciseId == null) {
      return;
    }

    await ref.read(trainingRepositoriesProvider).exercises.softDelete(
          exerciseId,
        );

    if (!mounted) {
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    await _load();
  }

  void _setLoadMode(ExerciseLoadMode loadMode) {
    final previousDefault = _defaultRecordProfile;
    final wasUsingDefault = _recordProfile == previousDefault;
    final nextDefault = defaultRecordProfileFor(
      type: _currentType,
      loadMode: loadMode,
    );

    setState(() {
      _loadMode = loadMode;
      if (wasUsingDefault) {
        _recordProfile = nextDefault;
      }
    });
  }

  void _setDimensions(List<DimensionId> dimensions) {
    final previousDefault = _defaultRecordProfile;
    final wasUsingDefault = _recordProfile == previousDefault;
    final hasLoadDimension = dimensions.contains(DimensionId.load);
    final nextLoadMode = hasLoadDimension ? _loadMode : ExerciseLoadMode.added;
    final nextDefault = defaultRecordProfileFor(
      type: ExerciseType(dimensions),
      loadMode: nextLoadMode,
    );

    setState(() {
      _dimensions = dimensions;
      _loadMode = nextLoadMode;
      if (wasUsingDefault) {
        _recordProfile = nextDefault;
      }
    });
  }

  void _setDimensionsForReset() {
    _dimensions = <DimensionId>[DimensionId.load, DimensionId.reps];
    _loadMode = ExerciseLoadMode.added;
    _recordProfile = defaultRecordProfileFor(
      type: ExerciseType(_dimensions),
      loadMode: _loadMode,
    );
  }

  bool _differsFromExercise(ExerciseRecord exercise, ExerciseDraft draft) {
    return exercise.name != draft.name ||
        exercise.type != draft.type ||
        exercise.defaultLoadUnit != draft.defaultLoadUnit ||
        exercise.loadMode != draft.effectiveLoadMode ||
        exercise.recordProfile != draft.effectiveRecordProfile ||
        exercise.isUnilateral != draft.isUnilateral ||
        exercise.usesRpe != draft.usesRpe ||
        exercise.categoryId != draft.categoryId ||
        !_equipmentEquals(exercise.equipment, draft.equipment) ||
        exercise.notes != draft.notes;
  }

  void _popOrReload([ExerciseRecord? result]) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
      return;
    }

    unawaited(_load());
  }
}

List<ExerciseEquipment> _withEquipment(
  List<ExerciseEquipment> equipment,
  ExerciseEquipment item,
) {
  if (equipment.contains(item)) {
    return equipment;
  }
  return <ExerciseEquipment>[...equipment, item];
}

List<ExerciseEquipment> _withoutEquipment(
  List<ExerciseEquipment> equipment,
  ExerciseEquipment item,
) {
  return equipment
      .where((equipmentItem) => equipmentItem != item)
      .toList(growable: false);
}

bool _equipmentEquals(
  List<ExerciseEquipment> left,
  List<ExerciseEquipment> right,
) {
  final leftIds = left.map((equipment) => equipment.id).toSet();
  final rightIds = right.map((equipment) => equipment.id).toSet();
  if (leftIds.length != rightIds.length) {
    return false;
  }
  return leftIds.every(rightIds.contains);
}

class _DimensionPreset {
  const _DimensionPreset({
    required this.label,
    required this.dimensions,
  });

  final String label;
  final List<DimensionId> dimensions;
}

const _presets = <_DimensionPreset>[
  _DimensionPreset(
    label: 'Strength',
    dimensions: <DimensionId>[DimensionId.load, DimensionId.reps],
  ),
  _DimensionPreset(
    label: 'Cardio',
    dimensions: <DimensionId>[DimensionId.distance, DimensionId.duration],
  ),
  _DimensionPreset(
    label: 'Timed hold',
    dimensions: <DimensionId>[DimensionId.duration],
  ),
  _DimensionPreset(
    label: 'Just track completion',
    dimensions: <DimensionId>[],
  ),
];

String _dimensionName(DimensionId dimension) {
  return switch (dimension) {
    DimensionId.load => 'Load',
    DimensionId.reps => 'Reps',
    DimensionId.duration => 'Duration',
    DimensionId.distance => 'Distance',
  };
}

String _recordProfileLabel(RecordProfile profile) {
  return switch (profile) {
    RecordProfile.repMax => 'Rep max',
    RecordProfile.maxLoad => 'Max load',
    RecordProfile.maxReps => 'Max reps',
    RecordProfile.maxDuration => 'Max duration',
    RecordProfile.minDuration => 'Min duration',
    RecordProfile.maxDistance => 'Max distance',
    RecordProfile.fastestPace => 'Fastest pace',
    RecordProfile.minAssistancePerRepCount => 'Min assistance per rep count',
    RecordProfile.completionStreak => 'Completion streak (no trophy)',
  };
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
