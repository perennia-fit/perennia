import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/effect/effect.dart';

/// the shared golden vector for the `Effect` window's before/during/
/// after delta computation (PROTOCOLS.md §4). Fixed against a sample dataset
/// so a later M30 agent surface can reuse the identical fixture and expect
/// the identical numbers — the same "never disagree" discipline as the other
/// golden-vectored analytics (AGENTS.md §8.2). Everything under test is a
/// pure function: nothing here touches persistence (derived,
/// never stored).
void main() {
  test('computeOutcomeEffect matches the shared golden vectors', () {
    final vectorFile = _vectorFile('effect_window_golden.json');
    final vector =
        jsonDecode(vectorFile.readAsStringSync()) as Map<String, Object?>;
    expect(vector['name'], 'm29-effect-window-deltas');

    final cases = vector['cases']! as List<Object?>;
    expect(cases, isNotEmpty);

    for (final rawCase in cases) {
      final vectorCase = rawCase! as Map<String, Object?>;
      final reason = vectorCase['name']! as String;

      final windowJson = vectorCase['window']! as Map<String, Object?>;
      final window = EffectWindow(
        duringStart: DateTime.parse(windowJson['duringStart']! as String),
        duringEnd: windowJson['duringEnd'] == null
            ? null
            : DateTime.parse(windowJson['duringEnd']! as String),
        now: DateTime.parse(windowJson['now']! as String),
      );

      final samples = (vectorCase['samples']! as List<Object?>)
          .map((raw) {
            final sample = raw! as Map<String, Object?>;
            return EffectSample(
              at: DateTime.parse(sample['at']! as String),
              value: (sample['value']! as num).toDouble(),
            );
          })
          .toList(growable: false);

      final result = computeOutcomeEffect(window: window, samples: samples);
      final expected = vectorCase['expected']! as Map<String, Object?>;

      _expectSegment(
        result.before,
        expected['before']! as Map<String, Object?>,
        '$reason before',
      );
      _expectSegment(
        result.during,
        expected['during']! as Map<String, Object?>,
        '$reason during',
      );
      _expectSegment(
        result.after,
        expected['after']! as Map<String, Object?>,
        '$reason after',
      );

      _expectNullableClose(
        result.duringDelta,
        expected['duringDelta'],
        '$reason duringDelta',
      );
      _expectNullableClose(
        result.afterDelta,
        expected['afterDelta'],
        '$reason afterDelta',
      );
      _expectNullableClose(
        result.overallDelta,
        expected['overallDelta'],
        '$reason overallDelta',
      );
    }
  });
}

void _expectSegment(
  EffectSegmentStats actual,
  Map<String, Object?> expected,
  String reason,
) {
  _expectNullableClose(actual.mean, expected['mean'], '$reason mean');
  expect(actual.sampleCount, expected['sampleCount'],
      reason: '$reason sampleCount');
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

/// Walks up from the current working directory to find the fixture,
/// tolerant of tests being invoked from either the repo root or
/// `apps/mobile` (mirrors the pattern in `dose_validation_test.dart`).
File _vectorFile(String name) {
  var directory = Directory.current;
  for (var depth = 0; depth < 6; depth += 1) {
    final direct = File(
      '${directory.path}${Platform.pathSeparator}test'
      '${Platform.pathSeparator}fixtures'
      '${Platform.pathSeparator}$name',
    );
    if (direct.existsSync()) {
      return direct;
    }
    final fromRepoRoot = File(
      '${directory.path}${Platform.pathSeparator}apps'
      '${Platform.pathSeparator}mobile'
      '${Platform.pathSeparator}test'
      '${Platform.pathSeparator}fixtures'
      '${Platform.pathSeparator}$name',
    );
    if (fromRepoRoot.existsSync()) {
      return fromRepoRoot;
    }
    directory = directory.parent;
  }
  throw StateError('Effect golden vector not found: $name.');
}
