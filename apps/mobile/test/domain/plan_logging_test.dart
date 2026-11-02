import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/plan_logging.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/domain/training/training_records.dart';

void main() {
  group('currentSetFor', () {
    test('is the first Planned Set', () {
      final sets = [
        _set('a', 0, done: true),
        _set('b', 1),
        _set('c', 2),
      ];
      expect(currentSetFor(sets)?.id, 'b');
    });

    test('is the picked Planned Set', () {
      final sets = [_set('a', 0), _set('b', 1), _set('c', 2)];
      expect(currentSetFor(sets, pickedSetId: 'c')?.id, 'c');
    });

    test('falls back to the first Planned Set when the pick is performed', () {
      final sets = [_set('a', 0, done: true), _set('b', 1), _set('c', 2)];
      expect(currentSetFor(sets, pickedSetId: 'a')?.id, 'b');
    });

    test('falls back when the pick is gone', () {
      final sets = [_set('a', 0), _set('b', 1)];
      expect(currentSetFor(sets, pickedSetId: 'missing')?.id, 'a');
    });

    test('is null when no Set is planned', () {
      expect(currentSetFor([_set('a', 0, done: true)]), isNull);
      expect(currentSetFor(const []), isNull);
    });

    test('orders tied positions by id', () {
      final sets = [_set('b', 0), _set('a', 0), _set('c', 1)];
      expect(currentSetFor(sets)?.id, 'a');
    });

    test('skips a deleted Set', () {
      final sets = [_set('a', 0, deleted: true), _set('b', 1)];
      expect(currentSetFor(sets)?.id, 'b');
    });
  });

  group('carryForwardFor', () {
    test('a weight missing from the plan fills the later Sets (CUJ 2)', () {
      final sets = [
        _set('1', 0, values: _lr('0', '10')),
        _set('2', 1, values: _lr('0', '10')),
        _set('3', 2, values: _lr('0', '10')),
      ];
      final targets = _carry(sets, sets[0], _lr('26', '10'));
      expect(targets, [
        _target('2', [_load('26')]),
        _target('3', [_load('26')]),
      ]);
    });

    test('a missed rep does not lower the plan (CUJ 3)', () {
      final sets = [
        _set('1', 0, values: _lr('100', '5')),
        _set('2', 1, values: _lr('100', '5')),
        _set('3', 2, values: _lr('100', '5')),
      ];
      expect(_carry(sets, sets[0], _lr('100', '4')), isEmpty);
    });

    test('a pyramid keeps its shape (CUJ 4)', () {
      final sets = [
        _set('1', 0, values: _lr('0', '10')),
        _set('2', 1, values: _lr('0', '8')),
        _set('3', 2, values: _lr('0', '6')),
      ];
      expect(_carry(sets, sets[0], _lr('40', '10')), [
        _target('2', [_load('40')]),
        _target('3', [_load('40')]),
      ]);
    });

    test(
        'a reps placeholder from copy-previous fills the later zeros '
        '(CUJ 4a)', () {
      final sets = [
        _set('1', 0, values: _r('0')),
        _set('2', 1, values: _r('0')),
        _set('3', 2, values: _r('0')),
      ];
      expect(_carry(sets, sets[0], _r('8')), [
        _target('2', [_reps('8')]),
        _target('3', [_reps('8')]),
      ]);
    });

    test('a duration placeholder fills the later zeros', () {
      final sets = [
        _set('1', 0, values: _d('0')),
        _set('2', 1, values: _d('0')),
      ];
      expect(_carry(sets, sets[0], _d('45')), [
        _target('2', [_duration('45')]),
      ]);
    });

    test('a distance placeholder fills the later zeros', () {
      final sets = [
        _set('1', 0, values: _km('0')),
        _set('2', 1, values: _km('0')),
      ];
      expect(_carry(sets, sets[0], _km('5')), [
        _target('2', [_distance('5')]),
      ]);
    });

    test('a "0.0" placeholder counts as zero', () {
      final sets = [
        _set('1', 0, values: _r('0.0')),
        _set('2', 1, values: _r('0.0')),
        _set('3', 2, values: _r('0')),
      ];
      expect(_carry(sets, sets[0], _r('8')), [
        _target('2', [_reps('8')]),
        _target('3', [_reps('8')]),
      ]);
    });

    test('a logged value over a non-zero planned rep carries nothing', () {
      final sets = [
        _set('1', 0, values: _r('5')),
        _set('2', 1, values: _r('0')),
      ];
      expect(_carry(sets, sets[0], _r('8')), isEmpty);
    });

    test('load and a placeholder carry together', () {
      final sets = [
        _set('1', 0, values: _lr('0', '0')),
        _set('2', 1, values: _lr('0', '0')),
      ];
      expect(_carry(sets, sets[0], _lr('20', '12')), [
        _target('2', [_load('20'), _reps('12')]),
      ]);
    });

    test('an unchanged load carries nothing', () {
      final sets = [
        _set('1', 0, values: _lr('60', '10')),
        _set('2', 1, values: _lr('60', '10')),
      ];
      expect(_carry(sets, sets[0], _lr('60', '10')), isEmpty);
    });

    test('a later Set with a different load is untouched', () {
      final sets = [
        _set('1', 0, values: _lr('60', '10')),
        _set('2', 1, values: _lr('70', '8')),
        _set('3', 2, values: _lr('60', '10')),
      ];
      expect(_carry(sets, sets[0], _lr('62.5', '10')), [
        _target('3', [_load('62.5')]),
      ]);
    });

    test('earlier Sets and later Performed Sets are untouched', () {
      final sets = [
        _set('1', 0, values: _lr('60', '10')),
        _set('2', 1, values: _lr('60', '10')),
        _set('3', 2, values: _lr('60', '10'), done: true),
        _set('4', 3, values: _lr('60', '10')),
      ];
      expect(_carry(sets, sets[1], _lr('65', '10')), [
        _target('4', [_load('65')]),
      ]);
    });

    test('later means plan order, not raw position', () {
      final sets = [
        _set('b', 0, values: _lr('60', '10')),
        _set('a', 0, values: _lr('60', '10')),
        _set('c', 0, values: _lr('60', '10')),
      ];
      expect(_carry(sets, sets[0], _lr('65', '10')), [
        _target('c', [_load('65')]),
      ]);
    });

    test('rest carries only when changed', () {
      final sets = [
        _set('1', 0, values: _lr('60', '10'), rest: _s(90)),
        _set('2', 1, values: _lr('60', '10'), rest: _s(90)),
      ];
      expect(
        carryForwardFor(
          exerciseSets: sets,
          logged: sets[0],
          newValues: _lr('60', '10'),
          restChanged: false,
          newRest: _s(120),
        ),
        isEmpty,
      );
    });

    test('rest carries only to equal rests', () {
      final sets = [
        _set('1', 0, values: _lr('60', '10'), rest: _s(90)),
        _set('2', 1, values: _lr('60', '10'), rest: _s(90)),
        _set('3', 2, values: _lr('60', '10'), rest: _s(60)),
        _set('4', 3, values: _lr('60', '10')),
      ];
      expect(
        carryForwardFor(
          exerciseSets: sets,
          logged: sets[0],
          newValues: _lr('60', '10'),
          restChanged: true,
          newRest: _s(120),
        ),
        [_target('2', const [], rest: _s(120))],
      );
    });

    test('two null rests are equal', () {
      final sets = [
        _set('1', 0, values: _lr('60', '10')),
        _set('2', 1, values: _lr('60', '10')),
        _set('3', 2, values: _lr('60', '10'), rest: _s(90)),
      ];
      expect(
        carryForwardFor(
          exerciseSets: sets,
          logged: sets[0],
          newValues: _lr('60', '10'),
          restChanged: true,
          newRest: _s(45),
        ),
        [_target('2', const [], rest: _s(45))],
      );
    });

    test('a target already holding the values is left out', () {
      final sets = [
        _set('1', 0, values: _r('0'), rest: _s(90)),
        _set('2', 1, values: _r('0.0'), rest: _s(90)),
        _set('3', 2, values: _r('0'), rest: _s(90)),
      ];
      // Logging "0.0" over "0": set 2 already holds "0.0", set 3 does not.
      expect(
        carryForwardFor(
          exerciseSets: sets,
          logged: sets[0],
          newValues: _r('0.0'),
          restChanged: true,
          newRest: _s(90),
        ),
        [
          _target('3', [_reps('0.0')]),
        ],
      );
    });

    test('"60" against "60.0" differ', () {
      final sets = [
        _set('1', 0, values: _lr('60', '10')),
        _set('2', 1, values: _lr('60', '10')),
        _set('3', 2, values: _lr('60.0', '10')),
      ];
      expect(_carry(sets, sets[0], _lr('60.0', '10')), [
        _target('2', [_load('60.0')]),
      ]);
    });

    test('a load in another unit differs', () {
      final sets = [
        _set('1', 0, values: _lr('60', '10')),
        _set('2', 1, values: _lr('60', '10')),
      ];
      final pounds = LoggedSet.fromValues([
        const SetDimensionValue(
          dimension: DimensionId.load,
          entered: '60',
          unit: TrainingUnit.pound,
        ),
        _reps('10'),
      ]);
      expect(_carry(sets, sets[0], pounds), [
        _target('2', [pounds.load!]),
      ]);
    });

    test('an exercise without load carries no load', () {
      final sets = [
        _set('1', 0, values: _r('10')),
        _set('2', 1, values: _r('10')),
      ];
      expect(_carry(sets, sets[0], _r('10')), isEmpty);
      expect(_carry(sets, sets[0], _lr('20', '10')), isEmpty);
    });
  });

  group('nextGroupMemberAfterLog', () {
    String? next({
      List<String> members = const ['a', 'b'],
      required String logged,
      Set<String> withPlan = const {'a', 'b'},
      bool planned = true,
      bool auto = true,
    }) {
      return nextGroupMemberAfterLog(
        memberIdsInOrder: members,
        loggedWorkoutExerciseId: logged,
        membersWithPlannedSetBefore: withPlan,
        loggedAPlannedSet: planned,
        autoSelectNextSet: auto,
      );
    }

    test('two members interleave', () {
      expect(next(logged: 'a'), 'b');
      expect(next(logged: 'b'), 'a');
    });

    test('three members wrap', () {
      const members = ['a', 'b', 'c'];
      const all = {'a', 'b', 'c'};
      expect(next(members: members, logged: 'b', withPlan: all), 'c');
      expect(next(members: members, logged: 'c', withPlan: all), 'a');
    });

    test('a member without Planned Sets is skipped', () {
      expect(
        next(members: ['a', 'b', 'c'], logged: 'a', withPlan: {'a', 'c'}),
        'c',
      );
    });

    test('none left is null, so the screen stays', () {
      expect(next(logged: 'b', withPlan: {'b'}), isNull);
      expect(next(logged: 'b', withPlan: const {}), isNull);
    });

    test('a freestyle superset wraps to the next member', () {
      expect(next(logged: 'b', withPlan: const {}, planned: false), 'a');
      expect(
        next(
          members: ['a', 'b', 'c'],
          logged: 'a',
          withPlan: const {},
          planned: false,
        ),
        'b',
      );
    });

    test('a Set logged after the plan wraps to the next member', () {
      expect(next(logged: 'a', withPlan: {'a'}, planned: false), 'b');
    });

    test('ungrouped is null', () {
      expect(next(members: const [], logged: 'a', withPlan: {'a'}), isNull);
      expect(next(members: ['a'], logged: 'a', withPlan: {'a'}), isNull);
    });

    test('Auto-select next set off is null', () {
      expect(next(logged: 'a', auto: false), isNull);
      expect(next(logged: 'a', planned: false, auto: false), isNull);
    });
  });

  group('groupRoundFor', () {
    test('equal counts', () {
      expect(
        groupRoundFor([
          (performed: 1, planned: 2),
          (performed: 1, planned: 2),
        ]),
        const GroupRoundInProgress(round: 2, of: 3),
      );
      expect(
        groupRoundFor([
          (performed: 1, planned: 2),
          (performed: 0, planned: 3),
        ]),
        const GroupRoundInProgress(round: 1, of: 3),
      );
    });

    test('unequal counts follow the member with the most left', () {
      expect(
        groupRoundFor([
          (performed: 2, planned: 2),
          (performed: 2, planned: 0),
        ]),
        const GroupRoundInProgress(round: 3, of: 4),
      );
    });

    test('a member with no Sets is left out', () {
      expect(
        groupRoundFor([
          (performed: 1, planned: 1),
          (performed: 0, planned: 0),
        ]),
        const GroupRoundInProgress(round: 2, of: 2),
      );
    });

    test('a replaced member keeps the round', () {
      // Pull-Up 1 performed, 2 planned; its replaced partner has no
      // Performed Set but the same two Planned Sets left.
      expect(
        groupRoundFor([
          (performed: 1, planned: 2),
          (performed: 0, planned: 2),
        ]),
        const GroupRoundInProgress(round: 2, of: 3),
      );
    });

    test('all done', () {
      expect(
        groupRoundFor([
          (performed: 3, planned: 0),
          (performed: 3, planned: 0),
        ]),
        const GroupRoundAllDone(),
      );
    });

    test('no Sets is null', () {
      expect(groupRoundFor(const []), isNull);
      expect(
        groupRoundFor([
          (performed: 0, planned: 0),
          (performed: 0, planned: 0),
        ]),
        isNull,
      );
    });
  });

  group('restShownFor', () {
    test("a Set's planned rest", () {
      expect(
        restShownFor(
          shownSet: _set('1', 0, rest: _s(90)),
          lastSetOfExercise: _set('2', 1, rest: _s(30)),
          rememberedRest: _s(60),
        ),
        _s(90),
      );
    });

    test('the Remembered Rest when the Set has none', () {
      expect(
        restShownFor(
          shownSet: _set('1', 0),
          lastSetOfExercise: _set('2', 1, rest: _s(30)),
          rememberedRest: _s(60),
        ),
        _s(60),
      );
    });

    test('120 s when nothing gives one', () {
      expect(
        restShownFor(
          shownSet: _set('1', 0),
          lastSetOfExercise: null,
          rememberedRest: null,
        ),
        const Duration(seconds: 120),
      );
      expect(defaultRestAfter, const Duration(seconds: 120));
    });

    test("with no Current Set, the last Set's rest", () {
      expect(
        restShownFor(
          shownSet: null,
          lastSetOfExercise: _set('2', 1, rest: _s(30)),
          rememberedRest: _s(60),
        ),
        _s(30),
      );
    });

    test('with no Current Set, then the Remembered Rest', () {
      expect(
        restShownFor(
          shownSet: null,
          lastSetOfExercise: _set('2', 1),
          rememberedRest: _s(60),
        ),
        _s(60),
      );
      expect(
        restShownFor(
          shownSet: null,
          lastSetOfExercise: null,
          rememberedRest: _s(60),
        ),
        _s(60),
      );
    });

    test('with no Current Set, then 120 s', () {
      expect(
        restShownFor(
          shownSet: null,
          lastSetOfExercise: _set('2', 1),
          rememberedRest: null,
        ),
        defaultRestAfter,
      );
    });

    test('a planned zero is kept', () {
      expect(
        restShownFor(
          shownSet: _set('1', 0, rest: Duration.zero),
          lastSetOfExercise: null,
          rememberedRest: _s(60),
        ),
        Duration.zero,
      );
      expect(
        restShownFor(
          shownSet: null,
          lastSetOfExercise: _set('2', 1, rest: Duration.zero),
          rememberedRest: _s(60),
        ),
        Duration.zero,
      );
    });
  });

  group('currentExerciseFor and nextExerciseWithPlan', () {
    test('an in-progress exercise', () {
      expect(
        currentExerciseFor([
          _progress('bench', performed: 3, planned: 0, at: 5),
          _progress('squat', performed: 1, planned: 2, at: 6),
          _progress('row', planned: 3),
        ]),
        const CurrentWorkoutExercise('squat'),
      );
    });

    test('an in-progress group, across its members', () {
      expect(
        currentExerciseFor([
          _progress('press', group: 'g', performed: 3, planned: 0, at: 6),
          _progress('pull', group: 'g', planned: 3),
          _progress('triceps', planned: 2),
        ]),
        const CurrentGroup('g'),
      );
    });

    test('the group after a Replace keeps Now (CUJ 13)', () {
      expect(
        currentExerciseFor([
          _progress('pull-up', group: 'g', performed: 1, planned: 2, at: 5),
          _progress('machine-press', group: 'g', planned: 2),
          _progress('incline-press', performed: 1, planned: 0, at: 6),
          _progress('triceps', planned: 2),
        ]),
        const CurrentGroup('g'),
      );
    });

    test('moving on from a finished exercise', () {
      expect(
        currentExerciseFor([
          _progress('bench', performed: 3, planned: 0, at: 5),
          _progress('row', planned: 3),
        ]),
        const CurrentWorkoutExercise('row'),
      );
    });

    test('moving on from a finished group', () {
      expect(
        currentExerciseFor([
          _progress('press', group: 'g', performed: 3, planned: 0, at: 5),
          _progress('pull', group: 'g', performed: 3, planned: 0, at: 6),
          _progress('triceps', planned: 2),
        ]),
        const CurrentWorkoutExercise('triceps'),
      );
    });

    test('moving on goes from the latest performed exercise', () {
      expect(
        currentExerciseFor([
          _progress('bench', planned: 3),
          _progress('squat', performed: 3, planned: 0, at: 9),
          _progress('row', performed: 3, planned: 0, at: 5),
          _progress('curl', planned: 2),
        ]),
        const CurrentWorkoutExercise('curl'),
      );
    });

    test('wrapping', () {
      expect(
        currentExerciseFor([
          _progress('bench', planned: 3),
          _progress('row', performed: 3, planned: 0, at: 5),
        ]),
        const CurrentWorkoutExercise('bench'),
      );
      expect(
        nextExerciseWithPlan(
          exercises: [
            _progress('bench', planned: 3),
            _progress('press', group: 'g', planned: 0),
            _progress('pull', group: 'g', planned: 0),
          ],
          fromWorkoutExerciseId: 'press',
        ),
        'bench',
      );
    });

    test('no Performed Set is the first exercise with a plan', () {
      expect(
        currentExerciseFor([
          _progress('warm-up'),
          _progress('press', group: 'g', planned: 3),
          _progress('pull', group: 'g', planned: 3),
        ]),
        const CurrentGroup('g'),
      );
    });

    test('nothing planned is null', () {
      expect(currentExerciseFor(const []), isNull);
      expect(currentExerciseFor([_progress('bench')]), isNull);
      expect(
        currentExerciseFor([
          _progress('bench', performed: 3, planned: 0, at: 5),
        ]),
        isNull,
      );
    });

    test('next skips the start and its group, and is null with no plan', () {
      final exercises = [
        _progress('press', group: 'g', planned: 2),
        _progress('pull', group: 'g', planned: 2),
        _progress('triceps', planned: 0),
      ];
      expect(
        nextExerciseWithPlan(
          exercises: exercises,
          fromWorkoutExerciseId: 'press',
        ),
        isNull,
      );
      expect(
        nextExerciseWithPlan(
          exercises: exercises,
          fromWorkoutExerciseId: 'triceps',
        ),
        'press',
      );
      expect(
        nextExerciseWithPlan(
          exercises: exercises,
          fromWorkoutExerciseId: 'missing',
        ),
        isNull,
      );
    });
  });
}

final _createdAt = DateTime.utc(2026, 11, 2, 9);

LoggedSetRecord _set(
  String id,
  int position, {
  LoggedSet? values,
  Duration? rest,
  bool done = false,
  bool deleted = false,
}) {
  return LoggedSetRecord(
    id: id,
    workoutId: 'workout',
    exerciseId: 'exercise',
    position: position,
    values: values ?? _lr('60', '10'),
    plannedRestAfter: rest,
    performedAt: done ? _createdAt : null,
    isCompleted: done,
    updatedAt: _createdAt,
    deletedAt: deleted ? _createdAt : null,
  );
}

List<CarryTarget> _carry(
  List<LoggedSetRecord> sets,
  LoggedSetRecord logged,
  LoggedSet newValues,
) {
  return carryForwardFor(
    exerciseSets: sets,
    logged: logged,
    newValues: newValues,
    restChanged: false,
    newRest: null,
  );
}

CarryTarget _target(
  String setId,
  List<SetDimensionValue> values, {
  Duration? rest,
}) {
  return CarryTarget(
    setId: setId,
    values: values,
    rest: rest,
    restChanged: rest != null,
  );
}

ProgressExercise _progress(
  String id, {
  String? group,
  int performed = 0,
  int planned = 0,
  int? at,
}) {
  return ProgressExercise(
    workoutExerciseId: id,
    groupId: group,
    performed: performed,
    planned: planned,
    latestPerformedAt: at == null ? null : _createdAt.add(Duration(hours: at)),
  );
}

Duration _s(int seconds) => Duration(seconds: seconds);

SetDimensionValue _load(String entered) => SetDimensionValue(
      dimension: DimensionId.load,
      entered: entered,
      unit: TrainingUnit.kilogram,
    );

SetDimensionValue _reps(String entered) => SetDimensionValue(
      dimension: DimensionId.reps,
      entered: entered,
      unit: TrainingUnit.repetition,
    );

SetDimensionValue _duration(String entered) => SetDimensionValue(
      dimension: DimensionId.duration,
      entered: entered,
      unit: TrainingUnit.second,
    );

SetDimensionValue _distance(String entered) => SetDimensionValue(
      dimension: DimensionId.distance,
      entered: entered,
      unit: TrainingUnit.kilometer,
    );

LoggedSet _lr(String load, String reps) =>
    LoggedSet.fromValues([_load(load), _reps(reps)]);

LoggedSet _r(String reps) => LoggedSet.fromValues([_reps(reps)]);

LoggedSet _d(String seconds) => LoggedSet.fromValues([_duration(seconds)]);

LoggedSet _km(String kilometers) =>
    LoggedSet.fromValues([_distance(kilometers)]);
