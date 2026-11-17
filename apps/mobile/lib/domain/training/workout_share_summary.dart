/// The plain-text Workout summary the Share action hands to the platform
/// share sheet: date, duration and comment, then each exercise in Workout
/// order with its numbered sets.
library;

import 'training_dimensions.dart';
import 'training_records.dart';

/// Formats [workout] as share text.
///
/// Exercises come in [workoutExercises] order, followed by any exercise that
/// has [sets] but no Workout Exercise row, in first-set order. An exercise
/// missing from [exercisesById] prints as "Unknown exercise". Each set shows
/// its values as entered, never converted.
String workoutShareSummary({
  required WorkoutSessionRecord workout,
  required List<WorkoutExerciseRecord> workoutExercises,
  required List<LoggedSetRecord> sets,
  required Map<String, ExerciseRecord> exercisesById,
}) {
  final buffer = StringBuffer()
    ..writeln('Workout on ${workout.localDate.storageValue}');
  final duration = _formatWorkoutDuration(
    workout.endedAt?.difference(workout.startedAt),
  );
  if (duration != null) {
    buffer.writeln('Duration: $duration');
  }
  final comment = _trimmedOrNull(workout.comment);
  if (comment != null) {
    buffer.writeln('Comment: $comment');
  }

  final exerciseIds = <String>[
    for (final workoutExercise in workoutExercises) workoutExercise.exerciseId,
  ];
  final knownIds = exerciseIds.toSet();
  for (final set in sets) {
    if (knownIds.add(set.exerciseId)) {
      exerciseIds.add(set.exerciseId);
    }
  }

  if (exerciseIds.isEmpty) {
    buffer
      ..writeln()
      ..writeln('No exercises logged.');
    return buffer.toString().trimRight();
  }

  for (final exerciseId in exerciseIds) {
    final exercise = exercisesById[exerciseId];
    final exerciseSets = sets
        .where((set) => set.exerciseId == exerciseId)
        .toList(growable: false);
    buffer
      ..writeln()
      ..writeln(exercise?.name ?? 'Unknown exercise');
    if (exerciseSets.isEmpty) {
      buffer.writeln('- No sets logged');
      continue;
    }

    for (var index = 0; index < exerciseSets.length; index += 1) {
      final set = exerciseSets[index];
      final parts = <String>[
        'Set ${index + 1}: ${_formatSetSummary(set)}',
        if (set.isCompleted) 'completed',
        if (set.side != null) set.side!.name,
        if (set.rpe != null) 'RPE ${_formatDecimal(set.rpe!)}',
      ];
      buffer.writeln('- ${parts.join(' | ')}');
      final setComment = _trimmedOrNull(set.comment);
      if (setComment != null) {
        buffer.writeln('  Note: $setComment');
      }
    }
  }

  return buffer.toString().trimRight();
}

String? _formatWorkoutDuration(Duration? duration) {
  if (duration == null || duration.isNegative) {
    return null;
  }

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return '${minutes}m';
  }
  return '${seconds}s';
}

String _formatSetSummary(LoggedSetRecord set) {
  final load = set.values.load;
  final reps = set.values.reps;
  final duration = set.values.duration;
  final distance = set.values.distance;
  if (load != null && reps != null) {
    return '${load.entered} ${_unitLabel(load.unit)} x '
        '${reps.entered} ${_unitLabel(reps.unit)}';
  }
  if (distance != null && duration != null) {
    return '${distance.entered} ${_unitLabel(distance.unit)} in '
        '${duration.entered} ${_unitLabel(duration.unit)}';
  }

  final parts = set.values.values.values
      .map((value) => '${value.entered} ${_unitLabel(value.unit)}')
      .toList(growable: false);
  return parts.isEmpty ? 'Completed' : parts.join(', ');
}

String _formatDecimal(double value) {
  final rounded = value.roundToDouble();
  return rounded == value ? rounded.toInt().toString() : value.toString();
}

String _unitLabel(TrainingUnit unit) {
  return switch (unit) {
    TrainingUnit.kilogram => 'kg',
    TrainingUnit.pound => 'lb',
    TrainingUnit.repetition => 'reps',
    TrainingUnit.second => 'sec',
    TrainingUnit.kilometer => 'km',
    TrainingUnit.mile => 'mi',
  };
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
