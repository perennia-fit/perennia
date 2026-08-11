import '../../training/widgets/training_screen.dart';

class ExercisePage extends TrainingScreen {
  const ExercisePage({
    super.key,
    required super.workoutExerciseId,
    super.initialWorkoutExercise,
    super.initialExercise,
    super.initialPriorSet,
    super.setsStream,
    super.recordSetIdsStream,
    super.enableRestTimerTicker,
  });
}
