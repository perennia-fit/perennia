import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

void main() {
  group('dimension registry', () {
    test('exposes exactly the curated dimensions and valid units', () {
      expect(
        DimensionRegistry.ids,
        const <DimensionId>[
          DimensionId.load,
          DimensionId.reps,
          DimensionId.duration,
          DimensionId.distance,
        ],
      );

      expect(
        DimensionRegistry.byId(DimensionId.load).units,
        const <TrainingUnit>{TrainingUnit.kilogram, TrainingUnit.pound},
      );
      expect(
        DimensionRegistry.byId(DimensionId.reps).units,
        const <TrainingUnit>{TrainingUnit.repetition},
      );
      expect(
        DimensionRegistry.byId(DimensionId.duration).units,
        const <TrainingUnit>{TrainingUnit.second},
      );
      expect(
        DimensionRegistry.byId(DimensionId.distance).units,
        const <TrainingUnit>{TrainingUnit.kilometer, TrainingUnit.mile},
      );

      expect(
        DimensionRegistry.ids
            .map(DimensionRegistry.byId)
            .map((definition) => definition.id),
        DimensionRegistry.ids,
      );
    });

    test('supports empty completion-only exercise types', () {
      const type = ExerciseType.empty;
      final set = LoggedSet.completion();

      expect(type.isCompletionOnly, isTrue);
      expect(type.dimensions, isEmpty);
      expect(set.isCompletionOnly, isTrue);
      expect(set.values, isEmpty);
      expect(type.accepts(set), isTrue);
    });

    test('dimension definitions expose immutable unit snapshots', () {
      final units = <TrainingUnit>{TrainingUnit.kilogram};
      final definition = DimensionDefinition(
        id: DimensionId.load,
        units: units,
      );

      units.add(TrainingUnit.pound);

      expect(definition.units, const <TrainingUnit>{TrainingUnit.kilogram});
      expect(() => definition.units.add(TrainingUnit.pound),
          throwsUnsupportedError);
      expect(definition.allowsUnit(TrainingUnit.pound), isFalse);
      expect(() => DimensionRegistry.byId(DimensionId.load).units.clear(),
          throwsUnsupportedError);
    });
  });

  group('self-describing logged sets', () {
    test('preserve each entered value and unit exactly', () {
      final set = LoggedSet.fromValues(
        const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.load,
            entered: '100.50',
            unit: TrainingUnit.kilogram,
          ),
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '5',
            unit: TrainingUnit.repetition,
          ),
          SetDimensionValue(
            dimension: DimensionId.duration,
            entered: '60',
            unit: TrainingUnit.second,
          ),
          SetDimensionValue(
            dimension: DimensionId.distance,
            entered: '1.25',
            unit: TrainingUnit.mile,
          ),
        ],
      );

      expect(set.valueFor(DimensionId.load)?.entered, '100.50');
      expect(set.valueFor(DimensionId.load)?.unit, TrainingUnit.kilogram);
      expect(set.valueFor(DimensionId.reps)?.entered, '5');
      expect(set.valueFor(DimensionId.duration)?.unit, TrainingUnit.second);
      expect(set.valueFor(DimensionId.distance)?.entered, '1.25');
      expect(set.dimensionIds, DimensionRegistry.ids);
    });

    test('reject invalid unit and duplicate dimension combinations', () {
      expect(
        () => LoggedSet.fromValues(
          const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.reps,
              entered: '5',
              unit: TrainingUnit.kilogram,
            ),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => LoggedSet.fromValues(
          const <SetDimensionValue>[
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '100',
              unit: TrainingUnit.kilogram,
            ),
            SetDimensionValue(
              dimension: DimensionId.load,
              entered: '220',
              unit: TrainingUnit.pound,
            ),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('converts units only at computation time', () {
      const load = SetDimensionValue(
        dimension: DimensionId.load,
        entered: '220.462262',
        unit: TrainingUnit.pound,
      );
      const distance = SetDimensionValue(
        dimension: DimensionId.distance,
        entered: '1',
        unit: TrainingUnit.mile,
      );

      expect(load.entered, '220.462262');
      expect(load.convertedTo(TrainingUnit.kilogram), closeTo(100, 0.000001));
      expect(load.entered, '220.462262');

      expect(distance.convertedTo(TrainingUnit.kilometer),
          closeTo(1.609344, 0.000001));
      expect(
        const SetDimensionValue(
          dimension: DimensionId.duration,
          entered: '90',
          unit: TrainingUnit.second,
        ).convertedTo(TrainingUnit.second),
        90,
      );
    });

    test('compare set values by dimension, entered value, and unit', () {
      final load = SetDimensionValue(
        dimension: DimensionId.load,
        entered: '100.50',
        unit: TrainingUnit.kilogram,
      );
      final sameLoad = SetDimensionValue(
        dimension: DimensionId.load,
        entered: '100.50',
        unit: TrainingUnit.kilogram,
      );
      final differentLoad = SetDimensionValue(
        dimension: DimensionId.load,
        entered: '100.5',
        unit: TrainingUnit.kilogram,
      );

      expect(load, sameLoad);
      expect(load.hashCode, sameLoad.hashCode);
      expect(load, isNot(differentLoad));
    });
  });

  group('exercise type dimension sets', () {
    test('derive default record profiles from dimensions and load mode', () {
      final cases = <_RecordProfileCase>[
        _RecordProfileCase(
          type: ExerciseType.empty,
          loadMode: ExerciseLoadMode.added,
          profile: RecordProfile.completionStreak,
        ),
        _RecordProfileCase(
          type: ExerciseType(<DimensionId>[DimensionId.load]),
          loadMode: ExerciseLoadMode.added,
          profile: RecordProfile.maxLoad,
        ),
        _RecordProfileCase(
          type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
          loadMode: ExerciseLoadMode.added,
          profile: RecordProfile.repMax,
        ),
        _RecordProfileCase(
          type: ExerciseType(<DimensionId>[DimensionId.load, DimensionId.reps]),
          loadMode: ExerciseLoadMode.assisted,
          profile: RecordProfile.minAssistancePerRepCount,
        ),
        _RecordProfileCase(
          type: ExerciseType(<DimensionId>[DimensionId.reps]),
          loadMode: ExerciseLoadMode.added,
          profile: RecordProfile.maxReps,
        ),
        _RecordProfileCase(
          type: ExerciseType(<DimensionId>[DimensionId.duration]),
          loadMode: ExerciseLoadMode.added,
          profile: RecordProfile.maxDuration,
        ),
        _RecordProfileCase(
          type: ExerciseType(<DimensionId>[DimensionId.distance]),
          loadMode: ExerciseLoadMode.added,
          profile: RecordProfile.maxDistance,
        ),
        _RecordProfileCase(
          type: ExerciseType(<DimensionId>[
            DimensionId.distance,
            DimensionId.duration,
          ]),
          loadMode: ExerciseLoadMode.added,
          profile: RecordProfile.fastestPace,
        ),
      ];

      for (final entry in cases) {
        expect(
          defaultRecordProfileFor(
            type: entry.type,
            loadMode: entry.loadMode,
          ),
          entry.profile,
          reason: '${entry.type.dimensions.map((dimension) => dimension.name)} '
              '${entry.loadMode.name}',
        );
      }
    });

    test('preserve ordered dimensions and validate sets by carried fields', () {
      final strength = ExerciseType(<DimensionId>[
        DimensionId.load,
        DimensionId.reps,
      ]);

      final set = LoggedSet.fromValues(
        const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.load,
            entered: '80',
            unit: TrainingUnit.kilogram,
          ),
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '8',
            unit: TrainingUnit.repetition,
          ),
        ],
      );

      expect(strength.dimensions,
          const <DimensionId>[DimensionId.load, DimensionId.reps]);
      expect(strength.accepts(set), isTrue);
      expect(
        ExerciseType(<DimensionId>[DimensionId.duration]).accepts(set),
        isFalse,
      );
    });

    test('reject duplicate exercise type dimensions', () {
      expect(
        () => ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.load],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('compare exercise types by ordered dimensions', () {
      final strength = ExerciseType(<DimensionId>[
        DimensionId.load,
        DimensionId.reps,
      ]);
      final sameStrength = ExerciseType(<DimensionId>[
        DimensionId.load,
        DimensionId.reps,
      ]);
      final reversedStrength = ExerciseType(<DimensionId>[
        DimensionId.reps,
        DimensionId.load,
      ]);

      expect(strength, sameStrength);
      expect(strength.hashCode, sameStrength.hashCode);
      expect(strength, isNot(reversedStrength));
    });

    test('compare logged sets by carried dimension values', () {
      final set = LoggedSet.fromValues(
        const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.load,
            entered: '80',
            unit: TrainingUnit.kilogram,
          ),
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '8',
            unit: TrainingUnit.repetition,
          ),
        ],
      );
      final sameSet = LoggedSet.fromValues(
        const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '8',
            unit: TrainingUnit.repetition,
          ),
          SetDimensionValue(
            dimension: DimensionId.load,
            entered: '80',
            unit: TrainingUnit.kilogram,
          ),
        ],
      );
      final differentSet = LoggedSet.fromValues(
        const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.load,
            entered: '80.0',
            unit: TrainingUnit.kilogram,
          ),
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '8',
            unit: TrainingUnit.repetition,
          ),
        ],
      );

      expect(set, sameSet);
      expect(set.hashCode, sameSet.hashCode);
      expect(set, isNot(differentSet));
    });
  });
}

class _RecordProfileCase {
  const _RecordProfileCase({
    required this.type,
    required this.loadMode,
    required this.profile,
  });

  final ExerciseType type;
  final ExerciseLoadMode loadMode;
  final RecordProfile profile;
}
