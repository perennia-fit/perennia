import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart'
    show
        DuplicateMealTypeNameException,
        NutrientValidationException,
        validateNutritionGoalTargets;
import '../../../domain/nutrition/nutrition.dart';
import '../../../theme/theme.dart';
import '../controllers/nutrition_day_controller.dart';
import '../repositories/add_food_repository.dart';
import 'add_food_picker.dart';
import 'log_portion_screen.dart';
import 'nutrition_attribution.dart';
import 'nutrition_trends_view.dart';
import 'quick_entry_dialog.dart';

class NutritionDayView extends ConsumerWidget {
  const NutritionDayView({
    super.key,
    this.onFoodSelected,
  });

  static const String routeName = '/nutrition';
  static const dayHeaderKey = Key('nutrition.dayHeader');
  static const previousDayButtonKey = Key('nutrition.previousDay');
  static const nextDayButtonKey = Key('nutrition.nextDay');
  static const daySummaryKey = Key('nutrition.daySummary');
  static const quickEntryNameFieldKey = QuickEntryDialog.nameFieldKey;
  static const quickEntryEnergyFieldKey = QuickEntryDialog.energyFieldKey;
  static const quickEntrySaveButtonKey = QuickEntryDialog.saveButtonKey;
  static const manageMealTypesButtonKey = Key('nutrition.manageMealTypes');
  static const editGoalsButtonKey = Key('nutrition.editGoals');
  static const viewTrendsButtonKey = Key('nutrition.viewTrends');
  static const saveGoalsButtonKey = Key('nutrition.goals.save');
  static const addMealTypeButtonKey = Key('nutrition.mealType.add');
  static const mealTypeNameFieldKey = Key('nutrition.mealType.name');
  static const saveMealTypeButtonKey = Key('nutrition.mealType.save');
  static const confirmArchiveMealTypeButtonKey =
      Key('nutrition.mealType.confirmArchive');

  final ValueChanged<FoodPickerItem>? onFoodSelected;

  static Key summaryValueKey(NutrientId id) {
    return Key('nutrition.summaryValue-${id.name}');
  }

  static Key goalFieldKey(NutrientId id) {
    return Key('nutrition.goal.field-${id.name}');
  }

  static Key incompleteMarkerKey(NutrientId id) {
    return Key('nutrition.incompleteMarker-${id.name}');
  }

  static Key mealCardKey(String mealId) {
    return Key('nutrition.meal-$mealId');
  }

  static Key startMealButtonKey(String mealTypeId) {
    return Key('nutrition.startMeal-$mealTypeId');
  }

  static Key mealTypeTileKey(String mealTypeId) {
    return Key('nutrition.mealType.tile-$mealTypeId');
  }

  static Key mealTypeReorderHandleKey(String mealTypeId) {
    return Key('nutrition.mealType.reorder-$mealTypeId');
  }

  static Key editMealTypeButtonKey(String mealTypeId) {
    return Key('nutrition.mealType.edit-$mealTypeId');
  }

  static Key archiveMealTypeButtonKey(String mealTypeId) {
    return Key('nutrition.mealType.archive-$mealTypeId');
  }

  static Key addFoodButtonKey(String mealId) {
    return Key('nutrition.addFood-$mealId');
  }

  /// Marks an imported (read-only) `Food Entry` row's provenance badge.
  static Key importedEntryBadgeKey(String foodEntryId) {
    return Key('nutrition.foodEntry.importedBadge-$foodEntryId');
  }

  /// Marks the non-blocking review-flag indicator on a materialized entry.
  static Key reviewFlagMarkerKey(String foodEntryId) {
    return Key('nutrition.foodEntry.reviewFlag-$foodEntryId');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nutritionDayControllerProvider);

    return state.when(
      data: (state) => _NutritionDayContent(
        day: state.day,
        onFoodSelected: onFoodSelected,
      ),
      loading: () => const Scaffold(
        appBar: _NutritionDayAppBar(),
        body: SizedBox.expand(),
      ),
      error: (_, __) => Scaffold(
        appBar: const _NutritionDayAppBar(),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              'Nutrition Day unavailable',
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NutritionDayContent extends ConsumerWidget {
  const _NutritionDayContent({
    required this.day,
    required this.onFoodSelected,
  });

  final NutritionDayRecord day;
  final ValueChanged<FoodPickerItem>? onFoodSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const _NutritionDayAppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: ListView(
            children: [
              _NutritionDayHeader(localDate: day.localDate),
              const SizedBox(height: AppDimens.base),
              ..._nutritionDayBodyChildren(
                context: context,
                ref: ref,
                day: day,
                onFoodSelected: onFoodSelected,
                onStartMeal: (mealType) {
                  return ref
                      .read(nutritionDayControllerProvider.notifier)
                      .startMeal(mealType: mealType);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NutritionDayAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _NutritionDayAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('Nutrition Day'));
  }
}

class NutritionDayBody extends ConsumerWidget {
  const NutritionDayBody({
    super.key,
    required this.day,
    required this.onStartMeal,
    this.onFoodSelected,
  });

  final NutritionDayRecord day;
  final Future<String> Function(MealTypeRecord mealType) onStartMeal;
  final ValueChanged<FoodPickerItem>? onFoodSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _nutritionDayBodyChildren(
        context: context,
        ref: ref,
        day: day,
        onFoodSelected: onFoodSelected,
        onStartMeal: onStartMeal,
      ),
    );
  }
}

List<Widget> _nutritionDayBodyChildren({
  required BuildContext context,
  required WidgetRef ref,
  required NutritionDayRecord day,
  required ValueChanged<FoodPickerItem>? onFoodSelected,
  required Future<String> Function(MealTypeRecord mealType) onStartMeal,
}) {
  final mealTypes = ref.watch(mealTypeListProvider);

  return [
    NutritionDaySummary(totals: day.totals),
    const SizedBox(height: AppDimens.base),
    if (day.meals.isEmpty)
      Text(
        'No meals logged yet',
        style: context.textStyles.body.copyWith(
          color: context.colors.textSecondary,
        ),
      )
    else ...[
      Text('Meals', style: context.textStyles.h2),
      const SizedBox(height: AppDimens.dense),
      for (final meal in day.meals)
        _MealSummary(
          meal: meal,
          onFoodSelected: onFoodSelected,
        ),
    ],
    const SizedBox(height: AppDimens.base),
    _MealTypeActions(
      mealTypes: mealTypes,
      onStartMeal: onStartMeal,
    ),
    const SizedBox(height: AppDimens.touchTarget),
  ];
}

class _NutritionDayHeader extends ConsumerWidget {
  const _NutritionDayHeader({
    required this.localDate,
  });

  final NutritionDayDate localDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      key: NutritionDayView.dayHeaderKey,
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 0) {
          ref.read(nutritionDayControllerProvider.notifier).showPreviousDay();
        } else if (velocity < 0) {
          ref.read(nutritionDayControllerProvider.notifier).showNextDay();
        }
      },
      child: Row(
        children: [
          IconButton(
            key: NutritionDayView.previousDayButtonKey,
            tooltip: 'Previous day',
            onPressed: () {
              ref
                  .read(nutritionDayControllerProvider.notifier)
                  .showPreviousDay();
            },
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              MaterialLocalizations.of(context).formatMediumDate(
                localDate.toLocalDateTime(),
              ),
              textAlign: TextAlign.center,
              style: context.textStyles.h2,
            ),
          ),
          IconButton(
            key: NutritionDayView.nextDayButtonKey,
            tooltip: 'Next day',
            onPressed: () {
              ref.read(nutritionDayControllerProvider.notifier).showNextDay();
            },
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class NutritionDaySummary extends StatelessWidget {
  const NutritionDaySummary({
    super.key,
    required this.totals,
  });

  final NutrientTotals totals;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Nutrition Day summary',
      child: Wrap(
        key: NutritionDayView.daySummaryKey,
        spacing: AppDimens.dense,
        runSpacing: AppDimens.dense,
        children: [
          _NutrientSummaryTile(
            label: 'Calories',
            total: totals[NutrientId.energy],
          ),
          _NutrientSummaryTile(
            label: 'Protein',
            total: totals[NutrientId.protein],
          ),
          _NutrientSummaryTile(
            label: 'Carbs',
            total: totals[NutrientId.carbohydrate],
          ),
          _NutrientSummaryTile(
            label: 'Fat',
            total: totals[NutrientId.fat],
          ),
        ],
      ),
    );
  }
}

class _NutrientSummaryTile extends StatelessWidget {
  const _NutrientSummaryTile({
    required this.label,
    required this.total,
  });

  final String label;
  final NutrientTotal total;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 112),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.dense),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatNutrientTotal(total),
                    key: NutritionDayView.summaryValueKey(total.id),
                    style: context.textStyles.h2,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: context.textStyles.label.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
              if (total.isIncomplete) ...[
                const SizedBox(width: AppDimens.dense),
                Tooltip(
                  message: 'Incomplete total',
                  child: Icon(
                    Icons.info_outline,
                    key: NutritionDayView.incompleteMarkerKey(total.id),
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MealTypeActions extends ConsumerWidget {
  const _MealTypeActions({
    required this.mealTypes,
    required this.onStartMeal,
  });

  final AsyncValue<List<MealTypeRecord>> mealTypes;
  final Future<String> Function(MealTypeRecord mealType) onStartMeal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return mealTypes.when(
      data: (types) {
        if (types.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start Meal', style: context.textStyles.h2),
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense,
              children: [
                for (final type in types)
                  OutlinedButton.icon(
                    key: NutritionDayView.startMealButtonKey(type.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.textPrimary,
                    ),
                    onPressed: () {
                      unawaited(
                        onStartMeal(type),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: Text(type.name),
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.dense),
            TextButton.icon(
              key: NutritionDayView.manageMealTypesButtonKey,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.textPrimary,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _MealTypeManagerScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.tune),
              label: const Text('Manage Meal Types'),
            ),
            TextButton.icon(
              key: NutritionDayView.editGoalsButtonKey,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.textPrimary,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NutritionGoalEditorScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Nutrition Goals'),
            ),
            TextButton.icon(
              key: NutritionDayView.viewTrendsButtonKey,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.textPrimary,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NutritionTrendsView(),
                  ),
                );
              },
              icon: const Icon(Icons.insights_outlined),
              label: const Text('Nutrition Trends'),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => Text(
        'Meal Types unavailable',
        style: context.textStyles.body.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _MealTypeManagerScreen extends ConsumerWidget {
  const _MealTypeManagerScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mealTypes = ref.watch(mealTypeListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Meal Types')),
      body: SafeArea(
        child: mealTypes.when(
          data: (types) {
            return ReorderableListView.builder(
              padding: const EdgeInsets.all(AppDimens.base),
              header: Padding(
                padding: const EdgeInsets.only(bottom: AppDimens.base),
                child: FilledButton.icon(
                  key: NutritionDayView.addMealTypeButtonKey,
                  onPressed: () => _openCreateMealType(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Meal Type'),
                ),
              ),
              itemCount: types.length,
              onReorderItem: (oldIndex, newIndex) {
                final ids = types.map((type) => type.id).toList(growable: true);
                final moved = ids.removeAt(oldIndex);
                ids.insert(newIndex, moved);
                unawaited(
                  ref
                      .read(nutritionDayControllerProvider.notifier)
                      .reorderMealTypes(ids),
                );
              },
              itemBuilder: (context, index) {
                final type = types[index];
                return _MealTypeManagementTile(
                  key: ValueKey<String>(type.id),
                  mealType: type,
                  index: index,
                );
              },
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              'Meal Types unavailable',
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openCreateMealType(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _MealTypeFormScreen(),
      ),
    );
  }
}

class _MealTypeManagementTile extends ConsumerWidget {
  const _MealTypeManagementTile({
    super.key,
    required this.mealType,
    required this.index,
  });

  final MealTypeRecord mealType;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      key: NutritionDayView.mealTypeTileKey(mealType.id),
      margin: const EdgeInsets.only(bottom: AppDimens.dense),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              button: true,
              label: 'Reorder Meal Type',
              child: SizedBox(
                key: NutritionDayView.mealTypeReorderHandleKey(mealType.id),
                width: AppDimens.touchTarget,
                height: AppDimens.touchTarget,
                child: Icon(
                  Icons.drag_handle,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(mealType.name),
              subtitle: Text('Display order ${mealType.sortOrder + 1}'),
            ),
          ),
          IconButton(
            key: NutritionDayView.editMealTypeButtonKey(mealType.id),
            tooltip: 'Rename Meal Type',
            onPressed: () => _openEditMealType(context),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: NutritionDayView.archiveMealTypeButtonKey(mealType.id),
            tooltip: 'Archive Meal Type',
            onPressed: () => _confirmArchive(context, ref),
            icon: const Icon(Icons.archive_outlined),
          ),
        ],
      ),
    );
  }

  void _openEditMealType(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MealTypeFormScreen(mealType: mealType),
      ),
    );
  }

  Future<void> _confirmArchive(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Archive ${mealType.name}?'),
            content: const Text(
              'Existing Meals keep their stamped Meal Type. '
              'Archived types leave the picker.',
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: NutritionDayView.confirmArchiveMealTypeButtonKey,
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Archive'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }

    await ref
        .read(nutritionDayControllerProvider.notifier)
        .archiveMealType(mealType.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${mealType.name} archived')),
    );
  }
}

class _MealTypeFormScreen extends ConsumerStatefulWidget {
  const _MealTypeFormScreen({
    this.mealType,
  });

  final MealTypeRecord? mealType;

  @override
  ConsumerState<_MealTypeFormScreen> createState() =>
      _MealTypeFormScreenState();
}

class _MealTypeFormScreenState extends ConsumerState<_MealTypeFormScreen> {
  late final TextEditingController _nameController;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.mealType?.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.mealType != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Rename Meal Type' : 'New Meal Type'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.base),
          children: [
            TextField(
              key: NutritionDayView.mealTypeNameFieldKey,
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Meal Type name',
                errorText: _nameError,
              ),
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppDimens.base),
            FilledButton(
              key: NutritionDayView.saveMealTypeButtonKey,
              onPressed: _save,
              child: Text(isEditing ? 'Save' : 'Add Meal Type'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _nameError = 'Meal Type is required';
      });
      return;
    }

    final mealType = widget.mealType;
    try {
      if (mealType == null) {
        await ref
            .read(nutritionDayControllerProvider.notifier)
            .createMealType(name: name);
      } else {
        await ref.read(nutritionDayControllerProvider.notifier).renameMealType(
              mealType: mealType,
              name: name,
            );
      }
    } on DuplicateMealTypeNameException {
      if (!mounted) {
        return;
      }
      setState(() {
        _nameError = 'Meal Type already exists';
      });
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}

/// A small settings-style editor for the v1 nutrition `Goal`: one field per
/// goalable `Nutrient` (energy + the three macros), each a fixed target value
/// with its unit. Goals attach to the **derived** nutrition analytics, never a
/// `Metric`. Distribution, per-weekday, and micronutrient forms are
/// deferred (NUTRITION.md §12) — only these four fields exist. Reached from the
/// nutrition secondary surface, not primary navigation.
class NutritionGoalEditorScreen extends ConsumerWidget {
  const NutritionGoalEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(nutritionGoalListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nutrition Goals')),
      body: SafeArea(
        child: goals.when(
          data: (records) => _NutritionGoalForm(
            goalsByNutrient: <NutrientId, NutritionGoalRecord>{
              for (final record in records) record.nutrient: record,
            },
          ),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              'Nutrition Goals unavailable',
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NutritionGoalForm extends ConsumerStatefulWidget {
  const _NutritionGoalForm({
    required this.goalsByNutrient,
  });

  final Map<NutrientId, NutritionGoalRecord> goalsByNutrient;

  @override
  ConsumerState<_NutritionGoalForm> createState() => _NutritionGoalFormState();
}

class _NutritionGoalFormState extends ConsumerState<_NutritionGoalForm> {
  late final Map<NutrientId, TextEditingController> _controllers;
  final Map<NutrientId, String?> _errors = <NutrientId, String?>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controllers = <NutrientId, TextEditingController>{
      for (final id in goalableNutrientIds)
        id: TextEditingController(
          text: widget.goalsByNutrient[id]?.target.entered ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppDimens.base),
      children: [
        Text(
          'Set a daily target for calories and the three macros. Targets '
          'compare against the day’s logged totals — they never store '
          'a computed total.',
          style: context.textStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDimens.base),
        for (final id in goalableNutrientIds) ...[
          TextField(
            key: NutritionDayView.goalFieldKey(id),
            controller: _controllers[id],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  '${nutrientDisplayLabel(id)} target '
                  '(${nutrientUnitLabel(id.defaultUnit)})',
              helperText: 'Leave empty to clear this goal',
              errorText: _errors[id],
            ),
          ),
          const SizedBox(height: AppDimens.base),
        ],
        FilledButton(
          key: NutritionDayView.saveGoalsButtonKey,
          onPressed: _saving ? null : _save,
          child: const Text('Save Goals'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final controller = ref.read(nutritionDayControllerProvider.notifier);
    final parsed = <NutrientId, double?>{};
    final errors = <NutrientId, String?>{};
    var hasError = false;

    for (final id in goalableNutrientIds) {
      final raw = _controllers[id]!.text.trim();
      if (raw.isEmpty) {
        parsed[id] = null;
        errors[id] = null;
        continue;
      }
      final value = double.tryParse(raw);
      if (value == null) {
        errors[id] = 'Enter a number';
        hasError = true;
        continue;
      }
      // Reuse the shared two-tier validator for the hard-reject bounds so the
      // editor agrees with the repository and the agent API (NUTRITION.md §6).
      final result = validateNutritionGoalTargets(<NutritionGoalTarget>[
        NutritionGoalTarget(nutrient: id, value: value, entered: raw),
      ]);
      if (!result.accepted) {
        errors[id] = result.errors.first.message;
        hasError = true;
        continue;
      }
      parsed[id] = value;
      errors[id] = null;
    }

    if (hasError) {
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
      });
      return;
    }

    setState(() {
      _saving = true;
      _errors
        ..clear()
        ..addAll(errors);
    });

    try {
      for (final id in goalableNutrientIds) {
        final value = parsed[id];
        if (value == null) {
          await controller.clearNutritionGoal(id);
        } else {
          await controller.saveNutritionGoal(
            NutritionGoalTarget(
              nutrient: id,
              value: value,
              entered: _controllers[id]!.text.trim(),
            ),
          );
        }
      }
    } on NutrientValidationException catch (error) {
      if (!mounted) {
        return;
      }
      final issue = error.errors.first;
      setState(() {
        _saving = false;
        final nutrient = issue.nutrient;
        if (nutrient != null) {
          _errors[nutrient] = issue.message;
        }
      });
      return;
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nutrition Goals saved')),
    );
  }
}

class _MealSummary extends ConsumerWidget {
  const _MealSummary({
    required this.meal,
    required this.onFoodSelected,
  });

  final NutritionDayMealRecord meal;
  final ValueChanged<FoodPickerItem>? onFoodSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final energy = meal.totals[NutrientId.energy];
    final localizations = MaterialLocalizations.of(context);
    final startedAt = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(meal.meal.startedAt.toLocal()),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.dense),
      child: DecoratedBox(
        key: NutritionDayView.mealCardKey(meal.meal.id),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border.all(color: context.colors.divider),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.dense),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.restaurant_outlined, size: 18),
                  const SizedBox(width: AppDimens.dense),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          meal.meal.mealType,
                          style: context.textStyles.body,
                        ),
                        Text(
                          startedAt,
                          style: context.textStyles.label.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatNutrientTotal(energy),
                    style: context.textStyles.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
              if (meal.entries.isNotEmpty) ...[
                const SizedBox(height: AppDimens.dense),
                for (final entry in meal.entries) _FoodEntryLine(entry: entry),
              ],
              const SizedBox(height: AppDimens.dense),
              OutlinedButton.icon(
                key: NutritionDayView.addFoodButtonKey(meal.meal.id),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                ),
                onPressed: () {
                  unawaited(
                    _showAddFoodPicker(
                      context,
                      ref,
                      meal.meal,
                      onFoodSelected,
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Add food'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodEntryLine extends StatelessWidget {
  const _FoodEntryLine({
    required this.entry,
  });

  final FoodEntryRecord entry;

  @override
  Widget build(BuildContext context) {
    final energy = entry.resolvedNutrients[NutrientId.energy];
    final foodSource = entry.foodSource;
    final showImportedBadge = entry.isImported && foodSource != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.name,
                  style: context.textStyles.body,
                ),
              ),
              const SizedBox(width: AppDimens.dense),
              Text(
                _formatFoodEntryAmount(entry),
                style: context.textStyles.label.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(width: AppDimens.dense),
              Text(
                _formatNutrientAmount(energy),
                style: context.textStyles.label.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
          if (showImportedBadge || entry.hasReviewFlags) ...[
            const SizedBox(height: AppDimens.dense / 2),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense / 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (showImportedBadge)
                  KeyedSubtree(
                    key: NutritionDayView.importedEntryBadgeKey(entry.id),
                    // Imported entries are read-only observations; the badge
                    // surfaces the Food Source (and the preserved provider
                    // string for a generic Imported origin).
                    child: FoodSourceBadge(
                      source: foodSource,
                      providerLabel: entry.importProvider,
                    ),
                  ),
                if (entry.hasReviewFlags)
                  _ReviewFlagMarker(entry: entry),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A small, **non-blocking** indicator that a materialized `Food Entry` carries
/// soft-warn review flags the user may want to look at (NUTRITION.md §6/§10).
/// It is informational — never a blocking dialog. Color is paired with text and
/// an icon, never the sole signal.
class _ReviewFlagMarker extends StatelessWidget {
  const _ReviewFlagMarker({required this.entry});

  final FoodEntryRecord entry;

  @override
  Widget build(BuildContext context) {
    final count = entry.reviewFlags.length;
    final label = count == 1 ? 'Review flag' : '$count review flags';

    return Semantics(
      label: '$label to review',
      child: Padding(
        key: NutritionDayView.reviewFlagMarkerKey(entry.id),
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flag_outlined,
              size: 16,
              color: context.colors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: context.textStyles.caption.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAddFoodPicker(
  BuildContext context,
  WidgetRef ref,
  MealRecord meal,
  ValueChanged<FoodPickerItem>? onFoodSelected,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return FractionallySizedBox(
        heightFactor: 0.88,
        child: AddFoodPicker(
          meal: meal,
          onFoodSelected: (food) {
            Navigator.of(sheetContext).pop();
            if (onFoodSelected != null) {
              onFoodSelected(food);
              return;
            }
            unawaited(_showLogPortion(context, ref, meal, food));
          },
          onQuickEntry: (draft) {
            return ref
                .read(nutritionDayControllerProvider.notifier)
                .logQuickEntryForMeal(
                  mealId: meal.id,
                  entry: draft,
                )
                .then((_) {});
          },
        ),
      );
    },
  );
}

Future<void> _showLogPortion(
  BuildContext context,
  WidgetRef ref,
  MealRecord meal,
  FoodPickerItem food,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) {
      return FractionallySizedBox(
        heightFactor: 0.82,
        child: LogPortionScreen(
          meal: meal,
          food: food,
          onSave: (draft) {
            return ref
                .read(nutritionDayControllerProvider.notifier)
                .logFoodEntrySnapshot(entry: draft);
          },
        ),
      );
    },
  );
}

String _formatNutrientTotal(NutrientTotal total) {
  if (total.isIncomplete) {
    return '—';
  }
  return '${formatNutritionNumber(total.value)} '
      '${nutrientUnitLabel(total.unit)}';
}

String _formatNutrientAmount(NutrientAmount amount) {
  if (!amount.isComplete) {
    return '—';
  }
  return '${formatNutritionNumber(amount.value!)} '
      '${nutrientUnitLabel(amount.unit)}';
}

String _formatFoodEntryAmount(FoodEntryRecord entry) {
  final portion = entry.portion;
  if (portion == null) {
    return 'Quick entry';
  }
  return '${portion.entered} ${portionUnitLabel(portion.unit)}';
}
