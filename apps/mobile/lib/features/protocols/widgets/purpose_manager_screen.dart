import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/protocols_day_controller.dart';
import 'protocols_lock_screen.dart';

/// Add, rename, reorder (press and hold) and archive Purposes. The order here is
/// the order the Compound list's and the picker's filter rows offer them in.
/// Modelled on `FocusManagerScreen`, without color
/// (docs/designs/compound-purposes.md, D7).
///
/// Push it inside `ProtocolsLockGate`. The dialogs sit in
/// [ProtocolsLockSheetGuard], because the gate swaps only its own route and a
/// dialog above it would keep a Purpose name on screen after a re-lock.
///
/// No string here puts a Purpose's name next to a verb, so the archive dialog's
/// title is the name alone and its question is in the body. Purpose names can
/// read as a claim about a Compound, which the neutral-instrument rule forbids.
class PurposeManagerScreen extends ConsumerWidget {
  const PurposeManagerScreen({super.key});

  static const addButtonKey = Key('purpose-manager.add');
  static const nameFieldKey = Key('purpose-manager.name');
  static const saveNameButtonKey = Key('purpose-manager.save');
  static const archiveConfirmButtonKey = Key('purpose-manager.archive.confirm');

  static Key rowKey(String id) => Key('purpose-manager.row.$id');
  static Key menuButtonKey(String id) => Key('purpose-manager.menu.$id');
  static Key renameMenuKey(String id) => Key('purpose-manager.rename.$id');
  static Key archiveMenuKey(String id) => Key('purpose-manager.archive.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = context.l10n;
    final purposes = ref.watch(activePurposesProvider);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.chrome,
        title: Text(l10n.purposeManagerTitle),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: addButtonKey,
        onPressed: () => unawaited(_add(context, ref)),
        icon: const Icon(Icons.add),
        label: Text(l10n.purposeManagerAdd),
      ),
      body: SafeArea(
        child: purposes.when(
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppDimens.base),
                  child: Text(
                    l10n.purposeManagerEmpty,
                    style: context.textStyles.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                )
              : _PurposeList(purposes: list),
          loading: () => const SizedBox.expand(),
          error: (_, __) => const SizedBox.expand(),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) {
    final controller = ref.read(protocolDayControllerProvider.notifier);
    return _promptForName(
      context,
      title: context.l10n.purposeManagerAdd,
      initialName: '',
      save: controller.createPurpose,
    );
  }
}

class _PurposeList extends ConsumerWidget {
  const _PurposeList({required this.purposes});

  final List<PurposeRecord> purposes;

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
          context.l10n.purposeManagerReorderHint,
          style: context.textStyles.caption.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
      buildDefaultDragHandles: false,
      itemCount: purposes.length,
      onReorderItem: (oldIndex, newIndex) {
        final ordered = purposes.map((purpose) => purpose.id).toList();
        ordered.insert(newIndex, ordered.removeAt(oldIndex));
        unawaited(
          ref
              .read(protocolDayControllerProvider.notifier)
              .reorderPurposes(ordered),
        );
      },
      itemBuilder: (context, index) {
        final purpose = purposes[index];
        return ReorderableDelayedDragStartListener(
          key: PurposeManagerScreen.rowKey(purpose.id),
          index: index,
          child: ListTile(
            minTileHeight: AppDimens.touchTarget + AppDimens.dense,
            title: Text(
              purpose.name,
              style: context.textStyles.body.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            trailing: _PurposeMenu(purpose: purpose),
          ),
        );
      },
    );
  }
}

enum _PurposeAction { rename, archive }

class _PurposeMenu extends ConsumerWidget {
  const _PurposeMenu({required this.purpose});

  final PurposeRecord purpose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return PopupMenuButton<_PurposeAction>(
      key: PurposeManagerScreen.menuButtonKey(purpose.id),
      tooltip: l10n.purposeManagerRowMenuTooltip,
      onSelected: (action) {
        // Read before the dialog: a sync can drop this row while it is open,
        // and a disposed widget's ref can no longer be read.
        final controller = ref.read(protocolDayControllerProvider.notifier);
        switch (action) {
          case _PurposeAction.rename:
            unawaited(
              _promptForName(
                context,
                title: l10n.purposeManagerRename,
                initialName: purpose.name,
                save: (name) => controller.renamePurpose(purpose.id, name),
              ),
            );
          case _PurposeAction.archive:
            unawaited(_confirmArchive(context, controller));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_PurposeAction>(
          key: PurposeManagerScreen.renameMenuKey(purpose.id),
          value: _PurposeAction.rename,
          child: Text(l10n.purposeManagerRename),
        ),
        PopupMenuItem<_PurposeAction>(
          key: PurposeManagerScreen.archiveMenuKey(purpose.id),
          value: _PurposeAction.archive,
          child: Text(l10n.purposeManagerArchive),
        ),
      ],
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    ProtocolDayController controller,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ProtocolsLockSheetGuard(
        child: AlertDialog(
          title: Text(purpose.name),
          content: Text(l10n.purposeManagerArchiveBody),
          actions: [
            TextButton(
              // DESIGN.md: text buttons use the primary text color. The theme's
              // cyan fails AA on the light dialog's surface.
              style: TextButton.styleFrom(
                foregroundColor: dialogContext.colors.textPrimary,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              key: PurposeManagerScreen.archiveConfirmButtonKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.purposeManagerArchive),
            ),
          ],
        ),
      ),
    );
    if (confirmed ?? false) {
      await controller.archivePurpose(purpose.id);
    }
  }
}

/// Asks for a Purpose name and saves it, keeping the dialog open with the reason
/// when the name is empty or already taken.
Future<void> _promptForName(
  BuildContext context, {
  required String title,
  required String initialName,
  required Future<Object?> Function(String name) save,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => ProtocolsLockSheetGuard(
      child: _PurposeNameDialog(
        title: title,
        initialName: initialName,
        save: save,
      ),
    ),
  );
}

class _PurposeNameDialog extends StatefulWidget {
  const _PurposeNameDialog({
    required this.title,
    required this.initialName,
    required this.save,
  });

  final String title;
  final String initialName;
  final Future<Object?> Function(String name) save;

  @override
  State<_PurposeNameDialog> createState() => _PurposeNameDialogState();
}

class _PurposeNameDialogState extends State<_PurposeNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  String? _errorText;
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The repository's `validatePurposeName` is the one check, the same module
  /// the Agent API runs, so both refusals arrive here as its codes.
  Future<void> _submit() async {
    final l10n = context.l10n;
    setState(() => _isSaving = true);
    try {
      await widget.save(_controller.text);
    } on PurposeNameException catch (error) {
      _showError(
        error.code == purposeNameRequiredCode
            ? l10n.purposeManagerNameRequired
            : l10n.purposeManagerDuplicateName,
      );
      return;
    } on Object {
      // Any other failure keeps the dialog usable, with the reason shown,
      // instead of leaving Save disabled.
      _showError(l10n.purposeManagerSaveFailed);
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
        key: PurposeManagerScreen.nameFieldKey,
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: l10n.purposeManagerNameLabel,
          errorText: _errorText,
        ),
        onChanged: (_) {
          if (_errorText != null) {
            setState(() => _errorText = null);
          }
        },
        onSubmitted: (_) => unawaited(_submit()),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: context.colors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          key: PurposeManagerScreen.saveNameButtonKey,
          onPressed: _isSaving ? null : () => unawaited(_submit()),
          child: Text(l10n.purposeManagerSave),
        ),
      ],
    );
  }
}
