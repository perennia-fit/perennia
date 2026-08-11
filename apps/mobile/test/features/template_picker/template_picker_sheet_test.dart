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

  group('Template picker sheet accessibility', () {
    for (final brightness in Brightness.values) {
      testWidgets(
          'meets contrast, Android target, and label guidelines in '
          '${brightness.name}', (tester) async {
        await _setLargePhone(tester);
        await tester.pumpWidget(
          _testApp(
            brightness: brightness,
            upNext: _upNextRepository(),
            picker: _pickerRepository(
              routines: _threeRoutines(),
              templates: _fewTemplates(),
            ),
            home: const Scaffold(body: TemplatePickerSheet()),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }
  });

  testWidgets('shows the empty state teaching capture when nothing exists',
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
    expect(find.byKey(TemplatePickerSheet.upNextSectionKey), findsNothing);
    expect(find.byKey(TemplatePickerSheet.routinesSectionKey), findsNothing);
  });

  testWidgets(
      'a Template referenced by several Routines appears under each of '
      'them — reference semantics made visible', (tester) async {
    await _setLargePhone(tester);
    await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: _threeRoutines(),
        templates: const <TemplatePickerTemplateView>[],
      ),
    );

    for (final routineId in <String>['routine-1', 'routine-2', 'routine-3']) {
      await tester
          .tap(find.byKey(TemplatePickerSheet.routineHeaderKey(routineId)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.byKey(TemplatePickerSheet.routineEntryTileKey('entry-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(TemplatePickerSheet.routineEntryTileKey('entry-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(TemplatePickerSheet.routineEntryTileKey('entry-3')),
      findsOneWidget,
    );
  });

  testWidgets('a cadenced Routine shows its slot label', (tester) async {
    await _setLargePhone(tester);
    await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: _threeRoutines(),
        templates: const <TemplatePickerTemplateView>[],
      ),
    );

    await tester
        .tap(find.byKey(TemplatePickerSheet.routineHeaderKey('routine-1')));
    await _pumpUntilSettled(tester);

    expect(find.text('Monday'), findsOneWidget);
  });

  testWidgets(
      'tapping an All Templates row pops the sheet with a bare '
      'materialize request', (tester) async {
    await _setLargePhone(tester);
    final handle = await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: const <TemplatePickerRoutineView>[],
        templates: _fewTemplates(),
      ),
    );

    await tester.tap(
      find.byKey(TemplatePickerSheet.allTemplateTileKey('template-recent')),
    );
    await tester.pump();
    await tester.pump();

    final picked = await handle.future;
    expect(picked?.workoutTemplateId, 'template-recent');
    expect(picked?.routineId, isNull);
    expect(picked?.slot, isNull);
  });

  testWidgets(
      'tapping a Routine entry pops the sheet with the Routine and '
      'slot context', (tester) async {
    await _setLargePhone(tester);
    final handle = await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: _threeRoutines(),
        templates: const <TemplatePickerTemplateView>[],
      ),
    );

    await tester
        .tap(find.byKey(TemplatePickerSheet.routineHeaderKey('routine-1')));
    await _pumpUntilSettled(tester); // lets the ExpansionTile fully expand
    await tester
        .tap(find.byKey(TemplatePickerSheet.routineEntryTileKey('entry-1')));
    await tester.pump();
    await tester.pump();

    final picked = await handle.future;
    expect(picked?.workoutTemplateId, 'template-shared');
    expect(picked?.routineId, 'routine-1');
    expect(picked?.slot, DateTime.monday);
  });

  testWidgets('search filters the All Templates group', (tester) async {
    await _setLargePhone(tester);
    await _openSheetForResult(
      tester,
      upNext: _upNextRepository(suggestions: const <UpNextSuggestionView>[]),
      picker: _pickerRepository(
        routines: const <TemplatePickerRoutineView>[],
        templates: _fewTemplates(),
      ),
    );

    expect(
      find.byKey(TemplatePickerSheet.allTemplateTileKey('template-recent')),
      findsOneWidget,
    );
    expect(
      find.byKey(TemplatePickerSheet.allTemplateTileKey('template-old')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(TemplatePickerSheet.searchFieldKey),
      'legs',
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(TemplatePickerSheet.allTemplateTileKey('template-recent')),
      findsNothing,
    );
    expect(
      find.byKey(TemplatePickerSheet.allTemplateTileKey('template-old')),
      findsOneWidget,
    );
  });

  testWidgets(
      'customize opens a read-only preview and Start still produces the '
      'same materialize request as the default tap', (tester) async {
    await _setLargePhone(tester);
    final workoutTemplateRepository = StubWorkoutTemplateFeatureRepository(
      details: <String, WorkoutTemplateDetail>{
        'template-recent': WorkoutTemplateDetail(
          id: 'template-recent',
          name: 'Push A',
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
        templates: _fewTemplates(),
      ),
      workoutTemplateRepository: workoutTemplateRepository,
    );

    await tester.tap(
      find.byKey(
        TemplatePickerSheet.allTemplateCustomizeKey('template-recent'),
      ),
    );
    await _pumpUntilSettled(tester); // lets the nested preview sheet open

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

List<TemplatePickerTemplateView> _fewTemplates() {
  return <TemplatePickerTemplateView>[
    TemplatePickerTemplateView(
      id: 'template-recent',
      name: 'Push A',
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
            routineName: 'Weekly split',
            cadenceKind: CadenceKind.weekly,
            slot: DateTime.monday,
            cards: const <UpNextCardView>[
              UpNextCardView(
                routineEntryId: 'entry-up-next',
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
