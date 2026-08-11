import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/effect_controller.dart';

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

  test(
      'EffectSelection defensively copies outcomes and exposes immutable views',
      () {
    final sourceOutcomes = <EffectOutcomeSelection>[
      EffectOutcomeSelection.metric('metric-weight'),
    ];

    final selection = EffectSelection(outcomes: sourceOutcomes);

    sourceOutcomes.add(const EffectOutcomeSelection.performance());

    expect(
      selection.outcomes,
      <EffectOutcomeSelection>[EffectOutcomeSelection.metric('metric-weight')],
    );
    expect(
      () => selection.outcomes.add(const EffectOutcomeSelection.performance()),
      throwsUnsupportedError,
    );

    final nextOutcomes = <EffectOutcomeSelection>[
      EffectOutcomeSelection.metric('metric-sleep'),
    ];
    final copied = selection.copyWith(outcomes: nextOutcomes);

    nextOutcomes.clear();

    expect(
      copied.outcomes,
      <EffectOutcomeSelection>[EffectOutcomeSelection.metric('metric-sleep')],
    );
    expect(
      () => copied.outcomes.clear(),
      throwsUnsupportedError,
    );
  });

  test(
      'EffectComputation defensively copies collections and exposes immutable views',
      () {
    final window = EffectWindow(
      duringStart: DateTime.utc(2026, 7, 1),
      duringEnd: DateTime.utc(2026, 7, 31),
      now: DateTime.utc(2026, 8, 1),
    );
    final outcome = EffectOutcomeSelection.metric('metric-sleep');
    final results = <EffectOutcomeSelection, OutcomeEffectResult>{
      outcome: const OutcomeEffectResult(
        before: EffectSegmentStats(mean: 7, sampleCount: 1),
        during: EffectSegmentStats(mean: 8, sampleCount: 1),
        after: EffectSegmentStats(mean: null, sampleCount: 0),
      ),
    };
    final sampleList = <EffectSample>[
      EffectSample(at: DateTime.utc(2026, 7, 2), value: 8),
    ];
    final samples = <EffectOutcomeSelection, List<EffectSample>>{
      outcome: sampleList,
    };
    final doses = <DoseRecord>[
      _dose(id: 'dose-1', tookAt: DateTime.utc(2026, 7, 2)),
    ];
    final responseRows = <DoseResponseRow>[
      const DoseResponseRow(
        compoundName: 'Creatine',
        levelLabel: '5 g',
        levelValue: 5,
        doseCount: 1,
        stats: EffectSegmentStats(mean: 8, sampleCount: 1),
      ),
    ];
    final doseResponseTables = <EffectOutcomeSelection, List<DoseResponseRow>>{
      outcome: responseRows,
    };

    final computation = EffectComputation(
      window: window,
      results: results,
      samples: samples,
      doses: doses,
      doseResponseTables: doseResponseTables,
    );

    results.clear();
    sampleList.add(EffectSample(at: DateTime.utc(2026, 7, 3), value: 9));
    samples.clear();
    doses.add(_dose(id: 'dose-2', tookAt: DateTime.utc(2026, 7, 3)));
    responseRows.clear();
    doseResponseTables.clear();

    expect(computation.results.keys, <EffectOutcomeSelection>[outcome]);
    expect(computation.samples[outcome], hasLength(1));
    expect(computation.doses.map((dose) => dose.id), <String>['dose-1']);
    expect(computation.doseResponseTables[outcome], hasLength(1));
    expect(() => computation.results.clear(), throwsUnsupportedError);
    expect(() => computation.samples.clear(), throwsUnsupportedError);
    expect(
      () => computation.samples[outcome]!.add(
        EffectSample(at: DateTime.utc(2026, 7, 4), value: 10),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => computation.doses.add(
        _dose(id: 'dose-3', tookAt: DateTime.utc(2026, 7, 4)),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => computation.doseResponseTables[outcome]!.clear(),
      throwsUnsupportedError,
    );
  });

  test('Effect computation ignores unrelated Protocol plan changes', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final creatineId = await _createCompoundId(repositories, 'Creatine');
    final magnesiumId = await _createCompoundId(repositories, 'Magnesium');
    final watched = await repositories.protocols.createProtocol(
      ProtocolDraft(
        name: 'Lean bulk',
        startDate: DateTime.utc(2026, 7, 1),
        compoundIds: <String>[creatineId],
      ),
    );
    final unrelated = await repositories.protocols.createProtocol(
      ProtocolDraft(
        name: 'Recovery',
        startDate: DateTime.utc(2026, 7, 1),
        compoundIds: <String>[magnesiumId],
      ),
    );
    final watchedProtocol = (await repositories.protocols.listProtocols())
        .singleWhere((protocol) => protocol.id == watched.protocolId);
    final container = ProviderContainer(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
      ],
    );
    addTearDown(container.dispose);

    final computations = <EffectComputation?>[];
    final subscription = container.listen<AsyncValue<EffectComputation?>>(
      effectComputationProvider,
      (_, next) {
        final data = next.asData;
        if (data != null) {
          computations.add(data.value);
        }
      },
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    container.read(effectSelectionControllerProvider.notifier).selectProtocol(
          ProtocolEffectOptionRecord(
            id: watchedProtocol.id,
            name: watchedProtocol.name,
            targetOutcomes: watchedProtocol.targetOutcomes,
          ),
        );
    await _waitFor(
      () => computations.whereType<EffectComputation>().any((computation) =>
          computation.window.duringStart.toUtc() == DateTime.utc(2026, 7, 1)),
    );
    final initialComputationCount =
        computations.whereType<EffectComputation>().length;

    await repositories.protocols.editProtocol(
      unrelated.protocolId,
      ProtocolDraft(
        name: 'Recovery',
        startDate: DateTime.utc(2026, 7, 1),
        compoundIds: <String>[magnesiumId],
        schedulesByCompoundId: <String, ScheduleDraft?>{
          magnesiumId: const ScheduleDraft(
            doseAmountValue: 400,
            doseAmountEntered: '400',
            doseUnit: DoseUnit.milligram,
            frequency: ScheduleFrequency.onceDaily,
            route: DoseRoute.oral,
          ),
        },
      ),
    );
    await pumpEventQueue(times: 5);

    expect(
      computations.whereType<EffectComputation>(),
      hasLength(initialComputationCount),
    );

    await repositories.protocols.editProtocol(
      watched.protocolId,
      ProtocolDraft(
        name: 'Lean bulk',
        startDate: DateTime.utc(2026, 7, 2),
        compoundIds: <String>[creatineId],
      ),
    );

    await _waitFor(
      () => computations.whereType<EffectComputation>().any((computation) =>
          computation.window.duringStart.toUtc() == DateTime.utc(2026, 7, 2)),
    );
  });
}

DoseRecord _dose({required String id, required DateTime tookAt}) {
  return DoseRecord(
    id: id,
    compoundName: 'Creatine',
    amountValue: 5,
    amountEntered: '5',
    unit: DoseUnit.gram,
    route: DoseRoute.oral,
    tookAt: tookAt,
    timezone: 'UTC',
    localDate: ProtocolDayDate.fromDateTime(tookAt),
    provenance: DoseProvenance.manual,
    updatedAt: tookAt,
  );
}

Future<String> _createCompoundId(
  TrainingRepositories repositories,
  String name,
) async {
  final result = await repositories.protocols.createCompound(
    CompoundDraft(
      name: name,
      defaultUnit: DoseUnit.milligram,
      defaultRoute: DoseRoute.oral,
    ),
  );
  return result.compoundId;
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for condition.');
}
