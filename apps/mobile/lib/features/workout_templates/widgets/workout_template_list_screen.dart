import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../home/widgets/workout_screen.dart';
import '../../template_materialize/controllers/template_materialize_controller.dart';
import '../controllers/workout_template_controller.dart';
import '../repositories/workout_template_feature_repository.dart';
import 'workout_template_editor_screen.dart';

class WorkoutTemplateListScreen extends ConsumerStatefulWidget {
  const WorkoutTemplateListScreen({super.key});

  static const routeName = '/library/training/workout-templates';
  static const createButtonKey = Key('workoutTemplates.create');
  static const createNameFieldKey = Key('workoutTemplates.create.name');
  static const createNotesFieldKey = Key('workoutTemplates.create.notes');
  static const createSubmitButtonKey = Key('workoutTemplates.create.submit');
  static const archivedToggleKey = Key('workoutTemplates.archived.toggle');

  static Key templateTileKey(String id) => Key('workoutTemplates.tile.$id');
  static Key archiveButtonKey(String id) => Key('workoutTemplates.archive.$id');
  static Key restoreButtonKey(String id) => Key('workoutTemplates.restore.$id');
  static Key startButtonKey(String id) => Key('workoutTemplates.start.$id');

  @override
  ConsumerState<WorkoutTemplateListScreen> createState() =>
      _WorkoutTemplateListScreenState();
}

class _WorkoutTemplateListScreenState
    extends ConsumerState<WorkoutTemplateListScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(workoutTemplateListControllerProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.workoutTemplatesTitle)),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppDimens.base),
        child: FilledButton.icon(
          key: WorkoutTemplateListScreen.createButtonKey,
          onPressed: () => unawaited(_showCreateSheet(context)),
          icon: const Icon(Icons.add),
          label: Text(l10n.workoutTemplatesNew),
        ),
      ),
      body: SafeArea(
        child: templates.when(
          data: (snapshot) => _TemplateListBody(
            snapshot: snapshot,
            showArchived: _showArchived,
            onShowArchivedChanged: (value) {
              setState(() => _showArchived = value);
            },
            onOpen: _openTemplate,
            onArchive: _confirmArchive,
            onRestore: _restoreTemplate,
            onStart: _startTemplate,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.base),
              child: Text(
                l10n.workoutTemplateUnavailable,
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

  void _openTemplate(WorkoutTemplateSummary template) {
    Navigator.of(context).pushNamed(
      WorkoutTemplateEditorScreen.routeName,
      arguments: template.id,
    );
  }

  Future<void> _showCreateSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _CreateTemplateSheet(
        onCreate: ({required name, notes}) async {
          try {
            final templateId = await ref
                .read(workoutTemplateListControllerProvider.notifier)
                .createTemplate(name: name, notes: notes);
            if (!sheetContext.mounted) {
              return;
            }
            Navigator.of(sheetContext).pop();
            if (!mounted) {
              return;
            }
            Navigator.of(this.context).pushNamed(
              WorkoutTemplateEditorScreen.routeName,
              arguments: templateId,
            );
          } on Object {
            if (sheetContext.mounted) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(
                    content:
                        Text(sheetContext.l10n.workoutTemplatesActionFailed)),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _confirmArchive(WorkoutTemplateSummary template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.workoutTemplatesArchiveTitle),
        content: Text(dialogContext.l10n.workoutTemplatesArchiveMessage),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: dialogContext.colors.textPrimary,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.workoutTemplatesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.workoutTemplatesArchive),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref
          .read(workoutTemplateListControllerProvider.notifier)
          .archiveTemplate(template.id);
    } on Object {
      if (mounted) {
        _showFailure();
      }
    }
  }

  Future<void> _restoreTemplate(WorkoutTemplateSummary template) async {
    try {
      await ref
          .read(workoutTemplateListControllerProvider.notifier)
          .restoreTemplate(template.id);
    } on Object {
      if (mounted) {
        _showFailure();
      }
    }
  }

  void _showFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.workoutTemplatesActionFailed)),
    );
  }

  Future<void> _startTemplate(WorkoutTemplateSummary template) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final failureMessage = context.l10n.workoutTemplatesStartFailed;
    try {
      final workoutId = await ref
          .read(templateMaterializeControllerProvider)
          .start(workoutTemplateId: template.id);
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

class _TemplateListBody extends StatelessWidget {
  const _TemplateListBody({
    required this.snapshot,
    required this.showArchived,
    required this.onShowArchivedChanged,
    required this.onOpen,
    required this.onArchive,
    required this.onRestore,
    required this.onStart,
  });

  final WorkoutTemplateListSnapshot snapshot;
  final bool showArchived;
  final ValueChanged<bool> onShowArchivedChanged;
  final ValueChanged<WorkoutTemplateSummary> onOpen;
  final ValueChanged<WorkoutTemplateSummary> onArchive;
  final ValueChanged<WorkoutTemplateSummary> onRestore;
  final ValueChanged<WorkoutTemplateSummary> onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(AppDimens.base),
      children: [
        if (snapshot.active.isEmpty) ...[
          Text(
            l10n.workoutTemplatesEmptyTitle,
            style: context.textStyles.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppDimens.dense),
          Text(
            l10n.workoutTemplatesEmptyMessage,
            style: context.textStyles.body.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ] else ...[
          _SectionLabel(label: l10n.workoutTemplatesActiveHeading),
          const SizedBox(height: AppDimens.dense),
          for (var index = 0; index < snapshot.active.length; index += 1) ...[
            if (index > 0) const SizedBox(height: AppDimens.dense),
            _WorkoutTemplateTile(
              template: snapshot.active[index],
              onOpen: onOpen,
              onArchive: onArchive,
              onStart: onStart,
            ),
          ],
        ],
        const SizedBox(height: AppDimens.base),
        SwitchListTile(
          key: WorkoutTemplateListScreen.archivedToggleKey,
          contentPadding: EdgeInsets.zero,
          title: Text(
            showArchived
                ? l10n.workoutTemplatesHideArchived
                : l10n.workoutTemplatesShowArchived,
          ),
          value: showArchived,
          onChanged: onShowArchivedChanged,
        ),
        if (showArchived) ...[
          const SizedBox(height: AppDimens.dense),
          _SectionLabel(label: l10n.workoutTemplatesArchivedHeading),
          const SizedBox(height: AppDimens.dense),
          if (snapshot.archived.isEmpty)
            Text(
              l10n.workoutTemplatesArchivedEmpty,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            )
          else
            for (var index = 0;
                index < snapshot.archived.length;
                index += 1) ...[
              if (index > 0) const SizedBox(height: AppDimens.dense),
              _WorkoutTemplateTile(
                template: snapshot.archived[index],
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

class _WorkoutTemplateTile extends StatelessWidget {
  const _WorkoutTemplateTile({
    required this.template,
    required this.onOpen,
    this.onArchive,
    this.onRestore,
    this.onStart,
  });

  final WorkoutTemplateSummary template;
  final ValueChanged<WorkoutTemplateSummary> onOpen;
  final ValueChanged<WorkoutTemplateSummary>? onArchive;
  final ValueChanged<WorkoutTemplateSummary>? onRestore;
  final ValueChanged<WorkoutTemplateSummary>? onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadii.cardMd,
      ),
      child: Semantics(
        button: !template.isArchived,
        label: template.isArchived
            ? template.name
            : l10n.workoutTemplatesOpenTooltip(template.name),
        child: ListTile(
          key: WorkoutTemplateListScreen.templateTileKey(template.id),
          minTileHeight: AppDimens.rowHeight,
          title: Text(template.name, style: context.textStyles.h2),
          subtitle: Text(
            l10n.workoutTemplatesExerciseCount(template.exerciseCount),
            style: context.textStyles.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          onTap: template.isArchived ? null : () => onOpen(template),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!template.isArchived)
                IconButton(
                  key: WorkoutTemplateListScreen.startButtonKey(template.id),
                  tooltip: l10n.workoutTemplatesStartTooltip(template.name),
                  onPressed: () => onStart?.call(template),
                  icon: const Icon(Icons.play_arrow),
                ),
              template.isArchived
                  ? IconButton(
                      key: WorkoutTemplateListScreen.restoreButtonKey(
                        template.id,
                      ),
                      tooltip: l10n.workoutTemplatesRestore,
                      onPressed: () => onRestore?.call(template),
                      icon: const Icon(Icons.restore),
                    )
                  : IconButton(
                      key: WorkoutTemplateListScreen.archiveButtonKey(
                        template.id,
                      ),
                      tooltip: l10n.workoutTemplatesArchive,
                      onPressed: () => onArchive?.call(template),
                      icon: const Icon(Icons.archive_outlined),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateTemplateSheet extends StatefulWidget {
  const _CreateTemplateSheet({required this.onCreate});

  final Future<void> Function({required String name, String? notes}) onCreate;

  @override
  State<_CreateTemplateSheet> createState() => _CreateTemplateSheetState();
}

class _CreateTemplateSheetState extends State<_CreateTemplateSheet> {
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
              Text(l10n.workoutTemplatesCreateTitle,
                  style: context.textStyles.h2),
              const SizedBox(height: AppDimens.base),
              TextField(
                key: WorkoutTemplateListScreen.createNameFieldKey,
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.workoutTemplatesNameLabel,
                  errorText:
                      _showNameError ? l10n.workoutTemplatesNameLabel : null,
                ),
              ),
              const SizedBox(height: AppDimens.base),
              TextField(
                key: WorkoutTemplateListScreen.createNotesFieldKey,
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.workoutTemplatesNotesLabel,
                ),
              ),
              const SizedBox(height: AppDimens.base),
              FilledButton.icon(
                key: WorkoutTemplateListScreen.createSubmitButtonKey,
                onPressed: _saving ? null : _submit,
                icon: const Icon(Icons.add),
                label: Text(l10n.workoutTemplatesCreate),
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
    await widget.onCreate(
      name: _nameController.text,
      notes: _notesController.text,
    );
    if (mounted) {
      setState(() => _saving = false);
    }
  }
}
