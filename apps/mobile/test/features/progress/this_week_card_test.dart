import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_progress.dart';
import 'package:perennia/features/progress/controllers/progress_controller.dart';
import 'package:perennia/features/progress/repositories/progress_feature_repository.dart';
import 'package:perennia/features/progress/widgets/this_week_card.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

// The week of Monday 26 October 2026; today is Friday the 30th.
const _monday = TrainingDayDate(year: 2026, month: 10, day: 26);
final _fridayEvening = DateTime(2026, 10, 30, 18);

TrainingDayDate _day(int offset) => _monday.addDays(offset);

WeeklyPlanFacts _plan(
  String id,
  String name,
  Map<String, List<int>> weekdaysByTemplate,
) {
  return WeeklyPlanFacts(
    routineId: id,
    routineName: name,
    entries: <WeeklyPlanEntry>[
      for (final MapEntry(key: template, value: weekdays)
          in weekdaysByTemplate.entries)
        for (final weekday in weekdays)
          WeeklyPlanEntry(workoutTemplateId: template, weekday: weekday),
    ],
  );
}

ProgressWorkout _workout(int dayOffset, {String? template, String? id}) {
  final date = _day(dayOffset);
  final startedAt = DateTime(date.year, date.month, date.day, 7);
  return ProgressWorkout(
    workoutId: id ?? 'w-$dayOffset-${template ?? 'none'}',
    localDate: date,
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(hours: 1)),
    focusId: null,
    linkedTemplateId: template,
    performedSetCount: 1,
  );
}

Future<void> _pump(
  WidgetTester tester,
  StubProgressFeatureRepository repository, {
  DateTime? now,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        progressFeatureRepositoryProvider.overrideWith((ref) => repository),
        settingsRepositoryProvider.overrideWith(
          (ref) => InMemorySettingsRepository(),
        ),
        progressClockProvider.overrideWith(
          (ref) => () => now ?? _fridayEvening,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(AppDimens.base),
            child: ThisWeekCard(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The icon drawn in [date]'s column, or null for none.
IconData? _dayIcon(WidgetTester tester, TrainingDayDate date) {
  final icons = find.descendant(
    of: find.byKey(ThisWeekCard.dayKey(date)),
    matching: find.byType(Icon),
  );
  return icons.evaluate().isEmpty ? null : tester.widget<Icon>(icons).icon;
}

String _text(WidgetTester tester, Key key) {
  return tester.widget<Text>(find.byKey(key)).data!;
}

void main() {
  // Mon partly done, Tue done differently, Wed not done, Thu trained, Fri
  // (today) done, Sat planned, Sun rest.
  final mixedWeek = StubProgressFeatureRepository(
    weeklyPlans: <WeeklyPlanFacts>[
      _plan('r1', 'Hybrid block', {
        't-lower': [1, 3, 5],
        't-run': [1, 2, 6],
      }),
    ],
    workouts: <ProgressWorkout>[
      _workout(0, template: 't-lower'),
      _workout(1),
      _workout(3),
      _workout(4, template: 't-lower'),
    ],
  );

  testWidgets('every status shows its icon and a legend entry', (
    tester,
  ) async {
    await _pump(tester, mixedWeek);

    const expected = <TrainingDayStatus, IconData?>{
      TrainingDayStatus.partlyDone: Icons.timelapse,
      TrainingDayStatus.doneDifferently: Icons.swap_horiz,
      TrainingDayStatus.notDone: Icons.radio_button_unchecked,
      TrainingDayStatus.trained: Icons.add_circle_outline,
      TrainingDayStatus.done: Icons.check_circle,
      TrainingDayStatus.planned: Icons.event,
      TrainingDayStatus.rest: null,
    };
    const labels = <TrainingDayStatus, String>{
      TrainingDayStatus.partlyDone: 'Partly done',
      TrainingDayStatus.doneDifferently: 'Done differently',
      TrainingDayStatus.notDone: 'Not done',
      TrainingDayStatus.trained: 'Trained',
      TrainingDayStatus.done: 'Done',
      TrainingDayStatus.planned: 'Planned',
      TrainingDayStatus.rest: 'Rest',
    };
    for (final (offset, MapEntry(key: status, value: icon))
        in expected.entries.indexed) {
      expect(_dayIcon(tester, _day(offset)), icon, reason: status.name);
      final legend = find.byKey(ThisWeekCard.legendKey(status));
      expect(legend, findsOneWidget, reason: status.name);
      expect(
        find.descendant(of: legend, matching: find.text(labels[status]!)),
        findsOneWidget,
      );
      // Rest is text only; every other status repeats its icon.
      expect(
        find.descendant(of: legend, matching: find.byType(Icon)),
        icon == null ? findsNothing : findsOneWidget,
        reason: status.name,
      );
    }
    for (final status in <TrainingDayStatus>[
      TrainingDayStatus.pending,
      TrainingDayStatus.noPlan,
    ]) {
      expect(find.byKey(ThisWeekCard.legendKey(status)), findsNothing);
    }
    expect(
      _text(tester, ThisWeekCard.summaryKey),
      '1 done · 1 partly done · 1 done differently · 1 not done · 1 trained',
    );
  });

  testWidgets('today with a planned workout not yet done is Pending', (
    tester,
  ) async {
    await _pump(
      tester,
      StubProgressFeatureRepository(
        weeklyPlans: <WeeklyPlanFacts>[
          _plan('r1', 'Hybrid block', {
            't-upper': [5],
          }),
        ],
        workouts: <ProgressWorkout>[_workout(4)],
      ),
    );

    expect(_dayIcon(tester, _day(4)), Icons.schedule);
    expect(
      find.descendant(
        of: find.byKey(ThisWeekCard.legendKey(TrainingDayStatus.pending)),
        matching: find.text('Pending'),
      ),
      findsOneWidget,
    );
    // Pending is not counted, so nothing is.
    expect(
      _text(tester, ThisWeekCard.summaryKey),
      'Nothing logged yet this week',
    );
  });

  testWidgets('without weekly Routines a day is Trained or No plan', (
    tester,
  ) async {
    await _pump(
      tester,
      StubProgressFeatureRepository(
        hasRotatingRoutine: true,
        workouts: <ProgressWorkout>[_workout(0)],
      ),
    );

    expect(_dayIcon(tester, _day(0)), Icons.add_circle_outline);
    for (var offset = 1; offset < 7; offset += 1) {
      expect(_dayIcon(tester, _day(offset)), isNull);
    }
    final noPlan = find.byKey(ThisWeekCard.legendKey(TrainingDayStatus.noPlan));
    expect(
      find.descendant(of: noPlan, matching: find.text('No plan')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: noPlan, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(_text(tester, ThisWeekCard.summaryKey), '1 trained');
  });

  group('the compared-Routines line', () {
    final plans = <WeeklyPlanFacts>[
      _plan('r2', 'upper/lower', {
        't-upper': [4],
      }),
      _plan('r1', 'Hybrid block', {
        't-lower': [1],
      }),
    ];

    testWidgets('names the compared Routines in name order', (tester) async {
      await _pump(tester, StubProgressFeatureRepository(weeklyPlans: plans));
      expect(
        _text(tester, ThisWeekCard.comparedKey),
        'Comparing Hybrid block · upper/lower',
      );
    });

    testWidgets('adds that only weekly Routines count', (tester) async {
      await _pump(
        tester,
        StubProgressFeatureRepository(
          weeklyPlans: plans,
          hasRotatingRoutine: true,
        ),
      );
      expect(
        _text(tester, ThisWeekCard.comparedKey),
        'Comparing Hybrid block · upper/lower. Weekly Routines only.',
      );
    });

    testWidgets('says only that with a rotating Routine and none compared', (
      tester,
    ) async {
      await _pump(
        tester,
        const StubProgressFeatureRepository(hasRotatingRoutine: true),
      );
      expect(
        _text(tester, ThisWeekCard.comparedKey),
        'Weekly Routines only.',
      );
    });

    testWidgets('is absent with neither', (tester) async {
      await _pump(
        tester,
        StubProgressFeatureRepository(workouts: <ProgressWorkout>[_workout(2)]),
      );
      expect(find.byKey(ThisWeekCard.daysKey), findsOneWidget);
      expect(find.byKey(ThisWeekCard.comparedKey), findsNothing);
    });
  });

  testWidgets('a week with nothing counted reads "Nothing logged yet"', (
    tester,
  ) async {
    // Monday morning: Monday's plan is still pending, the rest is ahead.
    await _pump(
      tester,
      StubProgressFeatureRepository(
        weeklyPlans: <WeeklyPlanFacts>[
          _plan('r1', 'Hybrid block', {
            't-lower': [1, 4],
          }),
        ],
      ),
      now: DateTime(2026, 10, 26, 8),
    );

    expect(
      _text(tester, ThisWeekCard.summaryKey),
      'Nothing logged yet this week',
    );
    expect(_dayIcon(tester, _day(0)), Icons.schedule);
    expect(_dayIcon(tester, _day(3)), Icons.event);
  });

  testWidgets('the day row is read as one label listing every day', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, mixedWeek);

    expect(
      tester.getSemantics(find.byKey(ThisWeekCard.daysKey)),
      matchesSemantics(
        label: 'This week: Monday partly done, Tuesday done differently, '
            'Wednesday not done, Thursday trained, Friday done, '
            'Saturday planned, Sunday rest.',
      ),
    );
    semantics.dispose();
  });

  testWidgets(
      'with no plan, no rotating Routine and nothing logged, the card offers '
      'Routines once', (tester) async {
    await _pump(tester, const StubProgressFeatureRepository());

    expect(find.text('Plan your week with a Routine'), findsOneWidget);
    expect(find.byKey(ThisWeekCard.routinesButtonKey), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byKey(ThisWeekCard.daysKey), findsNothing);
  });
}
