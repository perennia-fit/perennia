import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/routine_cadence.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/features/home/controllers/home_controller.dart';
import 'package:perennia/features/template_picker/repositories/template_picker_feature_repository.dart';
import 'package:perennia/features/template_picker/widgets/template_picker_sheet.dart';
import 'package:perennia/features/up_next/repositories/up_next_feature_repository.dart';
import 'package:perennia/features/workout_templates/repositories/workout_template_feature_repository.dart';
import 'package:perennia/l10n/app_localizations.dart';
import 'package:perennia/theme/theme.dart';

import '../workout_templates/workout_template_test_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Routines sheet accessibility', () {
    for (final brightness in Brightness.values) {
      for (final level in <String>['list', 'routine']) {
        testWidgets(
            'the $level level meets contrast, Android target, and label '
            'guidelines in ${brightness.name}', (tester) async {
          await _setLargePhone(tester);
          await tester.pumpWidget(
            _testApp(
              brightness: brightness,
              upNext: _upNextRepository(),
              picker: _pickerRepository(
                routines: _threeRoutines(),
                templates: _templates(),
              ),
              home: const Scaffold(body: TemplatePickerSheet()),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
          if (level == 'routine') {
            await tester.tap(
                find.byKey(TemplatePickerSheet.routineRowKey('routine-1')));
            await tester.pump(const Duration(milliseconds: 50));
          }

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        });
      }
    }
  });

  testWidgets('with nothing to start, offers to create a routine',
      (tester) async {
    await _setLargePhone(tester);
    await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: const <TemplatePickerRoutineView>[],
        templates: const <TemplatePickerTemplateView>[],
      ),
    );

    expect(find.byKey(TemplatePickerSheet.emptyStateKey), findsOneWidget);
    expect(
      find.byKey(TemplatePickerSheet.createRoutineButtonKey),
      findsOneWidget,
    );
    expect(find.text('Create a routine'), findsOneWidget);
  });

  testWidgets(
      'lists Routines with what comes next, then the saved workouts no '
      'Routine holds, with no search and no repeated Up next section',
      (tester) async {
    await _setLargePhone(tester);
    await _openSheetForResult(
      tester,
      upNext: _upNextRepository(),
      picker: _pickerRepository(
        routines: _threeRoutines(),
        templates: _templates(),
      ),
    );

    expect(find.text('Routines'), findsOneWidget);
    expect(find.byKey(TemplatePickerSheet.manageButtonKey), findsOneWidget);
    expect(find.text('Weekly · Next: Push A'), findsOneWidget);
    expect(find.text('1 workout'), findsNWidgets(2));
    expect(find.byKey(TemplatePickerSheet.otherWorkoutsRowKey), findsOneWidget);
    expect(find.text('Not in a routine · 2 workouts'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(TemplatePickerSheet.backButtonKey), findsNothing);
  });

  testWidgets(
      'a Routine opens onto its workouts by day, marks Up next, and starts '
      'with the Routine and slot context', (tester) async {
    await _setLargePhone(tester);
    final handle = await _openSheetForResult(
      tester,
      upNext: _upNextRepository(),
      picker: _pickerRepository(
        routines: _threeRoutines(),
        templates: _templates(),
      ),
    );

    await tester
        .tap(find.byKey(TemplatePickerSheet.routineRowKey('routine-1')));
    await _pumpUntilSettled(tester);

    expect(find.text('Routine routine-1'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Up next · 5 exercises'), findsOneWidget);
    expect(
        find.byKey(TemplatePickerSheet.editRoutineButtonKey), findsOneWidget);
    expect(find.byKey(TemplatePickerSheet.backButtonKey), findsOneWidget);

    await tester
        .tap(find.byKey(TemplatePickerSheet.routineEntryTileKey('entry-1')));
    await tester.pump();
    await tester.pump();

    final picked = await handle.future;
    expect(picked?.workoutTemplateId, 'template-shared');
    expect(picked?.routineId, 'routine-1');
    expect(picked?.slot, DateTime.monday);
  });

  testWidgets('back returns from a Routine to the list', (tester) async {
    await _setLargePhone(tester);
    await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: _threeRoutines(),
        templates: _templates(),
      ),
    );

    await tester
        .tap(find.byKey(TemplatePickerSheet.routineRowKey('routine-2')));
    await _pumpUntilSettled(tester);
    expect(find.byKey(TemplatePickerSheet.routineRowKey('routine-1')),
        findsNothing);

    await tester.tap(find.byKey(TemplatePickerSheet.backButtonKey));
    await _pumpUntilSettled(tester);
    expect(find.byKey(TemplatePickerSheet.routineRowKey('routine-1')),
        findsOneWidget);
  });

  testWidgets(
      'with one Routine and no other saved workouts, opens straight onto '
      'that Routine', (tester) async {
    await _setLargePhone(tester);
    await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: _threeRoutines().take(1).toList(),
        templates: <TemplatePickerTemplateView>[_templates().first],
      ),
    );

    expect(
      find.byKey(TemplatePickerSheet.routineEntryTileKey('entry-1')),
      findsOneWidget,
    );
    expect(find.byKey(TemplatePickerSheet.backButtonKey), findsNothing);
    expect(
        find.byKey(TemplatePickerSheet.editRoutineButtonKey), findsOneWidget);
  });

  testWidgets(
      'a workout referenced by several Routines appears under each of '
      'them — reference semantics made visible', (tester) async {
    await _setLargePhone(tester);
    await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: _threeRoutines(),
        templates: _templates(),
      ),
    );

    for (final id in <String>['1', '2', '3']) {
      await tester
          .tap(find.byKey(TemplatePickerSheet.routineRowKey('routine-$id')));
      await _pumpUntilSettled(tester);
      expect(
        find.byKey(TemplatePickerSheet.routineEntryTileKey('entry-$id')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(TemplatePickerSheet.backButtonKey));
      await _pumpUntilSettled(tester);
    }
  });

  testWidgets('a workout with no exercises says so', (tester) async {
    await _setLargePhone(tester);
    await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: _threeRoutines(),
        templates: <TemplatePickerTemplateView>[
          TemplatePickerTemplateView(
            id: 'template-shared',
            name: 'Push A',
            exerciseCount: 0,
            updatedAt: DateTime.utc(2026, 7, 1),
          ),
        ],
      ),
    );

    await tester
        .tap(find.byKey(TemplatePickerSheet.routineRowKey('routine-2')));
    await _pumpUntilSettled(tester);

    expect(
      find.descendant(
        of: find.byKey(TemplatePickerSheet.routineEntryTileKey('entry-2')),
        matching: find.text('No exercises'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'an Other saved workouts pick pops a bare materialize request, '
      'without a Routine', (tester) async {
    await _setLargePhone(tester);
    final handle = await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: _threeRoutines(),
        templates: _templates(),
      ),
    );

    await tester.tap(find.byKey(TemplatePickerSheet.otherWorkoutsRowKey));
    await _pumpUntilSettled(tester);
    expect(
      find.byKey(TemplatePickerSheet.otherTemplateTileKey('template-shared')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(TemplatePickerSheet.otherTemplateTileKey('template-recent')),
    );
    await tester.pump();
    await tester.pump();

    final picked = await handle.future;
    expect(picked?.workoutTemplateId, 'template-recent');
    expect(picked?.routineId, isNull);
    expect(picked?.slot, isNull);
  });

  testWidgets(
      'preview opens a read-only look and Start still produces the same '
      'materialize request as the default tap', (tester) async {
    await _setLargePhone(tester);
    final workoutTemplateRepository = StubWorkoutTemplateFeatureRepository(
      details: <String, WorkoutTemplateDetail>{
        'template-recent': WorkoutTemplateDetail(
          id: 'template-recent',
          name: 'Upper B',
          exercises: <TemplateExerciseDetail>[],
        ),
      },
    );
    addTearDown(workoutTemplateRepository.close);
    final handle = await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: const <TemplatePickerRoutineView>[],
        templates: _templates().skip(1).toList(),
      ),
      workoutTemplateRepository: workoutTemplateRepository,
    );

    // Only other saved workouts exist, so the sheet opens straight on them.
    await tester.tap(
      find.byKey(
        TemplatePickerSheet.otherTemplatePreviewKey('template-recent'),
      ),
    );
    await _pumpUntilSettled(tester);

    expect(
      find.byKey(TemplatePickerPreviewSheet.startButtonKey),
      findsOneWidget,
    );

    await tester.tap(find.byKey(TemplatePickerPreviewSheet.startButtonKey));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final picked = await handle.future;
    expect(picked?.workoutTemplateId, 'template-recent');
    expect(picked?.routineId, isNull);
  });
}

List<TemplatePickerRoutineView> _threeRoutines() {
  TemplatePickerRoutineView routine(String id, {int? slot}) {
    return TemplatePickerRoutineView(
      routineId: id,
      routineName: 'Routine $id',
      cadenceKind: slot == null ? null : CadenceKind.weekly,
      entries: <TemplatePickerRoutineEntryView>[
        TemplatePickerRoutineEntryView(
          routineEntryId: 'entry-${id.split('-').last}',
          workoutTemplateId: 'template-shared',
          templateName: 'Push A',
          slot: slot,
        ),
      ],
    );
  }

  return <TemplatePickerRoutineView>[
    routine('routine-1', slot: DateTime.monday),
    routine('routine-2'),
    routine('routine-3'),
  ];
}

/// Push A sits in every Routine; Upper B and Legs A are in none.
List<TemplatePickerTemplateView> _templates() {
  return <TemplatePickerTemplateView>[
    TemplatePickerTemplateView(
      id: 'template-shared',
      name: 'Push A',
      exerciseCount: 5,
      updatedAt: DateTime.utc(2026, 7, 2),
    ),
    TemplatePickerTemplateView(
      id: 'template-recent',
      name: 'Upper B',
      exerciseCount: 3,
      updatedAt: DateTime.utc(2026, 7, 1),
    ),
    TemplatePickerTemplateView(
      id: 'template-old',
      name: 'Legs A',
      exerciseCount: 4,
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  ];
}

_StubUpNextFeatureRepository _upNextRepository({
  List<UpNextSuggestionView>? suggestions,
}) {
  return _StubUpNextFeatureRepository(
    suggestions ??
        <UpNextSuggestionView>[
          UpNextSuggestionView(
            routineId: 'routine-1',
            routineName: 'Routine routine-1',
            cadenceKind: CadenceKind.weekly,
            slot: DateTime.monday,
            cards: const <UpNextCardView>[
              UpNextCardView(
                routineEntryId: 'entry-1',
                workoutTemplateId: 'template-shared',
                templateName: 'Push A',
                isDone: false,
              ),
            ],
          ),
        ],
  );
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

_StubTemplatePickerFeatureRepository _pickerRepository({
  required List<TemplatePickerRoutineView> routines,
  required List<TemplatePickerTemplateView> templates,
}) {
  return _StubTemplatePickerFeatureRepository(
    routines: routines,
    templates: templates,
  );
}

class _StubTemplatePickerFeatureRepository
    implements TemplatePickerFeatureRepository {
  _StubTemplatePickerFeatureRepository({
    required this.routines,
    required this.templates,
  });

  final List<TemplatePickerRoutineView> routines;
  final List<TemplatePickerTemplateView> templates;

  @override
  Stream<List<TemplatePickerRoutineView>> watchRoutines() {
    return Stream<List<TemplatePickerRoutineView>>.value(routines);
  }

  @override
  Stream<List<TemplatePickerTemplateView>> watchAllTemplates() {
    return Stream<List<TemplatePickerTemplateView>>.value(templates);
  }
}

/// Holds the [Future] returned by `showTemplatePickerSheet` so a test can
/// tap through the sheet's UI first and only await the pick result once the
/// sheet has actually popped.
class _PickerHandle {
  Future<TemplatePickerResult?>? future;
}

Future<_PickerHandle> _openSheetForResult(
  WidgetTester tester, {
  required UpNextFeatureRepository upNext,
  required TemplatePickerFeatureRepository picker,
  WorkoutTemplateFeatureRepository? workoutTemplateRepository,
}) async {
  final handle = _PickerHandle();
  await tester.pumpWidget(
    _testApp(
      upNext: upNext,
      picker: picker,
      workoutTemplateRepository: workoutTemplateRepository,
      onOpen: (future) => handle.future = future,
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(find.text('Open'));
  await _pumpUntilSettled(tester);
  return handle;
}

/// Bounded alternative to `pumpAndSettle` for opening the modal sheet: pumps
/// a fixed number of short frames covering the modal transition and the
/// stub streams' first emission, instead of pumping until no frame is
/// scheduled (Windows flutter-test hygiene note in AGENTS.md — this file
/// hangs under `pumpAndSettle` for reasons not fully diagnosed, so it
/// deliberately never uses it).
Future<void> _pumpUntilSettled(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _testApp({
  required UpNextFeatureRepository upNext,
  required TemplatePickerFeatureRepository picker,
  WorkoutTemplateFeatureRepository? workoutTemplateRepository,
  void Function(Future<TemplatePickerResult?>)? onOpen,
  Brightness brightness = Brightness.light,
  Widget? home,
}) {
  return ProviderScope(
    overrides: [
      upNextFeatureRepositoryProvider.overrideWith((ref) => upNext),
      templatePickerFeatureRepositoryProvider.overrideWith((ref) => picker),
      if (workoutTemplateRepository != null)
        workoutTemplateFeatureRepositoryProvider
            .overrideWith((ref) => workoutTemplateRepository),
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
      home: home ??
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  child: const Text('Open'),
                  onPressed: () {
                    onOpen?.call(showTemplatePickerSheet(context));
                  },
                ),
              ),
            ),
          ),
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
