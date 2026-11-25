/// The Lab Result reading rules of the **single shared two-tier validator**
/// (docs/designs/lab-results.md, Validation). Its verdicts, rule ids, fields
/// and messages must agree with the TypeScript twin (`validateLabResult` in
/// apps/server/src/agent-validation.ts) against the shared golden vector
/// (packages/golden-vectors/vectors/m42-lab-result-validation.json).
///
/// Every writer runs these rules before the normaliser, and normalises only a
/// reading they accept. The Request rules (`lab_test_unknown` and the rest)
/// need the request or the stored data and live with the writers; so an
/// unknown `labTestKey` here is a programming error and throws.
///
/// Issue order and skipping, which both languages share:
///
/// * issues follow the Validation table's row order: collected_missing,
///   collected_invalid, collected_future, time_anchor_mismatch,
///   unit_not_accepted, value_invalid, value_out_of_bounds, value_implausible,
///   text_too_long (printedRange, printedFlag, labName), report_status_invalid,
///   fasting_invalid;
/// * the future and time-anchor checks are skipped when `collected` is
///   missing or invalid;
/// * the bounds checks run only when `entered` parses, a Limit Result's bound
///   being checked as the value, and `lab_value_implausible` is skipped when
///   `lab_value_out_of_bounds` fired;
/// * `entered` is trimmed, then must be a bare number or an ASCII comparator,
///   exactly one space and a number (the canonical form; `≤ 1` and `<1` are
///   rejected here even though the normaliser accepts them);
/// * text lengths count UTF-16 code units after trimming, and a blank text
///   field is valid (the normaliser writes it as null). A text field that is
///   not a string is left to the request schema and not judged here.
library;

import 'lab_result.dart';
import 'lab_test.dart';
import 'lab_test_catalogue.generated.dart';

/// Moves with `schemaVersion` in m42-lab-result-validation.json.
const int labResultValidationSchemaVersion = 1;

/// The longest `printedRange`, `printedFlag` and `labName`, in UTF-16 code
/// units after trimming.
const int labPrintedRangeMaxLength = 120;
const int labPrintedFlagMaxLength = 8;
const int labNameMaxLength = 80;

/// The time anchor's offset range, inclusive.
const int labTimezoneOffsetMinMinutes = -720;
const int labTimezoneOffsetMaxMinutes = 840;

/// One reading as a writer is about to save it, before normalisation.
class LabResultInput {
  const LabResultInput({
    required this.labTestKey,
    required this.entered,
    required this.enteredUnit,
    this.lab,
    required this.timeAnchor,
  });

  /// A key in the catalogue; an unknown one throws.
  final String labTestKey;

  /// The value as typed, in the canonical `entered` form once trimmed.
  final String entered;

  /// The unit as sent, matched against the Lab Test under [foldUnit].
  final String enteredUnit;

  /// The `lab` object as sent (raw JSON), or null.
  final Map<String, Object?>? lab;

  /// The Metric Reading time anchor as sent (raw JSON).
  final Map<String, Object?> timeAnchor;
}

class LabValidationIssue {
  const LabValidationIssue({
    required this.rule,
    required this.field,
    required this.message,
  });

  final String rule;

  /// The wire path, for example `lab.collected` or `entered`.
  final String field;

  /// Names no value and no Lab Test, so a logged message reveals nothing.
  final String message;
}

class LabValidationResult {
  const LabValidationResult({required this.errors, required this.warnings});

  final List<LabValidationIssue> errors;
  final List<LabValidationIssue> warnings;

  bool get accepted => errors.isEmpty;
}

/// Validates one Lab Result reading against the catalogue entry it names.
///
/// [today] is the device's local date (its time of day is ignored); a
/// collection is in the future when its date is later than today plus one
/// day. Throws [ArgumentError] when [LabResultInput.labTestKey] is not in the
/// catalogue.
LabValidationResult validateLabResult(
  LabResultInput input, {
  required DateTime today,
}) {
  final labTest = labTestByKey(input.labTestKey);
  if (labTest == null) {
    throw ArgumentError('Unknown Lab Test.');
  }
  final errors = <LabValidationIssue>[];
  final warnings = <LabValidationIssue>[];
  final lab = input.lab;

  // Collection date and time anchor.
  final collected = lab?['collected'];
  if (collected == null) {
    errors.add(
      const LabValidationIssue(
        rule: 'lab_collected_missing',
        field: 'lab.collected',
        message: 'Give the collection date.',
      ),
    );
  } else if (collected is! String || !isValidCollected(collected)) {
    errors.add(
      const LabValidationIssue(
        rule: 'lab_collected_invalid',
        field: 'lab.collected',
        message: 'Collection date must be YYYY-MM-DD or YYYY-MM-DDTHH:mm.',
      ),
    );
  } else {
    if (collected.substring(0, 10).compareTo(_latestCollectedDate(today)) > 0) {
      errors.add(
        const LabValidationIssue(
          rule: 'lab_collected_future',
          field: 'lab.collected',
          message: "Collection date can't be more than one day in the future.",
        ),
      );
    }
    if (!_timeAnchorMatches(input.timeAnchor, collected)) {
      errors.add(
        const LabValidationIssue(
          rule: 'lab_time_anchor_mismatch',
          field: 'timeAnchor',
          message: 'timeAnchor.localDateTime must match lab.collected.',
        ),
      );
    }
  }

  // Unit.
  if (resolveLabUnit(labTest, input.enteredUnit) == null) {
    errors.add(
      LabValidationIssue(
        rule: 'lab_unit_not_accepted',
        field: 'enteredUnit',
        message: 'Unit not accepted. Use ${_unitList(labTest)}.',
      ),
    );
  }

  // Value.
  final value = _canonicalEnteredNumber(input.entered.trim());
  if (value == null) {
    errors.add(
      const LabValidationIssue(
        rule: 'lab_value_invalid',
        field: 'entered',
        message: 'Enter a number, optionally after <, <=, > or >=.',
      ),
    );
  } else if (!labTest.hardBounds.contains(value)) {
    final bounds = labTest.hardBounds;
    errors.add(
      LabValidationIssue(
        rule: 'lab_value_out_of_bounds',
        field: 'entered',
        message: 'Value must be between ${bounds.min} and ${bounds.max} '
            '${labTest.unit}.',
      ),
    );
  } else if (labTest.plausibleBounds case final plausible?
      when !plausible.contains(value)) {
    warnings.add(
      const LabValidationIssue(
        rule: 'lab_value_implausible',
        field: 'entered',
        message: 'Value is unusual for this Lab Test. Check it before saving.',
      ),
    );
  }

  // Text fields.
  for (final (key, maxLength) in const <(String, int)>[
    ('printedRange', labPrintedRangeMaxLength),
    ('printedFlag', labPrintedFlagMaxLength),
    ('labName', labNameMaxLength),
  ]) {
    final text = lab?[key];
    if (text is String && text.trim().length > maxLength) {
      errors.add(
        LabValidationIssue(
          rule: 'lab_text_too_long',
          field: 'lab.$key',
          message: 'lab.$key is too long.',
        ),
      );
    }
  }

  // Report status and fasting.
  final reportStatus = lab?['reportStatus'];
  if (reportStatus != null &&
      reportStatus != ReportStatus.final_.wire &&
      reportStatus != ReportStatus.interim.wire) {
    errors.add(
      const LabValidationIssue(
        rule: 'lab_report_status_invalid',
        field: 'lab.reportStatus',
        message: 'Report status must be final or interim.',
      ),
    );
  }
  final fasting = lab?['fasting'];
  if (fasting != null && fasting != true) {
    errors.add(
      const LabValidationIssue(
        rule: 'lab_fasting_invalid',
        field: 'lab.fasting',
        message: 'Fasting must be true or empty.',
      ),
    );
  }

  return LabValidationResult(errors: errors, warnings: warnings);
}

/// `YYYY-MM-DD` of the day after [today]'s local date: the latest collection
/// date accepted. Fixed width, so it compares as a string.
String _latestCollectedDate(DateTime today) {
  final latest = DateTime.utc(today.year, today.month, today.day + 1);
  return '${latest.year.toString().padLeft(4, '0')}-'
      '${latest.month.toString().padLeft(2, '0')}-'
      '${latest.day.toString().padLeft(2, '0')}';
}

/// Whether [timeAnchor] is exactly a `localDateTime` equal to [collected]
/// expanded (`T12:00:00` for a date, `:00` seconds for a time) plus a whole
/// `timezoneOffsetMinutes` from -720 to 840, with no other non-null key.
bool _timeAnchorMatches(Map<String, Object?> timeAnchor, String collected) {
  for (final MapEntry(:key, :value) in timeAnchor.entries) {
    if (value != null &&
        key != 'localDateTime' &&
        key != 'timezoneOffsetMinutes') {
      return false;
    }
  }
  if (timeAnchor['localDateTime'] != collectedLocalDateTime(collected)) {
    return false;
  }
  final offset = timeAnchor['timezoneOffsetMinutes'];
  return offset is num &&
      offset.isFinite &&
      offset == offset.truncate() &&
      offset >= labTimezoneOffsetMinMinutes &&
      offset <= labTimezoneOffsetMaxMinutes;
}

/// The number [trimmed] states, or its Limit Result's bound; null unless it
/// is in the canonical `entered` form.
double? _canonicalEnteredNumber(String trimmed) {
  final parsed = parseEntered(trimmed);
  if (parsed == null) return null;
  if (trimmed != formatEntered(parsed.comparator, parsed.number)) return null;
  return double.parse(parsed.number);
}

/// The Lab Test's unit, then its aliases, as the message lists them.
String _unitList(LabTest labTest) =>
    <String>[labTest.unit, ...labTest.unitAliases].join(', ');
