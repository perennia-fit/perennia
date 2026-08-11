import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/training/routine_cadence.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../workout_templates/widgets/workout_template_editor_screen.dart';
import '../controllers/routine_plan_controller.dart';
import '../repositories/routine_plan_feature_repository.dart';
import 'localized_cadence_slot_label.dart';

class RoutinePlanEditorScreen extends ConsumerStatefulWidget {
  const RoutinePlanEditorScreen({
    required this.routineId,
    super.key,
  });

  static const routeName = '/library/training/routines/edit';
  static const nameFieldKey = Key('routinePlanEditor.name');
  static const notesFieldKey = Key('routinePlanEditor.notes');
  static const saveDetailsButtonKey = Key('routinePlanEditor.details.save');
  static const addTemplateButtonKey = Key('routinePlanEditor.template.add');
  static const entryListKey = Key('routinePlanEditor.entries');
  static const pickerKey = Key('routinePlanEditor.template.picker');
  static const cadenceKindKey = Key('routinePlanEditor.cadence.kind');
  static const rotatingWindowFieldKey =
      Key('routinePlanEditor.cadence.rotatingWindow');
  static const saveCadenceButtonKey = Key('routinePlanEditor.cadence.save');
  static const cadenceErrorKey = Key('routinePlanEditor.cadence.error');
  static const cadenceWarningDialogKey =
      Key('routinePlanEditor.cadence.warning');
  static const cadenceSaveAnywayKey =
      Key('routinePlanEditor.cadence.saveAnyway');

  static Key entryTileKey(String id) => Key('routinePlanEditor.entry.$id');
  static Key reorderEntryHandleKey(String id) =>
      Key('routinePlanEditor.entry.reorder.$id');
  static Key entryMenuButtonKey(String id) =>
      Key('routinePlanEditor.entry.menu.$id');
  static Key moveEntryEarlierKey(String id) =>
      Key('routinePlanEditor.entry.moveEarlier.$id');
  static Key moveEntryLaterKey(String id) =>
      Key('routinePlanEditor.entry.moveLater.$id');
  static Key removeEntryKey(String id) =>
      Key('routinePlanEditor.entry.remove.$id');
  static Key restoreTemplateKey(String id) =>
      Key('routinePlanEditor.entry.restoreTemplate.$id');
  static Key pickerTemplateKey(String id) =>
      Key('routinePlanEditor.template.pick.$id');
  static Key slotCardKey(int slot) => Key('routinePlanEditor.slot.$slot');
  static Key slotDragTargetKey(int slot) =>
      Key('routinePlanEditor.slot.drop.$slot');
  static Key slotHighlightKey(int slot) =>
      Key('routinePlanEditor.slot.highlight.$slot');
  static Key addTemplateToSlotKey(int slot) =>
      Key('routinePlanEditor.slot.add.$slot');
  static Key moveEntryToSlotKey(String id) =>
      Key('routinePlanEditor.entry.moveToSlot.$id');
  static Key moveToSlotOptionKey(int slot) =>
      Key('routinePlanEditor.moveToSlot.$slot');
  static Key dragFeedbackKey(String id) =>
      Key('routinePlanEditor.entry.dragFeedback.$id');

  final String routineId;

  @override
  ConsumerState<RoutinePlanEditorScreen> createState() =>
      _RoutinePlanEditorScreenState();
}

class _RoutinePlanEditorScreenState
    extends ConsumerState<RoutinePlanEditorScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late final TextEditingController _rotatingWindowController;
  late final ScrollController _scrollController;
  final GlobalKey _scrollViewKey = GlobalKey();
  Timer? _dragAutoScrollTimer;
  double _dragAutoScrollStep = 0;
  String? _hydratedRoutineId;
  String? _externalName;
  String? _externalNotes;
  Cadence? _externalCadence;
  CadenceKind? _cadenceKind;
  bool _nameDirty = false;
  bool _notesDirty = false;
  bool _cadenceDirty = false;
  bool _savingDetails = false;
  bool _savingCadence = false;
  bool _showNameError = false;
  bool _showCadenceError = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _notesController = TextEditingController();
    _rotatingWindowController = TextEditingController(text: '7');
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _rotatingWindowController.dispose();
    _dragAutoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routine = ref.watch(
      routinePlanDetailControllerProvider(widget.routineId),
    );
    final l10n = context.l10n;
    return routine.when(
      data: (detail) {
        if (detail == null) {
          return _UnavailableRoutineScaffold(
            title: l10n.routinePlansTitle,
          );
        }
        _hydrateFields(detail);
        return _buildEditor(detail);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.routinePlansTitle)),
        body: const SizedBox.expand(),
      ),
      error: (error, stackTrace) => _UnavailableRoutineScaffold(
        title: l10n.routinePlansTitle,
      ),
    );
  }

  void _hydrateFields(RoutinePlanDetail routine) {
    final externalNotes = routine.notes ?? '';
    final externalCadence = routine.cadence;
    if (_hydratedRoutineId != routine.id) {
      _hydratedRoutineId = routine.id;
      _externalName = routine.name;
      _externalNotes = externalNotes;
      _externalCadence = externalCadence;
      _nameDirty = false;
      _notesDirty = false;
      _cadenceDirty = false;
      _nameController.text = routine.name;
      _notesController.text = externalNotes;
      _hydrateCadenceDraft(routine.cadence);
      return;
    }

    final nameChangedExternally = _externalName != routine.name;
    final notesChangedExternally = _externalNotes != externalNotes;
    final cadenceChangedExternally =
        !_cadencesEqual(_externalCadence, externalCadence);
    _externalName = routine.name;
    _externalNotes = externalNotes;
    _externalCadence = externalCadence;
    if (!_nameDirty &&
        nameChangedExternally &&
        _nameController.text != routine.name) {
      _nameController.text = routine.name;
    }
    if (!_notesDirty &&
        notesChangedExternally &&
        _notesController.text != externalNotes) {
      _notesController.text = externalNotes;
    }
    if (!_cadenceDirty && cadenceChangedExternally) {
      _hydrateCadenceDraft(routine.cadence);
    }
  }

  void _hydrateCadenceDraft(Cadence? cadence) {
    _cadenceKind = cadence?.kind;
    if (cadence?.window != null) {
      _rotatingWindowController.text = cadence!.window.toString();
    }
    _showCadenceError = false;
  }

  Widget _buildEditor(RoutinePlanDetail routine) {
    final l10n = context.l10n;
    final enabled = !routine.isArchived;
    final entriesBySlot = routine.cadence == null
        ? const <int, List<RoutineEntryDetail>>{}
        : _groupEntriesBySlot(routine.entries);
    return Scaffold(
      appBar: AppBar(title: Text(routine.name)),
      body: SafeArea(
        child: CustomScrollView(
          key: _scrollViewKey,
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.base,
                AppDimens.base,
                AppDimens.base,
                0,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  TextField(
                    key: RoutinePlanEditorScreen.nameFieldKey,
                    controller: _nameController,
                    enabled: enabled && !_savingDetails,
                    textInputAction: TextInputAction.next,
                    onChanged: _onNameChanged,
                    decoration: InputDecoration(
                      labelText: l10n.routinePlansNameLabel,
                      errorText:
                          _showNameError ? l10n.routinePlansNameRequired : null,
                    ),
                  ),
                  const SizedBox(height: AppDimens.base),
                  TextField(
                    key: RoutinePlanEditorScreen.notesFieldKey,
                    controller: _notesController,
                    enabled: enabled && !_savingDetails,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: _onNotesChanged,
                    decoration: InputDecoration(
                      labelText: l10n.routinePlansNotesLabel,
                    ),
                  ),
                  const SizedBox(height: AppDimens.base),
                  FilledButton.icon(
                    key: RoutinePlanEditorScreen.saveDetailsButtonKey,
                    style: FilledButton.styleFrom(
                      backgroundColor: context.colors.save,
                      foregroundColor:
                          Theme.of(context).colorScheme.onSecondary,
                      minimumSize: const Size.fromHeight(AppDimens.rowHeight),
                    ),
                    onPressed: enabled && !_savingDetails ? _saveDetails : null,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.routinePlansSaveDetails),
                  ),
                  const SizedBox(height: AppDimens.base),
                  _buildCadenceSection(routine, enabled: enabled),
                  const SizedBox(height: AppDimens.base),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppDimens.dense,
                    runSpacing: AppDimens.dense,
                    children: [
                      Text(
                        l10n.routinePlansTemplatesHeading,
                        style: context.textStyles.h2,
                      ),
                      if (routine.cadence == null)
                        TextButton.icon(
                          key: RoutinePlanEditorScreen.addTemplateButtonKey,
                          style: TextButton.styleFrom(
                            foregroundColor: context.colors.textPrimary,
                            minimumSize: const Size(0, AppDimens.rowHeight),
                          ),
                          onPressed: enabled
                              ? () => unawaited(
                                    _showTemplatePicker(
                                      routine.id,
                                      slot: null,
                                    ),
                                  )
                              : null,
                          icon: const Icon(Icons.add),
                          label: Text(l10n.routinePlansAddTemplate),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppDimens.dense),
                ]),
              ),
            ),
            if (routine.cadence == null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.base,
                  0,
                  AppDimens.base,
                  AppDimens.base,
                ),
                sliver: SliverToBoxAdapter(
                  child: _buildFlatEntryLayout(routine, enabled: enabled),
                ),
              )
            else
              _buildCadenceEntrySliver(
                routine,
                entriesBySlot: entriesBySlot,
                enabled: enabled,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCadenceSection(
    RoutinePlanDetail routine, {
    required bool enabled,
  }) {
    final l10n = context.l10n;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.routinePlansCadenceHeading, style: context.textStyles.h2),
            const SizedBox(height: AppDimens.dense),
            InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.routinePlansCadenceLabel,
              ),
              child: Wrap(
                key: RoutinePlanEditorScreen.cadenceKindKey,
                spacing: AppDimens.dense,
                runSpacing: AppDimens.dense,
                children: [
                  ChoiceChip(
                    label: Text(l10n.routinePlansCadenceNone),
                    selected: _cadenceKind == null,
                    onSelected: enabled && !_savingCadence
                        ? (selected) {
                            if (selected) {
                              _selectCadenceKind(null);
                            }
                          }
                        : null,
                  ),
                  ChoiceChip(
                    label: Text(l10n.routinePlansCadenceWeekly),
                    selected: _cadenceKind == CadenceKind.weekly,
                    onSelected: enabled && !_savingCadence
                        ? (selected) {
                            if (selected) {
                              _selectCadenceKind(CadenceKind.weekly);
                            }
                          }
                        : null,
                  ),
                  ChoiceChip(
                    label: Text(l10n.routinePlansCadenceRotating),
                    selected: _cadenceKind == CadenceKind.rotating,
                    onSelected: enabled && !_savingCadence
                        ? (selected) {
                            if (selected) {
                              _selectCadenceKind(CadenceKind.rotating);
                            }
                          }
                        : null,
                  ),
                ],
              ),
            ),
            if (_cadenceKind == CadenceKind.rotating) ...[
              const SizedBox(height: AppDimens.base),
              TextField(
                key: RoutinePlanEditorScreen.rotatingWindowFieldKey,
                controller: _rotatingWindowController,
                enabled: enabled && !_savingCadence,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  _refreshCadenceDirty();
                  if (_showCadenceError) {
                    setState(() => _showCadenceError = false);
                  }
                },
                decoration: InputDecoration(
                  labelText: l10n.routinePlansRotatingWindowLabel,
                  helperText: l10n.routinePlansRotatingWindowHelp,
                  errorText: _showCadenceError
                      ? l10n.routinePlansRotatingWindowError
                      : null,
                ),
              ),
            ],
            if (_showCadenceError && _cadenceKind != CadenceKind.rotating)
              Padding(
                key: RoutinePlanEditorScreen.cadenceErrorKey,
                padding: const EdgeInsets.only(top: AppDimens.dense),
                child: Text(
                  l10n.routinePlansCadenceInvalid,
                  style: context.textStyles.body.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: AppDimens.base),
            FilledButton.icon(
              key: RoutinePlanEditorScreen.saveCadenceButtonKey,
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.save,
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
                minimumSize: const Size.fromHeight(AppDimens.rowHeight),
              ),
              onPressed: enabled && !_savingCadence
                  ? () => unawaited(_saveCadence(routine))
                  : null,
              icon: const Icon(Icons.event_repeat_outlined),
              label: Text(l10n.routinePlansSaveCadence),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlatEntryLayout(
    RoutinePlanDetail routine, {
    required bool enabled,
  }) {
    if (routine.entries.isEmpty) {
      return Text(
        context.l10n.routinePlansNoTemplates,
        style: context.textStyles.body.copyWith(
          color: context.colors.textSecondary,
        ),
        textAlign: TextAlign.center,
      );
    }
    return ReorderableListView.builder(
      key: RoutinePlanEditorScreen.entryListKey,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: routine.entries.length,
      onReorderItem: enabled
          ? (oldIndex, newIndex) => _reorderEntries(routine, oldIndex, newIndex)
          : (_, __) {},
      itemBuilder: (context, index) {
        final entry = routine.entries[index];
        return Padding(
          key: ValueKey<String>(entry.id),
          padding: EdgeInsets.only(
            bottom: index == routine.entries.length - 1 ? 0 : AppDimens.dense,
          ),
          child: _RoutineEntryTile(
            key: RoutinePlanEditorScreen.entryTileKey(entry.id),
            entry: entry,
            reorderIndex: index,
            enabled: enabled,
            canMoveEarlier: index > 0,
            canMoveLater: index < routine.entries.length - 1,
            onOpen: () => _openTemplate(entry),
            onRestore: () => unawaited(_restoreReferencedTemplate(entry)),
            onMoveEarlier: () => _moveEntry(routine, index, index - 1),
            onMoveLater: () => _moveEntry(routine, index, index + 1),
            onRemove: () => unawaited(_confirmRemoveReference(routine, entry)),
          ),
        );
      },
    );
  }

  Widget _buildCadenceEntrySliver(
    RoutinePlanDetail routine, {
    required Map<int, List<RoutineEntryDetail>> entriesBySlot,
    required bool enabled,
  }) {
    final cadence = routine.cadence!;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.base,
        0,
        AppDimens.base,
        AppDimens.base,
      ),
      sliver: SliverList(
        key: RoutinePlanEditorScreen.entryListKey,
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final slot = index + 1;
            return Padding(
              padding: EdgeInsets.only(
                bottom: slot == cadence.slotCount ? 0 : AppDimens.dense,
              ),
              child: _RoutineCadenceSlotCard(
                key: RoutinePlanEditorScreen.slotCardKey(slot),
                slot: slot,
                title: localizedCadenceSlotLabel(
                  context.l10n,
                  kind: cadence.kind,
                  slot: slot,
                ),
                entries: entriesBySlot[slot] ?? const <RoutineEntryDetail>[],
                enabled: enabled,
                onAdd: () => unawaited(
                  _showTemplatePicker(routine.id, slot: slot),
                ),
                onDrop: (entry) => _moveEntryToSlot(routine, entry, slot),
                onOpen: _openTemplate,
                onRestore: (entry) =>
                    unawaited(_restoreReferencedTemplate(entry)),
                onMoveEarlier: (entry) =>
                    _moveEntryWithinSlot(routine, entry, -1),
                onMoveLater: (entry) => _moveEntryWithinSlot(routine, entry, 1),
                onMoveToSlot: (entry) =>
                    unawaited(_showMoveToSlotSheet(routine, entry)),
                onRemove: (entry) =>
                    unawaited(_confirmRemoveReference(routine, entry)),
                onDragUpdate: _updateDragAutoScroll,
                onDragEnd: _stopDragAutoScroll,
              ),
            );
          },
          childCount: cadence.slotCount,
        ),
      ),
    );
  }

  Map<int, List<RoutineEntryDetail>> _groupEntriesBySlot(
    Iterable<RoutineEntryDetail> entries,
  ) {
    final grouped = <int, List<RoutineEntryDetail>>{};
    for (final entry in entries) {
      final slot = entry.slot;
      if (slot != null) {
        grouped.putIfAbsent(slot, () => <RoutineEntryDetail>[]).add(entry);
      }
    }
    return grouped;
  }

  void _updateDragAutoScroll(Offset globalPosition) {
    if (!_scrollController.hasClients) {
      return;
    }
    final renderBox =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return;
    }
    const edgeExtent = AppDimens.touchTarget * 2;
    const maximumStep = 14.0;
    final top = renderBox.localToGlobal(Offset.zero).dy;
    final bottom = top + renderBox.size.height;
    final distanceFromTop = globalPosition.dy - top;
    final distanceFromBottom = bottom - globalPosition.dy;
    if (distanceFromTop < edgeExtent) {
      _dragAutoScrollStep =
          -maximumStep * (1 - distanceFromTop / edgeExtent).clamp(0, 1);
    } else if (distanceFromBottom < edgeExtent) {
      _dragAutoScrollStep =
          maximumStep * (1 - distanceFromBottom / edgeExtent).clamp(0, 1);
    } else {
      _stopDragAutoScroll();
      return;
    }
    _dragAutoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tickDragAutoScroll(),
    );
  }

  void _tickDragAutoScroll() {
    if (!_scrollController.hasClients) {
      _stopDragAutoScroll();
      return;
    }
    final position = _scrollController.position;
    final target = (position.pixels + _dragAutoScrollStep)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target != position.pixels) {
      _scrollController.jumpTo(target);
    }
  }

  void _stopDragAutoScroll() {
    _dragAutoScrollTimer?.cancel();
    _dragAutoScrollTimer = null;
    _dragAutoScrollStep = 0;
  }

  void _onNameChanged(String value) {
    _nameDirty = value != _externalName;
    if (_showNameError && value.trim().isNotEmpty) {
      setState(() => _showNameError = false);
    }
  }

  void _onNotesChanged(String value) {
    _notesDirty = value != _externalNotes;
  }

  void _selectCadenceKind(CadenceKind? kind) {
    setState(() {
      _cadenceKind = kind;
      _showCadenceError = false;
      _refreshCadenceDirty();
    });
  }

  void _refreshCadenceDirty() {
    final rotatingWindow = _cadenceKind == CadenceKind.rotating
        ? int.tryParse(_rotatingWindowController.text.trim())
        : null;
    if (_cadenceKind == CadenceKind.rotating && rotatingWindow == null) {
      _cadenceDirty = true;
      return;
    }
    final draft = switch (_cadenceKind) {
      null => null,
      CadenceKind.weekly => const Cadence.weekly(),
      CadenceKind.rotating => Cadence.rotating(rotatingWindow!),
    };
    _cadenceDirty = !_cadencesEqual(draft, _externalCadence);
  }

  Future<void> _saveCadence(RoutinePlanDetail routine) async {
    final rotatingWindow = _cadenceKind == CadenceKind.rotating
        ? int.tryParse(_rotatingWindowController.text.trim())
        : null;
    if (_cadenceKind == CadenceKind.rotating && rotatingWindow == null) {
      setState(() => _showCadenceError = true);
      return;
    }
    final cadence = switch (_cadenceKind) {
      null => null,
      CadenceKind.weekly => const Cadence.weekly(),
      CadenceKind.rotating => Cadence.rotating(rotatingWindow!),
    };
    final controller = ref.read(routinePlanCommandsProvider);
    final validation = controller.validateCadence(cadence);
    if (!validation.accepted) {
      setState(() => _showCadenceError = true);
      return;
    }
    if (validation.hasWarning && !await _confirmCadenceWarning()) {
      return;
    }
    setState(() {
      _savingCadence = true;
      _showCadenceError = false;
    });
    try {
      await controller.setCadence(routineId: routine.id, cadence: cadence);
      if (mounted) {
        _externalCadence = cadence;
        _cadenceDirty = false;
      }
    } on Object {
      if (mounted) {
        _showFailure();
      }
    } finally {
      if (mounted) {
        setState(() => _savingCadence = false);
      }
    }
  }

  Future<bool> _confirmCadenceWarning() async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            key: RoutinePlanEditorScreen.cadenceWarningDialogKey,
            title: Text(dialogContext.l10n.routinePlansCadenceWarningTitle),
            content: Text(
              dialogContext.l10n.routinePlansCadenceWarningMessage,
            ),
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
                key: RoutinePlanEditorScreen.cadenceSaveAnywayKey,
                style: FilledButton.styleFrom(
                  backgroundColor: dialogContext.colors.save,
                  foregroundColor:
                      Theme.of(dialogContext).colorScheme.onSecondary,
                  minimumSize: const Size(0, AppDimens.rowHeight),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(dialogContext.l10n.routinePlansSaveAnyway),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _saveDetails() async {
    final normalizedName = _nameController.text.trim();
    final trimmedNotes = _notesController.text.trim();
    final normalizedNotes = trimmedNotes.isEmpty ? '' : trimmedNotes;
    if (normalizedName.isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    setState(() {
      _savingDetails = true;
      _showNameError = false;
    });
    try {
      await ref.read(routinePlanCommandsProvider).updateRoutine(
            routineId: widget.routineId,
            name: normalizedName,
            notes: normalizedNotes,
          );
      if (mounted) {
        _externalName = normalizedName;
        _externalNotes = normalizedNotes;
        _nameDirty = false;
        _notesDirty = false;
        _nameController.text = normalizedName;
        _notesController.text = normalizedNotes;
      }
    } on Object {
      if (mounted) {
        _showFailure();
      }
    } finally {
      if (mounted) {
        setState(() => _savingDetails = false);
      }
    }
  }

  Future<void> _showTemplatePicker(String routineId, {required int? slot}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _RoutineTemplatePickerSheet(
        onSelected: (template) async {
          await ref.read(routinePlanCommandsProvider).addTemplateReference(
                routineId: routineId,
                workoutTemplateId: template.id,
                slot: slot,
              );
        },
      ),
    );
  }

  void _openTemplate(RoutineEntryDetail entry) {
    if (entry.templateIsArchived) {
      return;
    }
    Navigator.of(context).pushNamed(
      WorkoutTemplateEditorScreen.routeName,
      arguments: entry.workoutTemplateId,
    );
  }

  void _reorderEntries(
    RoutinePlanDetail routine,
    int oldIndex,
    int newIndex,
  ) {
    final adjustedNewIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _moveEntry(routine, oldIndex, adjustedNewIndex);
  }

  void _moveEntry(
    RoutinePlanDetail routine,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex == newIndex ||
        newIndex < 0 ||
        newIndex >= routine.entries.length) {
      return;
    }
    final reordered = List<RoutineEntryDetail>.of(routine.entries);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    unawaited(
      ref
          .read(routinePlanCommandsProvider)
          .reorderTemplateReferences(
            routineId: routine.id,
            orderedEntryIds:
                reordered.map((entry) => entry.id).toList(growable: false),
          )
          .catchError((Object _) {
        if (mounted) {
          _showFailure();
        }
      }),
    );
  }

  void _moveEntryWithinSlot(
    RoutinePlanDetail routine,
    RoutineEntryDetail entry,
    int offset,
  ) {
    final cadence = routine.cadence;
    final slot = entry.slot;
    if (cadence == null || slot == null) {
      return;
    }
    final entriesBySlot = <int, List<RoutineEntryDetail>>{
      for (var index = 1; index <= cadence.slotCount; index += 1)
        index: routine.entries
            .where((candidate) => candidate.slot == index)
            .toList(growable: true),
    };
    final entries = entriesBySlot[slot]!;
    final oldIndex =
        entries.indexWhere((candidate) => candidate.id == entry.id);
    final newIndex = oldIndex + offset;
    if (oldIndex < 0 || newIndex < 0 || newIndex >= entries.length) {
      return;
    }
    entries.insert(newIndex, entries.removeAt(oldIndex));
    final placements = <RoutineEntryPlacement>[
      for (var index = 1; index <= cadence.slotCount; index += 1)
        for (final candidate in entriesBySlot[index]!)
          RoutineEntryPlacement(entryId: candidate.id, slot: index),
    ];
    unawaited(
      ref
          .read(routinePlanCommandsProvider)
          .replaceCadenceLayout(
            routineId: routine.id,
            placements: placements,
          )
          .catchError((Object _) {
        if (mounted) {
          _showFailure();
        }
      }),
    );
  }

  void _moveEntryToSlot(
    RoutinePlanDetail routine,
    RoutineEntryDetail entry,
    int slot,
  ) {
    if (routine.cadence == null || entry.slot == slot) {
      return;
    }
    unawaited(
      ref
          .read(routinePlanCommandsProvider)
          .moveTemplateReferenceToSlot(
            routineEntryId: entry.id,
            slot: slot,
          )
          .catchError((Object _) {
        if (mounted) {
          _showFailure();
        }
      }),
    );
  }

  Future<void> _showMoveToSlotSheet(
    RoutinePlanDetail routine,
    RoutineEntryDetail entry,
  ) {
    final cadence = routine.cadence!;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimens.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimens.base),
                child: Text(
                  sheetContext.l10n.routinePlansMoveToSlotTitle(
                    entry.templateName,
                  ),
                  style: sheetContext.textStyles.h2,
                ),
              ),
              const SizedBox(height: AppDimens.dense),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: cadence.slotCount,
                  itemBuilder: (context, index) {
                    final slot = index + 1;
                    final selected = slot == entry.slot;
                    return ListTile(
                      key: RoutinePlanEditorScreen.moveToSlotOptionKey(slot),
                      minTileHeight: AppDimens.rowHeight,
                      leading: Icon(
                        selected
                            ? Icons.check_circle_outline
                            : Icons.event_note_outlined,
                      ),
                      title: Text(
                        localizedCadenceSlotLabel(
                          context.l10n,
                          kind: cadence.kind,
                          slot: slot,
                        ),
                      ),
                      subtitle: selected
                          ? Text(context.l10n.routinePlansCurrentSlot)
                          : null,
                      enabled: !selected,
                      onTap: selected
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop();
                              _moveEntryToSlot(routine, entry, slot);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _restoreReferencedTemplate(RoutineEntryDetail entry) async {
    try {
      await ref
          .read(routinePlanCommandsProvider)
          .restoreReferencedTemplate(entry.workoutTemplateId);
    } on Object {
      if (mounted) {
        _showFailure();
      }
    }
  }

  Future<void> _confirmRemoveReference(
    RoutinePlanDetail routine,
    RoutineEntryDetail entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.l10n.routinePlansRemoveReferenceTitle(
            entry.templateName,
          ),
        ),
        content: Text(
          dialogContext.l10n.routinePlansRemoveReferenceMessage(routine.name),
        ),
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
            child: Text(dialogContext.l10n.routinePlansRemoveReference),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref
          .read(routinePlanCommandsProvider)
          .removeTemplateReference(entry.id);
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
}

bool _cadencesEqual(Cadence? left, Cadence? right) {
  return identical(left, right) ||
      (left?.kind == right?.kind && left?.window == right?.window);
}

enum _RoutineEntryMenuAction {
  moveEarlier,
  moveLater,
  moveToSlot,
  remove,
}

class _RoutineCadenceSlotCard extends StatelessWidget {
  const _RoutineCadenceSlotCard({
    required this.slot,
    required this.title,
    required this.entries,
    required this.enabled,
    required this.onAdd,
    required this.onDrop,
    required this.onOpen,
    required this.onRestore,
    required this.onMoveEarlier,
    required this.onMoveLater,
    required this.onMoveToSlot,
    required this.onRemove,
    required this.onDragUpdate,
    required this.onDragEnd,
    super.key,
  });

  final int slot;
  final String title;
  final List<RoutineEntryDetail> entries;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<RoutineEntryDetail> onDrop;
  final ValueChanged<RoutineEntryDetail> onOpen;
  final ValueChanged<RoutineEntryDetail> onRestore;
  final ValueChanged<RoutineEntryDetail> onMoveEarlier;
  final ValueChanged<RoutineEntryDetail> onMoveLater;
  final ValueChanged<RoutineEntryDetail> onMoveToSlot;
  final ValueChanged<RoutineEntryDetail> onRemove;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return DragTarget<RoutineEntryDetail>(
      key: RoutinePlanEditorScreen.slotDragTargetKey(slot),
      onWillAcceptWithDetails: (details) =>
          enabled && details.data.slot != slot,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return AnimatedContainer(
          key: RoutinePlanEditorScreen.slotHighlightKey(slot),
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: AppRadii.cardMd,
            border: Border.all(
              color: highlighted
                  ? Theme.of(context).colorScheme.primary
                  : context.colors.divider,
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: context.colors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadii.cardMd,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.dense),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: context.textStyles.h2),
                      ),
                      IconButton(
                        key: RoutinePlanEditorScreen.addTemplateToSlotKey(slot),
                        tooltip: context.l10n.routinePlansAddTemplateToSlot(
                          title,
                        ),
                        onPressed: enabled ? onAdd : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  if (highlighted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppDimens.dense),
                      child: Text(
                        context.l10n.routinePlansDropHere,
                        style: context.textStyles.body.copyWith(
                          color: context.colors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else if (entries.isEmpty)
                    Semantics(
                      label: context.l10n.routinePlansRestSlotLabel(title),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppDimens.base,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bedtime_outlined,
                              color: context.colors.textSecondary,
                            ),
                            const SizedBox(width: AppDimens.dense),
                            Text(
                              context.l10n.routinePlansRest,
                              style: context.textStyles.body.copyWith(
                                color: context.colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    for (var index = 0; index < entries.length; index += 1) ...[
                      _CadenceRoutineEntryTile(
                        key: RoutinePlanEditorScreen.entryTileKey(
                          entries[index].id,
                        ),
                        entry: entries[index],
                        enabled: enabled,
                        canMoveEarlier: index > 0,
                        canMoveLater: index < entries.length - 1,
                        onOpen: () => onOpen(entries[index]),
                        onRestore: () => onRestore(entries[index]),
                        onMoveEarlier: () => onMoveEarlier(entries[index]),
                        onMoveLater: () => onMoveLater(entries[index]),
                        onMoveToSlot: () => onMoveToSlot(entries[index]),
                        onRemove: () => onRemove(entries[index]),
                        onDragUpdate: onDragUpdate,
                        onDragEnd: onDragEnd,
                      ),
                      if (index != entries.length - 1)
                        const SizedBox(height: AppDimens.dense),
                    ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CadenceRoutineEntryTile extends StatelessWidget {
  const _CadenceRoutineEntryTile({
    required this.entry,
    required this.enabled,
    required this.canMoveEarlier,
    required this.canMoveLater,
    required this.onOpen,
    required this.onRestore,
    required this.onMoveEarlier,
    required this.onMoveLater,
    required this.onMoveToSlot,
    required this.onRemove,
    required this.onDragUpdate,
    required this.onDragEnd,
    super.key,
  });

  final RoutineEntryDetail entry;
  final bool enabled;
  final bool canMoveEarlier;
  final bool canMoveLater;
  final VoidCallback onOpen;
  final VoidCallback onRestore;
  final VoidCallback onMoveEarlier;
  final VoidCallback onMoveLater;
  final VoidCallback onMoveToSlot;
  final VoidCallback onRemove;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadii.cardMd,
        border: Border.all(color: context.colors.divider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(
          left: AppDimens.dense,
          right: AppDimens.dense,
        ),
        minTileHeight: AppDimens.rowHeight,
        leading: Semantics(
          button: true,
          enabled: enabled,
          label: l10n.routinePlansReorderTemplate(entry.templateName),
          onTap: enabled ? onMoveToSlot : null,
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? onMoveToSlot : null,
              child: Draggable<RoutineEntryDetail>(
                key: RoutinePlanEditorScreen.reorderEntryHandleKey(entry.id),
                data: entry,
                maxSimultaneousDrags: enabled ? 1 : 0,
                onDragUpdate: (details) => onDragUpdate(details.globalPosition),
                onDragEnd: (_) => onDragEnd(),
                feedback: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    key: RoutinePlanEditorScreen.dragFeedbackKey(entry.id),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: AppRadii.cardMd,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: SizedBox.square(
                      dimension: AppDimens.touchTarget,
                      child: Icon(
                        Icons.drag_handle,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
                childWhenDragging: const SizedBox.square(
                  dimension: AppDimens.touchTarget,
                  child: Icon(Icons.drag_handle, color: Colors.transparent),
                ),
                child: const SizedBox.square(
                  dimension: AppDimens.touchTarget,
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ),
          ),
        ),
        title: Text(entry.templateName, style: context.textStyles.h2),
        subtitle: _RoutineEntrySubtitle(entry: entry),
        onTap: enabled && !entry.templateIsArchived ? onOpen : null,
        trailing: _RoutineEntryActions(
          entry: entry,
          enabled: enabled,
          canMoveEarlier: canMoveEarlier,
          canMoveLater: canMoveLater,
          onRestore: onRestore,
          onMoveEarlier: onMoveEarlier,
          onMoveLater: onMoveLater,
          onMoveToSlot: onMoveToSlot,
          onRemove: onRemove,
        ),
      ),
    );
  }
}

class _UnavailableRoutineScaffold extends StatelessWidget {
  const _UnavailableRoutineScaffold({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: Text(
            context.l10n.routinePlansUnavailable,
            style: context.textStyles.body.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _RoutineEntryTile extends StatelessWidget {
  const _RoutineEntryTile({
    required this.entry,
    required this.reorderIndex,
    required this.enabled,
    required this.canMoveEarlier,
    required this.canMoveLater,
    required this.onOpen,
    required this.onRestore,
    required this.onMoveEarlier,
    required this.onMoveLater,
    required this.onRemove,
    super.key,
  });

  final RoutineEntryDetail entry;
  final int reorderIndex;
  final bool enabled;
  final bool canMoveEarlier;
  final bool canMoveLater;
  final VoidCallback onOpen;
  final VoidCallback onRestore;
  final VoidCallback onMoveEarlier;
  final VoidCallback onMoveLater;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardMd),
      child: ListTile(
        contentPadding: const EdgeInsets.only(
          left: AppDimens.dense,
          right: AppDimens.dense,
        ),
        minTileHeight: AppDimens.rowHeight,
        leading: Semantics(
          button: true,
          label: l10n.routinePlansReorderTemplate(entry.templateName),
          child: ReorderableDragStartListener(
            key: RoutinePlanEditorScreen.reorderEntryHandleKey(entry.id),
            index: reorderIndex,
            enabled: enabled,
            child: const SizedBox.square(
              dimension: AppDimens.touchTarget,
              child: Icon(Icons.drag_handle),
            ),
          ),
        ),
        title: Text(entry.templateName, style: context.textStyles.h2),
        subtitle: _RoutineEntrySubtitle(entry: entry),
        onTap: enabled && !entry.templateIsArchived ? onOpen : null,
        trailing: _RoutineEntryActions(
          entry: entry,
          enabled: enabled,
          canMoveEarlier: canMoveEarlier,
          canMoveLater: canMoveLater,
          onRestore: onRestore,
          onMoveEarlier: onMoveEarlier,
          onMoveLater: onMoveLater,
          onRemove: onRemove,
        ),
      ),
    );
  }
}

class _RoutineEntryActions extends StatelessWidget {
  const _RoutineEntryActions({
    required this.entry,
    required this.enabled,
    required this.canMoveEarlier,
    required this.canMoveLater,
    required this.onRestore,
    required this.onMoveEarlier,
    required this.onMoveLater,
    required this.onRemove,
    this.onMoveToSlot,
  });

  final RoutineEntryDetail entry;
  final bool enabled;
  final bool canMoveEarlier;
  final bool canMoveLater;
  final VoidCallback onRestore;
  final VoidCallback onMoveEarlier;
  final VoidCallback onMoveLater;
  final VoidCallback? onMoveToSlot;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (entry.templateIsArchived)
          IconButton(
            key: RoutinePlanEditorScreen.restoreTemplateKey(entry.id),
            tooltip: l10n.routinePlansRestoreTemplate,
            onPressed: enabled ? onRestore : null,
            icon: const Icon(Icons.restore),
          ),
        PopupMenuButton<_RoutineEntryMenuAction>(
          key: RoutinePlanEditorScreen.entryMenuButtonKey(entry.id),
          enabled: enabled,
          tooltip: l10n.routinePlansEntryActions(entry.templateName),
          onSelected: (action) {
            switch (action) {
              case _RoutineEntryMenuAction.moveEarlier:
                onMoveEarlier();
              case _RoutineEntryMenuAction.moveLater:
                onMoveLater();
              case _RoutineEntryMenuAction.moveToSlot:
                onMoveToSlot?.call();
              case _RoutineEntryMenuAction.remove:
                onRemove();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              key: RoutinePlanEditorScreen.moveEntryEarlierKey(entry.id),
              value: _RoutineEntryMenuAction.moveEarlier,
              enabled: canMoveEarlier,
              child: Text(l10n.routinePlansMoveEarlier),
            ),
            PopupMenuItem(
              key: RoutinePlanEditorScreen.moveEntryLaterKey(entry.id),
              value: _RoutineEntryMenuAction.moveLater,
              enabled: canMoveLater,
              child: Text(l10n.routinePlansMoveLater),
            ),
            if (onMoveToSlot != null)
              PopupMenuItem(
                key: RoutinePlanEditorScreen.moveEntryToSlotKey(entry.id),
                value: _RoutineEntryMenuAction.moveToSlot,
                child: Text(l10n.routinePlansMoveToSlot),
              ),
            PopupMenuItem(
              key: RoutinePlanEditorScreen.removeEntryKey(entry.id),
              value: _RoutineEntryMenuAction.remove,
              child: Text(
                l10n.routinePlansRemoveReference,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoutineEntrySubtitle extends StatelessWidget {
  const _RoutineEntrySubtitle({required this.entry});

  final RoutineEntryDetail entry;

  @override
  Widget build(BuildContext context) {
    final secondaryStyle = context.textStyles.body.copyWith(
      color: context.colors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.templateIsArchived)
          Row(
            children: [
              const Icon(Icons.archive_outlined, size: 18),
              const SizedBox(width: AppDimens.dense),
              Expanded(
                child: Text(
                  context.l10n.routinePlansArchivedTemplateLabel,
                  style: secondaryStyle,
                ),
              ),
            ],
          )
        else
          Text(context.l10n.routinePlansTemplateLabel, style: secondaryStyle),
        if (entry.templateNotes != null)
          Text(
            entry.templateNotes!,
            style: secondaryStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _RoutineTemplatePickerSheet extends ConsumerStatefulWidget {
  const _RoutineTemplatePickerSheet({required this.onSelected});

  final Future<void> Function(RoutineWorkoutTemplateOption template) onSelected;

  @override
  ConsumerState<_RoutineTemplatePickerSheet> createState() =>
      _RoutineTemplatePickerSheetState();
}

class _RoutineTemplatePickerSheetState
    extends ConsumerState<_RoutineTemplatePickerSheet> {
  String? _selectingId;

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(routinePlanTemplateOptionsProvider);
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: AppDimens.base),
        child: SizedBox(
          key: RoutinePlanEditorScreen.pickerKey,
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.base,
                ),
                child: Text(
                  l10n.routinePlansTemplatePickerTitle,
                  style: context.textStyles.h2,
                ),
              ),
              const SizedBox(height: AppDimens.dense),
              Expanded(
                child: templates.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppDimens.base),
                          child: Text(
                            l10n.routinePlansNoAvailableTemplates,
                            style: context.textStyles.body.copyWith(
                              color: context.colors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.base,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final template = items[index];
                        return ListTile(
                          key: RoutinePlanEditorScreen.pickerTemplateKey(
                            template.id,
                          ),
                          minTileHeight: AppDimens.rowHeight,
                          leading: const Icon(Icons.fitness_center_outlined),
                          title: Text(template.name),
                          subtitle: Text(
                            l10n.workoutTemplatesExerciseCount(
                              template.exerciseCount,
                            ),
                          ),
                          enabled: _selectingId == null,
                          onTap: () => unawaited(_select(template)),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, stackTrace) => Center(
                    child: Text(l10n.routinePlansUnavailable),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _select(RoutineWorkoutTemplateOption template) async {
    setState(() => _selectingId = template.id);
    try {
      await widget.onSelected(template);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object {
      if (mounted) {
        setState(() => _selectingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.routinePlansActionFailed)),
        );
      }
    }
  }
}
