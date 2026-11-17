import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/activity/undo_conflict_message.dart';
import 'package:perennia/l10n/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  ActivityLogUndoConflict conflict(
    ActivityLogUndoConflictReason reason, {
    String entityTable = AppDatabase.foodEntriesTable,
    String entityId = 'entry-1',
  }) {
    return ActivityLogUndoConflict(
      entryId: 'log-$entityId',
      entityTable: entityTable,
      entityId: entityId,
      reason: reason,
      expectedImage: null,
      currentImage: null,
    );
  }

  ActivityLogUndoResult refused(List<ActivityLogUndoConflict> conflicts) {
    return ActivityLogUndoResult(
      originalBatchId: 'batch-1',
      undoBatchId: null,
      appliedEntries: const <ActivityLogEntry>[],
      conflicts: conflicts,
    );
  }

  test('a dependent conflict gets the meal message (meal-logging.md §7)', () {
    final result = refused(<ActivityLogUndoConflict>[
      conflict(
        ActivityLogUndoConflictReason.dependent,
        entityTable: AppDatabase.mealsTable,
        entityId: 'meal-1',
      ),
    ]);

    expect(
      undoConflictMessage(l10n, result),
      "Can't undo: foods were added to this meal afterwards.",
    );
  });

  test(
      'a duplicate Purpose name gets its own message '
      '(compound-purposes.md, D8)', () {
    final result = refused(<ActivityLogUndoConflict>[
      conflict(
        ActivityLogUndoConflictReason.duplicatePurposeName,
        entityTable: AppDatabase.purposesTable,
        entityId: 'purpose-1',
      ),
    ]);

    expect(
      undoConflictMessage(l10n, result),
      "Can't undo: another purpose now has this name.",
    );
  });

  test('other conflicts name the first changed row', () {
    final result = refused(<ActivityLogUndoConflict>[
      conflict(ActivityLogUndoConflictReason.stale),
      conflict(ActivityLogUndoConflictReason.missing, entityId: 'entry-2'),
    ]);

    expect(
      undoConflictMessage(l10n, result),
      l10n.activityUndoConflict(2, AppDatabase.foodEntriesTable, 'entry-1'),
    );
  });

  test('no conflicts falls back to the generic message', () {
    expect(
      undoConflictMessage(l10n, refused(const <ActivityLogUndoConflict>[])),
      l10n.activityUndoGenericConflict,
    );
  });
}
