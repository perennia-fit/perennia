import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/training/routine_cadence.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../routine_plans/widgets/localized_cadence_slot_label.dart';
import '../controllers/workout_capture_controller.dart';
import '../repositories/workout_capture_feature_repository.dart';
import 'workout_capture_form_style.dart';

class WorkoutCapturePlacementFields extends StatelessWidget {
  const WorkoutCapturePlacementFields({
    required this.routines,
    required this.routinesLoading,
    required this.state,
    required this.enabled,
    required this.onRoutineSelected,
    required this.onSlotSelected,
    required this.routineFieldKey,
    required this.slotFieldKey,
    super.key,
  });

  static const routinePickerKey = Key('workoutCapture.routinePicker');
  static const slotPickerKey = Key('workoutCapture.slotPicker');
  static const slotPickerListKey = Key('workoutCapture.slotPicker.list');
  static const slotNumberFieldKey = Key('workoutCapture.slotPicker.number');
  static const slotApplyButtonKey = Key('workoutCapture.slotPicker.apply');

  static Key routineOptionKey(String id) =>
      Key('workoutCapture.routinePicker.$id');
  static Key slotOptionKey(int slot) =>
      Key('workoutCapture.slotPicker.option.$slot');

  final List<WorkoutCaptureRoutineOption> routines;
  final bool routinesLoading;
  final WorkoutCaptureFormState state;
  final bool enabled;
  final ValueChanged<WorkoutCaptureRoutineOption?> onRoutineSelected;
  final ValueChanged<int> onSlotSelected;
  final Key routineFieldKey;
  final Key slotFieldKey;

  @override
  Widget build(BuildContext context) {
    final selectedRoutine = state.selectedRoutine;
    final routineError = switch (state.placementNotice) {
      WorkoutCapturePlacementNotice.routineUnavailable =>
        context.l10n.workoutCaptureRoutineUnavailable,
      WorkoutCapturePlacementNotice.cadenceChanged
          when selectedRoutine?.requiresSlot != true =>
        context.l10n.workoutCaptureCadenceChanged,
      WorkoutCapturePlacementNotice.cadenceChanged => null,
      null => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppDimens.base),
        WorkoutCaptureFieldLabel(
          label: context.l10n.workoutCaptureRoutineLabel,
        ),
        _PickerField(
          key: routineFieldKey,
          semanticLabel: context.l10n.workoutCaptureRoutineLabel,
          value: routinesLoading
              ? context.l10n.workoutCaptureRoutinesLoading
              : _routineValueLabel(context, selectedRoutine),
          helperText: context.l10n.workoutCaptureRoutineHelp,
          errorText: routineError,
          enabled: enabled && !routinesLoading,
          loading: routinesLoading,
          onTap: () async {
            final choice = await _showRoutinePicker(
              context,
              routines: routines,
              selectedId: selectedRoutine?.id,
            );
            if (choice != null) {
              onRoutineSelected(choice.routine);
            }
          },
        ),
        if (selectedRoutine?.requiresSlot ?? false) ...[
          const SizedBox(height: AppDimens.base),
          WorkoutCaptureFieldLabel(
            label: context.l10n.workoutCaptureSlotLabel,
          ),
          _PickerField(
            key: slotFieldKey,
            semanticLabel: context.l10n.workoutCaptureSlotLabel,
            value: state.selectedSlot == null
                ? context.l10n.workoutCaptureChooseSlot
                : localizedCadenceSlotLabel(
                    context.l10n,
                    kind: selectedRoutine!.cadenceKind!,
                    slot: state.selectedSlot!,
                  ),
            errorText: state.showSlotError
                ? state.placementNotice ==
                        WorkoutCapturePlacementNotice.cadenceChanged
                    ? context.l10n.workoutCaptureCadenceChanged
                    : context.l10n.workoutCaptureSlotRequired
                : null,
            enabled: enabled &&
                state.placementNotice !=
                    WorkoutCapturePlacementNotice.routineUnavailable,
            onTap: () async {
              final slot = await _showCadenceSlotPicker(
                context,
                cadenceKind: selectedRoutine!.cadenceKind!,
                slotCount: selectedRoutine.slotCount,
                selectedSlot: state.selectedSlot,
              );
              if (slot != null) {
                onSlotSelected(slot);
              }
            },
          ),
        ],
      ],
    );
  }

  String _routineValueLabel(
    BuildContext context,
    WorkoutCaptureRoutineOption? routine,
  ) {
    if (routine == null) {
      return context.l10n.workoutCaptureRoutineNone;
    }
    return routine.requiresSlot
        ? context.l10n.workoutCaptureCadenceRoutineOption(routine.name)
        : context.l10n.workoutCaptureCollectionRoutineOption(routine.name);
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.value,
    required this.semanticLabel,
    required this.enabled,
    required this.onTap,
    this.helperText,
    this.errorText,
    this.loading = false,
    super.key,
  });

  final String value;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onTap;
  final String? helperText;
  final String? errorText;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: enabled,
      child: InkWell(
        borderRadius: AppRadii.cardMd,
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          decoration: workoutCaptureInputDecoration(
            context,
            helperText: helperText,
            errorText: errorText,
            suffixIcon: Icon(
              loading ? Icons.hourglass_empty : Icons.arrow_drop_down,
              color: context.colors.textSecondary,
            ),
          ),
          isEmpty: value.isEmpty,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDimens.rowHeight),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.body.copyWith(
                  color: enabled
                      ? context.colors.textPrimary
                      : context.colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<_RoutineChoice?> _showRoutinePicker(
  BuildContext context, {
  required List<WorkoutCaptureRoutineOption> routines,
  required String? selectedId,
}) {
  return showModalBottomSheet<_RoutineChoice>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => SizedBox(
      key: WorkoutCapturePlacementFields.routinePickerKey,
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Material(
        color: context.colors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PickerHeader(title: context.l10n.workoutCaptureRoutinePickerTitle),
            Expanded(
              child: ListView.builder(
                itemCount: routines.length + 1,
                itemBuilder: (context, index) {
                  final routine = index == 0 ? null : routines[index - 1];
                  final id = routine?.id ?? 'none';
                  final selected = routine?.id == selectedId ||
                      (routine == null && selectedId == null);
                  final label = routine == null
                      ? context.l10n.workoutCaptureRoutineNone
                      : routine.requiresSlot
                          ? context.l10n
                              .workoutCaptureCadenceRoutineOption(routine.name)
                          : context.l10n.workoutCaptureCollectionRoutineOption(
                              routine.name,
                            );
                  return ListTile(
                    key: WorkoutCapturePlacementFields.routineOptionKey(id),
                    minTileHeight: AppDimens.touchTarget,
                    title: Text(
                      label,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: selected ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(context).pop(
                      _RoutineChoice(routine),
                    ),
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

Future<int?> _showCadenceSlotPicker(
  BuildContext context, {
  required CadenceKind cadenceKind,
  required int slotCount,
  required int? selectedSlot,
}) {
  return showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _CadenceSlotPicker(
      cadenceKind: cadenceKind,
      slotCount: slotCount,
      selectedSlot: selectedSlot,
    ),
  );
}

class _CadenceSlotPicker extends StatefulWidget {
  const _CadenceSlotPicker({
    required this.cadenceKind,
    required this.slotCount,
    required this.selectedSlot,
  });

  final CadenceKind cadenceKind;
  final int slotCount;
  final int? selectedSlot;

  @override
  State<_CadenceSlotPicker> createState() => _CadenceSlotPickerState();
}

class _CadenceSlotPickerState extends State<_CadenceSlotPicker> {
  late final TextEditingController _numberController;
  bool _showNumberError = false;

  @override
  void initState() {
    super.initState();
    _numberController = TextEditingController(
      text: widget.selectedSlot?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        key: WorkoutCapturePlacementFields.slotPickerKey,
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Material(
          color: context.colors.background,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: _PickerHeader(
                  title: context.l10n.workoutCaptureSlotPickerTitle,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.base,
                    0,
                    AppDimens.base,
                    AppDimens.dense,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WorkoutCaptureFieldLabel(
                        label: context.l10n.workoutCaptureSlotNumberLabel,
                      ),
                      Semantics(
                        label: context.l10n.workoutCaptureSlotNumberLabel,
                        textField: true,
                        child: TextField(
                          key: WorkoutCapturePlacementFields.slotNumberFieldKey,
                          controller: _numberController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) {
                            if (_showNumberError) {
                              setState(() => _showNumberError = false);
                            }
                          },
                          onSubmitted: (_) => _applyNumber(),
                          decoration: workoutCaptureInputDecoration(
                            context,
                            helperText: context.l10n
                                .workoutCaptureSlotRange(widget.slotCount),
                            errorText: _showNumberError
                                ? context.l10n.workoutCaptureSlotOutOfRange
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimens.dense),
                      FilledButton(
                        key: WorkoutCapturePlacementFields.slotApplyButtonKey,
                        style: workoutCaptureSaveButtonStyle(context),
                        onPressed: _applyNumber,
                        child:
                            Text(context.l10n.workoutCaptureChooseSlotAction),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Divider(color: context.colors.divider),
              ),
              SliverList.builder(
                key: WorkoutCapturePlacementFields.slotPickerListKey,
                itemCount: widget.slotCount,
                itemBuilder: (context, index) {
                  final slot = index + 1;
                  return ListTile(
                    key: WorkoutCapturePlacementFields.slotOptionKey(slot),
                    minTileHeight: AppDimens.touchTarget,
                    title: Text(
                      localizedCadenceSlotLabel(
                        context.l10n,
                        kind: widget.cadenceKind,
                        slot: slot,
                      ),
                    ),
                    trailing: widget.selectedSlot == slot
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(context).pop(slot),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyNumber() {
    final slot = int.tryParse(_numberController.text);
    if (slot == null || slot < 1 || slot > widget.slotCount) {
      setState(() => _showNumberError = true);
      return;
    }
    Navigator.of(context).pop(slot);
  }
}

class _PickerHeader extends StatelessWidget {
  const _PickerHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppDimens.base),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.h1,
            ),
          ),
          IconButton(
            tooltip: context.l10n.workoutCapturePickerClose,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

final class _RoutineChoice {
  const _RoutineChoice(this.routine);

  final WorkoutCaptureRoutineOption? routine;
}
