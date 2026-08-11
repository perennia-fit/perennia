import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../models/measurement_progress_graph.dart';
import '../../settings/repositories/settings_repository.dart';
import 'measurement_delta.dart';

final measurementRepositoryProvider = Provider<MeasurementRepository>((ref) {
  return ref.watch(trainingRepositoriesProvider).measurements;
});

final bodyTrackerControllerProvider =
    StreamNotifierProvider<BodyTrackerController, BodyTrackerState>(
  BodyTrackerController.new,
);

final bodyTrackerHistoryProvider =
    StreamProvider.autoDispose.family<BodyTrackerHistoryState, String?>(
  (ref, measurementId) {
    final repository = ref.watch(measurementRepositoryProvider);
    return _watchBodyTrackerHistory(repository, measurementId);
  },
);

final bodyTrackerManagementProvider =
    StreamProvider.autoDispose<BodyTrackerManagementState>((ref) async* {
  final repository = ref.watch(measurementRepositoryProvider);
  await for (final measurements in repository.watchActive()) {
    yield BodyTrackerManagementState(measurements: measurements);
  }
});

final bodyTrackerGraphProvider =
    StreamProvider.autoDispose.family<BodyTrackerGraphState?, String>(
  (ref, measurementId) {
    final repository = ref.watch(measurementRepositoryProvider);
    return _watchBodyTrackerGraph(repository, measurementId);
  },
);

class BodyTrackerController extends StreamNotifier<BodyTrackerState> {
  @override
  Stream<BodyTrackerState> build() async* {
    final repository = ref.watch(measurementRepositoryProvider);
    final settings =
        ref.watch(settingsControllerProvider).value ?? AppSettings.defaults;
    await repository.ensureDefaultMeasurements(
      bodyWeightUnit: _bodyWeightUnitFor(settings.unitSystem),
    );

    yield* repository.watchTrackSummaries().map(
          BodyTrackerState.fromSummaries,
        );
  }

  Future<void> saveEntry({
    required String measurementId,
    required String valueEntered,
    required DateTime measuredAt,
    String? comment,
  }) {
    return ref.read(measurementRepositoryProvider).createEntry(
          MeasurementEntryDraft(
            measurementId: measurementId,
            valueEntered: valueEntered,
            measuredAt: measuredAt,
            comment: comment,
          ),
        );
  }

  Future<void> updateEntry({
    required String entryId,
    required String measurementId,
    required String valueEntered,
    required DateTime measuredAt,
    String? comment,
  }) {
    return ref.read(measurementRepositoryProvider).updateEntry(
          entryId,
          MeasurementEntryDraft(
            measurementId: measurementId,
            valueEntered: valueEntered,
            measuredAt: measuredAt,
            comment: comment,
          ),
        );
  }

  Future<void> deleteEntry(String entryId) {
    return ref.read(measurementRepositoryProvider).softDeleteEntry(entryId);
  }

  Future<void> createMeasurement({
    required String name,
    required MeasurementUnit unit,
    required MeasurementGoalType goalType,
    required bool enabled,
    double? targetValue,
  }) {
    return ref.read(measurementRepositoryProvider).createMeasurement(
          MeasurementDraft(
            name: name,
            unit: unit,
            goalType: goalType,
            targetValue: targetValue,
            enabled: enabled,
          ),
        );
  }

  Future<void> setMeasurementEnabled(String measurementId, bool enabled) {
    return ref
        .read(measurementRepositoryProvider)
        .setMeasurementEnabled(measurementId, enabled);
  }

  Future<void> reorderMeasurements(List<String> orderedIds) {
    return ref
        .read(measurementRepositoryProvider)
        .reorderMeasurements(orderedIds);
  }

  Future<void> resetDefaultMeasurements() {
    final settings =
        ref.read(settingsControllerProvider).value ?? AppSettings.defaults;
    return ref.read(measurementRepositoryProvider).resetDefaultMeasurements(
          bodyWeightUnit: _bodyWeightUnitFor(settings.unitSystem),
        );
  }

  Future<void> deleteMeasurement(String measurementId) {
    return ref
        .read(measurementRepositoryProvider)
        .softDeleteMeasurement(measurementId);
  }

  Future<MeasurementValueValidation> validateEntry({
    required String measurementId,
    required String valueEntered,
    required DateTime measuredAt,
    String? comment,
  }) {
    return ref.read(measurementRepositoryProvider).validateEntry(
          MeasurementEntryDraft(
            measurementId: measurementId,
            valueEntered: valueEntered,
            measuredAt: measuredAt,
            comment: comment,
          ),
        );
  }
}

final class BodyTrackerState {
  BodyTrackerState({
    required List<MeasurementTrackItem> items,
  }) : items = List<MeasurementTrackItem>.unmodifiable(items);

  factory BodyTrackerState.fromSummaries(
    List<MeasurementTrackSummary> summaries,
  ) {
    return BodyTrackerState(
      items: summaries
          .map(
            (summary) => MeasurementTrackItem(
              summary: summary,
              delta: deriveMeasurementDelta(summary: summary),
            ),
          )
          .toList(growable: false),
    );
  }

  final List<MeasurementTrackItem> items;
}

final class MeasurementTrackItem {
  const MeasurementTrackItem({
    required this.summary,
    this.delta,
  });

  final MeasurementTrackSummary summary;
  final MeasurementDelta? delta;
}

final class BodyTrackerHistoryState {
  BodyTrackerHistoryState({
    required List<MeasurementRecord> measurements,
    required List<MeasurementHistoryItem> items,
  })  : measurements = List<MeasurementRecord>.unmodifiable(measurements),
        items = List<MeasurementHistoryItem>.unmodifiable(items);

  factory BodyTrackerHistoryState.fromEntries({
    required List<MeasurementRecord> measurements,
    required List<MeasurementHistoryEntry> entries,
  }) {
    final measurementsById = <String, MeasurementRecord>{
      for (final measurement in measurements) measurement.id: measurement,
    };
    return BodyTrackerHistoryState(
      measurements: measurements,
      items: entries.map(
        (entry) {
          final measurement =
              measurementsById[entry.measurement.id] ?? entry.measurement;
          return MeasurementHistoryItem(
            measurement: measurement,
            entry: entry.entry,
            delta: deriveMeasurementDelta(
              summary: MeasurementTrackSummary(
                measurement: measurement,
                latestEntry: entry.entry,
                previousEntry: entry.previousEntry,
              ),
            ),
          );
        },
      ).toList(growable: false),
    );
  }

  final List<MeasurementRecord> measurements;
  final List<MeasurementHistoryItem> items;
}

final class MeasurementHistoryItem {
  const MeasurementHistoryItem({
    required this.measurement,
    required this.entry,
    this.delta,
  });

  final MeasurementRecord measurement;
  final MeasurementEntryRecord entry;
  final MeasurementDelta? delta;
}

final class BodyTrackerManagementState {
  BodyTrackerManagementState({
    required List<MeasurementRecord> measurements,
  }) : measurements = List<MeasurementRecord>.unmodifiable(measurements);

  final List<MeasurementRecord> measurements;
}

final class BodyTrackerGraphState {
  const BodyTrackerGraphState({
    required this.graph,
  });

  final MeasurementProgressGraph graph;
}

Stream<BodyTrackerHistoryState> _watchBodyTrackerHistory(
  MeasurementRepository repository,
  String? measurementId,
) {
  late final StreamSubscription<List<MeasurementRecord>>
      measurementSubscription;
  late final StreamSubscription<List<MeasurementHistoryEntry>>
      entrySubscription;
  final controller = StreamController<BodyTrackerHistoryState>();
  List<MeasurementRecord>? latestMeasurements;
  List<MeasurementHistoryEntry>? latestEntries;
  String? lastSignature;

  void emitIfReady() {
    final measurements = latestMeasurements;
    final entries = latestEntries;
    if (measurements == null || entries == null) {
      return;
    }

    final state = BodyTrackerHistoryState.fromEntries(
      measurements: measurements,
      entries: entries,
    );
    final signature = _bodyTrackerHistorySignature(state);
    if (signature == lastSignature) {
      return;
    }

    lastSignature = signature;
    controller.add(state);
  }

  controller.onListen = () {
    measurementSubscription = repository.watchCuratedActive().listen(
      (measurements) {
        latestMeasurements = measurements;
        emitIfReady();
      },
      onError: controller.addError,
    );
    entrySubscription =
        repository.watchHistoryEntries(measurementId: measurementId).listen(
      (entries) {
        latestEntries = entries;
        emitIfReady();
      },
      onError: controller.addError,
    );
  };
  controller.onCancel = () async {
    await measurementSubscription.cancel();
    await entrySubscription.cancel();
  };

  return controller.stream;
}

Stream<BodyTrackerGraphState?> _watchBodyTrackerGraph(
  MeasurementRepository repository,
  String measurementId,
) {
  late final StreamSubscription<MeasurementRecord?> measurementSubscription;
  late final StreamSubscription<List<MeasurementHistoryEntry>>
      entrySubscription;
  final controller = StreamController<BodyTrackerGraphState?>();
  MeasurementRecord? latestMeasurement;
  List<MeasurementHistoryEntry>? latestEntries;
  var hasMeasurement = false;
  String? lastSignature;

  void emitState(BodyTrackerGraphState? state) {
    final signature = _bodyTrackerGraphSignature(state);
    if (signature == lastSignature) {
      return;
    }

    lastSignature = signature;
    controller.add(state);
  }

  void emitIfReady() {
    final entries = latestEntries;
    if (!hasMeasurement || entries == null) {
      return;
    }

    final measurement = latestMeasurement;
    if (measurement == null) {
      emitState(null);
      return;
    }

    emitState(
      BodyTrackerGraphState(
        graph: MeasurementProgressGraph.fromHistory(
          measurement: measurement,
          entries: entries,
        ),
      ),
    );
  }

  controller.onListen = () {
    measurementSubscription =
        repository.watchCuratedActiveById(measurementId).listen(
      (measurement) {
        latestMeasurement = measurement;
        hasMeasurement = true;
        emitIfReady();
      },
      onError: controller.addError,
    );
    final entryStream = repository.watchHistoryEntries(
      measurementId: measurementId,
    );
    entrySubscription = entryStream.listen(
      (entries) {
        latestEntries = entries;
        emitIfReady();
      },
      onError: controller.addError,
    );
  };
  controller.onCancel = () async {
    await measurementSubscription.cancel();
    await entrySubscription.cancel();
  };

  return controller.stream;
}

String _bodyTrackerHistorySignature(BodyTrackerHistoryState state) {
  final buffer = StringBuffer();
  for (final measurement in state.measurements) {
    buffer
      ..write('m|')
      ..write(_measurementRecordSignature(measurement))
      ..write(';');
  }
  for (final item in state.items) {
    buffer
      ..write('i|')
      ..write(_measurementRecordSignature(item.measurement))
      ..write('|')
      ..write(_measurementEntryRecordSignature(item.entry))
      ..write('|')
      ..write(_measurementDeltaSignature(item.delta))
      ..write(';');
  }
  return buffer.toString();
}

String _bodyTrackerGraphSignature(BodyTrackerGraphState? state) {
  final graph = state?.graph;
  if (graph == null) {
    return 'missing';
  }

  final buffer = StringBuffer(_measurementRecordSignature(graph.measurement));
  for (final point in graph.rawPoints) {
    buffer
      ..write('|')
      ..write(point.entryId)
      ..write(':')
      ..write(point.measuredAt.toIso8601String())
      ..write(':')
      ..write(point.value)
      ..write(':')
      ..write(point.valueEntered)
      ..write(':')
      ..write(point.unit.name)
      ..write(':')
      ..write(point.provenance.name)
      ..write(':')
      ..write(point.source);
  }
  return buffer.toString();
}

String _measurementRecordSignature(MeasurementRecord measurement) {
  return <String>[
    measurement.id,
    measurement.name,
    measurement.unit.name,
    measurement.goalType.name,
    measurement.targetValue?.toString() ?? '',
    measurement.enabled.toString(),
    measurement.sortOrder.toString(),
    measurement.updatedAt.toIso8601String(),
    measurement.deletedAt?.toIso8601String() ?? '',
  ].join('|');
}

String _measurementEntryRecordSignature(MeasurementEntryRecord entry) {
  return <String>[
    entry.id,
    entry.measurementId,
    entry.value.toString(),
    entry.valueEntered,
    entry.measuredAt.toIso8601String(),
    entry.provenance.name,
    entry.source,
    entry.externalId ?? '',
    entry.comment ?? '',
    entry.updatedAt.toIso8601String(),
    entry.deletedAt?.toIso8601String() ?? '',
  ].join('|');
}

String _measurementDeltaSignature(MeasurementDelta? delta) {
  if (delta == null) {
    return 'none';
  }
  return <String>[
    delta.value.toString(),
    delta.valueEntered,
    delta.direction.name,
  ].join('|');
}

MeasurementUnit _bodyWeightUnitFor(UnitSystem unitSystem) {
  return switch (unitSystem) {
    UnitSystem.metric => MeasurementUnit.kilogram,
    UnitSystem.imperial => MeasurementUnit.pound,
  };
}
