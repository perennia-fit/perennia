/// Data-layer internal: repositories use this; `lib/features/` must not
/// import it (an architecture test enforces that).
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import 'id_factory.dart';
import 'write_context.dart';

/// Appends entries to the Activity Log, the record of every authored write.
///
/// Sync push and undo both read only the Activity Log, so a write that skips
/// [append] neither syncs nor can be undone.
final class ActivityLogWriter {
  ActivityLogWriter(this._database, this._ids);

  final AppDatabase _database;
  final IdFactory _ids;

  /// Records one row's change from [beforeImage] to [afterImage] (null for a
  /// create or a hard delete) under [context]'s actor and batch.
  ///
  /// [id] and [occurredAt] default to a fresh id and the context timestamp.
  /// An entry whose id already exists is skipped, so replaying the same
  /// entry is harmless.
  Future<void> append(
    WriteContext context, {
    required String entityTable,
    required String entityId,
    required Map<String, Object?>? beforeImage,
    required Map<String, Object?>? afterImage,
    String? id,
    DateTime? occurredAt,
    DateTime? syncAcknowledgedAt,
  }) {
    final activityLogId = id ?? _ids.create(context.timestamp);
    final activityOccurredAt = occurredAt ?? context.timestamp;
    return _database.into(_database.activityLog).insert(
          ActivityLogCompanion.insert(
            id: activityLogId,
            actor: context.actor,
            batchId: context.batchId,
            entityTable: entityTable,
            entityId: entityId,
            beforeImage: Value<String?>(
              beforeImage == null ? null : jsonEncode(beforeImage),
            ),
            afterImage: Value<String?>(
              afterImage == null ? null : jsonEncode(afterImage),
            ),
            occurredAt: activityOccurredAt,
            syncAcknowledgedAt: Value<DateTime?>(syncAcknowledgedAt),
            updatedAt: context.timestamp,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}
