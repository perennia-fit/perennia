import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/routine_cadence.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/features/home/controllers/home_controller.dart';
import 'package:perennia/features/home/repositories/home_repository.dart';
import 'package:perennia/features/home/widgets/workout_screen.dart';
import 'package:perennia/features/template_materialize/repositories/template_materialize_feature_repository.dart';
import 'package:perennia/features/up_next/repositories/up_next_feature_repository.dart';
import 'package:perennia/features/up_next/widgets/up_next_strip.dart';
import 'package:perennia/l10n/app_localizations.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Up-next strip accessibility', () {
    for (final brightness in Brightness.values) {
      testWidgets(
        'meets contrast, Android target, and label guidelines in '
        '${brightness.name}',
        (tester) async {
          await _setLargePhone(tester);
          final repository = _repositoryWith(<UpNextSuggestionView>[
            _weeklySuggestion(doneSecondCard: true),
          ]);
          await tester.pumpWidget(
            _testApp(
              brightness: brightness,
              repository: repository,
              home: const Scaffold(body: UpNextStrip()),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        },
      );
    }
  });

  testWidgets('renders nothing when there are no cadenced Routines',
      (tester) async {
    await _setLargePhone(tester);
    final repository = _repositoryWith(const <UpNextSuggestionView>[]);
    await tester.pumpWidget(
      _testApp(
        repository: repository,
        home: const Scaffold(body: UpNextStrip()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(UpNextStrip.sectionKey), findsNothing);
  });

  testWidgets(
      'shows a not-done card and a ticked done card, remaining session first',
      (tester) async {
    await _setLargePhone(tester);
    final suggestion = _weeklySuggestion(doneSecondCard: true);
    final repository = _repositoryWith(<UpNextSuggestionView>[suggestion]);
    await tester.pumpWidget(
      _testApp(
        repository: repository,
        home: const Scaffold(body: UpNextStrip()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(UpNextStrip.sectionKey), findsOneWidget);
    expect(
      find.byKey(UpNextStrip.cardKey('routine-1', 'template-remaining')),
      findsOneWidget,
    );
    expect(
      find.byKey(UpNextStrip.doneKey('routine-1', 'template-done')),
      findsOneWidget,
    );
    // The not-done card stays tappable; the done card is not a Start
    // affordance.
    expect(
      find.byKey(UpNextStrip.cardKey('routine-1', 'template-done')),
      findsNothing,
    );
  });

  testWidgets('tapping a suggested card materializes with the Routine slot',
      (tester) async {
    await _setLargePhone(tester);
    final suggestion = _weeklySuggestion(doneSecondCard: false);
    final repository = _repositoryWith(<UpNextSuggestionView>[suggestion]);
    final materializeRepository =
        _RecordingTemplateMaterializeFeatureRepository();
    await tester.pumpWidget(
      _testApp(
        repository: repository,
        materializeRepository: materializeRepository,
        home: const Scaffold(body: UpNextStrip()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(
      find.byKey(UpNextStrip.cardKey('routine-1', 'template-remaining')),
    );
    await tester.pump();

    expect(materializeRepository.calls, hasLength(1));
    expect(
      materializeRepository.calls.single.workoutTemplateId,
      'template-remaining',
    );
    expect(materializeRepository.calls.single.routineId, 'routine-1');
    expect(materializeRepository.calls.single.slot, DateTime.monday);
  });

  testWidgets(
      'tapping a suggested card materializes and lands on the Workout '
      'screen with the returned id — the ≤ 2-taps covenant', (tester) async {
    await _setLargePhone(tester);
    final suggestion = _weeklySuggestion(doneSecondCard: false);
    final repository = _repositoryWith(<UpNextSuggestionView>[suggestion]);
    final materializeRepository =
        _ResolvingTemplateMaterializeFeatureRepository('workout-materialized');
    await tester.pumpWidget(
      _testApp(
        repository: repository,
        materializeRepository: materializeRepository,
        homeRepository: StubHomeRepository(),
        home: const Scaffold(body: UpNextStrip()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(
      find.byKey(UpNextStrip.cardKey('routine-1', 'template-remaining')),
    );
    // A pushed MaterialPageRoute animates in; a bounded pump loop (not
    // pumpAndSettle) waits it out without risking a hang on any
    // perpetually-scheduling widget underneath (Windows flutter-test
    // hygiene note in AGENTS.md).
    await _pumpUntilFound(tester, find.byType(WorkoutScreen));

    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(materializeRepository.calls, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

UpNextSuggestionView _weeklySuggestion({required bool doneSecondCard}) {
  return UpNextSuggestionView(
    routineId: 'routine-1',
    routineName: 'Weekly split',
    cadenceKind: CadenceKind.weekly,
    slot: DateTime.monday,
    cards: <UpNextCardView>[
      const UpNextCardView(
        routineEntryId: 'entry-remaining',
        workoutTemplateId: 'template-remaining',
        templateName: 'Push A',
        isDone: false,
      ),
      UpNextCardView(
        routineEntryId: 'entry-done',
        workoutTemplateId: 'template-done',
        templateName: 'Swim Drills',
        isDone: doneSecondCard,
      ),
    ],
  );
}

_StubUpNextFeatureRepository _repositoryWith(
  List<UpNextSuggestionView> suggestions,
) {
  return _StubUpNextFeatureRepository(suggestions);
}

class _StubUpNextFeatureRepository implements UpNextFeatureRepository {
  _StubUpNextFeatureRepository(this._suggestions);

  final List<UpNextSuggestionView> _suggestions;

  @override
  Stream<List<UpNextSuggestionView>> watchSuggestions(
    TrainingDayDate selectedDate,
  ) {
    return Stream<List<UpNextSuggestionView>>.value(_suggestions);
  }
}

/// Records materialize calls without resolving them, mirroring the M34-01
/// widget-test convention (workout_template_screens_test.dart) so a test can
/// assert the request shape without rendering the full WorkoutScreen
/// provider graph.
class _RecordingTemplateMaterializeFeatureRepository
    implements TemplateMaterializeFeatureRepository {
  final List<
      ({
        String workoutTemplateId,
        String? routineId,
        int? slot,
      })> calls = <({String workoutTemplateId, String? routineId, int? slot})>[];
  final Completer<String> _completer = Completer<String>();

  @override
  Future<String> materializeTemplate({
    required String workoutTemplateId,
    String? routineId,
    int? slot,
  }) {
    calls.add(
      (workoutTemplateId: workoutTemplateId, routineId: routineId, slot: slot),
    );
    return _completer.future;
  }
}

/// Records materialize calls and resolves immediately with a fixed
/// Workout id, so a test can assert the post-materialize navigation without
/// a real database.
class _ResolvingTemplateMaterializeFeatureRepository
    implements TemplateMaterializeFeatureRepository {
  _ResolvingTemplateMaterializeFeatureRepository(this._workoutId);

  final String _workoutId;
  final List<
      ({
        String workoutTemplateId,
        String? routineId,
        int? slot,
      })> calls = <({String workoutTemplateId, String? routineId, int? slot})>[];

  @override
  Future<String> materializeTemplate({
    required String workoutTemplateId,
    String? routineId,
    int? slot,
  }) async {
    calls.add(
      (workoutTemplateId: workoutTemplateId, routineId: routineId, slot: slot),
    );
    return _workoutId;
  }
}

Widget _testApp({
  required Widget home,
  required UpNextFeatureRepository repository,
  TemplateMaterializeFeatureRepository? materializeRepository,
  HomeRepository? homeRepository,
  Brightness brightness = Brightness.light,
}) {
  return ProviderScope(
    overrides: [
      upNextFeatureRepositoryProvider.overrideWith((ref) => repository),
      templateMaterializeFeatureRepositoryProvider.overrideWith(
        (ref) =>
            materializeRepository ??
            _RecordingTemplateMaterializeFeatureRepository(),
      ),
      if (homeRepository != null)
        homeRepositoryProvider.overrideWith((ref) => homeRepository),
      selectedTrainingDayProvider.overrideWith(
        () => _FixedTrainingDayController(
          const TrainingDayDate(year: 2026, month: 7, day: 6),
        ),
      ),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

class _FixedTrainingDayController extends SelectedTrainingDayController {
  _FixedTrainingDayController(this._date);

  final TrainingDayDate _date;

  @override
  TrainingDayDate build() => _date;
}

Future<void> _setLargePhone(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Bounded alternative to `pumpAndSettle` for trees that may contain a
/// perpetually-scheduling widget (a live stream, a timer): pumps a fixed
/// number of short frames and stops as soon as [finder] resolves, instead of
/// pumping until nothing is scheduled (which never happens for those trees).
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
}) async {
  for (var attempt = 0; attempt < maxPumps; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}
