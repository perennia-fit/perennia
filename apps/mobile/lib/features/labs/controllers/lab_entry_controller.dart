import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/labs/lab_result.dart';
import '../../../domain/labs/lab_result_validation.dart';
import 'lab_results_providers.dart';

/// The clock the lab entry sheet reads "today" from: the date picker's last
/// day and the `lab_collected_future` rule. Overridden in tests, like
/// `protocolsClockProvider`.
final labClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The lab entry sheet's state (docs/designs/lab-results.md,
/// "Collection-based manual entry").
///
/// autoDispose on purpose: the sheet is the only listener, so closing it,
/// including the close a lock forces, discards every unsaved row. Nothing is
/// written before Save.
final labEntryControllerProvider =
    NotifierProvider.autoDispose<LabEntryController, LabEntryState>(
  LabEntryController.new,
);

/// One editable result row of the entry sheet.
///
/// [id] is stable for the row's life, so the sheet can keep a row's text
/// fields when an earlier row is removed; everything else addresses rows by
/// index, as [CollectionDraft.rows] does.
@immutable
class LabEntryRow {
  const LabEntryRow({
    required this.id,
    this.labTestKey,
    this.comparator,
    this.value = '',
    this.printedRange = '',
    this.printedFlag = '',
  });

  final int id;
  final String? labTestKey;
  final LabComparator? comparator;

  /// The value as typed.
  final String value;

  /// As typed; blank is saved as null.
  final String printedRange;

  /// As typed; blank is saved as null.
  final String printedFlag;

  LabEntryRow copyWith({
    String? labTestKey,
    LabComparator? Function()? comparator,
    String? value,
    String? printedRange,
    String? printedFlag,
  }) {
    return LabEntryRow(
      id: id,
      labTestKey: labTestKey ?? this.labTestKey,
      comparator: comparator == null ? this.comparator : comparator(),
      value: value ?? this.value,
      printedRange: printedRange ?? this.printedRange,
      printedFlag: printedFlag ?? this.printedFlag,
    );
  }
}

@immutable
class LabEntryState {
  const LabEntryState({
    this.collectedDate,
    this.collectedTime,
    this.labName = '',
    this.reportStatus = ReportStatus.final_,
    this.fasting = false,
    required this.rows,
    this.errorsByRow = const <int, List<LabValidationIssue>>{},
    this.collectionErrors = const <LabValidationIssue>[],
  });

  /// Null until chosen. Only the date part is read.
  final DateTime? collectedDate;

  /// The printed collection time, or null when only a date was printed.
  final ({int hour, int minute})? collectedTime;

  /// As typed; blank is saved as null.
  final String labName;
  final ReportStatus reportStatus;
  final bool fasting;

  /// Never empty.
  final List<LabEntryRow> rows;

  /// Hard errors by row index, from the last check or save.
  final Map<int, List<LabValidationIssue>> errorsByRow;

  /// Hard errors of the collection fields (`lab.collected`, `lab.labName`,
  /// and the other collection-wide fields), each once.
  final List<LabValidationIssue> collectionErrors;

  LabEntryState copyWith({
    DateTime? collectedDate,
    ({int hour, int minute})? Function()? collectedTime,
    String? labName,
    ReportStatus? reportStatus,
    bool? fasting,
    List<LabEntryRow>? rows,
    Map<int, List<LabValidationIssue>>? errorsByRow,
    List<LabValidationIssue>? collectionErrors,
  }) {
    return LabEntryState(
      collectedDate: collectedDate ?? this.collectedDate,
      collectedTime:
          collectedTime == null ? this.collectedTime : collectedTime(),
      labName: labName ?? this.labName,
      reportStatus: reportStatus ?? this.reportStatus,
      fasting: fasting ?? this.fasting,
      rows: rows ?? this.rows,
      errorsByRow: errorsByRow ?? this.errorsByRow,
      collectionErrors: collectionErrors ?? this.collectionErrors,
    );
  }
}

/// What a pre-save [LabEntryController.check] found.
@immutable
class LabEntryCheck {
  const LabEntryCheck({required this.hasErrors, required this.warnings});

  /// Whether any hard error was found; the errors are in the state.
  final bool hasErrors;

  /// Every soft warning, in row order, each with its row index. Empty when
  /// [hasErrors] is true.
  final List<({int rowIndex, LabValidationIssue issue})> warnings;
}

/// The issue the controller raises itself when Save is tapped with no
/// collection date: a [CollectionDraft] cannot be built without one.
const LabValidationIssue labCollectedMissingIssue = LabValidationIssue(
  rule: 'lab_collected_missing',
  field: 'lab.collected',
  message: 'Give the collection date.',
);

class LabEntryController extends Notifier<LabEntryState> {
  int _nextRowId = 1;

  @override
  LabEntryState build() {
    return LabEntryState(rows: <LabEntryRow>[_newRow()]);
  }

  LabResultsRepository get _repository =>
      ref.read(labResultsRepositoryProvider);

  LabEntryRow _newRow() => LabEntryRow(id: _nextRowId++);

  void setDate(DateTime date) {
    state = state.copyWith(
      collectedDate: DateTime(date.year, date.month, date.day),
      collectionErrors: _withoutField(state.collectionErrors, _dateFields),
    );
  }

  void setTime(int hour, int minute) {
    state = state.copyWith(
      collectedTime: () => (hour: hour, minute: minute),
      collectionErrors: _withoutField(state.collectionErrors, _dateFields),
    );
  }

  void clearTime() {
    state = state.copyWith(
      collectedTime: () => null,
      collectionErrors: _withoutField(state.collectionErrors, _dateFields),
    );
  }

  void setLabName(String labName) {
    state = state.copyWith(
      labName: labName,
      collectionErrors: _withoutField(
        state.collectionErrors,
        const <String>{'lab.labName'},
      ),
    );
  }

  void setReportStatus(ReportStatus reportStatus) {
    state = state.copyWith(
      reportStatus: reportStatus,
      collectionErrors: _withoutField(
        state.collectionErrors,
        const <String>{'lab.reportStatus'},
      ),
    );
  }

  void setFasting(bool fasting) {
    state = state.copyWith(
      fasting: fasting,
      collectionErrors: _withoutField(
        state.collectionErrors,
        const <String>{'lab.fasting'},
      ),
    );
  }

  void addRow() {
    state = state.copyWith(rows: <LabEntryRow>[...state.rows, _newRow()]);
  }

  /// Removes the row at [index], keeping at least one row. Later rows' errors
  /// move up with them.
  void removeRow(int index) {
    if (state.rows.length <= 1 || index < 0 || index >= state.rows.length) {
      return;
    }
    final rows = <LabEntryRow>[...state.rows]..removeAt(index);
    final errors = <int, List<LabValidationIssue>>{
      for (final MapEntry(:key, :value) in state.errorsByRow.entries)
        if (key < index) key: value else if (key > index) key - 1: value,
    };
    state = state.copyWith(rows: rows, errorsByRow: errors);
  }

  void setRowLabTest(int index, String labTestKey) =>
      _editRow(index, (row) => row.copyWith(labTestKey: labTestKey));

  void setRowComparator(int index, LabComparator? comparator) =>
      _editRow(index, (row) => row.copyWith(comparator: () => comparator));

  void setRowValue(int index, String value) =>
      _editRow(index, (row) => row.copyWith(value: value));

  void setRowPrintedRange(int index, String printedRange) =>
      _editRow(index, (row) => row.copyWith(printedRange: printedRange));

  void setRowPrintedFlag(int index, String printedFlag) =>
      _editRow(index, (row) => row.copyWith(printedFlag: printedFlag));

  /// Any edit of a row clears that row's errors.
  void _editRow(int index, LabEntryRow Function(LabEntryRow row) edit) {
    if (index < 0 || index >= state.rows.length) {
      return;
    }
    final rows = <LabEntryRow>[...state.rows];
    rows[index] = edit(rows[index]);
    final errors = <int, List<LabValidationIssue>>{...state.errorsByRow}
      ..remove(index);
    state = state.copyWith(rows: rows, errorsByRow: errors);
  }

  /// The repository's draft of the sheet, or null while no date is chosen.
  /// Blank text is null.
  CollectionDraft? toDraft() {
    final date = state.collectedDate;
    if (date == null) {
      return null;
    }
    return CollectionDraft(
      collectedDate: date,
      collectedTime: state.collectedTime,
      labName: _blankToNull(state.labName),
      reportStatus: state.reportStatus,
      fasting: state.fasting,
      rows: <CollectionDraftRow>[
        for (final row in state.rows)
          CollectionDraftRow(
            labTestKey: row.labTestKey,
            comparator: row.comparator,
            value: row.value,
            printedRange: _blankToNull(row.printedRange),
            printedFlag: _blankToNull(row.printedFlag),
          ),
      ],
    );
  }

  /// The pre-save check: hard errors land in the state; the soft warnings
  /// come back for the one confirmation dialog.
  ///
  /// The errors and the reading-rule warnings come from
  /// [LabResultsRepository.checkCollection], the code the save itself runs.
  /// `lab_result_replaces` needs stored results, so it is read from
  /// [LabResultsRepository.previewCollection] only once there are no errors.
  Future<LabEntryCheck> check() async {
    final draft = toDraft();
    if (draft == null) {
      state = state.copyWith(
        collectionErrors: _withIssue(
          state.collectionErrors,
          labCollectedMissingIssue,
        ),
      );
      return const LabEntryCheck(hasErrors: true, warnings: []);
    }
    final repository = _repository;
    final result = repository.checkCollection(
      draft,
      today: ref.read(labClockProvider)(),
    );
    _applyErrors(result.errors);
    if (result.errors.isNotEmpty) {
      return const LabEntryCheck(hasErrors: true, warnings: []);
    }
    final replaces = await repository.previewCollection(draft);
    return LabEntryCheck(
      hasErrors: false,
      warnings: <({int rowIndex, LabValidationIssue issue})>[
        for (var index = 0; index < draft.rows.length; index++) ...[
          for (final issue
              in result.warnings[index] ?? const <LabValidationIssue>[])
            (rowIndex: index, issue: issue),
          for (final issue in replaces[index] ?? const <LabValidationIssue>[])
            (rowIndex: index, issue: issue),
        ],
      ],
    );
  }

  /// Saves the collection, returning the Activity Log Batch id, or null when
  /// a hard rule rejected it (its errors are then in the state).
  Future<String?> save() async {
    final draft = toDraft();
    if (draft == null) {
      await check();
      return null;
    }
    try {
      return await _repository.saveCollection(
        draft,
        today: ref.read(labClockProvider)(),
      );
    } on LabResultValidationException catch (error) {
      if (ref.mounted) {
        _applyErrors(error.issuesByRow);
      }
      return null;
    }
  }

  /// Replaces the errors with [issuesByRow]: an issue of a collection field
  /// goes to [LabEntryState.collectionErrors] once, however many rows carry
  /// it; the rest stay on their rows.
  void _applyErrors(Map<int, List<LabValidationIssue>> issuesByRow) {
    final rowErrors = <int, List<LabValidationIssue>>{};
    var collectionErrors = const <LabValidationIssue>[];
    for (final MapEntry(key: index, value: issues) in issuesByRow.entries) {
      final onRow = <LabValidationIssue>[];
      for (final issue in issues) {
        if (isLabCollectionField(issue.field)) {
          collectionErrors = _withIssue(collectionErrors, issue);
        } else {
          onRow.add(issue);
        }
      }
      if (onRow.isNotEmpty) {
        rowErrors[index] = List<LabValidationIssue>.unmodifiable(onRow);
      }
    }
    state = state.copyWith(
      errorsByRow: rowErrors,
      collectionErrors: collectionErrors,
    );
  }
}

/// Whether an issue's [field] belongs to the collection fields at the top of
/// the sheet rather than to one result row: `lab.collected` and `lab.labName`,
/// and the other collection-wide fields (the time anchor, which follows
/// `lab.collected`, report status and fasting).
bool isLabCollectionField(String field) =>
    field == 'timeAnchor' ||
    field == 'lab.collected' ||
    field == 'lab.labName' ||
    field == 'lab.reportStatus' ||
    field == 'lab.fasting';

const Set<String> _dateFields = <String>{'lab.collected', 'timeAnchor'};

List<LabValidationIssue> _withoutField(
  List<LabValidationIssue> issues,
  Set<String> fields,
) {
  if (!issues.any((issue) => fields.contains(issue.field))) {
    return issues;
  }
  return List<LabValidationIssue>.unmodifiable(
    issues.where((issue) => !fields.contains(issue.field)),
  );
}

List<LabValidationIssue> _withIssue(
  List<LabValidationIssue> issues,
  LabValidationIssue issue,
) {
  if (issues.any((i) => i.rule == issue.rule && i.field == issue.field)) {
    return issues;
  }
  return List<LabValidationIssue>.unmodifiable(
    <LabValidationIssue>[...issues, issue],
  );
}

String? _blankToNull(String text) => text.trim().isEmpty ? null : text;
