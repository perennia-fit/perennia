import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/biometric_authenticator.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';

/// LOAD-BEARING (acceptance criterion 3): the Supplements
/// lock is a DEVICE/UI control ONLY. It must never alter what syncs — a
/// Compound/Dose's Activity Log rows (the sync source of truth)
/// must be byte-for-byte IDENTICAL whether the lock is disabled, configured-
/// but-locked, or unlocked. This suite proves that by exercising the REAL
/// `ProtocolsRepository` against a real in-memory Drift database, and a
/// SEPARATE, entirely independent `ProtocolsLockController` (backed by fakes)
/// that the repository never references — there is no code path connecting
/// the two, and this test demonstrates it behaviourally.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  late AppDatabase database;
  late TrainingRepositories repositories;
  late _FakeProtocolsLockStore lockStore;
  late ProviderContainer lockContainer;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
    lockStore = _FakeProtocolsLockStore();
    lockContainer = ProviderContainer(
      overrides: [
        protocolsLockStoreProvider.overrideWith((ref) => lockStore),
        biometricAuthenticatorProvider.overrideWith(
          (ref) => _FakeBiometricAuthenticator(),
        ),
        protocolsLockControllerProvider.overrideWith(
          () => ProtocolsLockController(
            hasher: const ProtocolsPinHasher(iterations: 10),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    lockContainer.dispose();
    await database.close();
  });

  test(
    'a Dose logged BEFORE enabling the Supplements lock keeps syncing '
    '(unchanged Activity Log row) after the lock is enabled and locked',
    () async {
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Vitamin D',
          amountValue: 2000,
          amountEntered: '2000',
          unit: DoseUnit.internationalUnit,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 8),
        ),
      );
      final before = await _entryFor(repositories, logged.batchId);

      // Enable and lock the Supplements section — a control from a
      // COMPLETELY SEPARATE provider container. Nothing in this call
      // touches `repositories` or `database`.
      final controller =
          lockContainer.read(protocolsLockControllerProvider.notifier);
      await lockContainer.read(protocolsLockControllerProvider.future);
      await controller.enableLock('1234');
      expect(
        lockContainer.read(protocolsLockControllerProvider).value!.status,
        ProtocolsLockStatus.locked,
      );

      final after = await _entryFor(repositories, logged.batchId);

      expect(after.batchId, before.batchId);
      expect(after.entityId, before.entityId);
      expect(after.entityTable, before.entityTable);
      expect(after.afterImage, before.afterImage);
      expect(after.updatedAt, before.updatedAt);
      expect(after.deletedAt, before.deletedAt);
      // Still pending sync (unacknowledged) exactly as before — the lock
      // neither pushes, withholds, nor acknowledges anything.
      final syncRow = await _rawRow(database, after.id);
      expect(syncRow.syncAcknowledgedAt, isNull);
    },
  );

  test(
    'a Dose logged WHILE the Supplements lock is enabled+locked still writes '
    'a normal, sync-eligible Activity Log row',
    () async {
      final controller =
          lockContainer.read(protocolsLockControllerProvider.notifier);
      await lockContainer.read(protocolsLockControllerProvider.future);
      await controller.enableLock('1234');
      expect(
        lockContainer.read(protocolsLockControllerProvider).value!.status,
        ProtocolsLockStatus.locked,
      );

      // The lock is a rendering concern in the UI layer only; the
      // repository/Activity Log write path is reached exactly as if no lock
      // existed (there is no gate at this layer — Widgets -> Controllers ->
      // Repositories, and the lock sits ABOVE the widgets, never inside the
      // repository).
      final logged = await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundName: 'Magnesium Glycinate',
          amountValue: 400,
          amountEntered: '400',
          unit: DoseUnit.milligram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 6, 30, 21),
        ),
      );

      final entry = await _entryFor(repositories, logged.batchId);
      expect(entry.entityTable, AppDatabase.dosesTable);
      expect(entry.entityId, logged.doseId);
      expect(entry.afterImage!['compound_name'], 'Magnesium Glycinate');
      // Pending sync, same as any other write — never excluded.
      final syncRow = await _rawRow(database, entry.id);
      expect(syncRow.syncAcknowledgedAt, isNull);
    },
  );

  test(
    'disabling the Supplements lock does not touch the repository or '
    'Activity Log at all',
    () async {
      final logged = await repositories.protocols.createCompound(
        const CompoundDraft(
          name: 'Ashwagandha',
          defaultUnit: DoseUnit.milligram,
          defaultRoute: DoseRoute.oral,
        ),
      );
      final beforeCount = (await repositories.activityLog.listEntries())
          .length;

      final controller =
          lockContainer.read(protocolsLockControllerProvider.notifier);
      await lockContainer.read(protocolsLockControllerProvider.future);
      await controller.enableLock('1234');
      await controller.unlockWithPin('1234');
      final disabled = await controller.disableLock();
      expect(disabled, isTrue);

      final afterCount = (await repositories.activityLog.listEntries())
          .length;
      expect(afterCount, beforeCount);
      final entry = await _entryFor(repositories, logged.batchId);
      expect(entry.entityId, logged.compoundId);
    },
  );
}

Future<ActivityLogEntry> _entryFor(
  TrainingRepositories repositories,
  String batchId,
) async {
  final all = await repositories.activityLog.listEntries();
  return all.singleWhere((e) => e.batchId == batchId);
}

Future<ActivityLogRow> _rawRow(AppDatabase database, String id) {
  return (database.select(database.activityLog)..where((row) => row.id.equals(id)))
      .getSingle();
}

class _FakeProtocolsLockStore implements ProtocolsLockStore {
  bool enabled = false;
  String? pinHash;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }

  @override
  Future<String?> readPinHash() async => pinHash;

  @override
  Future<void> writePinHash(String hash) async {
    pinHash = hash;
  }

  @override
  Future<void> clearPin() async {
    pinHash = null;
  }
}

class _FakeBiometricAuthenticator implements BiometricAuthenticator {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> authenticate({required String reason}) async => false;
}
