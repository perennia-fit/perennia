import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/nutrition/nutrition.dart';
import '../../../domain/training/training_day.dart';
import '../../nutrition/controllers/nutrition_day_controller.dart';
import '../repositories/home_repository.dart';

enum HomeDomain {
  training,
  nutrition,
}

enum HomeDestination {
  today,
  progress,
  library,
}

final selectedHomeDestinationProvider =
    NotifierProvider<SelectedHomeDestinationController, HomeDestination>(
  SelectedHomeDestinationController.new,
);

class SelectedHomeDestinationController extends Notifier<HomeDestination> {
  @override
  HomeDestination build() => HomeDestination.today;

  void select(HomeDestination destination) {
    state = destination;
  }
}

final selectedHomeDomainProvider =
    NotifierProvider<SelectedHomeDomainController, HomeDomain>(
  SelectedHomeDomainController.new,
);

class SelectedHomeDomainController extends Notifier<HomeDomain> {
  @override
  HomeDomain build() => HomeDomain.training;

  void select(HomeDomain domain) {
    state = domain;
  }
}

final selectedTrainingDayProvider =
    NotifierProvider<SelectedTrainingDayController, TrainingDayDate>(
  SelectedTrainingDayController.new,
);

class SelectedTrainingDayController extends Notifier<TrainingDayDate> {
  @override
  TrainingDayDate build() => TrainingDayDate.fromDateTime(DateTime.now());

  void select(TrainingDayDate localDate) {
    state = localDate;
  }

  void addDays(int days) {
    state = state.addDays(days);
  }
}

final homeNutritionDayProvider = StreamProvider<NutritionDayRecord>((ref) {
  final repository = ref.watch(nutritionRepositoryProvider);
  final selectedDate = ref.watch(selectedTrainingDayProvider);
  return repository.watchNutritionDay(
    nutritionDayDateFromTrainingDay(selectedDate),
  );
});

NutritionDayDate nutritionDayDateFromTrainingDay(
  TrainingDayDate localDate,
) {
  return NutritionDayDate(
    year: localDate.year,
    month: localDate.month,
    day: localDate.day,
  );
}

final homeControllerProvider =
    StreamNotifierProvider<HomeController, HomeState>(
  HomeController.new,
);

final workoutSummaryProvider =
    StreamProvider.family<HomeWorkoutSummary?, String>((ref, workoutId) {
  return ref.watch(homeRepositoryProvider).watchWorkout(workoutId);
});

class HomeController extends StreamNotifier<HomeState> {
  @override
  Stream<HomeState> build() {
    final repository = ref.watch(homeRepositoryProvider);
    final selectedDate = ref.watch(selectedTrainingDayProvider);
    return repository.watchTrainingDay(selectedDate).map(
          (summary) => HomeState(summary: summary),
        );
  }

  void selectTrainingDay(TrainingDayDate localDate) {
    ref.read(selectedTrainingDayProvider.notifier).select(localDate);
  }

  void showPreviousDay() {
    ref.read(selectedTrainingDayProvider.notifier).addDays(-1);
  }

  void showNextDay() {
    ref.read(selectedTrainingDayProvider.notifier).addDays(1);
  }

  Future<String> startNewWorkout() {
    return ref
        .read(homeRepositoryProvider)
        .startNewWorkout(ref.read(selectedTrainingDayProvider));
  }

  Future<String> addExerciseToWorkout({
    required String workoutId,
    required String exerciseId,
  }) {
    return ref.read(homeRepositoryProvider).addExerciseToWorkout(
          workoutId: workoutId,
          exerciseId: exerciseId,
        );
  }

  Future<void> removeExerciseFromWorkout({
    required String workoutExerciseId,
  }) {
    return ref.read(homeRepositoryProvider).removeExerciseFromWorkout(
          workoutExerciseId: workoutExerciseId,
        );
  }

  Future<void> reorderWorkoutExercises({
    required String workoutId,
    required List<String> orderedWorkoutExerciseIds,
  }) {
    return ref.read(homeRepositoryProvider).reorderWorkoutExercises(
          workoutId: workoutId,
          orderedWorkoutExerciseIds: orderedWorkoutExerciseIds,
        );
  }

  Future<void> linkWorkoutExercisesAsSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  }) {
    return ref.read(homeRepositoryProvider).linkWorkoutExercisesAsSuperset(
          workoutId: workoutId,
          firstWorkoutExerciseId: firstWorkoutExerciseId,
          secondWorkoutExerciseId: secondWorkoutExerciseId,
        );
  }

  Future<void> unlinkWorkoutExercisesFromSuperset({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  }) {
    return ref.read(homeRepositoryProvider).unlinkWorkoutExercisesFromSuperset(
          workoutId: workoutId,
          firstWorkoutExerciseId: firstWorkoutExerciseId,
          secondWorkoutExerciseId: secondWorkoutExerciseId,
        );
  }

  Future<void> updateWorkoutComment({
    required String workoutId,
    String? comment,
  }) {
    return ref.read(homeRepositoryProvider).updateWorkoutComment(
          workoutId: workoutId,
          comment: comment,
        );
  }

  Future<void> updateWorkoutStartedAt({
    required String workoutId,
    required DateTime startedAt,
    required TrainingDayDate localDate,
  }) {
    return ref.read(homeRepositoryProvider).updateWorkoutStartedAt(
          workoutId: workoutId,
          startedAt: startedAt,
          localDate: localDate,
        );
  }

  Future<void> updateWorkoutEndedAt({
    required String workoutId,
    required DateTime endedAt,
  }) {
    return ref.read(homeRepositoryProvider).updateWorkoutEndedAt(
          workoutId: workoutId,
          endedAt: endedAt,
        );
  }

  Future<void> finishWorkout(String workoutId) {
    return ref.read(homeRepositoryProvider).finishWorkout(workoutId);
  }

  Future<void> resumeWorkout(String workoutId) {
    return ref.read(homeRepositoryProvider).resumeWorkout(workoutId);
  }

  Future<void> deleteWorkout(String workoutId) {
    return ref.read(homeRepositoryProvider).deleteWorkout(workoutId);
  }

  Future<String> copyWorkout(String workoutId) {
    return ref.read(homeRepositoryProvider).copyWorkout(
          workoutId: workoutId,
          localDate: ref.read(selectedTrainingDayProvider),
        );
  }

  Future<void> moveWorkout({
    required String workoutId,
    required TrainingDayDate localDate,
  }) {
    return ref.read(homeRepositoryProvider).moveWorkout(
          workoutId: workoutId,
          localDate: localDate,
        );
  }

  Future<String> shareWorkout(String workoutId) {
    return ref.read(homeRepositoryProvider).shareWorkout(workoutId);
  }

  Future<void> logDefaultWeightRepsSet() {
    return ref.read(homeRepositoryProvider).logDefaultWeightRepsSet();
  }
}

class HomeState {
  const HomeState({
    required this.summary,
  });

  final HomeSummary summary;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HomeState &&
            runtimeType == other.runtimeType &&
            summary == other.summary;
  }

  @override
  int get hashCode => summary.hashCode;
}
