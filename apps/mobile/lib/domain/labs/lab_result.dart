/// The `lab` object a Lab Result carries in its `valueJson`, and the canonical
/// `entered` form of a Lab Result's value (docs/designs/lab-results.md,
/// "Storage"). The TypeScript twin is `apps/server/src/lab-results.ts`; the
/// two must agree, which the m43 golden vectors pin for [decodeLab].
library;

import 'dart:convert';

/// The comparator of a Limit Result, with its ASCII wire form.
enum LabComparator {
  lt('<'),
  le('<='),
  gt('>'),
  ge('>=');

  const LabComparator(this.wire);

  /// The stored and canonical `entered` spelling: always ASCII, so `≤` is
  /// never stored.
  final String wire;

  /// The comparator whose [wire] is [value], or null.
  static LabComparator? fromWire(Object? value) {
    for (final comparator in LabComparator.values) {
      if (comparator.wire == value) return comparator;
    }
    return null;
  }
}

/// The bound of a Limit Result (`< 1`). The bound lives only here: a Limit
/// Result's `value` and `scalarValue` are null.
class LabLimit {
  const LabLimit({required this.comparator, required this.bound});

  final LabComparator comparator;
  final num bound;

  @override
  bool operator ==(Object other) =>
      other is LabLimit &&
      other.comparator == comparator &&
      other.bound == bound;

  @override
  int get hashCode => Object.hash(comparator, bound);
}

/// Whether a lab printed the result as final or interim.
///
/// Not an enum: a `reportStatus` written by a later build is kept as an
/// unknown status carrying its text, so a reader never fails on it. An
/// unknown status ranks as interim in the collapse, so a known `final`
/// always beats it.
final class ReportStatus {
  const ReportStatus._(this.wire);

  /// A status this build does not know, keeping its stored text.
  const ReportStatus.unknown(String text) : wire = text;

  static const ReportStatus final_ = ReportStatus._('final');
  static const ReportStatus interim = ReportStatus._('interim');

  /// The stored text.
  final String wire;

  bool get isFinal => wire == final_.wire;

  /// Whether this build knows the status (`final` or `interim`).
  bool get isKnown => wire == final_.wire || wire == interim.wire;

  /// The status for stored [text]: a known one, or an unknown one keeping it.
  static ReportStatus fromWire(String text) => switch (text) {
        'final' => final_,
        'interim' => interim,
        _ => ReportStatus.unknown(text),
      };

  @override
  bool operator ==(Object other) => other is ReportStatus && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;

  @override
  String toString() => 'ReportStatus($wire)';
}

/// The `lab` object of a Lab Result. Text fields are stored trimmed, with a
/// blank written as null; nothing here names the patient.
class LabFields {
  const LabFields({
    required this.collected,
    this.limit,
    this.printedRange,
    this.printedFlag,
    this.reportStatus = ReportStatus.final_,
    this.fasting,
    this.labName,
  });

  /// The collection date (`YYYY-MM-DD`) or date and time (`YYYY-MM-DDTHH:mm`),
  /// local, as printed, with no offset. Part of a result's identity.
  final String collected;

  /// Set only for a Limit Result. Derived from `entered` by the normaliser.
  final LabLimit? limit;

  /// The range text, as printed.
  final String? printedRange;

  /// The flag, as printed (`+`, `--`, `H`).
  final String? printedFlag;

  final ReportStatus reportStatus;

  /// `true` when the report says the sample was fasting; otherwise null.
  final bool? fasting;

  /// The lab, never the patient.
  final String? labName;
}

/// The stored `lab` object for [fields], with keys in exactly the order
/// collected, limit, printedRange, printedFlag, reportStatus, fasting,
/// labName, and every absent optional key written as null.
Map<String, Object?> encodeLab(LabFields fields) {
  final limit = fields.limit;
  return <String, Object?>{
    'collected': fields.collected,
    'limit': limit == null
        ? null
        : <String, Object?>{
            'comparator': limit.comparator.wire,
            'bound': limit.bound,
          },
    'printedRange': fields.printedRange,
    'printedFlag': fields.printedFlag,
    'reportStatus': fields.reportStatus.wire,
    'fasting': fields.fasting,
    'labName': fields.labName,
  };
}

/// Decodes a stored `lab` object; the one rule every reader uses.
///
/// Returns null unless [value] is a map whose `collected` passes
/// [isValidCollected]: such a reading is treated as lab-less (the collapse
/// keeps it in a group of its own). Otherwise decoding is tolerant, so a row
/// written by a later build still reads:
///
/// * a missing or null `reportStatus` decodes as final; any other text is kept
///   as an unknown status (a non-string is kept as its JSON text);
/// * a `limit` without a known comparator and a finite numeric bound, a
///   non-string text field and a `fasting` other than `true` decode as null;
/// * unknown keys are dropped.
LabFields? decodeLab(Object? value) {
  if (value is! Map) return null;
  final collected = value['collected'];
  if (collected is! String || !isValidCollected(collected)) return null;
  final rawStatus = value['reportStatus'];
  final reportStatus = switch (rawStatus) {
    null => ReportStatus.final_,
    final String text => ReportStatus.fromWire(text),
    _ => ReportStatus.unknown(jsonEncode(rawStatus)),
  };
  return LabFields(
    collected: collected,
    limit: _decodeLimit(value['limit']),
    printedRange: _stringOrNull(value['printedRange']),
    printedFlag: _stringOrNull(value['printedFlag']),
    reportStatus: reportStatus,
    fasting: value['fasting'] == true ? true : null,
    labName: _stringOrNull(value['labName']),
  );
}

LabLimit? _decodeLimit(Object? value) {
  if (value is! Map) return null;
  final comparator = LabComparator.fromWire(value['comparator']);
  final bound = value['bound'];
  if (comparator == null || bound is! num || !bound.isFinite) return null;
  return LabLimit(comparator: comparator, bound: bound);
}

String? _stringOrNull(Object? value) => value is String ? value : null;

/// The canonical `entered` text: `"{comparator} {value}"` with the ASCII
/// comparator and one space (`"< 1"`) for a Limit Result, else [value].
String formatEntered(LabComparator? comparator, String value) =>
    comparator == null ? value : '${comparator.wire} $value';

/// The number grammar m12 uses for an entered Metric value (see
/// `apps/server/src/metric-reading-normalization.ts`, `DECIMAL_LITERAL`).
final RegExp _decimalLiteral =
    RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$');

/// Splits [entered] into an optional comparator and the number text.
///
/// Accepts a leading `<`, `<=`, `≤`, `>`, `>=` or `≥`, optionally followed by
/// one space, then a finite number in the m12 grammar; `≤` and `≥` map to
/// [LabComparator.le] and [LabComparator.ge]. The whole string must match:
/// callers trim it first, as the normaliser does. Returns null otherwise.
({LabComparator? comparator, String number})? parseEntered(String entered) {
  LabComparator? comparator;
  var rest = entered;
  // Two-character comparators first, so `<=` is not read as `<` and `=`.
  for (final (prefix, parsed) in const <(String, LabComparator)>[
    ('<=', LabComparator.le),
    ('>=', LabComparator.ge),
    ('≤', LabComparator.le),
    ('≥', LabComparator.ge),
    ('<', LabComparator.lt),
    ('>', LabComparator.gt),
  ]) {
    if (rest.startsWith(prefix)) {
      comparator = parsed;
      rest = rest.substring(prefix.length);
      if (rest.startsWith(' ')) rest = rest.substring(1);
      break;
    }
  }
  if (!_decimalLiteral.hasMatch(rest)) return null;
  final parsed = double.tryParse(rest);
  if (parsed == null || !parsed.isFinite) return null;
  return (comparator: comparator, number: rest);
}

final RegExp _collectedPattern =
    RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?$');

/// Whether [collected] is `YYYY-MM-DD` or `YYYY-MM-DDTHH:mm` naming a real
/// date (and, with a time, a real time from 00:00 to 23:59).
bool isValidCollected(String collected) {
  final match = _collectedPattern.firstMatch(collected);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > _daysInMonth(year, month)) {
    return false;
  }
  final hour = match.group(4);
  if (hour == null) return true;
  final minute = int.parse(match.group(5)!);
  return int.parse(hour) <= 23 && minute <= 59;
}

int _daysInMonth(int year, int month) {
  const days = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0))) {
    return 29;
  }
  return days[month - 1];
}

/// The time anchor's `localDateTime` for [collected]: a date only becomes
/// `T12:00:00`, a date and time gains `:00` seconds. Throws [ArgumentError]
/// when [collected] is not valid.
String collectedLocalDateTime(String collected) {
  if (!isValidCollected(collected)) {
    throw ArgumentError.value(
        collected, 'collected', 'Invalid collection date.');
  }
  return collected.length == 10 ? '${collected}T12:00:00' : '$collected:00';
}
