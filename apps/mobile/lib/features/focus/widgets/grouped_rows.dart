import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

/// One bordered surface holding a run of rows, separated by hairlines
/// indented by the base gutter: a grouped list, never a stack of cards.
class GroupedRows extends StatelessWidget {
  const GroupedRows({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.colors.divider),
        borderRadius: AppRadii.cardMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index += 1) ...[
            if (index > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppDimens.base,
                color: context.colors.divider,
              ),
            children[index],
          ],
        ],
      ),
    );
  }
}

/// The selected look of a Focus chip wherever one appears: translucent Signal
/// Cyan with a cyan edge, as DESIGN.md sets selection; the theme's secondary
/// (Rested Teal) is reserved for Save. Avatar icons stay neutral so the chip
/// row adds no extra cyan marks.
({Color selectedColor, BorderSide side, TextStyle labelStyle, Color iconColor})
    focusChipStyle(BuildContext context, {required bool isSelected}) {
  final primary = Theme.of(context).colorScheme.primary;
  return (
    selectedColor: primary.withValues(alpha: 0.22),
    side: BorderSide(color: isSelected ? primary : context.colors.divider),
    labelStyle: context.textStyles.label.copyWith(
      color: context.colors.textPrimary,
    ),
    iconColor: context.colors.textSecondary,
  );
}
