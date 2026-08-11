import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../data/repositories/training_repositories.dart';

const workoutAutoFinishIdleThreshold = Duration(hours: 1);

final workoutAutoFinishServiceProvider = Provider<WorkoutAutoFinishService>(
  (ref) {
    return WorkoutAutoFinishService(
      workoutSessions: ref.watch(trainingRepositoriesProvider).workoutSessions,
      interactionStore: FileWorkoutInteractionStore.openDefault(),
    );
  },
);

abstract interface class WorkoutInteractionStore {
  Future<DateTime?> loadLastInteractionAt();

  Future<void> saveLastInteractionAt(DateTime interactedAt);
}

class FileWorkoutInteractionStore implements WorkoutInteractionStore {
  const FileWorkoutInteractionStore({
    required Future<File> Function() file,
  }) : _file = file;

  factory FileWorkoutInteractionStore.openDefault() {
    return FileWorkoutInteractionStore(file: _defaultFile);
  }

  final Future<File> Function() _file;

  @override
  Future<DateTime?> loadLastInteractionAt() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      final value = decoded['lastInteractionAt'];
      if (value is! String) {
        return null;
      }
      return DateTime.tryParse(value)?.toUtc();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveLastInteractionAt(DateTime interactedAt) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'lastInteractionAt': interactedAt.toUtc().toIso8601String(),
      }),
    );
  }

  static Future<File> _defaultFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'workout_auto_finish.json'));
  }
}

class WorkoutAutoFinishService {
  WorkoutAutoFinishService({
    required WorkoutSessionRepository workoutSessions,
    required WorkoutInteractionStore interactionStore,
    DateTime Function()? now,
    this.idleThreshold = workoutAutoFinishIdleThreshold,
  })  : _workoutSessions = workoutSessions,
        _interactionStore = interactionStore,
        _now = now ?? DateTime.now;

  final WorkoutSessionRepository _workoutSessions;
  final WorkoutInteractionStore _interactionStore;
  final DateTime Function() _now;
  final Duration idleThreshold;

  DateTime? _lastInteractionAt;
  Future<void>? _activeOpenCheck;

  Future<List<AutoFinishedWorkoutRecord>> checkForStaleWorkoutsOnOpen() {
    final active = _activeOpenCheck;
    if (active != null) {
      return active.then((_) => const <AutoFinishedWorkoutRecord>[]);
    }

    final completer = Completer<void>();
    _activeOpenCheck = completer.future;
    return _checkForStaleWorkoutsOnOpen().whenComplete(() {
      completer.complete();
      _activeOpenCheck = null;
    });
  }

  void recordInteraction([DateTime? interactedAt]) {
    final normalized = (interactedAt ?? _now()).toUtc();
    final previous = _lastInteractionAt;
    if (previous == null || normalized.isAfter(previous)) {
      _lastInteractionAt = normalized;
    }
  }

  Future<void> persistLastInteraction() async {
    final interactedAt = _lastInteractionAt ?? _now().toUtc();
    await _interactionStore.saveLastInteractionAt(interactedAt);
  }

  Future<List<AutoFinishedWorkoutRecord>> _checkForStaleWorkoutsOnOpen() async {
    final previousInteractionAt =
        _lastInteractionAt ?? await _interactionStore.loadLastInteractionAt();
    final openedAt = _now().toUtc();
    final finished = await _workoutSessions.autoFinishStaleOpenWorkouts(
      idleThreshold: idleThreshold,
      now: openedAt,
      lastInteractionAt: previousInteractionAt,
    );
    _lastInteractionAt = openedAt;
    await _interactionStore.saveLastInteractionAt(openedAt);
    return finished;
  }
}
