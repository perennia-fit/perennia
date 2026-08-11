import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/analytics/exercise_analytics.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

void main() {
  const engine = ExerciseAnalyticsEngine();

  test('load and reps records apply FitNotes precedence in metric units', () {
    final result = engine.compute(
      profile: ExerciseAnalyticsProfile.defaults(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
      ),
      sets: <AnalyticsSet>[
        _set('100kg-5', 1, _loadReps(load: '100', reps: '5')),
        _set('100kg-6', 2, _loadReps(load: '100', reps: '6')),
        _set('102-5kg-5', 3, _loadReps(load: '102.5', reps: '5')),
        _set('102-5kg-5-later', 4, _loadReps(load: '102.5', reps: '5')),
        _set(
          '225lb-5',
          5,
          _loadReps(load: '225', reps: '5', loadUnit: TrainingUnit.pound),
        ),
      ],
    );

    expect(result.profile.recordProfile, RecordProfile.repMax);
    expect(
      result.recordCatalog.repMaxRecords.map((record) => record.setId),
      <String>['102-5kg-5', '100kg-6'],
    );
    expect(result.recordCatalog.repMaxRecords.first.reps, 5);
    expect(result.recordCatalog.repMaxRecords.first.value, 102.5);
    expect(result.recordCatalog.repMaxRecords.last.reps, 6);
    expect(result.recordCatalog.repMaxRecords.last.value, 100);
    expect(result.headlineRecords, result.recordCatalog.repMaxRecords);
  });

  test('default profiles select records for common dimension sets', () {
    final repsOnly = engine.compute(
      profile: ExerciseAnalyticsProfile.defaults(
        type: ExerciseType(<DimensionId>[DimensionId.reps]),
      ),
      sets: <AnalyticsSet>[
        _set('reps-10', 1, _reps('10')),
        _set('reps-12', 2, _reps('12')),
      ],
    );
    final durationOnly = engine.compute(
      profile: ExerciseAnalyticsProfile.defaults(
        type: ExerciseType(<DimensionId>[DimensionId.duration]),
      ),
      sets: <AnalyticsSet>[
        _set('hold-60', 1, _duration('60')),
        _set('hold-90', 2, _duration('90')),
      ],
    );
    final distanceDuration = engine.compute(
      profile: ExerciseAnalyticsProfile.defaults(
        type: ExerciseType(<DimensionId>[
          DimensionId.distance,
          DimensionId.duration,
        ]),
      ),
      sets: <AnalyticsSet>[
        _set('5k-30m', 1, _distanceDuration(km: '5', seconds: '1800')),
        _set('5k-25m', 2, _distanceDuration(km: '5', seconds: '1500')),
      ],
    );
    final assisted = engine.compute(
      profile: ExerciseAnalyticsProfile.defaults(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
        loadMode: ExerciseLoadMode.assisted,
      ),
      sets: <AnalyticsSet>[
        _set('assist-20', 1, _loadReps(load: '20', reps: '5')),
        _set('assist-15', 2, _loadReps(load: '15', reps: '5')),
      ],
    );
    final completionOnly = engine.compute(
      profile: ExerciseAnalyticsProfile.defaults(type: ExerciseType.empty),
      sets: <AnalyticsSet>[_set('completion', 1, LoggedSet.completion())],
    );

    expect(repsOnly.headlineRecord?.profile, RecordProfile.maxReps);
    expect(repsOnly.headlineRecord?.value, 12);
    expect(durationOnly.headlineRecord?.profile, RecordProfile.maxDuration);
    expect(durationOnly.headlineRecord?.value, 90);
    expect(distanceDuration.headlineRecord?.profile, RecordProfile.fastestPace);
    expect(distanceDuration.headlineRecord?.value, 300);
    expect(
      assisted.headlineRecord?.profile,
      RecordProfile.minAssistancePerRepCount,
    );
    expect(assisted.headlineRecord?.value, 15);
    expect(completionOnly.headlineRecord, isNull);
  });

  test('record profile override changes only the headline selection', () {
    final type = ExerciseType(<DimensionId>[DimensionId.duration]);
    final result = engine.compute(
      profile: ExerciseAnalyticsProfile.defaults(
        type: type,
      ).copyWith(recordProfile: RecordProfile.minDuration),
      sets: <AnalyticsSet>[
        _set('slow', 1, _duration('120')),
        _set('fast', 2, _duration('45')),
      ],
    );

    expect(result.recordCatalog.maxDuration?.setId, 'slow');
    expect(result.recordCatalog.minDuration?.setId, 'fast');
    expect(result.headlineRecord?.profile, RecordProfile.minDuration);
    expect(result.headlineRecord?.setId, 'fast');
  });

  test('Brzycki e1RM is limited to reps 1 through 10', () {
    final result = engine.compute(
      profile: ExerciseAnalyticsProfile.defaults(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
      ),
      sets: <AnalyticsSet>[
        for (var reps = 1; reps <= 11; reps += 1)
          _set(
            'reps-$reps',
            reps,
            _loadReps(load: '100', reps: reps.toString()),
          ),
      ],
    );

    expect(result.estimatedOneRepMax.isDefined, isTrue);
    expect(result.estimatedOneRepMax.points, hasLength(10));
    expect(result.estimatedOneRepMax.points.first.value, 100);
    expect(
      result.estimatedOneRepMax.points.last.value,
      moreOrLessEquals(133.3333333333, epsilon: 0.000001),
    );
    expect(
      result.estimatedOneRepMax.points.map((point) => point.setId),
      isNot(contains('reps-11')),
    );
  });

  test('assisted exercises leave volume and e1RM undefined', () {
    final result = engine.compute(
      profile: ExerciseAnalyticsProfile.defaults(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
        loadMode: ExerciseLoadMode.assisted,
      ),
      sets: <AnalyticsSet>[_set('assist', 1, _loadReps(load: '10', reps: '5'))],
    );

    expect(result.volume.isDefined, isFalse);
    expect(result.volume.total, isNull);
    expect(result.estimatedOneRepMax.isDefined, isFalse);
    expect(result.estimatedOneRepMax.points, isEmpty);
  });

  test('analytics result models expose immutable snapshots', () {
    final firstRecord = _record('first', value: 100);
    final secondRecord = _record('second', value: 120);
    final repMaxRecords = <AnalyticsRecord>[firstRecord];
    final minAssistanceRecords = <AnalyticsRecord>[firstRecord];
    final headlineRecords = <AnalyticsRecord>[firstRecord];
    final e1rmPoints = <AnalyticsPoint>[_point('e1rm', value: 110)];

    final catalog = RecordCatalog(
      repMaxRecords: repMaxRecords,
      minAssistanceRecords: minAssistanceRecords,
      maxLoad: firstRecord,
      maxReps: null,
      maxDuration: null,
      minDuration: null,
      maxDistance: null,
      fastestPace: null,
    );
    final result = ExerciseAnalyticsResult(
      profile: ExerciseAnalyticsProfile.defaults(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
      ),
      recordCatalog: catalog,
      headlineRecords: headlineRecords,
      estimatedOneRepMax: DerivedSeries.defined(e1rmPoints),
      volume: const DerivedSeries.undefined(),
    );

    repMaxRecords.add(secondRecord);
    minAssistanceRecords.add(secondRecord);
    headlineRecords.add(secondRecord);
    e1rmPoints.add(_point('later', value: 130));

    expect(result.recordCatalog.repMaxRecords, <AnalyticsRecord>[firstRecord]);
    expect(
      result.recordCatalog.minAssistanceRecords,
      <AnalyticsRecord>[firstRecord],
    );
    expect(result.headlineRecords, <AnalyticsRecord>[firstRecord]);
    expect(
        result.estimatedOneRepMax.points, <AnalyticsPoint>[e1rmPoints.first]);

    expect(
      () => result.recordCatalog.repMaxRecords.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => result.recordCatalog.minAssistanceRecords.clear(),
      throwsUnsupportedError,
    );
    expect(() => result.headlineRecords.clear(), throwsUnsupportedError);
    expect(
      () => result.estimatedOneRepMax.points.clear(),
      throwsUnsupportedError,
    );

    final scalarRecords =
        result.recordCatalog.recordsFor(RecordProfile.maxLoad);
    expect(scalarRecords, <AnalyticsRecord>[firstRecord]);
    expect(() => scalarRecords.clear(), throwsUnsupportedError);
  });

  test('Dart analytics matches the shared golden vectors', () async {
    final vector = jsonDecode(
      await _vectorFile(
        'm4-analytics-pr-e1rm-volume.json',
      ).readAsString(),
    ) as Map<String, Object?>;
    final cases = vector['cases']! as List<Object?>;

    for (final caseObject in cases) {
      final caseData = caseObject! as Map<String, Object?>;
      final exercise = caseData['exercise']! as Map<String, Object?>;
      final expected = caseData['expected']! as Map<String, Object?>;
      final result = engine.compute(
        profile: ExerciseAnalyticsProfile(
          type: ExerciseType(
            (exercise['dimensions']! as List<Object?>).map(
              (dimension) => DimensionId.values.byName(dimension! as String),
            ),
          ),
          loadMode: ExerciseLoadMode.values.byName(
            exercise['loadMode']! as String,
          ),
          recordProfile: RecordProfile.values.byName(
            exercise['recordProfile']! as String,
          ),
        ),
        sets: (caseData['sets']! as List<Object?>).map(_setFromVector),
      );

      expect(
        result.estimatedOneRepMax.isDefined,
        expected['e1rmDefined'],
        reason: caseData['name']! as String,
      );
      expect(
        result.volume.isDefined,
        expected['volumeDefined'],
        reason: caseData['name']! as String,
      );

      final repMaxRecords = expected['repMaxRecords'];
      if (repMaxRecords != null) {
        _expectRecords(
          actual: result.recordCatalog.repMaxRecords,
          expected: repMaxRecords as List<Object?>,
          reason: caseData['name']! as String,
        );
      }

      final minAssistanceRecords = expected['minAssistanceRecords'];
      if (minAssistanceRecords != null) {
        _expectRecords(
          actual: result.recordCatalog.minAssistanceRecords,
          expected: minAssistanceRecords as List<Object?>,
          reason: caseData['name']! as String,
        );
      }

      final e1rmValues = expected['e1rmValues'];
      if (e1rmValues != null) {
        expect(result.estimatedOneRepMax.points, hasLength(10));
        for (var index = 0; index < 10; index += 1) {
          expect(
            result.estimatedOneRepMax.points[index].value,
            moreOrLessEquals(
              (e1rmValues as List<Object?>)[index]! as double,
              epsilon: 0.000001,
            ),
            reason: '${caseData['name']} e1RM[$index]',
          );
        }
      }

      final maxDistanceRecord = expected['maxDistanceRecord'];
      if (maxDistanceRecord != null) {
        _expectRecord(
          actual: result.recordCatalog.maxDistance,
          expected: maxDistanceRecord as Map<String, Object?>,
          reason: caseData['name']! as String,
        );
      }

      final fastestPaceRecord = expected['fastestPaceRecord'];
      if (fastestPaceRecord != null) {
        _expectRecord(
          actual: result.recordCatalog.fastestPace,
          expected: fastestPaceRecord as Map<String, Object?>,
          reason: caseData['name']! as String,
        );
      }

      final volumeValues = expected['volumeValues'];
      if (volumeValues != null) {
        final values = volumeValues as List<Object?>;
        expect(result.volume.points, hasLength(values.length));
        for (var index = 0; index < values.length; index += 1) {
          expect(
            result.volume.points[index].value,
            moreOrLessEquals(values[index]! as double, epsilon: 0.000001),
            reason: '${caseData['name']} volume[$index]',
          );
        }
      }
    }
  });

  test('50k-set aggregate stays under the M4 performance budget', () {
    final sets = List<AnalyticsSet>.generate(
      50000,
      (index) => _set(
        'set-$index',
        index,
        _loadReps(
          load: (80 + (index % 40)).toString(),
          reps: (1 + (index % 10)).toString(),
        ),
      ),
      growable: false,
    );
    final stopwatch = Stopwatch()..start();

    final result = engine.compute(
      profile: ExerciseAnalyticsProfile.defaults(
        type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
      ),
      sets: sets,
    );
    stopwatch.stop();

    expect(result.volume.points, hasLength(50000));
    expect(stopwatch.elapsedMilliseconds, lessThan(300));
  });
}

AnalyticsSet _set(String id, int sequence, LoggedSet values) {
  return AnalyticsSet(
    id: id,
    performedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: sequence)),
    sequence: sequence,
    values: values,
  );
}

LoggedSet _loadReps({
  required String load,
  required String reps,
  TrainingUnit loadUnit = TrainingUnit.kilogram,
}) {
  return LoggedSet.fromValues(<SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.load,
      entered: load,
      unit: loadUnit,
    ),
    SetDimensionValue(
      dimension: DimensionId.reps,
      entered: reps,
      unit: TrainingUnit.repetition,
    ),
  ]);
}

LoggedSet _reps(String reps) {
  return LoggedSet.fromValues(<SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.reps,
      entered: reps,
      unit: TrainingUnit.repetition,
    ),
  ]);
}

LoggedSet _duration(String seconds) {
  return LoggedSet.fromValues(<SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.duration,
      entered: seconds,
      unit: TrainingUnit.second,
    ),
  ]);
}

LoggedSet _distanceDuration({required String km, required String seconds}) {
  return LoggedSet.fromValues(<SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.distance,
      entered: km,
      unit: TrainingUnit.kilometer,
    ),
    SetDimensionValue(
      dimension: DimensionId.duration,
      entered: seconds,
      unit: TrainingUnit.second,
    ),
  ]);
}

AnalyticsSet _setFromVector(Object? object) {
  final data = object! as Map<String, Object?>;
  return AnalyticsSet(
    id: data['id']! as String,
    performedAt: DateTime.parse(data['performedAt']! as String).toUtc(),
    sequence: (data['position']! as num).toInt(),
    values: _loggedSetFromVector(data['values']! as Map<String, Object?>),
  );
}

LoggedSet _loggedSetFromVector(Map<String, Object?> values) {
  final setValues = <SetDimensionValue>[];
  for (final entry in values.entries) {
    final value = entry.value! as Map<String, Object?>;
    setValues.add(
      SetDimensionValue(
        dimension: DimensionId.values.byName(entry.key),
        entered: value['entered']! as String,
        unit: TrainingUnit.values.byName(value['unit']! as String),
      ),
    );
  }
  return setValues.isEmpty
      ? LoggedSet.completion()
      : LoggedSet.fromValues(setValues);
}

void _expectRecord({
  required AnalyticsRecord? actual,
  required Map<String, Object?> expected,
  required String reason,
}) {
  expect(actual, isNotNull, reason: reason);
  expect(actual!.setId, expected['setId'], reason: reason);
  expect(
    actual.value,
    moreOrLessEquals(expected['value']! as double, epsilon: 0.000001),
    reason: reason,
  );
  expect(actual.unit.name, expected['unit'], reason: reason);
}

void _expectRecords({
  required List<AnalyticsRecord> actual,
  required List<Object?> expected,
  required String reason,
}) {
  expect(actual, hasLength(expected.length), reason: reason);
  for (var index = 0; index < expected.length; index += 1) {
    final expectedRecord = expected[index]! as Map<String, Object?>;
    expect(actual[index].setId, expectedRecord['setId'], reason: reason);
    expect(actual[index].reps, expectedRecord['reps'], reason: reason);
    expect(
      actual[index].value,
      moreOrLessEquals(expectedRecord['value']! as double, epsilon: 0.000001),
      reason: reason,
    );
    expect(actual[index].unit.name, expectedRecord['unit'], reason: reason);
  }
}

AnalyticsRecord _record(String setId, {required double value}) {
  return AnalyticsRecord(
    profile: RecordProfile.maxLoad,
    setId: setId,
    achievedAt: DateTime.utc(2026, 1, 1),
    sequence: 0,
    value: value,
    unit: TrainingUnit.kilogram,
  );
}

AnalyticsPoint _point(String setId, {required double value}) {
  return AnalyticsPoint(
    setId: setId,
    achievedAt: DateTime.utc(2026, 1, 1),
    value: value,
    unit: TrainingUnit.kilogram,
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
