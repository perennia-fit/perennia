/// Pure resolution and expansion of a Workout Template's Prescriptions into
/// the exact ordered Sets a materialized Workout receives (ROUTINES.md
/// §1.3, §1.4, §3.2;;).
///
/// Materialize deliberately has no storage, UUID, or Activity Log concerns.
/// The only I/O this domain leaves to its caller is "what did this Exercise
/// last perform" — everything else (which value a Prescription resolves to,
/// how `repeat` unrolls into Sets, how Template Groups map to Exercise
/// Group member indexes) is a pure function so both the Dart client and the
/// later TypeScript parity runner can agree on it via golden vectors.
library;

import 'training_dimensions.dart';

/// How a materializing Prescription obtains its values.
enum MaterializePrescriptionMode { fixed, copyPrevious }

/// One Prescription about to materialize into Sets.
///
/// `fixedValues` is required for [MaterializePrescriptionMode.fixed] and
/// ignored otherwise. `lastPerformedValues` is the Exercise's most recent
/// performed Set values (already read by the caller); when absent for a
/// `copyPrevious` Prescription the Exercise was never performed and
/// materialize falls back to zero-values (never fabricated).
final class MaterializePrescriptionInput {
  const MaterializePrescriptionInput({
    required this.mode,
    this.fixedValues,
    this.lastPerformedValues,
    required this.repeat,
    required this.restAfter,
  });

  final MaterializePrescriptionMode mode;
  final LoggedSet? fixedValues;
  final LoggedSet? lastPerformedValues;
  final int repeat;
  final Duration? restAfter;
}

/// One planned Exercise entry with its ordered Prescriptions.
///
/// `dimensions` and `defaultLoadUnit` are static Exercise catalog metadata
/// (not history) — they are what let a never-performed `copyPrevious`
/// Prescription resolve to a deterministic zero-value Set without any I/O.
final class MaterializeExerciseInput {
  MaterializeExerciseInput({
    required this.exerciseId,
    required Iterable<DimensionId> dimensions,
    required this.defaultLoadUnit,
    required Iterable<MaterializePrescriptionInput> prescriptions,
  })  : dimensions = List<DimensionId>.unmodifiable(dimensions),
        prescriptions =
            List<MaterializePrescriptionInput>.unmodifiable(prescriptions);

  final String exerciseId;
  final List<DimensionId> dimensions;
  final TrainingUnit defaultLoadUnit;
  final List<MaterializePrescriptionInput> prescriptions;
}

/// One Template Group about to materialize into an Exercise Group.
///
/// `memberExerciseIndexes` points at positions in the materialize request's
/// exercise list, mirroring [MaterializeExerciseInput] the same way capture
/// keeps groups pure by indexing rather than owning generated ids.
final class MaterializeGroupInput {
  MaterializeGroupInput({
    required this.name,
    required this.colorHex,
    required Iterable<int> memberExerciseIndexes,
  }) : memberExerciseIndexes = List<int>.unmodifiable(memberExerciseIndexes);

  final String name;
  final String colorHex;
  final List<int> memberExerciseIndexes;
}

/// One resolved Set ready to write, in materialize order.
final class MaterializedSet {
  const MaterializedSet({
    required this.values,
    required this.plannedRestAfter,
  });

  final LoggedSet values;
  final Duration? plannedRestAfter;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MaterializedSet &&
            other.values == values &&
            other.plannedRestAfter == plannedRestAfter;
  }

  @override
  int get hashCode => Object.hash(values, plannedRestAfter);
}

/// One materialized Exercise and its ordered resolved Sets.
final class MaterializedWorkoutExercise {
  MaterializedWorkoutExercise({
    required this.exerciseId,
    required Iterable<MaterializedSet> sets,
  }) : sets = List<MaterializedSet>.unmodifiable(sets);

  final String exerciseId;
  final List<MaterializedSet> sets;
}

/// One materialized Exercise Group and its member Exercise indexes.
final class MaterializedWorkoutGroup {
  MaterializedWorkoutGroup({
    required this.name,
    required this.colorHex,
    required Iterable<int> memberExerciseIndexes,
  }) : memberExerciseIndexes = List<int>.unmodifiable(memberExerciseIndexes);

  final String name;
  final String colorHex;
  final List<int> memberExerciseIndexes;
}

/// The complete materialized content for one new Workout.
final class MaterializedWorkoutPlan {
  MaterializedWorkoutPlan({
    required Iterable<MaterializedWorkoutExercise> exercises,
    required Iterable<MaterializedWorkoutGroup> groups,
  })  : exercises = List<MaterializedWorkoutExercise>.unmodifiable(exercises),
        groups = List<MaterializedWorkoutGroup>.unmodifiable(groups);

  final List<MaterializedWorkoutExercise> exercises;
  final List<MaterializedWorkoutGroup> groups;
}

/// Resolves and expands a Workout Template's ordered Exercises and Groups
/// into the exact Sets and Exercise Groups a materialized Workout receives.
///
/// `fixed` Prescriptions repeat their own values; `copyPrevious`
/// Prescriptions repeat the Exercise's last performed values, or a
/// deterministic zero-value Set when the Exercise was never performed.
/// `repeat` always unrolls to that many identical Sets. Template
/// notes never participate here — materialize never writes them.
MaterializedWorkoutPlan materializeTemplateContent({
  required Iterable<MaterializeExerciseInput> exercises,
  required Iterable<MaterializeGroupInput> groups,
}) {
  final exerciseList = List<MaterializeExerciseInput>.unmodifiable(exercises);
  return MaterializedWorkoutPlan(
    exercises: exerciseList.map(_materializeExercise),
    groups: groups.map(
      (group) => MaterializedWorkoutGroup(
        name: group.name,
        colorHex: group.colorHex,
        memberExerciseIndexes: group.memberExerciseIndexes,
      ),
    ),
  );
}

MaterializedWorkoutExercise _materializeExercise(
  MaterializeExerciseInput exercise,
) {
  final sets = <MaterializedSet>[];
  for (final prescription in exercise.prescriptions) {
    final resolvedValues = _resolvePrescriptionValues(prescription, exercise);
    sets.addAll(
      List<MaterializedSet>.filled(
        prescription.repeat,
        MaterializedSet(
          values: resolvedValues,
          plannedRestAfter: prescription.restAfter,
        ),
      ),
    );
  }
  return MaterializedWorkoutExercise(
    exerciseId: exercise.exerciseId,
    sets: sets,
  );
}

LoggedSet _resolvePrescriptionValues(
  MaterializePrescriptionInput prescription,
  MaterializeExerciseInput exercise,
) {
  switch (prescription.mode) {
    case MaterializePrescriptionMode.fixed:
      final values = prescription.fixedValues;
      if (values == null) {
        throw ArgumentError.value(
          prescription,
          'prescription',
          'A fixed Prescription requires fixedValues.',
        );
      }
      return values;
    case MaterializePrescriptionMode.copyPrevious:
      return prescription.lastPerformedValues ??
          zeroLoggedSetFor(
            dimensions: exercise.dimensions,
            defaultLoadUnit: exercise.defaultLoadUnit,
          );
  }
}

/// Deterministic zero-value Set for an Exercise that has never been
/// performed. Every dimension entry is literally "0" in the Exercise's own
/// default units — materialize never fabricates a plausible value and never
/// leaves a copy-previous Prescription unresolved.
LoggedSet zeroLoggedSetFor({
  required List<DimensionId> dimensions,
  required TrainingUnit defaultLoadUnit,
}) {
  if (dimensions.isEmpty) {
    return LoggedSet.completion();
  }
  return LoggedSet.fromValues(
    dimensions.map((dimension) {
      final unit = switch (dimension) {
        DimensionId.load => defaultLoadUnit,
        DimensionId.reps => TrainingUnit.repetition,
        DimensionId.duration => TrainingUnit.second,
        DimensionId.distance => TrainingUnit.kilometer,
      };
      return SetDimensionValue(dimension: dimension, entered: '0', unit: unit);
    }),
  );
}
