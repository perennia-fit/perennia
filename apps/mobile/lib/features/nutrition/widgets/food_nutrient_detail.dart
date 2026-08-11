import 'package:flutter/material.dart';

import '../../../domain/nutrition/nutrition.dart';
import '../../../theme/theme.dart';

class FoodNutrientDetail extends StatelessWidget {
  const FoodNutrientDetail({
    super.key,
    required this.foodName,
    required this.nutrientsPer100,
  });

  final String foodName;
  final NutrientVector nutrientsPer100;

  static const detailExpansionKey = Key('nutrition.foodNutrient.detail');

  static Key nutrientValueKey(NutrientId id) {
    return Key('nutrition.foodNutrient.value-${id.name}');
  }

  @override
  Widget build(BuildContext context) {
    final commonIds = nutrientIdsForDisplayTier(NutrientDisplayTier.common)
        .where((id) => nutrientsPer100[id].isComplete)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(AppDimens.base),
      children: [
        Text(foodName, style: context.textStyles.h2),
        const SizedBox(height: AppDimens.dense),
        Text(
          'Per 100 g/ml',
          style: context.textStyles.label.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDimens.base),
        _CoreNutrientGrid(nutrients: nutrientsPer100),
        if (commonIds.isNotEmpty) ...[
          const SizedBox(height: AppDimens.base),
          _NutrientSection(
            title: 'Common nutrients',
            ids: commonIds,
            nutrients: nutrientsPer100,
          ),
        ],
        const SizedBox(height: AppDimens.base),
        _NutrientDetailExpansion(nutrients: nutrientsPer100),
      ],
    );
  }
}

class _CoreNutrientGrid extends StatelessWidget {
  const _CoreNutrientGrid({
    required this.nutrients,
  });

  final NutrientVector nutrients;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppDimens.dense,
      runSpacing: AppDimens.dense,
      children: [
        for (final id in nutrientIdsForDisplayTier(NutrientDisplayTier.core))
          _CoreNutrientTile(id: id, amount: nutrients[id]),
      ],
    );
  }
}

class _CoreNutrientTile extends StatelessWidget {
  const _CoreNutrientTile({
    required this.id,
    required this.amount,
  });

  final NutrientId id;
  final NutrientAmount amount;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatNutrientAmount(amount),
                key: FoodNutrientDetail.nutrientValueKey(id),
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
        ),
      ),
    );
  }
}

class _NutrientSection extends StatelessWidget {
  const _NutrientSection({
    required this.title,
    required this.ids,
    required this.nutrients,
  });

  final String title;
  final List<NutrientId> ids;
  final NutrientVector nutrients;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
            Text(title, style: context.textStyles.label),
            const SizedBox(height: AppDimens.dense),
            for (final id in ids) _NutrientRow(id: id, amount: nutrients[id]),
          ],
        ),
      ),
    );
  }
}

class _NutrientDetailExpansion extends StatelessWidget {
  const _NutrientDetailExpansion({
    required this.nutrients,
  });

  final NutrientVector nutrients;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        key: FoodNutrientDetail.detailExpansionKey,
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.dense,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppDimens.dense,
          0,
          AppDimens.dense,
          AppDimens.dense,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        collapsedShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        title: Text('More nutrients', style: context.textStyles.label),
        children: [
          for (final id
              in nutrientIdsForDisplayTier(NutrientDisplayTier.detail))
            _NutrientRow(id: id, amount: nutrients[id]),
        ],
      ),
    );
  }
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({
    required this.id,
    required this.amount,
  });

  final NutrientId id;
  final NutrientAmount amount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDimens.rowHeight,
      child: Row(
        children: [
          Expanded(
            child: Text(
              nutrientDisplayLabel(id),
              style: context.textStyles.body,
            ),
          ),
          Text(
            _formatNutrientAmount(amount),
            key: FoodNutrientDetail.nutrientValueKey(id),
            style: context.textStyles.numeralRow,
          ),
        ],
      ),
    );
  }
}

String _formatNutrientAmount(NutrientAmount amount) {
  if (!amount.isComplete) {
    return '\u2014';
  }
  return '${formatNutritionNumber(amount.value!)} '
      '${nutrientUnitLabel(amount.unit)}';
}
