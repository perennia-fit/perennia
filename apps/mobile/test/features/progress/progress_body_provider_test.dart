import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/progress/controllers/progress_controller.dart';
import 'package:perennia/features/progress/repositories/progress_feature_repository.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';

// Today is Friday 30 October 2026; the default 12-week period runs from
// Monday 10 August to Sunday 1 November, in the device's zone.
final _fridayEvening = DateTime(2026, 10, 30, 18);

MeasurementRecord _measurement(
  String id,
  String name, {
  MeasurementUnit unit = MeasurementUnit.centimeter,
}) {
  return MeasurementRecord(
    id: id,
    name: name,
    unit: unit,
    goalType: MeasurementGoalType.decrease,
    enabled: true,
    sortOrder: 0,
    updatedAt: DateTime.utc(2026),
  );
}

/// Body Tracker's entries for [measurement], newest first as it reads them.
List<MeasurementHistoryEntry> _entries(
  MeasurementRecord measurement,
  List<(DateTime, double)> readings,
) {
  final records = <MeasurementEntryRecord>[
    for (final (index, (at, value)) in readings.indexed)
      MeasurementEntryRecord(
        id: '${measurement.id}-$index',
        measurementId: measurement.id,
        value: value,
        valueEntered: '$value',
        measuredAt: at.toUtc(),
        updatedAt: at.toUtc(),
      ),
  ]..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
  return <MeasurementHistoryEntry>[
    for (final (index, entry) in records.indexed)
      MeasurementHistoryEntry(
        measurement: measurement,
        entry: entry,
        previousEntry: index + 1 < records.length ? records[index + 1] : null,
      ),
  ];
}

class _FailingEntriesRepository extends StubProgressFeatureRepository {
  const _FailingEntriesRepository({
    super.curatedMeasurements,
    super.measurementEntries,
  });

  @override
  Stream<List<MeasurementHistoryEntry>> watchMeasurementEntries(
    String measurementId,
  ) {
    return measurementId == 'waist'
        ? Stream<List<MeasurementHistoryEntry>>.error(StateError('failed'))
        : super.watchMeasurementEntries(measurementId);
  }
}

Future<AsyncValue<List<ProgressBodyRow>>> _read(
  WidgetTester tester,
  ProgressFeatureRepository repository,
) async {
  late AsyncValue<List<ProgressBodyRow>> body;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        progressFeatureRepositoryProvider.overrideWith((ref) => repository),
        settingsRepositoryProvider.overrideWith(
          (ref) => InMemorySettingsRepository(),
        ),
        progressClockProvider.overrideWith((ref) => () => _fridayEvening),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          body = ref.watch(progressBodyProvider);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return body;
}

void main() {
  final bodyWeight = _measurement(
    'body-weight',
    'Body Weight',
    unit: MeasurementUnit.kilogram,
  );
  final waist = _measurement('waist', 'Waist');
  final bodyFat = _measurement(
    'body-fat',
    'Body Fat',
    unit: MeasurementUnit.percent,
  );
  final chest = _measurement('chest', 'Chest');

  testWidgets(
      'keeps measurements with a Reading in the period, in Body Tracker\'s '
      'order, with the period\'s Trend and its change', (tester) async {
    final body = await _read(
      tester,
      StubProgressFeatureRepository(
        curatedMeasurements: <MeasurementRecord>[
          bodyWeight,
          waist,
          bodyFat,
          chest,
        ],
        measurementEntries: <String, List<MeasurementHistoryEntry>>{
          bodyWeight.id: _entries(bodyWeight, <(DateTime, double)>[
            // The day before the period, then its first instant, then a day
            // later; a Reading after the period's last day is left out.
            (DateTime(2026, 8, 9), 80),
            (DateTime(2026, 8, 10), 81),
            (DateTime(2026, 8, 11), 82),
            (DateTime(2026, 11, 2), 90),
          ]),
          // Only before the period: no row.
          waist.id: _entries(waist, <(DateTime, double)>[
            (DateTime(2026, 8, 9, 23, 59), 90),
          ]),
          chest.id: _entries(chest, <(DateTime, double)>[
            (DateTime(2026, 9, 1, 7), 100),
          ]),
        },
      ),
    );

    final rows = body.requireValue;
    expect(
        rows.map((row) => row.measurementId), <String>['body-weight', 'chest']);

    final weight = rows.first;
    expect(weight.name, 'Body Weight');
    expect(weight.unit, MeasurementUnit.kilogram);
    expect(
      weight.readings.map((point) => point.value),
      <double>[81, 82],
    );
    // Daily Readings move the Trend 10% of the way: 80, 80.1, 80.29. The
    // change runs from the last Trend before the period.
    expect(weight.readings.first.trend, closeTo(80.1, 1e-9));
    expect(weight.latestTrend, closeTo(80.29, 1e-9));
    expect(weight.change, closeTo(0.29, 1e-9));

    // With no Reading before the period, its first one is the baseline.
    final chestRow = rows.last;
    expect(chestRow.latestTrend, 100);
    expect(chestRow.change, 0);
  });

  testWidgets('no curated measurement with a Reading in the period is empty', (
    tester,
  ) async {
    final body = await _read(
      tester,
      StubProgressFeatureRepository(
        curatedMeasurements: <MeasurementRecord>[bodyWeight],
      ),
    );

    expect(body.requireValue, isEmpty);
  });

  testWidgets('a failed measurement read makes the card unavailable', (
    tester,
  ) async {
    final body = await _read(
      tester,
      _FailingEntriesRepository(
        curatedMeasurements: <MeasurementRecord>[bodyWeight, waist],
        measurementEntries: <String, List<MeasurementHistoryEntry>>{
          bodyWeight.id: _entries(bodyWeight, <(DateTime, double)>[
            (DateTime(2026, 9, 1, 7), 80),
          ]),
        },
      ),
    );

    expect(body.hasError, isTrue);
  });
}
