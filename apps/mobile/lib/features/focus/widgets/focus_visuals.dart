import 'package:flutter/material.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/focus_color.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';

/// Icons for the starter Focuses, keyed by their seeded ids. A Focus the user
/// created, or a starter they renamed into something else, keeps a neutral
/// icon: the icon is a recognition aid next to the name, never the signal.
const _starterFocusIcons = <String, IconData>{
  starterFocusWeightsId: Icons.fitness_center,
  starterFocusEnduranceId: Icons.directions_run,
  starterFocusFunctionalId: Icons.bolt_outlined,
  starterFocusCalisthenicsId: Icons.sports_gymnastics,
  starterFocusMobilityId: Icons.self_improvement,
};

IconData focusIcon(String focusId) {
  return _starterFocusIcons[focusId] ?? Icons.flag_outlined;
}

/// The color training under [focus] is drawn in: the user's stored color, or
/// the Focus's default category token when none is stored or it is malformed.
Color resolvedFocusColor(FocusRecord focus, AppColors colors) {
  final fallback = colors.categoryColor(focusDefaultColorToken(focus.id));
  final colorHex = focus.colorHex;
  return colorHex == null
      ? fallback
      : colorFromHex(colorHex, fallback: fallback);
}

/// The name a Workout or Template shows for its Focus: the Focus's name,
/// marked when it has since been archived so history still reads honestly.
String focusDisplayName(BuildContext context, FocusRecord focus) {
  return focus.isArchived
      ? context.l10n.focusArchivedName(focus.name)
      : focus.name;
}

/// A Focus as a selectable chip, wherever Focuses are chosen. The theme gives
/// selection its Signal Cyan tint; the chip adds a cyan edge so the selected
/// one reads at a glance, and keeps its icon neutral so a chip row adds no
/// extra cyan marks.
class FocusChip extends StatelessWidget {
  const FocusChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final primary = Theme.of(context).colorScheme.primary;
    return FilterChip(
      label: Text(label),
      avatar: icon == null
          ? null
          : Icon(icon, size: 18, color: context.colors.textSecondary),
      selected: selected,
      side: BorderSide(color: selected ? primary : context.colors.divider),
      labelStyle: context.textStyles.label.copyWith(
        color: context.colors.textPrimary,
      ),
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      onSelected: onSelected,
    );
  }
}
