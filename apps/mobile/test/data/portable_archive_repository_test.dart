import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  group('portable archive repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('exports a zip manifest plus one JSON-lines file per entity',
        () async {
      await _seedWorkoutData(repositories);
      final createdAt = DateTime.utc(2026, 6, 16, 12);
      final archiveFile =
          await Directory.systemTemp.createTemp('prn_archive_export_');
      addTearDown(() => archiveFile.delete(recursive: true));
      final destination = File('${archiveFile.path}/backup.zip');

      final bytes = await repositories.portableArchives.exportPortableArchive(
        createdAt: createdAt,
      );
      await repositories.portableArchives.exportPortableArchiveToFile(
        destination,
        createdAt: createdAt,
      );

      final zip = ZipDecoder().decodeBytes(bytes);
      final manifest = _manifestFrom(zip);
      final writtenBytes = await destination.readAsBytes();

      expect(bytes.take(2), <int>[0x50, 0x4b]);
      expect(writtenBytes.take(2), <int>[0x50, 0x4b]);
      expect(manifest['schemaVersion'], database.schemaVersion);
      expect(manifest['appVersion'], PortableArchiveRepository.appVersion);
      expect(manifest['createdAt'], createdAt.toIso8601String());
      expect(
        manifest['entities'],
        hasLength(AppDatabase.tableNames.length),
      );
      final rowsByTable = _archiveRowsByTable(bytes);
      _expectSeededMetricArchiveRows(rowsByTable);
      _expectSeededNutritionArchiveRows(rowsByTable);
      _expectSeededProtocolsArchiveRows(rowsByTable);
      _expectSeededWorkoutTemplateArchiveRows(rowsByTable);
      for (final tableName in AppDatabase.tableNames) {
        expect(
          zip.findFile(PortableArchiveRepository.entityFileName(tableName)),
          isNotNull,
          reason: tableName,
        );
      }
    });

    test('fresh export contains only the current plan entities', () async {
      final bytes = await repositories.portableArchives.exportPortableArchive(
        createdAt: DateTime.utc(2026, 7, 11, 12),
      );
      final zip = _decodeArchive(bytes);
      final manifest = _manifestFrom(zip);
      final manifestTables = (manifest['entities']! as List<Object?>)
          .map(
            (entry) => (entry! as Map<String, Object?>)['table']! as String,
          )
          .toSet();
      const currentPlanTables = <String>{
        AppDatabase.workoutTemplatesTable,
        AppDatabase.templateExercisesTable,
        AppDatabase.templateGroupsTable,
        AppDatabase.templateGroupMembersTable,
        AppDatabase.prescriptionsTable,
        AppDatabase.templateLinksTable,
        AppDatabase.planRoutinesTable,
        AppDatabase.routineEntriesTable,
      };
      const retiredPlanTables = <String>{
        'routines',
        'routine_days',
        'routine_exercises',
        'predefined_sets',
        'routine_exercise_groups',
        'routine_exercise_group_members',
      };

      expect(manifestTables, containsAll(currentPlanTables));
      expect(manifestTables.intersection(retiredPlanTables), isEmpty);
      for (final tableName in currentPlanTables) {
        expect(
          zip.findFile(PortableArchiveRepository.entityFileName(tableName)),
          isNotNull,
          reason: tableName,
        );
      }
      for (final tableName in retiredPlanTables) {
        expect(
          zip.findFile(PortableArchiveRepository.entityFileName(tableName)),
          isNull,
          reason: tableName,
        );
      }
    });

    test('exports plaintext by default and AES-GCM archive with passphrase',
        () async {
      await _seedWorkoutData(repositories);

      final plaintext =
          await repositories.portableArchives.exportPortableArchive();
      final encrypted =
          await repositories.portableArchives.exportPortableArchive(
        encryption:
            const PortableArchiveEncryptionOptions(passphrase: 'correct horse'),
      );
      final plaintextZip = _decodeArchive(plaintext);
      final encryptedZip = _decodeArchive(encrypted);
      final encryptedManifest = _encryptedManifestFrom(encryptedZip);
      final inspectedEncrypted = await repositories.portableArchives
          .inspectPortableArchive(encrypted, passphrase: 'correct horse');

      expect(plaintextZip.findFile('manifest.json'), isNotNull);
      expect(
        encryptedZip.findFile(PortableArchiveRepository.manifestFileName),
        isNull,
      );
      expect(
        encryptedZip.findFile(
          PortableArchiveRepository.encryptedManifestFileName,
        ),
        isNotNull,
      );
      expect(
        encryptedZip.findFile(
          PortableArchiveRepository.encryptedPayloadFileName,
        ),
        isNotNull,
      );
      expect(
        encryptedManifest['iterations'],
        PortableArchiveRepository.keyDerivationIterations,
      );
      expect(inspectedEncrypted.schemaVersion, database.schemaVersion);
      expect(
        PortableArchiveEncryptionOptions.forgottenPassphraseWarning
            .toLowerCase(),
        contains('forget'),
      );
      expect(
        PortableArchiveEncryptionOptions.forgottenPassphraseWarning
            .toLowerCase(),
        contains('cannot be recovered'),
      );
    });

    test('manifest constructors snapshot collection fields', () {
      final entities = <PortableArchiveEntityManifest>[
        const PortableArchiveEntityManifest(
          tableName: 'workouts',
          fileName: 'entities/workouts.jsonl',
          rowCount: 1,
        ),
      ];
      final manifest = PortableArchiveManifest(
        formatVersion: PortableArchiveRepository.archiveFormatVersion,
        schemaVersion: 1,
        appVersion: 'test',
        createdAt: DateTime.utc(2026, 6, 16),
        entities: entities,
      );

      final salt = <int>[1, 2, 3];
      final nonce = <int>[4, 5, 6];
      final mac = <int>[7, 8, 9];
      final encryptedManifest = PortableArchiveEncryptedManifest(
        formatVersion: PortableArchiveRepository.archiveFormatVersion,
        encryptionAlgorithm: 'AES-256-GCM',
        keyDerivationAlgorithm: 'PBKDF2-HMAC-SHA256',
        keyDerivationIterations:
            PortableArchiveRepository.keyDerivationIterations,
        salt: salt,
        nonce: nonce,
        mac: mac,
        createdAt: DateTime.utc(2026, 6, 16),
      );

      entities.clear();
      salt[0] = 99;
      nonce.add(99);
      mac.clear();

      expect(manifest.entities, hasLength(1));
      expect(encryptedManifest.salt, <int>[1, 2, 3]);
      expect(encryptedManifest.nonce, <int>[4, 5, 6]);
      expect(encryptedManifest.mac, <int>[7, 8, 9]);
      expect(
        () => manifest.entities.add(
          const PortableArchiveEntityManifest(
            tableName: 'sets',
            fileName: 'entities/sets.jsonl',
            rowCount: 1,
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => encryptedManifest.salt.add(10),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => encryptedManifest.nonce.add(10),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => encryptedManifest.mac.add(10),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('import result snapshots collection fields', () {
      final changedRowsByTable = <String, int>{'workouts': 1};
      final skippedRowsByTable = <String, int>{'sets': 2};
      final changedExerciseIds = <String>{'exercise-1'};
      final result = PortableArchiveImportResult(
        changedRowsByTable: changedRowsByTable,
        skippedRowsByTable: skippedRowsByTable,
        changedExerciseIds: changedExerciseIds,
      );

      changedRowsByTable['doses'] = 3;
      skippedRowsByTable.clear();
      changedExerciseIds.add('exercise-2');

      expect(result.changedRowsByTable, <String, int>{'workouts': 1});
      expect(result.skippedRowsByTable, <String, int>{'sets': 2});
      expect(result.changedExerciseIds, <String>{'exercise-1'});
      expect(
        () => result.changedRowsByTable['doses'] = 3,
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => result.skippedRowsByTable.clear(),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => result.changedExerciseIds.add('exercise-2'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('round-trips into a fresh database without losing source rows',
        () async {
      await _seedWorkoutData(repositories);
      final sourceBytes =
          await repositories.portableArchives.exportPortableArchive();
      final sourceRows = _archiveRowsByTable(sourceBytes);
      _expectSeededMetricArchiveRows(sourceRows);
      _expectSeededNutritionArchiveRows(sourceRows);
      _expectSeededProtocolsArchiveRows(sourceRows);
      _expectSeededWorkoutTemplateArchiveRows(sourceRows);

      final restoredDatabase = AppDatabase.inMemory();
      addTearDown(restoredDatabase.close);
      final restoredRepositories = TrainingRepositories(restoredDatabase);

      final result = await restoredRepositories.portableArchives
          .importPortableArchive(sourceBytes);
      final restoredBytes =
          await restoredRepositories.portableArchives.exportPortableArchive();
      final restoredRows = _archiveRowsByTable(restoredBytes);
      _expectSeededMetricArchiveRows(restoredRows);
      _expectSeededNutritionArchiveRows(restoredRows);
      _expectSeededProtocolsArchiveRows(restoredRows);
      _expectSeededWorkoutTemplateArchiveRows(restoredRows);

      for (final tableName in AppDatabase.tableNames) {
        if (tableName == AppDatabase.activityLogTable) {
          continue;
        }
        expect(restoredRows[tableName], sourceRows[tableName],
            reason: tableName);
      }
      expect(result.changedRowsByTable[AppDatabase.exercisesTable], 1);
      expect(result.changedExerciseIds,
          contains(sourceRows[AppDatabase.exercisesTable]!.single['id']));
      expect(
        _ids(restoredRows[AppDatabase.activityLogTable]!),
        containsAll(_ids(sourceRows[AppDatabase.activityLogTable]!)),
      );
    });

    test('merges every plan-tree entity without destroying existing local rows',
        () async {
      final localExerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Local plan exercise',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final localSecondExerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Local second plan exercise',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final localWorkoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 7, 12, 8),
          timezone: 'UTC',
        ),
      );
      await _seedCompletePlanTree(
        database,
        prefix: 'local',
        exerciseId: localExerciseId,
        secondExerciseId: localSecondExerciseId,
        workoutId: localWorkoutId,
        updatedAt: DateTime.utc(2026, 7, 12, 8, 5),
      );
      final localRows = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );

      final remoteDatabase = AppDatabase.inMemory();
      addTearDown(remoteDatabase.close);
      final remoteRepositories = TrainingRepositories(remoteDatabase);
      final remoteExerciseId = await remoteRepositories.exercises.create(
        ExerciseDraft(
          name: 'Remote plan exercise',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final remoteSecondExerciseId = await remoteRepositories.exercises.create(
        ExerciseDraft(
          name: 'Remote second plan exercise',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.reps],
          ),
        ),
      );
      final remoteWorkoutId = await remoteRepositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 7, 12, 9),
          timezone: 'UTC',
        ),
      );
      await _seedCompletePlanTree(
        remoteDatabase,
        prefix: 'remote',
        exerciseId: remoteExerciseId,
        secondExerciseId: remoteSecondExerciseId,
        workoutId: remoteWorkoutId,
        updatedAt: DateTime.utc(2026, 7, 12, 9, 5),
      );
      final remoteArchive =
          await remoteRepositories.portableArchives.exportPortableArchive();
      final remoteRows = _archiveRowsByTable(remoteArchive);

      final result = await repositories.portableArchives.importPortableArchive(
        remoteArchive,
      );
      final mergedRows = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );

      for (final tableName in _planTreeTables) {
        expect(
          _ids(mergedRows[tableName]!),
          containsAll(_ids(localRows[tableName]!)),
          reason: '$tableName local rows',
        );
        expect(
          _ids(mergedRows[tableName]!),
          containsAll(_ids(remoteRows[tableName]!)),
          reason: '$tableName imported rows',
        );
        expect(
          result.changedRowsByTable[tableName],
          remoteRows[tableName]!.length,
          reason: tableName,
        );
      }
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    });

    test('encrypted archive round-trips with zero data loss', () async {
      await _seedWorkoutData(repositories);
      final sourceRows = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );
      // The strictest privacy tier (PROTOCOLS.md §8) keeps Protocols
      // OUT of CSV/share but IN the encrypted portable archive — a Compound +
      // Dose must survive this export→import round-trip byte-for-byte, same
      // as every other domain.
      _expectSeededProtocolsArchiveRows(sourceRows);
      final encrypted =
          await repositories.portableArchives.exportPortableArchive(
        encryption: const PortableArchiveEncryptionOptions(
          passphrase: 'top secret passphrase',
        ),
      );

      final restoredDatabase = AppDatabase.inMemory();
      addTearDown(restoredDatabase.close);
      final restoredRepositories = TrainingRepositories(restoredDatabase);

      final result =
          await restoredRepositories.portableArchives.importPortableArchive(
        encrypted,
        passphrase: 'top secret passphrase',
      );
      final restoredRows = _archiveRowsByTable(
        await restoredRepositories.portableArchives.exportPortableArchive(),
      );

      for (final tableName in AppDatabase.tableNames) {
        if (tableName == AppDatabase.activityLogTable) {
          continue;
        }
        expect(restoredRows[tableName], sourceRows[tableName],
            reason: tableName);
      }
      _expectSeededProtocolsArchiveRows(restoredRows);
      expect(result.changedRowsByTable[AppDatabase.loggedSetsTable], 1);
      expect(result.changedRowsByTable[AppDatabase.compoundsTable], 1);
      expect(result.changedRowsByTable[AppDatabase.dosesTable], 1);
      expect(result.changedExerciseIds, isNotEmpty);
    });

    test('decrypts using valid manifest iteration count different from export',
        () async {
      await _seedWorkoutData(repositories);
      final sourceBytes =
          await repositories.portableArchives.exportPortableArchive();
      final sourceRows = _archiveRowsByTable(sourceBytes);
      final legacyIterations =
          PortableArchiveRepository.minimumKeyDerivationIterations;
      expect(
        legacyIterations,
        isNot(PortableArchiveRepository.keyDerivationIterations),
      );
      final encrypted = await _encryptPlaintextArchiveForTest(
        sourceBytes,
        passphrase: 'older valid passphrase',
        iterations: legacyIterations,
      );

      final restoredDatabase = AppDatabase.inMemory();
      addTearDown(restoredDatabase.close);
      final restoredRepositories = TrainingRepositories(restoredDatabase);

      await restoredRepositories.portableArchives.importPortableArchive(
        encrypted,
        passphrase: 'older valid passphrase',
      );
      final restoredRows = _archiveRowsByTable(
        await restoredRepositories.portableArchives.exportPortableArchive(),
      );

      for (final tableName in AppDatabase.tableNames) {
        if (tableName == AppDatabase.activityLogTable) {
          continue;
        }
        expect(restoredRows[tableName], sourceRows[tableName],
            reason: tableName);
      }
    });

    test('imports merge-only with last-writer-wins and preserves local rows',
        () async {
      final remoteDatabase = AppDatabase.inMemory();
      addTearDown(remoteDatabase.close);
      final remoteRepositories = TrainingRepositories(remoteDatabase);
      await _insertExerciseRow(
        remoteDatabase,
        id: 'shared-exercise',
        name: 'Remote newer',
        updatedAt: DateTime.utc(2026, 6, 16, 12),
      );
      await _insertMetricRow(
        remoteDatabase,
        id: 'shared-metric',
        name: 'Remote newer metric',
        updatedAt: DateTime.utc(2026, 6, 16, 12),
      );
      await _insertMetricReadingRow(
        remoteDatabase,
        id: 'shared-reading',
        metricId: 'shared-metric',
        scalarEntered: '62',
        updatedAt: DateTime.utc(2026, 6, 16, 12),
        deletedAt: DateTime.utc(2026, 6, 16, 12, 30),
      );
      final remoteArchive =
          await remoteRepositories.portableArchives.exportPortableArchive();

      await _insertExerciseRow(
        database,
        id: 'shared-exercise',
        name: 'Local older',
        updatedAt: DateTime.utc(2026, 6, 16, 10),
      );
      await _insertExerciseRow(
        database,
        id: 'local-only',
        name: 'Local only',
        updatedAt: DateTime.utc(2026, 6, 16, 11),
      );
      await _insertMetricRow(
        database,
        id: 'shared-metric',
        name: 'Local older metric',
        updatedAt: DateTime.utc(2026, 6, 16, 10),
      );
      await _insertMetricReadingRow(
        database,
        id: 'shared-reading',
        metricId: 'shared-metric',
        scalarEntered: '60',
        updatedAt: DateTime.utc(2026, 6, 16, 10),
      );
      await _insertMetricRow(
        database,
        id: 'local-only-metric',
        name: 'Local only metric',
        updatedAt: DateTime.utc(2026, 6, 16, 11),
      );
      await _insertMetricReadingRow(
        database,
        id: 'local-only-reading',
        metricId: 'local-only-metric',
        scalarEntered: '70',
        updatedAt: DateTime.utc(2026, 6, 16, 11),
      );

      final result = await repositories.portableArchives.importPortableArchive(
        remoteArchive,
      );
      final rowsAfterNewerImport = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );
      final exercisesAfterNewerImport =
          rowsAfterNewerImport[AppDatabase.exercisesTable]!;
      final metricsAfterNewerImport =
          rowsAfterNewerImport[AppDatabase.metricsTable]!;
      final readingsAfterNewerImport =
          rowsAfterNewerImport[AppDatabase.metricReadingsTable]!;

      expect(
        exercisesAfterNewerImport.singleWhere(
          (row) => row['id'] == 'shared-exercise',
        )['name'],
        'Remote newer',
      );
      expect(
        exercisesAfterNewerImport.singleWhere(
          (row) => row['id'] == 'local-only',
        )['name'],
        'Local only',
      );
      expect(
        metricsAfterNewerImport.singleWhere(
          (row) => row['id'] == 'shared-metric',
        )['name'],
        'Remote newer metric',
      );
      expect(
        metricsAfterNewerImport.singleWhere(
          (row) => row['id'] == 'local-only-metric',
        )['name'],
        'Local only metric',
      );
      final sharedReadingAfterNewerImport =
          readingsAfterNewerImport.singleWhere(
        (row) => row['id'] == 'shared-reading',
      );
      expect(sharedReadingAfterNewerImport['scalarEntered'], '62');
      expect(sharedReadingAfterNewerImport['deletedAt'], isNotNull);
      expect(
        readingsAfterNewerImport.singleWhere(
          (row) => row['id'] == 'local-only-reading',
        )['scalarEntered'],
        '70',
      );
      expect(result.changedRowsByTable[AppDatabase.exercisesTable], 1);
      expect(result.changedRowsByTable[AppDatabase.metricsTable], 1);
      expect(result.changedRowsByTable[AppDatabase.metricReadingsTable], 1);
      expect(result.skippedRowsByTable[AppDatabase.exercisesTable], isNull);
      expect(
        (await repositories.activityLog.listEntries()).where(
          (entry) =>
              entry.actor == PortableArchiveRepository.importActor &&
              entry.entityTable == AppDatabase.exercisesTable &&
              entry.entityId == 'shared-exercise',
        ),
        isNotEmpty,
      );
      expect(
        (await repositories.activityLog.listEntries()).where(
          (entry) =>
              entry.actor == PortableArchiveRepository.importActor &&
              entry.entityTable == AppDatabase.metricReadingsTable &&
              entry.entityId == 'shared-reading',
        ),
        isNotEmpty,
      );

      final olderDatabase = AppDatabase.inMemory();
      addTearDown(olderDatabase.close);
      final olderRepositories = TrainingRepositories(olderDatabase);
      await _insertExerciseRow(
        olderDatabase,
        id: 'shared-exercise',
        name: 'Remote older',
        updatedAt: DateTime.utc(2026, 6, 16, 9),
      );
      await _insertMetricRow(
        olderDatabase,
        id: 'shared-metric',
        name: 'Remote older metric',
        updatedAt: DateTime.utc(2026, 6, 16, 9),
      );
      await _insertMetricReadingRow(
        olderDatabase,
        id: 'shared-reading',
        metricId: 'shared-metric',
        scalarEntered: '50',
        updatedAt: DateTime.utc(2026, 6, 16, 9),
      );
      final olderArchive =
          await olderRepositories.portableArchives.exportPortableArchive();

      final olderResult =
          await repositories.portableArchives.importPortableArchive(
        olderArchive,
      );
      final rowsAfterOlderImport = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );

      expect(
        rowsAfterOlderImport[AppDatabase.exercisesTable]!.singleWhere(
          (row) => row['id'] == 'shared-exercise',
        )['name'],
        'Remote newer',
      );
      expect(
        rowsAfterOlderImport[AppDatabase.metricsTable]!.singleWhere(
          (row) => row['id'] == 'shared-metric',
        )['name'],
        'Remote newer metric',
      );
      final sharedReadingAfterOlderImport =
          rowsAfterOlderImport[AppDatabase.metricReadingsTable]!.singleWhere(
        (row) => row['id'] == 'shared-reading',
      );
      expect(sharedReadingAfterOlderImport['scalarEntered'], '62');
      expect(sharedReadingAfterOlderImport['deletedAt'], isNotNull);
      expect(
          olderResult.changedRowsByTable[AppDatabase.exercisesTable], isNull);
      expect(olderResult.skippedRowsByTable[AppDatabase.exercisesTable], 1);
      expect(olderResult.changedRowsByTable[AppDatabase.metricsTable], isNull);
      expect(olderResult.skippedRowsByTable[AppDatabase.metricsTable], 1);
      expect(olderResult.changedRowsByTable[AppDatabase.metricReadingsTable],
          isNull);
      expect(
          olderResult.skippedRowsByTable[AppDatabase.metricReadingsTable], 1);
    });

    test(
        'plan-tree import is merge-only across conflicts, local rows, and tombstones',
        () async {
      final remoteDatabase = AppDatabase.inMemory();
      addTearDown(remoteDatabase.close);
      final remoteRepositories = TrainingRepositories(remoteDatabase);
      final remoteUpdatedAt = DateTime.utc(2026, 7, 11, 12);
      final remoteDeletedAt = DateTime.utc(2026, 7, 11, 12, 1);
      await _insertArchivePlanTree(
        remoteDatabase,
        prefix: 'shared-plan',
        templateName: 'Remote tombstone',
        entryNote: 'Remote note',
        repeat: 7,
        slot: 4,
        updatedAt: remoteUpdatedAt,
        deletedAt: remoteDeletedAt,
      );
      final remoteArchive =
          await remoteRepositories.portableArchives.exportPortableArchive();

      await _insertArchivePlanTree(
        database,
        prefix: 'shared-plan',
        templateName: 'Local older active',
        entryNote: 'Local older note',
        repeat: 3,
        slot: 1,
        updatedAt: DateTime.utc(2026, 7, 11, 10),
      );
      await _insertArchivePlanTree(
        database,
        prefix: 'local-only-plan',
        templateName: 'Local-only template',
        entryNote: 'Local-only note',
        repeat: 2,
        slot: 2,
        updatedAt: DateTime.utc(2026, 7, 11, 11),
      );

      final result = await repositories.portableArchives.importPortableArchive(
        remoteArchive,
      );
      final rowsAfterNewerImport = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );
      const sharedIds = <String, String>{
        AppDatabase.workoutTemplatesTable: 'shared-plan-template',
        AppDatabase.templateExercisesTable: 'shared-plan-entry',
        AppDatabase.prescriptionsTable: 'shared-plan-prescription',
        AppDatabase.templateLinksTable: 'shared-plan-link',
      };
      const localOnlyIds = <String, String>{
        AppDatabase.workoutTemplatesTable: 'local-only-plan-template',
        AppDatabase.templateExercisesTable: 'local-only-plan-entry',
        AppDatabase.prescriptionsTable: 'local-only-plan-prescription',
        AppDatabase.templateLinksTable: 'local-only-plan-link',
      };

      for (final entry in sharedIds.entries) {
        final row = rowsAfterNewerImport[entry.key]!
            .singleWhere((candidate) => candidate['id'] == entry.value);
        expect(row['deletedAt'], isNotNull, reason: entry.key);
        expect(result.changedRowsByTable[entry.key], 1, reason: entry.key);
      }
      for (final entry in localOnlyIds.entries) {
        final row = rowsAfterNewerImport[entry.key]!
            .singleWhere((candidate) => candidate['id'] == entry.value);
        expect(row['deletedAt'], isNull, reason: entry.key);
      }
      expect(
        rowsAfterNewerImport[AppDatabase.workoutTemplatesTable]!.singleWhere(
          (row) => row['id'] == sharedIds[AppDatabase.workoutTemplatesTable],
        )['name'],
        'Remote tombstone',
      );
      expect(
        rowsAfterNewerImport[AppDatabase.templateExercisesTable]!.singleWhere(
          (row) => row['id'] == sharedIds[AppDatabase.templateExercisesTable],
        )['note'],
        'Remote note',
      );
      expect(
        rowsAfterNewerImport[AppDatabase.prescriptionsTable]!.singleWhere(
          (row) => row['id'] == sharedIds[AppDatabase.prescriptionsTable],
        )['repeat'],
        7,
      );
      expect(
        rowsAfterNewerImport[AppDatabase.templateLinksTable]!.singleWhere(
          (row) => row['id'] == sharedIds[AppDatabase.templateLinksTable],
        )['slot'],
        4,
      );

      final importedPlanActivity =
          (await repositories.activityLog.listEntries())
              .where(
                (entry) =>
                    entry.actor == PortableArchiveRepository.importActor &&
                    sharedIds[entry.entityTable] == entry.entityId,
              )
              .toList(growable: false);
      expect(importedPlanActivity, hasLength(4));
      expect(
        importedPlanActivity.map((entry) => entry.batchId).toSet(),
        hasLength(1),
      );
      for (final activity in importedPlanActivity) {
        expect(activity.beforeImage?['deleted_at'], isNull);
        expect(activity.afterImage?['deleted_at'], isNotNull);
      }

      final olderDatabase = AppDatabase.inMemory();
      addTearDown(olderDatabase.close);
      final olderRepositories = TrainingRepositories(olderDatabase);
      await _insertArchivePlanTree(
        olderDatabase,
        prefix: 'shared-plan',
        templateName: 'Remote older active',
        entryNote: 'Remote older note',
        repeat: 1,
        slot: 1,
        updatedAt: DateTime.utc(2026, 7, 11, 9),
      );
      final olderArchive =
          await olderRepositories.portableArchives.exportPortableArchive();
      final olderResult =
          await repositories.portableArchives.importPortableArchive(
        olderArchive,
      );
      final rowsAfterOlderImport = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );

      for (final entry in sharedIds.entries) {
        final row = rowsAfterOlderImport[entry.key]!
            .singleWhere((candidate) => candidate['id'] == entry.value);
        expect(row['deletedAt'], isNotNull, reason: entry.key);
        expect(olderResult.changedRowsByTable[entry.key], isNull,
            reason: entry.key);
        expect(olderResult.skippedRowsByTable[entry.key], 1, reason: entry.key);
      }
      for (final entry in localOnlyIds.entries) {
        expect(
          rowsAfterOlderImport[entry.key]!.singleWhere(
              (candidate) => candidate['id'] == entry.value)['deletedAt'],
          isNull,
          reason: entry.key,
        );
      }
    });

    test('imports a schema-50 archive with v51 plan entities absent', () async {
      await _seedWorkoutData(repositories);
      final currentArchive =
          await repositories.portableArchives.exportPortableArchive();
      final schema50Archive = _asSchema50Archive(currentArchive);

      final restoredDatabase = AppDatabase.inMemory();
      addTearDown(restoredDatabase.close);
      final restoredRepositories = TrainingRepositories(restoredDatabase);

      await restoredRepositories.portableArchives.importPortableArchive(
        schema50Archive,
      );
      final restoredRows = _archiveRowsByTable(
        await restoredRepositories.portableArchives.exportPortableArchive(),
      );

      expect(restoredRows[AppDatabase.exercisesTable], isNotEmpty);
      expect(restoredRows[AppDatabase.workoutTemplatesTable], isEmpty);
      expect(restoredRows[AppDatabase.templateExercisesTable], isEmpty);
      expect(restoredRows[AppDatabase.prescriptionsTable], isEmpty);
      expect(restoredRows[AppDatabase.templateLinksTable], isEmpty);
    });

    test('imports an exact schema-52 archive with an opaque Routine seam',
        () async {
      await _seedWorkoutData(repositories);
      final currentArchive =
          await repositories.portableArchives.exportPortableArchive();
      final schema52Archive = _asSchema52Archive(currentArchive);

      final restoredDatabase = AppDatabase.inMemory();
      addTearDown(restoredDatabase.close);
      final restoredRepositories = TrainingRepositories(restoredDatabase);
      await restoredRepositories.portableArchives.importPortableArchive(
        schema52Archive,
      );

      expect(await restoredDatabase.select(restoredDatabase.planRoutines).get(),
          isEmpty);
      expect(
          await restoredDatabase.select(restoredDatabase.routineEntries).get(),
          isEmpty);
      final restoredLink = await (restoredDatabase.select(
        restoredDatabase.templateLinks,
      )..where((row) => row.id.equals('archive-template-link')))
          .getSingle();
      expect(restoredLink.routineId, isNull);
      expect(restoredLink.workoutTemplateId, 'archive-template');
      expect(
        await restoredDatabase.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    });

    test('imports schema-53 Routine rows as cadence-less collections',
        () async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Schema 53 template'),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Schema 53 collection'),
      );
      await repositories.routinePlans.addTemplateReference(
        routineId,
        templateId,
      );
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
      );
      final currentArchive =
          await repositories.portableArchives.exportPortableArchive();
      final schema53Archive = _asSchema53Archive(currentArchive);

      final restoredDatabase = AppDatabase.inMemory();
      addTearDown(restoredDatabase.close);
      final restoredRepositories = TrainingRepositories(restoredDatabase);
      await restoredRepositories.portableArchives.importPortableArchive(
        schema53Archive,
      );

      final restored =
          await restoredRepositories.routinePlans.getById(routineId);
      expect(restored?.cadence, isNull);
      expect(restored?.entries.single.slot, isNull);
    });

    test('rejects hard-invalid Prescriptions before writing anything',
        () async {
      await _seedWorkoutData(repositories);
      final source =
          await repositories.portableArchives.exportPortableArchive();
      final before = _archiveRowsByTable(source);
      final invalidRows = <String, Map<String, Object?>>{
        'unsupported mode': <String, Object?>{'mode': 'inherit'},
        'zero repeat': <String, Object?>{'repeat': 0},
        'negative rest': <String, Object?>{'restAfter': -1},
      };

      for (final invalid in invalidRows.entries) {
        final tampered = _withUpdatedArchiveEntityRow(
          source,
          tableName: AppDatabase.prescriptionsTable,
          update: (row) => <String, Object?>{
            ...row,
            ...invalid.value,
          },
        );
        await expectLater(
          repositories.portableArchives.importPortableArchive(tampered),
          throwsA(isA<PortableArchiveException>()),
          reason: invalid.key,
        );
        expect(
          _archiveRowsByTable(
            await repositories.portableArchives.exportPortableArchive(),
          ),
          before,
          reason: invalid.key,
        );
      }
    });

    test('rejects invalid archives before writing anything', () async {
      await _seedWorkoutData(repositories);
      final before = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );
      final badManifestArchive = _zipWith(
        'manifest.json',
        jsonEncode(<String, Object?>{
          'formatVersion': 999,
          'schemaVersion': database.schemaVersion,
          'appVersion': PortableArchiveRepository.appVersion,
          'createdAt': DateTime.utc(2026, 6, 16).toIso8601String(),
          'entities': <Object?>[],
        }),
      );

      await expectLater(
        repositories.portableArchives.importPortableArchive(badManifestArchive),
        throwsA(isA<PortableArchiveException>()),
      );
      await expectLater(
        repositories.portableArchives.importPortableArchive(<int>[1, 2, 3]),
        throwsA(isA<PortableArchiveException>()),
      );

      final after = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );
      expect(after, before);
    });

    test('rejects wrong passphrase and tampered ciphertext before writes',
        () async {
      await _seedWorkoutData(repositories);
      final before = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );
      final encrypted =
          await repositories.portableArchives.exportPortableArchive(
        encryption:
            const PortableArchiveEncryptionOptions(passphrase: 'right pass'),
      );

      await expectLater(
        repositories.portableArchives.importPortableArchive(
          encrypted,
          passphrase: 'wrong pass',
        ),
        throwsA(isA<PortableArchiveException>()),
      );
      await expectLater(
        repositories.portableArchives.importPortableArchive(
          _tamperEncryptedPayload(encrypted),
          passphrase: 'right pass',
        ),
        throwsA(isA<PortableArchiveException>()),
      );

      final after = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );
      expect(after, before);
    });

    test(
        'rejects encrypted archives below minimum KDF iterations before writes',
        () async {
      await _seedWorkoutData(repositories);
      final plaintext =
          await repositories.portableArchives.exportPortableArchive();
      final before = _archiveRowsByTable(plaintext);
      final encrypted = await _encryptPlaintextArchiveForTest(
        plaintext,
        passphrase: 'too cheap',
        iterations:
            PortableArchiveRepository.minimumKeyDerivationIterations - 1,
      );

      await expectLater(
        repositories.portableArchives.importPortableArchive(
          encrypted,
          passphrase: 'too cheap',
        ),
        throwsA(isA<PortableArchiveException>()),
      );

      final after = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );
      expect(after, before);
    });

    test('Template Groups round-trip with LWW and reject invalid rounds',
        () async {
      final firstExerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Archive run',
          type: ExerciseType(
            const <DimensionId>[DimensionId.distance],
          ),
        ),
      );
      final secondExerciseId = await repositories.exercises.create(
        ExerciseDraft(
          name: 'Archive carry',
          type: ExerciseType(
            const <DimensionId>[DimensionId.load, DimensionId.distance],
          ),
        ),
      );
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Archive hybrid'),
      );
      final firstEntryId = await repositories.workoutTemplates.addExercise(
        templateId,
        firstExerciseId,
      );
      final secondEntryId = await repositories.workoutTemplates.addExercise(
        templateId,
        secondExerciseId,
      );
      final groupId = await repositories.workoutTemplates.createTemplateGroup(
        templateId,
        TemplateGroupDraft(
          name: 'Hyrox circuit',
          colorHex: '#4A8FE0',
          rounds: 3,
          orderedTemplateExerciseIds: <String>[
            firstEntryId,
            secondEntryId,
          ],
        ),
      );
      final source =
          await repositories.portableArchives.exportPortableArchive();
      final sourceRows = _archiveRowsByTable(source);
      expect(
        sourceRows[AppDatabase.templateGroupsTable],
        contains(
          allOf(
            containsPair('id', groupId),
            containsPair('rounds', 3),
          ),
        ),
      );
      expect(
        sourceRows[AppDatabase.templateGroupMembersTable],
        hasLength(2),
      );

      final restoredDatabase = AppDatabase.inMemory();
      addTearDown(restoredDatabase.close);
      final restoredRepositories = TrainingRepositories(restoredDatabase);
      await restoredRepositories.portableArchives.importPortableArchive(
        source,
      );
      var restored =
          await restoredRepositories.workoutTemplates.getById(templateId);
      expect(restored?.groups.single.rounds, 3);
      expect(
        restored?.groups.single.members
            .map((member) => member.templateExerciseId),
        <String>[firstEntryId, secondEntryId],
      );

      await repositories.workoutTemplates.updateTemplateGroup(
        groupId,
        TemplateGroupDraft(
          name: 'Hyrox circuit',
          colorHex: '#4A8FE0',
          rounds: 4,
          orderedTemplateExerciseIds: <String>[
            firstEntryId,
            secondEntryId,
          ],
        ),
      );
      final newer = await repositories.portableArchives.exportPortableArchive();
      await restoredRepositories.portableArchives.importPortableArchive(
        newer,
      );
      restored =
          await restoredRepositories.workoutTemplates.getById(templateId);
      expect(restored?.groups.single.rounds, 4);

      final tampered = _withUpdatedArchiveEntityRow(
        newer,
        tableName: AppDatabase.templateGroupsTable,
        update: (row) => <String, Object?>{...row, 'rounds': 0},
      );
      await expectLater(
        restoredRepositories.portableArchives.importPortableArchive(tampered),
        throwsA(isA<PortableArchiveException>()),
      );
      expect(
        (await restoredRepositories.workoutTemplates.getById(templateId))
            ?.groups
            .single
            .rounds,
        4,
      );
    });

    test('rejects an invalid final LWW Template Group graph atomically',
        () async {
      final fixture = await _createPortableTemplateGroupFixture(
        repositories,
        count: 4,
      );
      final commonBase =
          await repositories.portableArchives.exportPortableArchive();

      await repositories.workoutTemplates.createTemplateGroup(
        fixture.templateId,
        TemplateGroupDraft(
          name: 'Local circuit',
          colorHex: '#4A8FE0',
          rounds: 2,
          orderedTemplateExerciseIds: fixture.entryIds.take(2).toList(),
        ),
      );
      final beforeRows = _archiveRowsByTable(
        await repositories.portableArchives.exportPortableArchive(),
      );
      final beforeActivityIds = (await repositories.activityLog.listEntries())
          .map((entry) => entry.id)
          .toList(growable: false);

      final remoteDatabase = AppDatabase.inMemory();
      addTearDown(remoteDatabase.close);
      final remoteRepositories = TrainingRepositories(remoteDatabase);
      await remoteRepositories.portableArchives.importPortableArchive(
        commonBase,
      );
      await remoteRepositories.workoutTemplates.createTemplateGroup(
        fixture.templateId,
        TemplateGroupDraft(
          name: 'Remote circuit',
          colorHex: '#E07A4A',
          rounds: 3,
          orderedTemplateExerciseIds: fixture.entryIds.skip(2).toList(),
        ),
      );
      final remoteArchive =
          await remoteRepositories.portableArchives.exportPortableArchive();

      await expectLater(
        repositories.portableArchives.importPortableArchive(remoteArchive),
        throwsA(isA<PortableArchiveException>()),
      );

      expect(
        _archiveRowsByTable(
          await repositories.portableArchives.exportPortableArchive(),
        ),
        beforeRows,
      );
      expect(
        (await repositories.activityLog.listEntries()).map((entry) => entry.id),
        beforeActivityIds,
      );
    });

    test('imports reverse-ID Template Group member replacement tombstone first',
        () async {
      final fixture = await _createPortableTemplateGroupFixture(
        repositories,
        count: 2,
      );
      final groupId = await repositories.workoutTemplates.createTemplateGroup(
        fixture.templateId,
        TemplateGroupDraft(
          name: 'Replacement circuit',
          colorHex: '#4A8FE0',
          rounds: 2,
          orderedTemplateExerciseIds: fixture.entryIds,
        ),
      );
      final originalMembers = await (database.select(
        database.templateGroupMembers,
      )..where((row) => row.groupId.equals(groupId)))
          .get();
      final replacedMember = originalMembers.singleWhere(
        (member) => member.templateExerciseId == fixture.entryIds.first,
      );
      final stableMember = originalMembers.singleWhere(
        (member) => member.templateExerciseId == fixture.entryIds.last,
      );
      await (database.update(database.templateGroupMembers)
            ..where((row) => row.id.equals(replacedMember.id)))
          .write(
        const TemplateGroupMembersCompanion(
          id: Value<String>('z-replaced-member'),
        ),
      );
      await (database.update(database.templateGroupMembers)
            ..where((row) => row.id.equals(stableMember.id)))
          .write(
        const TemplateGroupMembersCompanion(
          id: Value<String>('m-stable-member'),
        ),
      );

      final initialArchive =
          await repositories.portableArchives.exportPortableArchive();
      final restoredDatabase = AppDatabase.inMemory();
      addTearDown(restoredDatabase.close);
      final restoredRepositories = TrainingRepositories(restoredDatabase);
      await restoredRepositories.portableArchives.importPortableArchive(
        initialArchive,
      );
      final beforeActivityIds =
          (await restoredRepositories.activityLog.listEntries())
              .map((entry) => entry.id)
              .toSet();

      final changedAt = DateTime.now().toUtc().add(
            const Duration(seconds: 1),
          );
      await (database.update(database.templateGroupMembers)
            ..where((row) => row.id.equals('z-replaced-member')))
          .write(
        TemplateGroupMembersCompanion(
          updatedAt: Value<DateTime>(changedAt),
          deletedAt: Value<DateTime?>(changedAt),
        ),
      );
      await database.into(database.templateGroupMembers).insert(
            TemplateGroupMembersCompanion.insert(
              id: 'a-replacement-member',
              groupId: groupId,
              templateExerciseId: fixture.entryIds.first,
              position: replacedMember.position,
              updatedAt: changedAt,
            ),
          );
      final replacementArchive =
          await repositories.portableArchives.exportPortableArchive();

      final result = await restoredRepositories.portableArchives
          .importPortableArchive(replacementArchive);
      final restoredMembers = await (restoredDatabase.select(
        restoredDatabase.templateGroupMembers,
      )..where((row) => row.groupId.equals(groupId)))
          .get();
      expect(
        restoredMembers
            .singleWhere(
              (member) =>
                  member.templateExerciseId == fixture.entryIds.first &&
                  member.deletedAt == null,
            )
            .id,
        'a-replacement-member',
      );
      expect(
        restoredMembers
            .singleWhere((member) => member.id == 'z-replaced-member')
            .deletedAt,
        isNotNull,
      );
      expect(
        result.changedRowsByTable[AppDatabase.templateGroupMembersTable],
        2,
      );
      final importActivity =
          (await restoredRepositories.activityLog.listEntries())
              .where(
                (entry) =>
                    !beforeActivityIds.contains(entry.id) &&
                    entry.actor == PortableArchiveRepository.importActor &&
                    entry.entityTable == AppDatabase.templateGroupMembersTable,
              )
              .toList(growable: false);
      expect(importActivity, hasLength(2));
      expect(
        importActivity.map((entry) => entry.batchId).toSet(),
        hasLength(1),
      );
    });

    test('imports dissolved Template Group duplicate tombstoned history',
        () async {
      final fixture = await _createPortableTemplateGroupFixture(
        repositories,
        count: 2,
      );
      final groupId = await repositories.workoutTemplates.createTemplateGroup(
        fixture.templateId,
        TemplateGroupDraft(
          name: 'Archived circuit',
          colorHex: '#4A8FE0',
          rounds: 2,
          orderedTemplateExerciseIds: fixture.entryIds,
        ),
      );
      await repositories.workoutTemplates.dissolveTemplateGroup(groupId);
      final archivedMember = (await (database.select(
        database.templateGroupMembers,
      )..where((row) => row.groupId.equals(groupId)))
              .get())
          .first;
      await database.into(database.templateGroupMembers).insert(
            TemplateGroupMembersCompanion.insert(
              id: 'duplicate-tombstoned-loser',
              groupId: groupId,
              templateExerciseId: archivedMember.templateExerciseId,
              position: archivedMember.position,
              updatedAt: archivedMember.updatedAt,
              deletedAt: Value<DateTime?>(archivedMember.deletedAt),
            ),
          );
      final archive =
          await repositories.portableArchives.exportPortableArchive();

      final restoredDatabase = AppDatabase.inMemory();
      addTearDown(restoredDatabase.close);
      final restoredRepositories = TrainingRepositories(restoredDatabase);
      await restoredRepositories.portableArchives.importPortableArchive(
        archive,
      );

      final restoredGroup = await (restoredDatabase.select(
        restoredDatabase.templateGroups,
      )..where((row) => row.id.equals(groupId)))
          .getSingle();
      final restoredMembers = await (restoredDatabase.select(
        restoredDatabase.templateGroupMembers,
      )..where((row) => row.groupId.equals(groupId)))
          .get();
      expect(restoredGroup.deletedAt, isNotNull);
      expect(restoredMembers, hasLength(3));
      expect(
          restoredMembers.every((member) => member.deletedAt != null), isTrue);
      expect(
        restoredMembers.map((member) => member.id),
        contains('duplicate-tombstoned-loser'),
      );
    });

    test('Routine references round-trip with archived Templates and parent',
        () async {
      final firstTemplateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Archive intervals'),
      );
      final secondTemplateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Archive mobility'),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(
          name: 'Archive collection',
          notes: 'Reference semantics',
        ),
      );
      final firstEntryId = await repositories.routinePlans.addTemplateReference(
        routineId,
        firstTemplateId,
      );
      final duplicateEntryId =
          await repositories.routinePlans.addTemplateReference(
        routineId,
        firstTemplateId,
      );
      final secondEntryId =
          await repositories.routinePlans.addTemplateReference(
        routineId,
        secondTemplateId,
      );
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
      );
      await repositories.routinePlans.replaceCadenceLayout(
        routineId,
        <RoutineEntrySlotPlacement>[
          RoutineEntrySlotPlacement(entryId: firstEntryId, slot: 2),
          RoutineEntrySlotPlacement(entryId: duplicateEntryId, slot: 2),
          RoutineEntrySlotPlacement(entryId: secondEntryId, slot: 7),
        ],
      );
      await repositories.workoutTemplates.archive(firstTemplateId);
      await repositories.routinePlans.archive(routineId);
      final source =
          await repositories.portableArchives.exportPortableArchive();
      final sourceRows = _archiveRowsByTable(source);

      final restoredDatabase = AppDatabase.inMemory();
      addTearDown(restoredDatabase.close);
      final restoredRepositories = TrainingRepositories(restoredDatabase);
      final result = await restoredRepositories.portableArchives
          .importPortableArchive(source);
      final restoredRows = _archiveRowsByTable(
        await restoredRepositories.portableArchives.exportPortableArchive(),
      );
      final restoredRoutine =
          await restoredRepositories.routinePlans.getById(routineId);

      expect(
        restoredRows[AppDatabase.planRoutinesTable],
        sourceRows[AppDatabase.planRoutinesTable],
      );
      expect(
        restoredRows[AppDatabase.routineEntriesTable],
        sourceRows[AppDatabase.routineEntriesTable],
      );
      expect(restoredRoutine?.isArchived, isTrue);
      expect(restoredRoutine?.cadence?.kind, CadenceKind.weekly);
      expect(restoredRoutine?.cadence?.window, isNull);
      expect(restoredRoutine?.entries, hasLength(3));
      expect(
        restoredRoutine?.entries.map((entry) => entry.slot),
        <int?>[2, 2, 7],
      );
      expect(
        restoredRoutine?.entries
            .where((entry) => entry.workoutTemplateId == firstTemplateId)
            .every((entry) => entry.templateIsArchived),
        isTrue,
      );
      expect(
        restoredRoutine?.entries
            .singleWhere(
              (entry) => entry.workoutTemplateId == secondTemplateId,
            )
            .templateIsArchived,
        isFalse,
      );
      expect(result.changedRowsByTable[AppDatabase.planRoutinesTable], 1);
      expect(result.changedRowsByTable[AppDatabase.routineEntriesTable], 3);
      final importActivity =
          (await restoredRepositories.activityLog.listEntries())
              .where(
                (entry) =>
                    entry.actor == PortableArchiveRepository.importActor &&
                    (entry.entityTable == AppDatabase.planRoutinesTable ||
                        entry.entityTable == AppDatabase.routineEntriesTable),
              )
              .toList(growable: false);
      expect(importActivity, hasLength(4));
      expect(
        importActivity.map((entry) => entry.batchId).toSet(),
        hasLength(1),
      );
    });

    test('Routine LWW preserves local rows and newer tombstones', () async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Shared template'),
      );
      final sharedRoutineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Shared collection'),
      );
      final sharedEntryId =
          await repositories.routinePlans.addTemplateReference(
        sharedRoutineId,
        templateId,
      );
      final commonBase =
          await repositories.portableArchives.exportPortableArchive();
      final sharedRoutine = await (database.select(database.planRoutines)
            ..where((row) => row.id.equals(sharedRoutineId)))
          .getSingle();
      final newerAt = sharedRoutine.updatedAt.add(const Duration(minutes: 5));

      final localRoutineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Local-only collection'),
      );
      final localEntryId = await repositories.routinePlans.addTemplateReference(
        localRoutineId,
        templateId,
      );

      final remoteDatabase = AppDatabase.inMemory();
      addTearDown(remoteDatabase.close);
      final remoteRepositories = TrainingRepositories(remoteDatabase);
      await remoteRepositories.portableArchives.importPortableArchive(
        commonBase,
      );
      await (remoteDatabase.update(remoteDatabase.planRoutines)
            ..where((row) => row.id.equals(sharedRoutineId)))
          .write(
        PlanRoutinesCompanion(
          name: const Value<String>('Remote archived collection'),
          updatedAt: Value<DateTime>(newerAt),
          deletedAt: Value<DateTime?>(newerAt),
        ),
      );
      await (remoteDatabase.update(remoteDatabase.routineEntries)
            ..where((row) => row.id.equals(sharedEntryId)))
          .write(
        RoutineEntriesCompanion(
          updatedAt: Value<DateTime>(newerAt),
          deletedAt: Value<DateTime?>(newerAt),
        ),
      );
      final remoteArchive =
          await remoteRepositories.portableArchives.exportPortableArchive();

      final newerResult =
          await repositories.portableArchives.importPortableArchive(
        remoteArchive,
      );
      expect(
        (await repositories.routinePlans.getById(sharedRoutineId))?.isArchived,
        isTrue,
      );
      expect(
        (await repositories.routinePlans.getById(localRoutineId))
            ?.entries
            .single
            .id,
        localEntryId,
      );
      final sharedEntry = await (database.select(database.routineEntries)
            ..where((row) => row.id.equals(sharedEntryId)))
          .getSingle();
      expect(sharedEntry.deletedAt, isNotNull);
      expect(newerResult.changedRowsByTable[AppDatabase.planRoutinesTable], 1);
      expect(
          newerResult.changedRowsByTable[AppDatabase.routineEntriesTable], 1);

      final olderResult =
          await repositories.portableArchives.importPortableArchive(
        commonBase,
      );
      expect(
        (await repositories.routinePlans.getById(sharedRoutineId))?.isArchived,
        isTrue,
      );
      expect(olderResult.skippedRowsByTable[AppDatabase.planRoutinesTable], 1);
      expect(
          olderResult.skippedRowsByTable[AppDatabase.routineEntriesTable], 1);
    });

    test('Routine LWW reconciles a valid Cadence with a newer unslotted Entry',
        () async {
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Concurrent Cadence template'),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Concurrent Cadence collection'),
      );
      final entryId = await repositories.routinePlans.addTemplateReference(
        routineId,
        templateId,
      );
      final commonBase =
          await repositories.portableArchives.exportPortableArchive();

      final remoteDatabase = AppDatabase.inMemory();
      addTearDown(remoteDatabase.close);
      final remoteRepositories = TrainingRepositories(remoteDatabase);
      await remoteRepositories.portableArchives.importPortableArchive(
        commonBase,
      );
      final baseRoutine = await (remoteDatabase.select(
        remoteDatabase.planRoutines,
      )..where((row) => row.id.equals(routineId)))
          .getSingle();
      final remoteAt = baseRoutine.updatedAt.add(const Duration(minutes: 10));
      await (remoteDatabase.update(remoteDatabase.planRoutines)
            ..where((row) => row.id.equals(routineId)))
          .write(
        PlanRoutinesCompanion(
          cadenceKind: const Value<String?>('weekly'),
          cadenceWindow: const Value<int?>(null),
          updatedAt: Value<DateTime>(remoteAt),
        ),
      );
      await (remoteDatabase.update(remoteDatabase.routineEntries)
            ..where((row) => row.id.equals(entryId)))
          .write(
        RoutineEntriesCompanion(
          slot: const Value<int?>(1),
          updatedAt: Value<DateTime>(remoteAt),
        ),
      );
      final remoteArchive =
          await remoteRepositories.portableArchives.exportPortableArchive();

      // This local row is independently valid under the still cadence-less
      // local Routine, but newer than the remote Entry image. Row-level LWW
      // therefore creates a cross-row mismatch that import must reconcile.
      final localEntryAt = remoteAt.add(const Duration(minutes: 5));
      await (database.update(database.routineEntries)
            ..where((row) => row.id.equals(entryId)))
          .write(
        RoutineEntriesCompanion(
          updatedAt: Value<DateTime>(localEntryAt),
        ),
      );

      final result = await repositories.portableArchives.importPortableArchive(
        remoteArchive,
      );
      final routine = await repositories.routinePlans.getById(routineId);
      expect(routine?.cadence?.kind, CadenceKind.weekly);
      expect(routine?.entries.single.slot, 1);
      expect(result.changedRowsByTable[AppDatabase.planRoutinesTable], 1);
      expect(result.skippedRowsByTable[AppDatabase.routineEntriesTable], 1);
      expect(
        result.changedRowsByTable[AppDatabase.routineEntriesTable],
        greaterThanOrEqualTo(1),
      );
      final importActivity = (await repositories.activityLog.listEntries())
          .where(
            (entry) =>
                entry.actor == PortableArchiveRepository.importActor &&
                (entry.entityId == routineId || entry.entityId == entryId),
          )
          .toList(growable: false);
      final normalizedEntryActivity = importActivity.singleWhere(
        (entry) =>
            entry.entityId == entryId &&
            entry.beforeImage?['slot'] == null &&
            entry.afterImage?['slot'] == 1,
      );
      final currentImportActivity = importActivity
          .where((entry) => entry.batchId == normalizedEntryActivity.batchId)
          .toList(growable: false);
      expect(currentImportActivity, hasLength(2));
      expect(
        currentImportActivity.map((entry) => entry.batchId).toSet(),
        hasLength(1),
      );
      expect(
        normalizedEntryActivity.afterImage?['slot'],
        1,
      );
    });

    test('Routine LWW defaults changed slot meaning and coalesces undo image',
        () async {
      final templateIds = <String>[];
      for (var index = 0; index < 5; index += 1) {
        templateIds.add(
          await repositories.workoutTemplates.create(
            WorkoutTemplateDraft(name: 'Meaning ${index + 1}'),
          ),
        );
      }
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Cadence meaning'),
      );
      final entryIds = <String>[];
      for (final templateId in templateIds) {
        entryIds.add(
          await repositories.routinePlans.addTemplateReference(
            routineId,
            templateId,
          ),
        );
      }
      final commonBase =
          await repositories.portableArchives.exportPortableArchive();

      final remoteDatabase = AppDatabase.inMemory();
      addTearDown(remoteDatabase.close);
      final remoteRepositories = TrainingRepositories(remoteDatabase);
      await remoteRepositories.portableArchives.importPortableArchive(
        commonBase,
      );
      await remoteRepositories.routinePlans.setCadence(
        routineId,
        const Cadence.rotating(3),
      );
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
      );

      final remoteRoutine = await (remoteDatabase.select(
        remoteDatabase.planRoutines,
      )..where((row) => row.id.equals(routineId)))
          .getSingle();
      final localRoutine = await (database.select(database.planRoutines)
            ..where((row) => row.id.equals(routineId)))
          .getSingle();
      final localRoutineAt = remoteRoutine.updatedAt.add(
        const Duration(minutes: 5),
      );
      await (database.update(database.planRoutines)
            ..where((row) => row.id.equals(routineId)))
          .write(
        PlanRoutinesCompanion(
          updatedAt: Value<DateTime>(localRoutineAt),
        ),
      );
      expect(localRoutine.cadenceKind, 'weekly');

      final localLast = await (database.select(database.routineEntries)
            ..where((row) => row.id.equals(entryIds.last)))
          .getSingle();
      await (remoteDatabase.update(remoteDatabase.routineEntries)
            ..where((row) => row.id.equals(entryIds.last)))
          .write(
        RoutineEntriesCompanion(
          updatedAt: Value<DateTime>(
            localLast.updatedAt.add(const Duration(minutes: 10)),
          ),
        ),
      );
      final remoteArchive =
          await remoteRepositories.portableArchives.exportPortableArchive();

      final result = await repositories.portableArchives.importPortableArchive(
        remoteArchive,
      );
      final routine = (await repositories.routinePlans.getById(routineId))!;
      expect(routine.cadence?.kind, CadenceKind.weekly);
      // Rotating slot 2 is numerically valid for a week, but its meaning must
      // not be reinterpreted as Tuesday. Position 4 defaults to Friday.
      expect(routine.entries.last.slot, 5);
      expect(
        result.changedRowsByTable[AppDatabase.routineEntriesTable],
        greaterThanOrEqualTo(1),
      );

      final importLogs = (await repositories.activityLog.listEntries())
          .where(
            (entry) =>
                entry.actor == PortableArchiveRepository.importActor &&
                entry.entityTable == AppDatabase.routineEntriesTable &&
                entry.entityId == entryIds.last &&
                entry.beforeImage?['slot'] == 5 &&
                entry.afterImage?['slot'] == 5,
          )
          .toList(growable: false);
      expect(importLogs, hasLength(1));
      final undo = await repositories.activityLog.undoBatch(
        importLogs.single.batchId,
        actor: 'test-undo',
      );
      expect(undo.conflicts, isEmpty);
      expect(
        (await repositories.routinePlans.getById(routineId))?.entries.last.slot,
        5,
      );
    });

    test('normalizes concurrent Routine Entry additions deterministically',
        () async {
      final firstTemplateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Local archive plan'),
      );
      final secondTemplateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Remote archive plan'),
      );
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Concurrent collection'),
      );
      final commonBase =
          await repositories.portableArchives.exportPortableArchive();

      final localEntryId = await repositories.routinePlans.addTemplateReference(
        routineId,
        firstTemplateId,
      );

      final remoteDatabase = AppDatabase.inMemory();
      addTearDown(remoteDatabase.close);
      final remoteRepositories = TrainingRepositories(remoteDatabase);
      await remoteRepositories.portableArchives.importPortableArchive(
        commonBase,
      );
      final remoteEntryId =
          await remoteRepositories.routinePlans.addTemplateReference(
        routineId,
        secondTemplateId,
      );
      final remoteArchive =
          await remoteRepositories.portableArchives.exportPortableArchive();

      final result = await repositories.portableArchives.importPortableArchive(
        remoteArchive,
      );
      final expectedIds = <String>[localEntryId, remoteEntryId]..sort();
      final routine = await repositories.routinePlans.getById(routineId);
      expect(
        routine?.entries.map((entry) => entry.id),
        expectedIds,
      );
      expect(
        routine?.entries.map((entry) => entry.position),
        <int>[0, 1],
      );
      expect(
        result.changedRowsByTable[AppDatabase.routineEntriesTable],
        1,
      );
      final importActivity = (await repositories.activityLog.listEntries())
          .where(
            (entry) =>
                entry.actor == PortableArchiveRepository.importActor &&
                entry.entityTable == AppDatabase.routineEntriesTable,
          )
          .toList(growable: false);
      expect(importActivity, hasLength(1));
      expect(
        importActivity.map((entry) => entry.batchId).toSet(),
        hasLength(1),
      );
      expect(importActivity.single.entityId, remoteEntryId);
      expect(importActivity.single.beforeImage, isNull);
      expect(importActivity.single.afterImage?['position'], 1);
    });
  });
}

Future<({String templateId, List<String> entryIds})>
    _createPortableTemplateGroupFixture(
  TrainingRepositories repositories, {
  required int count,
}) async {
  final templateId = await repositories.workoutTemplates.create(
    const WorkoutTemplateDraft(name: 'Portable hybrid'),
  );
  final entryIds = <String>[];
  for (var index = 0; index < count; index += 1) {
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Portable station ${index + 1}',
        type: ExerciseType(
          const <DimensionId>[DimensionId.duration],
        ),
      ),
    );
    entryIds.add(
      await repositories.workoutTemplates.addExercise(
        templateId,
        exerciseId,
      ),
    );
  }
  return (templateId: templateId, entryIds: entryIds);
}

Future<void> _seedWorkoutData(TrainingRepositories repositories) async {
  final exerciseId = await repositories.exercises.create(
    ExerciseDraft(
      name: 'Bench Press',
      type: ExerciseType(<DimensionId>[
        DimensionId.load,
        DimensionId.reps,
      ]),
    ),
    actor: 'tester',
  );
  final workoutId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime.utc(2026, 6, 16, 8),
      timezone: 'UTC',
      localDate: const TrainingDayDate(year: 2026, month: 6, day: 16),
      comment: 'Archive test',
    ),
    actor: 'tester',
  );
  await repositories.workoutExercises.create(
    WorkoutExerciseDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
    ),
    actor: 'tester',
  );
  final setId = await repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: exerciseId,
      position: 0,
      values: LoggedSet.fromValues(
        const <SetDimensionValue>[
          SetDimensionValue(
            dimension: DimensionId.load,
            entered: '100',
            unit: TrainingUnit.kilogram,
          ),
          SetDimensionValue(
            dimension: DimensionId.reps,
            entered: '5',
            unit: TrainingUnit.repetition,
          ),
        ],
      ),
      isCompleted: true,
      plannedRestAfter: const Duration(seconds: 120),
    ),
    actor: 'tester',
  );
  await repositories.restTimers.startForSet(
    (await repositories.sets.getById(setId))!,
    defaultDuration: const Duration(seconds: 120),
    now: DateTime.utc(2026, 6, 16, 8, 5),
  );
  await _seedWorkoutTemplateData(
    repositories,
    exerciseId: exerciseId,
    workoutId: workoutId,
  );
  await _seedMetricData(repositories);
  await _seedNutritionData(repositories);
  await _seedProtocolsData(repositories);
}

const _planTreeTables = <String>[
  AppDatabase.workoutTemplatesTable,
  AppDatabase.templateExercisesTable,
  AppDatabase.prescriptionsTable,
  AppDatabase.templateGroupsTable,
  AppDatabase.templateGroupMembersTable,
  AppDatabase.planRoutinesTable,
  AppDatabase.routineEntriesTable,
  AppDatabase.templateLinksTable,
];

Future<void> _seedCompletePlanTree(
  AppDatabase database, {
  required String prefix,
  required String exerciseId,
  required String secondExerciseId,
  required String workoutId,
  required DateTime updatedAt,
}) async {
  final ids = <String, String>{
    AppDatabase.workoutTemplatesTable: '$prefix-template',
    AppDatabase.templateExercisesTable: '$prefix-template-exercise',
    AppDatabase.prescriptionsTable: '$prefix-prescription',
    AppDatabase.templateGroupsTable: '$prefix-template-group',
    AppDatabase.templateGroupMembersTable: '$prefix-template-group-member',
    AppDatabase.planRoutinesTable: '$prefix-routine',
    AppDatabase.routineEntriesTable: '$prefix-routine-entry',
    AppDatabase.templateLinksTable: '$prefix-template-link',
  };

  await database.into(database.workoutTemplates).insert(
        WorkoutTemplatesCompanion.insert(
          id: ids[AppDatabase.workoutTemplatesTable]!,
          name: '$prefix Template',
          notes: Value<String?>('$prefix notes'),
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateExercises).insert(
        TemplateExercisesCompanion.insert(
          id: ids[AppDatabase.templateExercisesTable]!,
          workoutTemplateId: ids[AppDatabase.workoutTemplatesTable]!,
          exerciseId: exerciseId,
          position: 0,
          note: Value<String?>('$prefix entry note'),
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateExercises).insert(
        TemplateExercisesCompanion.insert(
          id: '$prefix-template-exercise-2',
          workoutTemplateId: ids[AppDatabase.workoutTemplatesTable]!,
          exerciseId: secondExerciseId,
          position: 1,
          note: Value<String?>('$prefix second entry note'),
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.prescriptions).insert(
        PrescriptionsCompanion.insert(
          id: ids[AppDatabase.prescriptionsTable]!,
          templateExerciseId: ids[AppDatabase.templateExercisesTable]!,
          position: 0,
          repeat: const Value<int>(3),
          loadValue: const Value<double?>(60),
          loadUnit: const Value<String?>('kilogram'),
          loadEntered: const Value<String?>('60'),
          repsValue: const Value<double?>(5),
          repsUnit: const Value<String?>('repetition'),
          repsEntered: const Value<String?>('5'),
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateGroups).insert(
        TemplateGroupsCompanion.insert(
          id: ids[AppDatabase.templateGroupsTable]!,
          workoutTemplateId: ids[AppDatabase.workoutTemplatesTable]!,
          name: '$prefix Group',
          colorHex: '#4A8FE0',
          rounds: const Value<int>(3),
          position: 0,
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateGroupMembers).insert(
        TemplateGroupMembersCompanion.insert(
          id: ids[AppDatabase.templateGroupMembersTable]!,
          groupId: ids[AppDatabase.templateGroupsTable]!,
          templateExerciseId: ids[AppDatabase.templateExercisesTable]!,
          position: 0,
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateGroupMembers).insert(
        TemplateGroupMembersCompanion.insert(
          id: '$prefix-template-group-member-2',
          groupId: ids[AppDatabase.templateGroupsTable]!,
          templateExerciseId: '$prefix-template-exercise-2',
          position: 1,
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.planRoutines).insert(
        PlanRoutinesCompanion.insert(
          id: ids[AppDatabase.planRoutinesTable]!,
          name: '$prefix Routine',
          cadenceKind: const Value<String?>('weekly'),
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.routineEntries).insert(
        RoutineEntriesCompanion.insert(
          id: ids[AppDatabase.routineEntriesTable]!,
          routineId: ids[AppDatabase.planRoutinesTable]!,
          workoutTemplateId: ids[AppDatabase.workoutTemplatesTable]!,
          position: 0,
          slot: const Value<int?>(1),
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateLinks).insert(
        TemplateLinksCompanion.insert(
          id: ids[AppDatabase.templateLinksTable]!,
          workoutId: workoutId,
          workoutTemplateId: ids[AppDatabase.workoutTemplatesTable]!,
          routineId: Value<String?>(ids[AppDatabase.planRoutinesTable]),
          slot: const Value<int?>(1),
          updatedAt: updatedAt,
        ),
      );
}

Future<void> _seedWorkoutTemplateData(
  TrainingRepositories repositories, {
  required String exerciseId,
  required String workoutId,
}) async {
  final database = repositories.database;
  final updatedAt = DateTime.utc(2026, 6, 16, 8, 10);
  await database.into(database.workoutTemplates).insert(
        WorkoutTemplatesCompanion.insert(
          id: 'archive-template',
          name: 'Archive Push',
          notes: const Value<String?>('Keep one rep in reserve'),
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateExercises).insert(
        TemplateExercisesCompanion.insert(
          id: 'archive-template-exercise',
          workoutTemplateId: 'archive-template',
          exerciseId: exerciseId,
          position: 0,
          note: const Value<String?>('Use the flat bench'),
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.prescriptions).insert(
        PrescriptionsCompanion.insert(
          id: 'archive-prescription',
          templateExerciseId: 'archive-template-exercise',
          mode: const Value<String>('fixed'),
          position: 0,
          repeat: const Value<int>(3),
          restAfter: const Value<int?>(120),
          loadValue: const Value<double?>(100),
          loadUnit: const Value<String?>('kilogram'),
          loadEntered: const Value<String?>('100'),
          repsValue: const Value<double?>(5),
          repsUnit: const Value<String?>('repetition'),
          repsEntered: const Value<String?>('5'),
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.templateLinks).insert(
        TemplateLinksCompanion.insert(
          id: 'archive-template-link',
          workoutId: workoutId,
          workoutTemplateId: 'archive-template',
          updatedAt: updatedAt,
        ),
      );
}

void _expectSeededWorkoutTemplateArchiveRows(
  Map<String, List<Map<String, Object?>>> rowsByTable,
) {
  expect(
    rowsByTable[AppDatabase.workoutTemplatesTable],
    contains(
      containsPair('id', 'archive-template'),
    ),
  );
  expect(
    rowsByTable[AppDatabase.templateExercisesTable],
    contains(
      containsPair('id', 'archive-template-exercise'),
    ),
  );
  expect(
    rowsByTable[AppDatabase.prescriptionsTable],
    contains(
      allOf(
        containsPair('id', 'archive-prescription'),
        containsPair('repeat', 3),
        containsPair('restAfter', 120),
      ),
    ),
  );
  expect(
    rowsByTable[AppDatabase.templateLinksTable],
    contains(
      containsPair('id', 'archive-template-link'),
    ),
  );
}

// Protocols (Compound/Dose) rides the same merge-only LWW backup rails as
// every other domain: it is excluded from CSV/share but RETAINED in the
// encrypted portable archive (PROTOCOLS.md §8), so a user keeps a
// complete sovereign backup.
Future<void> _seedProtocolsData(TrainingRepositories repositories) async {
  final compound = await repositories.protocols.createCompound(
    CompoundDraft(
      name: 'Archive Vitamin D',
      defaultUnit: DoseUnit.internationalUnit,
      defaultRoute: DoseRoute.oral,
      strength: CompoundStrength.parse('1000 IU/capsule'),
    ),
    actor: 'tester',
  );
  await repositories.protocols.logDose(
    DoseSnapshotDraft(
      compoundId: compound.compoundId,
      compoundName: 'Archive Vitamin D',
      compoundStrength: CompoundStrength.parse('1000 IU/capsule'),
      amountValue: 2000,
      amountEntered: '2000',
      unit: DoseUnit.internationalUnit,
      route: DoseRoute.oral,
      tookAt: DateTime.utc(2026, 6, 16, 8),
    ),
    actor: 'tester',
  );
}

Future<void> _seedMetricData(TrainingRepositories repositories) async {
  final metricId = await repositories.metrics.createMetric(
    const MetricDraft(
      name: 'Body Weight',
      unit: 'kilogram',
      valueShape: MetricValueShape.scalar,
      group: MetricGroup.bodyComposition,
      goalType: MetricGoalType.decrease,
      goalTargetValue: 80,
      enabled: true,
      pinned: true,
      sortOrder: 0,
    ),
    actor: 'tester',
  );
  await repositories.metrics.createManualReading(
    ManualMetricReadingDraft.scalar(
      metricId: metricId,
      valueEntered: '82.125',
      atTime: DateTime.utc(2026, 6, 16, 7, 30),
      source: 'manual',
      externalId: 'archive-active-reading',
    ),
    actor: 'tester',
  );
  final tombstonedReadingId = await repositories.metrics.createManualReading(
    ManualMetricReadingDraft.scalar(
      metricId: metricId,
      valueEntered: '81.900',
      atTime: DateTime.utc(2026, 6, 17, 7, 30),
      source: 'manual',
      externalId: 'archive-tombstoned-reading',
    ),
    actor: 'tester',
  );
  await repositories.metrics.softDeleteReading(
    tombstonedReadingId,
    actor: 'tester',
  );
}

Future<void> _seedNutritionData(TrainingRepositories repositories) async {
  final quickEntry = await repositories.nutrition.logQuickEntry(
    meal: MealDraft(
      mealType: 'Breakfast',
      startedAt: DateTime.utc(2026, 6, 16, 9),
      timezone: 'UTC',
      localDate: const NutritionDayDate(year: 2026, month: 6, day: 16),
    ),
    entry: QuickFoodEntryDraft(
      name: 'Archive oats',
      nutrients: NutrientVector.energyAndMacros(
        energy: NutrientAmount.complete(
          value: 320,
          entered: '320',
          unit: NutrientUnit.kilocalorie,
        ),
        protein: NutrientAmount.complete(
          value: 18,
          entered: '18',
          unit: NutrientUnit.gram,
        ),
        carbohydrate: NutrientAmount.complete(
          value: 42,
          entered: '42',
          unit: NutrientUnit.gram,
        ),
        fat: NutrientAmount.complete(
          value: 7,
          entered: '7',
          unit: NutrientUnit.gram,
        ),
      ),
    ),
    actor: 'tester',
  );
  final foodId = await repositories.nutrition.createUserFood(
    UserFoodDraft(
      name: 'Archive protein bar',
      nutrientsPer100: NutrientVector.energyAndMacros(
        energy: NutrientAmount.complete(
          value: 500,
          entered: '500',
          unit: NutrientUnit.kilocalorie,
        ),
        protein: NutrientAmount.complete(
          value: 40,
          entered: '40',
          unit: NutrientUnit.gram,
        ),
        carbohydrate: NutrientAmount.complete(
          value: 35,
          entered: '35',
          unit: NutrientUnit.gram,
        ),
        fat: NutrientAmount.complete(
          value: 18,
          entered: '18',
          unit: NutrientUnit.gram,
        ),
      ),
      isLiquid: false,
      servingLabel: 'bar',
      servingSize: 50,
      packageSize: 200,
    ),
    actor: 'tester',
  );
  await repositories.nutrition.logFoodEntry(
    entry: FoodEntryDraft(
      mealId: quickEntry.mealId,
      foodId: foodId,
      portion: Portion(
        value: 0.5,
        entered: '0.5',
        unit: PortionUnit.package,
      ),
    ),
    actor: 'tester',
  );
}

Future<void> _insertExerciseRow(
  AppDatabase database, {
  required String id,
  required String name,
  required DateTime updatedAt,
}) {
  return database.into(database.exercises).insert(
        ExercisesCompanion.insert(
          id: id,
          name: name,
          dimensionIds: jsonEncode(<String>[
            DimensionId.load.name,
            DimensionId.reps.name,
          ]),
          defaultLoadUnit: Value<String>(TrainingUnit.kilogram.name),
          loadMode: Value<String>(ExerciseLoadMode.added.name),
          recordProfile: Value<String>(RecordProfile.repMax.name),
          updatedAt: updatedAt,
        ),
      );
}

Future<void> _insertArchivePlanTree(
  AppDatabase database, {
  required String prefix,
  required String templateName,
  required String entryNote,
  required int repeat,
  required int slot,
  required DateTime updatedAt,
  DateTime? deletedAt,
}) async {
  final exerciseId = '$prefix-exercise';
  final workoutId = '$prefix-workout';
  final templateId = '$prefix-template';
  final entryId = '$prefix-entry';
  await _insertExerciseRow(
    database,
    id: exerciseId,
    name: '$templateName Exercise',
    updatedAt: updatedAt,
  );
  await database.into(database.workoutSessions).insert(
        WorkoutSessionsCompanion.insert(
          id: workoutId,
          startedAt: updatedAt.subtract(const Duration(hours: 1)),
          timezone: 'UTC',
          localDate: const Value<String>('2026-07-11'),
          updatedAt: updatedAt,
        ),
      );
  await database.into(database.workoutTemplates).insert(
        WorkoutTemplatesCompanion.insert(
          id: templateId,
          name: templateName,
          notes: Value<String?>('$templateName notes'),
          updatedAt: updatedAt,
          deletedAt: Value<DateTime?>(deletedAt),
        ),
      );
  await database.into(database.templateExercises).insert(
        TemplateExercisesCompanion.insert(
          id: entryId,
          workoutTemplateId: templateId,
          exerciseId: exerciseId,
          position: 0,
          note: Value<String?>(entryNote),
          updatedAt: updatedAt,
          deletedAt: Value<DateTime?>(deletedAt),
        ),
      );
  await database.into(database.prescriptions).insert(
        PrescriptionsCompanion.insert(
          id: '$prefix-prescription',
          templateExerciseId: entryId,
          mode: const Value<String>('fixed'),
          position: 0,
          repeat: Value<int>(repeat),
          restAfter: const Value<int?>(120),
          loadValue: const Value<double?>(80),
          loadUnit: const Value<String?>('kilogram'),
          loadEntered: const Value<String?>('80'),
          repsValue: const Value<double?>(8),
          repsUnit: const Value<String?>('repetition'),
          repsEntered: const Value<String?>('8'),
          updatedAt: updatedAt,
          deletedAt: Value<DateTime?>(deletedAt),
        ),
      );
  await database.into(database.templateLinks).insert(
        TemplateLinksCompanion.insert(
          id: '$prefix-link',
          workoutId: workoutId,
          workoutTemplateId: templateId,
          slot: Value<int?>(slot),
          updatedAt: updatedAt,
          deletedAt: Value<DateTime?>(deletedAt),
        ),
      );
}

Future<void> _insertMetricRow(
  AppDatabase database, {
  required String id,
  required String name,
  required DateTime updatedAt,
}) {
  return database.into(database.metrics).insert(
        MetricsCompanion.insert(
          id: id,
          name: name,
          unit: 'beatsPerMinute',
          valueShape: MetricValueShape.scalar.name,
          metricGroup: MetricGroup.monitoring.name,
          goalType: Value<String?>(MetricGoalType.decrease.name),
          goalTargetValue: const Value<double?>(60),
          enabled: const Value<bool>(true),
          pinned: const Value<bool>(false),
          sortOrder: 0,
          updatedAt: updatedAt,
        ),
      );
}

Future<void> _insertMetricReadingRow(
  AppDatabase database, {
  required String id,
  required String metricId,
  required String scalarEntered,
  required DateTime updatedAt,
  DateTime? deletedAt,
}) {
  final scalarValue = double.parse(scalarEntered);
  return database.into(database.metricReadings).insert(
        MetricReadingsCompanion.insert(
          id: id,
          metricId: metricId,
          valueJson: jsonEncode(<String, Object?>{
            'shape': MetricValueShape.scalar.name,
            'value': scalarValue,
            'entered': scalarEntered,
          }),
          scalarValue: Value<double?>(scalarValue),
          scalarEntered: Value<String?>(scalarEntered),
          atTime: Value<DateTime?>(DateTime.utc(2026, 6, 16, 7, 30)),
          provenance: MetricReadingProvenance.manual.name,
          source: 'manual',
          externalId: Value<String?>('external-$id'),
          updatedAt: updatedAt,
          deletedAt: Value<DateTime?>(deletedAt),
        ),
      );
}

Archive _decodeArchive(List<int> bytes) {
  return ZipDecoder().decodeBytes(bytes);
}

Map<String, Object?> _manifestFrom(Archive archive) {
  final manifestFile = archive.findFile('manifest.json');
  expect(manifestFile, isNotNull);
  return jsonDecode(utf8.decode(manifestFile!.content)) as Map<String, Object?>;
}

Map<String, Object?> _encryptedManifestFrom(Archive archive) {
  final manifestFile =
      archive.findFile(PortableArchiveRepository.encryptedManifestFileName);
  expect(manifestFile, isNotNull);
  return jsonDecode(utf8.decode(manifestFile!.content)) as Map<String, Object?>;
}

Map<String, List<Map<String, Object?>>> _archiveRowsByTable(List<int> bytes) {
  final archive = _decodeArchive(bytes);
  return <String, List<Map<String, Object?>>>{
    for (final tableName in AppDatabase.tableNames)
      tableName: _jsonLinesFrom(
        archive.findFile(PortableArchiveRepository.entityFileName(tableName))!,
      ),
  };
}

List<Map<String, Object?>> _jsonLinesFrom(ArchiveFile file) {
  final content = utf8.decode(file.content).trimRight();
  if (content.isEmpty) {
    return const <Map<String, Object?>>[];
  }
  return content
      .split('\n')
      .map((line) => jsonDecode(line) as Map<String, Object?>)
      .toList(growable: false);
}

Set<Object?> _ids(List<Map<String, Object?>> rows) {
  return rows.map((row) => row['id']).toSet();
}

void _expectSeededMetricArchiveRows(
  Map<String, List<Map<String, Object?>>> rowsByTable,
) {
  final metricRows = rowsByTable[AppDatabase.metricsTable]!;
  final readingRows = rowsByTable[AppDatabase.metricReadingsTable]!;

  expect(metricRows, hasLength(1));
  final metric = metricRows.single;
  expect(metric['name'], 'Body Weight');
  expect(metric['unit'], 'kilogram');
  expect(metric['valueShape'], MetricValueShape.scalar.name);
  expect(metric['metricGroup'], MetricGroup.bodyComposition.name);
  expect(metric['goalType'], MetricGoalType.decrease.name);
  expect(metric['goalTargetValue'], 80);
  expect(metric['pinned'], isTrue);
  expect(metric['deletedAt'], isNull);

  expect(readingRows, hasLength(2));
  final activeReading = readingRows.singleWhere(
    (row) => row['externalId'] == 'archive-active-reading',
  );
  expect(activeReading['metricId'], metric['id']);
  expect(activeReading['scalarEntered'], '82.125');
  expect(activeReading['scalarValue'], 82.125);
  expect(activeReading['provenance'], MetricReadingProvenance.manual.name);
  expect(activeReading['source'], 'manual');
  expect(activeReading['deletedAt'], isNull);

  final tombstonedReading = readingRows.singleWhere(
    (row) => row['externalId'] == 'archive-tombstoned-reading',
  );
  expect(tombstonedReading['metricId'], metric['id']);
  expect(tombstonedReading['scalarEntered'], '81.900');
  expect(tombstonedReading['scalarValue'], 81.9);
  expect(tombstonedReading['deletedAt'], isNotNull);
}

void _expectSeededNutritionArchiveRows(
  Map<String, List<Map<String, Object?>>> rowsByTable,
) {
  final mealRows = rowsByTable[AppDatabase.mealsTable]!;
  final foodRows = rowsByTable[AppDatabase.foodsTable]!;
  final entryRows = rowsByTable[AppDatabase.foodEntriesTable]!;

  expect(mealRows, hasLength(1));
  final meal = mealRows.single;
  expect(meal['mealType'], 'Breakfast');
  expect(meal['timezone'], 'UTC');
  expect(meal['localDate'], '2026-06-16');
  expect(meal['endedAt'], isNull);
  expect(meal['deletedAt'], isNull);

  expect(foodRows, hasLength(1));
  final food = foodRows.single;
  expect(food['name'], 'Archive protein bar');
  expect(food['foodSource'], FoodSource.user.name);
  expect(food['isLiquid'], isFalse);
  expect(food['servingLabel'], 'bar');
  expect(food['servingSize'], 50);
  expect(food['packageSize'], 200);
  expect(food['deletedAt'], isNull);

  final foodNutrients =
      jsonDecode(food['nutrientValuesJson']! as String) as Map<String, Object?>;
  final foodEnergy =
      foodNutrients[NutrientId.energy.storageKey] as Map<String, Object?>;
  expect(foodEnergy['value'], 500);

  expect(entryRows, hasLength(2));
  final quickEntry = entryRows.singleWhere(
    (row) => row['entryKind'] == FoodEntryKind.quickEntry.name,
  );
  expect(quickEntry['mealId'], meal['id']);
  expect(quickEntry['name'], 'Archive oats');
  expect(quickEntry['foodId'], isNull);
  expect(quickEntry['portionJson'], isNull);
  expect(quickEntry['foodSource'], isNull);
  expect(quickEntry['isLiquid'], isNull);
  expect(quickEntry['servingLabel'], isNull);
  expect(quickEntry['servingSize'], isNull);
  expect(quickEntry['packageSize'], isNull);

  final nutrients = jsonDecode(quickEntry['nutrientValuesJson']! as String)
      as Map<String, Object?>;
  expect(
    nutrients.keys.toSet(),
    NutrientId.values.map((id) => id.storageKey).toSet(),
  );
  final energy =
      nutrients[NutrientId.energy.storageKey] as Map<String, Object?>;
  final fiber = nutrients[NutrientId.fiber.storageKey] as Map<String, Object?>;
  expect(energy['status'], NutrientValueStatus.complete.name);
  expect(energy['value'], 320);
  expect(energy['entered'], '320');
  expect(fiber['status'], NutrientValueStatus.unknown.name);

  final foodEntry = entryRows.singleWhere(
    (row) => row['entryKind'] == FoodEntryKind.food.name,
  );
  expect(foodEntry['mealId'], meal['id']);
  expect(foodEntry['name'], 'Archive protein bar');
  expect(foodEntry['foodId'], food['id']);
  expect(foodEntry['foodSource'], FoodSource.user.name);
  expect(foodEntry['isLiquid'], isFalse);
  expect(foodEntry['servingLabel'], 'bar');
  expect(foodEntry['servingSize'], 50);
  expect(foodEntry['packageSize'], 200);
  final portion =
      jsonDecode(foodEntry['portionJson']! as String) as Map<String, Object?>;
  expect(portion['value'], 0.5);
  expect(portion['entered'], '0.5');
  expect(portion['unit'], PortionUnit.package.name);
  final entryNutrients = jsonDecode(foodEntry['nutrientValuesJson']! as String)
      as Map<String, Object?>;
  expect(
    entryNutrients.keys.toSet(),
    NutrientId.values.map((id) => id.storageKey).toSet(),
  );
  final entryEnergy =
      entryNutrients[NutrientId.energy.storageKey] as Map<String, Object?>;
  expect(entryEnergy['value'], 500);
}

void _expectSeededProtocolsArchiveRows(
  Map<String, List<Map<String, Object?>>> rowsByTable,
) {
  final compoundRows = rowsByTable[AppDatabase.compoundsTable]!;
  final doseRows = rowsByTable[AppDatabase.dosesTable]!;

  expect(compoundRows, hasLength(1));
  final compound = compoundRows.single;
  expect(compound['name'], 'Archive Vitamin D');
  expect(compound['defaultUnit'], DoseUnit.internationalUnit.name);
  expect(compound['defaultRoute'], DoseRoute.oral.name);
  expect(
    compound['strength'],
    CompoundStrength.parse('1000 IU/capsule').storageValue,
  );
  expect(compound['deletedAt'], isNull);

  expect(doseRows, hasLength(1));
  final dose = doseRows.single;
  expect(dose['compoundId'], compound['id']);
  expect(dose['compoundName'], 'Archive Vitamin D');
  expect(
    dose['compoundStrength'],
    CompoundStrength.parse('1000 IU/capsule').storageValue,
  );
  expect(dose['amountEntered'], '2000');
  expect(dose['amountValue'], 2000);
  expect(dose['unit'], DoseUnit.internationalUnit.name);
  expect(dose['route'], DoseRoute.oral.name);
  expect(dose['deletedAt'], isNull);
}

List<int> _zipWith(String name, String content) {
  final archive = Archive()..addFile(ArchiveFile.string(name, content));
  return ZipEncoder().encode(archive);
}

List<int> _asSchema50Archive(List<int> bytes) {
  const postSchema50Tables = <String>{
    AppDatabase.workoutTemplatesTable,
    AppDatabase.templateExercisesTable,
    AppDatabase.templateGroupsTable,
    AppDatabase.templateGroupMembersTable,
    AppDatabase.planRoutinesTable,
    AppDatabase.routineEntriesTable,
    AppDatabase.prescriptionsTable,
    AppDatabase.templateLinksTable,
  };
  final source = _decodeArchive(bytes);
  final manifest = _manifestFrom(source);
  manifest['schemaVersion'] = 50;
  manifest['entities'] =
      (manifest['entities']! as List<Object?>).where((entry) {
    final entity = entry! as Map<String, Object?>;
    return !postSchema50Tables.contains(entity['table']);
  }).toList(growable: false);

  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        PortableArchiveRepository.manifestFileName,
        jsonEncode(manifest),
      ),
    );
  for (final file in source.files) {
    if (file.name == PortableArchiveRepository.manifestFileName ||
        postSchema50Tables.any(
          (table) =>
              file.name == PortableArchiveRepository.entityFileName(table),
        )) {
      continue;
    }
    archive.addFile(ArchiveFile.bytes(file.name, file.content));
  }
  return ZipEncoder().encode(archive);
}

List<int> _asSchema52Archive(List<int> bytes) {
  const schema53Tables = <String>{
    AppDatabase.planRoutinesTable,
    AppDatabase.routineEntriesTable,
  };
  final source = _decodeArchive(bytes);
  final manifest = _manifestFrom(source);
  manifest['schemaVersion'] = 52;
  manifest['entities'] =
      (manifest['entities']! as List<Object?>).where((entry) {
    final entity = entry! as Map<String, Object?>;
    return !schema53Tables.contains(entity['table']);
  }).toList(growable: false);

  final templateLinksFileName = PortableArchiveRepository.entityFileName(
    AppDatabase.templateLinksTable,
  );
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        PortableArchiveRepository.manifestFileName,
        jsonEncode(manifest),
      ),
    );
  for (final file in source.files) {
    if (file.name == PortableArchiveRepository.manifestFileName ||
        schema53Tables.any(
          (table) =>
              file.name == PortableArchiveRepository.entityFileName(table),
        )) {
      continue;
    }
    if (file.name == templateLinksFileName) {
      final rows = _jsonLinesFrom(file);
      expect(rows, isNotEmpty);
      rows[0] = <String, Object?>{
        ...rows[0],
        'routineId': 'opaque-routine-v52',
      };
      archive.addFile(
        ArchiveFile.string(
          file.name,
          rows.map(jsonEncode).join('\n'),
        ),
      );
      continue;
    }
    archive.addFile(ArchiveFile.bytes(file.name, file.content));
  }
  return ZipEncoder().encode(archive);
}

List<int> _asSchema53Archive(List<int> bytes) {
  final source = _decodeArchive(bytes);
  final manifest = _manifestFrom(source)..['schemaVersion'] = 53;
  final planRoutinesFileName = PortableArchiveRepository.entityFileName(
    AppDatabase.planRoutinesTable,
  );
  final routineEntriesFileName = PortableArchiveRepository.entityFileName(
    AppDatabase.routineEntriesTable,
  );
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        PortableArchiveRepository.manifestFileName,
        jsonEncode(manifest),
      ),
    );
  for (final file in source.files) {
    if (file.name == PortableArchiveRepository.manifestFileName) {
      continue;
    }
    if (file.name == planRoutinesFileName ||
        file.name == routineEntriesFileName) {
      final rows = _jsonLinesFrom(file)
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
      for (final row in rows) {
        if (file.name == planRoutinesFileName) {
          row.remove('cadenceKind');
          row.remove('cadenceWindow');
        } else {
          row.remove('slot');
        }
      }
      archive.addFile(
        ArchiveFile.string(
          file.name,
          rows.map(jsonEncode).join('\n'),
        ),
      );
      continue;
    }
    archive.addFile(ArchiveFile.bytes(file.name, file.content));
  }
  return ZipEncoder().encode(archive);
}

List<int> _withUpdatedArchiveEntityRow(
  List<int> bytes, {
  required String tableName,
  required Map<String, Object?> Function(Map<String, Object?> row) update,
}) {
  final source = _decodeArchive(bytes);
  final fileName = PortableArchiveRepository.entityFileName(tableName);
  final entityFile = source.findFile(fileName);
  expect(entityFile, isNotNull);
  final rows = _jsonLinesFrom(entityFile!);
  expect(rows, isNotEmpty);
  rows[0] = update(Map<String, Object?>.from(rows[0]));

  final archive = Archive();
  for (final file in source.files) {
    archive.addFile(
      file.name == fileName
          ? ArchiveFile.string(
              fileName,
              rows.map(jsonEncode).join('\n'),
            )
          : ArchiveFile.bytes(file.name, file.content),
    );
  }
  return ZipEncoder().encode(archive);
}

Future<List<int>> _encryptPlaintextArchiveForTest(
  List<int> plaintext, {
  required String passphrase,
  required int iterations,
}) async {
  final salt = List<int>.generate(16, (index) => index + 1);
  final nonce = List<int>.generate(12, (index) => index + 17);
  final secretKey = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(
    password: passphrase.trim(),
    nonce: salt,
  );
  final secretBox = await AesGcm.with256bits().encrypt(
    plaintext,
    secretKey: secretKey,
    nonce: nonce,
  );
  final manifest = PortableArchiveEncryptedManifest(
    formatVersion: 1,
    encryptionAlgorithm: 'AES-256-GCM',
    keyDerivationAlgorithm: 'PBKDF2-HMAC-SHA256',
    keyDerivationIterations: iterations,
    salt: salt,
    nonce: nonce,
    mac: secretBox.mac.bytes,
    createdAt: DateTime.utc(2026, 6, 16, 12),
  );
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        PortableArchiveRepository.encryptedManifestFileName,
        jsonEncode(manifest.toJson()),
      ),
    )
    ..addFile(
      ArchiveFile.bytes(
        PortableArchiveRepository.encryptedPayloadFileName,
        secretBox.cipherText,
      ),
    );
  return ZipEncoder().encode(archive);
}

List<int> _tamperEncryptedPayload(List<int> bytes) {
  final source = _decodeArchive(bytes);
  final manifest =
      source.findFile(PortableArchiveRepository.encryptedManifestFileName);
  final payload =
      source.findFile(PortableArchiveRepository.encryptedPayloadFileName);
  expect(manifest, isNotNull);
  expect(payload, isNotNull);

  final tamperedPayload = payload!.content.toList(growable: false);
  tamperedPayload[0] = tamperedPayload[0] ^ 0x01;
  final archive = Archive()
    ..addFile(
      ArchiveFile.bytes(
        PortableArchiveRepository.encryptedManifestFileName,
        manifest!.content,
      ),
    )
    ..addFile(
      ArchiveFile.bytes(
        PortableArchiveRepository.encryptedPayloadFileName,
        tamperedPayload,
      ),
    );
  return ZipEncoder().encode(archive);
}
