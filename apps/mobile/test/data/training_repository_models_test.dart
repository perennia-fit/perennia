import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

void main() {
  test('list-backed training repository models are immutable snapshots', () {
    final updatedAt = DateTime.utc(2026, 7, 9, 17);

    final equipment = <ExerciseEquipment>[ExerciseEquipment.barbell];
    final exerciseDraft = ExerciseDraft(
      name: 'Squat',
      type: ExerciseType.empty,
      equipment: equipment,
    );
    final exerciseRecord = ExerciseRecord(
      id: 'exercise-1',
      origin: ExerciseLibraryOrigin.user,
      name: 'Squat',
      type: ExerciseType.empty,
      defaultLoadUnit: TrainingUnit.kilogram,
      loadMode: ExerciseLoadMode.added,
      recordProfile: RecordProfile.completionStreak,
      categoryId: null,
      equipment: equipment,
      notes: null,
      isFavorite: false,
      updatedAt: updatedAt,
    );
    equipment.add(ExerciseEquipment.dumbbell);

    expect(exerciseDraft.equipment, <ExerciseEquipment>[
      ExerciseEquipment.barbell,
    ]);
    expect(exerciseRecord.equipment, <ExerciseEquipment>[
      ExerciseEquipment.barbell,
    ]);
    expect(
      () => exerciseDraft.equipment.add(ExerciseEquipment.kettlebell),
      throwsUnsupportedError,
    );
    expect(
      () => exerciseRecord.equipment.add(ExerciseEquipment.kettlebell),
      throwsUnsupportedError,
    );

    final workoutExerciseIds = <String>['workout-exercise-1'];
    final exerciseGroupDraft = ExerciseGroupDraft(
      workoutId: 'workout-1',
      name: 'Superset',
      colorHex: '#3366ff',
      workoutExerciseIds: workoutExerciseIds,
    );
    workoutExerciseIds.add('workout-exercise-2');

    expect(exerciseGroupDraft.workoutExerciseIds, <String>[
      'workout-exercise-1',
    ]);
    expect(
      () => exerciseGroupDraft.workoutExerciseIds.add('workout-exercise-3'),
      throwsUnsupportedError,
    );

    final groupMember = ExerciseGroupMemberRecord(
      id: 'member-1',
      groupId: 'group-1',
      workoutExerciseId: 'workout-exercise-1',
      position: 0,
      updatedAt: updatedAt,
    );
    final groupMembers = <ExerciseGroupMemberRecord>[groupMember];
    final exerciseGroup = ExerciseGroupRecord(
      id: 'group-1',
      workoutId: 'workout-1',
      name: 'Superset',
      colorHex: '#3366ff',
      position: 0,
      members: groupMembers,
      updatedAt: updatedAt,
    );
    groupMembers.add(
      ExerciseGroupMemberRecord(
        id: 'member-2',
        groupId: 'group-1',
        workoutExerciseId: 'workout-exercise-2',
        position: 1,
        updatedAt: updatedAt,
      ),
    );

    expect(exerciseGroup.members, <ExerciseGroupMemberRecord>[groupMember]);
    expect(
      () => exerciseGroup.members.clear(),
      throwsUnsupportedError,
    );

    final metric = MetricRecord(
      id: 'metric-1',
      name: 'Weight',
      unit: 'kg',
      valueShape: MetricValueShape.scalar,
      group: MetricGroup.bodyComposition,
      enabled: true,
      pinned: false,
      sortOrder: 0,
      updatedAt: updatedAt,
    );
    final reading = MetricReadingRecord(
      id: 'reading-1',
      metricId: 'metric-1',
      valueJson: '{"value":82}',
      scalarValue: 82,
      scalarEntered: '82',
      provenance: MetricReadingProvenance.manual,
      source: 'manual',
      updatedAt: updatedAt,
    );
    final readings = <MetricReadingRecord>[reading];
    final series = MetricSeriesData(metric: metric, readings: readings);
    readings.clear();

    expect(series.readings, <MetricReadingRecord>[reading]);
    expect(() => series.readings.clear(), throwsUnsupportedError);

    final entry = ActivityLogEntry(
      id: 'entry-1',
      actor: 'app',
      batchId: 'batch-1',
      entityTable: AppDatabase.loggedSetsTable,
      entityId: 'set-1',
      occurredAt: updatedAt,
      updatedAt: updatedAt,
    );
    final appliedEntries = <ActivityLogEntry>[entry];
    final conflicts = <ActivityLogUndoConflict>[
      const ActivityLogUndoConflict(
        entryId: 'entry-2',
        entityTable: AppDatabase.loggedSetsTable,
        entityId: 'set-2',
        reason: ActivityLogUndoConflictReason.stale,
        expectedImage: null,
        currentImage: null,
      ),
    ];
    final undo = ActivityLogUndoResult(
      originalBatchId: 'batch-1',
      undoBatchId: null,
      appliedEntries: appliedEntries,
      conflicts: conflicts,
    );
    appliedEntries.clear();
    conflicts.clear();

    expect(undo.appliedEntries, <ActivityLogEntry>[entry]);
    expect(undo.conflicts, hasLength(1));
    expect(() => undo.appliedEntries.clear(), throwsUnsupportedError);
    expect(() => undo.conflicts.clear(), throwsUnsupportedError);

    final workoutExerciseResultIds = <String>['workout-exercise-1'];
    final loggedSetResultIds = <String>['set-1'];
    final planResult = WorkoutPlanLogResult(
      batchId: 'batch-1',
      workoutId: 'workout-1',
      workoutExerciseIds: workoutExerciseResultIds,
      loggedSetIds: loggedSetResultIds,
    );
    workoutExerciseResultIds.clear();
    loggedSetResultIds.clear();

    expect(planResult.workoutExerciseIds, <String>['workout-exercise-1']);
    expect(planResult.loggedSetIds, <String>['set-1']);
    expect(
      () => planResult.workoutExerciseIds.clear(),
      throwsUnsupportedError,
    );
    expect(() => planResult.loggedSetIds.clear(), throwsUnsupportedError);

    final doseWarnings = <String>['dose.amount.high'];
    final doseResult = LogDoseResult(
      batchId: 'batch-1',
      doseId: 'dose-1',
      warnings: doseWarnings,
    );
    doseWarnings.clear();

    expect(doseResult.warnings, <String>['dose.amount.high']);
    expect(() => doseResult.warnings.clear(), throwsUnsupportedError);
  });
}
