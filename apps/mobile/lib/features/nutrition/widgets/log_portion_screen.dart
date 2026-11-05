import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/nutrition/nutrition.dart';
import '../../../domain/training/set_validation.dart'
    show NutrientValidationException;
import '../../../theme/theme.dart';
import '../repositories/add_food_repository.dart';
import 'nutrition_attribution.dart';

/// Chooses a Portion for one Food (docs/designs/meal-logging.md §6).
///
/// The default constructor logs [food] into [target]: Save hands one Food
/// Entry snapshot to [onSave], which creates the Meal first for a
/// [NewMealTarget], and pops with the id of the Meal it landed in.
///
/// [LogPortionScreen.editEntry] changes a logged Food Entry's Portion
/// instead: it shows the entry's own snapshot, prefilled with its Portion,
/// hands the new Portion to [onUpdatePortion], and pops with the entry's
/// Meal id.
///
/// The screen never writes on its own: the caller owns the write, so the
/// Meal screen's in-flight guard, its already-exists handling, and its switch
/// to the saved Meal cover every Save.
class LogPortionScreen extends StatefulWidget {
  const LogPortionScreen({
    super.key,
    required MealTarget this.target,
    required this.food,
    this.contextLabel,
    required Future<LogFoodEntryResult?> Function(FoodEntrySnapshotDraft draft)
        this.onSave,
  })  : entry = null,
        onUpdatePortion = null;

  /// Edit mode, only for an entry [canEditEntry] accepts: the Meal screen
  /// decides which entries open it.
  LogPortionScreen.editEntry({
    super.key,
    required FoodEntryRecord this.entry,
    this.contextLabel,
    required Future<LogFoodEntryResult?> Function(Portion portion)
        this.onUpdatePortion,
  })  : assert(
          canEditEntry(entry),
          'Only a Food-backed entry without import keys has an editable '
          'Portion.',
        ),
        target = null,
        food = _foodOfEntry(entry),
        onSave = null;

  static const amountFieldKey = Key('nutrition.logPortion.amount');
  static const brandKey = Key('nutrition.logPortion.brand');
  static const decrementButtonKey = Key('nutrition.logPortion.decrement');
  static const incrementButtonKey = Key('nutrition.logPortion.increment');
  static const saveButtonKey = Key('nutrition.logPortion.save');

  /// The Meal Save logs into; null in edit mode.
  final MealTarget? target;

  /// The Food shown: the picked Food, or in edit mode the entry's snapshot.
  final FoodPickerItem food;

  /// The Food Entry whose Portion Save changes; null when logging a Food.
  final FoodEntryRecord? entry;

  /// A line under the Food naming where it is logged (the Meal screen's
  /// header text); nothing shows when null.
  final String? contextLabel;

  /// Makes the log write; null in edit mode. A null result means the write
  /// was ignored, and the screen stays open.
  final Future<LogFoodEntryResult?> Function(FoodEntrySnapshotDraft draft)?
      onSave;

  /// Makes the edit-mode write; null when logging a Food. A null result means
  /// the write was ignored, and the screen stays open.
  final Future<LogFoodEntryResult?> Function(Portion portion)? onUpdatePortion;

  /// Whether [entry]'s Portion can be edited here: a Food-backed entry
  /// without import keys. Imported entries are immutable observations and
  /// Quick Entries have no Portion, so both are remove-only (§6).
  static bool canEditEntry(FoodEntryRecord entry) {
    return entry.kind == FoodEntryKind.food &&
        entry.foodId != null &&
        entry.foodSource != null &&
        entry.portion != null &&
        entry.importSource == null &&
        entry.importExternalId == null;
  }

  static Key unitChipKey(PortionUnit unit) {
    return Key('nutrition.logPortion.unit-${unit.name}');
  }

  static Key readoutValueKey(NutrientId id) {
    return Key('nutrition.logPortion.readout-${id.name}');
  }

  @override
  State<LogPortionScreen> createState() => _LogPortionScreenState();
}

class _LogPortionScreenState extends State<LogPortionScreen> {
  late PortionUnit _unit;
  late final TextEditingController _amountController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initialPortion = _initialPortionForFood(widget.food);
    _unit = initialPortion.unit;
    _amountController = TextEditingController(
      text: initialPortion.entered,
    );
  }

  @override
  void didUpdateWidget(LogPortionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.food.id == widget.food.id &&
        oldWidget.food.foodSource == widget.food.foodSource) {
      return;
    }
    final initialPortion = _initialPortionForFood(widget.food);
    _unit = initialPortion.unit;
    _amountController.text = initialPortion.entered;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portion = _portionOrNull();
    final resolvedNutrients = portion == null
        ? null
        : _resolvedNutrients(
            portion,
          );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppDimens.base,
          right: AppDimens.base,
          top: AppDimens.base,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppDimens.base,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(widget.food.name, style: context.textStyles.h1),
            if (widget.food.brand case final brand?) ...[
              const SizedBox(height: AppDimens.dense / 2),
              Text(
                brand,
                key: LogPortionScreen.brandKey,
                style: context.textStyles.body.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FoodSourceBadge(
                  source: widget.food.foodSource,
                  showLicense:
                      widget.food.foodSource == FoodSource.openFoodFacts,
                ),
                if (widget.contextLabel case final label?)
                  Text(
                    label,
                    style: context.textStyles.label.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppDimens.base),
            _AmountStepper(
              controller: _amountController,
              unit: _unit,
              onChanged: () => setState(() {}),
              onDecrement: () => _stepAmount(-_stepForUnit(_unit)),
              onIncrement: () => _stepAmount(_stepForUnit(_unit)),
            ),
            const SizedBox(height: AppDimens.base),
            _UnitChips(
              units: widget.food.availablePortionUnits,
              selected: _unit,
              onSelected: _selectUnit,
            ),
            if (_portionHint != null) ...[
              const SizedBox(height: AppDimens.dense),
              Text(
                _portionHint!,
                style: context.textStyles.caption.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppDimens.base),
            _PortionReadout(nutrients: resolvedNutrients),
            const SizedBox(height: AppDimens.base),
            FilledButton.icon(
              key: LogPortionScreen.saveButtonKey,
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.save,
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
                minimumSize: const Size.fromHeight(AppDimens.rowHeight),
              ),
              onPressed: portion == null || _saving
                  ? null
                  : () {
                      unawaited(_save(portion));
                    },
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Save'),
            ),
            if (widget.food.foodSource == FoodSource.openFoodFacts) ...[
              const SizedBox(height: AppDimens.base),
              OpenFoodFactsAttributionNotice(
                code: widget.food.id,
                changeDate: widget.food.sourceModifiedAt,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? get _portionHint {
    return switch (_unit) {
      PortionUnit.serving when widget.food.servingSize != null =>
        '${widget.food.servingLabel ?? 'Serving'} = '
            '${formatNutritionNumber(widget.food.servingSize!)} '
            '${widget.food.isLiquid ? 'ml' : 'g'}',
      PortionUnit.package when widget.food.packageSize != null =>
        'Package = ${formatNutritionNumber(widget.food.packageSize!)} '
            '${widget.food.isLiquid ? 'ml' : 'g'}',
      _ => null,
    };
  }

  void _selectUnit(PortionUnit unit) {
    if (unit == _unit) {
      return;
    }
    setState(() {
      _unit = unit;
      _amountController.text = _defaultAmountText(unit);
    });
  }

  void _stepAmount(double delta) {
    final current = _parseAmount() ?? _defaultAmount(_unit);
    final step = _stepForUnit(_unit);
    final next = current + delta;
    final clamped = next <= 0 ? step : next;
    _amountController.text = _formatPortionInput(clamped);
    setState(() {});
  }

  Portion? _portionOrNull() {
    final value = _parseAmount();
    if (value == null) {
      return null;
    }
    try {
      return Portion(
        value: value,
        entered: _amountController.text,
        unit: _unit,
      );
    } on ArgumentError {
      return null;
    }
  }

  double? _parseAmount() {
    final value = double.tryParse(_amountController.text.trim());
    if (value == null || !value.isFinite || value <= 0) {
      return null;
    }
    return value;
  }

  NutrientVector _resolvedNutrients(Portion portion) {
    final baseQuantity = resolvePortionBaseQuantity(
      portion,
      servingSize: widget.food.servingSize,
      packageSize: widget.food.packageSize,
    );
    return widget.food.nutrientsPer100.scale(baseQuantity / 100);
  }

  Future<void> _save(Portion portion) async {
    setState(() => _saving = true);
    try {
      final mealId = await _write(portion);
      if (mounted && mealId != null) {
        await Navigator.of(context).maybePop<String>(mealId);
      }
    } on NutrientValidationException catch (error) {
      if (mounted) {
        _showValidationError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// Makes Save's one write and shows its warnings. Returns the id of the
  /// Meal it landed in, or null when the hook ignored it.
  Future<String?> _write(Portion portion) async {
    final entry = widget.entry;
    if (entry != null) {
      final result = await widget.onUpdatePortion!(portion);
      if (result == null) {
        return null;
      }
      if (mounted) {
        _showWarnings(result.warnings);
      }
      return entry.mealId;
    }

    final target = widget.target!;
    final food = widget.food;
    final draft = FoodEntrySnapshotDraft(
      mealId: target.mealId,
      foodId: food.id,
      name: food.name,
      foodSource: food.foodSource,
      nutrientsPer100: food.nutrientsPer100,
      isLiquid: food.isLiquid,
      servingLabel: food.servingLabel,
      servingSize: food.servingSize,
      packageSize: food.packageSize,
      portion: portion,
    );
    final result = await widget.onSave!(draft);
    if (result == null) {
      return null;
    }
    if (mounted) {
      _showWarnings(result.warnings);
    }
    return result.mealId;
  }

  void _showValidationError(NutrientValidationException error) {
    final message =
        error.errors.isEmpty ? error.message : error.errors.first.message;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showWarnings(List<NutrientValidationIssue> warnings) {
    if (warnings.isEmpty) {
      return;
    }
    final message = warnings.length == 1
        ? warnings.single.message
        : 'Food Entry saved with ${warnings.length} warnings.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _AmountStepper extends StatelessWidget {
  const _AmountStepper({
    required this.controller,
    required this.unit,
    required this.onChanged,
    required this.onDecrement,
    required this.onIncrement,
  });

  final TextEditingController controller;
  final PortionUnit unit;
  final VoidCallback onChanged;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.outlined(
          key: LogPortionScreen.decrementButtonKey,
          tooltip: 'Decrease amount',
          onPressed: onDecrement,
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: AppDimens.dense),
        Expanded(
          child: TextField(
            key: LogPortionScreen.amountFieldKey,
            controller: controller,
            textAlign: TextAlign.center,
            style: context.textStyles.numeralHero,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: InputDecoration(
              labelText: 'Amount',
              suffixText: portionUnitLabel(unit),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: AppDimens.dense),
        IconButton.filled(
          key: LogPortionScreen.incrementButtonKey,
          tooltip: 'Increase amount',
          onPressed: onIncrement,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _UnitChips extends StatelessWidget {
  const _UnitChips({
    required this.units,
    required this.selected,
    required this.onSelected,
  });

  final List<PortionUnit> units;
  final PortionUnit selected;
  final ValueChanged<PortionUnit> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppDimens.dense,
      runSpacing: AppDimens.dense,
      children: [
        for (final unit in units)
          ChoiceChip(
            key: LogPortionScreen.unitChipKey(unit),
            label: Text(portionUnitLabel(unit)),
            selected: selected == unit,
            onSelected: (_) => onSelected(unit),
          ),
      ],
    );
  }
}

class _PortionReadout extends StatelessWidget {
  const _PortionReadout({
    required this.nutrients,
  });

  final NutrientVector? nutrients;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.dense),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This portion', style: context.textStyles.label),
            const SizedBox(height: AppDimens.dense),
            Wrap(
              spacing: AppDimens.dense,
              runSpacing: AppDimens.dense,
              children: [
                for (final id in NutrientVector.coreIds)
                  _ReadoutTile(id: id, amount: nutrients?[id]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadoutTile extends StatelessWidget {
  const _ReadoutTile({
    required this.id,
    required this.amount,
  });

  final NutrientId id;
  final NutrientAmount? amount;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatAmount(amount),
            key: LogPortionScreen.readoutValueKey(id),
            style: context.textStyles.h2,
          ),
          const SizedBox(height: 2),
          Text(
            nutrientDisplayLabel(id),
            style: context.textStyles.label.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatAmount(NutrientAmount? amount) {
  if (amount == null || !amount.isComplete) {
    return '\u2014';
  }
  return '${formatNutritionNumber(amount.value!)} '
      '${nutrientUnitLabel(amount.unit)}';
}

String _defaultAmountText(PortionUnit unit) {
  return _formatPortionInput(_defaultAmount(unit));
}

/// The entry's own snapshot in the shape the shared readout reads, with its
/// Portion as the prefill. Facts come from the entry, never from the current
/// Food: a Food Entry is self-describing.
FoodPickerItem _foodOfEntry(FoodEntryRecord entry) {
  return FoodPickerItem(
    id: entry.foodId ?? '',
    name: entry.name,
    origin: FoodPickerOrigin.history,
    foodSource: entry.foodSource ?? FoodSource.user,
    nutrientsPer100: entry.nutrients,
    isLiquid: entry.isLiquid ?? false,
    servingLabel: entry.servingLabel,
    servingSize: entry.servingSize,
    packageSize: entry.packageSize,
    lastPortion: entry.portion,
  );
}

Portion _initialPortionForFood(FoodPickerItem food) {
  final availableUnits = food.availablePortionUnits;
  final lastPortion = food.lastPortion;
  if (lastPortion != null && availableUnits.contains(lastPortion.unit)) {
    return lastPortion;
  }
  final unit = availableUnits.first;
  return Portion(
    value: _defaultAmount(unit),
    entered: _defaultAmountText(unit),
    unit: unit,
  );
}

double _defaultAmount(PortionUnit unit) {
  return switch (unit) {
    PortionUnit.gram || PortionUnit.milliliter => 100,
    PortionUnit.ounce || PortionUnit.fluidOunce => 1,
    PortionUnit.serving || PortionUnit.package => 1,
  };
}

double _stepForUnit(PortionUnit unit) {
  return switch (unit) {
    PortionUnit.gram || PortionUnit.milliliter => 5,
    PortionUnit.ounce || PortionUnit.fluidOunce => 0.25,
    PortionUnit.serving || PortionUnit.package => 0.25,
  };
}

String _formatPortionInput(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.000001) {
    return rounded.toInt().toString();
  }
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
        RegExp(r'\.$'),
        '',
      );
}
