import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../../data/local/uuid_v7.dart';
import '../../../data/repositories/training_repositories.dart';
import '../../settings/repositories/integration_consent_repository.dart';

final nutritionImportConsentRepositoryProvider =
    Provider<NutritionImportConsentRepository>((ref) {
  return NutritionImportConsentRepository(ref.watch(appDatabaseProvider));
});

final nutritionImportConsentProvider = StreamProvider<bool>((ref) {
  return ref.watch(nutritionImportConsentRepositoryProvider).watchConsent();
});

/// The on-device ("edge") import-consent gate for nutrition file imports
/// (NUTRITION.md §9; INTEGRATIONS.md §2). Unlike the Garmin tracker consent —
/// which is scoped to a connected OAuth credential — a file import has no
/// hosted credential, so its consent is a single self-managed local row under a
/// fixed [_edgeCredentialId]. There was no on-device enforcement to reuse; the
/// landing path consults [hasConsent] and refuses to land anything when off.
class NutritionImportConsentRepository {
  NutritionImportConsentRepository(
    this._database, {
    UuidV7Generator? uuidGenerator,
    DateTime Function()? clock,
  })  : _uuidGenerator = uuidGenerator ?? UuidV7Generator(),
        _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase _database;
  final UuidV7Generator _uuidGenerator;
  final DateTime Function() _clock;

  static const _edgeCredentialId = 'edge-local';
  static const _dataClass = ImportDataClass.nutrition;

  Stream<bool> watchConsent() {
    return _rowQuery().watch().map(_consentFromRows);
  }

  Future<bool> hasConsent() async {
    return _consentFromRows(await _rowQuery().get());
  }

  Future<void> setConsent({
    required bool enabled,
    String actor = 'app',
  }) async {
    final timestamp = _clock().toUtc();
    final context = _ConsentWriteContext(
      actor: actor,
      batchId: _createId(timestamp),
      timestamp: timestamp,
    );
    await _database.transaction(() async {
      final existing = await _rowQuery().getSingleOrNull();
      if (existing == null) {
        final id = _createId(timestamp);
        await _database.into(_database.integrationDataClassConsents).insert(
              IntegrationDataClassConsentsCompanion.insert(
                id: id,
                credentialId: _edgeCredentialId,
                dataClass: _dataClass.name,
                enabled: Value<bool>(enabled),
                updatedAt: timestamp,
              ),
            );
        final after = await _requireRow(id);
        await _appendActivityLog(
          context,
          entityId: id,
          beforeImage: null,
          afterImage: integrationConsentImage(after),
        );
        return;
      }
      if (existing.enabled == enabled && existing.deletedAt == null) {
        return;
      }
      final before = await _requireRow(existing.id);
      await (_database.update(_database.integrationDataClassConsents)
            ..where((table) => table.id.equals(existing.id)))
          .write(
        IntegrationDataClassConsentsCompanion(
          enabled: Value<bool>(enabled),
          updatedAt: Value<DateTime>(timestamp),
          deletedAt: const Value<DateTime?>(null),
        ),
      );
      final after = await _requireRow(existing.id);
      await _appendActivityLog(
        context,
        entityId: existing.id,
        beforeImage: integrationConsentImage(before),
        afterImage: integrationConsentImage(after),
      );
    });
  }

  SimpleSelectStatement<$IntegrationDataClassConsentsTable,
      IntegrationDataClassConsentRow> _rowQuery() {
    return _database.select(_database.integrationDataClassConsents)
      ..where(
        (row) =>
            row.credentialId.equals(_edgeCredentialId) &
            row.dataClass.equals(_dataClass.name),
      );
  }

  bool _consentFromRows(List<IntegrationDataClassConsentRow> rows) {
    final row = rows.where((row) => row.deletedAt == null).firstOrNull;
    return row?.enabled ?? false;
  }

  Future<IntegrationDataClassConsentRow> _requireRow(String id) async {
    final row = await (_database.select(_database.integrationDataClassConsents)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Nutrition import consent row not found: $id.');
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
