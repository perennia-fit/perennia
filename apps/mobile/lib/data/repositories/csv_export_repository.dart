part of 'training_repositories.dart';

class CsvExportRepository {
  CsvExportRepository._(this._repositories);

  static const supportsImport = false;
  static const workoutHistoryColumns = <String>[
    'set_id',
    'workout_id',
    'workout_started_at',
    'local_date',
    'timezone',
    'exercise_id',
    'exercise_name',
    'set_position',
    'is_completed',
    'load_entered',
    'load_unit',
    'load_value',
    'reps_entered',
    'reps_unit',
    'reps_value',
    'duration_entered',
    'duration_unit',
    'duration_value',
    'distance_entered',
    'distance_unit',
    'distance_value',
    'planned_rest_seconds',
    'comment',
    'side',
    'rpe',
    'updated_at',
  ];

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<String> exportWorkoutHistoryCsv() async {
    final rows = await _workoutHistoryRows();
    final buffer = StringBuffer();
    _writeCsvRow(buffer, workoutHistoryColumns);
    for (final row in rows) {
      _writeCsvRow(buffer, row.values);
    }
    return buffer.toString();
  }

  Future<File> exportWorkoutHistoryCsvToFile(File destination) async {
    final csv = await exportWorkoutHistoryCsv();
    await destination.parent.create(recursive: true);
    return destination.writeAsString(csv, flush: true);
  }

  Future<List<_CsvWorkoutHistoryRow>> _workoutHistoryRows() async {
    final sets = await (_database.select(_database.loggedSets)
          ..where((row) => row.deletedAt.isNull()))
        .get();
    if (sets.isEmpty) {
      return const <_CsvWorkoutHistoryRow>[];
    }

    final workoutIds = sets.map((row) => row.workoutId).toSet();
    final workouts = await (_database.select(_database.workoutSessions)
          ..where((row) => row.id.isIn(workoutIds)))
        .get();
    final workoutById = <String, WorkoutSessionRow>{
      for (final row in workouts) row.id: row,
    };

    final exerciseIds = sets.map((row) => row.exerciseId).toSet();
    final exercises = await (_database.select(_database.exercises)
          ..where((row) => row.id.isIn(exerciseIds)))
        .get();
    final exerciseById = <String, ExerciseRow>{
      for (final row in exercises) row.id: row,
    };

    final rows = <_CsvWorkoutHistoryRow>[];
    for (final set in sets) {
      final workout = workoutById[set.workoutId];
      final exercise = exerciseById[set.exerciseId];
      if (workout == null || workout.deletedAt != null || exercise == null) {
        continue;
      }
      rows.add(
        _CsvWorkoutHistoryRow(
          set: set,
          workout: workout,
          exercise: exercise,
        ),
      );
    }

    rows.sort(_compareWorkoutHistoryRows);
    return List<_CsvWorkoutHistoryRow>.unmodifiable(rows);
  }
}

class _CsvWorkoutHistoryRow {
  const _CsvWorkoutHistoryRow({
    required this.set,
    required this.workout,
    required this.exercise,
  });

  final LoggedSetRow set;
  final WorkoutSessionRow workout;
  final ExerciseRow exercise;

  List<String?> get values => <String?>[
        set.id,
        workout.id,
        _formatCsvDateTime(workout.startedAt),
        workout.localDate,
        workout.timezone,
        exercise.id,
        exercise.name,
        set.position.toString(),
        set.isCompleted.toString(),
        set.loadEntered,
        set.loadUnit,
        _formatCsvNumber(set.loadValue),
        set.repsEntered,
        set.repsUnit,
        _formatCsvNumber(set.repsValue),
        set.durationEntered,
        set.durationUnit,
        _formatCsvNumber(set.durationValue),
        set.distanceEntered,
        set.distanceUnit,
        _formatCsvNumber(set.distanceValue),
        set.plannedRestAfter?.toString(),
        set.comment,
        set.side,
        _formatCsvNumber(set.rpe),
        _formatCsvDateTime(set.updatedAt),
      ];
}

int _compareWorkoutHistoryRows(
  _CsvWorkoutHistoryRow left,
  _CsvWorkoutHistoryRow right,
) {
  final startedAt = left.workout.startedAt.compareTo(right.workout.startedAt);
  if (startedAt != 0) {
    return startedAt;
  }

  final workoutId = left.workout.id.compareTo(right.workout.id);
  if (workoutId != 0) {
    return workoutId;
  }

  final position = left.set.position.compareTo(right.set.position);
  if (position != 0) {
    return position;
  }

  final updatedAt = left.set.updatedAt.compareTo(right.set.updatedAt);
  if (updatedAt != 0) {
    return updatedAt;
  }

  return left.set.id.compareTo(right.set.id);
}

void _writeCsvRow(StringBuffer buffer, Iterable<String?> values) {
  var isFirst = true;
  for (final value in values) {
    if (!isFirst) {
      buffer.write(',');
    }
    buffer.write(_escapeCsvField(value));
    isFirst = false;
  }
  buffer.write('\r\n');
}

String _escapeCsvField(String? value) {
  final field = value ?? '';
  if (!field.contains(',') &&
      !field.contains('"') &&
      !field.contains('\r') &&
      !field.contains('\n')) {
    return field;
  }
  return '"${field.replaceAll('"', '""')}"';
}

String _formatCsvDateTime(DateTime value) {
  return value.toUtc().toIso8601String();
}

String? _formatCsvNumber(num? value) {
  return value?.toString();
}
