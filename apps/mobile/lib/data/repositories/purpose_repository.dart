part of 'training_repositories.dart';

/// Purposes: labels for why the user takes a Compound
/// (docs/designs/compound-purposes.md, D1). Modelled on [FocusRepository].
///
/// The starter Purposes are seeded with fixed ids alongside the OTC Compounds,
/// users rename, reorder, archive, and add their own, and every change is an
/// Activity Log entry that syncs as an ordinary LWW row. Archiving never blocks
/// on use: a Compound keeps naming an archived Purpose, and no Dose ever
/// changes.
class PurposeRepository {
  PurposeRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  /// Active Purposes in the user's order, for filters and pickers.
  Stream<List<PurposeRecord>> watchActive() {
    return _activeQuery()
        .watch()
        .map((rows) => rows.map(_purposeFromRow).toList(growable: false));
  }

  Future<List<PurposeRecord>> listActive() async {
    final rows = await _activeQuery().get();
    return rows.map(_purposeFromRow).toList(growable: false);
  }

  /// Every Purpose, archived ones included, so the Compound editor can tell an
  /// archived tag it keeps attached from a live one.
  Stream<Map<String, PurposeRecord>> watchAllById() {
    return _database.select(_database.purposes).watch().map(
          (rows) => <String, PurposeRecord>{
            for (final row in rows) row.id: _purposeFromRow(row),
          },
        );
  }

  /// Creates a Purpose at the end of the user's order and returns its id.
  /// Throws [PurposeNameException] for an empty or duplicate name.
  Future<String> create(
    String name, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._writeContexts.create(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final activeRows = await _activeQuery().get();
      final stored = validatePurposeName(
        name,
        activeRows.map((row) => row.name),
      );
      final id = _repositories._ids.create(context.timestamp);
      await _database.into(_database.purposes).insert(
            PurposesCompanion.insert(
              id: id,
              name: stored,
              sortOrder: _nextPosition(activeRows, (row) => row.sortOrder),
              updatedAt: context.timestamp,
            ),
          );
      await _appendChange(context, id, before: null);
      return id;
    });
  }

  /// Renames a Purpose. No Compound changes, because tags hold ids, and an
  /// unchanged name writes nothing. Throws [PurposeNameException] for an empty
  /// or duplicate name.
  Future<void> rename(
    String id, {
    required String name,
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._writeContexts.create(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final before = await _requireRow(id);
      final activeRows = await _activeQuery().get();
      final stored = validatePurposeName(
        name,
        activeRows.where((row) => row.id != id).map((row) => row.name),
      );
      if (stored == before.name) {
        return;
      }
      await (_database.update(_database.purposes)
            ..where((row) => row.id.equals(id)))
          .write(
        PurposesCompanion(
          name: Value<String>(stored),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      await _appendChange(context, id, before: before);
    });
  }

  Future<void> reorder(
    List<String> purposeIds, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._writeContexts.create(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final activeRows = await _activeQuery().get();
      _requireEachActiveIdOnce(
        purposeIds,
        activeRows.map((row) => row.id),
        name: 'purposeIds',
        noun: 'Purpose',
      );
      final beforeById = <String, PurposeRow>{
        for (final row in activeRows) row.id: row,
      };
      for (var index = 0; index < purposeIds.length; index += 1) {
        final id = purposeIds[index];
        final before = beforeById[id]!;
        if (before.sortOrder == index) {
          continue;
        }
        await (_database.update(_database.purposes)
              ..where((row) => row.id.equals(id)))
            .write(
          PurposesCompanion(
            sortOrder: Value<int>(index),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        await _appendChange(context, id, before: before);
      }
    });
  }

  /// Sets the tombstone. A Compound tagged with this Purpose keeps the id.
  Future<void> archive(
    String id, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._writeContexts.create(
      actor: actor,
      batchId: batchId,
    );
    return _database.transaction(() async {
      final before = await _requireRow(id);
      if (before.deletedAt != null) {
        return;
      }
      await (_database.update(_database.purposes)
            ..where((row) => row.id.equals(id)))
          .write(
        PurposesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      await _appendChange(context, id, before: before);
    });
  }

  /// Inserts the starter Purposes this device has never had, at the fixed seed
  /// timestamp so a real edit on any device is always newer. Runs inside the
  /// OTC seed transaction; a starter the user renamed or archived is left alone
  /// because its row already exists.
  Future<void> _seedStarterPurposes(WriteContext context) async {
    final existingIds = (await _database.select(_database.purposes).get())
        .map((row) => row.id)
        .toSet();
    for (final starter in starterPurposes) {
      if (existingIds.contains(starter.id)) {
        continue;
      }
      await _database.into(_database.purposes).insert(
            PurposesCompanion.insert(
              id: starter.id,
              name: starter.name,
              sortOrder: starter.sortOrder,
              updatedAt: compoundSeedTimestamp,
            ),
          );
      await _appendChange(context, starter.id, before: null);
    }
  }

  Future<Map<String, Object?>?> _imageFor(String id) async {
    final row = await (_database.select(_database.purposes)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _purposeImage(row);
  }

  Future<void> _appendChange(
    WriteContext context,
    String id, {
    required PurposeRow? before,
  }) async {
    final after = await _requireRow(id);
    await _repositories._activityLogWriter.append(
      context,
      entityTable: AppDatabase.purposesTable,
      entityId: id,
      beforeImage: before == null ? null : _purposeImage(before),
      afterImage: _purposeImage(after),
    );
  }

  SimpleSelectStatement<$PurposesTable, PurposeRow> _activeQuery() {
    return _database.select(_database.purposes)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
      ]);
  }

  Future<PurposeRow> _requireRow(String id) async {
    final row = await (_database.select(_database.purposes)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Purpose not found: $id.');
    }
    return row;
  }
}

PurposeRecord _purposeFromRow(PurposeRow row) {
  return PurposeRecord(
    id: row.id,
    name: row.name,
    sortOrder: row.sortOrder,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

Map<String, Object?> _purposeImage(PurposeRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'sort_order': row.sortOrder,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

PurposesCompanion _purposeCompanionFromImage(Map<String, Object?> image) {
  return PurposesCompanion(
    name: Value<String>(_activityRequiredString(image, 'name')),
    sortOrder: Value<int>(_activityRequiredInt(image, 'sort_order')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

PurposesCompanion _purposeSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _purposeCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

/// A Compound's stored `purpose_ids`: deduplicated, first occurrence and order
/// kept.
String _encodePurposeIds(Iterable<String> purposeIds) {
  return jsonEncode(normalizePurposeIds(purposeIds));
}

// Most Compounds a user creates have no Purposes; skip the decode for them.
List<String> _decodePurposeIds(String encoded) {
  if (encoded == '[]') {
    return const <String>[];
  }
  final decoded = jsonDecode(encoded);
  return decoded is List
      ? List<String>.unmodifiable(decoded.whereType<String>())
      : const <String>[];
}
