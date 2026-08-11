import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../data/local/uuid_v7.dart';
import '../../../data/repositories/training_repositories.dart';

final integrationConsentRepositoryProvider =
    Provider<IntegrationConsentRepository>((ref) {
  return IntegrationConsentRepository(ref.watch(appDatabaseProvider));
});

final garminImportConsentStateProvider =
    StreamProvider<GarminImportConsentState>((ref) {
  return ref
      .watch(integrationConsentRepositoryProvider)
      .watchGarminImportConsentState();
});

enum ImportDataClass {
  activities,
  heartRate,
  gps,
  sleepWellness,
  bodyComposition,

  /// Food/nutrition imports (e.g. a Cronometer CSV). Gated and enforced
  /// **on-device only** — the §2 placement rule from INTEGRATIONS.md holds:
  /// the importer must refuse to land anything when this is un-consented, and
  /// no hosted-service code path can run it (NUTRITION.md §9).
  nutrition;

  String get label {
    return switch (this) {
      ImportDataClass.activities => 'Activities',
      ImportDataClass.heartRate => 'Heart rate',
      ImportDataClass.gps => 'GPS',
      ImportDataClass.sleepWellness => 'Sleep/wellness',
      ImportDataClass.bodyComposition => 'Body composition',
      ImportDataClass.nutrition => 'Nutrition imports',
    };
  }
}

class IntegrationConsentRepository {
  IntegrationConsentRepository(
    this._database, {
    UuidV7Generator? uuidGenerator,
    DateTime Function()? clock,
  })  : _uuidGenerator = uuidGenerator ?? UuidV7Generator(),
        _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase _database;
  final UuidV7Generator _uuidGenerator;
  final DateTime Function() _clock;

  Stream<GarminImportConsentState> watchGarminImportConsentState() {
    final query = _database.select(_database.integrationDataClassConsents)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.credentialId),
        (row) => OrderingTerm.asc(row.dataClass),
      ]);
    return query.watch().map(_garminStateFromRows);
  }

  Future<GarminImportConsentState> loadGarminImportConsentState() async {
    final query = _database.select(_database.integrationDataClassConsents)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.credentialId),
        (row) => OrderingTerm.asc(row.dataClass),
      ]);
    return _garminStateFromRows(await query.get());
  }

  Future<void> setGarminConsentEnabled(
    ImportDataClass dataClass, {
    required bool enabled,
    String actor = 'app',
  }) async {
    final state = await loadGarminImportConsentState();
    final row = state.rowFor(dataClass);
    if (row == null) {
      throw StateError(
        'Garmin ${dataClass.name} consent is not available to edit.',
      );
    }
    if (row.enabled == enabled) {
      return;
    }

    final timestamp = _clock().toUtc();
    final context = _ConsentWriteContext(
      actor: actor,
      batchId: _createId(timestamp),
      timestamp: timestamp,
    );
    await _database.transaction(() async {
      final before = await _requireRow(row.id);
      await (_database.update(_database.integrationDataClassConsents)
            ..where((table) => table.id.equals(row.id)))
          .write(
        IntegrationDataClassConsentsCompanion(
          enabled: Value<bool>(enabled),
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: const Value<DateTime?>(null),
        ),
      );
      final after = await _requireRow(row.id);
      await _appendActivityLog(
        context,
        entityId: row.id,
        beforeImage: integrationConsentImage(before),
        afterImage: integrationConsentImage(after),
      );
    });
  }

  Future<void> disconnectGarminImport({
    String actor = 'app',
  }) async {
    final state = await loadGarminImportConsentState();
    final credentialId = state.credentialId;
    if (credentialId == null) {
      return;
    }

    final timestamp = _clock().toUtc();
    final context = _ConsentWriteContext(
      actor: actor,
      batchId: _createId(timestamp),
      timestamp: timestamp,
    );
    final rows = await (_database.select(_database.integrationDataClassConsents)
          ..where(
            (row) =>
                row.credentialId.equals(credentialId) & row.deletedAt.isNull(),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.dataClass)]))
        .get();

    await _database.transaction(() async {
      for (final before in rows) {
        await (_database.update(_database.integrationDataClassConsents)
              ..where((table) => table.id.equals(before.id)))
            .write(
          IntegrationDataClassConsentsCompanion(
            enabled: const Value<bool>(false),
            updatedAt: Value<DateTime>(timestamp),
            deletedAt: Value<DateTime?>(timestamp),
          ),
        );
        final after = await _requireRow(before.id);
        await _appendActivityLog(
          context,
          entityId: before.id,
          beforeImage: integrationConsentImage(before),
          afterImage: integrationConsentImage(after),
        );
      }
    });
  }

  Future<IntegrationDataClassConsentRow> _requireRow(String id) async {
    final row = await (_database.select(_database.integrationDataClassConsents)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Integration consent row not found: $id.');
    }
    return row;
  }

  Future<void> _appendActivityLog(
    _ConsentWriteContext context, {
    required String entityId,
    required Map<String, Object?>? beforeImage,
    required Map<String, Object?>? afterImage,
  }) {
    final activityLogId = _createId(context.timestamp);
    return _database.into(_database.activityLog).insert(
          ActivityLogCompanion.insert(
            id: activityLogId,
            actor: context.actor,
            batchId: context.batchId,
            entityTable: AppDatabase.integrationDataClassConsentsTable,
            entityId: entityId,
            beforeImage: Value<String?>(
              beforeImage == null ? null : jsonEncode(beforeImage),
            ),
            afterImage: Value<String?>(
              afterImage == null ? null : jsonEncode(afterImage),
            ),
            occurredAt: context.timestamp,
            updatedAt: context.timestamp,
          ),
        );
  }

  String _createId(DateTime timestamp) {
    return _uuidGenerator.generate(timestamp: timestamp);
  }
}

@immutable
final class GarminImportConsentState {
  GarminImportConsentState({
    required this.credentialId,
    required Map<ImportDataClass, IntegrationDataClassConsentRow>
        rowsByDataClass,
  }) : rowsByDataClass =
            Map<ImportDataClass, IntegrationDataClassConsentRow>.unmodifiable(
          rowsByDataClass,
        );

  static final empty = GarminImportConsentState(
    credentialId: null,
    rowsByDataClass: <ImportDataClass, IntegrationDataClassConsentRow>{},
  );

  final String? credentialId;
  final Map<ImportDataClass, IntegrationDataClassConsentRow> rowsByDataClass;

  bool get isConnected => credentialId != null;

  bool consentFor(ImportDataClass dataClass) {
    return rowsByDataClass[dataClass]?.enabled ?? false;
  }

  bool canEdit(ImportDataClass dataClass) {
    return rowsByDataClass.containsKey(dataClass);
  }

  IntegrationDataClassConsentRow? rowFor(ImportDataClass dataClass) {
    return rowsByDataClass[dataClass];
  }
}

Map<String, Object?> integrationConsentImage(
  IntegrationDataClassConsentRow row,
) {
  return <String, Object?>{
    'id': row.id,
    'credential_id': row.credentialId,
    'data_class': row.dataClass,
    'enabled': row.enabled,
    'updated_at': row.updatedAt.toUtc().toIso8601String(),
    'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
  };
}

ImportDataClass? importDataClassFromName(String name) {
  for (final dataClass in ImportDataClass.values) {
    if (dataClass.name == name) {
      return dataClass;
    }
  }
  return null;
}

GarminImportConsentState _garminStateFromRows(
  List<IntegrationDataClassConsentRow> rows,
) {
  if (rows.isEmpty) {
    return GarminImportConsentState.empty;
  }
  final credentialId = rows.first.credentialId;
  final rowsByDataClass = <ImportDataClass, IntegrationDataClassConsentRow>{};
  for (final row in rows.where((row) => row.credentialId == credentialId)) {
    final dataClass = importDataClassFromName(row.dataClass);
    if (dataClass != null) {
      rowsByDataClass[dataClass] = row;
    }
  }
  return GarminImportConsentState(
    credentialId: credentialId,
    rowsByDataClass:
        Map<ImportDataClass, IntegrationDataClassConsentRow>.unmodifiable(
      rowsByDataClass,
    ),
  );
}

class _ConsentWriteContext {
  const _ConsentWriteContext({
    required this.actor,
    required this.batchId,
    required this.timestamp,
  });

  final String actor;
  final String batchId;
  final DateTime timestamp;
}
