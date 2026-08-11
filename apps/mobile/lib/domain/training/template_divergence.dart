/// The plan-learns-from-fact loop closed at Finish (ROUTINES.md §2, §3.4;
///).
///
/// **Divergence** = `captureWorkout(workout) != the linked Template's
/// content`, with two carve-outs: a `copyPrevious` Prescription matches *any*
/// performed values at its Set positions (copy-previous is the plan
/// working, not the plan drifting), and annotations can never diverge
/// because [captureWorkout] already strips them. This module reuses
/// [captureWorkout] rather than re-implementing fact projection.
///
/// **Update** content is computed in the same pass: capture's performed
/// values, re-tagged `copyPrevious` wherever every Set position a captured
/// Prescription block covers was planned that way and stayed unresolved.
/// Deliberately pure — no storage, UUID, or Activity Log concerns — so the
/// Dart client and the later TypeScript parity runner agree via golden
/// vectors.
library;

import 'training_dimensions.dart';
import 'workout_capture.dart';

/// Version of `m34-plan-divergence.schema.json` consumed by parity runners.
const int templateDivergenceGoldenSchemaVersion = 1;

/// How one planned Prescription slot obtains its values. Mirrors the data
/// layer's `PrescriptionMode` without importing storage types, keeping this
/// comparison pure and storage-independent.
enum TemplateDivergencePrescriptionMode { fixed, copyPrevious }

/// One planned Prescription, in comparable form — the Template side of a
/// divergence comparison.
final class TemplateDivergencePrescriptionSnapshot {
  const TemplateDivergencePrescriptionSnapshot({
    required this.mode,
    required this.values,
    required this.repeat,
    required this.restAfter,
  });

  final TemplateDivergencePrescriptionMode mode;

  /// Meaningful only for [TemplateDivergencePrescriptionMode.fixed]; a
  /// `copyPrevious` Prescription never stores performed values.
  final LoggedSet values;
  final int repeat;
  final Duration? restAfter;
}

/// One planned Exercise entry and its ordered Prescriptions, as currently
/// stored on the linked Template.
final class TemplateDivergenceExerciseSnapshot {
  TemplateDivergenceExerciseSnapshot({
    required this.exerciseId,
    required this.exerciseName,
    required Iterable<TemplateDivergencePrescriptionSnapshot> prescriptions,
  }) : prescriptions =
            List<TemplateDivergencePrescriptionSnapshot>.unmodifiable(
          prescriptions,
        );

  final String exerciseId;
  final String exerciseName;
  final List<TemplateDivergencePrescriptionSnapshot> prescriptions;
}

/// One planned Template Group — membership only. `rounds` cannot round-trip
/// through capture (a logged Workout never stores authored rounds; see
/// [CapturedTemplateGroupContent]), so it never participates in comparison.
final class TemplateDivergenceGroupSnapshot {
  TemplateDivergenceGroupSnapshot({
    required Iterable<String> memberExerciseIds,
  }) : memberExerciseIds = List<String>.unmodifiable(memberExerciseIds);

  final List<String> memberExerciseIds;
}

/// The currently-stored content of the linked Workout Template, in
/// comparable form. Built by the repository from stored Template records;
/// kept separate from those storage types so this comparison stays pure.
final class TemplateContentSnapshot {
  TemplateContentSnapshot({
    required Iterable<TemplateDivergenceExerciseSnapshot> exercises,
    required Iterable<TemplateDivergenceGroupSnapshot> groups,
  })  : exercises = List<TemplateDivergenceExerciseSnapshot>.unmodifiable(
          exercises,
        ),
        groups = List<TemplateDivergenceGroupSnapshot>.unmodifiable(groups);

  final List<TemplateDivergenceExerciseSnapshot> exercises;
  final List<TemplateDivergenceGroupSnapshot> groups;
}

/// One Exercise named in a divergence diff summary.
final class TemplateDivergenceExerciseRef {
  const TemplateDivergenceExerciseRef({
    required this.exerciseId,
    required this.exerciseName,
  });

  final String exerciseId;
  final String exerciseName;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TemplateDivergenceExerciseRef &&
            other.exerciseId == exerciseId &&
            other.exerciseName == exerciseName;
  }

  @override
  int get hashCode => Object.hash(exerciseId, exerciseName);
}

/// `capture(workout) != the linked Template's content` (ROUTINES.md §2,
/// §3.4).
///
/// `changedExercises` covers Exercises present in both whose Sets differ —
/// counted by name, not itemized by Set, because v1 offers no diff
/// cherry-picking (the Template editor covers surgery). A `copyPrevious`
/// Prescription matches any performed values for the Set positions it
/// covers; only its Set count and planned rest participate. Group `rounds`
/// never participates (capture cannot recover it); only membership does.
final class TemplateDivergenceResult {
  const TemplateDivergenceResult({
    required this.addedExercises,
    required this.removedExercises,
    required this.changedExercises,
    required this.groupsChanged,
  });

  final List<TemplateDivergenceExerciseRef> addedExercises;
  final List<TemplateDivergenceExerciseRef> removedExercises;
  final List<TemplateDivergenceExerciseRef> changedExercises;
  final bool groupsChanged;

  bool get hasDivergence =>
      addedExercises.isNotEmpty ||
      removedExercises.isNotEmpty ||
      changedExercises.isNotEmpty ||
      groupsChanged;
}

/// One reconciled Prescription for the Update verb: capture's performed
/// values, re-tagged `copyPrevious` when every Set position it covers was
/// planned that way and remains unresolved (ROUTINES.md §2 — Update
/// "preserving copy-previous modes").
final class TemplateUpdatePrescriptionContent {
  const TemplateUpdatePrescriptionContent({
    required this.mode,
    required this.values,
    required this.repeat,
    required this.restAfter,
  });

  final TemplateDivergencePrescriptionMode mode;
  final LoggedSet values;
  final int repeat;
  final Duration? restAfter;
}

final class TemplateUpdateExerciseContent {
  TemplateUpdateExerciseContent({
    required this.exerciseId,
    required Iterable<TemplateUpdatePrescriptionContent> prescriptions,
  }) : prescriptions =
            List<TemplateUpdatePrescriptionContent>.unmodifiable(
          prescriptions,
        );

  final String exerciseId;
  final List<TemplateUpdatePrescriptionContent> prescriptions;
}

/// Group content mirrors [CapturedTemplateGroupContent] exactly: rounds
/// always collapse to 1 (v1 Update is capture-replace, so a superset's
/// authored rounds cannot survive any more than a fresh capture's can).
final class TemplateUpdateGroupContent {
  TemplateUpdateGroupContent({
    required this.name,
    required this.colorHex,
    required Iterable<int> memberExerciseIndexes,
  }) : memberExerciseIndexes = List<int>.unmodifiable(memberExerciseIndexes);

  static const int rounds = 1;

  final String name;
  final String colorHex;
  final List<int> memberExerciseIndexes;
}

/// The complete Update-verb content tree: capture-replace of the linked
/// Template's content, with `copyPrevious` modes preserved wherever valid.
final class TemplateUpdateContent {
  TemplateUpdateContent({
    required Iterable<TemplateUpdateExerciseContent> exercises,
    required Iterable<TemplateUpdateGroupContent> groups,
  })  : exercises = List<TemplateUpdateExerciseContent>.unmodifiable(
          exercises,
        ),
        groups = List<TemplateUpdateGroupContent>.unmodifiable(groups);

  final List<TemplateUpdateExerciseContent> exercises;
  final List<TemplateUpdateGroupContent> groups;
}

/// Both halves of the plan-learns-from-fact loop, computed in one pass so
/// the Finish prompt's diff and the Update verb's write always agree.
final class TemplateDivergenceComparison {
  const TemplateDivergenceComparison({
    required this.divergence,
    required this.updatedContent,
  });

  final TemplateDivergenceResult divergence;
  final TemplateUpdateContent updatedContent;
}

/// Compares a Template's currently-stored content against one performed
/// Workout, reusing [captureWorkout] as the single fact-projection function.
TemplateDivergenceComparison compareTemplateToWorkout({
  required TemplateContentSnapshot template,
  required WorkoutCaptureSnapshot workout,
}) {
  final captured = captureWorkout(workout);
  final capturedExerciseIdByIndex = <String>[
    for (final exercise in captured.exercises) exercise.exerciseId,
  ];
  final capturedNameByExerciseId = <String, String>{
    for (final exercise in workout.exercises)
      exercise.exerciseId: exercise.exerciseName,
  };
  final templateByExerciseId = <String, TemplateDivergenceExerciseSnapshot>{
    for (final exercise in template.exercises) exercise.exerciseId: exercise,
  };
  final capturedExerciseIds = capturedExerciseIdByIndex.toSet();

  final addedExercises = <TemplateDivergenceExerciseRef>[];
  final changedExercises = <TemplateDivergenceExerciseRef>[];
  final updatedExercises = <TemplateUpdateExerciseContent>[];

  for (final exercise in captured.exercises) {
    final name = capturedNameByExerciseId[exercise.exerciseId] ??
        exercise.exerciseId;
    final templateExercise = templateByExerciseId[exercise.exerciseId];
    if (templateExercise == null) {
      addedExercises.add(
        TemplateDivergenceExerciseRef(
          exerciseId: exercise.exerciseId,
          exerciseName: name,
        ),
      );
      updatedExercises.add(_updateExerciseFromCaptureOnly(exercise));
      continue;
    }

    final expectedSlots = _expandTemplateExercise(templateExercise);
    final actualSlots = exercise.expandPrescriptions();
    if (_slotsDiverge(expectedSlots, actualSlots)) {
      changedExercises.add(
        TemplateDivergenceExerciseRef(
          exerciseId: exercise.exerciseId,
          exerciseName: name,
        ),
      );
    }
    updatedExercises.add(
      TemplateUpdateExerciseContent(
        exerciseId: exercise.exerciseId,
        prescriptions: _reconcilePrescriptions(
          capturedPrescriptions: exercise.prescriptions,
          expectedSlots: expectedSlots,
        ),
      ),
    );
  }

  final removedExercises = <TemplateDivergenceExerciseRef>[
    for (final exercise in template.exercises)
      if (!capturedExerciseIds.contains(exercise.exerciseId))
        TemplateDivergenceExerciseRef(
          exerciseId: exercise.exerciseId,
          exerciseName: exercise.exerciseName,
        ),
  ];

  final groupsChanged = _groupsDiffer(
    template.groups,
    captured.groups,
    capturedExerciseIdByIndex,
  );

  return TemplateDivergenceComparison(
    divergence: TemplateDivergenceResult(
      addedExercises: List<TemplateDivergenceExerciseRef>.unmodifiable(
        addedExercises,
      ),
      removedExercises: removedExercises,
      changedExercises: List<TemplateDivergenceExerciseRef>.unmodifiable(
        changedExercises,
      ),
      groupsChanged: groupsChanged,
    ),
    updatedContent: TemplateUpdateContent(
      exercises: updatedExercises,
      groups: captured.groups.map(
        (group) => TemplateUpdateGroupContent(
          name: group.name,
          colorHex: group.colorHex,
          memberExerciseIndexes: group.memberExerciseIndexes,
        ),
      ),
    ),
  );
}

final class _ExpectedSlot {
  const _ExpectedSlot({
    required this.mode,
    required this.values,
    required this.restAfter,
  });

  final TemplateDivergencePrescriptionMode mode;

  /// `null` for `copyPrevious` slots — a wildcard, never compared.
  final LoggedSet? values;
  final Duration? restAfter;
}

List<_ExpectedSlot> _expandTemplateExercise(
  TemplateDivergenceExerciseSnapshot exercise,
) {
  final slots = <_ExpectedSlot>[];
  for (final prescription in exercise.prescriptions) {
    final slot = _ExpectedSlot(
      mode: prescription.mode,
      values: prescription.mode == TemplateDivergencePrescriptionMode.fixed
          ? prescription.values
          : null,
      restAfter: prescription.restAfter,
    );
    slots.addAll(List<_ExpectedSlot>.filled(prescription.repeat, slot));
  }
  return slots;
}

bool _slotsDiverge(
  List<_ExpectedSlot> expected,
  List<WorkoutCaptureSetProjection> actual,
) {
  if (expected.length != actual.length) {
    return true;
  }
  for (var index = 0; index < expected.length; index += 1) {
    final expectedSlot = expected[index];
    final actualSlot = actual[index];
    if (expectedSlot.restAfter != actualSlot.plannedRestAfter) {
      return true;
    }
    if (expectedSlot.mode == TemplateDivergencePrescriptionMode.fixed &&
        expectedSlot.values != actualSlot.values) {
      return true;
    }
  }
  return false;
}

List<TemplateUpdatePrescriptionContent> _reconcilePrescriptions({
  required List<CapturedPrescriptionContent> capturedPrescriptions,
  required List<_ExpectedSlot> expectedSlots,
}) {
  final reconciled = <TemplateUpdatePrescriptionContent>[];
  var cursor = 0;
  for (final block in capturedPrescriptions) {
    final start = cursor;
    final end = cursor + block.repeat;
    cursor = end;
    final allCopyPreviousMatch = end <= expectedSlots.length &&
        List<int>.generate(block.repeat, (offset) => start + offset).every(
          (index) {
            final slot = expectedSlots[index];
            return slot.mode ==
                    TemplateDivergencePrescriptionMode.copyPrevious &&
                slot.restAfter == block.restAfter;
          },
        );
    reconciled.add(
      TemplateUpdatePrescriptionContent(
        mode: allCopyPreviousMatch
            ? TemplateDivergencePrescriptionMode.copyPrevious
            : TemplateDivergencePrescriptionMode.fixed,
        values: allCopyPreviousMatch ? LoggedSet.completion() : block.values,
        repeat: block.repeat,
        restAfter: block.restAfter,
      ),
    );
  }
  return reconciled;
}

TemplateUpdateExerciseContent _updateExerciseFromCaptureOnly(
  CapturedTemplateExerciseContent exercise,
) {
  return TemplateUpdateExerciseContent(
    exerciseId: exercise.exerciseId,
    prescriptions: exercise.prescriptions.map(
      (prescription) => TemplateUpdatePrescriptionContent(
        mode: TemplateDivergencePrescriptionMode.fixed,
        values: prescription.values,
        repeat: prescription.repeat,
        restAfter: prescription.restAfter,
      ),
    ),
  );
}

bool _groupsDiffer(
  List<TemplateDivergenceGroupSnapshot> templateGroups,
  List<CapturedTemplateGroupContent> capturedGroups,
  List<String> capturedExerciseIdByIndex,
) {
  final templateKeys = _groupKeySet(
    templateGroups.map((group) => group.memberExerciseIds),
  );
  final capturedKeys = _groupKeySet(
    capturedGroups.map(
      (group) => group.memberExerciseIndexes.map(
        (index) => capturedExerciseIdByIndex[index],
      ),
    ),
  );
  if (templateKeys.length != capturedKeys.length) {
    return true;
  }
  return !templateKeys.containsAll(capturedKeys);
}

Set<String> _groupKeySet(Iterable<Iterable<String>> groups) {
  return groups.map((memberIds) {
    final sorted = memberIds.toList()..sort();
    return sorted.join(' ');
  }).toSet();
}
