import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/labs/lab_default_range.dart';
import 'package:perennia/domain/labs/lab_result.dart';
import 'package:perennia/domain/labs/lab_test.dart';
import 'package:perennia/domain/labs/lab_test_catalogue.generated.dart';
import 'package:perennia/domain/profile/user_profile.dart';

/// Moves with `schemaVersion` in m44-lab-default-range.json and its schema's
/// constant: an incompatible case-shape change bumps them together. Dart
/// only: no server reader computes Default Ranges or positions.
const int labDefaultRangeGoldenSchemaVersion = 1;

void main() {
  group('Lab Default Range', () {
    test('matches the shared M44 golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m44-lab-default-range.json').readAsString(),
      ) as Map<String, Object?>;

      expect(vector['name'], 'm44-lab-default-range');
      expect(vector['domain'], 'lab-default-range');
      expect(vector['schemaVersion'], labDefaultRangeGoldenSchemaVersion);
      expect(vector['schema'], 'm44-lab-default-range.schema.json');
      final cases = vector['cases']! as List<Object?>;
      expect(cases, isNotEmpty);

      final functions = <String>{};
      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final name = caseData['name']! as String;
        final function = caseData['function']! as String;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected'];
        functions.add(function);

        switch (function) {
          case 'defaultRangeFor':
            final chosen = defaultRangeFor(
              _labTest(
                (input['defaultRanges']! as List<Object?>)
                    .map((entry) =>
                        _defaultRange(entry! as Map<String, Object?>))
                    .toList(),
              ),
              input['printedRange'] as String?,
              ProfileSex.fromWireName(input['sex']),
              input['age'] as int?,
            );
            expect(
              chosen == null ? null : _defaultRangeJson(chosen),
              expected,
              reason: name,
            );
          case 'parsePrintedRange':
            final parsed = parsePrintedRange(input['text']! as String);
            expect(
              parsed == null ? null : _parsedRangeJson(parsed),
              expected,
              reason: name,
            );
          case 'rangePosition':
            expect(
              rangePosition(
                _labValue(input['value']! as Map<String, Object?>),
                _parsedRange(input['range']! as Map<String, Object?>),
              ).name,
              expected,
              reason: name,
            );
          case 'resultPosition':
            final defaultRange = input['defaultRange'] as Map<String, Object?>?;
            final result = resultPosition(
              value: _labValue(input['value']! as Map<String, Object?>),
              printedRange: input['printedRange'] as String?,
              kind: PrintedRangeKind.values.byName(input['kind']! as String),
              defaultRange:
                  defaultRange == null ? null : _defaultRange(defaultRange),
            );
            expect(
              result == null
                  ? null
                  : <String, Object?>{
                      'position': result.position.name,
                      'source': result.source.name,
                    },
              expected,
              reason: name,
            );
          default:
            fail('$name: unknown function "$function"');
        }
      }
      expect(functions, {
        'defaultRangeFor',
        'parsePrintedRange',
        'rangePosition',
        'resultPosition',
      });
    });
  });

  group('the real catalogue', () {
    final creatinine = labTestByKey('creatinine')!;

    test('gives Creatinine a Default Range once sex and age are known', () {
      final range = defaultRangeFor(creatinine, null, ProfileSex.male, 40);
      expect(range, isNotNull);
      expect(range!.sex, DefaultRangeSex.male);
      expect(range.low, isNotNull);
      expect(range.high, isNotNull);
      expect(range.source.url, isNotEmpty);
    });

    test('gives Creatinine none with no sex and no age', () {
      expect(defaultRangeFor(creatinine, null, null, null), isNull);
    });
  });
}

LabTest _labTest(List<DefaultRange> defaultRanges) => LabTest(
      key: 'vector_test',
      name: 'Vector test',
      panel: 'Vectors',
      variants: const [],
      unit: 'mmol/L',
      unitAliases: const [],
      hardBounds: const Bounds(min: -1000, max: 1000),
      printedRangeKind: PrintedRangeKind.reference,
      defaultRanges: defaultRanges,
    );

DefaultRange _defaultRange(Map<String, Object?> json) {
  final source = json['source']! as Map<String, Object?>;
  return DefaultRange(
    sex: DefaultRangeSex.values.byName(json['sex']! as String),
    ageMin: json['ageMin'] as int?,
    ageMax: json['ageMax'] as int?,
    low: json['low'] as num?,
    high: json['high'] as num?,
    source: DefaultRangeSource(
      title: source['title']! as String,
      url: source['url']! as String,
      version: source['version']! as String,
    ),
  );
}

Map<String, Object?> _defaultRangeJson(DefaultRange range) => {
      'sex': range.sex.name,
      'ageMin': range.ageMin,
      'ageMax': range.ageMax,
      'low': range.low,
      'high': range.high,
      'source': {
        'title': range.source.title,
        'url': range.source.url,
        'version': range.source.version,
      },
    };

ParsedRange _parsedRange(Map<String, Object?> json) => ParsedRange(
      low: json['low'] as num?,
      lowInclusive: json['lowInclusive']! as bool,
      high: json['high'] as num?,
      highInclusive: json['highInclusive']! as bool,
    );

Map<String, Object?> _parsedRangeJson(ParsedRange range) => {
      'low': range.low,
      'lowInclusive': range.lowInclusive,
      'high': range.high,
      'highInclusive': range.highInclusive,
    };

LabValue _labValue(Map<String, Object?> json) {
  if (json.containsKey('number')) return LabNumber(json['number']! as num);
  final limit = json['limit']! as Map<String, Object?>;
  return LabLimitValue(
    LabLimit(
      comparator: LabComparator.fromWire(limit['comparator'])!,
      bound: limit['bound']! as num,
    ),
  );
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
