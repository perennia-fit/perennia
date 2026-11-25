import 'dart:convert';

import '../labs/lab_result.dart';
import '../labs/lab_test.dart';
import '../labs/lab_test_catalogue.generated.dart';

/// Normalises one Metric Reading to its stored columns; the TypeScript twin is
/// `normalizeMetricReading` in apps/server/src/metric-reading-normalization.ts,
/// and the m12 golden vectors pin both.
///
/// `metric.labTestKey` (optional) marks a Lab Metric, whose scalar `value` may
/// carry a `lab` object; see [_normalizeLabValue]. A `lab` on any other
/// Metric's scalar value throws.
Map<String, Object?> normalizeMetricReading(Map<String, Object?> input) {
  final metric = _requiredMap(input, 'metric');
  final value = _requiredMap(input, 'value');
  final timeAnchor = _requiredMap(input, 'timeAnchor');
  final valueShape = _requiredString(metric, 'valueShape');
  final unit = _requiredString(metric, 'unit');
  final labTestKey = metric['labTestKey'];
  if (labTestKey != null && labTestKey is! String) {
    throw ArgumentError('labTestKey must be a string.');
  }
  if (_requiredString(value, 'shape') != valueShape) {
    throw ArgumentError('Reading value shape must match Metric value shape.');
  }

  final warnings = <String>[];
  final normalizedValue = labTestKey is String && valueShape == 'scalar'
      ? _normalizeLabValue(labTestKey: labTestKey, unit: unit, value: value)
      : _normalizeValue(
          valueShape: valueShape,
          unit: unit,
          value: value,
        );
  final normalizedAnchor = _normalizeTimeAnchor(timeAnchor, warnings);

  return <String, Object?>{
    'valueShape': valueShape,
    'unit': unit,
    'valueJson': normalizedValue.valueJson,
    'scalarValue': normalizedValue.scalarValue,
    'atTime': normalizedAnchor.atTime,
    'windowStartedAt': normalizedAnchor.windowStartedAt,
    'windowEndedAt': normalizedAnchor.windowEndedAt,
    'warnings': warnings,
  };
}

_NormalizedReadingValue _normalizeValue({
  required String valueShape,
  required String unit,
  required Map<String, Object?> value,
}) {
  switch (valueShape) {
    case 'scalar':
      if (value['lab'] != null) {
        throw ArgumentError('Lab fields need a Lab Metric.');
      }
      final normalized = _normalizeNumericValue(
        entered: _requiredString(value, 'entered'),
        enteredUnit: (value['unit'] as String?) ?? unit,
        targetUnit: unit,
      );
      return _NormalizedReadingValue(
        valueJson: jsonEncode(<String, Object?>{
          'shape': 'scalar',
          'unit': unit,
          'value': normalized.value,
          'entered': normalized.entered,
          'enteredUnit': normalized.enteredUnit,
        }),
        scalarValue: normalized.value,
      );
    case 'structured':
      final fields = _requiredMap(value, 'fields');
      final normalizedFields = <String, Object?>{};
      final fieldNames = fields.keys.toList()..sort();
      for (final fieldName in fieldNames) {
        final field = _requiredMap(fields, fieldName);
        final normalized = _normalizeNumericValue(
          entered: _requiredString(field, 'entered'),
          enteredUnit: (field['unit'] as String?) ?? unit,
          targetUnit: unit,
        );
        normalizedFields[fieldName] = <String, Object?>{
          'unit': unit,
          'value': normalized.value,
          'entered': normalized.entered,
          'enteredUnit': normalized.enteredUnit,
        };
      }
      return _NormalizedReadingValue(
        valueJson: jsonEncode(<String, Object?>{
          'shape': 'structured',
          'fields': normalizedFields,
        }),
        scalarValue: null,
      );
    case 'series':
      final samples = _requiredList(value, 'samples')
          .map((sample) => sample! as Map<String, Object?>)
          .toList(growable: false)
        ..sort((left, right) {
          final leftOffset = _requiredNumber(left, 'offsetSeconds');
          final rightOffset = _requiredNumber(right, 'offsetSeconds');
          return leftOffset.compareTo(rightOffset);
        });
      final normalizedSamples = samples.map((sample) {
        final normalized = _normalizeNumericValue(
          entered: _requiredString(sample, 'entered'),
          enteredUnit: (sample['unit'] as String?) ?? unit,
          targetUnit: unit,
        );
        return <String, Object?>{
          'offsetSeconds': _canonicalNumber(
            _requiredNumber(sample, 'offsetSeconds'),
          ),
          'value': normalized.value,
          'entered': normalized.entered,
          'enteredUnit': normalized.enteredUnit,
        };
      }).toList(growable: false);
      return _NormalizedReadingValue(
        valueJson: jsonEncode(<String, Object?>{
          'shape': 'series',
          'unit': unit,
          'samples': normalizedSamples,
        }),
        scalarValue: null,
      );
    default:
      throw ArgumentError.value(valueShape, 'valueShape', 'Unknown shape.');
  }
}

/// A Lab Result's value (docs/designs/lab-results.md, "The normaliser"). Every
/// writer validates first (`validateLabResult`), so each throw here is a
/// defensive check a writer reaching it has a bug for; no message names a
/// value. The steps:
///
/// 1. the entered unit (`value.unit`, else the Metric's) must be the Lab
///    Test's unit or an alias under [foldUnit]; it is stored as sent and never
///    converted, so `value` is the entered number;
/// 2. a leading comparator (`<`, `<=`, `≤`, `>`, `>=`, `≥`, optionally then a
///    space) makes a Limit Result: `value` and `scalarValue` are null, the
///    bound lives in `lab.limit`, `entered` takes the canonical `"< 1"` form,
///    and any `limit` sent is replaced;
/// 3. the text fields are trimmed with a blank (or a non-string) written as
///    null, an absent `reportStatus` becomes `final`, and `lab` is written
///    last, in [encodeLab]'s key order.
_NormalizedReadingValue _normalizeLabValue({
  required String labTestKey,
  required String unit,
  required Map<String, Object?> value,
}) {
  final labTest = labTestByKey(labTestKey);
  if (labTest == null) {
    throw ArgumentError('Unknown Lab Test.');
  }
  final enteredUnit = (value['unit'] as String?) ?? unit;
  if (resolveLabUnit(labTest, enteredUnit) == null) {
    throw ArgumentError('Lab result unit not accepted.');
  }
  final rawLab = value['lab'];
  final lab = rawLab is Map ? Map<String, Object?>.from(rawLab) : null;
  final collected = lab?['collected'];
  if (collected is! String || !isValidCollected(collected)) {
    throw ArgumentError('Lab result collected date is invalid.');
  }
  final parsed = parseEntered(_requiredString(value, 'entered').trim());
  if (parsed == null) {
    throw ArgumentError('Metric Reading value must be finite.');
  }
  final number = _canonicalNumber(double.parse(parsed.number)) as num;
  final comparator = parsed.comparator;
  final reportStatus = lab!['reportStatus'];
  final valueOrNull = comparator == null ? number : null;
  return _NormalizedReadingValue(
    valueJson: jsonEncode(<String, Object?>{
      'shape': 'scalar',
      'unit': unit,
      'value': valueOrNull,
      'entered': formatEntered(comparator, parsed.number),
      'enteredUnit': enteredUnit,
      'lab': encodeLab(
        LabFields(
          collected: collected,
          limit: comparator == null
              ? null
              : LabLimit(comparator: comparator, bound: number),
          printedRange: _labText(lab['printedRange']),
          printedFlag: _labText(lab['printedFlag']),
          reportStatus: reportStatus is String
              ? ReportStatus.fromWire(reportStatus)
              : ReportStatus.final_,
          fasting: lab['fasting'] == true ? true : null,
          labName: _labText(lab['labName']),
        ),
      ),
    }),
    scalarValue: valueOrNull,
  );
}

/// A text field trimmed, with a blank or a non-string as null.
String? _labText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

_NormalizedNumericValue _normalizeNumericValue({
  required String entered,
  required String enteredUnit,
  required String targetUnit,
}) {
  final trimmed = entered.trim();
  final parsed = double.tryParse(trimmed);
  if (parsed == null || !parsed.isFinite) {
    throw ArgumentError.value(
      entered,
      'entered',
      'Metric Reading value must be finite.',
    );
  }
  return _NormalizedNumericValue(
    entered: trimmed,
    enteredUnit: enteredUnit,
    value: _canonicalNumber(_convertUnit(parsed, enteredUnit, targetUnit)),
  );
}

_NormalizedTimeAnchor _normalizeTimeAnchor(
  Map<String, Object?> timeAnchor,
  List<String> warnings,
) {
  final atTime = timeAnchor['atTime'] as String?;
  final windowStartedAt = timeAnchor['windowStartedAt'] as String?;
  final windowEndedAt = timeAnchor['windowEndedAt'] as String?;
  final hasWindow = windowStartedAt != null || windowEndedAt != null;
  if (hasWindow) {
    if (atTime != null) {
      warnings.add('time_anchor_window_preferred');
    }
    if (windowStartedAt == null || windowEndedAt == null) {
      throw ArgumentError('Window anchors require start and end times.');
    }
    var start = DateTime.parse(windowStartedAt).toUtc();
    var end = DateTime.parse(windowEndedAt).toUtc();
    if (end.isBefore(start)) {
      final originalStart = start;
      start = end;
      end = originalStart;
      warnings.add('window_bounds_reordered');
    }
    return _NormalizedTimeAnchor(
      atTime: null,
      windowStartedAt: _isoUtc(start),
      windowEndedAt: _isoUtc(end),
    );
  }
  if (atTime != null) {
    return _NormalizedTimeAnchor(
      atTime: _isoUtc(DateTime.parse(atTime).toUtc()),
      windowStartedAt: null,
      windowEndedAt: null,
    );
  }
  final localDateTime = timeAnchor['localDateTime'] as String?;
  if (localDateTime != null) {
    final offsetMinutes = _requiredNumber(
      timeAnchor,
      'timezoneOffsetMinutes',
    ).toInt();
    final localUtc = _parseLocalDateTimeAsUtc(localDateTime);
    return _NormalizedTimeAnchor(
      atTime: _isoUtc(localUtc.subtract(Duration(minutes: offsetMinutes))),
      windowStartedAt: null,
      windowEndedAt: null,
    );
  }
  throw ArgumentError('Reading requires an instant or window time anchor.');
}

DateTime _parseLocalDateTimeAsUtc(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?$',
  ).firstMatch(value);
  if (match == null) {
    throw ArgumentError.value(value, 'localDateTime', 'Invalid local time.');
  }
  final fraction = match.group(7) ?? '0';
  final microseconds = int.parse(fraction.padRight(6, '0'));
  return DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
    microseconds ~/ Duration.microsecondsPerMillisecond,
    microseconds % Duration.microsecondsPerMillisecond,
  );
}

String _isoUtc(DateTime value) => value.toUtc().toIso8601String();

num _convertUnit(double value, String from, String to) {
  if (from == to) {
    return value;
  }
  if (from == 'pound' && to == 'kilogram') {
    return value * 0.45359237;
  }
  if (from == 'kilogram' && to == 'pound') {
    return value / 0.45359237;
  }
  if (from == 'inch' && to == 'centimeter') {
    return value * 2.54;
  }
  if (from == 'centimeter' && to == 'inch') {
    return value / 2.54;
  }
  throw ArgumentError('Cannot convert Metric Reading unit $from to $to.');
}

Object _canonicalNumber(num value) {
  if (value is double) {
    final rounded = double.parse(value.toStringAsFixed(10));
    if (rounded == rounded.roundToDouble()) {
      return rounded.round();
    }
    return rounded;
  }
  return value;
}

Map<String, Object?> _requiredMap(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw ArgumentError.value(value, key, 'Expected an object.');
}

List<Object?> _requiredList(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is List) {
    return List<Object?>.from(value);
  }
  throw ArgumentError.value(value, key, 'Expected a list.');
}

String _requiredString(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is String) {
    return value;
  }
  throw ArgumentError.value(value, key, 'Expected a string.');
}

double _requiredNumber(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is num) {
    return value.toDouble();
  }
  throw ArgumentError.value(value, key, 'Expected a number.');
}

class _NormalizedReadingValue {
  const _NormalizedReadingValue({
    required this.valueJson,
    required this.scalarValue,
  });

  final String valueJson;
  final Object? scalarValue;
}

class _NormalizedNumericValue {
  const _NormalizedNumericValue({
    required this.entered,
    required this.enteredUnit,
    required this.value,
  });

  final String entered;
  final String enteredUnit;
  final Object value;
}

class _NormalizedTimeAnchor {
  const _NormalizedTimeAnchor({
    required this.atTime,
    required this.windowStartedAt,
    required this.windowEndedAt,
  });

  final String? atTime;
  final String? windowStartedAt;
  final String? windowEndedAt;
}
