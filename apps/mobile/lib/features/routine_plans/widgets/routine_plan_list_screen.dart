import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../home/widgets/workout_screen.dart';
import '../../template_materialize/controllers/template_materialize_controller.dart';
import '../controllers/routine_plan_controller.dart';
import '../repositories/routine_plan_feature_repository.dart';
import 'routine_plan_editor_screen.dart';
import 'routine_start_sheet.dart';

class RoutinePlanListScreen extends ConsumerStatefulWidget {
  const RoutinePlanListScreen({super.key});

  static const routeName = '/library/training/routines';
  static const createButtonKey = Key('routinePlans.create');
  static const createNameFieldKey = Key('routinePlans.create.name');
  static const createNotesFieldKey = Key('routinePlans.create.notes');
  static const createSubmitButtonKey = Key('routinePlans.create.submit');
  static const archivedToggleKey = Key('routinePlans.archived.toggle');

  static Key routineTileKey(String id) => Key('routinePlans.tile.$id');
  static Key archiveButtonKey(String id) => Key('routinePlans.archive.$id');
  static Key restoreButtonKey(String id) => Key('routinePlans.restore.$id');
  static Key startButtonKey(String id) => Key('routinePlans.start.$id');

  @override
  ConsumerState<RoutinePlanListScreen> createState() =>
      _RoutinePlanListScreenState();
}

class _RoutinePlanListScreenState extends ConsumerState<RoutinePlanListScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final routines = ref.watch(routinePlanListControllerProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.routinePlansTitle)),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppDimens.base),
        child: FilledButton.icon(
          key: RoutinePlanListScreen.createButtonKey,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(AppDimens.rowHeight),
          ),
          onPressed: () => unawaited(_showCreateSheet()),
          icon: const Icon(Icons.add),
          label: Text(l10n.routinePlansNew),
        ),
      ),
      body: SafeArea(
        child: routines.when(
          data: (snapshot) => _RoutinePlanListBody(
            snapshot: snapshot,
            showArchived: _showArchived,
            onShowArchivedChanged: (value) {
              setState(() => _showArchived = value);
            },
            onOpen: _openRoutine,
            onArchive: _confirmArchive,
            onRestore: _restoreRoutine,
            onStart: _startRoutine,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.base),
              child: Text(
                l10n.routinePlansUnavailable,
                style: context.textStyles.body.copyWith(
                  color: context.colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openRoutine(RoutinePlanSummary routine) {
    Navigator.of(context).pushNamed(
      RoutinePlanEditorScreen.routeName,
      arguments: routine.id,
    );
  }

  Future<void> _showCreateSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _CreateRoutineSheet(
        onCreate: ({required name, notes}) async {
          try {
            final routineId = await ref
                .read(routinePlanCommandsProvider)
                .createRoutine(name: name, notes: notes);
            if (!sheetContext.mounted) {
              return;
            }
            Navigator.of(sheetContext).pop();
            if (!mounted) {
              return;
            }
            Navigator.of(context).pushNamed(
              RoutinePlanEditorScreen.routeName,
              arguments: routineId,
            );
          } on Object {
            if (sheetContext.mounted) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(
                    content: Text(sheetContext.l10n.routinePlansActionFailed)),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _confirmArchive(RoutinePlanSummary routine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.routinePlansArchiveTitle(routine.name)),
        content: Text(dialogContext.l10n.routinePlansArchiveMessage),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: dialogContext.colors.textPrimary,
              minimumSize: const Size(0, AppDimens.rowHeight),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.routinePlansCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              minimumSize: const Size(0, AppDimens.rowHeight),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.routinePlansArchive),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(routinePlanCommandsProvider).archiveRoutine(routine.id);
    } on Object {
      if (mounted) {
        _showFailure();
      }
    }
  }

  Future<void> _restoreRoutine(RoutinePlanSummary routine) async {
    try {
      await ref.read(routinePlanCommandsProvider).restoreRoutine(routine.id);
    } on Object {
      if (mounted) {
        _showFailure();
      }
    }
  }

  void _showFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.routinePlansActionFailed)),
    );
  }

  Future<void> _startRoutine(RoutinePlanSummary routine) async {
    final selectedEntry = await showRoutineStartSheet(
      context,
      routineId: routine.id,
      routineName: routine.name,
    );
    if (selectedEntry == null || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final failureMessage = context.l10n.routinePlansStartFailed;
    try {
      final workoutId = await ref.read(templateMaterializeControllerProvider).start(
            workoutTemplateId: selectedEntry.workoutTemplateId,
            routineId: selectedEntry.routineId,
            slot: selectedEntry.slot,
          );
      if (!mounted) {
        return;
      }
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutScreen(workoutId: workoutId),
        ),
      );
    } on Object {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
      }
    }
  }
}

class _RoutinePlanListBody extends StatelessWidget {
  const _RoutinePlanListBody({
    required this.snapshot,
    required this.showArchived,
    required this.onShowArchivedChanged,
    required this.onOpen,
    required this.onArchive,
    required this.onRestore,
    required this.onStart,
  });

  final RoutinePlanListSnapshot snapshot;
  final bool showArchived;
  final ValueChanged<bool> onShowArchivedChanged;
  final ValueChanged<RoutinePlanSummary> onOpen;
  final ValueChanged<RoutinePlanSummary> onArchive;
  final ValueChanged<RoutinePlanSummary> onRestore;
  final ValueChanged<RoutinePlanSummary> onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(AppDimens.base),
      children: [
        if (snapshot.active.isEmpty) ...[
          Text(
            l10n.routinePlansEmptyTitle,
            style: context.textStyles.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppDimens.dense),
          Text(
            l10n.routinePlansEmptyMessage,
            style: context.textStyles.body.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ] else ...[
          _SectionLabel(label: l10n.routinePlansActiveHeading),
          const SizedBox(height: AppDimens.dense),
          for (var index = 0; index < snapshot.active.length; index += 1) ...[
            if (index > 0) const SizedBox(height: AppDimens.dense),
            _RoutinePlanTile(
              routine: snapshot.active[index],
              onOpen: onOpen,
              onArchive: onArchive,
              onStart: onStart,
            ),
          ],
        ],
        const SizedBox(height: AppDimens.base),
        SwitchListTile(
          key: RoutinePlanListScreen.archivedToggleKey,
          contentPadding: EdgeInsets.zero,
          title: Text(
            showArchived
                ? l10n.routinePlansHideArchived
                : l10n.routinePlansShowArchived,
          ),
          value: showArchived,
          onChanged: onShowArchivedChanged,
        ),
        if (showArchived) ...[
          const SizedBox(height: AppDimens.dense),
          _SectionLabel(label: l10n.routinePlansArchivedHeading),
          const SizedBox(height: AppDimens.dense),
          if (snapshot.archived.isEmpty)
            Text(
              l10n.routinePlansArchivedEmpty,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            )
          else
            for (var index = 0;
                index < snapshot.archived.length;
                index += 1) ...[
              if (index > 0) const SizedBox(height: AppDimens.dense),
              _RoutinePlanTile(
                routine: snapshot.archived[index],
                onOpen: onOpen,
                onRestore: onRestore,
              ),
            ],
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: context.textStyles.label.copyWith(
        color: context.colors.textSecondary,
      ),
    );
  }
}

class _RoutinePlanTile extends StatelessWidget {
  const _RoutinePlanTile({
    required this.routine,
    required this.onOpen,
    this.onArchive,
    this.onRestore,
    this.onStart,
  });

  final RoutinePlanSummary routine;
  final ValueChanged<RoutinePlanSummary> onOpen;
  final ValueChanged<RoutinePlanSummary>? onArchive;
  final ValueChanged<RoutinePlanSummary>? onRestore;
  final ValueChanged<RoutinePlanSummary>? onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final summary = routine.archivedTemplateCount == 0
        ? l10n.routinePlansTemplateCount(routine.entryCount)
        : '${l10n.routinePlansTemplateCount(routine.entryCount)} · '
            '${l10n.routinePlansArchivedTemplateCount(routine.archivedTemplateCount)}';
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
      child: Semantics(
        button: !routine.isArchived,
        label: routine.isArchived
            ? l10n.routinePlansArchivedTileLabel(routine.name)
            : l10n.routinePlansOpenTooltip(routine.name),
        child: ListTile(
          key: RoutinePlanListScreen.routineTileKey(routine.id),
          minTileHeight: AppDimens.rowHeight,
          title: Text(routine.name, style: context.textStyles.h2),
          subtitle: Text(
            summary,
            style: context.textStyles.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          onTap: routine.isArchived ? null : () => onOpen(routine),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!routine.isArchived)
                IconButton(
                  key: RoutinePlanListScreen.startButtonKey(routine.id),
                  tooltip: l10n.routinePlansStartTooltip(routine.name),
                  onPressed: () => onStart?.call(routine),
                  icon: const Icon(Icons.play_arrow),
                ),
              routine.isArchived
                  ? IconButton(
                      key: RoutinePlanListScreen.restoreButtonKey(routine.id),
                      tooltip: l10n.routinePlansRestore,
                      onPressed: () => onRestore?.call(routine),
                      icon: const Icon(Icons.restore),
                    )
                  : IconButton(
                      key: RoutinePlanListScreen.archiveButtonKey(routine.id),
                      tooltip: l10n.routinePlansArchive,
                      onPressed: () => onArchive?.call(routine),
                      icon: const Icon(Icons.archive_outlined),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateRoutineSheet extends StatefulWidget {
  const _CreateRoutineSheet({required this.onCreate});

  final Future<void> Function({required String name, String? notes}) onCreate;

  @override
  State<_CreateRoutineSheet> createState() => _CreateRoutineSheetState();
}

class _CreateRoutineSheetState extends State<_CreateRoutineSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  bool _saving = false;
  bool _showNameError = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppDimens.base,
          top: AppDimens.base,
          right: AppDimens.base,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppDimens.base,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.routinePlansCreateTitle, style: context.textStyles.h2),
              const SizedBox(height: AppDimens.base),
              TextField(
                key: RoutinePlanListScreen.createNameFieldKey,
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.routinePlansNameLabel,
                  errorText:
                      _showNameError ? l10n.routinePlansNameRequired : null,
                ),
              ),
              const SizedBox(height: AppDimens.base),
              TextField(
                key: RoutinePlanListScreen.createNotesFieldKey,
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.routinePlansNotesLabel,
                ),
              ),
              const SizedBox(height: AppDimens.base),
              FilledButton.icon(
                key: RoutinePlanListScreen.createSubmitButtonKey,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.save,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  minimumSize: const Size.fromHeight(AppDimens.rowHeight),
                ),
                onPressed: _saving ? null : _submit,
                icon: const Icon(Icons.add),
                label: Text(l10n.routinePlansCreate),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    setState(() {
      _saving = true;
      _showNameError = false;
    });
    try {
      await widget.onCreate(
        name: _nameController.text,
        notes: _notesController.text,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
