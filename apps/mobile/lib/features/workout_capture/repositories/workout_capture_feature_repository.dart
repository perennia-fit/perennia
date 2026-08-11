import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';

final workoutCaptureFeatureRepositoryProvider =
    Provider<WorkoutCaptureFeatureRepository>(
  (ref) => RepositoryWorkoutCaptureFeatureRepository(
    ref.watch(trainingRepositoriesProvider),
  ),
);

abstract interface class WorkoutCaptureFeatureRepository {
  Future<WorkoutCapturePreview> preview(String workoutId);

  Stream<List<WorkoutCaptureRoutineOption>> watchRoutines();

  Future<WorkoutCaptureSaveResult> save(WorkoutCaptureSaveRequest request);
}

class RepositoryWorkoutCaptureFeatureRepository
    implements WorkoutCaptureFeatureRepository {
  const RepositoryWorkoutCaptureFeatureRepository(this._repositories);

  final TrainingRepositories _repositories;

  @override
  Future<WorkoutCapturePreview> preview(String workoutId) {
    return _repositories.workoutCapture.preview(workoutId);
  }

  @override
  Stream<List<WorkoutCaptureRoutineOption>> watchRoutines() {
    return _repositories.routinePlans.watchActiveSummaries().map(
          (records) => records
              .map(
                (record) => WorkoutCaptureRoutineOption(
                  id: record.id,
                  name: record.name,
                  cadenceKind: record.cadence?.kind,
                  slotCount: record.cadence?.slotCount ?? 0,
                ),
              )
              .toList(growable: false),
        );
  }

  @override
  Future<WorkoutCaptureSaveResult> save(WorkoutCaptureSaveRequest request) {
    return _repositories.workoutCapture.save(request);
  }
}

final class WorkoutCaptureRoutineOption {
  const WorkoutCaptureRoutineOption({
    required this.id,
    required this.name,
    required this.cadenceKind,
    required this.slotCount,
  });

  final String id;
  final String name;
  final CadenceKind? cadenceKind;
  final int slotCount;

  bool get requiresSlot => cadenceKind != null;
}
