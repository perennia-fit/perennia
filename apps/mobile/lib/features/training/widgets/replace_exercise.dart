import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../catalog/widgets/exercise_catalog_picker.dart';

/// A Replace that its **Undo** reverted: [newWorkoutExerciseId] is
/// soft-deleted and [oldWorkoutExerciseId] is back in its place.
typedef ReplaceUndone = ({
  String oldWorkoutExerciseId,
  String newWorkoutExerciseId,
});

/// Every undone Replace, wherever it started. A Training Screen open on the
/// new Workout Exercise switches back on it, including one opened from a
/// Workout screen card while that screen's "Replaced" confirmation, which
/// follows the user onto the pushed route, was still showing.
final replaceUndoneProvider = Provider<StreamController<ReplaceUndone>>((ref) {
  final controller = StreamController<ReplaceUndone>.broadcast();
  ref.onDispose(controller.close);
  return controller;
});

/// Replaces the Workout Exercise [workoutExerciseId] with an Exercise the
/// user picks, and returns the new Workout Exercise's id; null when the
/// user cancels the picker or the Replace is refused.
///
/// The picker opens on the Workout's Focus. The Replace runs under its own
/// batch id, which the "Replaced" confirmation's **Undo** hands to
/// `undoBatch`; once that Undo has reverted it, [replaceUndoneProvider]
/// reports it. A pick already active in the Workout (the exercise itself
/// included) shows "Already in this workout" and writes nothing.
///
/// [snackBarMargin] floats the confirmation above a screen's pinned
/// buttons, as the Training Screen's own confirmations do. The confirmation
/// goes when the calling screen closes (see [showTrainingSnackBar]).
Future<String?> replaceExercise(
  BuildContext context,
  WidgetRef ref,
  String workoutExerciseId, {
  EdgeInsetsGeometry? snackBarMargin,
}) async {
  final repositories = ref.read(trainingRepositoriesProvider);
  // Read now: the calling screen may be gone by the time Undo is tapped.
  final undoneEvents = ref.read(replaceUndoneProvider);
  final messenger = ScaffoldMessenger.of(context);
  final route = ModalRoute.of(context);
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
    showTrainingSnackBar(
      messenger,
      l10n.replaceExerciseAlreadyInWorkout,
      margin: snackBarMargin,
      route: route,
    );
    return null;
  } on StateError {
    // The exercise was removed, or the picked Exercise was archived, since
    // the screen read it; nothing was written.
    showTrainingSnackBar(
      messenger,
      l10n.replaceExerciseNotReplaced,
      margin: snackBarMargin,
      route: route,
    );
    return null;
  }

  showTrainingSnackBar(
    messenger,
    l10n.replaceExerciseReplaced,
    margin: snackBarMargin,
    route: route,
    undoLabel: l10n.trainingUndo,
    onUndo: () => unawaited(
      undoTrainingBatch(
        repositories,
        messenger,
        l10n,
        batchId,
        margin: snackBarMargin,
        route: route,
      ).then((undone) {
        if (undone && !undoneEvents.isClosed) {
          undoneEvents.add(
            (
              oldWorkoutExerciseId: workoutExerciseId,
              newWorkoutExerciseId: newWorkoutExerciseId,
            ),
          );
        }
      }),
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

/// Reverses one action's batch and returns whether it did; on a conflict
/// (another write touched its rows since) nothing is reverted and "Couldn't
/// undo: changed since" shows. The Training Screen's Undo and Replace's
/// share it, so every Undo on the gym-floor path behaves alike.
Future<bool> undoTrainingBatch(
  TrainingRepositories repositories,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String batchId, {
  EdgeInsetsGeometry? margin,
  ModalRoute<Object?>? route,
}) async {
  final ActivityLogUndoResult result;
  try {
    result = await repositories.activityLog.undoBatch(batchId);
  } on StateError {
    showTrainingSnackBar(
      messenger,
      l10n.trainingUndoConflict,
      margin: margin,
      route: route,
    );
    return false;
  }
  if (result.hasConflicts) {
    showTrainingSnackBar(
      messenger,
      l10n.trainingUndoConflict,
      margin: margin,
      route: route,
    );
    return false;
  }
  return true;
}

/// Replaces the current confirmation with [message]: 4 s with **Undo**
/// ([undoLabel], [onUndo]), else 2 s. With [margin] it floats there, as the
/// Training Screen's do above its pinned buttons.
///
/// `persist: false` is what makes those durations hold: a SnackBar with an
/// action otherwise stays until it is dismissed, so "Set 3 logged · Undo"
/// sat over the form and followed the user to Today.
///
/// With [route], the screen that shows it, the confirmation also goes when
/// that screen closes, so its Undo never outlives it. Covering the screen
/// with another route keeps it (a Workout screen's "Replaced" follows the
/// user onto the Training Screen it pushes).
void showTrainingSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  Key? key,
  EdgeInsetsGeometry? margin,
  ModalRoute<Object?>? route,
  String? undoLabel,
  VoidCallback? onUndo,
}) {
  var hidden = false;
  messenger
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: key,
        content: route == null
            ? Text(message)
            : _ClosesWithRoute(
                route: route,
                // Once: during a route transition each Scaffold builds the
                // SnackBar, and a second hide could take the next one.
                onClosed: () {
                  if (!hidden) {
                    hidden = true;
                    messenger.hideCurrentSnackBar();
                  }
                },
                child: Text(message),
              ),
        duration: Duration(seconds: onUndo == null ? 2 : 4),
        persist: false,
        margin: margin,
        action: onUndo == null || undoLabel == null
            ? null
            : SnackBarAction(label: undoLabel, onPressed: onUndo),
      ),
    );
}

/// A SnackBar's content that calls [onClosed] when [route] is popped. Only
/// the showing SnackBar is built, so a mounted one is the current one, and
/// hiding the current SnackBar hides this one.
class _ClosesWithRoute extends StatefulWidget {
  const _ClosesWithRoute({
    required this.route,
    required this.onClosed,
    required this.child,
  });

  final ModalRoute<Object?> route;
  final VoidCallback onClosed;
  final Widget child;

  @override
  State<_ClosesWithRoute> createState() => _ClosesWithRouteState();
}

class _ClosesWithRouteState extends State<_ClosesWithRoute> {
  @override
  void initState() {
    super.initState();
    unawaited(
      widget.route.popped.whenComplete(() {
        if (mounted) {
          widget.onClosed();
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
