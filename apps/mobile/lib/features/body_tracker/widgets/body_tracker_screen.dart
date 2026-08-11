import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../controllers/body_tracker_controller.dart';
import '../controllers/measurement_delta.dart';
import '../models/measurement_progress_graph.dart';

class BodyTrackerScreen extends ConsumerWidget {
  const BodyTrackerScreen({super.key});

  static const routeName = '/body-tracker';
  static const valueFieldKey = Key('bodyTracker.value');
  static const measuredAtFieldKey = Key('bodyTracker.measuredAt');
  static const commentFieldKey = Key('bodyTracker.comment');
  static const saveEntryButtonKey = Key('bodyTracker.saveEntry');
  static const suspiciousValueDialogKey =
      Key('bodyTracker.suspiciousValueDialog');
  static const suspiciousValueConfirmButtonKey =
      Key('bodyTracker.suspiciousValueConfirm');
  static const suspiciousValueCancelButtonKey =
      Key('bodyTracker.suspiciousValueCancel');
  static const deltaBadgeKey = Key('bodyTracker.deltaBadge');
  static const historyButtonKey = Key('bodyTracker.history');
  static const historyFilterKey = Key('bodyTracker.historyFilter');
  static const progressButtonKey = Key('bodyTracker.progress');
  static const progressTargetLineKey = Key('bodyTracker.progress.targetLine');
  static const manageButtonKey = Key('bodyTracker.manage');
  static const addMeasurementButtonKey = Key('bodyTracker.addMeasurement');
  static const resetMeasurementsButtonKey =
      Key('bodyTracker.resetMeasurements');
  static const measurementNameFieldKey = Key('bodyTracker.measurementName');
  static const measurementUnitFieldKey = Key('bodyTracker.measurementUnit');
  static const measurementGoalFieldKey = Key('bodyTracker.measurementGoal');
  static const measurementTargetValueFieldKey =
      Key('bodyTracker.measurementTargetValue');
  static const measurementEnabledFieldKey =
      Key('bodyTracker.measurementEnabled');
  static const saveMeasurementButtonKey = Key('bodyTracker.saveMeasurement');

  static Key historyEntryTileKey(String entryId) =>
      Key('bodyTracker.historyEntry.$entryId');

  static Key historyEntryDeleteButtonKey(String entryId) =>
      Key('bodyTracker.historyEntry.delete.$entryId');

  static Key measurementEnabledSwitchKey(String measurementId) =>
      Key('bodyTracker.measurement.enabled.$measurementId');

  static Key measurementDeleteButtonKey(String measurementId) =>
      Key('bodyTracker.measurement.delete.$measurementId');

  static Key measurementReorderHandleKey(String measurementId) =>
      Key('bodyTracker.measurement.reorder.$measurementId');

  static Key progressGraphKey(String measurementId) =>
      Key('bodyTracker.progress.graph.$measurementId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bodyTrackerControllerProvider);

    return state.when(
      data: (bodyTracker) => _BodyTrackerContent(state: bodyTracker),
      loading: () => Scaffold(
        appBar: AppBar(title: Text(context.l10n.bodyTrackerTitle)),
        body: const SizedBox.expand(),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.bodyTrackerTitle)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              context.l10n.bodyTrackerUnavailable,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BodyTrackerContent extends StatelessWidget {
  const _BodyTrackerContent({
    required this.state,
  });

  final BodyTrackerState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.bodyTrackerTitle),
        actions: [
          IconButton(
            key: BodyTrackerScreen.manageButtonKey,
            tooltip: context.l10n.bodyTrackerManageTooltip,
            onPressed: () => _openManagement(context),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            key: BodyTrackerScreen.historyButtonKey,
            tooltip: context.l10n.bodyTrackerHistoryTooltip,
            onPressed: () => _openHistory(context),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(AppDimens.base),
          itemCount: state.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppDimens.dense),
          itemBuilder: (context, index) {
            final item = state.items[index];
            return _MeasurementTile(item: item);
          },
        ),
      ),
    );
  }

  void _openHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _MeasurementHistoryScreen(),
      ),
    );
  }

  void _openManagement(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _MeasurementManagementScreen(),
      ),
    );
  }
}

class _MeasurementTile extends StatelessWidget {
  const _MeasurementTile({
    required this.item,
  });

  final MeasurementTrackItem item;

  @override
  Widget build(BuildContext context) {
    final summary = item.summary;
    final latestEntry = summary.latestEntry;
    final unitLabel = _unitLabel(context.l10n, summary.measurement.unit);
    final latestValue = latestEntry == null
        ? null
        : context.l10n.bodyTrackerValueWithUnit(
            latestEntry.valueEntered,
            unitLabel,
          );
    final delta = item.delta;
    final deltaValue = delta == null
        ? null
        : context.l10n.bodyTrackerValueWithUnit(
            delta.valueEntered,
            unitLabel,
          );
    final subtitle = latestEntry == null
        ? context.l10n.bodyTrackerNoValueYet
        : context.l10n.bodyTrackerLatestRecency(
            _recencyLabel(context.l10n, latestEntry.measuredAt),
          );

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        minVerticalPadding: AppDimens.dense,
        title: Text(summary.measurement.name),
        subtitle: Text(subtitle),
        trailing: latestValue == null
            ? null
            : _MeasurementTrailing(
                latestValue: latestValue,
                delta: delta,
                deltaValue: deltaValue,
              ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _MeasurementEntryScreen(
                measurement: summary.measurement,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MeasurementTrailing extends StatelessWidget {
  const _MeasurementTrailing({
    required this.latestValue,
    required this.delta,
    required this.deltaValue,
  });

  final String latestValue;
  final MeasurementDelta? delta;
  final String? deltaValue;

  @override
  Widget build(BuildContext context) {
    final delta = this.delta;
    final deltaValue = this.deltaValue;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          latestValue,
          style: context.textStyles.numeralRow,
        ),
        if (delta != null && deltaValue != null) ...[
          const SizedBox(height: AppDimens.dense / 3),
          _MeasurementDeltaBadge(
            delta: delta,
            label: deltaValue,
          ),
        ],
      ],
    );
  }
}

class _MeasurementDeltaBadge extends StatelessWidget {
  const _MeasurementDeltaBadge({
    required this.delta,
    required this.label,
  });

  final MeasurementDelta delta;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = switch (delta.direction) {
      MeasurementDeltaDirection.good => context.colors.save,
      MeasurementDeltaDirection.bad => colorScheme.error,
      MeasurementDeltaDirection.neutral => context.colors.divider,
    };
    final foreground = switch (delta.direction) {
      MeasurementDeltaDirection.good => DesignTokens.onSave,
      MeasurementDeltaDirection.bad => colorScheme.onError,
      MeasurementDeltaDirection.neutral => context.colors.textPrimary,
    };
    final icon = switch (delta.direction) {
      MeasurementDeltaDirection.good => Icons.check,
      MeasurementDeltaDirection.bad => Icons.priority_high,
      MeasurementDeltaDirection.neutral => Icons.remove,
    };

    return DecoratedBox(
      key: BodyTrackerScreen.deltaBadgeKey,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.chipFull,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.dense / 2,
          vertical: AppDimens.dense / 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: AppDimens.dense / 3),
            Text(
              label,
              style: context.textStyles.caption.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeasurementEntryScreen extends ConsumerStatefulWidget {
  const _MeasurementEntryScreen({
    required this.measurement,
    this.entry,
  });

  final MeasurementRecord measurement;
  final MeasurementEntryRecord? entry;

  @override
  ConsumerState<_MeasurementEntryScreen> createState() =>
      _MeasurementEntryScreenState();
}

class _MeasurementEntryScreenState
    extends ConsumerState<_MeasurementEntryScreen> {
  late final TextEditingController _valueController;
  late final TextEditingController _measuredAtController;
  late final TextEditingController _commentController;
  String? _valueError;
  String? _measuredAtError;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _valueController = TextEditingController(text: entry?.valueEntered);
    _measuredAtController = TextEditingController(
      text: _formatEditableDateTime(entry?.measuredAt ?? DateTime.now()),
    );
    _commentController = TextEditingController(text: entry?.comment);
  }

  @override
  void dispose() {
    _valueController.dispose();
    _measuredAtController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.measurement.name),
        actions: [
          IconButton(
            key: BodyTrackerScreen.progressButtonKey,
            tooltip: l10n.bodyTrackerProgressTooltip,
            onPressed: () => _openProgress(context, widget.measurement),
            icon: const Icon(Icons.show_chart),
          ),
          IconButton(
            key: BodyTrackerScreen.historyButtonKey,
            tooltip: l10n.bodyTrackerHistoryTooltip,
            onPressed: () => _openHistory(context),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.base),
          children: [
            TextField(
              key: BodyTrackerScreen.valueFieldKey,
              controller: _valueController,
              decoration: InputDecoration(
                labelText: l10n.bodyTrackerValueLabel,
                suffixText: _unitLabel(l10n, widget.measurement.unit),
                errorText: _valueError,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: AppDimens.base),
            TextField(
              key: BodyTrackerScreen.measuredAtFieldKey,
              controller: _measuredAtController,
              decoration: InputDecoration(
                labelText: l10n.bodyTrackerMeasuredAtLabel,
                errorText: _measuredAtError,
              ),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: AppDimens.base),
            TextField(
              key: BodyTrackerScreen.commentFieldKey,
              controller: _commentController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.bodyTrackerCommentLabel,
              ),
            ),
            const SizedBox(height: AppDimens.base),
            FilledButton.icon(
              key: BodyTrackerScreen.saveEntryButtonKey,
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(
                widget.entry == null
                    ? l10n.bodyTrackerSaveEntry
                    : l10n.bodyTrackerUpdateEntry,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final measuredAt = _parseEditableDateTime(_measuredAtController.text);
    setState(() {
      _valueError = null;
      _measuredAtError =
          measuredAt == null ? l10n.bodyTrackerInvalidDateTime : null;
    });
    if (measuredAt == null) {
      return;
    }

    try {
      final validation =
          await ref.read(bodyTrackerControllerProvider.notifier).validateEntry(
                measurementId: widget.measurement.id,
                valueEntered: _valueController.text,
                measuredAt: measuredAt,
                comment: _commentController.text,
              );
      if (validation.hasWarnings) {
        if (!mounted) {
          return;
        }
        final confirmed = await _confirmWarnings(l10n, validation.warnings);
        if (!confirmed) {
          return;
        }
      }

      final controller = ref.read(bodyTrackerControllerProvider.notifier);
      final entry = widget.entry;
      if (entry == null) {
        await controller.saveEntry(
          measurementId: widget.measurement.id,
          valueEntered: _valueController.text,
          measuredAt: measuredAt,
          comment: _commentController.text,
        );
      } else {
        await controller.updateEntry(
          entryId: entry.id,
          measurementId: widget.measurement.id,
          valueEntered: _valueController.text,
          measuredAt: measuredAt,
          comment: _commentController.text,
        );
      }
    } on MeasurementValueException {
      setState(() {
        _valueError = l10n.bodyTrackerInvalidValue;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          widget.entry == null
              ? l10n.bodyTrackerEntrySaved
              : l10n.bodyTrackerEntryUpdated,
        ),
      ),
    );
  }

  void _openHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MeasurementHistoryScreen(
          initialMeasurementId: widget.measurement.id,
        ),
      ),
    );
  }

  void _openProgress(BuildContext context, MeasurementRecord measurement) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MeasurementProgressScreen(measurement: measurement),
      ),
    );
  }

  Future<bool> _confirmWarnings(
    AppLocalizations l10n,
    List<MeasurementValidationWarning> warnings,
  ) async {
    final warning = warnings.first;
    final message = switch (warning.code) {
      MeasurementValidationWarningCode.suspiciouslyHigh =>
        l10n.bodyTrackerSuspiciousValueMessage(
          _valueController.text.trim(),
          _unitLabel(l10n, widget.measurement.unit),
        ),
    };

    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              key: BodyTrackerScreen.suspiciousValueDialogKey,
              title: Text(l10n.bodyTrackerSuspiciousValueTitle),
              content: Text(message),
              actions: [
                TextButton(
                  key: BodyTrackerScreen.suspiciousValueCancelButtonKey,
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.bodyTrackerSuspiciousValueCancel),
                ),
                FilledButton(
                  key: BodyTrackerScreen.suspiciousValueConfirmButtonKey,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.bodyTrackerSuspiciousValueConfirm),
                ),
              ],
            );
          },
        ) ??
        false;
  }
}

class _MeasurementManagementScreen extends ConsumerWidget {
  const _MeasurementManagementScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bodyTrackerManagementProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.bodyTrackerManageTitle),
        actions: [
          IconButton(
            key: BodyTrackerScreen.resetMeasurementsButtonKey,
            tooltip: context.l10n.bodyTrackerResetMeasurementsTooltip,
            onPressed: () => _confirmReset(context, ref),
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: SafeArea(
        child: state.when(
          data: (state) => _MeasurementManagementList(state: state),
          loading: () => const SizedBox.expand(),
          error: (error, stackTrace) => Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              context.l10n.bodyTrackerUnavailable,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.bodyTrackerResetMeasurementsTitle),
            content: Text(l10n.bodyTrackerResetMeasurementsMessage),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.bodyTrackerCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.bodyTrackerReset),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }

    await ref
        .read(bodyTrackerControllerProvider.notifier)
        .resetDefaultMeasurements();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.bodyTrackerMeasurementReset)),
    );
  }
}

class _MeasurementManagementList extends ConsumerWidget {
  const _MeasurementManagementList({
    required this.state,
  });

  final BodyTrackerManagementState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(AppDimens.base),
      header: Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.base),
        child: FilledButton.icon(
          key: BodyTrackerScreen.addMeasurementButtonKey,
          onPressed: () => _openCreateMeasurement(context),
          icon: const Icon(Icons.add),
          label: Text(context.l10n.bodyTrackerAddMeasurement),
        ),
      ),
      itemCount: state.measurements.length,
      onReorderItem: (oldIndex, newIndex) {
        final ids = state.measurements
            .map((measurement) => measurement.id)
            .toList(growable: true);
        final moved = ids.removeAt(oldIndex);
        ids.insert(newIndex, moved);
        ref.read(bodyTrackerControllerProvider.notifier).reorderMeasurements(
              ids,
            );
      },
      itemBuilder: (context, index) {
        final measurement = state.measurements[index];
        return _MeasurementManagementTile(
          key: ValueKey<String>(measurement.id),
          measurement: measurement,
          index: index,
        );
      },
    );
  }

  void _openCreateMeasurement(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _MeasurementFormScreen(),
      ),
    );
  }
}

class _MeasurementManagementTile extends ConsumerWidget {
  const _MeasurementManagementTile({
    super.key,
    required this.measurement,
    required this.index,
  });

  final MeasurementRecord measurement;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final targetValue = measurement.targetValue;
    final subtitleParts = <String>[
      _unitLabel(l10n, measurement.unit),
      _goalLabel(l10n, measurement.goalType),
      if (targetValue != null)
        '${l10n.bodyTrackerMeasurementTargetLabel}: '
            '${_formatMeasurementNumber(targetValue)}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: AppDimens.dense),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              button: true,
              label: l10n.bodyTrackerReorderMeasurementTooltip,
              child: SizedBox(
                key: BodyTrackerScreen.measurementReorderHandleKey(
                  measurement.id,
                ),
                width: AppDimens.touchTarget,
                height: AppDimens.touchTarget,
                child: Icon(
                  Icons.drag_handle,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            child: SwitchListTile(
              key: BodyTrackerScreen.measurementEnabledSwitchKey(
                measurement.id,
              ),
              contentPadding: EdgeInsets.zero,
              title: Text(measurement.name),
              subtitle: Text(subtitleParts.join(' - ')),
              value: measurement.enabled,
              onChanged: (enabled) {
                ref
                    .read(bodyTrackerControllerProvider.notifier)
                    .setMeasurementEnabled(measurement.id, enabled);
              },
            ),
          ),
          IconButton(
            key: BodyTrackerScreen.measurementDeleteButtonKey(measurement.id),
            tooltip: l10n.bodyTrackerDeleteMeasurementTooltip,
            onPressed: () => _confirmDelete(context, ref),
            icon: const Icon(Icons.archive_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.bodyTrackerDeleteMeasurementTitle),
            content: Text(l10n.bodyTrackerDeleteMeasurementMessage),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.bodyTrackerCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.bodyTrackerArchive),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }

    await ref
        .read(bodyTrackerControllerProvider.notifier)
        .deleteMeasurement(measurement.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.bodyTrackerMeasurementDeleted)),
    );
  }
}

class _MeasurementFormScreen extends ConsumerStatefulWidget {
  const _MeasurementFormScreen();

  @override
  ConsumerState<_MeasurementFormScreen> createState() =>
      _MeasurementFormScreenState();
}

class _MeasurementFormScreenState
    extends ConsumerState<_MeasurementFormScreen> {
  final _nameController = TextEditingController();
  final _targetValueController = TextEditingController();
  MeasurementUnit _unit = MeasurementUnit.centimeter;
  MeasurementGoalType _goalType = MeasurementGoalType.decrease;
  bool _enabled = true;
  String? _nameError;
  String? _targetValueError;

  @override
  void dispose() {
    _nameController.dispose();
    _targetValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.bodyTrackerCreateMeasurementTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.base),
          children: [
            TextField(
              key: BodyTrackerScreen.measurementNameFieldKey,
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.bodyTrackerMeasurementNameLabel,
                errorText: _nameError,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppDimens.base),
            DropdownButtonFormField<MeasurementUnit>(
              key: BodyTrackerScreen.measurementUnitFieldKey,
              initialValue: _unit,
              decoration: InputDecoration(
                labelText: l10n.bodyTrackerMeasurementUnitLabel,
              ),
              items: [
                for (final unit in MeasurementUnit.values)
                  DropdownMenuItem<MeasurementUnit>(
                    value: unit,
                    child: Text(_unitLabel(l10n, unit)),
                  ),
              ],
              onChanged: (unit) {
                if (unit != null) {
                  setState(() {
                    _unit = unit;
                  });
                }
              },
            ),
            const SizedBox(height: AppDimens.base),
            DropdownButtonFormField<MeasurementGoalType>(
              key: BodyTrackerScreen.measurementGoalFieldKey,
              initialValue: _goalType,
              decoration: InputDecoration(
                labelText: l10n.bodyTrackerMeasurementGoalLabel,
              ),
              items: [
                for (final goalType in MeasurementGoalType.values)
                  DropdownMenuItem<MeasurementGoalType>(
                    value: goalType,
                    child: Text(_goalLabel(l10n, goalType)),
                  ),
              ],
              onChanged: (goalType) {
                if (goalType != null) {
                  setState(() {
                    _goalType = goalType;
                    _targetValueError = null;
                  });
                }
              },
            ),
            if (_goalType == MeasurementGoalType.target) ...[
              const SizedBox(height: AppDimens.base),
              TextField(
                key: BodyTrackerScreen.measurementTargetValueFieldKey,
                controller: _targetValueController,
                decoration: InputDecoration(
                  labelText: l10n.bodyTrackerMeasurementTargetLabel,
                  suffixText: _unitLabel(l10n, _unit),
                  errorText: _targetValueError,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
            const SizedBox(height: AppDimens.base),
            SwitchListTile(
              key: BodyTrackerScreen.measurementEnabledFieldKey,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.bodyTrackerMeasurementEnabledLabel),
              value: _enabled,
              onChanged: (enabled) {
                setState(() {
                  _enabled = enabled;
                });
              },
            ),
            const SizedBox(height: AppDimens.base),
            FilledButton.icon(
              key: BodyTrackerScreen.saveMeasurementButtonKey,
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(l10n.bodyTrackerCreate),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    final targetValue = _goalType == MeasurementGoalType.target
        ? double.tryParse(_targetValueController.text.trim())
        : null;
    setState(() {
      _nameError =
          name.isEmpty ? l10n.bodyTrackerMeasurementNameRequired : null;
      _targetValueError = _goalType == MeasurementGoalType.target &&
              (targetValue == null || !targetValue.isFinite || targetValue < 0)
          ? l10n.bodyTrackerMeasurementTargetRequired
          : null;
    });
    if (_nameError != null || _targetValueError != null) {
      return;
    }

    await ref.read(bodyTrackerControllerProvider.notifier).createMeasurement(
          name: name,
          unit: _unit,
          goalType: _goalType,
          targetValue: targetValue,
          enabled: _enabled,
        );
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.bodyTrackerMeasurementCreated)),
    );
  }
}

class _MeasurementProgressScreen extends ConsumerStatefulWidget {
  const _MeasurementProgressScreen({
    required this.measurement,
  });

  final MeasurementRecord measurement;

  @override
  ConsumerState<_MeasurementProgressScreen> createState() =>
      _MeasurementProgressScreenState();
}

class _MeasurementProgressScreenState
    extends ConsumerState<_MeasurementProgressScreen> {
  MeasurementGraphPoint? _selectedPoint;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bodyTrackerGraphProvider(widget.measurement.id));
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.bodyTrackerProgressTitle)),
      body: SafeArea(
        child: state.when(
          data: (state) {
            if (state == null) {
              return Padding(
                padding: const EdgeInsets.all(AppDimens.base),
                child: Text(
                  context.l10n.bodyTrackerUnavailable,
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              );
            }
            return _buildGraph(context, state.graph);
          },
          loading: () => const SizedBox.expand(),
          error: (error, stackTrace) => Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              context.l10n.bodyTrackerUnavailable,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGraph(BuildContext context, MeasurementProgressGraph graph) {
    final l10n = context.l10n;
    final selectedPoint = _selectedPoint;
    final hasPoints = graph.renderPoints.isNotEmpty;
    final unitLabel = _unitLabel(l10n, graph.measurement.unit);
    final targetValue = graph.targetValue;
    final selectedSourceLabels = selectedPoint == null
        ? const <String>[]
        : _metricReadingSourceLabels(
            l10n,
            selectedPoint.provenance,
            selectedPoint.source,
          );

    return ListView(
      padding: const EdgeInsets.all(AppDimens.base),
      children: [
        Text(graph.measurement.name, style: context.textStyles.h2),
        const SizedBox(height: AppDimens.dense),
        Semantics(
          container: true,
          label: l10n.bodyTrackerProgressGraphSemanticLabel(
            graph.measurement.name,
            graph.rawPoints.length,
          ),
          button: hasPoints,
          hint: hasPoints ? l10n.bodyTrackerProgressGraphHint : null,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tapWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              return GestureDetector(
                key: BodyTrackerScreen.progressGraphKey(graph.measurement.id),
                behavior: HitTestBehavior.opaque,
                onTapDown: hasPoints
                    ? (details) => _selectNearestPoint(
                          details.localPosition.dx,
                          tapWidth,
                          graph,
                        )
                    : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: context.colors.divider),
                    borderRadius: AppRadii.cardMd,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimens.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 160,
                          width: double.infinity,
                          child: hasPoints
                              ? CustomPaint(
                                  painter: _MeasurementProgressPainter(
                                    points: graph.renderPoints,
                                    targetValue: targetValue,
                                    lineColor: context.colors.save,
                                    targetLineColor: context.colors.record,
                                    gridColor: context.colors.divider,
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    l10n.bodyTrackerProgressEmpty,
                                    style: context.textStyles.caption.copyWith(
                                      color: context.colors.textSecondary,
                                    ),
                                  ),
                                ),
                        ),
                        if (targetValue != null) ...[
                          const SizedBox(height: AppDimens.dense),
                          Text(
                            key: BodyTrackerScreen.progressTargetLineKey,
                            l10n.bodyTrackerProgressTargetLine(
                              _formatMeasurementNumber(targetValue),
                              unitLabel,
                            ),
                            style: context.textStyles.caption.copyWith(
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                        if (graph.isDownsampled) ...[
                          const SizedBox(height: AppDimens.dense / 2),
                          Text(
                            l10n.bodyTrackerProgressDownsampled(
                              graph.renderPoints.length,
                              graph.rawPoints.length,
                            ),
                            style: context.textStyles.caption.copyWith(
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                        if (selectedPoint != null) ...[
                          const SizedBox(height: AppDimens.dense / 2),
                          Semantics(
                            liveRegion: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l10n.bodyTrackerProgressSelected(
                                    graph.measurement.name,
                                    _formatMeasurementNumber(
                                      selectedPoint.value,
                                    ),
                                    unitLabel,
                                    _formatDisplayDateTime(
                                      selectedPoint.measuredAt,
                                    ),
                                  ),
                                  style: context.textStyles.caption,
                                ),
                                if (selectedSourceLabels.isNotEmpty) ...[
                                  const SizedBox(height: AppDimens.dense / 3),
                                  Text(
                                    selectedSourceLabels.join(' - '),
                                    style: context.textStyles.caption.copyWith(
                                      color: context.colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _selectNearestPoint(
    double localDx,
    double width,
    MeasurementProgressGraph graph,
  ) {
    if (graph.renderPoints.isEmpty) {
      return;
    }

    final effectiveWidth = math.max(width, 1);
    final clampedDx = localDx.clamp(0, effectiveWidth).toDouble();
    final scaledIndex =
        (clampedDx / effectiveWidth) * (graph.renderPoints.length - 1);
    final renderIndex = scaledIndex.round().clamp(
          0,
          graph.renderPoints.length - 1,
        );
    setState(() {
      _selectedPoint = graph.inspectRawPoint(renderIndex);
    });
  }
}

class _MeasurementProgressPainter extends CustomPainter {
  const _MeasurementProgressPainter({
    required this.points,
    required this.targetValue,
    required this.lineColor,
    required this.targetLineColor,
    required this.gridColor,
  });

  final List<MeasurementGraphPoint> points;
  final double? targetValue;
  final Color lineColor;
  final Color targetLineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      gridPaint,
    );

    if (points.isEmpty) {
      return;
    }

    final targetLineValue = targetValue;
    final values = <double>[
      for (final point in points) point.value,
      if (targetLineValue != null) targetLineValue,
    ];
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = maxValue == minValue ? 1 : maxValue - minValue;

    Offset pointOffset(int index) {
      final point = points[index];
      final x = points.length == 1
          ? size.width / 2
          : size.width * index / (points.length - 1);
      final normalized = (point.value - minValue) / range;
      final y = size.height - (normalized * (size.height - AppDimens.base));
      return Offset(x, y.clamp(0, size.height).toDouble());
    }

    if (targetLineValue != null) {
      final normalized = (targetLineValue - minValue) / range;
      final y = size.height - (normalized * (size.height - AppDimens.base));
      final targetPaint = Paint()
        ..color = targetLineColor
        ..strokeWidth = 1.5;
      const dashWidth = 8.0;
      const dashGap = 6.0;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + dashWidth, size.width), y),
          targetPaint,
        );
        x += dashWidth + dashGap;
      }
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    if (points.length == 1) {
      canvas.drawCircle(pointOffset(0), 4, dotPaint);
      return;
    }

    final path = Path()..moveTo(pointOffset(0).dx, pointOffset(0).dy);
    for (var index = 1; index < points.length; index += 1) {
      final offset = pointOffset(index);
      path.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(path, linePaint);

    canvas.drawCircle(pointOffset(0), 3, dotPaint);
    canvas.drawCircle(pointOffset(points.length - 1), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _MeasurementProgressPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.targetValue != targetValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.targetLineColor != targetLineColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _MeasurementHistoryScreen extends ConsumerStatefulWidget {
  const _MeasurementHistoryScreen({
    this.initialMeasurementId,
  });

  final String? initialMeasurementId;

  @override
  ConsumerState<_MeasurementHistoryScreen> createState() =>
      _MeasurementHistoryScreenState();
}

class _MeasurementHistoryScreenState
    extends ConsumerState<_MeasurementHistoryScreen> {
  static const _allMeasurementsFilterId = '__all__';

  late String? _selectedMeasurementId;

  @override
  void initState() {
    super.initState();
    _selectedMeasurementId = widget.initialMeasurementId;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bodyTrackerHistoryProvider(_selectedMeasurementId));
    final selectedMeasurement = _selectedMeasurementId == null
        ? null
        : _measurementById(state.value?.measurements, _selectedMeasurementId!);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.bodyTrackerHistoryTitle),
        actions: [
          if (selectedMeasurement != null)
            IconButton(
              key: BodyTrackerScreen.progressButtonKey,
              tooltip: context.l10n.bodyTrackerProgressTooltip,
              onPressed: () => _openProgress(context, selectedMeasurement),
              icon: const Icon(Icons.show_chart),
            ),
        ],
      ),
      body: SafeArea(
        child: state.when(
          data: _buildHistory,
          loading: () => const SizedBox.expand(),
          error: (error, stackTrace) => Padding(
            padding: const EdgeInsets.all(AppDimens.base),
            child: Text(
              context.l10n.bodyTrackerUnavailable,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistory(BodyTrackerHistoryState state) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppDimens.base),
      itemCount: state.items.isEmpty ? 2 : state.items.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: AppDimens.dense),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _MeasurementHistoryFilter(
            selectedMeasurementId: _selectedMeasurementId,
            measurements: state.measurements,
            allMeasurementsFilterId: _allMeasurementsFilterId,
            onChanged: (value) {
              setState(() {
                _selectedMeasurementId =
                    value == _allMeasurementsFilterId ? null : value;
              });
            },
          );
        }

        if (state.items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.base),
            child: Text(
              context.l10n.bodyTrackerHistoryEmpty,
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          );
        }

        final item = state.items[index - 1];
        return _MeasurementHistoryTile(
          item: item,
          onDelete: () => _deleteEntry(item),
        );
      },
    );
  }

  Future<void> _deleteEntry(MeasurementHistoryItem item) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.bodyTrackerDeleteEntryTitle),
            content: Text(l10n.bodyTrackerDeleteEntryMessage),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.textPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.bodyTrackerDeleteEntryCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.bodyTrackerDeleteEntryConfirm),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }

    await ref
        .read(bodyTrackerControllerProvider.notifier)
        .deleteEntry(item.entry.id);
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.bodyTrackerEntryDeleted)),
    );
  }

  void _openProgress(BuildContext context, MeasurementRecord measurement) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MeasurementProgressScreen(measurement: measurement),
      ),
    );
  }

  MeasurementRecord? _measurementById(
    List<MeasurementRecord>? measurements,
    String measurementId,
  ) {
    if (measurements == null) {
      return null;
    }
    for (final measurement in measurements) {
      if (measurement.id == measurementId) {
        return measurement;
      }
    }
    return null;
  }
}

class _MeasurementHistoryFilter extends StatelessWidget {
  const _MeasurementHistoryFilter({
    required this.selectedMeasurementId,
    required this.measurements,
    required this.allMeasurementsFilterId,
    required this.onChanged,
  });

  final String? selectedMeasurementId;
  final List<MeasurementRecord> measurements;
  final String allMeasurementsFilterId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: BodyTrackerScreen.historyFilterKey,
      initialValue: selectedMeasurementId ?? allMeasurementsFilterId,
      decoration: InputDecoration(
        labelText: context.l10n.bodyTrackerHistoryFilterLabel,
      ),
      items: [
        DropdownMenuItem<String>(
          value: allMeasurementsFilterId,
          child: Text(context.l10n.bodyTrackerHistoryAllMeasurements),
        ),
        for (final measurement in measurements)
          DropdownMenuItem<String>(
            value: measurement.id,
            child: Text(measurement.name),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _MeasurementHistoryTile extends StatelessWidget {
  const _MeasurementHistoryTile({
    required this.item,
    required this.onDelete,
  });

  final MeasurementHistoryItem item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unitLabel = _unitLabel(l10n, item.measurement.unit);
    final value = l10n.bodyTrackerValueWithUnit(
      item.entry.valueEntered,
      unitLabel,
    );
    final delta = item.delta;
    final deltaValue = delta == null
        ? null
        : l10n.bodyTrackerValueWithUnit(
            delta.valueEntered,
            unitLabel,
          );
    final comment = item.entry.comment;
    final subtitleParts = <String>[
      _formatDisplayDateTime(item.entry.measuredAt),
      ..._metricReadingSourceLabels(
        l10n,
        item.entry.provenance,
        item.entry.source,
      ),
      if (comment != null && comment.isNotEmpty) comment,
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        key: BodyTrackerScreen.historyEntryTileKey(item.entry.id),
        minVerticalPadding: AppDimens.dense,
        title: Text(item.measurement.name),
        subtitle: Text(subtitleParts.join(' - ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: context.textStyles.numeralRow),
                if (delta != null && deltaValue != null) ...[
                  const SizedBox(height: AppDimens.dense / 3),
                  _MeasurementDeltaBadge(
                    delta: delta,
                    label: deltaValue,
                  ),
                ],
              ],
            ),
            const SizedBox(width: AppDimens.dense),
            IconButton(
              key: BodyTrackerScreen.historyEntryDeleteButtonKey(item.entry.id),
              tooltip: context.l10n.bodyTrackerDeleteEntryTooltip,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        onTap: item.entry.canEditInPlace
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _MeasurementEntryScreen(
                      measurement: item.measurement,
                      entry: item.entry,
                    ),
                  ),
                );
              }
            : null,
      ),
    );
  }
}

List<String> _metricReadingSourceLabels(
  AppLocalizations l10n,
  MetricReadingProvenance provenance,
  String source,
) {
  final normalizedSource = source.trim();
  return <String>[
    _metricReadingProvenanceLabel(l10n, provenance),
    if (normalizedSource.isNotEmpty && normalizedSource != 'manual')
      l10n.metricsSource(normalizedSource),
  ];
}

String _metricReadingProvenanceLabel(
  AppLocalizations l10n,
  MetricReadingProvenance provenance,
) {
  return switch (provenance) {
    MetricReadingProvenance.manual => l10n.metricsManualProvenance,
    MetricReadingProvenance.integration => l10n.metricsIntegrationProvenance,
    MetricReadingProvenance.agent => l10n.metricsAgentProvenance,
  };
}

String _unitLabel(AppLocalizations l10n, MeasurementUnit unit) {
  return switch (unit) {
    MeasurementUnit.kilogram => l10n.bodyTrackerUnitKilogram,
    MeasurementUnit.pound => l10n.bodyTrackerUnitPound,
    MeasurementUnit.centimeter => l10n.bodyTrackerUnitCentimeter,
    MeasurementUnit.inch => l10n.bodyTrackerUnitInch,
    MeasurementUnit.percent => l10n.bodyTrackerUnitPercent,
  };
}

String _goalLabel(AppLocalizations l10n, MeasurementGoalType goalType) {
  return switch (goalType) {
    MeasurementGoalType.increase => l10n.bodyTrackerGoalIncrease,
    MeasurementGoalType.decrease => l10n.bodyTrackerGoalDecrease,
    MeasurementGoalType.target => l10n.bodyTrackerGoalTarget,
  };
}

String _formatMeasurementNumber(double value) {
  final fixed = value.toStringAsFixed(5);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _recencyLabel(AppLocalizations l10n, DateTime measuredAt) {
  final elapsed = DateTime.now().difference(measuredAt.toLocal());
  if (elapsed < const Duration(minutes: 1)) {
    return l10n.activityRelativeLessThanOneMinuteAgo;
  }
  if (elapsed < const Duration(hours: 1)) {
    return l10n.activityRelativeMinutesAgo(elapsed.inMinutes);
  }
  if (elapsed < const Duration(days: 1)) {
    return l10n.activityRelativeHoursAgo(elapsed.inHours);
  }
  return l10n.activityRelativeDaysAgo(elapsed.inDays);
}

String _formatEditableDateTime(DateTime value) {
  return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
}

String _formatDisplayDateTime(DateTime value) {
  return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
}

DateTime? _parseEditableDateTime(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})$',
  ).firstMatch(value.trim());
  if (match == null) {
    return null;
  }

  final parts = <int>[];
  for (var index = 1; index <= 5; index += 1) {
    final parsed = int.tryParse(match.group(index)!);
    if (parsed == null) {
      return null;
    }
    parts.add(parsed);
  }

  final parsed = DateTime(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
  );
  if (parsed.year != parts[0] ||
      parsed.month != parts[1] ||
      parsed.day != parts[2] ||
      parsed.hour != parts[3] ||
      parsed.minute != parts[4]) {
    return null;
  }
  return parsed;
}
