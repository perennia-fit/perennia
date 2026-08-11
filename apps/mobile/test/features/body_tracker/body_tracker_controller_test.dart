import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/body_tracker/controllers/body_tracker_controller.dart';

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

  test('body tracker state defensively copies track items', () {
    final firstItem = MeasurementTrackItem(summary: _summary('measurement-1'));
    final secondItem = MeasurementTrackItem(summary: _summary('measurement-2'));
    final items = <MeasurementTrackItem>[firstItem];

    final state = BodyTrackerState(items: items);

    items.add(secondItem);

    expect(state.items, hasLength(1));
    expect(() => state.items.add(secondItem), throwsUnsupportedError);
    expect(() => state.items[0] = secondItem, throwsUnsupportedError);
  });

  test('body tracker history state defensively copies measurements and items',
      () {
    final firstMeasurement = _measurement('measurement-1');
    final secondMeasurement = _measurement('measurement-2');
    final firstItem = MeasurementHistoryItem(
      measurement: firstMeasurement,
      entry: _entry('entry-1', measurementId: firstMeasurement.id),
    );
    final secondItem = MeasurementHistoryItem(
      measurement: secondMeasurement,
      entry: _entry('entry-2', measurementId: secondMeasurement.id),
    );
    final measurements = <MeasurementRecord>[firstMeasurement];
    final items = <MeasurementHistoryItem>[firstItem];

    final state = BodyTrackerHistoryState(
      measurements: measurements,
      items: items,
    );

    measurements.add(secondMeasurement);
    items.add(secondItem);

    expect(state.measurements, hasLength(1));
    expect(state.items, hasLength(1));
    expect(
      () => state.measurements.add(secondMeasurement),
      throwsUnsupportedError,
    );
    expect(() => state.items.add(secondItem), throwsUnsupportedError);
    expect(() => state.measurements[0] = secondMeasurement,
        throwsUnsupportedError);
    expect(() => state.items[0] = secondItem, throwsUnsupportedError);
  });

  test('body tracker management state defensively copies measurements', () {
    final firstMeasurement = _measurement('measurement-1');
    final secondMeasurement = _measurement('measurement-2');
    final measurements = <MeasurementRecord>[firstMeasurement];

    final state = BodyTrackerManagementState(measurements: measurements);

    measurements.add(secondMeasurement);

    expect(state.measurements, hasLength(1));
    expect(
      () => state.measurements.add(secondMeasurement),
      throwsUnsupportedError,
    );
    expect(() => state.measurements[0] = secondMeasurement,
        throwsUnsupportedError);
  });

  test('graph provider refreshes scoped measurement metadata without entries',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final measurementId = await repositories.measurements.createMeasurement(
      const MeasurementDraft(
        name: 'Waist',
        unit: MeasurementUnit.centimeter,
        goalType: MeasurementGoalType.target,
        targetValue: 80,
        enabled: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
      ],
    );
    addTearDown(container.dispose);

    final states = <AsyncValue<BodyTrackerGraphState?>>[];
    final subscription = container.listen(
      bodyTrackerGraphProvider(measurementId),
      (previous, next) => states.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await _waitFor(
      () => states.any(
        (state) => state.asData?.value?.graph.targetValue == 80,
      ),
    );

    await (database.update(database.metrics)
          ..where((row) => row.id.equals(measurementId)))
        .write(
      MetricsCompanion(
        goalTargetValue: const Value<double?>(75),
        updatedAt: Value<DateTime>(DateTime.utc(2026, 7, 9)),
      ),
    );

    await _waitFor(
      () => states.any(
        (state) => state.asData?.value?.graph.targetValue == 75,
      ),
    );
  });

  test('history provider refreshes curated measurements for selected history',
      () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    await repositories.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.kilogram,
    );
    final measurements = await repositories.measurements.listEnabled();
    final bodyWeight = measurements.singleWhere(
      (measurement) => measurement.name == 'Body Weight',
    );
    final bodyFat = measurements.singleWhere(
      (measurement) => measurement.name == 'Body Fat',
    );
    await repositories.measurements.createEntry(
      MeasurementEntryDraft(
        measurementId: bodyWeight.id,
        valueEntered: '82',
        measuredAt: DateTime.utc(2026, 7, 9, 7),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
      ],
    );
    addTearDown(container.dispose);

    final states = <AsyncValue<BodyTrackerHistoryState>>[];
    final subscription = container.listen(
      bodyTrackerHistoryProvider(bodyWeight.id),
      (previous, next) => states.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await _waitFor(
      () => states.any(
        (state) =>
            state.asData?.value.measurements.any(
              (measurement) =>
                  measurement.id == bodyFat.id && measurement.enabled,
            ) ??
            false,
      ),
    );

    await repositories.measurements.setMeasurementEnabled(bodyFat.id, false);

    await _waitFor(
      () => states.any(
        (state) =>
            state.asData?.value.measurements.any(
              (measurement) =>
                  measurement.id == bodyFat.id && !measurement.enabled,
            ) ??
            false,
      ),
    );
    expect(
      states.last.asData?.value.items.map((item) => item.measurement.id),
      everyElement(bodyWeight.id),
    );
  });
}

Matcher get throwsUnsupportedError => throwsA(isA<UnsupportedError>());

MeasurementTrackSummary _summary(String measurementId) {
  final measurement = _measurement(measurementId);
  return MeasurementTrackSummary(
    measurement: measurement,
    latestEntry: _entry('latest-$measurementId', measurementId: measurementId),
  );
}

MeasurementRecord _measurement(String id) {
  return MeasurementRecord(
    id: id,
    name: 'Body Weight',
    unit: MeasurementUnit.kilogram,
    goalType: MeasurementGoalType.decrease,
    enabled: true,
    sortOrder: 0,
    updatedAt: DateTime.utc(2026),
  );
}

MeasurementEntryRecord _entry(
  String id, {
  required String measurementId,
}) {
  return MeasurementEntryRecord(
    id: id,
    measurementId: measurementId,
    value: 82,
    valueEntered: '82',
    measuredAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
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
