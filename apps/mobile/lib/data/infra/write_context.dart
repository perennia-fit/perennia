/// Data-layer internal: repositories use this; `lib/features/` must not
/// import it (an architecture test enforces that).
library;

import 'id_factory.dart';

/// Who made one logical write, which Activity Log batch it belongs to, and
/// when it happened.
///
/// Every row a write touches carries [timestamp] as its `updated_at`, and
/// every Activity Log entry it appends carries [actor] and [batchId], so
/// undo can revert the whole batch together.
final class WriteContext {
  const WriteContext({
    required this.actor,
    required this.batchId,
    required this.timestamp,
  });

  final String actor;
  final String batchId;
  final DateTime timestamp;
}

/// Opens a [WriteContext] for each logical write.
final class WriteContextFactory {
  WriteContextFactory(this._ids);

  final IdFactory _ids;

  /// A context stamped with the current UTC time. The batch id is minted
  /// from that time unless [batchId] joins an existing batch.
  WriteContext create({required String actor, String? batchId}) {
    final timestamp = DateTime.now().toUtc();
    return WriteContext(
      actor: actor,
      batchId: batchId ?? _ids.create(timestamp),
      timestamp: timestamp,
    );
  }
}
