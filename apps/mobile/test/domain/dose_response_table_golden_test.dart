import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/effect/effect.dart';
import 'package:perennia/domain/protocols/protocols.dart';

/// the shared golden vector for the `Effect` view's dose-response
/// table (PROTOCOLS.md §4) — grouping outcome behavior by the ACTUAL LOGGED
/// `Dose` level (resolved active mass where available), NEVER the
/// Schedule/plan (§1.4, load-bearing). Pure function under test: nothing
/// here touches persistence (derived, never stored).
void main() {
  test('computeDoseResponseTable matches the shared golden vectors', () {
    final vectorFile = _vectorFile('dose_response_table_golden.json');
    final vector =
        jsonDecode(vectorFile.readAsStringSync()) as Map<String, Object?>;
    expect(vector['name'], 'm29-dose-response-table');

    final cases = vector['cases']! as List<Object?>;
    expect(cases, isNotEmpty);

    for (final rawCase in cases) {
      final vectorCase = rawCase! as Map<String, Object?>;
      final reason = vectorCase['name']! as String;

      final doses = (vectorCase['doses']! as List<Object?>)
          .map((raw) => _doseFromJson(raw! as Map<String, Object?>))
          .toList(growable: false);
      final samples = (vectorCase['samples']! as List<Object?>).map((raw) {
        final sample = raw! as Map<String, Object?>;
        return EffectSample(
          at: DateTime.parse(sample['at']! as String),
          value: (sample['value']! as num).toDouble(),
        );
      }).toList(growable: false);

      final rows = computeDoseResponseTable(doses: doses, samples: samples);
      final expected = vectorCase['expected']! as List<Object?>;

      expect(rows, hasLength(expected.length), reason: reason);
      for (var i = 0; i < expected.length; i += 1) {
        final expectedRow = expected[i]! as Map<String, Object?>;
        final row = rows[i];
        expect(
          row.compoundName,
          expectedRow['compoundName'],
          reason: '$reason row $i compoundName',
        );
        expect(
          row.levelLabel,
          expectedRow['levelLabel'],
          reason: '$reason row $i levelLabel',
        );
        expect(
          row.levelValue,
          closeTo((expectedRow['levelValue']! as num).toDouble(), 1e-9),
          reason: '$reason row $i levelValue',
        );
        expect(
          row.doseCount,
          expectedRow['doseCount'],
          reason: '$reason row $i doseCount',
        );
        expect(
          row.stats.sampleCount,
          expectedRow['sampleCount'],
          reason: '$reason row $i sampleCount',
        );
        final expectedMean = expectedRow['mean'];
        if (expectedMean == null) {
          expect(row.stats.mean, isNull, reason: '$reason row $i mean');
        } else {
          expect(
            row.stats.mean,
            isNotNull,
            reason: '$reason row $i mean',
          );
          expect(
            row.stats.mean!,
            closeTo((expectedMean as num).toDouble(), 1e-6),
            reason: '$reason row $i mean',
          );
        }
      }
    }
  });

  test('computeDoseResponseTable exposes immutable row snapshots', () {
    final dose = _doseFromJson(<String, Object?>{
      'id': 'dose-1',
      'compoundName': 'Creatine',
      'amountValue': 5,
      'amountEntered': '5',
      'unit': 'milligram',
      'tookAt': '2026-01-10T08:00:00.000Z',
    });
    final rows = computeDoseResponseTable(
      doses: <DoseRecord>[dose],
      samples: <EffectSample>[
        EffectSample(
          at: DateTime.utc(2026, 1, 10, 9),
          value: 100,
        ),
      ],
    );

    expect(rows, hasLength(1));
    expect(() => rows.clear(), throwsUnsupportedError);
    expect(
      () => rows[0] = const DoseResponseRow(
        compoundName: 'Replaced',
        levelLabel: '0 mg',
        levelValue: 0,
        doseCount: 0,
        stats: EffectSegmentStats(mean: null, sampleCount: 0),
      ),
      throwsUnsupportedError,
    );
  });
}

DoseRecord _doseFromJson(Map<String, Object?> json) {
  final strengthJson = json['strength'] as Map<String, Object?>?;
  final tookAt = DateTime.parse(json['tookAt']! as String);
  return DoseRecord(
    id: json['id']! as String,
    compoundName: json['compoundName']! as String,
    compoundStrength: strengthJson == null
        ? null
        : CompoundStrength(
            amount: (strengthJson['amount']! as num).toDouble(),
            amountEntered: strengthJson['amountEntered']! as String,
            massUnit: doseUnitFromName(strengthJson['massUnit']! as String),
            perUnit: doseUnitFromName(strengthJson['perUnit']! as String),
          ),
    amountValue: (json['amountValue']! as num).toDouble(),
    amountEntered: json['amountEntered']! as String,
    unit: doseUnitFromName(json['unit']! as String),
    route: DoseRoute.oral,
    tookAt: tookAt,
    timezone: 'UTC',
    localDate: ProtocolDayDate.fromDateTime(tookAt),
    provenance: DoseProvenance.manual,
    updatedAt: tookAt,
  );
}

/// Walks up from the current working directory to find the fixture,
/// tolerant of tests being invoked from either the repo root or
/// `apps/mobile` (mirrors `effect_window_golden_test.dart`).
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
  throw StateError('Dose response table golden vector not found: $name.');
}
