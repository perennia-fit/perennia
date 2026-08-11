import 'package:flutter/material.dart';

import '../../../domain/nutrition/nutrition.dart';
import '../../../theme/theme.dart';

class QuickEntryDialog extends StatefulWidget {
  const QuickEntryDialog({
    super.key,
    required this.mealType,
  });

  static const nameFieldKey = Key('nutrition.quickEntry.name');
  static const energyFieldKey = Key('nutrition.quickEntry.energy');
  static const saveButtonKey = Key('nutrition.quickEntry.save');

  final String mealType;

  @override
  State<QuickEntryDialog> createState() => _QuickEntryDialogState();
}

class _QuickEntryDialogState extends State<QuickEntryDialog> {
  final _nameController = TextEditingController();
  final _energyController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _energyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add food to ${widget.mealType}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: QuickEntryDialog.nameFieldKey,
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Food name'),
          ),
          TextField(
            key: QuickEntryDialog.energyFieldKey,
            controller: _energyController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Calories'),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: context.colors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: QuickEntryDialog.saveButtonKey,
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    final energyEntered = _energyController.text.trim();
    final energy = double.tryParse(energyEntered);
    if (name.isEmpty || energy == null || energy < 0) {
      return;
    }
    Navigator.of(context).pop(
      QuickFoodEntryDraft(
        name: name,
        nutrients: NutrientVector.full(
          <NutrientId, NutrientAmount>{
            NutrientId.energy: NutrientAmount.complete(
              value: energy,
              entered: energyEntered,
              unit: NutrientUnit.kilocalorie,
            ),
          },
        ),
      ),
    );
  }
}
