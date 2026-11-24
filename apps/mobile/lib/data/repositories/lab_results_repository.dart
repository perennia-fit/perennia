part of 'training_repositories.dart';

/// Lab Results on the device (docs/designs/lab-results.md): the collection
/// save behind the entry sheet, the reads behind the Lab Results screen and
/// the Lab Test detail, and archiving one result.
///
/// A Lab Result is a scalar Metric Reading on a Lab Metric (a Metric with a
/// non-null `labTestKey`). Every read here joins the readings of **every**
/// Metric with a key and ignores each Lab Metric's own `deletedAt`: identity
/// is per Lab Test, not per Metric row, and an archived Lab Metric (left by the
/// undo of the save that created it) still holds results. The readings are
/// then collapsed with [collapseLabResults], after dropping archived readings,
/// so an interim and its final, or two devices' copies of one collection,
/// read as one result.
class LabResultsRepository {
  LabResultsRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  MetricRepository get _metrics => _repositories.metrics;

  /// Lab Tests with at least one collapsed result, each with its latest.
  ///
  /// Keys in this build's catalogue come first, in catalogue order. Keys the
  /// catalogue lacks (written by a later build) come last, as "Other" ([
  /// LabTestSummary.labTest] and [LabTestSummary.panel] null), named by the
  /// stored name and unit of that key's Metric with the lowest `sortOrder`
  /// (then lowest id), and ordered by that name, then key. A reading whose
  /// `lab` does not decode is left out (see [watchLabResults]), so a key with
  /// only such readings is not listed.
  Stream<List<LabTestSummary>> watchLabTests() {
    return _labRowsQuery(null).watch().map((rows) {
      final byKey = _groupByKey(rows);
      final known = <LabTestSummary>[];
      final other = <LabTestSummary>[];
      final catalogueIndex = <String, int>{
        for (var index = 0; index < labTestCatalogue.length; index++)
          labTestCatalogue[index].key: index,
      };
      for (final MapEntry(key: labTestKey, value: group) in byKey.entries) {
        final results = _collapsedRecords(labTestKey, group.readings);
        if (results.isEmpty) continue;
        final labTest = labTestByKey(labTestKey);
        final namingMetric = group.namingMetric;
        final summary = LabTestSummary(
          labTestKey: labTestKey,
          labTest: labTest,
          name: labTest?.name ?? namingMetric.name,
          unit: labTest?.unit ?? namingMetric.unit,
          panel: labTest?.panel,
          latest: results.first,
          resultCount: results.length,
        );
        (labTest == null ? other : known).add(summary);
      }
      known.sort(
        (a, b) => catalogueIndex[a.labTestKey]!
            .compareTo(catalogueIndex[b.labTestKey]!),
      );
      other.sort((a, b) {
        final byName = a.name.compareTo(b.name);
        if (byName != 0) return byName;
        return a.labTestKey.compareTo(b.labTestKey);
      });
      return List<LabTestSummary>.unmodifiable(<LabTestSummary>[
        ...known,
        ...other,
      ]);
    });
  }

  /// The collapsed results of [labTestKey], newest first.
  ///
  /// A reading whose `lab` does not decode ([decodeLab]; for example one
  /// written by an older build) is its own group in the collapse but is left
  /// out of this list, because a [LabResultRecord] carries [LabFields].
  /// [LabResultRecord.identityRowCount] counts the live rows that share the
  /// result's identity, which is how many rows [archiveResult] archives.
  Stream<List<LabResultRecord>> watchLabResults(String labTestKey) {
    return _labRowsQuery(labTestKey).watch().map((rows) {
      final group = _groupByKey(rows)[labTestKey];
      if (group == null) return const <LabResultRecord>[];
      return List<LabResultRecord>.unmodifiable(
        _collapsedRecords(labTestKey, group.readings),
      );
    });
  }

  /// Validates and saves one collection, returning the Activity Log Batch id.
  ///
  /// Every row gets the reading rules ([validateLabResult]) and the app's
  /// request rules: `lab_test_unknown` (field `labTestKey`) for a row with no
  /// Lab Test or one this build's catalogue lacks, which reuses the Agent
  /// surface's code for the same condition; and `lab_result_repeated` (field
  /// `labTestKey`) on every row after the first that names the same Lab Test.
  /// On any hard error this throws [LabResultValidationException] before a
  /// transaction opens, so nothing is written. Soft warnings never block here;
  /// the sheet shows them from [previewCollection] and [validateLabResult].
  ///
  /// Then one [WriteContext] and one transaction write everything, so the
  /// Batch holds every Lab Metric created and every Lab Result: for each row,
  /// the live Metric with its key (lowest `sortOrder`, then lowest id) is
  /// reused, or one is created (named and united from the catalogue, `custom`,
  /// `scalar`, enabled, not pinned, at the next sort position). A Metric
  /// created earlier in the same save is reused. Each Reading is manual with
  /// source `labEntry`, anchored at `collected` as a local time with the
  /// device's offset at that local time.
  ///
  /// Throws [ArgumentError] when [CollectionDraft.rows] is empty.
  Future<String> saveCollection(
    CollectionDraft draft, {
    required DateTime today,
  }) async {
    if (draft.rows.isEmpty) {
      throw ArgumentError.value(
        draft.rows.length,
        'rows',
        'A collection needs at least one result.',
      );
    }
    final collected = draft.collected;
    final anchor = _collectedAnchor(collected);
    final issuesByRow = <int, List<LabValidationIssue>>{};
    final seenKeys = <String>{};
    for (var index = 0; index < draft.rows.length; index++) {
      final row = draft.rows[index];
      final errors = <LabValidationIssue>[];
      final labTestKey = row.labTestKey;
      final labTest = labTestKey == null ? null : labTestByKey(labTestKey);
      if (labTestKey == null || labTest == null) {
        errors.add(_labTestUnknownIssue);
      } else {
        if (!seenKeys.add(labTestKey)) {
          errors.add(_labResultRepeatedIssue);
        }
        final result = validateLabResult(
          LabResultInput(
            labTestKey: labTestKey,
            entered: _rowEntered(row),
            enteredUnit: labTest.unit,
            lab: _rawLab(draft, row, collected),
            timeAnchor: <String, Object?>{
              'localDateTime': anchor.localDateTime,
              'timezoneOffsetMinutes': anchor.timezoneOffsetMinutes,
            },
          ),
          today: today,
        );
        errors.addAll(result.errors);
      }
      if (errors.isNotEmpty) {
        issuesByRow[index] = List<LabValidationIssue>.unmodifiable(errors);
      }
    }
    if (issuesByRow.isNotEmpty) {
      throw LabResultValidationException(issuesByRow);
    }

    final context = _repositories._writeContexts.create(actor: 'app');
    return _database.transaction(() async {
      final metricsByKey = <String, MetricRow>{};
      for (final row in draft.rows) {
        final labTestKey = row.labTestKey!;
        final metric = metricsByKey[labTestKey] ??=
            await _liveLabMetric(labTestKey) ??
                await _createLabMetric(labTestByKey(labTestKey)!, context);
        await _metrics._insertMetricReading(
          metric,
          ManualMetricReadingDraft.scalar(
            metricId: metric.id,
            valueEntered: _rowEntered(row),
            source: labEntryReadingSource,
            lab: LabFields(
              collected: collected,
              printedRange: row.printedRange,
              printedFlag: row.printedFlag,
              reportStatus: draft.reportStatus,
              fasting: draft.fasting ? true : null,
              labName: draft.labName,
            ),
            localDateTime: anchor.localDateTime,
            timezoneOffsetMinutes: anchor.timezoneOffsetMinutes,
          ),
          context,
        );
      }
      return context.batchId;
    });
  }

  /// The `lab_result_replaces` soft warnings (field `entered`) for [draft]'s
  /// rows, by row index: a row whose identity (Lab Test key and `collected`)
  /// already has a live collapsed result with a different value. Numbers are
  /// compared numerically (`20` equals `20.0`), limits by comparator and bound,
  /// and a number against a limit always differs. Rows with no known Lab Test
  /// or a value that does not parse get nothing here; [saveCollection] rejects
  /// them. Nothing is written.
  Future<Map<int, List<LabValidationIssue>>> previewCollection(
    CollectionDraft draft,
  ) async {
    final collected = draft.collected;
    final warnings = <int, List<LabValidationIssue>>{};
    final savedByKey = <String, List<LabResultRecord>>{};
    for (var index = 0; index < draft.rows.length; index++) {
      final row = draft.rows[index];
      final labTestKey = row.labTestKey;
      if (labTestKey == null || labTestByKey(labTestKey) == null) continue;
      final entered = parseEntered(_rowEntered(row));
      if (entered == null) continue;
      final saved = savedByKey[labTestKey] ??= await _loadResults(labTestKey);
      final existing = saved.where((r) => r.lab.collected == collected);
      if (existing.isEmpty) continue;
      if (_sameValue(
        existing.first,
        entered.comparator,
        double.parse(entered.number),
      )) {
        continue;
      }
      warnings[index] = const <LabValidationIssue>[_labResultReplacesIssue];
    }
    return warnings;
  }

  /// Archives the result [readingId] belongs to, returning the Batch id: every
  /// live reading with its identity across every Metric with its key, or just
  /// that reading when its `lab` does not decode. One [WriteContext] and one
  /// transaction, so undo of the Batch restores every row.
  ///
  /// Throws [StateError] when [readingId] is not a live reading of a Lab
  /// Metric.
  Future<String> archiveResult(String readingId) {
    final context = _repositories._writeContexts.create(actor: 'app');
    return _database.transaction(() async {
      final reading = await _metrics._requireActiveReadingRow(readingId);
      final metric = await _metrics._requireMetricRow(reading.metricId);
      final labTestKey = metric.labTestKey;
      if (labTestKey == null) {
        throw StateError('Metric Reading is not a Lab Result: $readingId.');
      }
      final lab = _decodeReadingLab(reading);
      final toArchive = <MetricReadingRow>[];
      if (lab == null) {
        toArchive.add(reading);
      } else {
        final rows = await _labRowsQuery(labTestKey).get();
        final readings = _groupByKey(rows)[labTestKey]?.readings ??
            const <MetricReadingRow>[];
        for (final candidate in readings) {
          if (_decodeReadingLab(candidate)?.collected == lab.collected) {
            toArchive.add(candidate);
          }
        }
      }
      for (final row in toArchive) {
        await _metrics._archiveReadingRow(row, context);
      }
      return context.batchId;
    });
  }

  /// Every Lab Metric (whatever its own `deletedAt`), with [labTestKey]'s
  /// only when given, joined to its live readings. A Metric with no live
  /// reading still appears once, with a null reading, so its name can label
  /// an "Other" key.
  JoinedSelectStatement<HasResultSet, dynamic> _labRowsQuery(
    String? labTestKey,
  ) {
    final metrics = _database.metrics;
    final readings = _database.metricReadings;
    final query = _database.select(metrics).join([
      leftOuterJoin(
        readings,
        readings.metricId.equalsExp(metrics.id) & readings.deletedAt.isNull(),
      ),
    ])
      ..where(
        labTestKey == null
            ? metrics.labTestKey.isNotNull()
            : metrics.labTestKey.equals(labTestKey),
      );
    return query;
  }

  Map<String, _LabKeyRows> _groupByKey(List<TypedResult> rows) {
    final byKey = <String, _LabKeyRows>{};
    for (final row in rows) {
      final metric = row.readTable(_database.metrics);
      final group = byKey.putIfAbsent(
        metric.labTestKey!,
        () => _LabKeyRows(metric),
      );
      group.offerNamingMetric(metric);
      final reading = row.readTableOrNull(_database.metricReadings);
      if (reading != null) group.readings.add(reading);
    }
    return byKey;
  }

  Future<List<LabResultRecord>> _loadResults(String labTestKey) async {
    final rows = await _labRowsQuery(labTestKey).get();
    final group = _groupByKey(rows)[labTestKey];
    if (group == null) return const <LabResultRecord>[];
    return _collapsedRecords(labTestKey, group.readings);
  }

  /// [readings] (live, every Metric with [labTestKey]) collapsed newest first,
  /// keeping only the results whose `lab` decodes.
  List<LabResultRecord> _collapsedRecords(
    String labTestKey,
    List<MetricReadingRow> readings,
  ) {
    final rowsById = <String, MetricReadingRow>{};
    final labsById = <String, LabFields?>{};
    final identityCounts = <String, int>{};
    final refs = <LabReadingRef>[];
    for (final reading in readings) {
      final lab = _decodeReadingLab(reading);
      rowsById[reading.id] = reading;
      labsById[reading.id] = lab;
      if (lab != null) {
        identityCounts.update(
          lab.collected,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      refs.add(
        LabReadingRef(
          id: reading.id,
          labTestKey: labTestKey,
          lab: lab,
          // A Lab Result is always anchored at an instant; the fallbacks only
          // keep a malformed row from failing the read.
          atTime:
              (reading.atTime ?? reading.windowStartedAt ?? reading.updatedAt)
                  .toUtc(),
          updatedAt: reading.updatedAt.toUtc(),
          deletedAt: reading.deletedAt,
        ),
      );
    }
    final records = <LabResultRecord>[];
    for (final kept in collapseLabResults(refs)) {
      final lab = labsById[kept.id];
      if (lab == null) continue;
      final reading = rowsById[kept.id]!;
      final value = _decodeValueJson(reading.valueJson);
      final entered = value['entered'];
      final enteredUnit = value['enteredUnit'];
      records.add(
        LabResultRecord(
          readingId: reading.id,
          metricId: reading.metricId,
          labTestKey: labTestKey,
          entered: entered is String ? entered : (reading.scalarEntered ?? ''),
          enteredUnit: enteredUnit is String ? enteredUnit : '',
          scalarValue: reading.scalarValue,
          lab: lab,
          atTime: reading.atTime?.toUtc(),
          updatedAt: reading.updatedAt.toUtc(),
          identityRowCount: identityCounts[lab.collected] ?? 1,
        ),
      );
    }
    return records;
  }

  Future<MetricRow?> _liveLabMetric(String labTestKey) {
    return (_database.select(_database.metrics)
          ..where(
            (row) => row.labTestKey.equals(labTestKey) & row.deletedAt.isNull(),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.sortOrder),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<MetricRow> _createLabMetric(
    LabTest labTest,
    WriteContext context,
  ) async {
    final activeRows = await _metrics._activeMetricQuery().get();
    final id = await _metrics._createMetric(
      MetricDraft(
        name: labTest.name,
        unit: labTest.unit,
        valueShape: MetricValueShape.scalar,
        group: MetricGroup.custom,
        enabled: true,
        pinned: false,
        sortOrder: _nextPosition(activeRows, (row) => row.sortOrder),
        labTestKey: labTest.key,
      ),
      context,
    );
    return _metrics._requireMetricRow(id);
  }
}

/// The source of a Lab Result entered by hand (docs/designs/lab-results.md,
/// Storage); an Agent's results carry source `agent`.
const String labEntryReadingSource = 'labEntry';

const LabValidationIssue _labTestUnknownIssue = LabValidationIssue(
  rule: 'lab_test_unknown',
  field: 'labTestKey',
  message: 'Choose a Lab Test.',
);

const LabValidationIssue _labResultRepeatedIssue = LabValidationIssue(
  rule: 'lab_result_repeated',
  field: 'labTestKey',
  message: 'This Lab Test is already in this collection.',
);

const LabValidationIssue _labResultReplacesIssue = LabValidationIssue(
  rule: 'lab_result_replaces',
  field: 'entered',
  message: 'This replaces a saved result for the same collection.',
);

/// A row's canonical `entered`: the comparator (ASCII) and the trimmed value.
String _rowEntered(CollectionDraftRow row) =>
    formatEntered(row.comparator, row.value.trim());

/// The raw `lab` object the reading rules judge, as the save will send it.
Map<String, Object?> _rawLab(
  CollectionDraft draft,
  CollectionDraftRow row,
  String collected,
) {
  return <String, Object?>{
    'collected': collected,
    'printedRange': row.printedRange,
    'printedFlag': row.printedFlag,
    'reportStatus': draft.reportStatus.wire,
    'fasting': draft.fasting ? true : null,
    'labName': draft.labName,
  };
}

/// The time anchor for [collected]: its local date-time (a date only reads as
/// `T12:00:00`) and the offset this device's time zone has at that local
/// date and time, so an old collection across a daylight-saving change gets
/// its own offset. A time in a gap or overlap takes the offset Dart returns.
({String localDateTime, int timezoneOffsetMinutes}) _collectedAnchor(
  String collected,
) {
  final localDateTime = collectedLocalDateTime(collected);
  final local = DateTime.parse(localDateTime);
  return (
    localDateTime: localDateTime,
    timezoneOffsetMinutes: local.timeZoneOffset.inMinutes,
  );
}

LabFields? _decodeReadingLab(MetricReadingRow reading) =>
    decodeLab(_decodeValueJson(reading.valueJson)['lab']);

Map<String, Object?> _decodeValueJson(String valueJson) {
  try {
    final decoded = jsonDecode(valueJson);
    return decoded is Map<String, Object?>
        ? decoded
        : const <String, Object?>{};
  } on FormatException {
    return const <String, Object?>{};
  }
}

/// Whether [saved] states the same value as a row entering [comparator] and
/// [number]: numbers compared numerically, limits by comparator and bound.
bool _sameValue(
  LabResultRecord saved,
  LabComparator? comparator,
  double number,
) {
  final limit = saved.lab.limit;
  if (limit != null) {
    return comparator == limit.comparator && number == limit.bound;
  }
  final value = saved.scalarValue;
  return comparator == null && value != null && number == value;
}

/// One Lab Test key's rows: its live readings, and the Metric whose stored
/// name and unit label the key when the catalogue lacks it.
class _LabKeyRows {
  _LabKeyRows(this.namingMetric);

  MetricRow namingMetric;
  final List<MetricReadingRow> readings = <MetricReadingRow>[];

  /// Keeps the Metric with the lowest `sortOrder`, then the lowest id.
  void offerNamingMetric(MetricRow metric) {
    final bySort = metric.sortOrder.compareTo(namingMetric.sortOrder);
    if (bySort < 0 ||
        (bySort == 0 && metric.id.compareTo(namingMetric.id) < 0)) {
      namingMetric = metric;
    }
  }
}

/// The entry sheet's state: one collection (one blood draw) and its result
/// rows (docs/designs/lab-results.md, "Collection-based manual entry").
///
/// [collectedTime] is a `({int hour, int minute})` record rather than
/// Flutter's `TimeOfDay`, because the data layer does not import Flutter's
/// widgets library; the sheet converts at its edge.
class CollectionDraft {
  CollectionDraft({
    required this.collectedDate,
    this.collectedTime,
    this.labName,
    this.reportStatus = ReportStatus.final_,
    this.fasting = false,
    required Iterable<CollectionDraftRow> rows,
  }) : rows = List<CollectionDraftRow>.unmodifiable(rows);

  /// Only the date part is read.
  final DateTime collectedDate;

  /// The printed collection time, or null when only a date was printed.
  final ({int hour, int minute})? collectedTime;

  final String? labName;
  final ReportStatus reportStatus;

  /// False is stored as null.
  final bool fasting;

  final List<CollectionDraftRow> rows;

  /// `YYYY-MM-DD`, or `YYYY-MM-DDTHH:mm` when [collectedTime] is set.
  String get collected {
    final date = '${collectedDate.year.toString().padLeft(4, '0')}-'
        '${collectedDate.month.toString().padLeft(2, '0')}-'
        '${collectedDate.day.toString().padLeft(2, '0')}';
    final time = collectedTime;
    if (time == null) return date;
    return '${date}T${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}

/// One result row of a [CollectionDraft].
class CollectionDraftRow {
  const CollectionDraftRow({
    this.labTestKey,
    this.comparator,
    this.value = '',
    this.printedRange,
    this.printedFlag,
  });

  /// Null until a Lab Test is chosen.
  final String? labTestKey;

  /// Set for a Limit Result; `≤` and `≥` are [LabComparator.le] and
  /// [LabComparator.ge], stored as `<=` and `>=`.
  final LabComparator? comparator;

  /// The value as typed.
  final String value;

  final String? printedRange;
  final String? printedFlag;
}

/// One Lab Test with results, for the Lab Results screen.
class LabTestSummary {
  const LabTestSummary({
    required this.labTestKey,
    required this.labTest,
    required this.name,
    required this.unit,
    required this.panel,
    required this.latest,
    required this.resultCount,
  });

  final String labTestKey;

  /// Null for a key this build's catalogue lacks ("Other").
  final LabTest? labTest;

  /// The catalogue name, or for "Other" the stored Metric name.
  final String name;

  /// The catalogue unit, or for "Other" the stored Metric unit.
  final String unit;

  /// Null for "Other".
  final String? panel;

  /// The newest collapsed result.
  final LabResultRecord latest;

  /// How many collapsed results the key has.
  final int resultCount;
}

/// One collapsed Lab Result.
class LabResultRecord {
  const LabResultRecord({
    required this.readingId,
    required this.metricId,
    required this.labTestKey,
    required this.entered,
    required this.enteredUnit,
    required this.scalarValue,
    required this.lab,
    required this.atTime,
    required this.updatedAt,
    required this.identityRowCount,
  });

  /// The kept row of the result's identity group.
  final String readingId;
  final String metricId;
  final String labTestKey;

  /// As entered, with an ASCII comparator for a Limit Result (`< 1`).
  final String entered;
  final String enteredUnit;

  /// Null for a Limit Result.
  final double? scalarValue;
  final LabFields lab;

  /// The stored instant; the display uses [LabFields.collected] instead.
  final DateTime? atTime;
  final DateTime updatedAt;

  /// How many live rows share this result's identity (Lab Test key and
  /// `collected`), across every Metric with the key.
  final int identityRowCount;
}

/// A collection that failed a hard rule. [issuesByRow] maps a row index of
/// the [CollectionDraft] to its errors.
class LabResultValidationException implements Exception {
  LabResultValidationException(Map<int, List<LabValidationIssue>> issuesByRow)
      : issuesByRow = Map<int, List<LabValidationIssue>>.unmodifiable(
          issuesByRow,
        );

  final Map<int, List<LabValidationIssue>> issuesByRow;

  /// Rule codes only: never a value or a Lab Test name, so a logged exception
  /// reveals nothing.
  @override
  String toString() {
    final rules = <String>{
      for (final issues in issuesByRow.values)
        for (final issue in issues) issue.rule,
    };
    return 'LabResultValidationException: ${rules.join(', ')}';
  }
}
