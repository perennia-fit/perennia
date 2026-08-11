import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/activity/controllers/activity_feed_controller.dart';
import 'package:perennia/features/activity/repositories/activity_feed_repository.dart';

void main() {
  group('ActivityFeedState', () {
    test('defensively copies batches', () {
      final batches = <ActivityFeedBatch>[_batch('batch-1')];

      final state = ActivityFeedState(batches: batches);
      batches.clear();

      expect(state.batches, hasLength(1));
      expect(state.batches.single.batchId, 'batch-1');
      expect(() => state.batches.clear(), throwsUnsupportedError);
    });
  });

  group('ActivityFeedBatch', () {
    test('defensively copies entries', () {
      final entries = <ActivityLogEntry>[_entry('entry-1')];

      final batch = _batch('batch-1', entries: entries);
      entries.clear();

      expect(batch.entries, hasLength(1));
      expect(batch.entries.single.id, 'entry-1');
      expect(() => batch.entries.clear(), throwsUnsupportedError);
    });
  });
}

ActivityFeedBatch _batch(
  String batchId, {
  List<ActivityLogEntry>? entries,
}) {
  return ActivityFeedBatch(
    batchId: batchId,
    actor: 'app',
    occurredAt: DateTime.utc(2026, 7, 9, 3),
    entries: entries ?? <ActivityLogEntry>[_entry('entry-$batchId')],
  );
}

ActivityLogEntry _entry(String id) {
  return ActivityLogEntry(
    id: id,
    actor: 'app',
    batchId: 'batch-1',
    entityTable: AppDatabase.loggedSetsTable,
    entityId: 'set-1',
    occurredAt: DateTime.utc(2026, 7, 9, 3),
    updatedAt: DateTime.utc(2026, 7, 9, 3),
    beforeImage: null,
    afterImage: const <String, Object?>{'id': 'set-1'},
  );
}
