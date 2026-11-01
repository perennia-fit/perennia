import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_progress.dart';

/// The schema version this runner reads. It moves together with the vector
/// file's `schemaVersion` and its schema's constant
/// (packages/golden-vectors/vectors/README.md).
const int _schemaVersion = 1;

/// The shared golden vector for the training progress core
/// (docs/designs/progress-overview.md, D0-D3): `trainingWeek`,
/// `summarizeTrainingWeek` and `trainingDays`. The agent API runs the same
/// file (`apps/server/test/training-progress.golden.test.mjs`), so Progress
/// Overview and an Agent never disagree about how the week went.
void main() {
  final vector = jsonDecode(
    _vectorFile('m37-training-progress.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('the training-progress vector header matches this runner', () {
    expect(vector['name'], 'm37-training-progress');
    expect(vector['domain'], 'training-progress');
    expect(vector['schemaVersion'], _schemaVersion);
    expect(vector['schema'], 'm37-training-progress.schema.json');
    expect(vector['cases'], isNotEmpty);
  });

  group('the training progress core matches the shared golden vectors', () {
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

  // Not vector cases: weeklyFocusSeconds is Dart only (D3).
  group('weeklyFocusSeconds', () {
    test('buckets a Monday first week into Monday-to-Sunday weeks', () {
      final days = trainingDays(
        workouts: <ProgressWorkout>[
          _workout('w1', '2026-10-05', 3600, focusId: 'f-weights'),
          _workout('w2', '2026-10-11', 1800, focusId: 'f-weights'),
          _workout('w3', '2026-10-11', 600),
          _workout('w4', '2026-10-12', 900, focusId: 'f-endurance'),
          _workout('w5', '2026-10-25', 1200, focusId: 'f-weights'),
        ],
        from: _date('2026-10-05'),
        to: _date('2026-11-01'),
      );

      final weeks = weeklyFocusSeconds(days, _date('2026-10-05'));

      expect(weeks.map((week) => week.weekStart.storageValue), <String>[
        '2026-10-05',
        '2026-10-12',
        '2026-10-19',
        '2026-10-26',
      ]);
      // Sunday 11 October closes the first week and Sunday 25 October the
      // third; the fourth week has no time but is still a bucket.
      expect(weeks.map((week) => week.secondsByFocus), <Map<String, int>>[
        <String, int>{'f-weights': 5400, noFocusKey: 600},
        <String, int>{'f-endurance': 900},
        <String, int>{'f-weights': 1200},
        <String, int>{},
      ]);
    });

    test('buckets a Sunday first week into Sunday-to-Saturday weeks', () {
      final days = trainingDays(
        workouts: <ProgressWorkout>[
          _workout('w1', '2026-10-04', 3600, focusId: 'f-weights'),
          _workout('w2', '2026-10-10', 1800, focusId: 'f-weights'),
          _workout('w3', '2026-10-11', 900, focusId: 'f-weights'),
          _workout('w4', '2026-10-17', 600, focusId: 'f-mobility'),
        ],
        from: _date('2026-10-04'),
        to: _date('2026-10-17'),
      );

      final weeks = weeklyFocusSeconds(days, _date('2026-10-04'));

      expect(weeks.map((week) => week.weekStart.storageValue), <String>[
        '2026-10-04',
        '2026-10-11',
      ]);
      expect(weeks.map((week) => week.secondsByFocus), <Map<String, int>>[
        <String, int>{'f-weights': 5400},
        <String, int>{'f-weights': 900, 'f-mobility': 600},
      ]);
    });

    test('ignores days before the first week and returns nothing for none', () {
      final days = trainingDays(
        workouts: <ProgressWorkout>[
          _workout('w1', '2026-10-03', 3600, focusId: 'f-weights'),
          _workout('w2', '2026-10-04', 60, focusId: 'f-weights'),
        ],
        from: _date('2026-10-03'),
        to: _date('2026-10-04'),
      );

      final weeks = weeklyFocusSeconds(days, _date('2026-10-04'));

      expect(weeks, hasLength(1));
      expect(weeks.single.secondsByFocus, <String, int>{'f-weights': 60});
      expect(weeklyFocusSeconds(const <TrainingDay>[], _date('2026-10-04')),
          isEmpty);
    });
  });
}

Object? _run(String function, Map<String, Object?> input) {
  switch (function) {
    case 'training_week':
      return _argumentOrResult(() {
        final week = trainingWeek(
          plans: _list(input['plans']).map(_planFrom),
          workouts: _list(input['workouts']).map(_workoutFrom),
          weekStart: _date(input['weekStart']),
          today: _date(input['today']),
        );
        return <String, Object?>{
          'weekStart': week.weekStart.storageValue,
          'comparedRoutineIds': week.comparedRoutineIds,
          'days': week.days.map(_weekDayToJson).toList(),
        };
      });
    case 'summarize_training_week':
      final counts = summarizeTrainingWeek(
        _list(input['days']).map(_weekDayFrom),
      );
      return <String, Object?>{
        'done': counts.done,
        'partlyDone': counts.partlyDone,
        'doneDifferently': counts.doneDifferently,
        'notDone': counts.notDone,
        'trained': counts.trained,
      };
    case 'training_days':
      return _argumentOrResult(
        () => trainingDays(
          workouts: _list(input['workouts']).map(_workoutFrom),
          from: _date(input['from']),
          to: _date(input['to']),
        )
            .map(
              (day) => <String, Object?>{
                'localDate': day.localDate.storageValue,
                'workoutCount': day.workoutCount,
                'secondsByFocus': day.secondsByFocus,
              },
            )
            .toList(),
      );
  }
  throw StateError('Unknown training-progress function: $function.');
}

Object? _argumentOrResult(Object? Function() run) {
  try {
    return run();
  } on ArgumentError {
    return const <String, Object?>{'error': 'argument'};
  }
}

WeeklyPlan _planFrom(Object? raw) {
  final map = raw! as Map<String, Object?>;
  return WeeklyPlan(
    routineId: map['routineId']! as String,
    entries: _list(map['entries']).map((rawEntry) {
      final entry = rawEntry! as Map<String, Object?>;
      return WeeklyPlanEntry(
        workoutTemplateId: entry['workoutTemplateId']! as String,
        weekday: entry['weekday']! as int,
      );
    }),
  );
}

ProgressWorkout _workoutFrom(Object? raw) {
  final map = raw! as Map<String, Object?>;
  final endedAt = map['endedAt'] as String?;
  return ProgressWorkout(
    workoutId: map['workoutId']! as String,
    localDate: _date(map['localDate']),
    startedAt: DateTime.parse(map['startedAt']! as String),
    endedAt: endedAt == null ? null : DateTime.parse(endedAt),
    focusId: map['focusId'] as String?,
    linkedTemplateId: map['linkedTemplateId'] as String?,
    performedSetCount: map['performedSetCount']! as int,
  );
}

TrainingWeekDay _weekDayFrom(Object? raw) {
  final map = raw! as Map<String, Object?>;
  return TrainingWeekDay(
    localDate: _date(map['localDate']),
    status: TrainingDayStatus.values.singleWhere(
      (status) => status.wireName == map['status'],
    ),
    plannedCount: map['plannedCount']! as int,
    matchedCount: map['matchedCount']! as int,
    workoutCount: map['workoutCount']! as int,
  );
}

Map<String, Object?> _weekDayToJson(TrainingWeekDay day) => <String, Object?>{
      'localDate': day.localDate.storageValue,
      'status': day.status.wireName,
      'plannedCount': day.plannedCount,
      'matchedCount': day.matchedCount,
      'workoutCount': day.workoutCount,
    };

/// An ended Logged Workout of [seconds] on [localDate].
ProgressWorkout _workout(
  String workoutId,
  String localDate,
  int seconds, {
  String? focusId,
}) {
  final startedAt = DateTime.parse('${localDate}T07:00:00.000Z');
  return ProgressWorkout(
    workoutId: workoutId,
    localDate: _date(localDate),
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(seconds: seconds)),
    focusId: focusId,
    linkedTemplateId: null,
    performedSetCount: 1,
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
