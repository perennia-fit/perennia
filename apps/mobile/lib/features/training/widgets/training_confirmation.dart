import 'package:flutter/widgets.dart';

/// One message for the Training Screen's status row: its text and, for an
/// action that can be reverted, an **Undo**.
class TrainingConfirmation {
  const TrainingConfirmation({
    required this.message,
    this.textKey,
    this.undoLabel,
    this.onUndo,
    this.replacesCurrent = false,
  });

  final String message;

  /// Sits on the message's `Text`.
  final Key? textKey;
  final String? undoLabel;
  final VoidCallback? onUndo;

  /// Keeps the current sequence number, so Log set's Undo version updates
  /// its first message in place instead of crossfading to a new one.
  final bool replacesCurrent;

  /// How long it shows: time to reach **Undo**, or a short notice without it.
  Duration get duration => Duration(seconds: onUndo == null ? 2 : 4);
}

/// Shows a [TrainingConfirmation], on the Training Screen's status row or,
/// from the Workout screen, as a SnackBar.
typedef ShowTrainingConfirmation = void Function(TrainingConfirmation);
