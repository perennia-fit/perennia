import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/body_tracker/widgets/body_tracker_screen.dart';
import 'package:perennia/features/progress/controllers/progress_controller.dart';
import 'package:perennia/features/progress/repositories/progress_feature_repository.dart';
import 'package:perennia/features/progress/widgets/body_card.dart';
import 'package:perennia/features/progress/widgets/progress_card.dart';
import 'package:perennia/features/progress/widgets/progress_sparkline.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

// Today is Friday 30 October 2026; the default 12-week period runs from
// Monday 10 August to Sunday 1 November, in the device's zone.
final _fridayEvening = DateTime(2026, 10, 30, 18);
final _periodStartMorning = DateTime(2026, 8, 10, 7);

MeasurementRecord _measurement(
  String id,
  String name, {
  MeasurementUnit unit = MeasurementUnit.kilogram,
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

/// A stub holding [measurement] with [readings].
StubProgressFeatureRepository _repository(
  MeasurementRecord measurement,
  List<(DateTime, double)> readings,
) {
  return StubProgressFeatureRepository(
    curatedMeasurements: <MeasurementRecord>[measurement],
    measurementEntries: <String, List<MeasurementHistoryEntry>>{
      measurement.id: _entries(measurement, readings),
    },
  );
}

class _FailingMeasurementsRepository extends StubProgressFeatureRepository {
  const _FailingMeasurementsRepository();

  @override
  Stream<List<MeasurementRecord>> watchCuratedMeasurements() {
    return Stream<List<MeasurementRecord>>.error(StateError('query failed'));
  }
}

Future<void> _pump(
  WidgetTester tester,
  ProgressFeatureRepository repository, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        progressFeatureRepositoryProvider.overrideWith((ref) => repository),
        settingsRepositoryProvider.overrideWith(
          (ref) => InMemorySettingsRepository(),
        ),
        progressClockProvider.overrideWith((ref) => () => _fridayEvening),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routes: <String, WidgetBuilder>{
          BodyTrackerScreen.routeName: (_) =>
              const Scaffold(body: Text('Body Tracker opened')),
        },
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(AppDimens.base),
              child: BodyCard(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

void main() {
  final bodyWeight = _measurement('body-weight', 'Body Weight');

  testWidgets(
      'CUJ 11: a noisy scale shows its readings as dots under the Trend, '
      'labelled with the latest Trend and its change', (tester) async {
    // Two weeks of mornings, swinging between 80.4 and 81.9 kg. The Trend
    // was worked out by hand: 81.07 at the last Reading, 0.13 below the
    // first.
    const values = <double>[
      81.2, 80.4, 81.9, 80.8, 81.5, 80.6, 81.7, //
      80.5, 81.3, 81.9, 80.7, 81.1, 80.4, 81.0,
    ];
    final first = DateTime(2026, 10, 17, 7);
    await _pump(
      tester,
      _repository(bodyWeight, <(DateTime, double)>[
        for (final (day, value) in values.indexed)
          (first.add(Duration(days: day)), value),
      ]),
    );

    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Smoothed over about 10 days'), findsOneWidget);
    expect(find.text('Body Weight'), findsOneWidget);
    expect(_text(tester, BodyCard.trendKey(bodyWeight.id)), '81.1 kg');
    expect(_text(tester, BodyCard.changeKey(bodyWeight.id)), '↓ 0.1 kg');
    expect(find.byKey(BodyCard.bodyTrackerButtonKey), findsOneWidget);

    final chart = find.byKey(BodyCard.chartKey(bodyWeight.id));
    expect(
      tester.getSize(chart).height,
      AppDimens.progressBodyChartHeight,
    );
    final sparkline = tester.widget<ProgressSparkline>(
      find.descendant(of: chart, matching: find.byType(ProgressSparkline)),
    );
    expect(sparkline.points.map((point) => point.y), values);
    expect(sparkline.overlay, hasLength(values.length));
    expect(sparkline.overlay.first.y, values.first);
    expect(sparkline.overlay.last.y, closeTo(81.0732156983, 1e-9));
    expect(sparkline.pointColor, AppColors.light.textSecondary);
    expect(sparkline.overlayColor, AppTheme.light().colorScheme.primary);

    // The chart is one labelled node, its content excluded.
    expect(
      tester.getSemantics(
        find.ancestor(of: chart, matching: find.byType(Semantics)).first,
      ),
      matchesSemantics(
        label: 'Body Weight: 14 readings and their trend in this period',
      ),
    );
  });

  testWidgets('the change counts from the Trend before the period', (
    tester,
  ) async {
    // 82 the day before the period, 80 on its first day: the Trend moves
    // 10% of the way, to 81.8.
    await _pump(
      tester,
      _repository(bodyWeight, <(DateTime, double)>[
        (_periodStartMorning.subtract(const Duration(days: 1)), 82),
        (_periodStartMorning, 80),
      ]),
    );

    expect(_text(tester, BodyCard.trendKey(bodyWeight.id)), '81.8 kg');
    expect(_text(tester, BodyCard.changeKey(bodyWeight.id)), '↓ 0.2 kg');
    // Only the period's Reading is drawn.
    final sparkline = tester.widget<ProgressSparkline>(
      find.byType(ProgressSparkline),
    );
    expect(sparkline.points.map((point) => point.y), <double>[80]);
  });

  testWidgets(
      'without a Reading before the period, the change counts from its '
      'first Trend', (tester) async {
    await _pump(
      tester,
      _repository(bodyWeight, <(DateTime, double)>[
        (DateTime(2026, 10, 1, 7), 80),
        (DateTime(2026, 10, 1, 7).add(const Duration(days: 1)), 81),
      ]),
    );

    expect(_text(tester, BodyCard.trendKey(bodyWeight.id)), '80.1 kg');
    expect(_text(tester, BodyCard.changeKey(bodyWeight.id)), '↑ 0.1 kg');
  });

  testWidgets('a change that rounds to 0.0 reads "No change"', (
    tester,
  ) async {
    // The Trend moves from 80.0 to 80.04, which shows as 80.0.
    final waist = _measurement(
      'waist',
      'Waist',
      unit: MeasurementUnit.centimeter,
    );
    await _pump(
      tester,
      _repository(waist, <(DateTime, double)>[
        (_periodStartMorning.subtract(const Duration(days: 1)), 80),
        (_periodStartMorning, 80.4),
      ]),
    );

    expect(_text(tester, BodyCard.trendKey(waist.id)), '80.0 cm');
    expect(_text(tester, BodyCard.changeKey(waist.id)), 'No change');
  });

  testWidgets(
      'with no Reading in the period, the empty state opens Body Tracker '
      'with its one action', (tester) async {
    // A Reading before the period only.
    await _pump(
      tester,
      _repository(bodyWeight, <(DateTime, double)>[
        (DateTime(2026, 7, 1, 7), 80),
      ]),
    );

    expect(find.text('Log a measurement to see its trend'), findsOneWidget);
    expect(find.text('Smoothed over about 10 days'), findsNothing);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byKey(BodyCard.bodyTrackerButtonKey), findsOneWidget);

    await tester.tap(find.byKey(BodyCard.bodyTrackerButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Body Tracker opened'), findsOneWidget);
  });

  testWidgets('a long name at 320 dp and 1.3x text does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final long = _measurement(
      'long',
      'Left upper arm circumference, relaxed, measured at the midpoint',
      unit: MeasurementUnit.centimeter,
    );
    await _pump(
      tester,
      _repository(long, <(DateTime, double)>[
        (DateTime(2026, 10, 1, 7), 1234.5),
        (DateTime(2026, 10, 20, 7), 1200.25),
      ]),
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(BodyCard.trendKey(long.id)), findsOneWidget);
  });

  testWidgets('a failed read shows the card as unavailable, not loading', (
    tester,
  ) async {
    await _pump(tester, const _FailingMeasurementsRepository());

    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Unavailable right now'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox &&
            widget.height == ProgressCard.loadingBodyHeight,
      ),
      findsNothing,
    );
  });

  testWidgets('a Trend that overflows renders without throwing', (
    tester,
  ) async {
    final bodyWeight = _measurement('body-weight', 'Body Weight');
    await _pump(
      tester,
      _repository(bodyWeight, <(DateTime, double)>[
        (_periodStartMorning, 1e308),
        (_periodStartMorning, -1e308),
      ]),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(BodyCard.rowKey(bodyWeight.id)), findsOneWidget);
  });
}
