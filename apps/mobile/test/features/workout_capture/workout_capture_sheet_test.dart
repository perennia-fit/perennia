import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/routine_cadence.dart';
import 'package:perennia/domain/training/set_validation.dart';
import 'package:perennia/domain/training/workout_capture.dart';
import 'package:perennia/features/workout_capture/repositories/workout_capture_feature_repository.dart';
import 'package:perennia/features/workout_capture/widgets/workout_capture_sheet.dart';
import 'package:perennia/l10n/app_localizations.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  testWidgets(
      'prefills, submits exact warning tokens, and guards duplicate submit',
      (tester) async {
    final warning = _issue(
      rule: 'capture_warning',
      message: 'One captured value is unusual.',
      sourcePath: 'exercises[0]',
    );
    final validation = WorkoutCaptureValidationResult(
      warnings: <WorkoutCaptureValidationIssue>[warning],
    );
    final saveCompleter = Completer<WorkoutCaptureSaveResult>();
    final repository = _FakeWorkoutCaptureRepository(
      preview: _preview(validation: validation),
      routines: const <WorkoutCaptureRoutineOption>[_weekly],
      pendingSave: saveCompleter,
    );
    await _pumpLauncher(tester, repository: repository);
    await _openCapture(tester);

    final nameField = tester.widget<TextField>(
      find.byKey(WorkoutCaptureSheet.nameFieldKey),
    );
    expect(nameField.controller?.text, 'Bench Press + Row');
    expect(
      find.byKey(
        WorkoutCaptureSheet.validationIssueKey(
          warning: true,
          field: warning.fieldPath,
          rule: warning.rule,
          index: 0,
        ),
      ),
      findsOneWidget,
    );
    expect(_saveButton(tester).onPressed, isNull);

    await _selectRoutine(tester, 'weekly');
    await _selectSlot(tester, 2);
    await _acceptWarnings(tester);
    final saveButton = find.byKey(WorkoutCaptureSheet.saveButtonKey);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    await tester.tap(saveButton, warnIfMissed: false);
    await tester.pump();

    expect(repository.saveRequests, hasLength(1));
    expect(
      repository.saveRequests.single.placement,
      isA<WorkoutCaptureCadenceSlotPlacement>()
          .having((placement) => placement.routineId, 'routineId', 'weekly')
          .having((placement) => placement.slot, 'slot', 2),
    );
    expect(
      repository.saveRequests.single.acknowledgedWarningTokens,
      validation.warningAcknowledgementTokenSet,
    );

    saveCompleter.complete(_savedResult);
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutCaptureSheet), findsNothing);
  });

  testWidgets('blocks close, back, barrier, and drag while save is pending',
      (tester) async {
    final saveCompleter = Completer<WorkoutCaptureSaveResult>();
    final repository = _FakeWorkoutCaptureRepository(
      preview: _preview(),
      pendingSave: saveCompleter,
    );
    await _pumpLauncher(tester, repository: repository);
    await _openCapture(tester);

    await _tapSave(tester);
    expect(repository.saveRequests, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(WorkoutCaptureSheet.closeButtonKey),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(WorkoutCaptureSheet.closeButtonKey),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(find.byType(WorkoutCaptureSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(WorkoutCaptureSheet), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.byType(WorkoutCaptureSheet), findsOneWidget);

    final sheetTop = tester.getTopLeft(
      find.byKey(WorkoutCaptureSheet.sheetKey),
    );
    await tester.dragFrom(sheetTop + const Offset(20, 2), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutCaptureSheet), findsOneWidget);

    saveCompleter.complete(_savedResult);
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutCaptureSheet), findsNothing);
  });

  testWidgets('reactive Routine removal preserves intent and requires a choice',
      (tester) async {
    final routines = StreamController<List<WorkoutCaptureRoutineOption>>();
    addTearDown(routines.close);
    final repository = _FakeWorkoutCaptureRepository(
      preview: _preview(),
      routineStream: routines.stream,
    );
    await _pumpLauncher(tester, repository: repository);
    await _openCapture(tester, settle: false);
    routines.add(const <WorkoutCaptureRoutineOption>[_rotationFive]);
    await tester.pumpAndSettle();
    await _selectRoutine(tester, 'rotation');
    await _selectSlot(tester, 4);

    routines.add(const <WorkoutCaptureRoutineOption>[]);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The selected Routine is no longer available. '
        'Choose another Routine or None.',
      ),
      findsOneWidget,
    );
    expect(find.text('Rotation - choose slot'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);

    await _selectRoutine(tester, 'none');
    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(
      repository.saveRequests.single.placement,
      isA<WorkoutCaptureNoPlacement>(),
    );
  });

  testWidgets('Cadence shrink clears the invalid slot and can be corrected',
      (tester) async {
    final routines = StreamController<List<WorkoutCaptureRoutineOption>>();
    addTearDown(routines.close);
    final repository = _FakeWorkoutCaptureRepository(
      preview: _preview(),
      routineStream: routines.stream,
    );
    await _pumpLauncher(tester, repository: repository);
    await _openCapture(tester, settle: false);
    routines.add(const <WorkoutCaptureRoutineOption>[_rotationFive]);
    await tester.pumpAndSettle();
    await _selectRoutine(tester, 'rotation');
    await _selectSlot(tester, 5);

    routines.add(const <WorkoutCaptureRoutineOption>[
      WorkoutCaptureRoutineOption(
        id: 'rotation',
        name: 'Rotation',
        cadenceKind: CadenceKind.rotating,
        slotCount: 3,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      find.text(
        "This Routine's Cadence changed. Review the placement and choose an "
        'available slot.',
      ),
      findsOneWidget,
    );
    expect(find.text('Choose a slot'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);

    await _selectSlot(tester, 2);
    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(
      repository.saveRequests.single.placement,
      isA<WorkoutCaptureCadenceSlotPlacement>()
          .having((placement) => placement.slot, 'slot', 2),
    );
  });

  testWidgets('unexpected save failures are inline accessible live regions',
      (tester) async {
    final repository = _FakeWorkoutCaptureRepository(
      preview: _preview(),
      saveError: StateError('offline storage failed'),
    );
    await _pumpLauncher(tester, repository: repository);
    final semantics = tester.ensureSemantics();
    await _openCapture(tester);
    await _tapSave(tester);
    await tester.pumpAndSettle();

    final failure = find.byKey(WorkoutCaptureSheet.saveFailureKey);
    expect(failure, findsOneWidget);
    await tester.ensureVisible(failure);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(failure).label,
      'The Workout Template could not be saved. '
      'Review your choices and try again.',
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(WorkoutCaptureSheet), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('closing and reopening reads a fresh auto-disposed preview',
      (tester) async {
    final repository = _FakeWorkoutCaptureRepository(preview: _preview());
    await _pumpLauncher(tester, repository: repository);
    await _openCapture(tester);
    expect(_nameText(tester), 'Bench Press + Row');

    await tester.tap(find.byKey(WorkoutCaptureSheet.closeButtonKey));
    await tester.pumpAndSettle();
    repository.previewValue = _preview(suggestedName: 'Updated workout facts');
    await _openCapture(tester);

    expect(_nameText(tester), 'Updated workout facts');
    expect(repository.previewCalls, 2);
  });

  testWidgets('slot edit clears commit-time validation and resubmits',
      (tester) async {
    final error = _issue(
      rule: 'cadence_slot_invalid',
      message: 'The Cadence changed before capture.',
      sourcePath: 'placement',
    );
    var attempts = 0;
    final repository = _FakeWorkoutCaptureRepository(
      preview: _preview(),
      routines: const <WorkoutCaptureRoutineOption>[_rotationFive],
      saveHandler: (request) async {
        attempts += 1;
        if (attempts == 1) {
          throw WorkoutCaptureValidationException(
            WorkoutCaptureValidationResult(
              errors: <WorkoutCaptureValidationIssue>[error],
            ),
          );
        }
        return _savedResult;
      },
    );
    await _pumpLauncher(tester, repository: repository);
    await _openCapture(tester);
    await _selectRoutine(tester, 'rotation');
    await _selectSlot(tester, 3);
    await _tapSave(tester);
    await tester.pumpAndSettle();
    final errorKey = WorkoutCaptureSheet.validationIssueKey(
      warning: false,
      field: error.fieldPath,
      rule: error.rule,
      index: 0,
    );
    expect(find.byKey(errorKey), findsOneWidget);

    await _selectSlot(tester, 2);
    expect(find.byKey(errorKey), findsNothing);
    expect(_saveButton(tester).onPressed, isNotNull);
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(WorkoutCaptureSheet), findsNothing);
  });

  testWidgets('duplicate validation rules receive stable unique row keys',
      (tester) async {
    final first = _issue(
      rule: 'same_rule',
      message: 'First occurrence.',
      sourcePath: 'exercises[0]',
    );
    final second = _issue(
      rule: 'same_rule',
      message: 'Second occurrence.',
      sourcePath: 'exercises[1]',
    );
    final repository = _FakeWorkoutCaptureRepository(
      preview: _preview(
        validation: WorkoutCaptureValidationResult(
          errors: <WorkoutCaptureValidationIssue>[first, second],
        ),
      ),
    );
    await _pumpLauncher(tester, repository: repository);
    await _openCapture(tester);

    for (final (index, issue) in <WorkoutCaptureValidationIssue>[
      first,
      second,
    ].indexed) {
      expect(
        find.byKey(
          WorkoutCaptureSheet.validationIssueKey(
            warning: false,
            field: issue.fieldPath,
            rule: issue.rule,
            index: index,
          ),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('large rotating Cadence uses a lazy list and direct slot entry',
      (tester) async {
    const hugeRotation = WorkoutCaptureRoutineOption(
      id: 'huge',
      name: 'Long horizon',
      cadenceKind: CadenceKind.rotating,
      slotCount: 100000,
    );
    final repository = _FakeWorkoutCaptureRepository(
      preview: _preview(),
      routines: const <WorkoutCaptureRoutineOption>[hugeRotation],
    );
    await _pumpLauncher(tester, repository: repository);
    await _openCapture(tester);
    await _selectRoutine(tester, 'huge');
    await tester.tap(find.byKey(WorkoutCaptureSheet.slotFieldKey));
    await tester.pumpAndSettle();

    expect(find.byKey(WorkoutCaptureSheet.slotPickerKey), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(50));
    await tester.enterText(
      find.byKey(WorkoutCaptureSheet.slotNumberFieldKey),
      '99999',
    );
    await tester.tap(find.byKey(WorkoutCaptureSheet.slotApplyButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Position 99999'), findsOneWidget);

    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(
      repository.saveRequests.single.placement,
      isA<WorkoutCaptureCadenceSlotPlacement>()
          .having((placement) => placement.slot, 'slot', 99999),
    );
  });

  testWidgets('uses plural count semantics once and DESIGN form styles',
      (tester) async {
    final warning = _issue(
      rule: 'warning',
      message: 'Review this value.',
      sourcePath: 'exercises[0]',
    );
    final error = _issue(
      rule: 'hard_error',
      message: 'Correct this value.',
      sourcePath: 'exercises[1]',
    );
    final repository = _FakeWorkoutCaptureRepository(
      preview: _preview(
        exerciseCount: 1,
        setCount: 0,
        groupCount: 2,
        validation: WorkoutCaptureValidationResult(
          errors: <WorkoutCaptureValidationIssue>[error],
          warnings: <WorkoutCaptureValidationIssue>[warning],
        ),
      ),
    );
    await _pumpLauncher(tester, repository: repository);
    final semantics = tester.ensureSemantics();
    await _openCapture(tester);

    expect(
      find.bySemanticsLabel(
        'Capture preview: 1 exercise, no sets, and 2 groups.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^1 exercise$')),
      findsNothing,
    );
    final nameFinder = find.byKey(WorkoutCaptureSheet.nameFieldKey);
    final nameField = tester.widget<TextField>(nameFinder);
    expect(nameField.decoration?.labelText, isNull);
    expect(nameField.decoration?.filled, isTrue);
    final border = nameField.decoration?.enabledBorder as OutlineInputBorder;
    expect(border.borderRadius, AppRadii.cardMd);
    expect(tester.getSemantics(nameFinder).label, contains('Workout Template'));
    expect(
      tester
          .getSemantics(find.byKey(WorkoutCaptureSheet.routineFieldKey))
          .label,
      contains('Add to Routine'),
    );

    final saveShape = _saveButton(tester)
        .style
        ?.shape
        ?.resolve(const <WidgetState>{}) as RoundedRectangleBorder;
    expect(saveShape.borderRadius, AppRadii.cardMd);
    final warningIcon = tester.widget<Icon>(
      find.byIcon(Icons.warning_amber_rounded),
    );
    final context = tester.element(find.byType(WorkoutCaptureSheet));
    expect(nameField.decoration?.errorStyle?.color, context.colors.textPrimary);
    expect(warningIcon.color, context.colors.textSecondary);
    expect(warningIcon.color, isNot(context.colors.record));
    expect(warningIcon.color, isNot(Theme.of(context).colorScheme.error));
    final errorIcon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(errorIcon.color, context.colors.textPrimary);
    expect(errorIcon.color, isNot(Theme.of(context).colorScheme.error));
    semantics.dispose();
  });

  for (final brightness in <Brightness>[
    Brightness.light,
    Brightness.dark,
  ]) {
    testWidgets(
        '360x560 keyboard, warning, long placement, and pending save are accessible in $brightness',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 560);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final warning = _issue(
        rule: 'warning',
        message: 'One captured prescription deserves a careful review.',
        sourcePath: 'exercises[0].prescriptions[0]',
      );
      final saveCompleter = Completer<WorkoutCaptureSaveResult>();
      const longRoutine = WorkoutCaptureRoutineOption(
        id: 'long-routine',
        name: 'A very long hybrid training Routine name for a compact phone',
        cadenceKind: CadenceKind.rotating,
        slotCount: 40,
      );
      final repository = _FakeWorkoutCaptureRepository(
        preview: _preview(
          validation: WorkoutCaptureValidationResult(
            warnings: <WorkoutCaptureValidationIssue>[warning],
          ),
        ),
        routines: const <WorkoutCaptureRoutineOption>[longRoutine],
        pendingSave: saveCompleter,
      );
      await _pumpLauncher(
        tester,
        repository: repository,
        brightness: brightness,
        textScale: 2,
      );
      final semantics = tester.ensureSemantics();
      await _openCapture(tester);
      await _selectRoutine(tester, 'long-routine');
      await _selectSlot(tester, 2);
      await _acceptWarnings(tester);

      final nameField = find.byKey(WorkoutCaptureSheet.nameFieldKey);
      await tester.ensureVisible(nameField);
      await tester.pumpAndSettle();
      await tester.tap(nameField);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      final saveButton = find.byKey(WorkoutCaptureSheet.saveButtonKey);
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pump();

      expect(repository.saveRequests, hasLength(1));
      expect(tester.getSize(saveButton).height, greaterThanOrEqualTo(48));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester.takeException(), isNull);

      tester.view.resetViewInsets();
      saveCompleter.complete(_savedResult);
      await tester.pumpAndSettle();
      semantics.dispose();
    });
  }
}

const _savedResult = WorkoutCaptureSaveResult(
  workoutTemplateId: 'template-1',
  routineEntryId: 'entry-1',
  activityBatchId: 'batch-1',
);

const _weekly = WorkoutCaptureRoutineOption(
  id: 'weekly',
  name: 'Hybrid week',
  cadenceKind: CadenceKind.weekly,
  slotCount: 7,
);

const _rotationFive = WorkoutCaptureRoutineOption(
  id: 'rotation',
  name: 'Rotation',
  cadenceKind: CadenceKind.rotating,
  slotCount: 5,
);

WorkoutCapturePreview _preview({
  String suggestedName = 'Bench Press + Row',
  int exerciseCount = 2,
  int setCount = 5,
  int groupCount = 1,
  WorkoutCaptureValidationResult? validation,
}) {
  return WorkoutCapturePreview(
    workoutId: 'workout-1',
    content: CapturedWorkoutTemplateContent(exercises: [], groups: []),
    suggestedName: suggestedName,
    exerciseCount: exerciseCount,
    setCount: setCount,
    groupCount: groupCount,
    validation: validation ?? WorkoutCaptureValidationResult(),
  );
}

WorkoutCaptureValidationIssue _issue({
  required String rule,
  required String message,
  required String sourcePath,
  String field = 'values.load',
}) {
  return WorkoutCaptureValidationIssue(
    sourcePath: sourcePath,
    issue: SetValidationIssue(
      field: field,
      dimension: null,
      rule: rule,
      message: message,
      limit: null,
    ),
  );
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required _FakeWorkoutCaptureRepository repository,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        workoutCaptureFeatureRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme:
            brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const _CaptureLauncher(),
      ),
    ),
  );
}

Future<void> _openCapture(
  WidgetTester tester, {
  bool settle = true,
}) async {
  await tester.tap(find.text('Open capture'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _selectRoutine(WidgetTester tester, String id) async {
  final field = find.byKey(WorkoutCaptureSheet.routineFieldKey);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  final option = find.byKey(WorkoutCaptureSheet.routineOptionKey(id));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _selectSlot(WidgetTester tester, int slot) async {
  final field = find.byKey(WorkoutCaptureSheet.slotFieldKey);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  final option = find.byKey(WorkoutCaptureSheet.slotOptionKey(slot));
  if (option.evaluate().isEmpty) {
    final numberField = find.byKey(WorkoutCaptureSheet.slotNumberFieldKey);
    await tester.ensureVisible(numberField);
    await tester.enterText(numberField, '$slot');
    final apply = find.byKey(WorkoutCaptureSheet.slotApplyButtonKey);
    await tester.ensureVisible(apply);
    await tester.tap(apply);
  } else {
    await tester.ensureVisible(option);
    await tester.tap(option);
  }
  await tester.pumpAndSettle();
}

Future<void> _acceptWarnings(WidgetTester tester) async {
  final acceptance = find.byKey(WorkoutCaptureSheet.warningsAcceptanceKey);
  await tester.ensureVisible(acceptance);
  await tester.tap(acceptance);
  await tester.pump();
}

Future<void> _tapSave(WidgetTester tester) async {
  final save = find.byKey(WorkoutCaptureSheet.saveButtonKey);
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pump();
}

FilledButton _saveButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.byKey(WorkoutCaptureSheet.saveButtonKey),
  );
}

String _nameText(WidgetTester tester) {
  return tester
          .widget<TextField>(find.byKey(WorkoutCaptureSheet.nameFieldKey))
          .controller
          ?.text ??
      '';
}

class _CaptureLauncher extends StatelessWidget {
  const _CaptureLauncher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => showWorkoutCaptureSheet(
            context,
            workoutId: 'workout-1',
          ),
          child: const Text('Open capture'),
        ),
      ),
    );
  }
}

class _FakeWorkoutCaptureRepository implements WorkoutCaptureFeatureRepository {
  _FakeWorkoutCaptureRepository({
    required WorkoutCapturePreview preview,
    this.routines = const <WorkoutCaptureRoutineOption>[],
    this.routineStream,
    this.pendingSave,
    this.saveError,
    this.saveHandler,
  }) : previewValue = preview;

  WorkoutCapturePreview previewValue;
  final List<WorkoutCaptureRoutineOption> routines;
  final Stream<List<WorkoutCaptureRoutineOption>>? routineStream;
  final Completer<WorkoutCaptureSaveResult>? pendingSave;
  final Object? saveError;
  final Future<WorkoutCaptureSaveResult> Function(WorkoutCaptureSaveRequest)?
      saveHandler;
  final saveRequests = <WorkoutCaptureSaveRequest>[];
  int previewCalls = 0;

  @override
  Future<WorkoutCapturePreview> preview(String workoutId) async {
    previewCalls += 1;
    return previewValue;
  }

  @override
  Future<WorkoutCaptureSaveResult> save(
    WorkoutCaptureSaveRequest request,
  ) {
    saveRequests.add(request);
    final handler = saveHandler;
    if (handler != null) {
      return handler(request);
    }
    final error = saveError;
    if (error != null) {
      return Future<WorkoutCaptureSaveResult>.error(error);
    }
    return pendingSave?.future ??
        Future<WorkoutCaptureSaveResult>.value(_savedResult);
  }

  @override
  Stream<List<WorkoutCaptureRoutineOption>> watchRoutines() {
    return routineStream ??
        Stream<List<WorkoutCaptureRoutineOption>>.value(routines);
  }
}
