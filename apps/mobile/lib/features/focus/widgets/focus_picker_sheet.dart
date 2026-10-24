import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/focus_providers.dart';
import 'focus_manager_screen.dart';
import 'focus_visuals.dart';

/// What the user chose in [showFocusPickerSheet]. A null result means the
/// sheet was dismissed without a choice.
final class FocusPick {
  const FocusPick(this.focusId);

  /// The chosen Focus, or null for "No focus".
  final String? focusId;
}

/// Picks the Focus a Workout or Workout Template is performed under.
Future<FocusPick?> showFocusPickerSheet(
  BuildContext context, {
  required String? selectedFocusId,
}) {
  return showModalBottomSheet<FocusPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) =>
        _FocusPickerSheet(selectedFocusId: selectedFocusId),
  );
}

class _FocusPickerSheet extends ConsumerWidget {
  const _FocusPickerSheet({required this.selectedFocusId});

  static Key optionKey(String? focusId) =>
      Key('focus-picker.option.${focusId ?? 'none'}');

  final String? selectedFocusId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final focuses = ref.watch(activeFocusesProvider).value ?? const [];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AppDimens.base),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.base,
                0,
                AppDimens.base,
                AppDimens.dense,
              ),
              child: Text(l10n.focusPickerTitle, style: context.textStyles.h2),
            ),
            for (final focus in focuses)
              _FocusOption(
                key: optionKey(focus.id),
                icon: focusIcon(focus.id),
                label: focus.name,
                isSelected: focus.id == selectedFocusId,
                onTap: () => Navigator.of(context).pop(FocusPick(focus.id)),
              ),
            _FocusOption(
              key: optionKey(null),
              icon: Icons.block,
              label: l10n.focusPickerNone,
              isSelected: selectedFocusId == null,
              onTap: () => Navigator.of(context).pop(const FocusPick(null)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.focusPickerEdit),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FocusManagerScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusOption extends StatelessWidget {
  const _FocusOption({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      minTileHeight: AppDimens.touchTarget + AppDimens.dense,
      leading: Icon(icon, color: isSelected ? primary : null),
      title: Text(label, style: context.textStyles.body),
      // Selection reads from the check and the semantics, not from tinting
      // the label, which would fall below AA contrast in the light theme.
      trailing: isSelected ? Icon(Icons.check, color: primary) : null,
      selected: isSelected,
      selectedColor: context.colors.textPrimary,
      onTap: onTap,
    );
  }
}
