/// Data-layer internal: repositories use this; `lib/features/` must not
/// import it (an architecture test enforces that).
library;

import '../local/uuid_v7.dart';

/// Mints the ids of authored rows, Activity Log entries, and write batches.
///
/// Ids are UUIDv7 seeded from the write's timestamp, so ids minted for one
/// write sort with the time it happened.
final class IdFactory {
  IdFactory(this.generator);

  final UuidV7Generator generator;

  String create(DateTime timestamp) {
    return generator.generate(timestamp: timestamp);
  }
}
