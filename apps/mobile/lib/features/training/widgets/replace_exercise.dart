import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../catalog/widgets/exercise_catalog_picker.dart';

/// Replaces the Workout Exercise [workoutExerciseId] with an Exercise the
/// user picks, and returns the new Workout Exercise's id; null when the
/// user cancels the picker or the Replace is refused.
///
/// The picker opens on the Workout's Focus. The Replace runs under its own
/// batch id, which the "Replaced" confirmation's **Undo** hands to
/// `undoBatch`; [onUndone] runs once that Undo has reverted it. A pick
/// already active in the Workout (the exercise itself included) shows
/// "Already in this workout" and writes nothing.
///
/// [snackBarMargin] floats the confirmation above a screen's pinned
/// buttons, as the Training Screen's own confirmations do.
Future<String?> replaceExercise(
  BuildContext context,
  WidgetRef ref,
  String workoutExerciseId, {
  VoidCallback? onUndone,
  EdgeInsetsGeometry? snackBarMargin,
}) async {
  final repositories = ref.read(trainingRepositoriesProvider);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;

  final workoutExercise =
      await repositories.workoutExercises.getById(workoutExerciseId);
  if (workoutExercise == null || !context.mounted) {
    return null;
  }
  final workout =
      await repositories.workoutSessions.getById(workoutExercise.workoutId);
  if (!context.mounted) {
    return null;
  }

  final picked = await _pickExercise(context, initialFocusId: workout?.focusId);
  if (picked == null) {
    return null;
  }

  final batchId = repositories.uuidGenerator.generate();
  final String newWorkoutExerciseId;
  try {
    newWorkoutExerciseId = await repositories.workoutExercises.replace(
      workoutExerciseId,
      picked.id,
      batchId: batchId,
    );
  } on AlreadyInWorkoutException {
    _showSnackBar(
      messenger,
      l10n.replaceExerciseAlreadyInWorkout,
      margin: snackBarMargin,
    );
    return null;
  } on StateError {
    // The exercise was removed (or its Exercise deleted) since the screen
    // read it; nothing was written.
    _showSnackBar(
      messenger,
      l10n.replaceExerciseNotReplaced,
      margin: snackBarMargin,
    );
    return null;
  }

  _showSnackBar(
    messenger,
    l10n.replaceExerciseReplaced,
    margin: snackBarMargin,
    undoLabel: l10n.trainingUndo,
    onUndo: () => unawaited(
      _undoReplace(
        repositories,
        messenger,
        l10n,
        batchId: batchId,
        margin: snackBarMargin,
        onUndone: onUndone,
      ),
    ),
  );
  return newWorkoutExerciseId;
}

/// Opens the catalogue picker and returns the first Exercise tapped. Later
/// taps, while the sheet closes, are ignored, so a double tap replaces once.
Future<ExerciseRecord?> _pickExercise(
  BuildContext context, {
  required String? initialFocusId,
}) {
  var chosen = false;
  return showModalBottomSheet<ExerciseRecord>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.85,
            child: ExerciseCatalogPicker(
              initialFocusId: initialFocusId,
              onExerciseSelected: (exercise) {
                if (chosen) {
                  return;
                }
                chosen = true;
                Navigator.of(sheetContext).pop(exercise);
              },
            ),
          ),
        ),
      );
    },
  );
}

/// Reverses the Replace's batch; on a conflict (another write touched its
/// rows since) nothing is reverted and "Couldn't undo: changed since"
/// shows.
Future<void> _undoReplace(
  TrainingRepositories repositories,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n, {
  required String batchId,
  required EdgeInsetsGeometry? margin,
  required VoidCallback? onUndone,
}) async {
  final ActivityLogUndoResult result;
  try {
    result = await repositories.activityLog.undoBatch(batchId);
  } on StateError {
    _showSnackBar(messenger, l10n.trainingUndoConflict, margin: margin);
    return;
  }
  if (result.hasConflicts) {
    _showSnackBar(messenger, l10n.trainingUndoConflict, margin: margin);
    return;
  }
  onUndone?.call();
}

void _showSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  required EdgeInsetsGeometry? margin,
  String? undoLabel,
  VoidCallback? onUndo,
}) {
  messenger
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: onUndo == null ? 2 : 4),
        behavior: margin == null ? null : SnackBarBehavior.floating,
        margin: margin,
        action: onUndo == null || undoLabel == null
            ? null
            : SnackBarAction(label: undoLabel, onPressed: onUndo),
      ),
    );
}
