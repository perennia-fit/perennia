import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/common/local_clock.dart';
import 'package:perennia/domain/nutrition/meal_validation.dart';

/// The schema version this runner reads. It moves together with the vector
/// file's `schemaVersion`, its schema's constant and the TypeScript runner's
/// (packages/golden-vectors/vectors/README.md).
const int mealValidationGoldenSchemaVersion = 1;

// The server runs the same vector through validateAgentMealTime and
// localDateAtOffset (apps/server/test/agent-validation.golden.test.mjs), so
// the app and an agent judge a Meal's time, and derive its local date, alike.
void main() {
  test('Meal validation matches the shared m39 golden vector', () {
    final vector = jsonDecode(
      _vectorFile('m39-meal-validation.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(vector['name'], 'm39-meal-validation');
    expect(vector['domain'], 'meal-validation');
    expect(vector['schemaVersion'], mealValidationGoldenSchemaVersion);
    expect(vector['schema'], 'm39-meal-validation.schema.json');
    expect(vector['limits'], <String, Object?>{
      'futureToleranceMinutes': MealValidationLimits.futureToleranceMinutes,
    });

    final cases = vector['cases']! as List<Object?>;
    expect(cases, isNotEmpty);
    for (final caseObject in cases) {
      final caseData = caseObject! as Map<String, Object?>;
      final name = caseData['name']! as String;
      final input = caseData['input']! as Map<String, Object?>;
      final expected = caseData['expected']! as Map<String, Object?>;

      final startedAt = DateTime.parse(input['startedAt']! as String);
      final endedAtText = input['endedAt'] as String?;
      final result = validateMealTime(
        MealTimeInput(
          startedAt: startedAt,
          endedAt: endedAtText == null ? null : DateTime.parse(endedAtText),
          mealType: input['mealType']! as String,
        ),
        now: DateTime.parse(input['now']! as String),
      );

      expect(result.accepted, expected['accepted'], reason: name);
      expect(
        [for (final error in result.errors) error.rule],
        expected['errorRules'],
        reason: name,
      );
      expect(
        [for (final warning in result.warnings) warning.rule],
        expected['warningRules'],
        reason: name,
      );

      final localDate = localDateAtOffset(
        startedAt,
        input['timezoneOffsetMinutes']! as int,
      );
      expect(_formatDate(localDate), expected['localDate'], reason: name);
    }
  });
}

String _formatDate(({int year, int month, int day}) date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
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
