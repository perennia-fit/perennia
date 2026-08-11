import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/metrics/reading_normalization.dart';

void main() {
  group('Metric Reading normalization', () {
    test('matches the shared golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m12-reading-normalization.json').readAsString(),
      ) as Map<String, Object?>;
      final cases = vector['cases']! as List<Object?>;

      expect(cases, isNotEmpty);
      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;

        _expectNormalizedOutput(
          normalizeMetricReading(input),
          expected,
          reason: caseData['name']! as String,
        );
      }
    });

    test('drift check catches a perturbed normalized output', () async {
      final vector = jsonDecode(
        await _vectorFile('m12-reading-normalization.json').readAsString(),
      ) as Map<String, Object?>;
      final firstCase =
          (vector['cases']! as List<Object?>).first! as Map<String, Object?>;
      final expected = firstCase['expected']! as Map<String, Object?>;
      final perturbed = Map<String, Object?>.from(expected)
        ..['valueJson'] = '{}';

      expect(
        () => _expectNormalizedOutput(
          perturbed,
          expected,
          reason: 'perturbed output',
        ),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}

void _expectNormalizedOutput(
  Map<String, Object?> actual,
  Map<String, Object?> expected, {
  required String reason,
}) {
  expect(actual, expected, reason: reason);
}

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
