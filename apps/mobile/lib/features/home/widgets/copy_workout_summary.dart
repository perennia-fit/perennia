import 'package:flutter/services.dart';

import '../controllers/home_controller.dart';

/// Puts the Workout's shareable summary on the clipboard. It shows nothing:
/// each caller shows its own feedback.
Future<void> copyWorkoutSummary(
  HomeController controller,
  String workoutId,
) async {
  final summary = await controller.shareWorkout(workoutId);
  await Clipboard.setData(ClipboardData(text: summary));
}
