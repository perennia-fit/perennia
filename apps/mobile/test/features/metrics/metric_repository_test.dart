import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';

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

  group('metric repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('opens metric schema with sync-ready columns', () async {
      final columnsByTable = await database.describeSchema();

      expect(
        columnsByTable.keys,
        containsAll(<String>[
          AppDatabase.metricsTable,
          AppDatabase.metricReadingsTable,
        ]),
      );
      for (final tableName in <String>[
        AppDatabase.metricsTable,
        AppDatabase.metricReadingsTable,
      ]) {
        expect(columnsByTable[tableName], contains('id'), reason: tableName);
        expect(
          columnsByTable[tableName],
          contains('updated_at'),
          reason: tableName,
        );
        expect(
          columnsByTable[tableName],
          contains('deleted_at'),
          reason: tableName,
        );
      }

      expect(
        columnsByTable[AppDatabase.metricsTable],
        containsAll(<String>[
          'name',
          'unit',
          'value_shape',
          'metric_group',
          'goal_type',
          'goal_target_value',
          'enabled',
          'pinned',
          'sort_order',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.metricReadingsTable],
        containsAll(<String>[
          'metric_id',
          'value_json',
          'scalar_value',
          'scalar_entered',
          'at_time',
          'window_started_at',
          'window_ended_at',
          'provenance',
          'source',
          'external_id',
          'comment',
        ]),
      );
    });

    test('saves manual Reading, logs one batch, and reads it after reopen',
        () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_metrics_test_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final file = File('${directory.path}/metrics.sqlite');
      final fileDatabase = AppDatabase.openFile(file);
      final fileRepositories = TrainingRepositories(fileDatabase);

      final metricId = await fileRepositories.metrics.createMetric(
        const MetricDraft(
          name: 'Body Weight',
          unit: 'kilogram',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.bodyComposition,
          goalType: MetricGoalType.decrease,
          enabled: true,
          pinned: true,
          sortOrder: 0,
        ),
        actor: 'tester',
      );
      final atTime = DateTime.utc(2026, 6, 23, 7, 30);

      final readingId = await fileRepositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '82.125',
          atTime: atTime,
          source: 'manual',
          externalId: 'manual-reading-1',
          comment: 'felt steady',
        ),
        actor: 'tester',
      );

      final readings = await fileRepositories.metrics.listReadings(metricId);
      expect(readings, hasLength(1));
      expect(readings.single.id, readingId);
      expect(readings.single.metricId, metricId);
      expect(readings.single.scalarValue, 82.125);
      expect(readings.single.scalarEntered, '82.125');
      expect(readings.single.atTime, atTime);
      expect(readings.single.windowStartedAt, isNull);
      expect(readings.single.windowEndedAt, isNull);
      expect(readings.single.provenance, MetricReadingProvenance.manual);
      expect(readings.single.source, 'manual');
      expect(readings.single.externalId, 'manual-reading-1');
      expect(readings.single.comment, 'felt steady');

      final logs = await fileRepositories.activityLog.listEntries();
      final readingLogs = logs
          .where(
            (entry) =>
                entry.entityTable == AppDatabase.metricReadingsTable &&
                entry.entityId == readingId,
          )
          .toList(growable: false);
      expect(readingLogs, hasLength(1));
      final readingBatch = logs
          .where((entry) => entry.batchId == readingLogs.single.batchId)
          .toList(growable: false);
      expect(readingBatch, hasLength(1));
      expect(readingLogs.single.actor, 'tester');
      expect(readingLogs.single.beforeImage, isNull);
      expect(readingLogs.single.afterImage?['metric_id'], metricId);
      expect(readingLogs.single.afterImage?['scalar_value'], 82.125);
      expect(readingLogs.single.afterImage?['scalar_entered'], '82.125');
      expect(
          readingLogs.single.afterImage?['at_time'], atTime.toIso8601String());
      expect(readingLogs.single.afterImage?['window_started_at'], isNull);
      expect(readingLogs.single.afterImage?['window_ended_at'], isNull);
      expect(readingLogs.single.afterImage?['provenance'], 'manual');
      expect(readingLogs.single.afterImage?['source'], 'manual');
      expect(readingLogs.single.afterImage?['external_id'], 'manual-reading-1');
      expect(readingLogs.single.afterImage?['comment'], 'felt steady');
      expect(readingLogs.single.afterImage, isNot(contains('delta')));
      expect(readingLogs.single.afterImage, isNot(contains('trend')));
      expect(readingLogs.single.afterImage, isNot(contains('goal_progress')));

      await fileDatabase.close();

      final reopened = AppDatabase.openFile(file);
      addTearDown(reopened.close);
      final reopenedRepositories = TrainingRepositories(reopened);
      final reopenedReading =
          (await reopenedRepositories.metrics.listReadings(metricId)).single;

      expect(reopenedReading.id, readingId);
      expect(reopenedReading.scalarValue, 82.125);
      expect(reopenedReading.scalarEntered, '82.125');
      expect(reopenedReading.atTime, atTime);
      expect(reopenedReading.provenance, MetricReadingProvenance.manual);
      expect(reopenedReading.source, 'manual');
      expect(reopenedReading.externalId, 'manual-reading-1');
      expect(reopenedReading.comment, 'felt steady');
    });

    test('exposes the full Reading provenance enum for future sources', () {
      expect(
        MetricReadingProvenance.values.map((value) => value.name),
        <String>['manual', 'integration', 'agent'],
      );
    });

    test('does not create demo monitoring Readings', () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );

      final summaries = await repositories.metrics.listMonitoringSummaries();
      expect(summaries, isEmpty);

      final bodyTrackerNames = (await repositories.measurements.listEnabled())
          .map((measurement) => measurement.name);
      expect(bodyTrackerNames, isNot(contains('Resting Heart Rate')));

      final localDate = TrainingDayDate(year: 2026, month: 6, day: 24);
      expect(
        await repositories.workoutSessions.listActiveForLocalDate(localDate),
        isEmpty,
      );
      expect(
        await repositories.workoutSessions
            .watchActiveForLocalDate(localDate)
            .first,
        isEmpty,
      );
      expect(await database.select(database.workoutExercises).get(), isEmpty);
      expect(await database.select(database.loggedSets).get(), isEmpty);

      final readingLogs = (await repositories.activityLog.listEntries()).where(
        (entry) => entry.entityTable == AppDatabase.metricReadingsTable,
      );
      expect(readingLogs, isEmpty);
    });

    test('watchMetricOptions ignores non-label Metric edits', () async {
      final metricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Calories',
          unit: 'kilocalorie',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.monitoring,
          enabled: true,
          pinned: false,
          sortOrder: 0,
        ),
      );

      final emissions = <List<MetricOptionRecord>>[];
      final subscription =
          repositories.metrics.watchMetricOptions().listen(emissions.add);
      addTearDown(subscription.cancel);

      await _waitFor(() => emissions.isNotEmpty);
      expect(emissions.last.single.id, metricId);
      expect(emissions.last.single.name, 'Calories');

      emissions.clear();
      await (database.update(database.metrics)
            ..where((row) => row.id.equals(metricId)))
          .write(
        MetricsCompanion(
          unit: const Value<String>('kilocalorie/day'),
          enabled: const Value<bool>(false),
          goalType: Value<String?>(MetricGoalType.increase.name),
          goalTargetValue: const Value<double?>(3000),
          updatedAt: Value<DateTime>(DateTime.utc(2026, 6, 24, 9)),
        ),
      );
      await pumpEventQueue(times: 5);
      expect(emissions, isEmpty);

      await (database.update(database.metrics)
            ..where((row) => row.id.equals(metricId)))
          .write(
        MetricsCompanion(
          name: const Value<String>('Calories Burned'),
          updatedAt: Value<DateTime>(DateTime.utc(2026, 6, 24, 10)),
        ),
      );
      await _waitFor(
        () => emissions.any(
          (options) => options.single.name == 'Calories Burned',
        ),
      );
    });

    test('edits manual and agent Readings but rejects integration edits',
        () async {
      final metricId = await _createMonitoringMetric(repositories);
      final manualId = await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '61',
          atTime: DateTime.utc(2026, 6, 24, 8),
          source: 'manual',
        ),
      );
      await _insertAgentReading(
        database,
        id: 'agent-reading-1',
        metricId: metricId,
        valueEntered: '62',
        atTime: DateTime.utc(2026, 6, 24, 9),
      );
      final integrationId =
          (await repositories.metrics.upsertIntegrationReadings(
        <IntegrationMetricReadingDraft>[
          IntegrationMetricReadingDraft.scalar(
            metricId: metricId,
            valueEntered: '63',
            atTime: DateTime.utc(2026, 6, 24, 10),
            source: 'garmin',
            externalId: 'rhr-2026-06-24',
          ),
        ],
      ))
              .single;

      await repositories.metrics.updateReading(
        manualId,
        MetricReadingUpdateDraft.scalar(
          metricId: metricId,
          valueEntered: '60',
          atTime: DateTime.utc(2026, 6, 24, 8, 5),
          comment: 'user correction',
        ),
      );
      await repositories.metrics.updateReading(
        'agent-reading-1',
        MetricReadingUpdateDraft.scalar(
          metricId: metricId,
          valueEntered: '61.5',
          atTime: DateTime.utc(2026, 6, 24, 9, 5),
          comment: 'agent correction',
        ),
      );

      expect(
        () => repositories.metrics.updateReading(
          integrationId,
          MetricReadingUpdateDraft.scalar(
            metricId: metricId,
            valueEntered: '62.5',
            atTime: DateTime.utc(2026, 6, 24, 10, 5),
          ),
        ),
        throwsStateError,
      );

      final readings = await repositories.metrics.listReadings(metricId);
      final byId = <String, MetricReadingRecord>{
        for (final reading in readings) reading.id: reading,
      };
      expect(byId[manualId]?.scalarEntered, '60');
      expect(byId[manualId]?.comment, 'user correction');
      expect(byId['agent-reading-1']?.scalarEntered, '61.5');
      expect(byId['agent-reading-1']?.comment, 'agent correction');
      expect(byId[integrationId]?.scalarEntered, '63');
      expect(byId[integrationId]?.comment, isNull);
    });

    test('overrides an integration Reading by delete and add-manual', () async {
      final metricId = await _createMonitoringMetric(repositories);
      final observedAt = DateTime.utc(2026, 6, 24, 8);
      final integrationId =
          (await repositories.metrics.upsertIntegrationReadings(
        <IntegrationMetricReadingDraft>[
          IntegrationMetricReadingDraft.scalar(
            metricId: metricId,
            valueEntered: '82',
            atTime: observedAt,
            source: 'withings',
            externalId: 'weight-2026-06-24',
          ),
        ],
      ))
              .single;

      await repositories.metrics.softDeleteReading(
        integrationId,
        actor: 'tester',
      );
      final manualId = await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '81.5',
          atTime: observedAt,
          source: 'manual',
          comment: 'scale correction',
        ),
        actor: 'tester',
      );

      final active = await repositories.metrics.listReadings(metricId);
      expect(active.map((reading) => reading.id), <String>[manualId]);
      expect(active.single.provenance, MetricReadingProvenance.manual);
      expect(active.single.scalarEntered, '81.5');

      final stored = await (database.select(database.metricReadings)
            ..where((row) => row.metricId.equals(metricId)))
          .get();
      expect(stored, hasLength(2));
      final integration = stored.singleWhere((row) => row.id == integrationId);
      expect(integration.provenance, MetricReadingProvenance.integration.name);
      expect(integration.scalarEntered, '82');
      expect(integration.deletedAt, isNotNull);
    });

    test('upserts integration Readings by source and externalId in one batch',
        () async {
      final metricId = await _createMonitoringMetric(repositories);
      final firstImportIds =
          await repositories.metrics.upsertIntegrationReadings(
        <IntegrationMetricReadingDraft>[
          IntegrationMetricReadingDraft.scalar(
            metricId: metricId,
            valueEntered: '61',
            atTime: DateTime.utc(2026, 6, 24, 8),
            source: 'garmin',
            externalId: 'rhr-2026-06-24',
            comment: 'first pass',
          ),
          IntegrationMetricReadingDraft.scalar(
            metricId: metricId,
            valueEntered: '58',
            atTime: DateTime.utc(2026, 6, 25, 8),
            source: 'garmin',
            externalId: 'rhr-2026-06-25',
          ),
        ],
        actor: 'garmin-import',
      );

      final createLogs = (await repositories.activityLog.listEntries())
          .where(
            (entry) =>
                entry.entityTable == AppDatabase.metricReadingsTable &&
                firstImportIds.contains(entry.entityId),
          )
          .toList(growable: false);
      expect(createLogs, hasLength(2));
      expect(createLogs.map((entry) => entry.batchId).toSet(), hasLength(1));
      expect(
        createLogs.map((entry) => entry.actor),
        everyElement('garmin-import'),
      );

      final secondImportIds =
          await repositories.metrics.upsertIntegrationReadings(
        <IntegrationMetricReadingDraft>[
          IntegrationMetricReadingDraft.scalar(
            metricId: metricId,
            valueEntered: '60',
            atTime: DateTime.utc(2026, 6, 24, 8),
            source: 'garmin',
            externalId: 'rhr-2026-06-24',
            comment: 'retry refresh',
          ),
        ],
        actor: 'garmin-import',
      );

      expect(secondImportIds, <String>[firstImportIds.first]);
      final readings = await repositories.metrics.listReadings(metricId);
      expect(readings, hasLength(2));
      final refreshed = readings.singleWhere(
        (reading) => reading.externalId == 'rhr-2026-06-24',
      );
      expect(refreshed.id, firstImportIds.first);
      expect(refreshed.scalarEntered, '60');
      expect(refreshed.comment, 'retry refresh');

      final refreshLogs = (await repositories.activityLog.listEntries())
          .where(
            (entry) =>
                entry.entityTable == AppDatabase.metricReadingsTable &&
                entry.entityId == firstImportIds.first,
          )
          .toList(growable: false);
      expect(refreshLogs, hasLength(2));
      expect(refreshLogs.last.beforeImage?['scalar_entered'], '61');
      expect(refreshLogs.last.afterImage?['scalar_entered'], '60');
    });

    test('honors integration Reading tombstones across re-import', () async {
      final metricId = await _createMonitoringMetric(repositories);
      final readingId = (await repositories.metrics.upsertIntegrationReadings(
        <IntegrationMetricReadingDraft>[
          IntegrationMetricReadingDraft.scalar(
            metricId: metricId,
            valueEntered: '61',
            atTime: DateTime.utc(2026, 6, 24, 8),
            source: 'garmin',
            externalId: 'rhr-2026-06-24',
          ),
        ],
      ))
          .single;
      await repositories.metrics.softDeleteReading(readingId);
      final logCountAfterDelete =
          (await repositories.activityLog.listEntries()).length;

      final reimportIds = await repositories.metrics.upsertIntegrationReadings(
        <IntegrationMetricReadingDraft>[
          IntegrationMetricReadingDraft.scalar(
            metricId: metricId,
            valueEntered: '60',
            atTime: DateTime.utc(2026, 6, 24, 8),
            source: 'garmin',
            externalId: 'rhr-2026-06-24',
          ),
        ],
      );

      expect(reimportIds, <String>[readingId]);
      expect(await repositories.metrics.listReadings(metricId), isEmpty);
      final stored = await (database.select(database.metricReadings)
            ..where((row) => row.id.equals(readingId)))
          .getSingle();
      expect(stored.scalarEntered, '61');
      expect(stored.deletedAt, isNotNull);
      expect(
        (await repositories.activityLog.listEntries()).length,
        logCountAfterDelete,
      );
    });

    test('archives a Reading with a tombstone instead of hard-deleting it',
        () async {
      final metricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Resting Heart Rate',
          unit: 'beatsPerMinute',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.monitoring,
          enabled: true,
          pinned: false,
          sortOrder: 0,
        ),
      );
      final readingId = await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '61',
          atTime: DateTime.utc(2026, 6, 24, 8),
          source: 'manual',
        ),
      );

      await repositories.metrics.softDeleteReading(readingId, actor: 'tester');

      expect(await repositories.metrics.listReadings(metricId), isEmpty);
      final stored = await (database.select(database.metricReadings)
            ..where((row) => row.id.equals(readingId)))
          .getSingle();
      expect(stored.deletedAt, isNotNull);

      final logs = await repositories.activityLog.listEntries();
      final deleteLog = logs.lastWhere(
        (entry) =>
            entry.entityTable == AppDatabase.metricReadingsTable &&
            entry.entityId == readingId,
      );
      expect(deleteLog.beforeImage?['deleted_at'], isNull);
      expect(deleteLog.afterImage?['deleted_at'], isNotNull);
    });
  });
}

Future<String> _createMonitoringMetric(TrainingRepositories repositories) {
  return repositories.metrics.createMetric(
    const MetricDraft(
      name: 'Resting Heart Rate',
      unit: 'beatsPerMinute',
      valueShape: MetricValueShape.scalar,
      group: MetricGroup.monitoring,
      enabled: true,
      pinned: false,
      sortOrder: 0,
    ),
  );
}

Future<void> _insertAgentReading(
  AppDatabase database, {
  required String id,
  required String metricId,
  required String valueEntered,
  required DateTime atTime,
}) {
  final scalarValue = double.parse(valueEntered);
  return database.into(database.metricReadings).insert(
        MetricReadingsCompanion.insert(
          id: id,
          metricId: metricId,
          valueJson: '{"shape":"scalar","value":$scalarValue,'
              '"entered":"$valueEntered"}',
          scalarValue: Value<double?>(scalarValue),
          scalarEntered: Value<String?>(valueEntered),
          atTime: Value<DateTime?>(atTime),
          provenance: MetricReadingProvenance.agent.name,
          source: MetricReadingProvenance.agent.name,
          externalId: Value<String?>('$id-external'),
          updatedAt: DateTime.utc(2026, 6, 24, 9),
        ),
      );
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  fail('Timed out waiting for condition.');
}
