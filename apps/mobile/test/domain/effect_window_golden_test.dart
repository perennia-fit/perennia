import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/effect/effect.dart';

/// The shared golden vector for the `Effect` window (PROTOCOLS.md §4): how
/// DURING is derived from a Protocol's declared course or a Compound's logged
/// Doses, and the before/during/after means and deltas over it. The agent
/// API's `computeEffectWindowSegments` runs the same file
/// (`apps/server/test/effect-window.golden.test.mjs`), so the app and an agent
/// never report a different window for the same data. Everything under test
/// is a pure function: nothing here touches persistence (derived, never
/// stored).
void main() {
  test('the Effect window matches the shared golden vectors', () {
    final vector = jsonDecode(
      _vectorFile('m29-effect-window.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(vector['domain'], 'effect-window');
    expect(vector['schemaVersion'], 1);
    expect(vector['schema'], 'm29-effect-window.schema.json');

    final cases = vector['cases']! as List<Object?>;
    expect(cases, isNotEmpty);

    for (final rawCase in cases) {
      final vectorCase = rawCase! as Map<String, Object?>;
      final reason = vectorCase['name']! as String;
      final input = vectorCase['input']! as Map<String, Object?>;
      final expected = vectorCase['expected']! as Map<String, Object?>;

      final now = DateTime.parse(input['now']! as String);
      final window = _windowFrom(
        input['source']! as Map<String, Object?>,
        now: now,
      );
      expect(
        _windowToJson(window),
        expected['window'],
        reason: '$reason window',
      );

      final samples = (input['samples']! as List<Object?>)
          .map((raw) {
            final sample = raw! as Map<String, Object?>;
            return EffectSample(
              at: DateTime.parse(sample['at']! as String),
              value: (sample['value']! as num).toDouble(),
            );
          })
          .toList(growable: false);

      // No derivable window means nothing can be bucketed: every segment is
      // empty, which is what the vector expects of both languages.
      const empty = EffectSegmentStats(mean: null, sampleCount: 0);
      final result = window == null
          ? const OutcomeEffectResult(
              before: empty,
              during: empty,
              after: empty,
            )
          : computeOutcomeEffect(window: window, samples: samples);

      final segments = expected['segments']! as Map<String, Object?>;
      _expectSegment(
        result.before,
        segments['before']! as Map<String, Object?>,
        '$reason before',
      );
      _expectSegment(
        result.during,
        segments['during']! as Map<String, Object?>,
        '$reason during',
      );
      _expectSegment(
        result.after,
        segments['after']! as Map<String, Object?>,
        '$reason after',
      );

      final deltas = expected['deltas']! as Map<String, Object?>;
      _expectNullableClose(
        result.duringDelta,
        deltas['during'],
        '$reason duringDelta',
      );
      _expectNullableClose(
        result.afterDelta,
        deltas['after'],
        '$reason afterDelta',
      );
      _expectNullableClose(
        result.overallDelta,
        deltas['overall'],
        '$reason overallDelta',
      );
    }
  });
}

EffectWindow? _windowFrom(Map<String, Object?> source, {required DateTime now}) {
  switch (source['kind']) {
    case 'protocol':
      final endDate = source['endDate'] as String?;
      return effectWindowForProtocol(
        startDate: DateTime.parse(source['startDate']! as String),
        endDate: endDate == null ? null : DateTime.parse(endDate),
        now: now,
      );
    case 'compound':
      return effectWindowForDoseTimes(
        (source['doseTimes']! as List<Object?>)
            .map((raw) => DateTime.parse(raw! as String)),
        now: now,
      );
    default:
      throw StateError('Unknown Effect window source: ${source['kind']}.');
  }
}

Map<String, Object?>? _windowToJson(EffectWindow? window) {
  if (window == null) {
    return null;
  }
  String iso(DateTime instant) => instant.toUtc().toIso8601String();
  final duringEnd = window.duringEnd;
  return <String, Object?>{
    'duringStart': iso(window.duringStart),
    'duringEnd': duringEnd == null ? null : iso(duringEnd),
    'duringEndOrNow': iso(window.duringEndOrNow),
    'beforeStart': iso(window.beforeStart),
    'afterEnd': iso(window.afterEnd),
  };
}

void _expectSegment(
  EffectSegmentStats actual,
  Map<String, Object?> expected,
  String reason,
) {
  _expectNullableClose(actual.mean, expected['mean'], '$reason mean');
  expect(actual.sampleCount, expected['count'], reason: '$reason count');
}

void _expectNullableClose(double? actual, Object? expectedRaw, String reason) {
  if (expectedRaw == null) {
    expect(actual, isNull, reason: reason);
    return;
  }
  final expected = (expectedRaw as num).toDouble();
  expect(actual, isNotNull, reason: reason);
  expect(actual!, closeTo(expected, 1e-6), reason: reason);
}

/// Walks up from the current working directory to the shared vector,
/// tolerant of tests being invoked from either the repo root or
/// `apps/mobile` (mirrors `routine_up_next_golden_test.dart`).
File _vectorFile(String name) {
  var directory = Directory.current;
  for (var depth = 0; depth < 6; depth += 1) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}packages'
      '${Platform.pathSeparator}golden-vectors'
      '${Platform.pathSeparator}vectors'
      '${Platform.pathSeparator}$name',
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Golden vector not found: $name.');
}
