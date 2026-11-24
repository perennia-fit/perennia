/// Default Range selection, Printed Range parsing and range position
/// (docs/designs/lab-results.md, "Default Ranges"). All pure and computed on
/// read: nothing here is stored or synced, and no server reader computes it
/// (Agents get Default Ranges as catalogue data). Pinned by the Dart-only
/// m44 golden vectors (`m44-lab-default-range.json`).
library;

import '../profile/user_profile.dart';
import 'lab_result.dart';
import 'lab_test.dart';

/// A range parsed from a Printed Range, or a Default Range's bounds. A null
/// side is unbounded; its inclusivity flag is then `true` and has no effect.
class ParsedRange {
  const ParsedRange({
    this.low,
    this.lowInclusive = true,
    this.high,
    this.highInclusive = true,
  });

  /// A Default Range's bounds, which are always inclusive.
  factory ParsedRange.fromDefaultRange(DefaultRange range) =>
      ParsedRange(low: range.low, high: range.high);

  final num? low;
  final bool lowInclusive;
  final num? high;
  final bool highInclusive;

  @override
  bool operator ==(Object other) =>
      other is ParsedRange &&
      other.low == low &&
      other.lowInclusive == lowInclusive &&
      other.high == high &&
      other.highInclusive == highInclusive;

  @override
  int get hashCode => Object.hash(low, lowInclusive, high, highInclusive);

  @override
  String toString() => 'ParsedRange(${lowInclusive ? '[' : '('}$low, '
      '$high${highInclusive ? ']' : ')'})';
}

/// The Default Range of [labTest] for a result, or null.
///
/// 1. A non-blank [printedRange] means there is none: what the lab printed
///    always wins.
/// 2. Entries for `any` sex are kept; an entry for one sex is kept only when
///    [sex] equals it, so it never shows when sex is unknown.
/// 3. Entries without an age band are kept; a banded entry is kept only when
///    [age] is inside it (both ends inclusive, a null end unbounded), so it
///    never shows when the birth year is unknown.
/// 4. Exactly one entry left is the Default Range; none or several is none,
///    because guessing between two general ranges would be worse than
///    showing neither.
///
/// [age] is `UserProfile.ageAt` at the result's `collected` date.
DefaultRange? defaultRangeFor(
  LabTest labTest,
  String? printedRange,
  ProfileSex? sex,
  int? age,
) {
  if (printedRange != null && printedRange.trim().isNotEmpty) return null;
  final kept = <DefaultRange>[
    for (final entry in labTest.defaultRanges)
      if (_sexMatches(entry.sex, sex) && _ageMatches(entry, age)) entry,
  ];
  return kept.length == 1 ? kept.single : null;
}

bool _sexMatches(DefaultRangeSex entrySex, ProfileSex? sex) {
  if (entrySex == DefaultRangeSex.any) return true;
  if (sex == null) return false;
  return entrySex.name == sex.wireName;
}

bool _ageMatches(DefaultRange entry, int? age) {
  final ageMin = entry.ageMin;
  final ageMax = entry.ageMax;
  if (ageMin == null && ageMax == null) return true;
  if (age == null) return false;
  return (ageMin == null || age >= ageMin) && (ageMax == null || age <= ageMax);
}

/// The number grammar: `-?digits(.digits)?`. A comma is never a decimal
/// separator, so `4,5` does not parse.
const String _number = r'(-?\d+(?:\.\d+)?)';

final RegExp _whitespaceRun = RegExp(r'\s+');

final RegExp _between = RegExp('^$_number ?(?:-|–|—) ?$_number\$');
final RegExp _betweenTo = RegExp('^$_number to $_number\$');
final RegExp _highInclusive = RegExp('^(?:<= ?|≤ ?|up to )$_number\$');
final RegExp _highExclusive =
    RegExp('^(?:< ?|under |below |less than )$_number\$');
final RegExp _lowInclusive = RegExp('^(?:>= ?|≥ ?)$_number\$');
final RegExp _lowExclusive =
    RegExp('^(?:> ?|over |above |more than |greater than )$_number\$');

/// The range a Printed Range [text] states, or null when it states none this
/// grammar knows; the text is then shown as printed, with no position.
///
/// Trim, strip one pair of surrounding parentheses or square brackets, trim
/// again; match case-insensitively, with runs of whitespace as one space and
/// spaces around a symbol optional. The whole text must match one form, so
/// trailing text (a unit, a word) means it does not parse:
///
/// * `a-b`, `a–b`, `a—b`, `a to b`: both sides inclusive; null if `a > b`;
/// * `< b`, `under b`, `below b`, `less than b`: high, exclusive;
/// * `<= b`, `≤ b`, `up to b`: high, inclusive;
/// * `> a`, `over a`, `above a`, `more than a`, `greater than a`: low,
///   exclusive;
/// * `>= a`, `≥ a`: low, inclusive.
ParsedRange? parsePrintedRange(String text) {
  var normalized = text.trim();
  if (normalized.length >= 2 &&
      ((normalized.startsWith('(') && normalized.endsWith(')')) ||
          (normalized.startsWith('[') && normalized.endsWith(']')))) {
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }
  normalized = normalized.toLowerCase().replaceAll(_whitespaceRun, ' ');

  final between =
      _between.firstMatch(normalized) ?? _betweenTo.firstMatch(normalized);
  if (between != null) {
    final low = num.tryParse(between.group(1)!);
    final high = num.tryParse(between.group(2)!);
    if (low == null || high == null || low > high) return null;
    return ParsedRange(low: low, high: high);
  }
  final highInclusive = _highInclusive.firstMatch(normalized);
  if (highInclusive != null) {
    return _oneSide(highInclusive, isLow: false, inclusive: true);
  }
  final highExclusive = _highExclusive.firstMatch(normalized);
  if (highExclusive != null) {
    return _oneSide(highExclusive, isLow: false, inclusive: false);
  }
  final lowInclusive = _lowInclusive.firstMatch(normalized);
  if (lowInclusive != null) {
    return _oneSide(lowInclusive, isLow: true, inclusive: true);
  }
  final lowExclusive = _lowExclusive.firstMatch(normalized);
  if (lowExclusive != null) {
    return _oneSide(lowExclusive, isLow: true, inclusive: false);
  }
  return null;
}

ParsedRange? _oneSide(
  RegExpMatch match, {
  required bool isLow,
  required bool inclusive,
}) {
  final bound = num.tryParse(match.group(1)!);
  if (bound == null) return null;
  return isLow
      ? ParsedRange(low: bound, lowInclusive: inclusive)
      : ParsedRange(high: bound, highInclusive: inclusive);
}

/// A Lab Result's value as positioned: a number, or the bound of a Limit
/// Result, which is never treated as equal to its bound.
sealed class LabValue {
  const LabValue();
}

class LabNumber extends LabValue {
  const LabNumber(this.value);

  final num value;
}

class LabLimitValue extends LabValue {
  const LabLimitValue(this.limit);

  final LabLimit limit;
}

/// Where a result sits against a range. Shown as words, never as colour
/// alone, and never as "normal" or "abnormal".
enum RangePosition { below, within, above, unknown }

/// The position of [value] against [range]. A missing side is unbounded, and
/// each side's inclusivity is honoured: equal to an inclusive bound is inside
/// it, equal to an exclusive bound is outside it.
///
/// * A number: `below` if under the low side, `above` if over the high side,
///   otherwise `within`.
/// * `< b` or `<= b`: `below` if every possible value is under the low side;
///   `within` if there is no low side and every possible value is inside the
///   high side; otherwise `unknown`.
/// * `> a` or `>= a`: `above` if every possible value is over the high side;
///   `within` if there is no high side and every possible value is inside the
///   low side; otherwise `unknown`.
///
/// So against an inclusive low of 1, `< 1` is below and `<= 1` is unknown.
RangePosition rangePosition(LabValue value, ParsedRange range) {
  final low = range.low;
  final high = range.high;
  switch (value) {
    case LabNumber(value: final v):
      if (low != null && (range.lowInclusive ? v < low : v <= low)) {
        return RangePosition.below;
      }
      if (high != null && (range.highInclusive ? v > high : v >= high)) {
        return RangePosition.above;
      }
      return RangePosition.within;
    case LabLimitValue(limit: final limit):
      final bound = limit.bound;
      switch (limit.comparator) {
        case LabComparator.lt:
        case LabComparator.le:
          // Every possible value is below `bound`, or at it for `<=`.
          final attained = limit.comparator == LabComparator.le;
          if (low != null) {
            final allUnder =
                attained && range.lowInclusive ? bound < low : bound <= low;
            return allUnder ? RangePosition.below : RangePosition.unknown;
          }
          if (high == null) return RangePosition.within;
          final allInside =
              attained && !range.highInclusive ? bound < high : bound <= high;
          return allInside ? RangePosition.within : RangePosition.unknown;
        case LabComparator.gt:
        case LabComparator.ge:
          // Every possible value is above `bound`, or at it for `>=`.
          final attained = limit.comparator == LabComparator.ge;
          if (high != null) {
            final allOver =
                attained && range.highInclusive ? bound > high : bound >= high;
            return allOver ? RangePosition.above : RangePosition.unknown;
          }
          if (low == null) return RangePosition.within;
          final allInside =
              attained && !range.lowInclusive ? bound > low : bound >= low;
          return allInside ? RangePosition.within : RangePosition.unknown;
      }
  }
}

/// Which range a result was positioned against.
enum RangeSource { printed, general }

/// The position a result shows, and which range it came from, or null when
/// it shows none.
///
/// A [printedRange] that parses is used, unless the Lab Test's [kind] is
/// `riskTarget`: a guideline target is not a reference interval, so such a
/// result is never positioned. Otherwise the [defaultRange] (from
/// [defaultRangeFor], which is none whenever a Printed Range exists) is used
/// with inclusive bounds. With neither, there is no position.
({RangePosition position, RangeSource source})? resultPosition({
  required LabValue value,
  String? printedRange,
  required PrintedRangeKind kind,
  DefaultRange? defaultRange,
}) {
  final parsed = printedRange == null ? null : parsePrintedRange(printedRange);
  if (parsed != null) {
    if (kind == PrintedRangeKind.riskTarget) return null;
    return (
      position: rangePosition(value, parsed),
      source: RangeSource.printed,
    );
  }
  if (defaultRange != null) {
    return (
      position:
          rangePosition(value, ParsedRange.fromDefaultRange(defaultRange)),
      source: RangeSource.general,
    );
  }
  return null;
}
