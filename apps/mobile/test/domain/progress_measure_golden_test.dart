import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/analytics/exercise_analytics.dart';
import 'package:perennia/domain/analytics/progress_measure.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

/// The schema version this runner reads. It moves together with the vector
/// file's `schemaVersion` and its schema's constant
/// (packages/golden-vectors/vectors/README.md).
const int _schemaVersion = 1;

/// The shared golden vector for the Progress Measure core
/// (docs/designs/progress-overview.md, D0 and D4): `progressSeries` and
/// `newBestsBetween`. The agent API runs the same file
/// (`apps/server/test/progress-measure.golden.test.mjs`), so Progress
/// Overview and an Agent never disagree about what was a New Best.
void main() {
  final vector = jsonDecode(
    _vectorFile('m37-progress-measure.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('the progress-measure vector header matches this runner', () {
    expect(vector['name'], 'm37-progress-measure');
    expect(vector['domain'], 'progress-measure');
    expect(vector['schemaVersion'], _schemaVersion);
    expect(vector['schema'], 'm37-progress-measure.schema.json');
    expect(vector['cases'], isNotEmpty);
  });

  group('the Progress Measure core matches the shared golden vectors', () {
    for (final rawCase in vector['cases']! as List<Object?>) {
      final vectorCase = rawCase! as Map<String, Object?>;
      final name = vectorCase['name']! as String;
      final function = vectorCase['function']! as String;
      test('$function: $name', () {
        final input = vectorCase['input']! as Map<String, Object?>;
        expect(_run(function, input), vectorCase['expected'], reason: name);
      });
    }
  });

  // Not vector cases: periodBest is Dart only (D4).
  group('periodBest', () {
    final from = _date('2026-10-05');
    final to = _date('2026-11-01');

    test('has no bestBefore when no point is earlier than the period', () {
      final result = periodBest(
        _series(ProgressBetterIs.higher, <ProgressPoint>[
          _point('w1', '2026-10-05', 100),
          _point('w2', '2026-10-12', 105),
        ]),
        from,
        to,
      );

      expect(result.best?.workoutId, 'w2');
      expect(result.bestBefore, isNull);
    });

    test('keeps the earlier point when values are equal', () {
      final result = periodBest(
        _series(ProgressBetterIs.higher, <ProgressPoint>[
          _point('w1', '2026-09-28', 105),
          _point('w2', '2026-10-06', 105),
          _point('w3', '2026-10-20', 105),
        ]),
        from,
        to,
      );

      expect(result.best?.workoutId, 'w2');
      expect(result.bestBefore, 105);
    });

    test('a better period best beats the best before, lower is better', () {
      final result = periodBest(
        _series(ProgressBetterIs.lower, <ProgressPoint>[
          _point('w1', '2026-09-20', 330),
          _point('w2', '2026-10-01', 322),
          _point('w3', '2026-10-10', 325),
          _point('w4', '2026-10-31', 304),
          _point('w5', '2026-11-02', 290),
        ]),
        from,
        to,
      );

      // The 2 November point is after the period and does not count.
      expect(result.best?.workoutId, 'w4');
      expect(result.best?.value, 304);
      expect(result.bestBefore, 322);
    });

    test('a worse period best keeps the higher best before', () {
      final result = periodBest(
        _series(ProgressBetterIs.higher, <ProgressPoint>[
          _point('w1', '2026-09-14', 120),
          _point('w2', '2026-10-12', 110),
          _point('w3', '2026-10-19', 112.5),
        ]),
        from,
        to,
      );

      expect(result.best?.workoutId, 'w3');
      expect(result.bestBefore, 120);
    });

    test('has no best when no point is in the period', () {
      final result = periodBest(
        _series(ProgressBetterIs.higher, <ProgressPoint>[
          _point('w1', '2026-09-14', 120),
        ]),
        from,
        to,
      );

      expect(result.best, isNull);
      expect(result.bestBefore, 120);
    });
  });
}

Object? _run(String function, Map<String, Object?> input) {
  switch (function) {
    case 'progress_series':
      final series = progressSeries(
        exerciseId: input['exerciseId']! as String,
        profile: _profileFrom(input['profile']! as Map<String, Object?>),
        workouts: _list(input['workouts']).map(_workoutSetsFrom),
      );
      return series == null ? null : _seriesToJson(series);
    case 'new_bests_between':
      return newBestsBetween(
        _list(input['series']).map(_seriesFrom),
        _date(input['from']),
        _date(input['to']),
      ).map(_newBestToJson).toList();
  }
  throw StateError('Unknown progress-measure function: $function.');
}

ExerciseAnalyticsProfile _profileFrom(Map<String, Object?> map) {
  return ExerciseAnalyticsProfile(
    type: ExerciseType(
      _list(map['dimensions']).map(
        (dimension) => DimensionId.values.byName(dimension! as String),
      ),
    ),
    loadMode: ExerciseLoadMode.values.byName(map['loadMode']! as String),
    recordProfile: RecordProfile.values.byName(map['recordProfile']! as String),
  );
}

ProgressWorkoutSets _workoutSetsFrom(Object? raw) {
  final map = raw! as Map<String, Object?>;
  return ProgressWorkoutSets(
    workoutId: map['workoutId']! as String,
    localDate: _date(map['localDate']),
    startedAt: DateTime.parse(map['startedAt']! as String),
    sets: _list(map['sets']).map((rawSet) {
      final set = rawSet! as Map<String, Object?>;
      return ProgressSet(
        id: set['id']! as String,
        position: set['position']! as int,
        isCompleted: set['isCompleted']! as bool,
        values: _loggedSetFrom(set['values']! as Map<String, Object?>),
      );
    }),
  );
}

LoggedSet _loggedSetFrom(Map<String, Object?> values) {
  if (values.isEmpty) {
    return LoggedSet.completion();
  }
  return LoggedSet.fromValues(<SetDimensionValue>[
    for (final MapEntry(:key, :value) in values.entries)
      if (value
          case {'entered': final String entered, 'unit': final String unit})
        SetDimensionValue(
          dimension: DimensionId.values.byName(key),
          entered: entered,
          unit: TrainingUnit.values.byName(unit),
        )
      else
        throw StateError('Malformed dimension value for $key: $value.'),
  ]);
}

ProgressSeries _seriesFrom(Object? raw) {
  final map = raw! as Map<String, Object?>;
  return ProgressSeries(
    exerciseId: map['exerciseId']! as String,
    measure: ProgressMeasureKind.values.byName(map['measure']! as String),
    betterIs: ProgressBetterIs.values.byName(map['betterIs']! as String),
    points: _list(map['points']).map((rawPoint) {
      final point = rawPoint! as Map<String, Object?>;
      return ProgressPoint(
        workoutId: point['workoutId']! as String,
        localDate: _date(point['localDate']),
        startedAt: DateTime.parse(point['startedAt']! as String),
        setId: point['setId']! as String,
        value: (point['value']! as num).toDouble(),
        unit: TrainingUnit.values.byName(point['unit']! as String),
        isNewBest: point['isNewBest']! as bool,
      );
    }),
  );
}

Map<String, Object?> _seriesToJson(ProgressSeries series) => <String, Object?>{
      'exerciseId': series.exerciseId,
      'measure': series.measure.name,
      'betterIs': series.betterIs.name,
      'points': series.points
          .map(
            (point) => <String, Object?>{
              'workoutId': point.workoutId,
              'localDate': point.localDate.storageValue,
              'startedAt': point.startedAt.toIso8601String(),
              'setId': point.setId,
              'value': point.value,
              'unit': point.unit.name,
              'isNewBest': point.isNewBest,
            },
          )
          .toList(),
    };

Map<String, Object?> _newBestToJson(NewBest best) => <String, Object?>{
      'exerciseId': best.exerciseId,
      'measure': best.measure.name,
      'workoutId': best.workoutId,
      'localDate': best.localDate.storageValue,
      'startedAt': best.startedAt.toIso8601String(),
      'setId': best.setId,
      'value': best.value,
      'unit': best.unit.name,
    };

ProgressSeries _series(ProgressBetterIs betterIs, List<ProgressPoint> points) {
  return ProgressSeries(
    exerciseId: 'e1',
    measure: betterIs == ProgressBetterIs.higher
        ? ProgressMeasureKind.estimatedOneRepMax
        : ProgressMeasureKind.fastestPace,
    betterIs: betterIs,
    points: points,
  );
}

ProgressPoint _point(String workoutId, String localDate, double value) {
  return ProgressPoint(
    workoutId: workoutId,
    localDate: _date(localDate),
    startedAt: DateTime.parse('${localDate}T07:00:00.000Z'),
    setId: 's-$workoutId',
    value: value,
    unit: TrainingUnit.kilogram,
    isNewBest: false,
  );
}

List<Object?> _list(Object? value) => value! as List<Object?>;

TrainingDayDate _date(Object? value) => TrainingDayDate.parse(value! as String);

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
