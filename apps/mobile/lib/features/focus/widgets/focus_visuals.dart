import 'package:flutter/material.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';

/// Icons for the starter Focuses, keyed by their seeded ids. A Focus the user
/// created, or a starter they renamed into something else, keeps a neutral
/// icon: the icon is a recognition aid next to the name, never the signal.
const _starterFocusIcons = <String, IconData>{
  '01910000-0000-7000-8000-000000000401': Icons.fitness_center,
  '01910000-0000-7000-8000-000000000402': Icons.directions_run,
  '01910000-0000-7000-8000-000000000403': Icons.bolt_outlined,
  '01910000-0000-7000-8000-000000000404': Icons.sports_gymnastics,
  '01910000-0000-7000-8000-000000000405': Icons.self_improvement,
};

IconData focusIcon(String focusId) {
  return _starterFocusIcons[focusId] ?? Icons.flag_outlined;
}

/// The name a Workout or Template shows for its Focus: the Focus's name,
/// marked when it has since been archived so history still reads honestly.
String focusDisplayName(BuildContext context, FocusRecord focus) {
  return focus.isArchived
      ? context.l10n.focusArchivedName(focus.name)
      : focus.name;
}

/// A Focus as a selectable chip, wherever Focuses are chosen. Selection is
/// translucent Signal Cyan with a cyan edge, as DESIGN.md sets selection; the
/// theme's secondary (Rested Teal) is reserved for Save. The icon stays
/// neutral so a chip row adds no extra cyan marks.
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
      selectedColor: primary.withValues(alpha: 0.22),
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
