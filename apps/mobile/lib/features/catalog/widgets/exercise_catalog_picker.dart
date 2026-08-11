import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/training_dimensions.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/exercise_catalog_controller.dart';
import '../search/exercise_search.dart';
import 'exercise_editor_screen.dart';

class ExerciseCatalogPicker extends ConsumerWidget {
  const ExerciseCatalogPicker({
    super.key,
    this.onExerciseSelected,
  });

  static const typeFilterKey = Key('exercise-catalog-filter-type');
  static const bodyPartFilterKey = Key('exercise-catalog-filter-body-part');
  static const equipmentFilterKey = Key('exercise-catalog-filter-equipment');
  static const searchFieldKey = Key('exercise-catalog-search');
  static const createExerciseButtonKey =
      Key('exercise-catalog-create-exercise');
  static const pageSummaryKey = Key('exercise-catalog-page-summary');
  static const pageSize = 30;
  static const searchDebounceDuration = Duration(milliseconds: 300);

  final ValueChanged<ExerciseRecord>? onExerciseSelected;

  static Key typeFilterOptionKey(String id) {
    return Key('exercise-catalog-filter-type-option-$id');
  }

  static Key bodyPartFilterOptionKey(String id) {
    return Key('exercise-catalog-filter-body-part-option-$id');
  }

  static Key equipmentFilterOptionKey(String id) {
    return Key('exercise-catalog-filter-equipment-option-$id');
  }

  static Key selectButtonKey(String id) {
    return Key('exercise-catalog-select-$id');
  }

  static Key favoriteButtonKey(String id) {
    return Key('exercise-catalog-favorite-$id');
  }

  static Key customizeButtonKey(String id) {
    return Key('exercise-catalog-customize-$id');
  }

  static Key restorePlatformButtonKey(String id) {
    return Key('exercise-catalog-restore-platform-$id');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exerciseCatalogControllerProvider);

    return state.when(
      data: (catalog) => _CatalogSections(
        sections: catalog.sections,
        onExerciseSelected: onExerciseSelected,
      ),
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => Text(
        'Exercise catalog unavailable',
        style: context.textStyles.body.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _CatalogSections extends ConsumerStatefulWidget {
  const _CatalogSections({
    required this.sections,
    required this.onExerciseSelected,
  });

  final List<ExerciseCatalogSectionRecord> sections;
  final ValueChanged<ExerciseRecord>? onExerciseSelected;

  @override
  ConsumerState<_CatalogSections> createState() => _CatalogSectionsState();
}

class _CatalogSectionsState extends ConsumerState<_CatalogSections> {
  static const _loadMoreExtentThreshold = 240.0;

  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  late _CatalogFilterOptions _filterOptions;
  Timer? _searchDebounceTimer;
  String _selectedTypeId = _allFilterId;
  String _selectedBodyPartId = _allFilterId;
  String _selectedEquipmentId = _allFilterId;
  String _query = '';
  int _visibleExerciseLimit = ExerciseCatalogPicker.pageSize;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_loadMoreIfNeeded);
    _searchController = TextEditingController();
    _filterOptions = _CatalogFilterOptions.fromSections(widget.sections);
  }

  @override
  void didUpdateWidget(covariant _CatalogSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sections, widget.sections)) {
      _filterOptions = _CatalogFilterOptions.fromSections(widget.sections);
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_loadMoreIfNeeded);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filterOptions = _filterOptions;
    final selectedTypeId = _effectiveSelectedId(
      _selectedTypeId,
      filterOptions.typeOptions,
    );
    final selectedBodyPartId = _effectiveSelectedId(
      _selectedBodyPartId,
      filterOptions.bodyPartOptions,
    );
    final selectedEquipmentId = _effectiveSelectedId(
      _selectedEquipmentId,
      filterOptions.equipmentOptions,
    );
    final visibleSections = _visibleSections(
      widget.sections,
      selectedTypeId: selectedTypeId,
      selectedBodyPartId: selectedBodyPartId,
      selectedEquipmentId: selectedEquipmentId,
      query: _query,
    );
    final visibleSlice = _CatalogSlice.fromSections(
      visibleSections,
      visibleLimit: _visibleExerciseLimit,
    );
    final hasCatalogExercises = widget.sections
        .where((section) => !section.isVirtual)
        .any((section) => section.exercises.isNotEmpty);

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      children: [
        TextField(
          key: ExerciseCatalogPicker.searchFieldKey,
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search exercises',
            prefixIcon: Icon(Icons.search),
          ),
          textInputAction: TextInputAction.search,
          onChanged: _scheduleSearchQuery,
          onSubmitted: _applySearchQuery,
        ),
        const SizedBox(height: AppDimens.dense),
        SizedBox(
          width: double.infinity,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, child) {
              final createName = value.text.trim();
              final createLabel = createName.isEmpty
                  ? context.l10n.exerciseCatalogCreateExercise
                  : context.l10n.exerciseCatalogCreateNamedExercise(
                      createName,
                    );
              return FilledButton.tonalIcon(
                key: ExerciseCatalogPicker.createExerciseButtonKey,
                onPressed: () => _createExercise(createName),
                icon: const Icon(Icons.add),
                label: Text(
                  createLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppDimens.base),
        if (hasCatalogExercises) ...[
          _CatalogFilterControls(
            typeOptions: filterOptions.typeOptions,
            bodyPartOptions: filterOptions.bodyPartOptions,
            equipmentOptions: filterOptions.equipmentOptions,
            selectedTypeId: selectedTypeId,
            selectedBodyPartId: selectedBodyPartId,
            selectedEquipmentId: selectedEquipmentId,
            onTypeChanged: (value) {
              _resetCatalogWindow(() {
                _selectedTypeId = value;
              });
            },
            onBodyPartChanged: (value) {
              _resetCatalogWindow(() {
                _selectedBodyPartId = value;
              });
            },
            onEquipmentChanged: (value) {
              _resetCatalogWindow(() {
                _selectedEquipmentId = value;
              });
            },
          ),
          const SizedBox(height: AppDimens.base),
        ],
        if (visibleSections.isEmpty)
          _EmptyCatalogSearch(isCatalogEmpty: !hasCatalogExercises)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PageSummary(slice: visibleSlice),
              const SizedBox(height: AppDimens.dense),
              for (var index = 0;
                  index < visibleSlice.sections.length;
                  index += 1) ...[
                if (index > 0) const SizedBox(height: AppDimens.base),
                _CategorySection(
                  section: visibleSlice.sections[index],
                  onExerciseSelected: widget.onExerciseSelected,
                ),
              ],
              const SizedBox(height: AppDimens.base),
            ],
          ),
      ],
    );
  }

  Future<void> _createExercise(String name) async {
    final createdExercise = await Navigator.of(context).push<ExerciseRecord>(
      MaterialPageRoute<ExerciseRecord>(
        builder: (_) => ExerciseEditorScreen(
          initialName: name,
          returnCreatedExercise: true,
        ),
      ),
    );
    if (!mounted || createdExercise == null) {
      return;
    }

    widget.onExerciseSelected?.call(createdExercise);
  }

  void _resetCatalogWindow(VoidCallback mutate) {
    setState(() {
      mutate();
      _visibleExerciseLimit = ExerciseCatalogPicker.pageSize;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _scheduleSearchQuery(String value) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer =
        Timer(ExerciseCatalogPicker.searchDebounceDuration, () {
      _applySearchQuery(value);
    });
  }

  void _applySearchQuery(String value) {
    _searchDebounceTimer?.cancel();
    if (!mounted || value == _query) {
      return;
    }
    _resetCatalogWindow(() {
      _query = value;
    });
  }

  void _loadMoreIfNeeded() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }

    if (_scrollController.position.extentAfter > _loadMoreExtentThreshold) {
      return;
    }

    final filterOptions = _filterOptions;
    final selectedTypeId = _effectiveSelectedId(
      _selectedTypeId,
      filterOptions.typeOptions,
    );
    final selectedBodyPartId = _effectiveSelectedId(
      _selectedBodyPartId,
      filterOptions.bodyPartOptions,
    );
    final selectedEquipmentId = _effectiveSelectedId(
      _selectedEquipmentId,
      filterOptions.equipmentOptions,
    );
    final visibleSections = _visibleSections(
      widget.sections,
      selectedTypeId: selectedTypeId,
      selectedBodyPartId: selectedBodyPartId,
      selectedEquipmentId: selectedEquipmentId,
      query: _query,
    );
    final totalCount = visibleSections.fold<int>(
      0,
      (total, section) => total + section.exercises.length,
    );

    if (_visibleExerciseLimit >= totalCount) {
      return;
    }

    setState(() {
      _visibleExerciseLimit = math.min(
        _visibleExerciseLimit + ExerciseCatalogPicker.pageSize,
        totalCount,
      );
    });
  }

  List<ExerciseCatalogSectionRecord> _visibleSections(
    List<ExerciseCatalogSectionRecord> sections, {
    required String selectedTypeId,
    required String selectedBodyPartId,
    required String selectedEquipmentId,
    required String query,
  }) {
    final candidateSections = sections.where((section) => !section.isVirtual);
    return candidateSections
        .map(
          (section) => ExerciseCatalogSectionRecord(
            category: section.category,
            exercises: section.exercises
                .where(
                  (exercise) =>
                      _exerciseMatchesFilters(
                        exercise,
                        section: section,
                        selectedTypeId: selectedTypeId,
                        selectedBodyPartId: selectedBodyPartId,
                        selectedEquipmentId: selectedEquipmentId,
                      ) &&
                      exerciseNameMatchesQuery(exercise.name, query),
                )
                .toList(growable: false),
            virtualId: section.virtualId,
            virtualTitle: section.virtualTitle,
          ),
        )
        .where((section) => section.exercises.isNotEmpty)
        .toList(growable: false);
  }
}

class _EmptyCatalogSearch extends StatelessWidget {
  const _EmptyCatalogSearch({required this.isCatalogEmpty});

  final bool isCatalogEmpty;

  @override
  Widget build(BuildContext context) {
    return Text(
      isCatalogEmpty
          ? context.l10n.exerciseCatalogEmptyLibrary
          : context.l10n.exerciseCatalogNoMatches,
      style: context.textStyles.body.copyWith(
        color: context.colors.textSecondary,
      ),
    );
  }
}

class _CatalogFilterControls extends StatelessWidget {
  const _CatalogFilterControls({
    required this.typeOptions,
    required this.bodyPartOptions,
    required this.equipmentOptions,
    required this.selectedTypeId,
    required this.selectedBodyPartId,
    required this.selectedEquipmentId,
    required this.onTypeChanged,
    required this.onBodyPartChanged,
    required this.onEquipmentChanged,
  });

  final List<_FilterOption> typeOptions;
  final List<_FilterOption> bodyPartOptions;
  final List<_FilterOption> equipmentOptions;
  final String selectedTypeId;
  final String selectedBodyPartId;
  final String selectedEquipmentId;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onBodyPartChanged;
  final ValueChanged<String> onEquipmentChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final itemWidth =
            maxWidth >= 560 ? (maxWidth - (AppDimens.dense * 2)) / 3 : maxWidth;
        return Wrap(
          spacing: AppDimens.dense,
          runSpacing: AppDimens.dense,
          children: [
            SizedBox(
              width: itemWidth,
              child: _FilterDropdown(
                fieldKey: ExerciseCatalogPicker.typeFilterKey,
                label: 'Type',
                value: selectedTypeId,
                options: typeOptions,
                optionKeyBuilder: ExerciseCatalogPicker.typeFilterOptionKey,
                onChanged: onTypeChanged,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _FilterDropdown(
                fieldKey: ExerciseCatalogPicker.bodyPartFilterKey,
                label: 'Body part',
                value: selectedBodyPartId,
                options: bodyPartOptions,
                optionKeyBuilder: ExerciseCatalogPicker.bodyPartFilterOptionKey,
                onChanged: onBodyPartChanged,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _FilterDropdown(
                fieldKey: ExerciseCatalogPicker.equipmentFilterKey,
                label: 'Equipment',
                value: selectedEquipmentId,
                options: equipmentOptions,
                optionKeyBuilder:
                    ExerciseCatalogPicker.equipmentFilterOptionKey,
                onChanged: onEquipmentChanged,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.options,
    required this.optionKeyBuilder,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String value;
  final List<_FilterOption> options;
  final Key Function(String id) optionKeyBuilder;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: fieldKey,
          value: value,
          isExpanded: true,
          selectedItemBuilder: (context) => [
            for (final option in options)
              Text(
                option.label,
                overflow: TextOverflow.ellipsis,
              ),
          ],
          items: [
            for (final option in options)
              DropdownMenuItem<String>(
                value: option.id,
                child: Text(
                  option.label,
                  key: optionKeyBuilder(option.id),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            onChanged(value);
          },
        ),
      ),
    );
  }
}

class _CatalogFilterOptions {
  const _CatalogFilterOptions({
    required this.typeOptions,
    required this.bodyPartOptions,
    required this.equipmentOptions,
  });

  factory _CatalogFilterOptions.fromSections(
    List<ExerciseCatalogSectionRecord> sections,
  ) {
    final bodyPartOptions = <_FilterOption>[
      const _FilterOption(id: _allFilterId, label: 'All body parts'),
      for (final section in sections)
        if (_isBodyPartSection(section))
          _FilterOption(id: section.id, label: section.title),
    ];

    final equipmentById = <String, ExerciseEquipment>{};
    for (final section in sections.where((section) => !section.isVirtual)) {
      for (final exercise in section.exercises) {
        for (final equipment in exercise.equipment) {
          equipmentById[equipment.id] = equipment;
        }
      }
    }

    final unknownEquipment = equipmentById.values
        .where((equipment) => !ExerciseEquipment.known.contains(equipment))
        .toList(growable: false)
      ..sort((left, right) => left.label.compareTo(right.label));
    final equipmentOptions = <_FilterOption>[
      const _FilterOption(id: _allFilterId, label: 'All equipment'),
      for (final equipment in ExerciseEquipment.known)
        if (equipmentById.containsKey(equipment.id))
          _FilterOption(id: equipment.id, label: equipment.label),
      for (final equipment in unknownEquipment)
        _FilterOption(id: equipment.id, label: equipment.label),
    ];

    return _CatalogFilterOptions(
      typeOptions: _typeOptions,
      bodyPartOptions: bodyPartOptions,
      equipmentOptions: equipmentOptions,
    );
  }

  final List<_FilterOption> typeOptions;
  final List<_FilterOption> bodyPartOptions;
  final List<_FilterOption> equipmentOptions;
}

class _FilterOption {
  const _FilterOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class _CatalogSlice {
  const _CatalogSlice({
    required this.sections,
    required this.totalCount,
    required this.endIndex,
  });

  factory _CatalogSlice.fromSections(
    List<ExerciseCatalogSectionRecord> sections, {
    required int visibleLimit,
  }) {
    final totalCount = sections.fold<int>(
      0,
      (total, section) => total + section.exercises.length,
    );
    if (totalCount == 0) {
      return _CatalogSlice(
        sections: const <ExerciseCatalogSectionRecord>[],
        totalCount: 0,
        endIndex: 0,
      );
    }

    final endIndex = math.min(math.max(visibleLimit, 0), totalCount);
    final pageSections = <ExerciseCatalogSectionRecord>[];
    var remaining = endIndex;

    for (final section in sections) {
      if (remaining <= 0) {
        break;
      }

      final exerciseCount = math.min(remaining, section.exercises.length);
      if (exerciseCount > 0) {
        pageSections.add(
          ExerciseCatalogSectionRecord(
            category: section.category,
            exercises: section.exercises
                .sublist(
                  0,
                  exerciseCount,
                )
                .toList(growable: false),
            virtualId: section.virtualId,
            virtualTitle: section.virtualTitle,
          ),
        );
      }

      remaining -= exerciseCount;
    }

    return _CatalogSlice(
      sections: pageSections,
      totalCount: totalCount,
      endIndex: endIndex,
    );
  }

  final List<ExerciseCatalogSectionRecord> sections;
  final int totalCount;
  final int endIndex;

  int get visibleStart => totalCount == 0 ? 0 : 1;
}

class _PageSummary extends StatelessWidget {
  const _PageSummary({required this.slice});

  final _CatalogSlice slice;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Showing ${slice.visibleStart}-${slice.endIndex} of ${slice.totalCount}',
      key: ExerciseCatalogPicker.pageSummaryKey,
      style: context.textStyles.caption.copyWith(
        color: context.colors.textSecondary,
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.section,
    required this.onExerciseSelected,
  });

  final ExerciseCatalogSectionRecord section;
  final ValueChanged<ExerciseRecord>? onExerciseSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: _categoryColor(section.category?.colorHex),
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 10),
            ),
            const SizedBox(width: AppDimens.dense),
            Expanded(
              child: Text(
                section.title,
                style: context.textStyles.h2,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.dense),
        for (final exercise in section.exercises)
          _ExercisePickerRow(
            exercise: exercise,
            onExerciseSelected: onExerciseSelected,
          ),
      ],
    );
  }
}

class _ExercisePickerRow extends ConsumerWidget {
  const _ExercisePickerRow({
    required this.exercise,
    required this.onExerciseSelected,
  });

  final ExerciseRecord exercise;
  final ValueChanged<ExerciseRecord>? onExerciseSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSelected = onExerciseSelected;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.dense,
        vertical: AppDimens.dense,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppDimens.dense),
              child: Icon(
                Icons.fitness_center,
                size: 18,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(width: AppDimens.dense),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: context.textStyles.body,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _dimensionLabel(exercise.type),
                      style: context.textStyles.body.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                    if (exercise.equipment.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _equipmentLabel(exercise.equipment),
                        style: context.textStyles.caption.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                    if (exercise.shadowsPlatformExercise) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tune,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Customized - overrides a platform exercise',
                              style: context.textStyles.caption.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _PickerActionButton(
              buttonKey: ExerciseCatalogPicker.favoriteButtonKey(exercise.id),
              tooltip: exercise.isFavorite ? 'Remove favorite' : 'Add favorite',
              color: exercise.isFavorite
                  ? const Color(0xFFF59E0B)
                  : context.colors.textSecondary,
              icon: Icon(
                exercise.isFavorite ? Icons.star : Icons.star_border,
              ),
              onPressed: () {
                unawaited(
                  ref.read(trainingRepositoriesProvider).exercises.setFavorite(
                        exercise.id,
                        isFavorite: !exercise.isFavorite,
                      ),
                );
              },
            ),
            if (exercise.isReadOnly)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PickerActionButton(
                    buttonKey: ExerciseCatalogPicker.customizeButtonKey(
                      exercise.id,
                    ),
                    tooltip: 'Customize exercise',
                    icon: const Icon(Icons.edit_note),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExerciseEditorScreen(
                            platformExerciseId: exercise.id,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              )
            else ...[
              if (exercise.shadowsPlatformExercise)
                _PickerActionButton(
                  buttonKey: ExerciseCatalogPicker.restorePlatformButtonKey(
                    exercise.id,
                  ),
                  tooltip: 'Restore platform version',
                  icon: const Icon(Icons.restore),
                  onPressed: () {
                    unawaited(
                      ref
                          .read(trainingRepositoriesProvider)
                          .exercises
                          .restorePlatformVersion(exercise.id),
                    );
                  },
                ),
              _PickerActionButton(
                tooltip: 'Edit exercise',
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ExerciseEditorScreen(
                        exerciseId: exercise.id,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );

    if (onSelected == null) {
      return row;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ExerciseCatalogPicker.selectButtonKey(exercise.id),
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelected(exercise),
        child: row,
      ),
    );
  }
}

class _PickerActionButton extends StatelessWidget {
  const _PickerActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.buttonKey,
    this.color,
  });

  final Key? buttonKey;
  final String tooltip;
  final Widget icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        key: buttonKey,
        label: tooltip,
        button: true,
        enabled: true,
        onTap: onPressed,
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: AppDimens.touchTarget,
            child: IconButton(
              constraints: const BoxConstraints.tightFor(
                width: AppDimens.touchTarget,
                height: AppDimens.touchTarget,
              ),
              visualDensity: VisualDensity.standard,
              color: color,
              icon: icon,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}

Color _categoryColor(String? colorHex) {
  if (colorHex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(colorHex)) {
    return const Color(0xFF64748B);
  }

  return Color(int.parse('FF${colorHex.substring(1)}', radix: 16));
}

String _dimensionLabel(ExerciseType type) {
  if (type.isCompletionOnly) {
    return 'Done';
  }

  return type.dimensions.map(_dimensionName).join(' + ');
}

String _dimensionName(DimensionId dimension) {
  return switch (dimension) {
    DimensionId.load => 'Load',
    DimensionId.reps => 'Reps',
    DimensionId.duration => 'Duration',
    DimensionId.distance => 'Distance',
  };
}

String _equipmentLabel(List<ExerciseEquipment> equipment) {
  return equipment.map((item) => item.label).join(' + ');
}

const _allFilterId = 'all';
const _typeStrengthId = 'strength';
const _typeCardioId = 'cardio';
const _typeMobilityId = 'mobility';

const _typeOptions = <_FilterOption>[
  _FilterOption(id: _allFilterId, label: 'All types'),
  _FilterOption(id: _typeCardioId, label: 'Cardio'),
  _FilterOption(id: _typeStrengthId, label: 'Strength'),
  _FilterOption(id: _typeMobilityId, label: 'Mobility'),
];

const _modalityCategoryNames = <String>{
  'cardio',
  'running',
  'cycling',
  'swimming',
  'mobility',
  'strength',
};

const _cardioCategoryNames = <String>{
  'cardio',
  'running',
  'cycling',
  'swimming',
};

final _mobilityNamePattern = RegExp(
  r'\b(mobility|stretch|flow|yoga|warm[- ]?up|cool[- ]?down|foam roll)\b',
  caseSensitive: false,
);

String _effectiveSelectedId(
  String selectedId,
  List<_FilterOption> options,
) {
  return options.any((option) => option.id == selectedId)
      ? selectedId
      : _allFilterId;
}

bool _exerciseMatchesFilters(
  ExerciseRecord exercise, {
  required ExerciseCatalogSectionRecord section,
  required String selectedTypeId,
  required String selectedBodyPartId,
  required String selectedEquipmentId,
}) {
  return _exerciseMatchesType(exercise, section, selectedTypeId) &&
      _exerciseMatchesBodyPart(section, selectedBodyPartId) &&
      _exerciseMatchesEquipment(exercise, selectedEquipmentId);
}

bool _exerciseMatchesType(
  ExerciseRecord exercise,
  ExerciseCatalogSectionRecord section,
  String selectedTypeId,
) {
  return switch (selectedTypeId) {
    _allFilterId => true,
    _typeCardioId => _isCardioExercise(exercise, section),
    _typeMobilityId => _isMobilityExercise(exercise, section),
    _typeStrengthId => !_isCardioExercise(exercise, section) &&
        !_isMobilityExercise(exercise, section),
    _ => true,
  };
}

bool _exerciseMatchesBodyPart(
  ExerciseCatalogSectionRecord section,
  String selectedBodyPartId,
) {
  return selectedBodyPartId == _allFilterId || section.id == selectedBodyPartId;
}

bool _exerciseMatchesEquipment(
  ExerciseRecord exercise,
  String selectedEquipmentId,
) {
  return selectedEquipmentId == _allFilterId ||
      exercise.equipment
          .any((equipment) => equipment.id == selectedEquipmentId);
}

bool _isBodyPartSection(ExerciseCatalogSectionRecord section) {
  if (section.isVirtual || section.category == null) {
    return false;
  }

  return !_modalityCategoryNames.contains(
    _normalizedFilterName(section.category!.name),
  );
}

bool _isCardioExercise(
  ExerciseRecord exercise,
  ExerciseCatalogSectionRecord section,
) {
  final categoryName = section.category?.name;
  if (categoryName != null &&
      _cardioCategoryNames.contains(_normalizedFilterName(categoryName))) {
    return true;
  }

  return exercise.type.hasDimension(DimensionId.distance) &&
      exercise.type.hasDimension(DimensionId.duration) &&
      !exercise.type.hasDimension(DimensionId.load) &&
      !exercise.type.hasDimension(DimensionId.reps);
}

bool _isMobilityExercise(
  ExerciseRecord exercise,
  ExerciseCatalogSectionRecord section,
) {
  final categoryName = section.category?.name;
  return categoryName != null &&
          _normalizedFilterName(categoryName) == 'mobility' ||
      _mobilityNamePattern.hasMatch(exercise.name);
}

String _normalizedFilterName(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
