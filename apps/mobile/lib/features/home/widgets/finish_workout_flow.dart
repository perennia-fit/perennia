import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../template_divergence/repositories/template_divergence_feature_repository.dart';
import '../../training/services/timer_background_scheduler.dart';
import '../controllers/home_controller.dart';
import 'finish_summary_sheet.dart';

/// Finish Workout, the one flow both the Workout screen and the Training
/// Screen run: read the Template divergence, finish through
/// [HomeController.finishWorkout], show the Finish summary, then [leave].
///
/// The Workout is already finished when the sheet opens, so the sheet is a
/// summary, not a decision: there is nothing to go back to, and closing it
/// in any way (Done, a swipe-down, Back) calls [leave], which takes the
/// lifter back to the screen that opened the Workout. Each screen knows how
/// many routes that is, so each passes its own [leave].
///
/// [leave] gets the [NavigatorState] captured up front, not one read through
/// `context` afterwards: the calling widget can be rebuilt away while the
/// sheet is open (the Workout became unavailable, say), and the screen must
/// still leave. It runs only while the caller's route is still the current
/// one.
Future<void> runFinishWorkoutFlow(
  BuildContext context,
  WidgetRef ref, {
  required String workoutId,
  required void Function(NavigatorState navigator) leave,
}) async {
  final navigator = Navigator.of(context);
  // Back can pop this route during the awaits below. context.mounted stays
  // true while the route animates out, so only the route can say the lifter
  // has left: the Workout still finishes, but a sheet would open over the
  // opener, and closing it would pop the opener too.
  final route = ModalRoute.of(context);
  final controller = ref.read(homeControllerProvider.notifier);
  final scheduler = ref.read(timerBackgroundSchedulerProvider);
  // Read (not watch): only touched when Finish is actually tapped, so
  // widget tests that never tap Finish never instantiate the real
  // Drift-backed repository behind this provider.
  final divergenceRepository = ref.read(
    templateDivergenceFeatureRepositoryProvider,
  );

  // Divergence is read from the Workout's facts as they stand right now;
  // finishing (setting endedAt) doesn't change them, so this can safely
  // happen before the write.
  final divergenceSummary =
      await divergenceRepository.summaryForWorkout(workoutId);

  final stoppedTimerId = await controller.finishWorkout(workoutId);
  if (stoppedTimerId != null) {
    await scheduler.cancel(stoppedTimerId);
  }
  if (!context.mounted || route?.isActive != true) {
    return;
  }
  await showFinishSummarySheet(
    context,
    workoutId: workoutId,
    divergenceSummary: divergenceSummary,
  );
  if (route?.isCurrent == true) {
    leave(navigator);
  }
}
