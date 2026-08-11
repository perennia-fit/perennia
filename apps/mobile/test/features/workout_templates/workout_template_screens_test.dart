import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/template_materialize/repositories/template_materialize_feature_repository.dart';
import 'package:perennia/features/workout_templates/repositories/workout_template_feature_repository.dart';
import 'package:perennia/features/workout_templates/widgets/workout_template_editor_screen.dart';
import 'package:perennia/features/workout_templates/widgets/workout_template_list_screen.dart';
import 'package:perennia/features/workout_templates/widgets/template_group_editor_sheet.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/app_localizations.dart';
import 'package:perennia/theme/theme.dart';

import 'workout_template_test_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Workout Template accessibility', () {
    for (final brightness in Brightness.values) {
      testWidgets(
        'list meets contrast, Android target, and label guidelines in ${brightness.name}',
        (tester) async {
          await _setLargePhone(tester);
          final repository = _repository();
          await tester.pumpWidget(
            _testApp(
              brightness: brightness,
              repository: repository,
              home: const WorkoutTemplateListScreen(),
            ),
          );
          await tester.pumpAndSettle();

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        },
      );

      testWidgets(
        'editor meets contrast, Android target, and label guidelines in ${brightness.name}',
        (tester) async {
          await _setLargePhone(tester);
          final repository = _repository();
          await tester.pumpWidget(
            _testApp(
              brightness: brightness,
              repository: repository,
              home: const WorkoutTemplateEditorScreen(templateId: _templateId),
            ),
          );
          await tester.pumpAndSettle();

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        },
      );

      testWidgets(
        'Prescription sheet meets contrast, Android target, and label guidelines in ${brightness.name}',
        (tester) async {
          await _setLargePhone(tester);
          final exercise = _detail().exercises.first;
          await tester.pumpWidget(
            _testApp(
              brightness: brightness,
              repository: _repository(),
              home: Scaffold(
                body: PrescriptionEditorSheet(
                  exercise: exercise,
                  prescription: exercise.prescriptions.first,
                  onSave: (_) async {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        },
      );

      testWidgets(
        'Group sheet meets contrast, Android target, and label guidelines in ${brightness.name}',
        (tester) async {
          await _setLargePhone(tester);
          final detail = _twoExerciseDetail();
          await tester.pumpWidget(
            _testApp(
              brightness: brightness,
              repository: _repository(detail: detail),
              home: Scaffold(
                body: TemplateGroupEditorSheet(
                  exercises: detail.exercises,
                  groups: detail.groups,
                  defaultColorHex: '#8A969E',
                  onSave: (_) async {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        },
      );
    }
  });

  testWidgets(
      'archive confirmation hides active template and restore returns it',
      (tester) async {
    await _setLargePhone(tester);
    final repository = _repository();
    await tester.pumpWidget(
      _testApp(
        repository: repository,
        home: const WorkoutTemplateListScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(WorkoutTemplateListScreen.archiveButtonKey(_templateId)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Archive Workout Template?'), findsOneWidget);
    await tester.tap(find.text('Archive Workout Template').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(WorkoutTemplateListScreen.archiveButtonKey(_templateId)),
      findsNothing,
    );
    await tester.tap(
      find.byKey(WorkoutTemplateListScreen.archivedToggleKey),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(WorkoutTemplateListScreen.restoreButtonKey(_templateId)),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await tester.tap(
      find.byKey(WorkoutTemplateListScreen.restoreButtonKey(_templateId)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(WorkoutTemplateListScreen.archiveButtonKey(_templateId)),
      findsOneWidget,
    );
  });

  testWidgets(
      'tapping Start materializes the Template with no Routine and no slot',
      (tester) async {
    await _setLargePhone(tester);
    final repository = _repository();
    final materializeRepository =
        _RecordingTemplateMaterializeFeatureRepository();
    await tester.pumpWidget(
      _testApp(
        repository: repository,
        materializeRepository: materializeRepository,
        home: const WorkoutTemplateListScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(WorkoutTemplateListScreen.startButtonKey(_templateId)),
    );
    await tester.pump();

    expect(materializeRepository.calls, hasLength(1));
    expect(materializeRepository.calls.single.workoutTemplateId, _templateId);
    expect(materializeRepository.calls.single.routineId, isNull);
    expect(materializeRepository.calls.single.slot, isNull);
  });

  testWidgets('archived templates offer no Start affordance', (tester) async {
    await _setLargePhone(tester);
    final repository = _repository();
    await tester.pumpWidget(
      _testApp(
        repository: repository,
        home: const WorkoutTemplateListScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(WorkoutTemplateListScreen.archivedToggleKey),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(WorkoutTemplateListScreen.startButtonKey('template-archived')),
      findsNothing,
    );
  });

  testWidgets('list creates a named Workout Template and opens its editor',
      (tester) async {
    await _setLargePhone(tester);
    final repository = _repository();
    await tester.pumpWidget(
      _testApp(
        repository: repository,
        home: const WorkoutTemplateListScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(WorkoutTemplateListScreen.createButtonKey),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(WorkoutTemplateListScreen.createNameFieldKey),
      'Intervals',
    );
    await tester.enterText(
      find.byKey(WorkoutTemplateListScreen.createNotesFieldKey),
      'Track lane',
    );
    await tester.tap(
      find.byKey(WorkoutTemplateListScreen.createSubmitButtonKey),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutTemplateEditorScreen), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(WorkoutTemplateEditorScreen.nameFieldKey),
          )
          .controller
          ?.text,
      'Intervals',
    );
  });

  testWidgets('editor saves template and per-entry standing notes',
      (tester) async {
    await _setLargePhone(tester);
    final repository = _repository();
    await tester.pumpWidget(
      _testApp(
        repository: repository,
        home: const WorkoutTemplateEditorScreen(templateId: _templateId),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(WorkoutTemplateEditorScreen.nameFieldKey),
      'Push B',
    );
    await tester.enterText(
      find.byKey(WorkoutTemplateEditorScreen.notesFieldKey),
      'Use the quiet rack',
    );
    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.saveDetailsButtonKey),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        WorkoutTemplateEditorScreen.editExerciseNotesButtonKey(_entryId),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(WorkoutTemplateEditorScreen.exerciseNotesFieldKey),
      'Pause on the chest',
    );
    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.saveExerciseNotesButtonKey),
    );
    await tester.pumpAndSettle();

    final updated = await repository.watchTemplate(_templateId).first;
    expect(updated?.name, 'Push B');
    expect(updated?.notes, 'Use the quiet rack');
    expect(updated?.exercises.first.notes, 'Pause on the chest');
  });

  testWidgets(
      'Prescription sheet adapts dimensions and saves fixed plan values',
      (tester) async {
    await _setLargePhone(tester);
    PrescriptionInput? saved;
    final exercise = _detail().exercises.first;
    await tester.pumpWidget(
      _testApp(
        repository: _repository(),
        home: Scaffold(
          body: PrescriptionEditorSheet(
            exercise: exercise,
            onSave: (input) async {
              saved = input;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
          DimensionId.load,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
          DimensionId.reps,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
          DimensionId.duration,
        ),
      ),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(
        WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
          DimensionId.load,
        ),
      ),
      '100',
    );
    await tester.enterText(
      find.byKey(
        WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
          DimensionId.reps,
        ),
      ),
      '5',
    );
    await tester.enterText(
      find.byKey(WorkoutTemplateEditorScreen.prescriptionRepeatFieldKey),
      '3',
    );
    await tester.enterText(
      find.byKey(WorkoutTemplateEditorScreen.prescriptionRestFieldKey),
      '120',
    );
    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.savePrescriptionButtonKey),
    );
    await tester.pumpAndSettle();

    expect(saved?.mode, TemplatePrescriptionMode.fixed);
    expect(saved?.repeat, 3);
    expect(saved?.restAfter, const Duration(seconds: 120));
    expect(saved?.values.load?.entered, '100');
    expect(saved?.values.reps?.entered, '5');
  });

  testWidgets('Prescription sheet saves copy-previous without fixed values',
      (tester) async {
    await _setLargePhone(tester);
    PrescriptionInput? saved;
    final exercise = _detail().exercises.first;
    await tester.pumpWidget(
      _testApp(
        repository: _repository(),
        home: Scaffold(
          body: PrescriptionEditorSheet(
            exercise: exercise,
            prescription: PrescriptionDetail(
              id: 'copy-previous',
              mode: TemplatePrescriptionMode.copyPrevious,
              values: LoggedSet.completion(),
              repeat: 1,
              restAfter: null,
            ),
            onSave: (input) async {
              saved = input;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
          DimensionId.load,
        ),
      ),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(WorkoutTemplateEditorScreen.prescriptionRepeatFieldKey),
      '4',
    );
    await tester.ensureVisible(
      find.byKey(WorkoutTemplateEditorScreen.savePrescriptionButtonKey),
    );
    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.savePrescriptionButtonKey),
    );
    await tester.pumpAndSettle();

    expect(saved?.mode, TemplatePrescriptionMode.copyPrevious);
    expect(saved?.repeat, 4);
    expect(saved?.values.isCompletionOnly, isTrue);
  });

  testWidgets('Prescription sheet blocks hard-invalid values', (tester) async {
    await _setLargePhone(tester);
    PrescriptionInput? saved;
    final exercise = _detail().exercises.first;
    await tester.pumpWidget(
      _testApp(
        repository: _repository(),
        home: Scaffold(
          body: PrescriptionEditorSheet(
            exercise: exercise,
            onSave: (input) async => saved = input,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(
        WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
          DimensionId.load,
        ),
      ),
      '-1',
    );
    await tester.enterText(
      find.byKey(
        WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
          DimensionId.reps,
        ),
      ),
      '5',
    );
    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.savePrescriptionButtonKey),
    );
    await tester.pumpAndSettle();

    expect(saved, isNull);
    expect(
      find.text(
        'Enter valid non-negative values, a repeat of at least 1, and optional non-negative rest.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('soft warning supports cancel and explicit save-anyway',
      (tester) async {
    await _setLargePhone(tester);
    PrescriptionInput? saved;
    final exercise = _detail().exercises.first;
    await tester.pumpWidget(
      _testApp(
        repository: _repository(),
        home: Scaffold(
          body: PrescriptionEditorSheet(
            exercise: exercise,
            onSave: (input) async => saved = input,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(
        WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
          DimensionId.load,
        ),
      ),
      '60',
    );
    await tester.enterText(
      find.byKey(
        WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
          DimensionId.reps,
        ),
      ),
      '5',
    );
    await tester.enterText(
      find.byKey(WorkoutTemplateEditorScreen.prescriptionRepeatFieldKey),
      '101',
    );

    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.savePrescriptionButtonKey),
    );
    await tester.pumpAndSettle();
    expect(find.text('Check Prescription values'), findsOneWidget);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(saved, isNull);

    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.savePrescriptionButtonKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save anyway'));
    await tester.pumpAndSettle();
    expect(saved?.repeat, 101);
  });

  testWidgets('duration and completion-only Prescriptions adapt their fields',
      (tester) async {
    await _setLargePhone(tester);
    PrescriptionInput? durationSaved;
    final durationExercise = TemplateExerciseDetail(
      id: 'entry-plank',
      exerciseId: 'plank',
      name: 'Plank',
      type: ExerciseType(const <DimensionId>[DimensionId.duration]),
      defaultLoadUnit: TrainingUnit.kilogram,
      loadMode: ExerciseLoadMode.added,
      prescriptions: const <PrescriptionDetail>[],
    );
    await tester.pumpWidget(
      _testApp(
        repository: _repository(),
        home: Scaffold(
          body: PrescriptionEditorSheet(
            exercise: durationExercise,
            onSave: (input) async => durationSaved = input,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final durationField = find.byKey(
      WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
        DimensionId.duration,
      ),
    );
    expect(durationField, findsOneWidget);
    expect(
      find.byKey(
        WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
          DimensionId.load,
        ),
      ),
      findsNothing,
    );
    expect(
        tester.widget<TextField>(durationField).decoration?.suffixText, 'sec');
    await tester.enterText(durationField, '90');
    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.savePrescriptionButtonKey),
    );
    await tester.pumpAndSettle();
    expect(durationSaved?.values.duration?.entered, '90');
    expect(durationSaved?.values.duration?.unit, TrainingUnit.second);

    PrescriptionInput? completionSaved;
    final completionExercise = TemplateExerciseDetail(
      id: 'entry-sauna',
      exerciseId: 'sauna',
      name: 'Sauna',
      type: ExerciseType.empty,
      defaultLoadUnit: TrainingUnit.kilogram,
      loadMode: ExerciseLoadMode.added,
      prescriptions: const <PrescriptionDetail>[],
    );
    await tester.pumpWidget(
      _testApp(
        repository: _repository(),
        home: Scaffold(
          body: PrescriptionEditorSheet(
            key: const ValueKey<String>('completion-prescription-sheet'),
            exercise: completionExercise,
            onSave: (input) async => completionSaved = input,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final dimension in DimensionId.values) {
      expect(
        find.byKey(
          WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(dimension),
        ),
        findsNothing,
      );
    }
    expect(find.text('Completion'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(WorkoutTemplateEditorScreen.savePrescriptionButtonKey),
    );
    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.savePrescriptionButtonKey),
    );
    await tester.pumpAndSettle();
    expect(completionSaved?.values.isCompletionOnly, isTrue);
  });

  testWidgets('new distance Prescription uses the imperial unit preference',
      (tester) async {
    await _setLargePhone(tester);
    PrescriptionInput? saved;
    final exercise = TemplateExerciseDetail(
      id: 'entry-run',
      exerciseId: 'run',
      name: 'Run',
      type: ExerciseType(const <DimensionId>[DimensionId.distance]),
      defaultLoadUnit: TrainingUnit.kilogram,
      loadMode: ExerciseLoadMode.added,
      prescriptions: const <PrescriptionDetail>[],
    );
    await tester.pumpWidget(
      _testApp(
        repository: _repository(),
        home: Scaffold(
          body: PrescriptionEditorSheet(
            exercise: exercise,
            unitSystem: UnitSystem.imperial,
            onSave: (input) async {
              saved = input;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final distanceField = find.byKey(
      WorkoutTemplateEditorScreen.prescriptionDimensionFieldKey(
        DimensionId.distance,
      ),
    );
    expect(
      tester.widget<TextField>(distanceField).decoration?.suffixText,
      'mi',
    );
    await tester.enterText(distanceField, '5');
    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.savePrescriptionButtonKey),
    );
    await tester.pumpAndSettle();

    expect(saved?.values.distance?.entered, '5');
    expect(saved?.values.distance?.unit, TrainingUnit.mile);
  });

  testWidgets('exercise notes remain scrollable with keyboard and large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 560);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      _testApp(
        repository: _repository(),
        textScaler: const TextScaler.linear(2),
        home: const WorkoutTemplateEditorScreen(templateId: _templateId),
      ),
    );
    await tester.pumpAndSettle();
    final notesButton = find.byKey(
      WorkoutTemplateEditorScreen.editExerciseNotesButtonKey(_entryId),
    );
    await tester.scrollUntilVisible(
      notesButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(notesButton);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final saveButton = find.byKey(
      WorkoutTemplateEditorScreen.saveExerciseNotesButtonKey,
    );
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    expect(saveButton, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Group sheet displays and submits persisted member order',
      (tester) async {
    await _setLargePhone(tester);
    final detail = _memberOrderDetail();
    TemplateGroupInput? saved;
    await tester.pumpWidget(
      _testApp(
        repository: _repository(detail: detail),
        home: Scaffold(
          body: TemplateGroupEditorSheet(
            exercises: detail.exercises,
            groups: detail.groups,
            group: detail.groups.single,
            defaultColorHex: '#8A969E',
            onSave: (input) async {
              saved = input;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rowTile = find.byKey(
      TemplateGroupEditorSheet.selectedMemberTileKey('entry-row'),
    );
    final benchTile = find.byKey(
      TemplateGroupEditorSheet.selectedMemberTileKey('entry-bench'),
    );
    expect(tester.getTopLeft(rowTile).dy,
        lessThan(tester.getTopLeft(benchTile).dy));

    final saveFinder = find.byKey(TemplateGroupEditorSheet.saveButtonKey);
    final saveButton = tester.widget<FilledButton>(saveFinder);
    expect(
      saveButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      tester.element(saveFinder).colors.save,
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.ensureVisible(saveFinder);
    await tester.tap(saveFinder);
    await tester.pumpAndSettle();
    expect(
      saved?.orderedTemplateExerciseIds,
      <String>['entry-row', 'entry-bench'],
    );
  });

  testWidgets('Group member menu moves a station accessibly before submit',
      (tester) async {
    await _setLargePhone(tester);
    final detail = _memberOrderDetail();
    TemplateGroupInput? saved;
    await tester.pumpWidget(
      _testApp(
        repository: _repository(detail: detail),
        home: Scaffold(
          body: TemplateGroupEditorSheet(
            exercises: detail.exercises,
            groups: detail.groups,
            group: detail.groups.single,
            defaultColorHex: '#8A969E',
            onSave: (input) async {
              saved = input;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(TemplateGroupEditorSheet.memberMenuButtonKey('entry-row')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(TemplateGroupEditorSheet.moveMemberLaterKey('entry-row')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getTopLeft(
            find.byKey(
              TemplateGroupEditorSheet.selectedMemberTileKey('entry-bench'),
            ),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(
                TemplateGroupEditorSheet.selectedMemberTileKey('entry-row'),
              ),
            )
            .dy,
      ),
    );

    final saveFinder = find.byKey(TemplateGroupEditorSheet.saveButtonKey);
    await tester.ensureVisible(saveFinder);
    await tester.tap(saveFinder);
    await tester.pumpAndSettle();
    expect(
      saved?.orderedTemplateExerciseIds,
      <String>['entry-bench', 'entry-row'],
    );
  });

  testWidgets('Group member drag handler reorders stations before submit',
      (tester) async {
    await _setLargePhone(tester);
    final detail = _memberOrderDetail();
    TemplateGroupInput? saved;
    await tester.pumpWidget(
      _testApp(
        repository: _repository(detail: detail),
        home: Scaffold(
          body: TemplateGroupEditorSheet(
            exercises: detail.exercises,
            groups: detail.groups,
            group: detail.groups.single,
            defaultColorHex: '#8A969E',
            onSave: (input) async {
              saved = input;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rowHandle = find.byKey(
      TemplateGroupEditorSheet.reorderMemberHandleKey('entry-row'),
    );
    final benchTile = find.byKey(
      TemplateGroupEditorSheet.selectedMemberTileKey('entry-bench'),
    );
    final dragHandle = tester.widget<ReorderableDragStartListener>(rowHandle);
    expect(dragHandle.index, 0);
    expect(dragHandle.enabled, isTrue);
    final reorderableList = tester.widget<ReorderableListView>(
      find.byKey(TemplateGroupEditorSheet.selectedMemberListKey),
    );
    reorderableList.onReorderItem!(0, 2);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(benchTile).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(
                TemplateGroupEditorSheet.selectedMemberTileKey('entry-row'),
              ),
            )
            .dy,
      ),
    );

    final saveFinder = find.byKey(TemplateGroupEditorSheet.saveButtonKey);
    await tester.ensureVisible(saveFinder);
    await tester.tap(saveFinder);
    await tester.pumpAndSettle();
    expect(
      saved?.orderedTemplateExerciseIds,
      <String>['entry-bench', 'entry-row'],
    );
  });

  testWidgets('Group sheet hard-rejects invalid rounds before saving',
      (tester) async {
    await _setLargePhone(tester);
    final detail = _twoExerciseDetail();
    TemplateGroupInput? saved;
    await tester.pumpWidget(
      _testApp(
        repository: _repository(detail: detail),
        home: Scaffold(
          body: TemplateGroupEditorSheet(
            exercises: detail.exercises,
            groups: detail.groups,
            defaultColorHex: '#8A969E',
            onSave: (input) async {
              saved = input;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(TemplateGroupEditorSheet.nameFieldKey),
      'A1 Pair',
    );
    await tester.enterText(
      find.byKey(TemplateGroupEditorSheet.roundsFieldKey),
      '0',
    );
    await tester.ensureVisible(
      find.byKey(TemplateGroupEditorSheet.saveButtonKey),
    );
    await tester.tap(find.byKey(TemplateGroupEditorSheet.saveButtonKey));
    await tester.pumpAndSettle();

    expect(saved, isNull);
    expect(
      find.text('Rounds must be a whole number of at least 1.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(TemplateGroupEditorSheet.roundsFieldKey),
      '3',
    );
    await tester.tap(find.byKey(TemplateGroupEditorSheet.saveButtonKey));
    await tester.pumpAndSettle();
    expect(saved?.rounds, 3);
    expect(
      saved?.orderedTemplateExerciseIds,
      <String>['entry-bench', 'entry-row'],
    );
  });

  testWidgets('editor creates a Group and renders edge plus textual cues',
      (tester) async {
    await _setLargePhone(tester);
    final detail = _twoExerciseDetail();
    final repository = _repository(detail: detail);
    await tester.pumpWidget(
      _testApp(
        repository: repository,
        home: const WorkoutTemplateEditorScreen(templateId: _templateId),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.addGroupButtonKey),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(TemplateGroupEditorSheet.nameFieldKey),
      'A1 Pair',
    );
    await tester.enterText(
      find.byKey(TemplateGroupEditorSheet.roundsFieldKey),
      '3',
    );
    await tester.ensureVisible(
      find.byKey(TemplateGroupEditorSheet.saveButtonKey),
    );
    await tester.tap(find.byKey(TemplateGroupEditorSheet.saveButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('A1 Pair'), findsWidgets);
    expect(find.text('A1 Pair · 3 rounds'), findsNWidgets(2));
    await tester.ensureVisible(
      find.byKey(
        WorkoutTemplateEditorScreen.groupColorKey('template-group-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('Group color for A1 Pair'), findsOneWidget);
    final stored = await repository.watchTemplate(_templateId).first;
    expect(stored?.groups.single.rounds, 3);
    expect(stored?.groups.single.members, hasLength(2));
  });

  testWidgets(
      'accessible Group actions reorder and dissolve without touching plan content',
      (tester) async {
    await _setLargePhone(tester);
    final detail = _groupedDetail();
    final repository = _repository(detail: detail);
    await tester.pumpWidget(
      _testApp(
        repository: repository,
        home: const WorkoutTemplateEditorScreen(templateId: _templateId),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.groupMenuButtonKey('group-a')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.moveGroupLaterKey('group-a')),
    );
    await tester.pumpAndSettle();
    var stored = await repository.watchTemplate(_templateId).first;
    expect(
      stored?.groups.map((group) => group.id),
      <String>['group-b', 'group-a'],
    );

    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.groupMenuButtonKey('group-a')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(WorkoutTemplateEditorScreen.dissolveGroupKey('group-a')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dissolve A1 Pair?'), findsOneWidget);
    final dissolveButtonFinder = find.widgetWithText(
      FilledButton,
      'Dissolve Group',
    );
    final dissolveButton = tester.widget<FilledButton>(dissolveButtonFinder);
    expect(
      dissolveButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      Theme.of(tester.element(dissolveButtonFinder)).colorScheme.error,
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(dissolveButtonFinder);
    await tester.pumpAndSettle();

    stored = await repository.watchTemplate(_templateId).first;
    expect(stored?.groups.map((group) => group.id), <String>['group-b']);
    expect(stored?.exercises, hasLength(4));
    expect(stored?.exercises.first.prescriptions, hasLength(1));
  });
}

/// Records materialize calls without resolving them, so a widget test can
/// assert the request shape without also having to render the full
/// [WorkoutScreen] provider graph the successful navigation would build.
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

Widget _testApp({
  required Widget home,
  required StubWorkoutTemplateFeatureRepository repository,
  TemplateMaterializeFeatureRepository? materializeRepository,
  Brightness brightness = Brightness.light,
  TextScaler? textScaler,
}) {
  return ProviderScope(
    overrides: [
      workoutTemplateFeatureRepositoryProvider.overrideWith(
        (ref) => repository,
      ),
      templateMaterializeFeatureRepositoryProvider.overrideWith(
        (ref) =>
            materializeRepository ??
            _RecordingTemplateMaterializeFeatureRepository(),
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
      builder: (context, child) {
        final scaler = textScaler;
        if (scaler == null) {
          return child!;
        }
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child!,
        );
      },
      onGenerateRoute: (settings) {
        if (settings.name == WorkoutTemplateEditorScreen.routeName &&
            settings.arguments is String) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => WorkoutTemplateEditorScreen(
              templateId: settings.arguments! as String,
            ),
          );
        }
        return null;
      },
      home: home,
    ),
  );
}

Future<void> _setLargePhone(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

StubWorkoutTemplateFeatureRepository _repository({
  WorkoutTemplateDetail? detail,
}) {
  final resolvedDetail = detail ?? _detail();
  final repository = StubWorkoutTemplateFeatureRepository(
    snapshot: WorkoutTemplateListSnapshot(
      active: <WorkoutTemplateSummary>[
        WorkoutTemplateSummary(
          id: _templateId,
          name: 'Push A',
          notes: 'Barbell day',
          exerciseCount: resolvedDetail.exercises.length,
          isArchived: false,
        ),
      ],
      archived: const <WorkoutTemplateSummary>[
        WorkoutTemplateSummary(
          id: 'template-archived',
          name: 'Old Push',
          exerciseCount: 2,
          isArchived: true,
        ),
      ],
    ),
    details: <String, WorkoutTemplateDetail>{_templateId: resolvedDetail},
  );
  addTearDown(repository.close);
  return repository;
}

WorkoutTemplateDetail _detail() {
  return WorkoutTemplateDetail(
    id: _templateId,
    name: 'Push A',
    notes: 'Barbell day',
    exercises: <TemplateExerciseDetail>[
      TemplateExerciseDetail(
        id: _entryId,
        exerciseId: 'bench-press',
        name: 'Bench Press',
        type: ExerciseType(
          const <DimensionId>[DimensionId.load, DimensionId.reps],
        ),
        defaultLoadUnit: TrainingUnit.kilogram,
        loadMode: ExerciseLoadMode.added,
        notes: 'Use safeties',
        prescriptions: <PrescriptionDetail>[
          PrescriptionDetail(
            id: _prescriptionId,
            mode: TemplatePrescriptionMode.fixed,
            values: LoggedSet.fromValues(
              const <SetDimensionValue>[
                SetDimensionValue(
                  dimension: DimensionId.load,
                  entered: '90',
                  unit: TrainingUnit.kilogram,
                ),
                SetDimensionValue(
                  dimension: DimensionId.reps,
                  entered: '5',
                  unit: TrainingUnit.repetition,
                ),
              ],
            ),
            repeat: 3,
            restAfter: const Duration(seconds: 120),
          ),
        ],
      ),
    ],
  );
}

WorkoutTemplateDetail _twoExerciseDetail() {
  final detail = _detail();
  return detail.copyWith(
    exercises: <TemplateExerciseDetail>[
      detail.exercises.first,
      _templateExercise('entry-row', 'barbell-row', 'Barbell Row'),
    ],
  );
}

WorkoutTemplateDetail _memberOrderDetail() {
  final detail = _twoExerciseDetail();
  return detail.copyWith(
    groups: <TemplateGroupDetail>[
      TemplateGroupDetail(
        id: 'group-order',
        name: 'Ordered Circuit',
        colorHex: '#2F6FED',
        rounds: 3,
        members: const <TemplateGroupMemberDetail>[
          TemplateGroupMemberDetail(templateExerciseId: 'entry-row'),
          TemplateGroupMemberDetail(templateExerciseId: 'entry-bench'),
        ],
      ),
    ],
  );
}

WorkoutTemplateDetail _groupedDetail() {
  final detail = _detail();
  return detail.copyWith(
    exercises: <TemplateExerciseDetail>[
      detail.exercises.first,
      _templateExercise('entry-row', 'barbell-row', 'Barbell Row'),
      _templateExercise('entry-squat', 'back-squat', 'Back Squat'),
      _templateExercise('entry-lunge', 'walking-lunge', 'Walking Lunge'),
    ],
    groups: <TemplateGroupDetail>[
      TemplateGroupDetail(
        id: 'group-a',
        name: 'A1 Pair',
        colorHex: '#2F6FED',
        rounds: 3,
        members: const <TemplateGroupMemberDetail>[
          TemplateGroupMemberDetail(templateExerciseId: 'entry-bench'),
          TemplateGroupMemberDetail(templateExerciseId: 'entry-row'),
        ],
      ),
      TemplateGroupDetail(
        id: 'group-b',
        name: 'B1 Pair',
        colorHex: '#5FB05C',
        rounds: 2,
        members: const <TemplateGroupMemberDetail>[
          TemplateGroupMemberDetail(templateExerciseId: 'entry-squat'),
          TemplateGroupMemberDetail(templateExerciseId: 'entry-lunge'),
        ],
      ),
    ],
  );
}

TemplateExerciseDetail _templateExercise(
  String id,
  String exerciseId,
  String name,
) {
  return TemplateExerciseDetail(
    id: id,
    exerciseId: exerciseId,
    name: name,
    type: ExerciseType(const <DimensionId>[DimensionId.reps]),
    defaultLoadUnit: TrainingUnit.kilogram,
    loadMode: ExerciseLoadMode.added,
    prescriptions: const <PrescriptionDetail>[],
  );
}

const _templateId = 'template-push-a';
const _entryId = 'entry-bench';
const _prescriptionId = 'prescription-bench';
