import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/analytics/progress_measure.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/progress/controllers/progress_controller.dart';
import 'package:perennia/features/progress/repositories/progress_feature_repository.dart';
import 'package:perennia/features/progress/widgets/key_exercises_card.dart';
import 'package:perennia/features/progress/widgets/progress_sparkline.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

// Today is Friday 30 October 2026; the default 12-week period runs from
// Monday 10 August to Sunday 1 November.
final _fridayEvening = DateTime(2026, 10, 30, 18);
const _periodStart = TrainingDayDate(year: 2026, month: 8, day: 10);

ExerciseRecord _exercise(
  String id,
  String name,
  RecordProfile profile, {
  List<DimensionId> dimensions = const <DimensionId>[
    DimensionId.load,
    DimensionId.reps,
  ],
}) {
  return ExerciseRecord(
    id: id,
    origin: ExerciseLibraryOrigin.user,
    name: name,
    type: ExerciseType(dimensions),
    defaultLoadUnit: TrainingUnit.kilogram,
    loadMode: ExerciseLoadMode.added,
    recordProfile: profile,
    categoryId: null,
    notes: null,
    isFavorite: true,
    updatedAt: DateTime.utc(2026),
  );
}

/// A series from (days after the period starts, value) pairs: a negative
/// day is before the period. A point is a New Best when it beats every
/// earlier one, as the core marks it.
ProgressSeries _series(
  String exerciseId,
  ProgressMeasureKind measure,
  List<(int, double)> values,
) {
  double? best;
  return ProgressSeries(
    exerciseId: exerciseId,
    measure: measure,
    betterIs: measure.betterIs,
    points: <ProgressPoint>[
      for (final (index, (day, value)) in values.indexed)
        () {
          final date = _periodStart.addDays(day);
          final isNewBest =
              best != null && measure.betterIs.isBetter(value, best!);
          if (best == null || isNewBest) best = value;
          return ProgressPoint(
            workoutId: '$exerciseId-w$index',
            localDate: date,
            startedAt: DateTime(date.year, date.month, date.day, 7),
            setId: '$exerciseId-s$index',
            value: value,
            unit: measure == ProgressMeasureKind.maxReps
                ? TrainingUnit.repetition
                : measure == ProgressMeasureKind.maxDistance
                    ? TrainingUnit.kilometer
                    : measure == ProgressMeasureKind.estimatedOneRepMax ||
                            measure == ProgressMeasureKind.maxLoad
                        ? TrainingUnit.kilogram
                        : TrainingUnit.second,
            isNewBest: isNewBest,
          );
        }(),
    ],
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
              child: KeyExercisesCard(),
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
  testWidgets('each comparison line, by which way the measure improves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cases = <(ExerciseRecord, ProgressSeries, String, String)>[
      (
        _exercise('e-up', 'Bench press', RecordProfile.maxLoad),
        _series('e-up', ProgressMeasureKind.maxLoad, [(-7, 100), (14, 102.5)]),
        'Best 102.5 kg',
        '↑ 2.5 kg on before',
      ),
      (
        _exercise('e-same', 'Squat', RecordProfile.maxLoad),
        _series('e-same', ProgressMeasureKind.maxLoad, [(-7, 140), (14, 140)]),
        'Best 140 kg',
        'Same as before',
      ),
      (
        _exercise('e-down', 'Deadlift', RecordProfile.maxLoad),
        _series('e-down', ProgressMeasureKind.maxLoad, [(-7, 180), (14, 170)]),
        'Best 170 kg',
        'Best before 180 kg',
      ),
      (
        _exercise('e-first', 'Overhead press', RecordProfile.maxLoad),
        _series('e-first', ProgressMeasureKind.maxLoad, [(3, 50), (14, 52.5)]),
        'Best 52.5 kg',
        'First sessions',
      ),
      (
        _exercise(
          'e-pace',
          '5 km run',
          RecordProfile.fastestPace,
          dimensions: const <DimensionId>[
            DimensionId.distance,
            DimensionId.duration,
          ],
        ),
        _series(
          'e-pace',
          ProgressMeasureKind.fastestPace,
          [(-7, 322), (14, 304)],
        ),
        'Best 5:04 /km',
        '18 s faster than before',
      ),
      (
        _exercise(
          'e-row',
          '2 km row',
          RecordProfile.minDuration,
          dimensions: const <DimensionId>[DimensionId.duration],
        ),
        _series(
          'e-row',
          ProgressMeasureKind.minDuration,
          [(-7, 485), (14, 420)],
        ),
        'Best 7:00',
        '1:05 shorter than before',
      ),
    ];

    await _pump(
      tester,
      StubProgressFeatureRepository(
        favorites: [for (final entry in cases) entry.$1],
        progressSeries: [for (final entry in cases) entry.$2],
      ),
    );

    for (final (exercise, _, best, comparison) in cases) {
      expect(_text(tester, KeyExercisesCard.bestKey(exercise.id)), best);
      expect(
        _text(tester, KeyExercisesCard.comparisonKey(exercise.id)),
        comparison,
        reason: exercise.name,
      );
    }
    // No line uses red, green or gold.
    for (final (exercise, _, _, _) in cases) {
      final style = tester
          .widget<Text>(find.byKey(KeyExercisesCard.comparisonKey(exercise.id)))
          .style!;
      expect(style.color, AppColors.light.textSecondary);
    }
  });

  testWidgets(
      'a tile marks its New Bests as rings and names the latest in its '
      'label', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      StubProgressFeatureRepository(
        favorites: [
          _exercise(
            'e-pace',
            '5 km run',
            RecordProfile.fastestPace,
            dimensions: const <DimensionId>[
              DimensionId.distance,
              DimensionId.duration,
            ],
          ),
        ],
        progressSeries: [
          // Before the period, then Saturday 24 Oct and Thursday 29 Oct.
          _series(
            'e-pace',
            ProgressMeasureKind.fastestPace,
            [(-7, 322), (75, 330), (80, 304)],
          ),
        ],
      ),
    );

    final sparkline = tester.widget<ProgressSparkline>(
      find.byType(ProgressSparkline),
    );
    expect(sparkline.points.map((point) => point.y), <double>[330, 304]);
    expect(sparkline.markedIndexes, <int>{1});
    expect(
      tester.getSemantics(find.byKey(KeyExercisesCard.tileKey('e-pace'))),
      isSemantics(
        label: '5 km run, fastest pace, Best 5:04 /km, '
            '18 s faster than before, New best on Thu',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets(
      'a tile with no point in the period says so in place of the chart '
      'and its lines', (tester) async {
    await _pump(
      tester,
      StubProgressFeatureRepository(
        favorites: [_exercise('e-old', 'Front squat', RecordProfile.repMax)],
        progressSeries: [
          _series(
            'e-old',
            ProgressMeasureKind.estimatedOneRepMax,
            [(-30, 120), (-7, 125)],
          ),
        ],
      ),
    );

    expect(find.text('Front squat'), findsOneWidget);
    expect(find.text('e1RM'), findsOneWidget);
    expect(find.text('No sessions this period'), findsOneWidget);
    expect(find.byType(ProgressSparkline), findsNothing);
    expect(find.byKey(KeyExercisesCard.bestKey('e-old')), findsNothing);
    expect(find.byKey(KeyExercisesCard.comparisonKey('e-old')), findsNothing);
  });

  testWidgets('with no Favorite, the card asks for one, with no action', (
    tester,
  ) async {
    await _pump(tester, const StubProgressFeatureRepository());

    expect(
      find.text('Mark exercises as favorites to chart them here'),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets(
      'with Favorites but none charted, the card says so, with no '
      'action', (tester) async {
    await _pump(
      tester,
      StubProgressFeatureRepository(
        favorites: [
          _exercise(
            'e-stretch',
            'Hip stretch',
            RecordProfile.completionStreak,
            dimensions: const <DimensionId>[],
          ),
        ],
      ),
    );

    expect(find.text('Your favorites have no charted records'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('at most six Favorites are charted, in the order given', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ids = <String>[for (var index = 0; index < 8; index += 1) 'e-$index'];
    await _pump(
      tester,
      StubProgressFeatureRepository(
        favorites: [
          for (final id in ids)
            _exercise(id, 'Lift $id', RecordProfile.maxLoad),
        ],
        progressSeries: [
          for (final id in ids)
            _series(id, ProgressMeasureKind.maxLoad, [(1, 60)]),
        ],
      ),
    );

    for (final id in ids) {
      expect(
        find.byKey(KeyExercisesCard.tileKey(id)),
        ids.indexOf(id) < 6 ? findsOneWidget : findsNothing,
      );
    }
    final first =
        tester.getTopLeft(find.byKey(KeyExercisesCard.tileKey('e-0')));
    final second =
        tester.getTopLeft(find.byKey(KeyExercisesCard.tileKey('e-1')));
    final third =
        tester.getTopLeft(find.byKey(KeyExercisesCard.tileKey('e-2')));
    // Two columns: the second tile beside the first, the third below.
    expect(second.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
    expect(third.dx, first.dx);
    expect(third.dy, greaterThan(first.dy));
    expect(
      tester.getSize(find.byKey(KeyExercisesCard.tileKey('e-0'))).height,
      greaterThanOrEqualTo(AppDimens.touchTarget),
    );
  });

  testWidgets(
      'a long exercise name ellipsizes instead of overflowing at 320 dp '
      'and 1.3x text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const name = 'Single-arm landmine press with a pause at the bottom';
    await _pump(
      tester,
      StubProgressFeatureRepository(
        favorites: [
          _exercise('e-long', name, RecordProfile.maxLoad),
          _exercise('e-other', 'Bench press', RecordProfile.maxLoad),
        ],
        progressSeries: [
          _series(
            'e-long',
            ProgressMeasureKind.maxLoad,
            [(-7, 100), (14, 102.5)],
          ),
          _series(
            'e-other',
            ProgressMeasureKind.maxLoad,
            [(-7, 180), (14, 170)],
          ),
        ],
      ),
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.text(name), findsOneWidget);
  });
}
