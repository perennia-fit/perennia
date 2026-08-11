/// Pure conversion from an authored Workout fact tree into reusable Workout
/// Template content (ROUTINES.md section 2).
///
/// Capture deliberately has no storage, UUID, navigation, or Activity Log
/// concerns. The same ordered snapshot can therefore drive the Dart client and
/// the later TypeScript parity runner without either implementation guessing
/// which fact annotations belong in a plan.
library;

import 'dart:convert';

import 'set_validation.dart';
import 'training_dimensions.dart';

/// Version of `m33-workout-capture.schema.json` consumed by parity runners.
const int workoutCaptureGoldenSchemaVersion = 1;

/// Where the newly captured Workout Template should also be referenced.
sealed class WorkoutCapturePlacement {
  const WorkoutCapturePlacement();

  const factory WorkoutCapturePlacement.none() = WorkoutCaptureNoPlacement;

  const factory WorkoutCapturePlacement.collectionAppend(String routineId) =
      WorkoutCaptureCollectionAppendPlacement;

  const factory WorkoutCapturePlacement.cadenceSlot(
    String routineId,
    int slot,
  ) = WorkoutCaptureCadenceSlotPlacement;
}

final class WorkoutCaptureNoPlacement extends WorkoutCapturePlacement {
  const WorkoutCaptureNoPlacement();
}

final class WorkoutCaptureCollectionAppendPlacement
    extends WorkoutCapturePlacement {
  const WorkoutCaptureCollectionAppendPlacement(this.routineId);

  final String routineId;
}

final class WorkoutCaptureCadenceSlotPlacement extends WorkoutCapturePlacement {
  const WorkoutCaptureCadenceSlotPlacement(this.routineId, this.slot);

  final String routineId;
  final int slot;
}

/// User choices for one save-as-new capture operation.
final class WorkoutCaptureSaveRequest {
  WorkoutCaptureSaveRequest({
    required this.workoutId,
    required this.name,
    this.placement = const WorkoutCapturePlacement.none(),
    Iterable<String> acknowledgedWarningTokens = const <String>[],
  }) : acknowledgedWarningTokens = Set<String>.unmodifiable(
          acknowledgedWarningTokens,
        );

  final String workoutId;
  final String name;
  final WorkoutCapturePlacement placement;

  /// The exact warning fingerprints last shown to and acknowledged by the
  /// caller. Save rejects both missing and unexpected tokens after re-reading
  /// authoritative Workout and Routine state.
  final Set<String> acknowledgedWarningTokens;
}

/// Stable identities created by one atomic capture batch.
final class WorkoutCaptureSaveResult {
  const WorkoutCaptureSaveResult({
    required this.workoutTemplateId,
    required this.routineEntryId,
    required this.activityBatchId,
  });

  final String workoutTemplateId;
  final String? routineEntryId;
  final String activityBatchId;
}

/// One shared validation issue with its deterministic location in the capture
/// request. Shared rule, message, field, dimension, and limit values remain
/// unchanged; [sourcePath] disambiguates repeated plan-tree issues.
final class WorkoutCaptureValidationIssue {
  const WorkoutCaptureValidationIssue({
    required this.sourcePath,
    required this.issue,
  });

  static const int acknowledgementSchemaVersion = 1;

  final String sourcePath;
  final SetValidationIssue issue;

  String get field => issue.field;
  DimensionId? get dimension => issue.dimension;
  String get rule => issue.rule;
  String get message => issue.message;
  Object? get limit => issue.limit;

  String get fieldPath {
    if (sourcePath.isEmpty) {
      return field;
    }
    if (field.isEmpty) {
      return sourcePath;
    }
    return '$sourcePath.$field';
  }

  /// Language-neutral canonical JSON is the issue fingerprint. It is
  /// intentionally inspectable rather than an opaque process-local hash.
  String get fingerprintToken {
    return jsonEncode(<String, Object?>{
      'schemaVersion': acknowledgementSchemaVersion,
      'sourcePath': sourcePath,
      'field': field,
      'dimension': dimension?.name,
      'rule': rule,
      'message': message,
      'limit': _canonicalCaptureTokenValue(limit),
    });
  }

  /// Warning fingerprints are submitted verbatim as acknowledgements.
  String get acknowledgementToken => fingerprintToken;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WorkoutCaptureValidationIssue &&
            other.fingerprintToken == fingerprintToken;
  }

  @override
  int get hashCode => fingerprintToken.hashCode;
}

/// Ordered validation for captured content plus optional placement.
final class WorkoutCaptureValidationResult {
  WorkoutCaptureValidationResult({
    Iterable<WorkoutCaptureValidationIssue> errors =
        const <WorkoutCaptureValidationIssue>[],
    Iterable<WorkoutCaptureValidationIssue> warnings =
        const <WorkoutCaptureValidationIssue>[],
  })  : errors = List<WorkoutCaptureValidationIssue>.unmodifiable(errors),
        warnings = List<WorkoutCaptureValidationIssue>.unmodifiable(warnings) {
    _requireDistinctCaptureIssues(this.errors, label: 'errors');
    _requireDistinctCaptureIssues(this.warnings, label: 'warnings');
  }

  final List<WorkoutCaptureValidationIssue> errors;
  final List<WorkoutCaptureValidationIssue> warnings;

  bool get accepted => errors.isEmpty;

  /// Stable validation order, suitable for display and exact resubmission.
  List<String> get warningAcknowledgementTokens {
    return List<String>.unmodifiable(
      warnings.map((warning) => warning.acknowledgementToken),
    );
  }

  Set<String> get warningAcknowledgementTokenSet {
    return Set<String>.unmodifiable(warningAcknowledgementTokens);
  }
}

/// Read-only capture preview used to populate the save sheet.
final class WorkoutCapturePreview {
  const WorkoutCapturePreview({
    required this.workoutId,
    required this.content,
    required this.suggestedName,
    required this.exerciseCount,
    required this.setCount,
    required this.groupCount,
    required this.validation,
  });

  final String workoutId;
  final CapturedWorkoutTemplateContent content;
  final String suggestedName;
  final int exerciseCount;
  final int setCount;
  final int groupCount;
  final WorkoutCaptureValidationResult validation;
}

/// Capture output failed hard validation after authoritative re-read.
final class WorkoutCaptureValidationException implements Exception {
  const WorkoutCaptureValidationException(this.validation);

  final WorkoutCaptureValidationResult validation;

  @override
  String toString() {
    final rules = validation.errors
        .map((error) => '${error.fieldPath}:${error.rule}')
        .join(', ');
    return 'WorkoutCaptureValidationException: $rules';
  }
}

/// The exact authoritative warning set was not acknowledged.
final class WorkoutCaptureWarningsNotAcknowledged implements Exception {
  WorkoutCaptureWarningsNotAcknowledged({
    required this.validation,
    required Iterable<String> providedWarningTokens,
  }) : providedWarningTokens = Set<String>.unmodifiable(
          providedWarningTokens,
        );

  final WorkoutCaptureValidationResult validation;
  final Set<String> providedWarningTokens;

  Set<String> get expectedWarningTokens =>
      validation.warningAcknowledgementTokenSet;

  Set<String> get missingWarningTokens => Set<String>.unmodifiable(
        expectedWarningTokens.difference(providedWarningTokens),
      );

  Set<String> get unexpectedWarningTokens => Set<String>.unmodifiable(
        providedWarningTokens.difference(expectedWarningTokens),
      );

  @override
  String toString() {
    return 'WorkoutCaptureWarningsNotAcknowledged: '
        'missing=${missingWarningTokens.length}, '
        'unexpected=${unexpectedWarningTokens.length}';
  }
}

/// The authoritative, ordered Workout facts consumed by [captureWorkout].
final class WorkoutCaptureSnapshot {
  WorkoutCaptureSnapshot({
    required this.workoutId,
    required Iterable<WorkoutCaptureExerciseSnapshot> exercises,
    required Iterable<WorkoutCaptureGroupSnapshot> groups,
    this.comment,
    this.startedAt,
    this.endedAt,
  })  : exercises = List<WorkoutCaptureExerciseSnapshot>.unmodifiable(
          exercises,
        ),
        groups = List<WorkoutCaptureGroupSnapshot>.unmodifiable(groups);

  final String workoutId;

  /// Fact-only commentary. It is present on the input so tests can prove that
  /// capture cannot accidentally promote it to reusable plan guidance.
  final String? comment;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<WorkoutCaptureExerciseSnapshot> exercises;
  final List<WorkoutCaptureGroupSnapshot> groups;
}

/// One active Workout Exercise and its ordered active Sets.
final class WorkoutCaptureExerciseSnapshot {
  WorkoutCaptureExerciseSnapshot({
    required this.sourceWorkoutExerciseId,
    required this.exerciseId,
    required this.exerciseName,
    required this.position,
    required Iterable<WorkoutCaptureSetSnapshot> sets,
  }) : sets = List<WorkoutCaptureSetSnapshot>.unmodifiable(sets);

  final String sourceWorkoutExerciseId;
  final String exerciseId;
  final String exerciseName;
  final int position;
  final List<WorkoutCaptureSetSnapshot> sets;
}

/// One logged Set, including the annotations that capture must strip.
final class WorkoutCaptureSetSnapshot {
  const WorkoutCaptureSetSnapshot({
    required this.sourceSetId,
    required this.position,
    required this.values,
    required this.plannedRestAfter,
    this.comment,
    this.side,
    this.rpe,
    this.isCompleted = false,
    this.performedAt,
  });

  final String sourceSetId;
  final int position;
  final LoggedSet values;
  final Duration? plannedRestAfter;
  final String? comment;
  final String? side;
  final double? rpe;
  final bool isCompleted;
  final DateTime? performedAt;

  WorkoutCaptureSetProjection get projection {
    return WorkoutCaptureSetProjection(
      values: values,
      plannedRestAfter: plannedRestAfter,
    );
  }
}

/// One active authored Workout group in display order.
final class WorkoutCaptureGroupSnapshot {
  WorkoutCaptureGroupSnapshot({
    required this.sourceGroupId,
    required this.name,
    required this.colorHex,
    required this.position,
    required Iterable<String> memberSourceWorkoutExerciseIds,
  }) : memberSourceWorkoutExerciseIds = List<String>.unmodifiable(
          memberSourceWorkoutExerciseIds,
        );

  final String sourceGroupId;
  final String name;
  final String colorHex;
  final int position;
  final List<String> memberSourceWorkoutExerciseIds;
}

/// Storage-independent content for one newly captured Workout Template.
final class CapturedWorkoutTemplateContent {
  CapturedWorkoutTemplateContent({
    required Iterable<CapturedTemplateExerciseContent> exercises,
    required Iterable<CapturedTemplateGroupContent> groups,
  })  : exercises = List<CapturedTemplateExerciseContent>.unmodifiable(
          exercises,
        ),
        groups = List<CapturedTemplateGroupContent>.unmodifiable(groups);

  final List<CapturedTemplateExerciseContent> exercises;
  final List<CapturedTemplateGroupContent> groups;
}

/// One Exercise reference and the fixed Prescription blocks captured for it.
final class CapturedTemplateExerciseContent {
  CapturedTemplateExerciseContent({
    required this.exerciseId,
    required Iterable<CapturedPrescriptionContent> prescriptions,
  }) : prescriptions = List<CapturedPrescriptionContent>.unmodifiable(
          prescriptions,
        );

  final String exerciseId;
  final List<CapturedPrescriptionContent> prescriptions;

  /// Expands run-length encoded Prescriptions back to the exact fact
  /// projection. This is intentionally public so parity tests can assert that
  /// capture is lossless without comparing incidental Set annotations.
  List<WorkoutCaptureSetProjection> expandPrescriptions() {
    return List<WorkoutCaptureSetProjection>.unmodifiable(
      prescriptions.expand(
        (prescription) => List<WorkoutCaptureSetProjection>.filled(
          prescription.repeat,
          prescription.projection,
        ),
      ),
    );
  }
}

/// A fixed-only Prescription produced by capture.
///
/// There is deliberately no writable mode: capture can never manufacture a
/// copy-previous Prescription.
final class CapturedPrescriptionContent {
  const CapturedPrescriptionContent({
    required this.values,
    required this.repeat,
    required this.restAfter,
  });

  static const String mode = 'fixed';

  final LoggedSet values;
  final int repeat;
  final Duration? restAfter;

  WorkoutCaptureSetProjection get projection {
    return WorkoutCaptureSetProjection(
      values: values,
      plannedRestAfter: restAfter,
    );
  }
}

/// Group content points at captured Exercise indexes rather than generated
/// database ids, keeping the conversion pure and language-neutral.
final class CapturedTemplateGroupContent {
  CapturedTemplateGroupContent({
    required this.name,
    required this.colorHex,
    required Iterable<int> memberExerciseIndexes,
  }) : memberExerciseIndexes = List<int>.unmodifiable(
          memberExerciseIndexes,
        );

  /// Logged Workout groups do not store authored rounds. One round preserves
  /// every captured Set exactly; inferring a larger value would duplicate work
  /// when this Template is materialized again.
  static const int rounds = 1;

  final String name;
  final String colorHex;
  final List<int> memberExerciseIndexes;
}

/// The only Set fields that survive capture and participate in repeat
/// collapse equality.
final class WorkoutCaptureSetProjection {
  const WorkoutCaptureSetProjection({
    required this.values,
    required this.plannedRestAfter,
  });

  final LoggedSet values;
  final Duration? plannedRestAfter;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WorkoutCaptureSetProjection &&
            other.values == values &&
            other.plannedRestAfter == plannedRestAfter;
  }

  @override
  int get hashCode => Object.hash(values, plannedRestAfter);
}

/// Converts one ordered Workout snapshot into fixed-only Template content.
///
/// Adjacent Sets collapse only when their self-describing values (including
/// exact entered strings and units) and planned rest are equal. Commentary,
/// RPE, side, completion, and timing are projected away before equality is
/// considered.
CapturedWorkoutTemplateContent captureWorkout(
  WorkoutCaptureSnapshot snapshot,
) {
  final sourceExerciseIndexes = <String, int>{};
  final exerciseIds = <String>{};
  final capturedExercises = <CapturedTemplateExerciseContent>[];

  for (var index = 0; index < snapshot.exercises.length; index += 1) {
    final exercise = snapshot.exercises[index];
    if (exercise.sourceWorkoutExerciseId.trim().isEmpty) {
      throw ArgumentError.value(
        exercise.sourceWorkoutExerciseId,
        'sourceWorkoutExerciseId',
        'Workout Exercise id is required.',
      );
    }
    if (sourceExerciseIndexes.containsKey(exercise.sourceWorkoutExerciseId)) {
      throw ArgumentError.value(
        exercise.sourceWorkoutExerciseId,
        'sourceWorkoutExerciseId',
        'Workout Exercise ids must be unique.',
      );
    }
    if (exercise.exerciseId.trim().isEmpty ||
        !exerciseIds.add(exercise.exerciseId)) {
      throw ArgumentError.value(
        exercise.exerciseId,
        'exerciseId',
        'Captured Exercise ids must be non-empty and unique.',
      );
    }
    sourceExerciseIndexes[exercise.sourceWorkoutExerciseId] = index;
    capturedExercises.add(
      CapturedTemplateExerciseContent(
        exerciseId: exercise.exerciseId,
        prescriptions: _collapseSets(exercise.sets),
      ),
    );
  }

  final groupedExerciseIndexes = <int>{};
  final capturedGroups = <CapturedTemplateGroupContent>[];
  for (final group in snapshot.groups) {
    final memberIndexes = <int>[];
    final memberIds = <String>{};
    for (final sourceId in group.memberSourceWorkoutExerciseIds) {
      final index = sourceExerciseIndexes[sourceId];
      if (index == null) {
        throw ArgumentError.value(
          sourceId,
          'memberSourceWorkoutExerciseIds',
          'Captured group members must reference captured Workout Exercises.',
        );
      }
      if (!memberIds.add(sourceId)) {
        throw ArgumentError.value(
          sourceId,
          'memberSourceWorkoutExerciseIds',
          'Captured group members must be unique.',
        );
      }
      if (!groupedExerciseIndexes.add(index)) {
        throw ArgumentError.value(
          sourceId,
          'memberSourceWorkoutExerciseIds',
          'A captured Exercise can belong to only one group.',
        );
      }
      memberIndexes.add(index);
    }
    capturedGroups.add(
      CapturedTemplateGroupContent(
        name: group.name,
        colorHex: group.colorHex,
        memberExerciseIndexes: memberIndexes,
      ),
    );
  }

  return CapturedWorkoutTemplateContent(
    exercises: capturedExercises,
    groups: capturedGroups,
  );
}

/// Deterministic name prefill based on the two Exercises with most active
/// Sets. Ties use authored position then stable source identity.
String suggestCapturedWorkoutTemplateName(WorkoutCaptureSnapshot snapshot) {
  if (snapshot.exercises.isEmpty) {
    return '';
  }

  final ranked = snapshot.exercises.toList(growable: false)
    ..sort((left, right) {
      final count = right.sets.length.compareTo(left.sets.length);
      if (count != 0) {
        return count;
      }
      final position = left.position.compareTo(right.position);
      if (position != 0) {
        return position;
      }
      return left.sourceWorkoutExerciseId.compareTo(
        right.sourceWorkoutExerciseId,
      );
    });
  final hasLoggedSets = ranked.any((exercise) => exercise.sets.isNotEmpty);
  final dominant = hasLoggedSets
      ? ranked.where((exercise) => exercise.sets.isNotEmpty)
      : ranked;
  return dominant
      .take(2)
      .map((exercise) => exercise.exerciseName.trim())
      .join(' + ');
}

List<CapturedPrescriptionContent> _collapseSets(
  List<WorkoutCaptureSetSnapshot> sets,
) {
  final prescriptions = <CapturedPrescriptionContent>[];
  for (final set in sets) {
    final projection = set.projection;
    if (prescriptions.isNotEmpty &&
        prescriptions.last.projection == projection) {
      final previous = prescriptions.removeLast();
      prescriptions.add(
        CapturedPrescriptionContent(
          values: previous.values,
          repeat: previous.repeat + 1,
          restAfter: previous.restAfter,
        ),
      );
      continue;
    }
    prescriptions.add(
      CapturedPrescriptionContent(
        values: projection.values,
        repeat: 1,
        restAfter: projection.plannedRestAfter,
      ),
    );
  }
  return List<CapturedPrescriptionContent>.unmodifiable(prescriptions);
}

Object? _canonicalCaptureTokenValue(Object? value) {
  if (value == null || value is bool || value is String) {
    return value;
  }
  if (value is num) {
    final numeric = value.toDouble();
    if (!numeric.isFinite) {
      throw StateError('Validation issue limits must be finite.');
    }
    return numeric.truncateToDouble() == numeric ? numeric.toInt() : numeric;
  }
  if (value is Iterable<Object?>) {
    return value.map(_canonicalCaptureTokenValue).toList(growable: false);
  }
  if (value is Map<Object?, Object?>) {
    final entries = value.entries
        .map((entry) => (key: entry.key.toString(), value: entry.value))
        .toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    if (entries.map((entry) => entry.key).toSet().length != entries.length) {
      throw StateError('Validation warning limit map keys must be unique.');
    }
    return <String, Object?>{
      for (final entry in entries)
        entry.key: _canonicalCaptureTokenValue(entry.value),
    };
  }
  throw StateError(
    'Unsupported validation issue limit type: ${value.runtimeType}.',
  );
}

void _requireDistinctCaptureIssues(
  List<WorkoutCaptureValidationIssue> issues, {
  required String label,
}) {
  final tokens =
      issues.map((issue) => issue.fingerprintToken).toList(growable: false);
  if (tokens.toSet().length != tokens.length) {
    throw StateError(
      'Capture validation $label must have distinguishable source paths.',
    );
  }
}
