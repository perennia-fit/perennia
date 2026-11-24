import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/labs/lab_result.dart';
import 'package:perennia/domain/labs/lab_result_collapse.dart';

/// Moves with `schemaVersion` in m43-lab-result-collapse.json, its schema's
/// constant and the server runner's (apps/server/test/lab-results.golden.test.mjs):
/// an incompatible case-shape change bumps all of them together.
const int labResultCollapseGoldenSchemaVersion = 1;

void main() {
  group('Lab Result collapse', () {
    test('matches the shared M43 golden vectors', () async {
      final vector = jsonDecode(
        await _vectorFile('m43-lab-result-collapse.json').readAsString(),
      ) as Map<String, Object?>;

      expect(vector['name'], 'm43-lab-result-collapse');
      expect(vector['domain'], 'lab-result-collapse');
      expect(vector['schemaVersion'], labResultCollapseGoldenSchemaVersion);
      expect(vector['schema'], 'm43-lab-result-collapse.schema.json');
      final cases = vector['cases']! as List<Object?>;
      expect(cases, isNotEmpty);

      for (final caseObject in cases) {
        final caseData = caseObject! as Map<String, Object?>;
        final input = caseData['input']! as Map<String, Object?>;
        final expected = caseData['expected']! as Map<String, Object?>;
        final readings = (input['readings']! as List<Object?>)
            .map((reading) => _readingRef(reading! as Map<String, Object?>))
            .toList();

        expect(
          collapseLabResults(readings).map((reading) => reading.id).toList(),
          expected['keptIds'],
          reason: caseData['name']! as String,
        );
      }
    });
  });

  group('encodeLab', () {
    test('writes every key in the canonical order, nulls included', () {
      expect(
        jsonEncode(encodeLab(const LabFields(collected: '2026-03-04'))),
        '{"collected":"2026-03-04","limit":null,"printedRange":null,'
        '"printedFlag":null,"reportStatus":"final","fasting":null,'
        '"labName":null}',
      );
      expect(
        jsonEncode(
          encodeLab(
            const LabFields(
              collected: '2026-03-04T08:15',
              limit: LabLimit(comparator: LabComparator.lt, bound: 1),
              printedRange: '< 5',
              printedFlag: 'L',
              reportStatus: ReportStatus.interim,
              fasting: true,
              labName: 'Example Pathology',
            ),
          ),
        ),
        '{"collected":"2026-03-04T08:15","limit":{"comparator":"<","bound":1},'
        '"printedRange":"< 5","printedFlag":"L","reportStatus":"interim",'
        '"fasting":true,"labName":"Example Pathology"}',
      );
    });
  });

  group('decodeLab', () {
    test('applies the defaults and drops unknown keys', () {
      final decoded =
          decodeLab(<String, Object?>{'collected': '2026-03-04', 'x': 1})!;
      expect(encodeLab(decoded), <String, Object?>{
        'collected': '2026-03-04',
        'limit': null,
        'printedRange': null,
        'printedFlag': null,
        'reportStatus': 'final',
        'fasting': null,
        'labName': null,
      });
      expect(
        decodeLab(<String, Object?>{
          'collected': '2026-03-04',
          'reportStatus': null,
        })!
            .reportStatus,
        ReportStatus.final_,
      );
      expect(
        decodeLab(
                <String, Object?>{'collected': '2026-03-04', 'fasting': false})!
            .fasting,
        isNull,
      );
      expect(
        decodeLab(<String, Object?>{
          'collected': '2026-03-04',
          'limit': <String, Object?>{'comparator': '=', 'bound': 1},
        })!
            .limit,
        isNull,
      );
      expect(
        decodeLab(<String, Object?>{
          'collected': '2026-03-04',
          'limit': <String, Object?>{'comparator': '>=', 'bound': 2.5},
        })!
            .limit,
        const LabLimit(comparator: LabComparator.ge, bound: 2.5),
      );
    });

    test('keeps an unknown report status, which is not final', () {
      final status = decodeLab(<String, Object?>{
        'collected': '2026-03-04',
        'reportStatus': 'corrected',
      })!
          .reportStatus;
      expect(status.wire, 'corrected');
      expect(status.isKnown, isFalse);
      expect(status.isFinal, isFalse);
    });

    test('round-trips an encoded lab', () {
      const fields = LabFields(collected: '2026-03-04T08:15', printedFlag: 'H');
      expect(encodeLab(decodeLab(encodeLab(fields))!), encodeLab(fields));
    });

    test('returns null without a valid collected', () {
      for (final invalid in <Object?>[
        null,
        '2026-03-04',
        <Object?>[],
        <String, Object?>{},
        <String, Object?>{'collected': '2026-02-30'},
        <String, Object?>{'collected': '2026-03-04T24:00'},
        <String, Object?>{'collected': '2026-03-04 08:15'},
      ]) {
        expect(decodeLab(invalid), isNull, reason: '$invalid');
      }
    });
  });

  group('collected', () {
    test('isValidCollected accepts only real dates and times', () {
      for (final valid in <String>[
        '2026-03-04',
        '2026-03-04T00:00',
        '2026-03-04T23:59',
        '2024-02-29',
      ]) {
        expect(isValidCollected(valid), isTrue, reason: valid);
      }
      for (final invalid in <String>[
        '2026-3-04',
        '2025-02-29',
        '2026-13-01',
        '2026-04-31',
        '2026-03-04T08:60',
        '2026-03-04T08:15:00',
        '2026-03-04Z',
        '',
      ]) {
        expect(isValidCollected(invalid), isFalse, reason: invalid);
      }
    });

    test('collectedLocalDateTime expands to seconds', () {
      expect(collectedLocalDateTime('2026-03-04'), '2026-03-04T12:00:00');
      expect(collectedLocalDateTime('2026-03-04T08:15'), '2026-03-04T08:15:00');
      expect(
        () => collectedLocalDateTime('2026-02-30'),
        throwsArgumentError,
      );
    });
  });

  group('entered', () {
    test('parseEntered reads a number or a comparator and a number', () {
      void expectParsed(
        String entered,
        LabComparator? comparator,
        String number,
      ) {
        final parsed = parseEntered(entered);
        expect(parsed, isNotNull, reason: entered);
        expect(parsed!.comparator, comparator, reason: entered);
        expect(parsed.number, number, reason: entered);
      }

      expectParsed('20.0', null, '20.0');
      expectParsed('< 1', LabComparator.lt, '1');
      expectParsed('<1', LabComparator.lt, '1');
      expectParsed('<= 0.5', LabComparator.le, '0.5');
      expectParsed('≤0.5', LabComparator.le, '0.5');
      expectParsed('> 90', LabComparator.gt, '90');
      expectParsed('>=90', LabComparator.ge, '90');
      expectParsed('≥ 90', LabComparator.ge, '90');
      expectParsed('1e3', null, '1e3');
      for (final invalid in <String>[
        '',
        '<',
        '<  1',
        '< x',
        '1.7 x10^9',
        '=1',
        '1e999',
        'NaN',
        ' 1',
        '1 ',
      ]) {
        expect(parseEntered(invalid), isNull, reason: invalid);
      }
    });

    test('formatEntered writes the canonical form', () {
      expect(formatEntered(null, '20.0'), '20.0');
      expect(formatEntered(LabComparator.lt, '1'), '< 1');
      expect(formatEntered(LabComparator.ge, '90'), '>= 90');
      final parsed = parseEntered('≤0.5')!;
      expect(formatEntered(parsed.comparator, parsed.number), '<= 0.5');
    });
  });
}

LabReadingRef _readingRef(Map<String, Object?> reading) {
  final deletedAt = reading['deletedAt'] as String?;
  return LabReadingRef(
    id: reading['id']! as String,
    labTestKey: reading['labTestKey']! as String,
    lab: decodeLab(reading['lab']),
    atTime: DateTime.parse(reading['atTime']! as String),
    updatedAt: DateTime.parse(reading['updatedAt']! as String),
    deletedAt: deletedAt == null ? null : DateTime.parse(deletedAt),
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
