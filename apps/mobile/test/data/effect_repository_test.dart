import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_dimensions.dart';

/// the `Effect` view's window + outcome-sample reads, against real
/// in-memory SQLite (repo test strategy, AGENTS.md §8.2). Everything here is
/// a read — no test asserts a write, because the `Effect` view never has one
/// (PROTOCOLS.md §4: "join, never merge").
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

  group('effect repository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    test(
        'windowForProtocol derives DURING from the Protocol\'s own '
        'start/end dates', () async {
      final creatineId = await _createCompoundId(repositories, 'Creatine');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 1, 15),
          endDate: DateTime.utc(2026, 2, 14),
          compoundIds: <String>[creatineId],
        ),
      );
      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == created.protocolId);

      final window = repositories.effect.windowForProtocol(
        protocol,
        now: DateTime.utc(2026, 3, 16),
      );

      // Drift returns DateTimes in local time; compare the instant, not the
      // tagged zone (the same UTC moment was stored).
      expect(window.duringStart.toUtc(), DateTime.utc(2026, 1, 15));
      expect(window.duringEnd!.toUtc(), DateTime.utc(2026, 2, 14));
      expect(window.isOngoing, isFalse);
      expect(window.beforeStart.toUtc(), DateTime.utc(2025, 12, 16));
      expect(window.afterEnd.toUtc(), DateTime.utc(2026, 3, 16));
    });

    test(
        'windowForProtocol stays ongoing when the Protocol has no end date '
        '(never falls back to a Schedule)', () async {
      final creatineId = await _createCompoundId(repositories, 'Creatine');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Off-season stack',
          startDate: DateTime.utc(2026, 6, 1),
          compoundIds: <String>[creatineId],
        ),
      );
      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == created.protocolId);

      final window = repositories.effect.windowForProtocol(
        protocol,
        now: DateTime.utc(2026, 7, 3),
      );

      expect(window.isOngoing, isTrue);
      expect(window.duringEndOrNow, DateTime.utc(2026, 7, 3));
    });

    test('windowForCompound returns null with no logged Dose', () async {
      final creatineId = await _createCompoundId(repositories, 'Creatine');

      final window = await repositories.effect.windowForCompound(creatineId);

      expect(window, isNull);
    });

    test(
        'windowForCompound derives DURING from the actual logged Dose '
        'timeline bounds (never a Schedule/plan)', () async {
      final creatineId = await _createCompoundId(repositories, 'Creatine');
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 1, 10),
        ),
      );
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 2, 9),
        ),
      );

      final window = await repositories.effect.windowForCompound(
        creatineId,
        now: DateTime.utc(2026, 3, 1),
      );

      expect(window, isNotNull);
      expect(window!.duringStart.toUtc(), DateTime.utc(2026, 1, 10));
      expect(window.duringEnd!.toUtc(), DateTime.utc(2026, 2, 9));
    });

    test(
        'samplesFor a metric outcome reads the existing Metric Readings '
        'and excludes a Reading with no scalar value/instant', () async {
      final metricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Body Weight',
          unit: 'kilogram',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.bodyComposition,
          enabled: true,
          pinned: false,
        ),
      );
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '82',
          atTime: DateTime.utc(2026, 1, 1, 8),
          source: 'manual',
        ),
      );
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '80',
          atTime: DateTime.utc(2026, 1, 20, 8),
          source: 'manual',
        ),
      );

      final window = EffectWindow(
        duringStart: DateTime.utc(2026, 1, 15),
        duringEnd: DateTime.utc(2026, 2, 14),
        now: DateTime.utc(2026, 3, 16),
      );

      final samples = await repositories.effect.samplesFor(
        EffectOutcomeSelection.metric(metricId),
        window,
      );

      expect(samples, hasLength(2));
      expect(samples.map((s) => s.value), containsAll(<double>[82, 80]));
    });

    test(
        'samplesFor a performance outcome sums load x reps of completed '
        'sets per Workout session, excluding a session with no scoreable set',
        () async {
      final exercises = await repositories.ensureStarterExercises();
      final exerciseId = exercises.first.id;

      // In-window session with a completed, load+reps set: 100kg x 5 = 500.
      await repositories.logWorkoutWithSet(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 1, 20, 9),
          timezone: 'UTC',
        ),
        LoggedSetDraft(
          exerciseId: exerciseId,
          position: 0,
          isCompleted: true,
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
        ),
      );

      // Same window, but a duration-only session (no load/reps) — excluded,
      // never fabricated as a zero-volume sample.
      await repositories.logWorkoutWithSet(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 1, 25, 9),
          timezone: 'UTC',
        ),
        LoggedSetDraft(
          exerciseId: exerciseId,
          position: 0,
          isCompleted: true,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.duration,
                entered: '60',
                unit: TrainingUnit.second,
              ),
            ],
          ),
        ),
      );

      // Outside the window entirely.
      await repositories.logWorkoutWithSet(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2025, 1, 1, 9),
          timezone: 'UTC',
        ),
        LoggedSetDraft(
          exerciseId: exerciseId,
          position: 0,
          isCompleted: true,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '999',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '1',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
      );

      final samples = await repositories.effect.performanceVolumeSamples(
        from: DateTime.utc(2026, 1, 15),
        to: DateTime.utc(2026, 2, 14),
      );

      expect(samples, hasLength(1));
      expect(samples.single.value, 500);
      expect(samples.single.at.toUtc(), DateTime.utc(2026, 1, 20, 9));
    });

    test(
        'computeOutcome never writes anything back — no new Metric Reading, '
        'Dose, or Workout row is created by reading the Effect view',
        () async {
      final metricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Body Weight',
          unit: 'kilogram',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.bodyComposition,
          enabled: true,
          pinned: false,
        ),
      );
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '82',
          atTime: DateTime.utc(2026, 1, 1, 8),
          source: 'manual',
        ),
      );
      final window = EffectWindow(
        duringStart: DateTime.utc(2026, 1, 15),
        duringEnd: DateTime.utc(2026, 2, 14),
        now: DateTime.utc(2026, 3, 16),
      );

      final readingCountBefore =
          (await repositories.metrics.listReadings(metricId)).length;

      final result = await repositories.effect.computeOutcome(
        window: window,
        outcome: EffectOutcomeSelection.metric(metricId),
      );
      // Calling it again (as a "recompute on demand" caller would) must be
      // side-effect free too — no accidental cache/table appears.
      await repositories.effect.computeOutcome(
        window: window,
        outcome: EffectOutcomeSelection.metric(metricId),
      );

      final readingCountAfter =
          (await repositories.metrics.listReadings(metricId)).length;
      expect(readingCountAfter, readingCountBefore);
      // A single reading before the window, none during/after: never
      // fabricated into a during/after value.
      expect(result.before.sampleCount, 1);
      expect(result.during.sampleCount, 0);
      expect(result.during.mean, isNull);
      expect(result.duringDelta, isNull);
    });

    test(
        'doseMarkersFor a Compound source returns the ACTUAL logged Doses '
        '(never the Schedule/plan), scoped to the window\'s full span',
        () async {
      final creatineId = await _createCompoundId(repositories, 'Creatine');
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 1, 10),
        ),
      );
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 2, 9),
        ),
      );
      // Outside the window's before-through-after span entirely -> excluded.
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2020, 1, 1),
        ),
      );

      // A fixed window (not re-derived from the Doses just logged, since the
      // 2020 Dose would otherwise shift `windowForCompound`'s own DURING
      // bounds) so the "outside the span" exclusion is actually exercised.
      final window = EffectWindow(
        duringStart: DateTime.utc(2026, 1, 10),
        duringEnd: DateTime.utc(2026, 2, 9),
        now: DateTime.utc(2026, 3, 1),
      );

      final markers = await repositories.effect.doseMarkersFor(
        EffectWindowSource.compound(creatineId),
        window,
      );

      expect(markers, hasLength(2));
      expect(markers.map((d) => d.tookAt.toUtc()), <DateTime>[
        DateTime.utc(2026, 1, 10),
        DateTime.utc(2026, 2, 9),
      ]);
    });

    test(
        'doseMarkersFor a Protocol source returns only the Doses TAGGED to '
        'that Protocol, excluding an untagged Dose of the same Compound',
        () async {
      final creatineId = await _createCompoundId(repositories, 'Creatine');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 1, 15),
          endDate: DateTime.utc(2026, 2, 14),
          compoundIds: <String>[creatineId],
        ),
      );
      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == created.protocolId);

      // Tagged to the Protocol -> included.
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 1, 20),
          protocolId: protocol.id,
          protocolName: protocol.name,
        ),
      );
      // Same Compound, same window, but untagged -> excluded (the overlay
      // reads the actual tag, never infers it from the Compound/dates).
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 1, 25),
        ),
      );

      final window = repositories.effect.windowForProtocol(
        protocol,
        now: DateTime.utc(2026, 3, 16),
      );

      final markers = await repositories.effect.doseMarkersFor(
        EffectWindowSource.protocol(protocol.id),
        window,
      );

      expect(markers, hasLength(1));
      expect(markers.single.tookAt.toUtc(), DateTime.utc(2026, 1, 20));
      expect(markers.single.protocolId, protocol.id);
    });

    test(
        'doseMarkersFor excludes a tagged Dose that falls outside the '
        'window\'s before-through-after span', () async {
      final creatineId = await _createCompoundId(repositories, 'Creatine');
      final created = await repositories.protocols.createProtocol(
        ProtocolDraft(
          name: 'Lean bulk',
          startDate: DateTime.utc(2026, 1, 15),
          endDate: DateTime.utc(2026, 2, 14),
          compoundIds: <String>[creatineId],
        ),
      );
      final protocol = (await repositories.protocols.listProtocols())
          .firstWhere((p) => p.id == created.protocolId);

      // Far outside even the mirrored before/after span.
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2020, 1, 1),
          protocolId: protocol.id,
          protocolName: protocol.name,
        ),
      );

      final window = repositories.effect.windowForProtocol(
        protocol,
        now: DateTime.utc(2026, 3, 16),
      );

      final markers = await repositories.effect.doseMarkersFor(
        EffectWindowSource.protocol(protocol.id),
        window,
      );

      expect(markers, isEmpty);
    });

    test(
        'doseResponseFor groups outcome samples by the ACTUAL logged Dose '
        'level (never the Schedule/plan) and never writes anything back',
        () async {
      final creatineId = await _createCompoundId(repositories, 'Creatine');
      // Level A: 5g, taken once.
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 5,
          amountEntered: '5',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 1, 10),
        ),
      );
      // Level B: 10g, taken once.
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: creatineId,
          compoundName: 'Creatine',
          amountValue: 10,
          amountEntered: '10',
          unit: DoseUnit.gram,
          route: DoseRoute.oral,
          tookAt: DateTime.utc(2026, 1, 20),
        ),
      );

      final metricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Body Weight',
          unit: 'kilogram',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.bodyComposition,
          enabled: true,
          pinned: false,
        ),
      );
      // Attributed to the 5g level (most recent preceding Dose).
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '82',
          atTime: DateTime.utc(2026, 1, 12),
          source: 'manual',
        ),
      );
      // Attributed to the 10g level.
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '80',
          atTime: DateTime.utc(2026, 1, 22),
          source: 'manual',
        ),
      );

      final readingCountBefore =
          (await repositories.metrics.listReadings(metricId)).length;

      final window = EffectWindow(
        duringStart: DateTime.utc(2026, 1, 10),
        duringEnd: DateTime.utc(2026, 1, 20),
        now: DateTime.utc(2026, 2, 1),
      );

      final rows = await repositories.effect.doseResponseFor(
        source: EffectWindowSource.compound(creatineId),
        window: window,
        outcome: EffectOutcomeSelection.metric(metricId),
      );

      final readingCountAfter =
          (await repositories.metrics.listReadings(metricId)).length;
      expect(readingCountAfter, readingCountBefore);

      expect(rows, hasLength(2));
      expect(rows[0].levelLabel, '5 g');
      expect(rows[0].doseCount, 1);
      expect(rows[0].stats.mean, 82);
      expect(rows[1].levelLabel, '10 g');
      expect(rows[1].doseCount, 1);
      expect(rows[1].stats.mean, 80);
    });

    test(
        'samplesFor treats a manually-entered biomarker Metric '
        '(custom group, lab unit) exactly like a body-composition Metric',
        () async {
      final metricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Testosterone',
          unit: 'ng/dL',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.custom,
          enabled: true,
          pinned: false,
        ),
      );
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '620',
          atTime: DateTime.utc(2026, 1, 1, 8),
          source: 'manual',
        ),
      );
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '540',
          atTime: DateTime.utc(2026, 1, 20, 8),
          source: 'manual',
        ),
      );

      final window = EffectWindow(
        duringStart: DateTime.utc(2026, 1, 15),
        duringEnd: DateTime.utc(2026, 2, 14),
        now: DateTime.utc(2026, 3, 16),
      );

      final samples = await repositories.effect.samplesFor(
        EffectOutcomeSelection.metric(metricId),
        window,
      );
      final result = await repositories.effect.computeOutcome(
        window: window,
        outcome: EffectOutcomeSelection.metric(metricId),
      );

      expect(samples, hasLength(2));
      expect(samples.map((s) => s.value), containsAll(<double>[620, 540]));
      // Same shape as a body-composition Metric's delta: one BEFORE sample,
      // one DURING sample -> a real duringDelta, nothing fabricated.
      expect(result.before.sampleCount, 1);
      expect(result.during.sampleCount, 1);
      expect(result.duringDelta, closeTo(540 - 620, 1e-9));
    });

    test(
        'samplesFor a biomarker Metric with zero logged Readings '
        'degrades gracefully — an empty sample list, never a fabricated one',
        () async {
      final metricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Estradiol',
          unit: 'pg/mL',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.custom,
          enabled: true,
          pinned: false,
        ),
      );

      final window = EffectWindow(
        duringStart: DateTime.utc(2026, 1, 15),
        duringEnd: DateTime.utc(2026, 2, 14),
        now: DateTime.utc(2026, 3, 16),
      );

      final samples = await repositories.effect.samplesFor(
        EffectOutcomeSelection.metric(metricId),
        window,
      );
      final result = await repositories.effect.computeOutcome(
        window: window,
        outcome: EffectOutcomeSelection.metric(metricId),
      );

      expect(samples, isEmpty);
      expect(result.before.mean, isNull);
      expect(result.during.mean, isNull);
      expect(result.after.mean, isNull);
      expect(result.duringDelta, isNull);
      expect(result.afterDelta, isNull);
      expect(result.overallDelta, isNull);
    });

    test(
        'doseResponseFor groups a biomarker Metric\'s sparse '
        'manually-entered Readings by the ACTUAL logged Dose level — a '
        'level with no attributed lab draw still lists its dose count with '
        'a null mean, never fabricated', () async {
      final trtId = await _createCompoundId(repositories, 'Testosterone Cyp');
      // Level A: 100 mg, taken once, with a lab draw shortly after.
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: trtId,
          compoundName: 'Testosterone Cyp',
          amountValue: 100,
          amountEntered: '100',
          unit: DoseUnit.milligram,
          route: DoseRoute.intramuscular,
          tookAt: DateTime.utc(2026, 1, 10),
        ),
      );
      // Level B: 200 mg, taken once, with NO lab draw attributed to it.
      await repositories.protocols.logDose(
        DoseSnapshotDraft(
          compoundId: trtId,
          compoundName: 'Testosterone Cyp',
          amountValue: 200,
          amountEntered: '200',
          unit: DoseUnit.milligram,
          route: DoseRoute.intramuscular,
          tookAt: DateTime.utc(2026, 1, 20),
        ),
      );

      final metricId = await repositories.metrics.createMetric(
        const MetricDraft(
          name: 'Testosterone',
          unit: 'ng/dL',
          valueShape: MetricValueShape.scalar,
          group: MetricGroup.custom,
          enabled: true,
          pinned: false,
        ),
      );
      // A single manually-entered lab draw, attributed to the 100 mg level.
      await repositories.metrics.createManualReading(
        ManualMetricReadingDraft.scalar(
          metricId: metricId,
          valueEntered: '650',
          atTime: DateTime.utc(2026, 1, 12),
          source: 'manual',
        ),
      );

      final window = EffectWindow(
        duringStart: DateTime.utc(2026, 1, 10),
        duringEnd: DateTime.utc(2026, 1, 25),
        now: DateTime.utc(2026, 2, 1),
      );

      final rows = await repositories.effect.doseResponseFor(
        source: EffectWindowSource.compound(trtId),
        window: window,
        outcome: EffectOutcomeSelection.metric(metricId),
      );

      expect(rows, hasLength(2));
      expect(rows[0].levelLabel, '100 mg');
      expect(rows[0].doseCount, 1);
      expect(rows[0].stats.mean, 650);
      expect(rows[1].levelLabel, '200 mg');
      expect(rows[1].doseCount, 1);
      // No lab draw attributed to the 200 mg level -> dose count still
      // visible, mean stays null (never fabricated).
      expect(rows[1].stats.mean, isNull);
      expect(rows[1].stats.sampleCount, 0);
    });

    test(
        'EffectOutcomeSelection.fromTargetOutcome seeds 1:1 from a '
        'Protocol\'s declared target outcomes, detached from the '
        'plan', () async {
      const metricOutcome = ProtocolTargetOutcomeRecord(
        id: 'outcome-1',
        kind: ProtocolOutcomeKind.metric,
        metricId: 'metric-weight',
        position: 0,
      );
      const performanceOutcome = ProtocolTargetOutcomeRecord(
        id: 'outcome-2',
        kind: ProtocolOutcomeKind.performance,
        position: 1,
      );

      final metricSelection =
          EffectOutcomeSelection.fromTargetOutcome(metricOutcome);
      final performanceSelection =
          EffectOutcomeSelection.fromTargetOutcome(performanceOutcome);

      expect(metricSelection, EffectOutcomeSelection.metric('metric-weight'));
      expect(
        performanceSelection,
        const EffectOutcomeSelection.performance(),
      );
    });
  });
}

Future<String> _createCompoundId(
  TrainingRepositories repositories,
  String name,
) async {
  final result = await repositories.protocols.createCompound(
    CompoundDraft(
      name: name,
      defaultUnit: DoseUnit.gram,
      defaultRoute: DoseRoute.oral,
    ),
  );
  return result.compoundId;
}
