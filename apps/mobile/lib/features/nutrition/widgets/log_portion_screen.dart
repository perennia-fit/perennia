import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/nutrition/nutrition.dart';
import '../../../domain/training/set_validation.dart'
    show NutrientValidationException;
import '../../../theme/theme.dart';
import '../controllers/nutrition_day_controller.dart';
import '../repositories/add_food_repository.dart';
import 'nutrition_attribution.dart';

class LogPortionScreen extends ConsumerStatefulWidget {
  const LogPortionScreen({
    super.key,
    required this.meal,
    required this.food,
    this.onSave,
  });

  static const amountFieldKey = Key('nutrition.logPortion.amount');
  static const decrementButtonKey = Key('nutrition.logPortion.decrement');
  static const incrementButtonKey = Key('nutrition.logPortion.increment');
  static const saveButtonKey = Key('nutrition.logPortion.save');

  final MealRecord meal;
  final FoodPickerItem food;
  final Future<LogFoodEntryResult> Function(FoodEntrySnapshotDraft draft)?
      onSave;

  static Key unitChipKey(PortionUnit unit) {
    return Key('nutrition.logPortion.unit-${unit.name}');
  }

  static Key readoutValueKey(NutrientId id) {
    return Key('nutrition.logPortion.readout-${id.name}');
  }

  @override
  ConsumerState<LogPortionScreen> createState() => _LogPortionScreenState();
}

class _LogPortionScreenState extends ConsumerState<LogPortionScreen> {
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
                Text(
                  widget.meal.mealType,
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
              const OpenFoodFactsAttributionNotice(compact: true),
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
    final draft = FoodEntrySnapshotDraft(
      mealId: widget.meal.id,
      foodId: widget.food.id,
      name: widget.food.name,
      foodSource: widget.food.foodSource,
      nutrientsPer100: widget.food.nutrientsPer100,
      isLiquid: widget.food.isLiquid,
      servingLabel: widget.food.servingLabel,
      servingSize: widget.food.servingSize,
      packageSize: widget.food.packageSize,
      portion: portion,
    );

    try {
      final result = await () {
        final onSave = widget.onSave;
        if (onSave != null) {
          return onSave(draft);
        }
        return ref
            .read(nutritionDayControllerProvider.notifier)
            .logFoodEntrySnapshot(entry: draft);
      }();
      if (mounted) {
        _showWarnings(result.warnings);
        await Navigator.of(context).maybePop();
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
