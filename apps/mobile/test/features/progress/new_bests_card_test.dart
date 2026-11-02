import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/analytics/progress_measure.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/progress/controllers/progress_controller.dart';
import 'package:perennia/features/progress/repositories/progress_feature_repository.dart';
import 'package:perennia/features/progress/widgets/new_bests_card.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

// Today is Friday 30 October 2026.
final _fridayEvening = DateTime(2026, 10, 30, 18);

NewBest _best(
  String exerciseId,
  TrainingDayDate date,
  ProgressMeasureKind measure,
  double value, {
  TrainingUnit unit = TrainingUnit.kilogram,
}) {
  return NewBest(
    exerciseId: exerciseId,
    measure: measure,
    workoutId: 'w-${date.storageValue}',
    localDate: date,
    startedAt: DateTime(date.year, date.month, date.day, 7),
    setId: 's-$exerciseId-${date.storageValue}',
    value: value,
    unit: unit,
  );
}

Future<void> _pump(
  WidgetTester tester,
  StubProgressFeatureRepository repository, {
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
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(AppDimens.base),
              child: NewBestsCard(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The texts of [best]'s row, in reading order.
List<String> _rowTexts(WidgetTester tester, NewBest best) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(NewBestsCard.rowKey(best)),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data!)
    .toList();

/// A repository whose New Bests stream fails, as a failed computation does.
class _FailingNewBestsRepository extends StubProgressFeatureRepository {
  const _FailingNewBestsRepository();

  @override
  Stream<List<NewBest>> watchNewBests(
    TrainingDayDate from,
    TrainingDayDate to,
  ) {
    return Stream<List<NewBest>>.error(StateError('compute failed'));
  }
}

void main() {
  const names = <String, String>{
    'e-bench': 'Bench press',
    'e-run': '5 km run',
    'e-squat': 'Squat',
  };

  testWidgets('each date reads by how long ago it was', (tester) async {
    final weekday = _best(
      'e-squat',
      const TrainingDayDate(year: 2026, month: 10, day: 24),
      ProgressMeasureKind.maxLoad,
      140,
    );
    final today = _best(
      'e-squat',
      const TrainingDayDate(year: 2026, month: 10, day: 30),
      ProgressMeasureKind.maxLoad,
      142.5,
    );
    final thisYear = _best(
      'e-squat',
      const TrainingDayDate(year: 2026, month: 10, day: 23),
      ProgressMeasureKind.maxLoad,
      137.5,
    );
    final lastYear = _best(
      'e-squat',
      const TrainingDayDate(year: 2025, month: 12, day: 12),
      ProgressMeasureKind.maxLoad,
      135,
    );
    await _pump(
      tester,
      StubProgressFeatureRepository(
        exerciseNames: names,
        newBests: [today, weekday, thisYear, lastYear],
      ),
    );

    expect(_rowTexts(tester, today), ['Squat · 142.5 kg', 'Fri']);
    // Six days before today is still a weekday; seven is a date.
    expect(_rowTexts(tester, weekday), ['Squat · 140 kg', 'Sat']);
    expect(_rowTexts(tester, thisYear), ['Squat · 137.5 kg', '23 Oct']);
    expect(_rowTexts(tester, lastYear), ['Squat · 135 kg', '12 Dec 2025']);
  });

  testWidgets(
      'an estimated one-rep max is prefixed "e1RM", and every row has a '
      'trophy', (tester) async {
    final e1rm = _best(
      'e-bench',
      const TrainingDayDate(year: 2026, month: 10, day: 29),
      ProgressMeasureKind.estimatedOneRepMax,
      102.5,
    );
    final pace = _best(
      'e-run',
      const TrainingDayDate(year: 2026, month: 10, day: 28),
      ProgressMeasureKind.fastestPace,
      304,
      unit: TrainingUnit.second,
    );
    await _pump(
      tester,
      StubProgressFeatureRepository(
        exerciseNames: names,
        newBests: [e1rm, pace],
      ),
    );

    expect(_rowTexts(tester, e1rm), ['Bench press · e1RM 102.5 kg', 'Thu']);
    expect(_rowTexts(tester, pace), ['5 km run · 5:04 /km', 'Wed']);
    final trophies = tester.widgetList<Icon>(
      find.byIcon(Icons.emoji_events_outlined),
    );
    expect(trophies, hasLength(2));
    for (final trophy in trophies) {
      expect(trophy.color, AppColors.light.record);
    }
    expect(find.text('New bests · 2'), findsOneWidget);
  });

  testWidgets('the title counts every New Best; five rows are listed', (
    tester,
  ) async {
    final bests = <NewBest>[
      for (var day = 30; day >= 23; day -= 1)
        _best(
          'e-squat',
          TrainingDayDate(year: 2026, month: 10, day: day),
          ProgressMeasureKind.maxLoad,
          100.0 + day,
        ),
      // An exercise with no active name is left out of rows and count.
      _best(
        'e-gone',
        const TrainingDayDate(year: 2026, month: 10, day: 30),
        ProgressMeasureKind.maxLoad,
        80,
      ),
    ];
    await _pump(
      tester,
      StubProgressFeatureRepository(exerciseNames: names, newBests: bests),
    );

    expect(find.text('New bests · 8'), findsOneWidget);
    for (final (index, best) in bests.indexed) {
      expect(
        find.byKey(NewBestsCard.rowKey(best)),
        index < 5 ? findsOneWidget : findsNothing,
      );
    }
    expect(
      tester.getSize(find.byKey(NewBestsCard.rowKey(bests.first))).height,
      greaterThanOrEqualTo(AppDimens.touchTarget),
    );
  });

  testWidgets('with no New Best, the card says so, with no action', (
    tester,
  ) async {
    await _pump(
      tester,
      const StubProgressFeatureRepository(exerciseNames: names),
    );

    expect(find.text('New bests'), findsOneWidget);
    expect(find.text('No new bests in this period'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('a failed read shows the card as unavailable, not loading', (
    tester,
  ) async {
    await _pump(tester, const _FailingNewBestsRepository());

    expect(find.text('New bests'), findsOneWidget);
    expect(find.text('Unavailable right now'), findsOneWidget);
  });

  testWidgets(
      'a long exercise name ellipsizes instead of overflowing at 320 dp '
      'and 1.3x text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      StubProgressFeatureRepository(
        exerciseNames: const <String, String>{
          'e-long': 'Single-arm landmine press with a pause at the bottom',
        },
        newBests: [
          _best(
            'e-long',
            const TrainingDayDate(year: 2025, month: 12, day: 12),
            ProgressMeasureKind.estimatedOneRepMax,
            102.5,
          ),
        ],
      ),
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('12 Dec 2025'), findsOneWidget);
  });
}
