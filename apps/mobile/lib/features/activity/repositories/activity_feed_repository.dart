import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../data/repositories/training_repositories.dart';

final activityFeedRepositoryProvider = Provider<ActivityFeedRepository>((ref) {
  return ActivityFeedRepository(ref.watch(trainingRepositoriesProvider));
});

class ActivityFeedRepository {
  const ActivityFeedRepository(this._repositories);

  static const retentionWindow = Duration(days: 180);

  final TrainingRepositories _repositories;

  Future<List<ActivityFeedBatch>> listRecentBatches({DateTime? now}) async {
    final entries = await _repositories.activityLog.listEntriesSince(
      _retentionCutoff(now),
    );
    return _groupEntries(entries);
  }

  Stream<List<ActivityFeedBatch>> watchRecentBatches({DateTime? now}) {
    return _repositories.activityLog
        .watchEntriesSince(_retentionCutoff(now))
        .map(_groupEntries);
  }

  Future<ActivityLogUndoResult> undoBatch(
    String batchId, {
    String actor = 'app',
  }) {
    return _repositories.activityLog.undoBatch(batchId, actor: actor);
  }

  DateTime _retentionCutoff(DateTime? now) {
    return (now ?? DateTime.now()).toUtc().subtract(retentionWindow);
  }
}

final class ActivityFeedBatch {
  ActivityFeedBatch({
    required this.batchId,
    required this.actor,
    required this.occurredAt,
    required List<ActivityLogEntry> entries,
  }) : entries = List<ActivityLogEntry>.unmodifiable(entries);

  final String batchId;
  final String actor;
  final DateTime occurredAt;
  final List<ActivityLogEntry> entries;

  String get affectedEntitySummary {
    if (entries.isEmpty) {
      return 'Changed activity';
    }
    final mealSummary = _mealOccasionSummary();
    if (mealSummary != null) {
      return mealSummary;
    }
    if (entries.length == 1) {
      final entry = entries.first;
      return '${_verbFor(entry)} ${_entityLabel(entry.entityTable)}';
    }
    final verbs = <String>{for (final entry in entries) _verbFor(entry)};
    final entityLabels = <String>{
      for (final entry in entries) _entityLabel(entry.entityTable),
    }.toList(growable: false);
    if (entityLabels.length == 1) {
      final label = entityLabels.single;
      final pluralLabel = _pluralEntity(label);
      if (verbs.length == 1) {
        return '${verbs.single} ${entries.length} $pluralLabel';
      }
      return 'Changed ${entries.length} $pluralLabel';
    }
    if (entityLabels.length == 2) {
      return 'Changed ${entityLabels.first} and ${entityLabels.last}';
    }
    return 'Changed ${entries.length} entity types';
  }

  /// A `Meal` and its `Food Entry` rows are one eating occasion, so an
  /// agent-logged Meal batch reads as a single undoable unit rather than a
  /// scatter of per-`Food Entry` events. Returns a Meal-shaped summary when the
  /// batch is exactly one `Meal` create plus only `Food Entry` creates
  /// (NUTRITION.md §7-§8); otherwise `null` so the generic summary applies.
  String? _mealOccasionSummary() {
    ActivityLogEntry? mealEntry;
    for (final entry in entries) {
      if (entry.entityTable == AppDatabase.mealsTable) {
        if (mealEntry != null) {
          return null;
        }
        mealEntry = entry;
      } else if (entry.entityTable != AppDatabase.foodEntriesTable) {
        return null;
      }
    }
    if (mealEntry == null || !_isCreate(mealEntry)) {
      return null;
    }
    if (!entries.every(_isCreate)) {
      return null;
    }
    return 'Logged Meal';
  }

  static bool _isCreate(ActivityLogEntry entry) {
    return entry.beforeImage == null && entry.afterImage != null;
  }
}

List<ActivityFeedBatch> _groupEntries(List<ActivityLogEntry> entries) {
  final buildersByBatchId = <String, _ActivityFeedBatchBuilder>{};
  for (final entry in entries) {
    buildersByBatchId
        .putIfAbsent(
          entry.batchId,
          () => _ActivityFeedBatchBuilder(
            batchId: entry.batchId,
            actor: entry.actor,
            occurredAt: entry.occurredAt,
          ),
        )
        .add(entry);
  }

  final batches = buildersByBatchId.values
      .map((builder) => builder.build())
      .toList(growable: false)
    ..sort((left, right) {
      final occurredAtComparison = right.occurredAt.compareTo(left.occurredAt);
      if (occurredAtComparison != 0) {
        return occurredAtComparison;
      }
      return right.batchId.compareTo(left.batchId);
    });
  return List<ActivityFeedBatch>.unmodifiable(batches);
}

class _ActivityFeedBatchBuilder {
  _ActivityFeedBatchBuilder({
    required this.batchId,
    required this.actor,
    required this.occurredAt,
  });

  final String batchId;
  final String actor;
  DateTime occurredAt;
  final List<ActivityLogEntry> entries = <ActivityLogEntry>[];

  void add(ActivityLogEntry entry) {
    entries.add(entry);
    if (entry.occurredAt.isAfter(occurredAt)) {
      occurredAt = entry.occurredAt;
    }
  }

  ActivityFeedBatch build() {
    entries.sort((left, right) {
      final occurredAtComparison = left.occurredAt.compareTo(right.occurredAt);
      if (occurredAtComparison != 0) {
        return occurredAtComparison;
      }
      return left.id.compareTo(right.id);
    });
    return ActivityFeedBatch(
      batchId: batchId,
      actor: actor,
      occurredAt: occurredAt,
      entries: List<ActivityLogEntry>.unmodifiable(entries),
    );
  }
}

String _verbFor(ActivityLogEntry entry) {
  if (entry.beforeImage == null && entry.afterImage != null) {
    return entry.entityTable == AppDatabase.loggedSetsTable
        ? 'Logged'
        : 'Created';
  }
  if (entry.beforeImage != null && entry.afterImage == null) {
    return 'Deleted';
  }
  return 'Updated';
}

String _entityLabel(String entityTable) {
  return switch (entityTable) {
    AppDatabase.exerciseCategoriesTable => 'category',
    AppDatabase.exercisesTable => 'exercise',
    AppDatabase.workoutSessionsTable => 'workout',
    AppDatabase.workoutExercisesTable => 'workout exercise',
    AppDatabase.exerciseGroupsTable => 'exercise group',
    AppDatabase.exerciseGroupMembersTable => 'exercise group member',
    AppDatabase.workoutTemplatesTable => 'workout template',
    AppDatabase.templateExercisesTable => 'template exercise',
    AppDatabase.templateGroupsTable => 'template group',
    AppDatabase.templateGroupMembersTable => 'template group member',
    AppDatabase.prescriptionsTable => 'prescription',
    AppDatabase.templateLinksTable => 'template link',
    AppDatabase.planRoutinesTable => 'routine',
    AppDatabase.routineEntriesTable => 'routine entry',
    AppDatabase.loggedSetsTable => 'set',
    AppDatabase.restTimersTable => 'rest timer',
    AppDatabase.intervalTimersTable => 'interval timer',
    AppDatabase.mealTypesTable => 'meal type',
    AppDatabase.mealsTable => 'meal',
    AppDatabase.foodsTable => 'food',
    AppDatabase.foodEntriesTable => 'food entry',
    AppDatabase.nutritionGoalsTable => 'nutrition goal',
    AppDatabase.userSettingsTable => 'settings',
    AppDatabase.metricsTable => 'metric',
    AppDatabase.metricReadingsTable => 'reading',
    _ => entityTable.replaceAll('_', ' '),
  };
}

String _pluralEntity(String label) {
  if (label.endsWith('y')) {
    return '${label.substring(0, label.length - 1)}ies';
  }
  return '${label}s';
}
