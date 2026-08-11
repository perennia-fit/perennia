import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';

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

  group('measurement repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('opens measurement schema with sync-ready columns', () async {
      final columnsByTable = await database.describeSchema();

      expect(
        columnsByTable.keys,
        containsAll(<String>[
          AppDatabase.measurementsTable,
          AppDatabase.measurementEntriesTable,
        ]),
      );
      for (final tableName in <String>[
        AppDatabase.measurementsTable,
        AppDatabase.measurementEntriesTable,
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
        columnsByTable[AppDatabase.measurementsTable],
        containsAll(<String>[
          'name',
          'unit',
          'goal_type',
          'target_value',
          'enabled',
          'sort_order',
        ]),
      );
      expect(
        columnsByTable[AppDatabase.measurementEntriesTable],
        containsAll(<String>[
          'measurement_id',
          'value',
          'value_entered',
          'measured_at',
          'comment',
        ]),
      );
    });

    test('seeds default enabled measurements for a fresh database', () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );

      final measurements = await repositories.measurements.listEnabled();

      expect(
        measurements.map((measurement) => measurement.name),
        <String>['Body Weight', 'Body Fat'],
      );
      expect(measurements.first.unit, MeasurementUnit.kilogram);
      expect(measurements.first.goalType, MeasurementGoalType.decrease);
      expect(measurements.last.unit, MeasurementUnit.percent);
      expect(measurements.last.goalType, MeasurementGoalType.decrease);
    });

    test('filters Body Tracker to curated body-composition Metrics', () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final heartRateId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Resting Heart Rate',
          unit: 'beatsPerMinute',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.monitoring,
          goalType: MetricGoalType.decrease,
          enabled: true,
          pinned: true,
          sortOrder: 2,
        ),
      );
      final unpinnedWaistId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Unpinned Waist',
          unit: 'centimeter',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.bodyComposition,
          goalType: MetricGoalType.decrease,
          enabled: true,
          pinned: false,
          sortOrder: 3,
        ),
      );
      await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Body Water',
          unit: 'percent',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.bodyComposition,
          enabled: true,
          pinned: true,
          sortOrder: 4,
        ),
      );
      final disabledWaistId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Disabled Migrated Waist',
          unit: 'centimeter',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.bodyComposition,
          goalType: MetricGoalType.decrease,
          enabled: false,
          pinned: false,
          sortOrder: 5,
        ),
      );
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: heartRateId,
          valueEntered: '61',
          atTime: DateTime.utc(2026, 6, 23, 7),
          source: 'manual',
        ),
      );
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: unpinnedWaistId,
          valueEntered: '83',
          atTime: DateTime.utc(2026, 6, 23, 8),
          source: 'manual',
        ),
      );
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: disabledWaistId,
          valueEntered: '84',
          atTime: DateTime.utc(2026, 6, 23, 9),
          source: 'manual',
        ),
      );

      expect(
        (await repositories.measurements.listEnabled())
            .map((measurement) => measurement.name),
        <String>['Body Weight', 'Body Fat'],
      );
      expect(
        (await repositories.measurements.listHistoryEntries())
            .map((item) => item.measurement.name),
        isEmpty,
      );
      expect(
        (await repositories.measurements.listActive())
            .map((measurement) => measurement.name),
        contains('Disabled Migrated Waist'),
      );

      await repositories.measurements.setMeasurementEnabled(
        disabledWaistId,
        true,
      );

      expect(
        (await repositories.measurements.listEnabled())
            .map((measurement) => measurement.name),
        contains('Disabled Migrated Waist'),
      );
      final reenabledWaist = await (database.select(database.metrics)
            ..where((row) => row.id.equals(disabledWaistId)))
          .getSingle();
      expect(reenabledWaist.pinned, isTrue);
      expect(
        (await repositories.measurements.listHistoryEntries())
            .map((item) => item.measurement.name),
        <String>['Disabled Migrated Waist'],
      );
    });

    test('saves manual Reading, logs activity, and reads it after reopen',
        () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_measurements_test_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final file = File('${directory.path}/body-tracker.sqlite');
      final fileDatabase = AppDatabase.openFile(file);
      final fileRepositories = TrainingRepositories(fileDatabase);

      await fileRepositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final bodyWeight =
          (await fileRepositories.measurements.listEnabled()).first;
      final measuredAt = DateTime.utc(2026, 6, 23, 7, 30);

      final entryId = await fileRepositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: '82.125',
          measuredAt: measuredAt,
          comment: 'After breakfast',
        ),
        actor: 'tester',
      );

      final summaries =
          await fileRepositories.measurements.listTrackSummaries();
      final bodyWeightSummary = summaries.firstWhere(
        (summary) => summary.measurement.id == bodyWeight.id,
      );
      expect(bodyWeightSummary.latestEntry?.id, entryId);
      expect(bodyWeightSummary.latestEntry?.valueEntered, '82.125');
      expect(bodyWeightSummary.latestEntry?.comment, 'After breakfast');

      final logs = await fileRepositories.activityLog.listEntries();
      final log = logs.singleWhere(
        (entry) =>
            entry.entityTable == AppDatabase.metricReadingsTable &&
            entry.entityId == entryId,
      );
      expect(log.actor, 'tester');
      expect(log.beforeImage, isNull);
      expect(log.afterImage?['metric_id'], bodyWeight.id);
      expect(log.afterImage?['scalar_value'], 82.125);
      expect(log.afterImage?['scalar_entered'], '82.125');
      expect(log.afterImage?['at_time'], measuredAt.toIso8601String());
      expect(log.afterImage?['provenance'], 'manual');
      expect(log.afterImage?['source'], 'manual');
      expect(log.afterImage?['comment'], 'After breakfast');
      expect(
        await fileDatabase.select(fileDatabase.measurementEntries).get(),
        isEmpty,
      );

      await fileDatabase.close();

      final reopened = AppDatabase.openFile(file);
      addTearDown(reopened.close);
      final reopenedRepositories = TrainingRepositories(reopened);
      final reopenedSummary =
          (await reopenedRepositories.measurements.listTrackSummaries())
              .firstWhere(
        (summary) => summary.measurement.name == 'Body Weight',
      );

      expect(reopenedSummary.latestEntry?.valueEntered, '82.125');
      expect(reopenedSummary.latestEntry?.measuredAt, measuredAt);
    });

    test('validates measurement numeric values', () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final bodyWeight = (await repositories.measurements.listEnabled()).first;

      Future<void> save(String value) {
        return repositories.measurements.createEntry(
          MeasurementEntryDraft(
            measurementId: bodyWeight.id,
            valueEntered: value,
            measuredAt: DateTime.utc(2026, 6, 23),
          ),
          actor: 'tester',
        );
      }

      await expectLater(
          save('-0.1'), throwsA(isA<MeasurementValueException>()));
      await expectLater(save('NaN'), throwsA(isA<MeasurementValueException>()));
      await expectLater(
        save('Infinity'),
        throwsA(isA<MeasurementValueException>()),
      );
      await expectLater(
        save('1.123456'),
        throwsA(isA<MeasurementValueException>()),
      );

      await save('0');
      await save('1.12345');
    });

    test('surfaces suspicious measurement warnings from the shared rule',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final bodyWeight = (await repositories.measurements.listEnabled()).first;

      Future<MeasurementValueValidation> validate(String value) {
        return repositories.measurements.validateEntry(
          MeasurementEntryDraft(
            measurementId: bodyWeight.id,
            valueEntered: value,
            measuredAt: DateTime.utc(2026, 6, 23),
          ),
        );
      }

      final suspicious = await validate('5000');
      expect(suspicious.warnings, hasLength(1));
      expect(
        suspicious.warnings.single.code,
        MeasurementValidationWarningCode.suspiciouslyHigh,
      );

      expect((await validate('0')).warnings, isEmpty);
      expect((await validate('500')).warnings, isEmpty);
    });

    test('lists measurement history newest first with optional filtering',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final measurements = await repositories.measurements.listEnabled();
      final bodyWeight = measurements.firstWhere(
        (measurement) => measurement.name == 'Body Weight',
      );
      final bodyFat = measurements.firstWhere(
        (measurement) => measurement.name == 'Body Fat',
      );

      await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: '82',
          measuredAt: DateTime.utc(2026, 6, 23, 7, 30),
        ),
      );
      await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: '81',
          measuredAt: DateTime.utc(2026, 6, 24, 7, 30),
        ),
      );
      await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: '80',
          measuredAt: DateTime.utc(2026, 6, 25, 7, 30),
        ),
      );
      await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyFat.id,
          valueEntered: '20',
          measuredAt: DateTime.utc(2026, 6, 26, 7, 30),
        ),
      );

      final allHistory = await repositories.measurements.listHistoryEntries();
      final bodyWeightHistory =
          await repositories.measurements.listHistoryEntries(
        measurementId: bodyWeight.id,
      );

      expect(
        allHistory.map((item) => item.measurement.name),
        <String>['Body Fat', 'Body Weight', 'Body Weight', 'Body Weight'],
      );
      expect(
        allHistory.map((item) => item.entry.valueEntered),
        <String>['20', '80', '81', '82'],
      );
      expect(
        bodyWeightHistory.map((item) => item.entry.valueEntered),
        <String>['80', '81', '82'],
      );
      expect(bodyWeightHistory[0].previousEntry?.valueEntered, '81');
      expect(bodyWeightHistory[1].previousEntry?.valueEntered, '82');
      expect(bodyWeightHistory[2].previousEntry, isNull);
    });

    test('watchHistoryEntries ignores unrelated measurement entry changes',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final measurements = await repositories.measurements.listEnabled();
      final bodyWeight = measurements.firstWhere(
        (measurement) => measurement.name == 'Body Weight',
      );
      final bodyFat = measurements.firstWhere(
        (measurement) => measurement.name == 'Body Fat',
      );
      await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: '82',
          measuredAt: DateTime.utc(2026, 6, 23, 7, 30),
        ),
      );

      final emissions = <List<MeasurementHistoryEntry>>[];
      final subscription = repositories.measurements
          .watchHistoryEntries(measurementId: bodyWeight.id)
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await _waitFor(() => emissions.isNotEmpty);
      await _pumpEventQueue(times: 5);

      emissions.clear();
      await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyFat.id,
          valueEntered: '20',
          measuredAt: DateTime.utc(2026, 6, 24, 7, 30),
        ),
      );
      await _pumpEventQueue(times: 5);

      subscription.cancel().ignore();
      expect(emissions, isEmpty);
    });

    test('watchHistoryEntries ignores unrelated monitoring Reading changes',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final measurements = await repositories.measurements.listEnabled();
      final bodyWeight = measurements.firstWhere(
        (measurement) => measurement.name == 'Body Weight',
      );
      await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: '82',
          measuredAt: DateTime.utc(2026, 6, 23, 7, 30),
        ),
      );

      final emissions = <List<MeasurementHistoryEntry>>[];
      final subscription =
          repositories.measurements.watchHistoryEntries().listen(emissions.add);
      addTearDown(subscription.cancel);
      await _waitFor(() => emissions.isNotEmpty);
      await _pumpEventQueue(times: 5);

      emissions.clear();
      final heartRateId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Resting Heart Rate',
          unit: 'beatsPerMinute',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.monitoring,
          goalType: MetricGoalType.decrease,
          enabled: true,
          pinned: true,
          sortOrder: 2,
        ),
      );
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: heartRateId,
          valueEntered: '60',
          atTime: DateTime.utc(2026, 6, 24, 7, 30),
          source: 'manual',
        ),
      );
      await _pumpEventQueue(times: 5);

      subscription.cancel().ignore();
      expect(emissions, isEmpty);
    });

    test('watchCuratedActiveById ignores unrelated measurement changes',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final measurements = await repositories.measurements.listEnabled();
      final bodyWeight = measurements.firstWhere(
        (measurement) => measurement.name == 'Body Weight',
      );
      final bodyFat = measurements.firstWhere(
        (measurement) => measurement.name == 'Body Fat',
      );

      final emissions = <MeasurementRecord?>[];
      final subscription = repositories.measurements
          .watchCuratedActiveById(bodyWeight.id)
          .listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });
      await _waitFor(() => emissions.any(
            (measurement) => measurement?.id == bodyWeight.id,
          ));
      await _pumpEventQueue(times: 5);

      emissions.clear();
      await repositories.measurements.setMeasurementEnabled(bodyFat.id, false);
      await _pumpEventQueue(times: 5);
      expect(emissions, isEmpty);

      await repositories.measurements.setMeasurementEnabled(
        bodyWeight.id,
        false,
      );
      await _waitFor(
        () => emissions.any(
          (measurement) =>
              measurement?.id == bodyWeight.id && measurement?.enabled == false,
        ),
      );
      subscription.cancel().ignore();
    });

    test('watchCuratedActive ignores unrelated Metric changes', () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );

      final emissions = <List<MeasurementRecord>>[];
      final subscription =
          repositories.measurements.watchCuratedActive().listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });
      await _waitFor(() => emissions.isNotEmpty);
      await _pumpEventQueue(times: 5);

      emissions.clear();
      await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Resting Heart Rate',
          unit: 'beatsPerMinute',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.monitoring,
          goalType: MetricGoalType.decrease,
          enabled: true,
          pinned: true,
          sortOrder: 2,
        ),
      );
      await _pumpEventQueue(times: 5);

      subscription.cancel().ignore();
      expect(emissions, isEmpty);
    });

    test('watchActive ignores unrelated Metric changes', () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );

      final emissions = <List<MeasurementRecord>>[];
      final subscription =
          repositories.measurements.watchActive().listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });
      await _waitFor(() => emissions.isNotEmpty);
      await _pumpEventQueue(times: 5);

      emissions.clear();
      await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Resting Heart Rate',
          unit: 'beatsPerMinute',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.monitoring,
          goalType: MetricGoalType.decrease,
          enabled: true,
          pinned: true,
          sortOrder: 2,
        ),
      );
      await _pumpEventQueue(times: 5);

      subscription.cancel().ignore();
      expect(emissions, isEmpty);
    });

    test('watchTrackSummaries ignores readings for disabled measurements',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final bodyWeight = (await repositories.measurements.listEnabled())
          .singleWhere((measurement) => measurement.name == 'Body Weight');
      await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: '82',
          measuredAt: DateTime.utc(2026, 6, 23, 7, 30),
        ),
      );
      final disabledWaistId = await repositories.measurements.createMeasurement(
        const MeasurementDraft(
          name: 'Disabled Waist',
          unit: MeasurementUnit.centimeter,
          goalType: MeasurementGoalType.decrease,
          enabled: false,
        ),
      );

      final emissions = <List<MeasurementTrackSummary>>[];
      final subscription =
          repositories.measurements.watchTrackSummaries().listen(emissions.add);
      addTearDown(() {
        subscription.cancel().ignore();
      });
      await _waitFor(() {
        return emissions.any(
          (summaries) => summaries.any(
            (summary) =>
                summary.measurement.id == bodyWeight.id &&
                summary.latestEntry?.valueEntered == '82',
          ),
        );
      });
      await _pumpEventQueue(times: 5);

      emissions.clear();
      await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: disabledWaistId,
          valueEntered: '90',
          measuredAt: DateTime.utc(2026, 6, 24, 7, 30),
        ),
      );
      await _pumpEventQueue(times: 5);

      subscription.cancel().ignore();
      expect(emissions, isEmpty);
    });

    test(
        'lists imported body-composition Readings beside manual entries without surfacing unpinned Metrics',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final measurements = await repositories.measurements.listEnabled();
      final bodyWeight = measurements.firstWhere(
        (measurement) => measurement.name == 'Body Weight',
      );

      final manualId = await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: '82',
          measuredAt: DateTime.utc(2026, 6, 23, 7, 30),
        ),
        actor: 'tester',
      );
      final importedIds = await repositories.metrics.upsertIntegrationReadings(
        <IntegrationMetricReadingDraft>[
          IntegrationMetricReadingDraft.scalar(
            metricId: bodyWeight.id,
            valueEntered: '80.5',
            atTime: DateTime.utc(2026, 6, 24, 7, 30),
            source: 'garmin',
            externalId: 'scale-2026-06-24:body-weight',
          ),
        ],
      );
      final unpinnedWaistId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Unpinned Waist',
          unit: 'centimeter',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.bodyComposition,
          goalType: MetricGoalType.decrease,
          enabled: true,
          pinned: false,
          sortOrder: 3,
        ),
      );
      await repositories.metrics.upsertIntegrationReadings(
        <IntegrationMetricReadingDraft>[
          IntegrationMetricReadingDraft.scalar(
            metricId: unpinnedWaistId,
            valueEntered: '83',
            atTime: DateTime.utc(2026, 6, 25, 7, 30),
            source: 'garmin',
            externalId: 'scale-2026-06-25:waist',
          ),
        ],
      );

      final history = await repositories.measurements.listHistoryEntries();
      expect(
        history.map((item) => item.measurement.name),
        <String>['Body Weight', 'Body Weight'],
      );
      expect(
        history.map((item) => item.entry.id),
        <String>[importedIds.single, manualId],
      );
      expect(
        history.first.entry.provenance,
        MetricReadingProvenance.integration,
      );
      expect(history.first.entry.source, 'garmin');
      expect(
        history.first.entry.externalId,
        'scale-2026-06-24:body-weight',
      );
      expect(history.last.entry.provenance, MetricReadingProvenance.manual);
      expect(history.last.entry.source, 'manual');
      expect(history.first.previousEntry?.id, manualId);
      expect(
        (await repositories.measurements.listEnabled())
            .map((measurement) => measurement.name),
        <String>['Body Weight', 'Body Fat'],
      );
    });

    test('updates and soft-deletes manual Readings through activity log',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final bodyWeight = (await repositories.measurements.listEnabled()).first;
      final entryId = await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: '82',
          measuredAt: DateTime.utc(2026, 6, 23, 7, 30),
          comment: 'Before cut',
        ),
        actor: 'tester',
      );

      await repositories.measurements.updateEntry(
        entryId,
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: '81',
          measuredAt: DateTime.utc(2026, 6, 24, 7, 30),
          comment: 'After cut',
        ),
        actor: 'tester',
      );

      final updatedHistory = await repositories.measurements.listHistoryEntries(
        measurementId: bodyWeight.id,
      );
      expect(updatedHistory.single.entry.id, entryId);
      expect(updatedHistory.single.entry.valueEntered, '81');
      expect(updatedHistory.single.entry.comment, 'After cut');
      expect(
        updatedHistory.single.entry.measuredAt,
        DateTime.utc(2026, 6, 24, 7, 30),
      );

      final updateLog =
          (await repositories.activityLog.listEntries()).lastWhere(
        (entry) =>
            entry.entityTable == AppDatabase.metricReadingsTable &&
            entry.entityId == entryId,
      );
      expect(updateLog.beforeImage?['scalar_entered'], '82');
      expect(updateLog.afterImage?['scalar_entered'], '81');
      expect(updateLog.afterImage?['comment'], 'After cut');

      await repositories.measurements.softDeleteEntry(entryId, actor: 'tester');

      expect(
        await repositories.measurements.listHistoryEntries(
          measurementId: bodyWeight.id,
        ),
        isEmpty,
      );
      final row = await (database.select(database.metricReadings)
            ..where((row) => row.id.equals(entryId)))
          .getSingle();
      expect(row.deletedAt, isNotNull);

      final deleteLog =
          (await repositories.activityLog.listEntries()).lastWhere(
        (entry) =>
            entry.entityTable == AppDatabase.metricReadingsTable &&
            entry.entityId == entryId,
      );
      expect(deleteLog.actor, 'tester');
      expect(deleteLog.beforeImage?['deleted_at'], isNull);
      expect(deleteLog.afterImage?['deleted_at'], isNotNull);
    });

    test('rejects in-place edits to imported body-composition Readings',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final bodyWeight = (await repositories.measurements.listEnabled()).first;
      final importedIds = await repositories.metrics.upsertIntegrationReadings(
        <IntegrationMetricReadingDraft>[
          IntegrationMetricReadingDraft.scalar(
            metricId: bodyWeight.id,
            valueEntered: '80.5',
            atTime: DateTime.utc(2026, 6, 24, 7, 30),
            source: 'garmin',
            externalId: 'scale-2026-06-24:body-weight',
          ),
        ],
      );

      await expectLater(
        repositories.measurements.updateEntry(
          importedIds.single,
          MeasurementEntryDraft(
            measurementId: bodyWeight.id,
            valueEntered: '80',
            measuredAt: DateTime.utc(2026, 6, 24, 8),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      final row = await (database.select(database.metricReadings)
            ..where((row) => row.id.equals(importedIds.single)))
          .getSingle();
      expect(row.scalarEntered, '80.5');
      expect(row.provenance, MetricReadingProvenance.integration.name);
      expect(row.deletedAt, isNull);
    });

    test('creates custom measurements with target values through activity log',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );

      final waistId = await repositories.measurements.createMeasurement(
        const MeasurementDraft(
          name: 'Waist',
          unit: MeasurementUnit.centimeter,
          goalType: MeasurementGoalType.target,
          targetValue: 80,
          enabled: true,
        ),
        actor: 'tester',
      );

      final measurements = await repositories.measurements.listActive();
      final waist = measurements.singleWhere(
        (measurement) => measurement.id == waistId,
      );

      expect(waist.name, 'Waist');
      expect(waist.unit, MeasurementUnit.centimeter);
      expect(waist.goalType, MeasurementGoalType.target);
      expect(waist.targetValue, 80);
      expect(waist.enabled, isTrue);
      expect(waist.sortOrder, 2);

      final log = (await repositories.activityLog.listEntries()).lastWhere(
        (entry) =>
            entry.entityTable == AppDatabase.metricsTable &&
            entry.entityId == waistId,
      );
      expect(log.actor, 'tester');
      expect(log.beforeImage, isNull);
      expect(log.afterImage?['name'], 'Waist');
      expect(log.afterImage?['goal_target_value'], 80);
    });

    test('enable and disable updates track visibility without deleting entries',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final bodyFat = (await repositories.measurements.listEnabled())
          .singleWhere((measurement) => measurement.name == 'Body Fat');
      final entryId = await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyFat.id,
          valueEntered: '20',
          measuredAt: DateTime.utc(2026, 6, 23, 7, 30),
        ),
        actor: 'tester',
      );

      await repositories.measurements.setMeasurementEnabled(
        bodyFat.id,
        false,
        actor: 'tester',
      );

      expect(
        (await repositories.measurements.listEnabled())
            .map((measurement) => measurement.name),
        <String>['Body Weight'],
      );
      final entryRow = await (database.select(database.metricReadings)
            ..where((row) => row.id.equals(entryId)))
          .getSingle();
      expect(entryRow.deletedAt, isNull);
      expect(
        (await repositories.measurements.listHistoryEntries(
          measurementId: bodyFat.id,
        ))
            .single
            .entry
            .id,
        entryId,
      );

      await repositories.measurements.setMeasurementEnabled(
        bodyFat.id,
        true,
        actor: 'tester',
      );

      expect(
        (await repositories.measurements.listEnabled())
            .map((measurement) => measurement.name),
        <String>['Body Weight', 'Body Fat'],
      );
      final toggleLogs = (await repositories.activityLog.listEntries())
          .where(
            (entry) =>
                entry.entityTable == AppDatabase.metricsTable &&
                entry.entityId == bodyFat.id,
          )
          .toList(growable: false)
          .skip(1)
          .toList(growable: false);
      expect(toggleLogs, hasLength(2));
      expect(toggleLogs.last.beforeImage?['enabled'], isFalse);
      expect(toggleLogs.last.afterImage?['enabled'], isTrue);
    });

    test('reorders measurements and persists sort order after reopen',
        () async {
      final directory = await Directory.systemTemp.createTemp(
        'prn_measurement_reorder_test_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final file = File('${directory.path}/body-tracker.sqlite');
      final fileDatabase = AppDatabase.openFile(file);
      final fileRepositories = TrainingRepositories(fileDatabase);

      await fileRepositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final waistId = await fileRepositories.measurements.createMeasurement(
        const MeasurementDraft(
          name: 'Waist',
          unit: MeasurementUnit.centimeter,
          goalType: MeasurementGoalType.decrease,
          enabled: true,
        ),
        actor: 'tester',
      );
      final measurements = await fileRepositories.measurements.listActive();
      final bodyWeight = measurements.singleWhere(
        (measurement) => measurement.name == 'Body Weight',
      );
      final bodyFat = measurements.singleWhere(
        (measurement) => measurement.name == 'Body Fat',
      );

      await fileRepositories.measurements.reorderMeasurements(
        <String>[waistId, bodyWeight.id, bodyFat.id],
        actor: 'tester',
      );
      await fileDatabase.close();

      final reopened = AppDatabase.openFile(file);
      addTearDown(reopened.close);
      final reopenedRepositories = TrainingRepositories(reopened);
      final reopenedMeasurements =
          await reopenedRepositories.measurements.listEnabled();
      final reopenedTrackSummaries =
          await reopenedRepositories.measurements.listTrackSummaries();

      expect(
        reopenedMeasurements.map((measurement) => measurement.name),
        <String>['Waist', 'Body Weight', 'Body Fat'],
      );
      expect(
        reopenedMeasurements.map((measurement) => measurement.sortOrder),
        <int>[0, 1, 2],
      );
      expect(
        reopenedTrackSummaries.map((summary) => summary.measurement.name),
        <String>['Waist', 'Body Weight', 'Body Fat'],
      );
    });

    test('reset restores default enabled measurements', () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final bodyFat = (await repositories.measurements.listActive())
          .singleWhere((measurement) => measurement.name == 'Body Fat');
      await repositories.measurements.createMeasurement(
        const MeasurementDraft(
          name: 'Waist',
          unit: MeasurementUnit.centimeter,
          goalType: MeasurementGoalType.decrease,
          enabled: true,
        ),
        actor: 'tester',
      );
      await repositories.measurements.setMeasurementEnabled(
        bodyFat.id,
        false,
        actor: 'tester',
      );

      await repositories.measurements.resetDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.pound,
        actor: 'tester',
      );

      final active = await repositories.measurements.listActive();
      expect(
        active.map((measurement) => measurement.name),
        <String>['Body Weight', 'Body Fat'],
      );
      expect(active.first.unit, MeasurementUnit.pound);
      expect(active.first.enabled, isTrue);
      expect(active.last.enabled, isTrue);
      expect(
        active.map((measurement) => measurement.sortOrder),
        <int>[0, 1],
      );
    });

    test('soft-deletes measurements with tombstone through activity log',
        () async {
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final waistId = await repositories.measurements.createMeasurement(
        const MeasurementDraft(
          name: 'Waist',
          unit: MeasurementUnit.centimeter,
          goalType: MeasurementGoalType.decrease,
          enabled: true,
        ),
        actor: 'tester',
      );

      await repositories.measurements.softDeleteMeasurement(
        waistId,
        actor: 'tester',
      );

      expect(
        (await repositories.measurements.listActive())
            .map((measurement) => measurement.name),
        isNot(contains('Waist')),
      );
      final row = await (database.select(database.metrics)
            ..where((row) => row.id.equals(waistId)))
          .getSingle();
      expect(row.deletedAt, isNotNull);

      final deleteLog =
          (await repositories.activityLog.listEntries()).lastWhere(
        (entry) =>
            entry.entityTable == AppDatabase.metricsTable &&
            entry.entityId == waistId,
      );
      expect(deleteLog.actor, 'tester');
      expect(deleteLog.beforeImage?['deleted_at'], isNull);
      expect(deleteLog.afterImage?['deleted_at'], isNotNull);
    });
  });
}

Future<void> _pumpEventQueue({int times = 1}) async {
  for (var i = 0; i < times; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
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
