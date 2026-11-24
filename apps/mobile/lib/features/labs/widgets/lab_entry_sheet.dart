import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/labs/lab_result.dart';
import '../../../domain/labs/lab_result_validation.dart';
import '../../../domain/labs/lab_test.dart';
import '../../../domain/labs/lab_test_catalogue.generated.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../profile/widgets/profile_screen.dart';
import '../../protocols/widgets/protocols_lock_screen.dart';
import '../controllers/lab_entry_controller.dart';
import 'lab_test_picker.dart';

/// Opens the lab entry sheet (docs/designs/lab-results.md,
/// "Collection-based manual entry"): one collection's fields, then its result
/// rows. Completes with the Activity Log Batch id after a save, or null when
/// dismissed or when the app locks.
///
/// The sheet sits behind [ProtocolsLockSheetGuard]: lab results share the
/// Protocols lock, so a lock closes the sheet and its unsaved rows are
/// discarded with [labEntryControllerProvider].
Future<String?> showLabEntrySheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: const ProtocolsLockSheetGuard(
        child: FractionallySizedBox(
          heightFactor: _sheetHeightFactor,
          child: LabEntrySheet(),
        ),
      ),
    ),
  );
}

/// Nearly full height, as the Picker sheet.
const double _sheetHeightFactor = 0.92;

/// The comparator chooser's width: wide enough for "None" at 1x text.
const double _comparatorWidth = 112;

/// The lab entry sheet's content. Open it with [showLabEntrySheet].
class LabEntrySheet extends ConsumerStatefulWidget {
  const LabEntrySheet({super.key});

  static const saveButtonKey = Key('labs.entry.save');
  static const addRowButtonKey = Key('labs.entry.addRow');
  static const dateFieldKey = Key('labs.entry.date');
  static const timeFieldKey = Key('labs.entry.time');
  static const clearTimeButtonKey = Key('labs.entry.clearTime');
  static const labNameFieldKey = Key('labs.entry.labName');
  static const reportStatusKey = Key('labs.entry.reportStatus');
  static const fastingSwitchKey = Key('labs.entry.fasting');
  static const dateErrorKey = Key('labs.entry.dateError');
  static const warningDialogKey = Key('labs.entry.warningDialog');
  static const warningCancelKey = Key('labs.entry.warningCancel');
  static const warningSaveAnywayKey = Key('labs.entry.warningSaveAnyway');

  static Key rowKey(int index) => Key('labs.entry.row.$index');
  static Key rowLabTestKey(int index) => Key('labs.entry.row.$index.labTest');
  static Key rowLabTestErrorKey(int index) =>
      Key('labs.entry.row.$index.labTestError');
  static Key rowComparatorKey(int index) =>
      Key('labs.entry.row.$index.comparator');
  static Key rowValueKey(int index) => Key('labs.entry.row.$index.value');
  static Key rowUnitKey(int index) => Key('labs.entry.row.$index.unit');
  static Key rowPrintedRangeKey(int index) =>
      Key('labs.entry.row.$index.printedRange');
  static Key rowPrintedFlagKey(int index) =>
      Key('labs.entry.row.$index.printedFlag');
  static Key rowRemoveKey(int index) => Key('labs.entry.row.$index.remove');

  @override
  ConsumerState<LabEntrySheet> createState() => _LabEntrySheetState();
}

class _LabEntrySheetState extends ConsumerState<LabEntrySheet> {
  final _labNameController = TextEditingController();

  /// Set from the first tap of Save until its flow ends, so a second tap
  /// while the check or the dialog is up does nothing.
  bool _busy = false;

  @override
  void dispose() {
    _labNameController.dispose();
    super.dispose();
  }

  LabEntryController get _controller =>
      ref.read(labEntryControllerProvider.notifier);

  DateTime _today() => ref.read(labClockProvider)();

  Future<void> _pickDate() async {
    final today = _today();
    final todayDate = DateTime(today.year, today.month, today.day);
    // lab_collected_future rejects a date more than one day after today.
    final lastDate = DateTime(today.year, today.month, today.day + 1);
    final current = ref.read(labEntryControllerProvider).collectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? todayDate,
      firstDate: DateTime(1900),
      lastDate: lastDate,
    );
    if (picked == null || !mounted) {
      return;
    }
    _controller.setDate(picked);
  }

  Future<void> _pickTime() async {
    final current = ref.read(labEntryControllerProvider).collectedTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 8, minute: 0)
          : TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null || !mounted) {
      return;
    }
    _controller.setTime(picked.hour, picked.minute);
  }

  Future<void> _save() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final check = await _controller.check();
      if (!mounted || check.hasErrors) {
        return;
      }
      if (check.warnings.isNotEmpty) {
        final confirmed = await _confirmWarnings(check.warnings);
        if (!mounted || confirmed != true) {
          return;
        }
      }
      final batchId = await _controller.save();
      if (!mounted || batchId == null) {
        return;
      }
      Navigator.of(context).pop(batchId);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// One dialog listing every soft warning of this Save; true to save anyway.
  /// Behind [ProtocolsLockSheetGuard], so a lock closes it with null.
  Future<bool?> _confirmWarnings(
    List<({int rowIndex, LabValidationIssue issue})> warnings,
  ) {
    final rows = ref.read(labEntryControllerProvider).rows;
    final l10n = context.l10n;
    final lines = <String>[
      for (final warning in warnings)
        () {
          final key = rows[warning.rowIndex].labTestKey;
          final labTest = key == null ? null : labTestByKey(key);
          return l10n.labEntryWarningLine(
            labTest?.name ?? '',
            labIssueText(l10n, warning.issue, labTest),
          );
        }(),
    ];
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => ProtocolsLockSheetGuard(
        child: AlertDialog(
          key: LabEntrySheet.warningDialogKey,
          title: Text(l10n.labEntryWarningTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppDimens.dense),
                    child: Text(line, style: dialogContext.textStyles.body),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: LabEntrySheet.warningCancelKey,
              style: _textButtonStyle(dialogContext),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.labEntryWarningCancel),
            ),
            TextButton(
              key: LabEntrySheet.warningSaveAnywayKey,
              style: _textButtonStyle(dialogContext),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.labEntryWarningSaveAnyway),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(labEntryControllerProvider);
    final colors = context.colors;
    final l10n = context.l10n;
    final localizations = MaterialLocalizations.of(context);

    final date = state.collectedDate;
    final time = state.collectedTime;
    final dateErrors = <LabValidationIssue>[
      for (final issue in state.collectionErrors)
        if (issue.field != 'lab.labName') issue,
    ];
    final labNameErrors = <LabValidationIssue>[
      for (final issue in state.collectionErrors)
        if (issue.field == 'lab.labName') issue,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.base),
          child: Text(
            l10n.labEntryTitle,
            style: context.textStyles.h2.copyWith(color: colors.textPrimary),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AppDimens.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProfileDisclosureLine(),
                const SizedBox(height: AppDimens.base),
                _FieldLabel(l10n.labEntryDateLabel),
                _ChooserField(
                  key: LabEntrySheet.dateFieldKey,
                  text: date == null
                      ? l10n.labEntryDatePrompt
                      : localizations.formatMediumDate(date),
                  isPrompt: date == null,
                  icon: Icons.calendar_today_outlined,
                  hasError: dateErrors.isNotEmpty,
                  onTap: _pickDate,
                ),
                if (dateErrors.isNotEmpty)
                  _ErrorText(
                    key: LabEntrySheet.dateErrorKey,
                    text: _joined(l10n, dateErrors, null),
                  ),
                const SizedBox(height: AppDimens.base),
                _FieldLabel(l10n.labEntryTimeLabel),
                Row(
                  children: [
                    Expanded(
                      child: _ChooserField(
                        key: LabEntrySheet.timeFieldKey,
                        text: time == null
                            ? l10n.labEntryTimePrompt
                            : localizations.formatTimeOfDay(
                                TimeOfDay(hour: time.hour, minute: time.minute),
                              ),
                        isPrompt: time == null,
                        icon: Icons.schedule,
                        hasError: false,
                        onTap: _pickTime,
                      ),
                    ),
                    if (time != null)
                      IconButton(
                        key: LabEntrySheet.clearTimeButtonKey,
                        tooltip: l10n.labEntryClearTime,
                        constraints: const BoxConstraints(
                          minWidth: AppDimens.touchTarget,
                          minHeight: AppDimens.touchTarget,
                        ),
                        color: colors.textPrimary,
                        icon: const Icon(Icons.close),
                        onPressed: _controller.clearTime,
                      ),
                  ],
                ),
                const SizedBox(height: AppDimens.base),
                _FieldLabel(l10n.labEntryLabNameLabel),
                TextField(
                  key: LabEntrySheet.labNameFieldKey,
                  controller: _labNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: _labInputDecoration(
                    context,
                    errorText: labNameErrors.isEmpty
                        ? null
                        : _joined(l10n, labNameErrors, null),
                  ),
                  onChanged: _controller.setLabName,
                ),
                const SizedBox(height: AppDimens.base),
                _FieldLabel(l10n.labEntryReportStatusLabel),
                SegmentedButton<ReportStatus>(
                  key: LabEntrySheet.reportStatusKey,
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment<ReportStatus>(
                      value: ReportStatus.final_,
                      label: Text(l10n.labEntryReportStatusFinal),
                    ),
                    ButtonSegment<ReportStatus>(
                      value: ReportStatus.interim,
                      label: Text(l10n.labEntryReportStatusInterim),
                    ),
                  ],
                  selected: <ReportStatus>{state.reportStatus},
                  onSelectionChanged: (selected) =>
                      _controller.setReportStatus(selected.single),
                ),
                const SizedBox(height: AppDimens.dense),
                SwitchListTile(
                  key: LabEntrySheet.fastingSwitchKey,
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: AppDimens.touchTarget,
                  title: Text(
                    l10n.labEntryFasting,
                    style: context.textStyles.body.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  value: state.fasting,
                  onChanged: _controller.setFasting,
                ),
                for (var index = 0; index < state.rows.length; index++) ...[
                  const SizedBox(height: AppDimens.base),
                  _ResultRowCard(
                    key: ValueKey<int>(state.rows[index].id),
                    index: index,
                    row: state.rows[index],
                    errors: state.errorsByRow[index] ??
                        const <LabValidationIssue>[],
                    canRemove: state.rows.length > 1,
                  ),
                ],
                const SizedBox(height: AppDimens.base),
                OutlinedButton.icon(
                  key: LabEntrySheet.addRowButtonKey,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textPrimary,
                    side: BorderSide(color: colors.divider),
                    minimumSize: const Size.fromHeight(AppDimens.touchTarget),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadii.cardMd,
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.labEntryAddRow),
                  onPressed: _controller.addRow,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.base,
            AppDimens.dense,
            AppDimens.base,
            AppDimens.base,
          ),
          child: FilledButton(
            key: LabEntrySheet.saveButtonKey,
            style: saveFormButtonStyle(context),
            onPressed: _busy || state.saving ? null : _save,
            child: Text(l10n.labEntrySave),
          ),
        ),
      ],
    );
  }
}

/// One result row: Lab Test, comparator, value, the fixed unit, Printed
/// Range and Printed Flag, and a remove button. Each hard error shows beside
/// its field.
class _ResultRowCard extends ConsumerStatefulWidget {
  const _ResultRowCard({
    required super.key,
    required this.index,
    required this.row,
    required this.errors,
    required this.canRemove,
  });

  final int index;
  final LabEntryRow row;
  final List<LabValidationIssue> errors;
  final bool canRemove;

  @override
  ConsumerState<_ResultRowCard> createState() => _ResultRowCardState();
}

class _ResultRowCardState extends ConsumerState<_ResultRowCard> {
  // The card is keyed by the row's id, so these follow the row when an
  // earlier row is removed.
  late final _value = TextEditingController(text: widget.row.value);
  late final _printedRange =
      TextEditingController(text: widget.row.printedRange);
  late final _printedFlag = TextEditingController(text: widget.row.printedFlag);

  @override
  void dispose() {
    _value.dispose();
    _printedRange.dispose();
    _printedFlag.dispose();
    super.dispose();
  }

  LabEntryController get _controller =>
      ref.read(labEntryControllerProvider.notifier);

  Future<void> _chooseLabTest() async {
    final key = await showLabTestPicker(context);
    if (key == null || !mounted) {
      return;
    }
    _controller.setRowLabTest(widget.index, key);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final index = widget.index;
    final key = widget.row.labTestKey;
    final labTest = key == null ? null : labTestByKey(key);

    List<LabValidationIssue> errorsFor(Set<String> fields) =>
        <LabValidationIssue>[
          for (final issue in widget.errors)
            if (fields.contains(issue.field)) issue,
        ];
    String? errorText(Set<String> fields) {
      final issues = errorsFor(fields);
      return issues.isEmpty ? null : _joined(l10n, issues, labTest);
    }

    const valueFields = <String>{'entered', 'enteredUnit'};
    const rangeFields = <String>{'lab.printedRange'};
    const flagFields = <String>{'lab.printedFlag'};
    const shownFields = <String>{
      'labTestKey',
      ...valueFields,
      ...rangeFields,
      ...flagFields,
    };
    // An issue whose field the card has no place for shows under the Lab
    // Test, so no hard error is ever silent.
    final labTestErrors = <LabValidationIssue>[
      for (final issue in widget.errors)
        if (issue.field == 'labTestKey' || !shownFields.contains(issue.field))
          issue,
    ];

    return Container(
      key: LabEntrySheet.rowKey(index),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.cardMd,
        border: Border.all(color: colors.divider),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.base,
        AppDimens.dense,
        AppDimens.dense,
        AppDimens.base,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.labEntryRowTitle(index + 1),
                    style: context.textStyles.label.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: LabEntrySheet.rowRemoveKey(index),
                tooltip: l10n.labEntryRemoveRow,
                constraints: const BoxConstraints(
                  minWidth: AppDimens.touchTarget,
                  minHeight: AppDimens.touchTarget,
                ),
                color: colors.textPrimary,
                icon: const Icon(Icons.delete_outline),
                onPressed: widget.canRemove
                    ? () => _controller.removeRow(index)
                    : null,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppDimens.dense),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FieldLabel(l10n.labEntryLabTestLabel),
                _ChooserField(
                  key: LabEntrySheet.rowLabTestKey(index),
                  text: labTest?.name ?? l10n.labEntryLabTestPrompt,
                  isPrompt: labTest == null,
                  icon: Icons.arrow_drop_down,
                  hasError: labTestErrors.isNotEmpty,
                  onTap: _chooseLabTest,
                ),
                if (labTestErrors.isNotEmpty)
                  _ErrorText(
                    key: LabEntrySheet.rowLabTestErrorKey(index),
                    text: _joined(l10n, labTestErrors, labTest),
                  ),
                const SizedBox(height: AppDimens.dense),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _comparatorWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _FieldLabel(l10n.labEntryComparatorLabel),
                          DropdownButtonFormField<LabComparator?>(
                            key: LabEntrySheet.rowComparatorKey(index),
                            initialValue: widget.row.comparator,
                            isExpanded: true,
                            decoration: _labInputDecoration(context),
                            items: [
                              DropdownMenuItem<LabComparator?>(
                                value: null,
                                child: Text(l10n.labEntryComparatorNone),
                              ),
                              for (final comparator in LabComparator.values)
                                DropdownMenuItem<LabComparator?>(
                                  value: comparator,
                                  child: Semantics(
                                    label: _comparatorName(l10n, comparator),
                                    excludeSemantics: true,
                                    child: Text(comparatorSymbol(comparator)),
                                  ),
                                ),
                            ],
                            onChanged: (comparator) =>
                                _controller.setRowComparator(index, comparator),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppDimens.dense),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _FieldLabel(l10n.labEntryValueLabel),
                          TextField(
                            key: LabEntrySheet.rowValueKey(index),
                            controller: _value,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _labInputDecoration(
                              context,
                              errorText: errorText(valueFields),
                            ),
                            onChanged: (value) =>
                                _controller.setRowValue(index, value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppDimens.dense),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel(l10n.labEntryUnitLabel),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: AppDimens.touchTarget,
                          ),
                          child: Align(
                            widthFactor: 1,
                            child: Text(
                              labTest?.unit ?? '–',
                              key: LabEntrySheet.rowUnitKey(index),
                              style: context.textStyles.body.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppDimens.dense),
                _FieldLabel(l10n.labEntryPrintedRangeLabel),
                TextField(
                  key: LabEntrySheet.rowPrintedRangeKey(index),
                  controller: _printedRange,
                  decoration: _labInputDecoration(
                    context,
                    errorText: errorText(rangeFields),
                  ),
                  onChanged: (value) =>
                      _controller.setRowPrintedRange(index, value),
                ),
                const SizedBox(height: AppDimens.dense),
                _FieldLabel(l10n.labEntryPrintedFlagLabel),
                TextField(
                  key: LabEntrySheet.rowPrintedFlagKey(index),
                  controller: _printedFlag,
                  decoration: _labInputDecoration(
                    context,
                    errorText: errorText(flagFields),
                  ),
                  onChanged: (value) =>
                      _controller.setRowPrintedFlag(index, value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The comparator as the chooser shows it: `≤` and `≥` rather than the
/// stored `<=` and `>=`.
String comparatorSymbol(LabComparator comparator) => switch (comparator) {
      LabComparator.lt => '<',
      LabComparator.le => '≤',
      LabComparator.gt => '>',
      LabComparator.ge => '≥',
    };

String _comparatorName(AppLocalizations l10n, LabComparator comparator) =>
    switch (comparator) {
      LabComparator.lt => l10n.labEntryComparatorLt,
      LabComparator.le => l10n.labEntryComparatorLe,
      LabComparator.gt => l10n.labEntryComparatorGt,
      LabComparator.ge => l10n.labEntryComparatorGe,
    };

/// The app's copy for a lab validation issue, chosen by its rule code.
///
/// Never [LabValidationIssue.message]: that is the wire message, in English
/// and for an Agent (`lab_test_unknown` there names an MCP tool). The copy is
/// the spec's Validation table, with the Lab Test's catalogue entry filling
/// the unit list and the bounds; with no [labTest] those fall back to the
/// generic message.
String labIssueText(
  AppLocalizations l10n,
  LabValidationIssue issue,
  LabTest? labTest,
) {
  switch (issue.rule) {
    case 'lab_collected_missing':
      return l10n.labIssueCollectedMissing;
    case 'lab_collected_invalid':
      return l10n.labIssueCollectedInvalid;
    case 'lab_collected_future':
      return l10n.labIssueCollectedFuture;
    case 'lab_time_anchor_mismatch':
      return l10n.labIssueTimeAnchorMismatch;
    case 'lab_unit_not_accepted' when labTest != null:
      return l10n.labIssueUnitNotAccepted(
        <String>[labTest.unit, ...labTest.unitAliases].join(', '),
      );
    case 'lab_value_invalid':
      return l10n.labIssueValueInvalid;
    case 'lab_value_out_of_bounds' when labTest != null:
      return l10n.labIssueValueOutOfBounds(
        '${labTest.hardBounds.min}',
        '${labTest.hardBounds.max}',
        labTest.unit,
      );
    case 'lab_value_implausible':
      return l10n.labIssueValueImplausible;
    case 'lab_text_too_long':
      final field = switch (issue.field) {
        'lab.printedRange' => l10n.labEntryPrintedRangeLabel,
        'lab.printedFlag' => l10n.labEntryPrintedFlagLabel,
        'lab.labName' => l10n.labEntryLabNameField,
        _ => null,
      };
      return field == null
          ? l10n.labIssueFallback
          : l10n.labIssueTextTooLong(field);
    case 'lab_report_status_invalid':
      return l10n.labIssueReportStatusInvalid;
    case 'lab_fasting_invalid':
      return l10n.labIssueFastingInvalid;
    case 'lab_test_unknown':
      return l10n.labIssueTestUnknown;
    case 'lab_result_repeated':
      return l10n.labIssueResultRepeated;
    case 'lab_result_replaces':
      return l10n.labIssueResultReplaces;
    default:
      return l10n.labIssueFallback;
  }
}

String _joined(
  AppLocalizations l10n,
  List<LabValidationIssue> issues,
  LabTest? labTest,
) =>
    issues.map((issue) => labIssueText(l10n, issue, labTest)).join('\n');

/// DESIGN.md's form field: filled on the surface color with a 1px divider
/// stroke, `md` corners and a cyan focus stroke; the label sits above the
/// field, never floating. An error is its text, so color is not its only
/// signal.
InputDecoration _labInputDecoration(
  BuildContext context, {
  String? errorText,
}) {
  final colors = context.colors;
  final primary = Theme.of(context).colorScheme.primary;
  OutlineInputBorder border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: AppRadii.cardMd,
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    errorText: errorText,
    errorMaxLines: 4,
    filled: true,
    fillColor: colors.surface,
    isDense: true,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppDimens.dense,
      vertical: AppDimens.dense,
    ),
    constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
    enabledBorder: border(colors.divider),
    disabledBorder: border(colors.divider),
    focusedBorder: border(primary, width: 2),
    errorBorder: border(colors.textPrimary, width: 2),
    focusedErrorBorder: border(primary, width: 2),
    errorStyle: context.textStyles.label.copyWith(color: colors.textPrimary),
  );
}

ButtonStyle _textButtonStyle(BuildContext context) => TextButton.styleFrom(
      foregroundColor: context.colors.textPrimary,
      minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
    );

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.dense / 2),
      child: Text(
        text,
        style: context.textStyles.label.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

/// A form field that opens a chooser (a date, a time, a Lab Test) instead of
/// taking text.
class _ChooserField extends StatelessWidget {
  const _ChooserField({
    super.key,
    required this.text,
    required this.isPrompt,
    required this.icon,
    required this.hasError,
    required this.onTap,
  });

  final String text;

  /// Whether [text] is the prompt shown before a choice.
  final bool isPrompt;
  final IconData icon;
  final bool hasError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardMd,
        side: BorderSide(
          color: hasError ? colors.textPrimary : colors.divider,
          width: hasError ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.dense,
              vertical: AppDimens.dense,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: context.textStyles.body.copyWith(
                      color:
                          isPrompt ? colors.textSecondary : colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppDimens.dense),
                Icon(icon, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppDimens.dense / 2,
        left: AppDimens.dense,
      ),
      child: Text(
        text,
        style: context.textStyles.label.copyWith(
          color: context.colors.textPrimary,
        ),
      ),
    );
  }
}
