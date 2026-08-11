import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/workout_capture.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';
import 'package:perennia/features/home/widgets/workout_screen.dart';
import 'package:perennia/features/workout_capture/repositories/workout_capture_feature_repository.dart';
import 'package:perennia/features/workout_capture/widgets/workout_capture_sheet.dart';
import 'package:perennia/l10n/app_localizations.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  for (final isFinished in <bool>[false, true]) {
    testWidgets(
        'Workout overflow exposes capture for ${isFinished ? 'finished' : 'open'} workouts',
        (tester) async {
      const workoutId = 'workout-1';
      final workout = HomeWorkoutSummary(
        id: workoutId,
        startedAt: DateTime.utc(2026, 7, 11, 8),
        endedAt: isFinished ? DateTime.utc(2026, 7, 11, 9) : null,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeRepositoryProvider.overrideWithValue(
              _WorkoutHomeRepository(workout),
            ),
            workoutCaptureFeatureRepositoryProvider.overrideWithValue(
              const _MenuCaptureRepository(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const WorkoutScreen(workoutId: workoutId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(WorkoutScreen.optionsButtonKey(workoutId)));
      await tester.pumpAndSettle();
      final captureAction =
          find.byKey(WorkoutScreen.captureTemplateButtonKey(workoutId));
      expect(captureAction, findsOneWidget);
      await tester.tap(captureAction);
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutCaptureSheet), findsOneWidget);
    });
  }
}

class _WorkoutHomeRepository extends StubHomeRepository {
  _WorkoutHomeRepository(this.workout);

  final HomeWorkoutSummary workout;

  @override
  Stream<HomeWorkoutSummary?> watchWorkout(String workoutId) {
    return Stream<HomeWorkoutSummary?>.value(workout);
  }
}

class _MenuCaptureRepository implements WorkoutCaptureFeatureRepository {
  const _MenuCaptureRepository();

  @override
  Future<WorkoutCapturePreview> preview(String workoutId) async {
    return WorkoutCapturePreview(
      workoutId: workoutId,
      content: CapturedWorkoutTemplateContent(exercises: [], groups: []),
      suggestedName: 'Captured workout',
      exerciseCount: 0,
      setCount: 0,
      groupCount: 0,
      validation: WorkoutCaptureValidationResult(),
    );
  }

  @override
  Future<WorkoutCaptureSaveResult> save(
    WorkoutCaptureSaveRequest request,
  ) async {
    return const WorkoutCaptureSaveResult(
      workoutTemplateId: 'template-1',
      routineEntryId: null,
      activityBatchId: 'batch-1',
    );
  }

  @override
  Stream<List<WorkoutCaptureRoutineOption>> watchRoutines() {
    return Stream<List<WorkoutCaptureRoutineOption>>.value(
      const <WorkoutCaptureRoutineOption>[],
    );
  }
}
