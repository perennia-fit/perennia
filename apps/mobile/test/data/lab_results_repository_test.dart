import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/labs/lab_result.dart';
import 'package:perennia/domain/labs/lab_test_catalogue.generated.dart';

/// LabResultsRepository against an in-memory SQLite database
/// (docs/designs/lab-results.md, PR 3, V5).
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

  final today = DateTime(2026, 11, 25);

  late AppDatabase database;
  late TrainingRepositories repositories;
  late LabResultsRepository labs;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
    labs = repositories.labResults;
  });

  tearDown(() async {
    await database.close();
  });

  Future<List<MetricRow>> labMetrics(String labTestKey) {
    return (database.select(database.metrics)
          ..where((row) => row.labTestKey.equals(labTestKey)))
        .get();
  }

  Future<List<MetricReadingRow>> allReadings() {
    return database.select(database.metricReadings).get();
  }

  Future<String> createLabMetric(String labTestKey, {int sortOrder = 0}) {
    final labTest = labTestByKey(labTestKey);
    return repositories.metrics.createMetric(
      MetricDraft(
        name: labTest?.name ?? 'Vitamin Q',
        unit: labTest?.unit ?? 'nmol/L',
        valueShape: MetricValueShape.scalar,
        group: MetricGroup.custom,
        enabled: true,
        pinned: false,
        sortOrder: sortOrder,
        labTestKey: labTestKey,
      ),
    );
  }

  group('saveCollection', () {
    test('writes one Batch holding the created Lab Metrics and the Readings',
        () async {
      final batchId = await labs.saveCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '20.0'),
            CollectionDraftRow(labTestKey: 'shbg', value: '40'),
          ],
        ),
        today: today,
      );

      final entries = await repositories.activityLog.listEntries();
      expect(entries.map((entry) => entry.batchId).toSet(), <String>{batchId});
      expect(
        entries.where((e) => e.entityTable == AppDatabase.metricsTable),
        hasLength(2),
      );
      expect(
        entries.where((e) => e.entityTable == AppDatabase.metricReadingsTable),
        hasLength(2),
      );

      final testosterone = (await labMetrics('testosterone_total')).single;
      expect(testosterone.name, 'Testosterone');
      expect(testosterone.unit, 'nmol/L');
      expect(testosterone.metricGroup, MetricGroup.custom.name);
      expect(testosterone.valueShape, MetricValueShape.scalar.name);
      expect(testosterone.enabled, isTrue);
      expect(testosterone.pinned, isFalse);
      final shbg = (await labMetrics('shbg')).single;
      expect(shbg.sortOrder, testosterone.sortOrder + 1);

      final readings = await allReadings();
      expect(readings, hasLength(2));
      for (final reading in readings) {
        expect(reading.provenance, MetricReadingProvenance.manual.name);
        expect(reading.source, 'labEntry');
      }
      final stored = readings.singleWhere((r) => r.metricId == testosterone.id);
      expect(stored.scalarValue, 20.0);
      expect(stored.scalarEntered, '20.0');
      final valueJson = jsonDecode(stored.valueJson) as Map<String, Object?>;
      expect(valueJson['entered'], '20.0');
      expect(valueJson['enteredUnit'], 'nmol/L');
      expect(valueJson['lab'], <String, Object?>{
        'collected': '2026-03-04T08:15',
        'limit': null,
        'printedRange': null,
        'printedFlag': null,
        'reportStatus': 'final',
        'fasting': null,
        'labName': null,
      });
    });

    test(
        'undo archives the Readings and the created Lab Metrics; a later save '
        'creates a live one, and the next reuses it', () async {
      final batchId = await labs.saveCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '20'),
          ],
        ),
        today: today,
      );

      final undo = await repositories.activityLog.undoBatch(batchId);
      expect(undo.hasConflicts, isFalse);
      final archivedMetric = (await labMetrics('testosterone_total')).single;
      expect(archivedMetric.deletedAt, isNotNull);
      expect((await allReadings()).single.deletedAt, isNotNull);
      expect(await labs.watchLabTests().first, isEmpty);

      await labs.saveCollection(
        _draft(
          collectedDate: DateTime(2026, 5, 1),
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '21'),
          ],
        ),
        today: today,
      );
      final afterSecond = await labMetrics('testosterone_total');
      expect(afterSecond, hasLength(2));
      final live = afterSecond.singleWhere((row) => row.deletedAt == null);
      expect(live.id, isNot(archivedMetric.id));

      await labs.saveCollection(
        _draft(
          collectedDate: DateTime(2026, 6, 1),
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '22'),
          ],
        ),
        today: today,
      );
      expect(await labMetrics('testosterone_total'), hasLength(2));
      final liveReadings = (await allReadings())
          .where((row) => row.deletedAt == null)
          .toList(growable: false);
      expect(liveReadings.map((row) => row.metricId).toSet(), {live.id});
    });

    test('a hard reject writes nothing and names only rule codes', () async {
      Object? caught;
      try {
        await labs.saveCollection(
          _draft(
            rows: const <CollectionDraftRow>[
              CollectionDraftRow(labTestKey: 'hs_crp', value: '-1'),
              CollectionDraftRow(labTestKey: 'testosterone_total', value: 'x'),
              CollectionDraftRow(labTestKey: 'shbg', value: '40'),
            ],
          ),
          today: today,
        );
      } on LabResultValidationException catch (error) {
        caught = error;
      }

      expect(caught, isA<LabResultValidationException>());
      final exception = caught! as LabResultValidationException;
      expect(exception.issuesByRow.keys, <int>[0, 1]);
      expect(
        exception.issuesByRow[0]!.map((issue) => issue.rule),
        <String>['lab_value_out_of_bounds'],
      );
      expect(
        exception.issuesByRow[1]!.map((issue) => issue.rule),
        <String>['lab_value_invalid'],
      );
      final text = exception.toString();
      expect(text, contains('lab_value_out_of_bounds'));
      expect(text, isNot(contains('-1')));
      expect(text, isNot(contains('hs-CRP')));
      expect(text, isNot(contains('Testosterone')));

      expect(await database.select(database.metrics).get(), isEmpty);
      expect(await allReadings(), isEmpty);
      expect(await repositories.activityLog.listEntries(), isEmpty);
    });

    test('rejects a collection in the future', () async {
      await expectLater(
        labs.saveCollection(
          _draft(
            collectedDate: DateTime(2026, 11, 27),
            rows: const <CollectionDraftRow>[
              CollectionDraftRow(labTestKey: 'shbg', value: '40'),
            ],
          ),
          today: today,
        ),
        throwsA(
          isA<LabResultValidationException>().having(
            (error) => error.issuesByRow[0]!.map((issue) => issue.rule),
            'rules',
            <String>['lab_collected_future'],
          ),
        ),
      );
    });

    test('rejects the same Lab Test twice, and a row with no known Lab Test',
        () async {
      await expectLater(
        labs.saveCollection(
          _draft(
            rows: const <CollectionDraftRow>[
              CollectionDraftRow(labTestKey: 'shbg', value: '40'),
              CollectionDraftRow(labTestKey: 'shbg', value: '41'),
              CollectionDraftRow(labTestKey: 'shbg', value: '42'),
              CollectionDraftRow(value: '5'),
              CollectionDraftRow(labTestKey: 'vitamin_q', value: '5'),
            ],
          ),
          today: today,
        ),
        throwsA(
          isA<LabResultValidationException>().having(
            (error) => <int, List<String>>{
              for (final MapEntry(:key, :value) in error.issuesByRow.entries)
                key: <String>[
                  for (final issue in value) '${issue.rule}@${issue.field}',
                ],
            },
            'issues',
            <int, List<String>>{
              1: <String>['lab_result_repeated@labTestKey'],
              2: <String>['lab_result_repeated@labTestKey'],
              3: <String>['lab_test_unknown@labTestKey'],
              4: <String>['lab_test_unknown@labTestKey'],
            },
          ),
        ),
      );
      expect(await allReadings(), isEmpty);
    });

    test('an empty collection is an argument error', () async {
      await expectLater(
        labs.saveCollection(
          _draft(rows: const <CollectionDraftRow>[]),
          today: today,
        ),
        throwsArgumentError,
      );
    });

    test('writes to the live Lab Metric with the key, lowest sortOrder first',
        () async {
      final archived = await createLabMetric('testosterone_total');
      await (database.update(database.metrics)
            ..where((row) => row.id.equals(archived)))
          .write(MetricsCompanion(deletedAt: Value(DateTime.utc(2026))));
      final later = await createLabMetric('testosterone_total', sortOrder: 7);
      final first = await createLabMetric('testosterone_total', sortOrder: 5);
      // A hand-made Metric with the Lab Test's name is never matched.
      await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Testosterone',
          unit: 'nmol/L',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.custom,
          enabled: true,
          pinned: false,
          sortOrder: 1,
        ),
      );

      await labs.saveCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '20'),
          ],
        ),
        today: today,
      );

      expect(await labMetrics('testosterone_total'), hasLength(3));
      expect((await allReadings()).single.metricId, first);
      expect(later, isNot(first));
    });

    test('stores a Limit Result with a null scalarValue, and ≤ as <=',
        () async {
      await labs.saveCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(
              labTestKey: 'hs_crp',
              comparator: LabComparator.lt,
              value: '1',
            ),
            CollectionDraftRow(
              labTestKey: 'testosterone_total',
              comparator: LabComparator.le,
              value: '1',
            ),
          ],
        ),
        today: today,
      );

      final crpMetric = (await labMetrics('hs_crp')).single;
      final readings = await allReadings();
      final crp = readings.singleWhere((row) => row.metricId == crpMetric.id);
      expect(crp.scalarValue, isNull);
      expect(crp.scalarEntered, '< 1');
      final crpValue = jsonDecode(crp.valueJson) as Map<String, Object?>;
      expect(crpValue['value'], isNull);
      expect(crpValue['entered'], '< 1');
      expect(
        (crpValue['lab']! as Map<String, Object?>)['limit'],
        <String, Object?>{'comparator': '<', 'bound': 1},
      );

      final le = readings.singleWhere((row) => row.metricId != crpMetric.id);
      expect(le.scalarValue, isNull);
      expect(le.scalarEntered, '<= 1');
      expect(
        (jsonDecode(le.valueJson) as Map<String, Object?>)['entered'],
        '<= 1',
      );

      final records = await labs.watchLabResults('hs_crp').first;
      expect(records.single.entered, '< 1');
      expect(records.single.scalarValue, isNull);
      expect(
        records.single.lab.limit,
        const LabLimit(comparator: LabComparator.lt, bound: 1),
      );
    });

    test('a typed ≤ through createManualReading stores the canonical <= 1',
        () async {
      final metricId = await createLabMetric('hs_crp');
      final readingId = await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '≤ 1',
          source: 'labEntry',
          lab: const LabFields(collected: '2026-03-04'),
          localDateTime: '2026-03-04T12:00:00',
          timezoneOffsetMinutes: 0,
        ),
      );
      final stored = (await allReadings()).singleWhere(
        (row) => row.id == readingId,
      );
      expect(stored.scalarEntered, '<= 1');
      expect(
        (jsonDecode(stored.valueJson) as Map<String, Object?>)['entered'],
        '<= 1',
      );
      expect(stored.atTime?.toUtc(), DateTime.utc(2026, 3, 4, 12));
    });

    test(
        'anchors a date-only collection at T12:00:00 local, and a timed one '
        'at its local time', () async {
      await labs.saveCollection(
        _draft(
          collectedDate: DateTime(2026, 3, 4),
          collectedTime: null,
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'shbg', value: '40'),
          ],
        ),
        today: today,
      );
      await labs.saveCollection(
        _draft(
          collectedDate: DateTime(2026, 7, 9),
          collectedTime: (hour: 8, minute: 5),
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'shbg', value: '41'),
          ],
        ),
        today: today,
      );

      final records = await labs.watchLabResults('shbg').first;
      expect(records.map((r) => r.lab.collected), <String>[
        '2026-07-09T08:05',
        '2026-03-04',
      ]);
      expect(records[1].atTime, DateTime(2026, 3, 4, 12).toUtc());
      expect(records[0].atTime, DateTime(2026, 7, 9, 8, 5).toUtc());
    });

    test('stores the collection fields, fasting false as null', () async {
      await labs.saveCollection(
        CollectionDraft(
          collectedDate: DateTime(2026, 3, 4),
          labName: '  City Pathology  ',
          reportStatus: ReportStatus.interim,
          fasting: true,
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(
              labTestKey: 'shbg',
              value: '40',
              printedRange: ' 15-50 ',
              printedFlag: ' ',
            ),
          ],
        ),
        today: today,
      );
      final record = (await labs.watchLabResults('shbg').first).single;
      expect(record.lab.labName, 'City Pathology');
      expect(record.lab.reportStatus, ReportStatus.interim);
      expect(record.lab.fasting, isTrue);
      expect(record.lab.printedRange, '15-50');
      expect(record.lab.printedFlag, isNull);

      await labs.saveCollection(
        _draft(
          collectedDate: DateTime(2026, 4, 4),
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'shbg', value: '41'),
          ],
        ),
        today: today,
      );
      final latest = (await labs.watchLabResults('shbg').first).first;
      expect(latest.lab.fasting, isNull);
    });
  });

  group('previewCollection', () {
    test('warns lab_result_replaces only for a different saved value',
        () async {
      await labs.saveCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '20'),
            CollectionDraftRow(
              labTestKey: 'hs_crp',
              comparator: LabComparator.lt,
              value: '1',
            ),
          ],
        ),
        today: today,
      );

      final warnings = await labs.previewCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            // Same number, written differently: no warning.
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '20.0'),
            // Same limit: no warning.
            CollectionDraftRow(
              labTestKey: 'hs_crp',
              comparator: LabComparator.lt,
              value: '1.0',
            ),
          ],
        ),
      );
      expect(warnings, isEmpty);

      final different = await labs.previewCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '21'),
            CollectionDraftRow(
              labTestKey: 'hs_crp',
              comparator: LabComparator.le,
              value: '1',
            ),
            CollectionDraftRow(labTestKey: 'shbg', value: '40'),
          ],
        ),
      );
      expect(different.keys, <int>[0, 1]);
      for (final issues in different.values) {
        expect(issues.single.rule, 'lab_result_replaces');
        expect(issues.single.field, 'entered');
      }

      // A number against a limit differs.
      final limitAgainstNumber = await labs.previewCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(
              labTestKey: 'testosterone_total',
              comparator: LabComparator.lt,
              value: '20',
            ),
            CollectionDraftRow(labTestKey: 'hs_crp', value: '1'),
          ],
        ),
      );
      expect(limitAgainstNumber.keys, <int>[0, 1]);

      // Another collection is another identity.
      final otherDay = await labs.previewCollection(
        _draft(
          collectedTime: null,
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '99'),
          ],
        ),
      );
      expect(otherDay, isEmpty);
      expect(await allReadings(), hasLength(2));
    });
  });

  group('reads', () {
    test('an interim then the final shows the final', () async {
      await labs.saveCollection(
        _draft(
          reportStatus: ReportStatus.interim,
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '20'),
          ],
        ),
        today: today,
      );
      await labs.saveCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '21'),
          ],
        ),
        today: today,
      );
      // A later interim never hides the final.
      await labs.saveCollection(
        _draft(
          reportStatus: ReportStatus.interim,
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '22'),
          ],
        ),
        today: today,
      );

      final records = await labs.watchLabResults('testosterone_total').first;
      expect(records, hasLength(1));
      expect(records.single.entered, '21');
      expect(records.single.lab.reportStatus, ReportStatus.final_);
      expect(records.single.identityRowCount, 3);
      final summary = (await labs.watchLabTests().first).single;
      expect(summary.resultCount, 1);
      expect(summary.latest.readingId, records.single.readingId);
    });

    test('two Lab Metrics with one key read as one series', () async {
      final metricA = await createLabMetric('testosterone_total');
      final metricB = await createLabMetric('testosterone_total', sortOrder: 1);
      for (final (metricId, collected, value) in <(String, String, String)>[
        (metricA, '2026-01-10', '18'),
        (metricB, '2026-02-10', '19'),
        // The same collection on both Metrics collapses to one result.
        (metricB, '2026-01-10', '18'),
      ]) {
        await repositories.metrics.createManualReading(
          ManualMetricReadingDraft.scalar(
            metricId: metricId,
            valueEntered: value,
            source: 'labEntry',
            lab: LabFields(collected: collected),
            localDateTime: '${collected}T12:00:00',
            timezoneOffsetMinutes: 0,
          ),
        );
      }

      final records = await labs.watchLabResults('testosterone_total').first;
      expect(records.map((r) => r.lab.collected), <String>[
        '2026-02-10',
        '2026-01-10',
      ]);
      expect(records[1].identityRowCount, 2);
      final summary = (await labs.watchLabTests().first).single;
      expect(summary.resultCount, 2);
      expect(summary.latest.lab.collected, '2026-02-10');
    });

    test("an archived Lab Metric's results still read", () async {
      await labs.saveCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'shbg', value: '40'),
          ],
        ),
        today: today,
      );
      final metric = (await labMetrics('shbg')).single;
      await (database.update(database.metrics)
            ..where((row) => row.id.equals(metric.id)))
          .write(MetricsCompanion(deletedAt: Value(DateTime.utc(2026, 5))));

      expect(await labs.watchLabResults('shbg').first, hasLength(1));
      expect((await labs.watchLabTests().first).single.labTestKey, 'shbg');
    });

    test('excludes a reading whose lab does not decode', () async {
      final metricId = await createLabMetric('shbg');
      await database.into(database.metricReadings).insert(
            MetricReadingsCompanion.insert(
              id: 'reading-old',
              metricId: metricId,
              valueJson: '{"shape":"scalar","unit":"nmol/L","value":40,'
                  '"entered":"40","enteredUnit":"nmol/L"}',
              scalarValue: const Value<double?>(40),
              scalarEntered: const Value<String?>('40'),
              atTime: Value<DateTime?>(DateTime.utc(2026, 1, 1)),
              provenance: MetricReadingProvenance.manual.name,
              source: 'labEntry',
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      expect(await labs.watchLabResults('shbg').first, isEmpty);
      expect(await labs.watchLabTests().first, isEmpty);
    });

    test('watchLabTests lists catalogue order, then Other by name', () async {
      // Saved out of catalogue order: sodium comes after testosterone.
      await labs.saveCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'sodium', value: '140'),
          ],
        ),
        today: today,
      );
      await labs.saveCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '20'),
          ],
        ),
        today: today,
      );
      // A key from a later build, under two Metrics: the lowest sortOrder
      // names it.
      final unknownLater = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Zinc (later name)',
          unit: 'umol/L',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.custom,
          enabled: true,
          pinned: false,
          sortOrder: 9,
          labTestKey: 'zinc_serum',
        ),
      );
      final unknownFirst = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Zinc',
          unit: 'umol/L',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.custom,
          enabled: true,
          pinned: false,
          sortOrder: 8,
          labTestKey: 'zinc_serum',
        ),
      );
      final another = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Aluminium',
          unit: 'umol/L',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.custom,
          enabled: true,
          pinned: false,
          sortOrder: 10,
          labTestKey: 'aluminium_serum',
        ),
      );
      await _insertLabReading(
        database,
        id: 'reading-zinc',
        metricId: unknownLater,
        collected: '2026-02-01',
      );
      await _insertLabReading(
        database,
        id: 'reading-aluminium',
        metricId: another,
        collected: '2026-02-01',
      );

      final summaries = await labs.watchLabTests().first;
      expect(summaries.map((summary) => summary.labTestKey), <String>[
        'testosterone_total',
        'sodium',
        'aluminium_serum',
        'zinc_serum',
      ]);
      expect(summaries[0].labTest?.key, 'testosterone_total');
      expect(summaries[0].panel, 'Sex hormones');
      expect(summaries[0].name, 'Testosterone');
      final zinc = summaries[3];
      expect(zinc.labTest, isNull);
      expect(zinc.panel, isNull);
      expect(zinc.name, 'Zinc');
      expect(zinc.unit, 'umol/L');
      expect(zinc.resultCount, 1);
      expect(unknownFirst, isNot(unknownLater));
    });
  });

  group('archiveResult', () {
    test(
        'archives every row of the identity in one Batch, after reporting the '
        'row count; undo restores them all', () async {
      await labs.saveCollection(
        _draft(
          reportStatus: ReportStatus.interim,
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '20'),
          ],
        ),
        today: today,
      );
      await labs.saveCollection(
        _draft(
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '21'),
          ],
        ),
        today: today,
      );
      // Another collection of the same Lab Test is not touched.
      await labs.saveCollection(
        _draft(
          collectedDate: DateTime(2026, 1, 2),
          rows: const <CollectionDraftRow>[
            CollectionDraftRow(labTestKey: 'testosterone_total', value: '19'),
          ],
        ),
        today: today,
      );

      final before = await labs.watchLabResults('testosterone_total').first;
      expect(before, hasLength(2));
      final result = before.firstWhere(
        (record) => record.lab.collected == '2026-03-04T08:15',
      );
      expect(result.identityRowCount, 2);

      final batchId = await labs.archiveResult(result.readingId);

      final entries = (await repositories.activityLog.listEntries())
          .where((entry) => entry.batchId == batchId)
          .toList(growable: false);
      expect(entries, hasLength(2));
      final after = await labs.watchLabResults('testosterone_total').first;
      expect(after.single.lab.collected, '2026-01-02T08:15');
      expect(
        (await allReadings()).where((row) => row.deletedAt != null),
        hasLength(2),
      );

      final undo = await repositories.activityLog.undoBatch(batchId);
      expect(undo.hasConflicts, isFalse);
      final restored = await labs.watchLabResults('testosterone_total').first;
      expect(restored, hasLength(2));
      expect(
        restored
            .firstWhere((r) => r.lab.collected == '2026-03-04T08:15')
            .identityRowCount,
        2,
      );
    });

    test('archives just the row when its lab does not decode', () async {
      final metricId = await createLabMetric('shbg');
      await _insertLabReading(
        database,
        id: 'reading-a',
        metricId: metricId,
        collected: 'not-a-date',
      );
      await _insertLabReading(
        database,
        id: 'reading-b',
        metricId: metricId,
        collected: 'not-a-date',
      );

      await labs.archiveResult('reading-a');

      final rows = await allReadings();
      expect(
        rows.singleWhere((row) => row.id == 'reading-a').deletedAt,
        isNotNull,
      );
      expect(
          rows.singleWhere((row) => row.id == 'reading-b').deletedAt, isNull);
    });
  });
}

CollectionDraft _draft({
  DateTime? collectedDate,
  ({int hour, int minute})? collectedTime = (hour: 8, minute: 15),
  ReportStatus reportStatus = ReportStatus.final_,
  required List<CollectionDraftRow> rows,
}) {
  return CollectionDraft(
    collectedDate: collectedDate ?? DateTime(2026, 3, 4),
    collectedTime: collectedTime,
    reportStatus: reportStatus,
    rows: rows,
  );
}

Future<void> _insertLabReading(
  AppDatabase database, {
  required String id,
  required String metricId,
  required String collected,
}) {
  return database.into(database.metricReadings).insert(
        MetricReadingsCompanion.insert(
          id: id,
          metricId: metricId,
          valueJson: jsonEncode(<String, Object?>{
            'shape': 'scalar',
            'unit': 'umol/L',
            'value': 12,
            'entered': '12',
            'enteredUnit': 'umol/L',
            'lab': <String, Object?>{
              'collected': collected,
              'limit': null,
              'printedRange': null,
              'printedFlag': null,
              'reportStatus': 'final',
              'fasting': null,
              'labName': null,
            },
          }),
          scalarValue: const Value<double?>(12),
          scalarEntered: const Value<String?>('12'),
          atTime: Value<DateTime?>(DateTime.utc(2026, 2, 1, 12)),
          provenance: MetricReadingProvenance.agent.name,
          source: MetricReadingProvenance.agent.name,
          updatedAt: DateTime.utc(2026, 2, 1, 12),
        ),
      );
}
