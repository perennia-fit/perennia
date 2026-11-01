import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/focus_color.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../../widgets/color_swatch_row.dart';
import '../controllers/focus_providers.dart';
import '../repositories/focus_feature_repository.dart';
import 'focus_visuals.dart';

/// Add, rename, recolor, reorder (press and hold), and archive Focuses. The order here
/// is the order the start sheet and every picker offer them in.
class FocusManagerScreen extends ConsumerWidget {
  const FocusManagerScreen({super.key});

  static const addButtonKey = Key('focus-manager.add');
  static const nameFieldKey = Key('focus-manager.name');
  static const saveNameButtonKey = Key('focus-manager.save');

  static Key rowKey(String id) => Key('focus-manager.row.$id');
  static Key menuButtonKey(String id) => Key('focus-manager.menu.$id');
  static Key renameMenuKey(String id) => Key('focus-manager.rename.$id');
  static Key colorMenuKey(String id) => Key('focus-manager.color.$id');
  static Key colorSwatchKey(String token) => Key('focus-color.$token');
  static const colorCancelButtonKey = Key('focus-color.cancel');
  static Key archiveMenuKey(String id) => Key('focus-manager.archive.$id');
  static const archiveConfirmButtonKey = Key('focus-manager.archive.confirm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final focuses = ref.watch(activeFocusesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.focusManagerTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: addButtonKey,
        onPressed: () => unawaited(_add(context, ref)),
        icon: const Icon(Icons.add),
        label: Text(l10n.focusManagerAdd),
      ),
      body: SafeArea(
        child: focuses.when(
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppDimens.base),
                  child: Text(
                    l10n.focusManagerEmpty,
                    style: context.textStyles.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                )
              : _FocusList(focuses: list),
          loading: () => const SizedBox.expand(),
          error: (_, __) => const SizedBox.expand(),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(focusFeatureRepositoryProvider);
    await _promptForName(
      context,
      title: context.l10n.focusManagerAdd,
      initialName: '',
      save: repository.create,
    );
  }
}

class _FocusList extends ConsumerWidget {
  const _FocusList({required this.focuses});

  final List<FocusRecord> focuses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(
        top: AppDimens.dense,
        // Room for the extended FAB over the last row.
        bottom: AppDimens.touchTarget * 2,
      ),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.base,
          0,
          AppDimens.base,
          AppDimens.dense,
        ),
        child: Text(
          context.l10n.focusManagerReorderHint,
          style: context.textStyles.caption.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
      buildDefaultDragHandles: false,
      itemCount: focuses.length,
      onReorderItem: (oldIndex, newIndex) {
        final ordered = focuses.map((focus) => focus.id).toList();
        ordered.insert(newIndex, ordered.removeAt(oldIndex));
        unawaited(ref.read(focusFeatureRepositoryProvider).reorder(ordered));
      },
      itemBuilder: (context, index) {
        final focus = focuses[index];
        return ReorderableDelayedDragStartListener(
          key: FocusManagerScreen.rowKey(focus.id),
          index: index,
          child: ListTile(
            minTileHeight: AppDimens.touchTarget + AppDimens.dense,
            leading: Icon(focusIcon(focus.id)),
            title: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: resolvedFocusColor(focus, context.colors),
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox.square(dimension: 12),
                ),
                const SizedBox(width: AppDimens.dense),
                Expanded(
                  child: Text(focus.name, style: context.textStyles.body),
                ),
              ],
            ),
            trailing: _FocusMenu(focus: focus),
          ),
        );
      },
    );
  }
}

enum _FocusAction { rename, color, archive }

class _FocusMenu extends ConsumerWidget {
  const _FocusMenu({required this.focus});

  final FocusRecord focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return PopupMenuButton<_FocusAction>(
      key: FocusManagerScreen.menuButtonKey(focus.id),
      onSelected: (action) {
        switch (action) {
          case _FocusAction.rename:
            unawaited(
              _promptForName(
                context,
                title: l10n.focusManagerRename,
                initialName: focus.name,
                save: (name) => ref
                    .read(focusFeatureRepositoryProvider)
                    .rename(focus.id, name),
              ),
            );
          case _FocusAction.color:
            unawaited(_chooseColor(context, ref));
          case _FocusAction.archive:
            unawaited(_confirmArchive(context, ref));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_FocusAction>(
          key: FocusManagerScreen.renameMenuKey(focus.id),
          value: _FocusAction.rename,
          child: Text(l10n.focusManagerRename),
        ),
        PopupMenuItem<_FocusAction>(
          key: FocusManagerScreen.colorMenuKey(focus.id),
          value: _FocusAction.color,
          child: Text(l10n.focusColorMenu),
        ),
        PopupMenuItem<_FocusAction>(
          key: FocusManagerScreen.archiveMenuKey(focus.id),
          value: _FocusAction.archive,
          child: Text(l10n.focusManagerArchive),
        ),
      ],
    );
  }

  /// The Focus color dialog (docs/designs/progress-overview.md, D6): the
  /// seven category colors a Focus may take, the current one selected. There
  /// is no "Default" choice; picking the default's swatch stores its hex,
  /// which looks the same.
  Future<void> _chooseColor(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final defaultHex = colorToHex(
      context.colors.categoryColor(focusDefaultColorToken(focus.id)),
    );
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.focusColorDialogTitle(focus.name)),
        content: ColorSwatchRow(
          options: [
            for (final token in focusColorTokens)
              ColorSwatchOption(
                hex: colorToHex(dialogContext.colors.categoryColor(token)),
                label: _focusColorLabel(l10n, token),
                key: FocusManagerScreen.colorSwatchKey(token),
              ),
          ],
          selectedHex: focus.colorHex ?? defaultHex,
          onSelected: (hex) => Navigator.of(dialogContext).pop(hex),
        ),
        actions: [
          TextButton(
            key: FocusManagerScreen.colorCancelButtonKey,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
        ],
      ),
    );
    if (chosen != null) {
      await ref.read(focusFeatureRepositoryProvider).recolor(focus.id, chosen);
    }
  }

  Future<void> _confirmArchive(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.focusManagerArchiveTitle(focus.name)),
        content: Text(l10n.focusManagerArchiveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            key: FocusManagerScreen.archiveConfirmButtonKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.focusManagerArchive),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(focusFeatureRepositoryProvider).archive(focus.id);
    }
  }
}

String _focusColorLabel(AppLocalizations l10n, String token) {
  return switch (token) {
    'back' => l10n.focusColorBack,
    'cardio' => l10n.focusColorCardio,
    'core' => l10n.focusColorCore,
    'shoulders' => l10n.focusColorShoulders,
    'arms' => l10n.focusColorArms,
    'legs' => l10n.focusColorLegs,
    'chest' => l10n.focusColorChest,
    _ => token,
  };
}

/// Asks for a Focus name and saves it, keeping the dialog open with the
/// reason when the name is empty or already taken.
Future<void> _promptForName(
  BuildContext context, {
  required String title,
  required String initialName,
  required Future<Object?> Function(String name) save,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _FocusNameDialog(
      title: title,
      initialName: initialName,
      save: save,
    ),
  );
}

class _FocusNameDialog extends StatefulWidget {
  const _FocusNameDialog({
    required this.title,
    required this.initialName,
    required this.save,
  });

  final String title;
  final String initialName;
  final Future<Object?> Function(String name) save;

  @override
  State<_FocusNameDialog> createState() => _FocusNameDialogState();
}

class _FocusNameDialogState extends State<_FocusNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  String? _errorText;
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = l10n.focusManagerEmptyName);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.save(name);
    } on DuplicateFocusNameException {
      _showError(l10n.focusManagerDuplicateName);
      return;
    } on Object {
      // Any other failure keeps the dialog usable, with the reason shown,
      // instead of leaving Save disabled.
      _showError(l10n.focusManagerSaveFailed);
      return;
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() {
        _isSaving = false;
        _errorText = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: FocusManagerScreen.nameFieldKey,
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: l10n.focusManagerNameLabel,
          errorText: _errorText,
        ),
        onSubmitted: (_) => unawaited(_submit()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: FocusManagerScreen.saveNameButtonKey,
          onPressed: _isSaving ? null : () => unawaited(_submit()),
          child: Text(l10n.focusManagerSave),
        ),
      ],
    );
  }
}
