import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/analytics/progress_measure.dart';
import 'package:perennia/domain/training/training_day.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/analytics/widgets/exercise_overview_screen.dart';
import 'package:perennia/features/home/widgets/finish_summary_sheet.dart';
import 'package:perennia/features/home/widgets/workout_duration.dart';
import 'package:perennia/features/home/widgets/workout_screen.dart';
import 'package:perennia/features/progress/repositories/progress_feature_repository.dart';
import 'package:perennia/features/progress/widgets/new_best_row.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/features/template_divergence/repositories/template_divergence_feature_repository.dart';
import 'package:perennia/l10n/app_localizations_en.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

import '../../support/clipboard_capture.dart';

const _emDash = '—';
const _openKey = Key('test.open-sheet');
const _pushWorkoutKey = Key('test.push-workout');

final _loadReps = ExerciseType(
  const <DimensionId>[DimensionId.load, DimensionId.reps],
);

LoggedSet _weightReps(String load, String reps) {
  return LoggedSet.fromValues(<SetDimensionValue>[
    SetDimensionValue(
      dimension: DimensionId.load,
      entered: load,
      unit: TrainingUnit.kilogram,
    ),
    SetDimensionValue(
      dimension: DimensionId.reps,
      entered: reps,
      unit: TrainingUnit.repetition,
    ),
  ]);
}

void main() {
  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  late AppDatabase database;
  late TrainingRepositories repositories;

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(database);
  });

  tearDown(() async {
    await database.close();
  });

  _testSheet('CUJ 5: the facts, the New Best and the change lines', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories),
    ))!;
    await _openSheet(tester, repositories, fixture.workoutId,
        divergenceSummary: fixture.divergenceSummary);
    await _waitFor(tester, () => _isShown(find.byType(NewBestRow)));

    expect(find.text('Lower B'), findsOneWidget);
    final duration = formatWorkoutDuration(
      AppLocalizationsEn(),
      const Duration(minutes: 32),
    );
    expect(find.text('$duration · 7 of 7 sets · 2 exercises'), findsOneWidget);
    expect(find.text('New bests'), findsOneWidget);

    // One row: the Workout's Deadlift, the earlier 130 kg beaten, and no
    // date, since every row is from this Workout. Leg Press has no earlier
    // Workout, so its first point is no New Best.
    final row = tester.widget<NewBestRow>(find.byType(NewBestRow));
    expect(row.today, isNull);
    expect(row.unitSystem, UnitSystem.metric);
    expect(row.row.exerciseName, 'Deadlift');
    expect(row.row.best.workoutId, fixture.workoutId);
    expect(row.row.best.measure, ProgressMeasureKind.maxLoad);
    expect(row.row.best.value, 140);
    expect(find.text('Deadlift · 140 kg'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);

    expect(find.text('Update "Lower B"'), findsOneWidget);
    expect(_textsUnder(tester, FinishSummarySheet.updateTemplateKey), [
      'Update "Lower B"',
      'Remove Hip Thrust',
      'Deadlift: sets changed',
    ]);
    expect(find.text('Copy summary'), findsOneWidget);
    expect(find.byKey(FinishSummarySheet.doneKey), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  _testSheet('keeps only the New Bests of this Workout', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories),
    ))!;
    NewBest best(String workoutId, String exerciseId) => NewBest(
          exerciseId: exerciseId,
          measure: ProgressMeasureKind.maxLoad,
          workoutId: workoutId,
          localDate: const TrainingDayDate(year: 2026, month: 11, day: 3),
          startedAt: DateTime(2026, 11, 3, 7),
          setId: 's-$workoutId-$exerciseId',
          value: 140,
          unit: TrainingUnit.kilogram,
        );
    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: fixture.divergenceSummary,
      progress: StubProgressFeatureRepository(
        newBests: [
          best(fixture.workoutId, fixture.deadliftId),
          // The same day, another Workout.
          best('another-workout', fixture.deadliftId),
          // An exercise this Workout no longer holds has no name to show.
          best(fixture.workoutId, fixture.hipThrustId),
        ],
      ),
    );
    await _waitFor(tester, () => _isShown(find.byType(NewBestRow)));

    final rows = tester.widgetList<NewBestRow>(find.byType(NewBestRow));
    expect(rows.single.row.best.workoutId, fixture.workoutId);
    expect(rows.single.row.best.exerciseId, fixture.deadliftId);
  });

  _testSheet(
      'New Bests read an em dash until they return, then None, at the same '
      'height', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories),
    ))!;
    final bests = StreamController<List<NewBest>>();
    addTearDown(bests.close);
    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: fixture.divergenceSummary,
      progress: _ControlledNewBests(bests.stream),
    );
    await _waitFor(tester, () => _isShown(find.text(_emDash)));

    final sheet = find.byKey(FinishSummarySheet.sheetKey);
    expect(find.text('New bests'), findsOneWidget);
    expect(find.text('None'), findsNothing);
    expect(_noteHeight(tester, _emDash), AppDimens.touchTarget);
    final heightBefore = tester.getSize(sheet).height;

    bests.add(const <NewBest>[]);
    await _waitFor(tester, () => _isShown(find.text('None')));

    expect(find.text(_emDash), findsNothing);
    expect(_noteHeight(tester, 'None'), AppDimens.touchTarget);
    expect(tester.getSize(sheet).height, heightBefore);
  });

  _testSheet('a failed New Bests read keeps the em dash', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories),
    ))!;
    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: fixture.divergenceSummary,
      progress: _ControlledNewBests(
        Stream<List<NewBest>>.error(StateError('compute failed')),
      ),
    );
    await _waitFor(tester, () => _isShown(find.text(_emDash)));
    await _settle(tester);

    expect(find.text(_emDash), findsOneWidget);
    expect(find.text('None'), findsNothing);
  });

  _testSheet('holds the em dash while settings load', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories),
    ))!;
    final settings = _ControlledSettings();
    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: fixture.divergenceSummary,
      progress: const StubProgressFeatureRepository(),
      settings: settings,
    );
    await _waitFor(tester, () => _isShown(find.text(_emDash)));
    await _settle(tester);
    expect(find.text('None'), findsNothing);

    settings.complete(AppSettings.defaults);
    await _waitFor(tester, () => _isShown(find.text('None')));
  });

  _testSheet('reads the default units if settings fail to load', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories),
    ))!;
    final settings = _ControlledSettings();
    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: fixture.divergenceSummary,
      settings: settings,
    );
    await _waitFor(tester, () => _isShown(find.text(_emDash)));

    settings.fail(StateError('settings failed'));
    await _waitFor(tester, () => _isShown(find.byType(NewBestRow)));

    expect(
      tester.widget<NewBestRow>(find.byType(NewBestRow)).unitSystem,
      AppSettings.defaults.unitSystem,
    );
  });

  _testSheet('Update writes the template and disables the row', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories),
    ))!;
    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: fixture.divergenceSummary,
      progress: const StubProgressFeatureRepository(),
    );
    final semantics = tester.ensureSemantics();
    final row = find.byKey(FinishSummarySheet.updateTemplateKey);
    await _waitFor(tester, () => _isShown(row));
    expect(
      tester.getSemantics(row),
      isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
    );
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));

    await tester.tap(row);
    await _waitFor(tester, () => _isShown(find.text('"Lower B" updated')));

    final template = (await tester.runAsync(
      () => repositories.workoutTemplates.getById(fixture.templateId),
    ))!;
    expect(
      template.exercises.map((exercise) => exercise.exerciseId),
      [fixture.deadliftId, fixture.legPressId],
    );
    expect(template.exercises.first.prescriptions.single.repeat, 4);

    expect(find.text('Update "Lower B"'), findsNothing);
    expect(tester.widget<InkWell>(row).onTap, isNull);
    expect(
      tester.getSemantics(row),
      isSemantics(isButton: true, isEnabled: false),
    );
    // The lines stay, in every state.
    expect(_textsUnder(tester, FinishSummarySheet.updateTemplateKey), [
      '"Lower B" updated',
      'Remove Hip Thrust',
      'Deadlift: sets changed',
    ]);
    semantics.dispose();
  });

  _testSheet('a second tap while Update runs is ignored', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories),
    ))!;
    final pending = Completer<TemplateUpdateFromWorkoutResult?>();
    final divergence = _FakeDivergenceRepository(() => pending.future);
    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: fixture.divergenceSummary,
      progress: const StubProgressFeatureRepository(),
      divergence: divergence,
    );
    final row = find.byKey(FinishSummarySheet.updateTemplateKey);
    await _waitFor(tester, () => _isShown(row));

    await tester.tap(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();

    expect(divergence.calls, 1);
    expect(find.text('Update "Lower B"'), findsOneWidget);

    pending.complete(
      const TemplateUpdateFromWorkoutResult(
        workoutTemplateId: 'template',
        activityBatchId: 'batch',
      ),
    );
    await _waitFor(tester, () => _isShown(find.text('"Lower B" updated')));
    expect(divergence.calls, 1);
  });

  for (final (description, update) in <(
    String,
    Future<TemplateUpdateFromWorkoutResult?> Function(),
  )>[
    ('returns null', () async => null),
    ('throws', () async => throw StateError('write failed')),
  ]) {
    _testSheet('an Update that $description shows the failure, and can retry', (
      tester,
    ) async {
      final fixture = (await tester.runAsync(
        () => _createLowerB(repositories),
      ))!;
      final divergence = _FakeDivergenceRepository(update);
      await _openSheet(
        tester,
        repositories,
        fixture.workoutId,
        divergenceSummary: fixture.divergenceSummary,
        progress: const StubProgressFeatureRepository(),
        divergence: divergence,
      );
      final row = find.byKey(FinishSummarySheet.updateTemplateKey);
      await _waitFor(tester, () => _isShown(row));

      await tester.tap(row);
      await _waitFor(
        tester,
        () => _isShown(find.text('Couldn\'t update "Lower B"')),
      );

      expect(tester.takeException(), isNull);
      expect(tester.widget<InkWell>(row).onTap, isNotNull);
      expect(_textsUnder(tester, FinishSummarySheet.updateTemplateKey), [
        'Couldn\'t update "Lower B"',
        'Remove Hip Thrust',
        'Deadlift: sets changed',
      ]);

      await tester.tap(row);
      await tester.pump();
      expect(divergence.calls, 2);
    });
  }

  _testSheet('Copy summary puts the text on the clipboard, then says Copied', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories),
    ))!;
    final copied = captureClipboard(tester);
    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: fixture.divergenceSummary,
      progress: const StubProgressFeatureRepository(),
    );
    final row = find.byKey(FinishSummarySheet.copySummaryKey);
    await _waitFor(tester, () => _isShown(row));
    expect(find.text('Copied'), findsNothing);

    await tester.tap(row);
    await _waitFor(tester, () => _isShown(find.text('Copied')));

    expect(copied.single, contains('Deadlift'));
    expect(find.text('Copy summary'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Copied'), findsNothing);
    expect(find.text('Copy summary'), findsOneWidget);
  });

  _testSheet('an unlinked Workout has its fallback title and no Update row', (
    tester,
  ) async {
    final workoutId = (await tester.runAsync(
      () => repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 11, 3, 7),
          timezone: 'UTC',
          endedAt: DateTime.utc(2026, 11, 3, 7, 10),
        ),
      ),
    ))!;
    await _openSheet(
      tester,
      repositories,
      workoutId,
      divergenceSummary: null,
      progress: const StubProgressFeatureRepository(),
    );
    await _waitFor(
      tester,
      () => _isShown(find.byKey(FinishSummarySheet.copySummaryKey)),
    );

    expect(find.text('Workout'), findsOneWidget);
    expect(find.byKey(FinishSummarySheet.updateTemplateKey), findsNothing);
  });

  _testSheet('an undiverged Workout has no Update row', (tester) async {
    final fixture = (await tester.runAsync(() async {
      final exerciseId = await repositories.exercises.create(
        ExerciseDraft(name: 'Deadlift', type: _loadReps),
      );
      final templateId = await repositories.workoutTemplates.create(
        const WorkoutTemplateDraft(name: 'Lower B'),
      );
      final entryId = await repositories.workoutTemplates.addExercise(
        templateId,
        exerciseId,
      );
      await repositories.workoutTemplates.addPrescription(
        entryId,
        PrescriptionDraft(
          mode: PrescriptionMode.fixed,
          values: _weightReps('140', '5'),
          repeat: 3,
        ),
      );
      final result = await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(workoutTemplateId: templateId),
        now: DateTime(2026, 11, 3, 7),
      );
      final summary = await repositories.templateDivergence.summaryForWorkout(
        result.workoutId,
      );
      return (workoutId: result.workoutId, summary: summary);
    }))!;
    expect(fixture.summary, isNotNull);
    expect(fixture.summary!.hasDivergence, isFalse);

    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: fixture.summary,
      progress: const StubProgressFeatureRepository(),
    );
    await _waitFor(
      tester,
      () => _isShown(find.byKey(FinishSummarySheet.copySummaryKey)),
    );

    expect(find.text('Lower B'), findsOneWidget);
    expect(find.byKey(FinishSummarySheet.updateTemplateKey), findsNothing);
  });

  _testSheet('a missing Workout renders only Done', (tester) async {
    await _openSheet(
      tester,
      repositories,
      'no-such-workout',
      divergenceSummary: null,
      progress: const StubProgressFeatureRepository(),
    );
    await _settle(tester);

    expect(find.byKey(FinishSummarySheet.doneKey), findsOneWidget);
    expect(find.byKey(FinishSummarySheet.copySummaryKey), findsNothing);
    expect(find.text('New bests'), findsNothing);
  });

  _testSheet('Done closes the sheet', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories),
    ))!;
    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: fixture.divergenceSummary,
      progress: const StubProgressFeatureRepository(),
    );
    final done = find.byKey(FinishSummarySheet.doneKey);
    await _waitFor(tester, () => _isShown(done));
    expect(tester.getSize(done).height, AppDimens.rowHeight);

    await tester.tap(done);
    await _settle(tester);

    expect(find.byKey(FinishSummarySheet.sheetKey), findsNothing);
    expect(find.byKey(_openKey), findsOneWidget);
  });

  _testSheet('CUJ 5 through the real flow: Finish, the summary, Done', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories, finish: false),
    ))!;
    await _openWorkoutScreen(tester, repositories, fixture.workoutId);

    await tester
        .tap(find.byKey(WorkoutScreen.finishButtonKey(fixture.workoutId)));
    await _waitFor(tester, () => _isShown(find.byType(NewBestRow)));
    await _settle(tester);

    final workout = (await tester.runAsync(
      () => repositories.workoutSessions.getById(fixture.workoutId),
    ))!;
    expect(workout.endedAt, isNotNull);

    final sheet = find.byKey(FinishSummarySheet.sheetKey);
    expect(sheet, findsOneWidget);
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(_textsUnder(tester, FinishSummarySheet.updateTemplateKey), [
      'Update "Lower B"',
      'Remove Hip Thrust',
      'Deadlift: sets changed',
    ]);
    // The facts line, read after the finish write: its duration is the real
    // one, not the in-progress text the Workout had before it.
    final facts = find.descendant(
      of: sheet,
      matching: find.textContaining('7 of 7 sets · 2 exercises'),
    );
    expect(facts, findsOneWidget);
    expect(
      tester.widget<Text>(facts).data,
      isNot(contains(AppLocalizationsEn().workoutDurationInProgress)),
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.byKey(FinishSummarySheet.doneKey));
    await _expectBackAtOpener(tester);
  });

  _testSheet('a swipe-down on the handle also returns to the opener', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories, finish: false),
    ))!;
    await _openWorkoutScreen(tester, repositories, fixture.workoutId);

    await tester
        .tap(find.byKey(WorkoutScreen.finishButtonKey(fixture.workoutId)));
    await _waitFor(
        tester, () => _isShown(find.byKey(FinishSummarySheet.doneKey)));
    await _settle(tester);

    // The sheet's top edge is its drag handle: a drag on the scrolling body
    // moves the scroll view rather than the sheet.
    final sheetRect = tester.getRect(find.byType(BottomSheet));
    await tester.dragFrom(
      sheetRect.topCenter + const Offset(0, 12),
      Offset(0, sheetRect.height),
    );
    await _expectBackAtOpener(tester);
  });

  _testSheet('Back also returns to the opener', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories, finish: false),
    ))!;
    await _openWorkoutScreen(tester, repositories, fixture.workoutId);

    await tester
        .tap(find.byKey(WorkoutScreen.finishButtonKey(fixture.workoutId)));
    await _waitFor(
        tester, () => _isShown(find.byKey(FinishSummarySheet.doneKey)));
    await _settle(tester);

    await tester.binding.handlePopRoute();
    await _expectBackAtOpener(tester);
  });

  _testSheet('the second tap of a double tap on Finish leaves the sheet open', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories, finish: false),
    ))!;
    await _openWorkoutScreen(tester, repositories, fixture.workoutId);

    final finish = find.byKey(WorkoutScreen.finishButtonKey(fixture.workoutId));
    final finishCenter = tester.getCenter(finish);
    await tester.tap(finish);
    await _waitFor(tester, () => _isShown(find.byType(BottomSheet)));

    // The sheet is still rising below the button, so this lands on the scrim.
    expect(tester.getRect(find.byType(BottomSheet)).top,
        greaterThan(finishCenter.dy));
    await tester.tapAt(finishCenter);
    await _settle(tester);

    expect(find.byKey(FinishSummarySheet.sheetKey), findsOneWidget);
    expect(find.byType(WorkoutScreen), findsOneWidget);

    await tester.tap(find.byKey(FinishSummarySheet.doneKey));
    await _expectBackAtOpener(tester);
  });

  _testSheet('a second tap on Finish before the sheet opens finishes once', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories, finish: false),
    ))!;
    final release = Completer<void>();
    final divergence = _HeldDivergenceRepository(() => release.future);
    await _openWorkoutScreen(
      tester,
      repositories,
      fixture.workoutId,
      divergence: divergence,
    );

    final finish = find.byKey(WorkoutScreen.finishButtonKey(fixture.workoutId));
    await tester.tap(finish);
    await tester.pump();
    await tester.tap(finish);
    await tester.pump();
    expect(divergence.reads, 1);

    release.complete();
    await _waitFor(
        tester, () => _isShown(find.byKey(FinishSummarySheet.doneKey)));
    await _settle(tester);

    expect(divergence.reads, 1);
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.byKey(FinishSummarySheet.doneKey));
    await _expectBackAtOpener(tester);
  });

  _testSheet('Finish can be tapped again after a failed attempt', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories, finish: false),
    ))!;
    var failNextRead = true;
    final divergence = _HeldDivergenceRepository(() async {
      if (failNextRead) {
        failNextRead = false;
        throw StateError('read failed');
      }
    });
    await _openWorkoutScreen(
      tester,
      repositories,
      fixture.workoutId,
      divergence: divergence,
    );

    final finish = find.byKey(WorkoutScreen.finishButtonKey(fixture.workoutId));
    // Finish runs unawaited, so its failure goes to the tap's zone.
    Object? failure;
    await runZonedGuarded(
      () => tester.tap(finish),
      (error, _) => failure = error,
    );
    await _settle(tester);
    expect(failure, isStateError);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(finish);
    await _waitFor(
        tester, () => _isShown(find.byKey(FinishSummarySheet.doneKey)));

    expect(divergence.reads, 2);
  });

  _testSheet(
      'Back during Finish finishes the Workout, opens no sheet and leaves the '
      'opener in place', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories, finish: false),
    ))!;
    final release = Completer<void>();
    await _openWorkoutScreen(
      tester,
      repositories,
      fixture.workoutId,
      divergence: _HeldDivergenceRepository(() => release.future),
    );

    await tester
        .tap(find.byKey(WorkoutScreen.finishButtonKey(fixture.workoutId)));
    await tester.pump();

    // The Workout route is animating out, so its context is still mounted.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(WorkoutScreen), findsOneWidget);

    release.complete();
    await _settle(tester);
    await _settle(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(WorkoutScreen), findsNothing);
    expect(find.byKey(_pushWorkoutKey), findsOneWidget);
    final workout = await tester.runAsync(
      () => repositories.workoutSessions.getById(fixture.workoutId),
    );
    expect(workout!.endedAt, isNotNull);
  });

  _testSheet('a tap above the settled sheet leaves it open', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories, finish: false),
    ))!;
    await _openWorkoutScreen(tester, repositories, fixture.workoutId);

    await tester
        .tap(find.byKey(WorkoutScreen.finishButtonKey(fixture.workoutId)));
    await _waitFor(
        tester, () => _isShown(find.byKey(FinishSummarySheet.doneKey)));
    await _settle(tester);

    final sheetTop = tester.getRect(find.byType(BottomSheet)).top;
    expect(sheetTop, greaterThan(20));
    await tester.tapAt(Offset(200, sheetTop / 2));
    await _settle(tester);

    expect(find.byKey(FinishSummarySheet.sheetKey), findsOneWidget);
    expect(find.byType(WorkoutScreen), findsOneWidget);
  });

  _testSheet('at 2x text a long list scrolls inside the sheet', (tester) async {
    final fixture = (await tester.runAsync(() async {
      final workoutId = await repositories.workoutSessions.create(
        WorkoutSessionDraft(
          startedAt: DateTime.utc(2026, 11, 3, 7),
          timezone: 'UTC',
          endedAt: DateTime.utc(2026, 11, 3, 7, 32),
        ),
      );
      final bests = <NewBest>[];
      for (var index = 0; index < 12; index += 1) {
        final exerciseId = await repositories.exercises.create(
          ExerciseDraft(
            name: 'Single-Leg Romanian Deadlift Variation $index',
            type: _loadReps,
          ),
        );
        await repositories.workoutExercises.create(
          WorkoutExerciseDraft(workoutId: workoutId, exerciseId: exerciseId),
        );
        bests.add(
          NewBest(
            exerciseId: exerciseId,
            measure: ProgressMeasureKind.maxLoad,
            workoutId: workoutId,
            localDate: const TrainingDayDate(year: 2026, month: 11, day: 3),
            startedAt: DateTime.utc(2026, 11, 3, 7),
            setId: 's-$index',
            value: 140,
            unit: TrainingUnit.kilogram,
          ),
        );
      }
      return (workoutId: workoutId, bests: bests);
    }))!;
    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: null,
      progress: StubProgressFeatureRepository(newBests: fixture.bests),
      surfaceSize: const Size(360, 640),
      textScaler: const TextScaler.linear(2),
    );
    await _waitFor(tester, () => _isShown(find.byType(NewBestRow)));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    final sheet = find.byKey(FinishSummarySheet.sheetKey);
    expect(tester.getSize(sheet).height, lessThanOrEqualTo(640 * 0.9));

    final scrollable = find.descendant(
      of: sheet,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.drag(scrollable, const Offset(0, -5000));
    await _settle(tester);
    expect(position.pixels, position.maxScrollExtent);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(FinishSummarySheet.doneKey));
    await _settle(tester);
    expect(sheet, findsNothing);
  });

  _testSheet(
      'a New Best tap opens Exercise Overview over the sheet, and the sheet is '
      'still there on return', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories, finish: false),
    ))!;
    await _openWorkoutScreen(tester, repositories, fixture.workoutId);

    await tester
        .tap(find.byKey(WorkoutScreen.finishButtonKey(fixture.workoutId)));
    await _waitFor(tester, () => _isShown(find.byType(NewBestRow)));
    await _settle(tester);

    await tester.tap(find.byType(NewBestRow));
    await _waitFor(tester, () => _isShown(find.byType(ExerciseOverviewScreen)));
    await _settle(tester);
    expect(find.byType(ExerciseOverviewScreen), findsOneWidget);

    // A page route's reverse transition outlasts one _settle.
    await tester.binding.handlePopRoute();
    await _waitFor(
        tester, () => !_isShown(find.byType(ExerciseOverviewScreen)));
    await _settle(tester);

    expect(find.byType(ExerciseOverviewScreen), findsNothing);
    expect(find.byKey(FinishSummarySheet.sheetKey), findsOneWidget);
    expect(find.byType(WorkoutScreen), findsOneWidget);

    await tester.tap(find.byKey(FinishSummarySheet.doneKey));
    await _expectBackAtOpener(tester);
  });

  _testSheet(
      'a Workout that goes unavailable under the sheet leaves Done, which '
      'still returns to the opener', (tester) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories, finish: false),
    ))!;
    await _openWorkoutScreen(tester, repositories, fixture.workoutId);

    await tester
        .tap(find.byKey(WorkoutScreen.finishButtonKey(fixture.workoutId)));
    await _waitFor(tester, () => _isShown(find.byType(NewBestRow)));
    await _settle(tester);

    await tester.runAsync(
      () => repositories.workoutSessions.softDelete(fixture.workoutId),
    );
    await _waitFor(
      tester,
      () => !_isShown(find.byKey(FinishSummarySheet.copySummaryKey)),
    );
    await _settle(tester);

    expect(find.byKey(FinishSummarySheet.doneKey), findsOneWidget);
    expect(find.byKey(FinishSummarySheet.copySummaryKey), findsNothing);

    await tester.tap(find.byKey(FinishSummarySheet.doneKey));
    await _expectBackAtOpener(tester);
  });

  _testSheet('at 2x text the Update row and its lines show in full', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(
      () => _createLowerB(repositories),
    ))!;
    await _openSheet(
      tester,
      repositories,
      fixture.workoutId,
      divergenceSummary: fixture.divergenceSummary,
      surfaceSize: const Size(360, 640),
      textScaler: const TextScaler.linear(2),
    );
    await _waitFor(tester, () => _isShown(find.byType(NewBestRow)));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(_textsUnder(tester, FinishSummarySheet.updateTemplateKey), [
      'Update "Lower B"',
      'Remove Hip Thrust',
      'Deadlift: sets changed',
    ]);
    for (final text in [
      'Update "Lower B"',
      'Remove Hip Thrust',
      'Deadlift: sets changed',
      'Deadlift · 140 kg',
    ]) {
      expect(
        tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines,
        isFalse,
        reason: text,
      );
    }
  });
}

void _testSheet(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    try {
      await callback(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    }
  });
}

/// CUJ 5: Lower B plans Deadlift, Leg Press and Hip Thrust at 3 sets. Its
/// Workout logged 4 Deadlift sets at 140 kg, against 130 kg in an earlier
/// Workout, and the 3 Leg Press sets as prescribed, and removed Hip Thrust.
/// With [finish] false the Workout stays open, for a test that finishes it.
Future<_LowerB> _createLowerB(
  TrainingRepositories repositories, {
  bool finish = true,
}) async {
  Future<String> exercise(String name) {
    return repositories.exercises.create(
      ExerciseDraft(
        name: name,
        type: _loadReps,
        recordProfile: RecordProfile.maxLoad,
      ),
    );
  }

  final deadliftId = await exercise('Deadlift');
  final legPressId = await exercise('Leg Press');
  final hipThrustId = await exercise('Hip Thrust');

  final earlierId = await repositories.workoutSessions.create(
    WorkoutSessionDraft(
      startedAt: DateTime(2026, 11, 1, 7).toUtc(),
      timezone: 'UTC',
      endedAt: DateTime(2026, 11, 1, 7, 30).toUtc(),
    ),
  );
  await repositories.workoutExercises.create(
    WorkoutExerciseDraft(workoutId: earlierId, exerciseId: deadliftId),
  );
  await repositories.sets.create(
    LoggedSetDraft(
      workoutId: earlierId,
      exerciseId: deadliftId,
      position: await repositories.sets.nextPositionForWorkout(earlierId),
      values: _weightReps('130', '5'),
      isCompleted: true,
      performedAt: DateTime(2026, 11, 1, 7, 5).toUtc(),
    ),
  );

  final templateId = await repositories.workoutTemplates.create(
    const WorkoutTemplateDraft(name: 'Lower B'),
  );
  for (final (exerciseId, load) in <(String, String)>[
    (deadliftId, '140'),
    (legPressId, '200'),
    (hipThrustId, '100'),
  ]) {
    final entryId = await repositories.workoutTemplates.addExercise(
      templateId,
      exerciseId,
    );
    await repositories.workoutTemplates.addPrescription(
      entryId,
      PrescriptionDraft(
        mode: PrescriptionMode.fixed,
        values: _weightReps(load, '5'),
        repeat: 3,
      ),
    );
  }

  final startedAt = DateTime(2026, 11, 3, 7);
  final workoutId = (await repositories.templateMaterialize.materialize(
    TemplateMaterializeRequest(workoutTemplateId: templateId),
    now: startedAt,
  ))
      .workoutId;

  final workoutExercises =
      await repositories.workoutExercises.listActiveForWorkout(workoutId);
  await repositories.workoutExercises.softDelete(
    workoutExercises
        .firstWhere((exercise) => exercise.exerciseId == hipThrustId)
        .id,
  );
  for (final set in await repositories.sets.listActiveForWorkout(workoutId)) {
    await repositories.sets.setCompleted(set.id, isCompleted: true);
  }
  await repositories.sets.create(
    LoggedSetDraft(
      workoutId: workoutId,
      exerciseId: deadliftId,
      position: await repositories.sets.nextPositionForWorkout(workoutId),
      values: _weightReps('140', '5'),
      isCompleted: true,
      performedAt: startedAt.add(const Duration(minutes: 20)).toUtc(),
    ),
  );

  final divergenceSummary =
      await repositories.templateDivergence.summaryForWorkout(workoutId);
  if (finish) {
    await repositories.workoutSessions.updateEndedAt(
      workoutId,
      endedAt: startedAt.add(const Duration(minutes: 32)).toUtc(),
    );
  }

  return _LowerB(
    workoutId: workoutId,
    templateId: templateId,
    deadliftId: deadliftId,
    legPressId: legPressId,
    hipThrustId: hipThrustId,
    divergenceSummary: divergenceSummary!,
  );
}

class _LowerB {
  const _LowerB({
    required this.workoutId,
    required this.templateId,
    required this.deadliftId,
    required this.legPressId,
    required this.hipThrustId,
    required this.divergenceSummary,
  });

  final String workoutId;
  final String templateId;
  final String deadliftId;
  final String legPressId;
  final String hipThrustId;
  final TemplateDivergenceSummary divergenceSummary;
}

/// Pumps a small screen with one button, which runs [onPressed]. The tests'
/// openers differ only in that callback and in the wait after the tap.
Future<void> _pumpHost(
  WidgetTester tester,
  TrainingRepositories repositories, {
  required Key buttonKey,
  required String buttonLabel,
  required void Function(BuildContext) onPressed,
  ProgressFeatureRepository? progress,
  TemplateDivergenceFeatureRepository? divergence,
  SettingsRepository? settings,
  Size surfaceSize = const Size(400, 900),
  TextScaler? textScaler,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => repositories.database),
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        settingsRepositoryProvider.overrideWith(
          (ref) => settings ?? InMemorySettingsRepository(),
        ),
        if (progress != null)
          progressFeatureRepositoryProvider.overrideWith((ref) => progress),
        if (divergence != null)
          templateDivergenceFeatureRepositoryProvider.overrideWith(
            (ref) => divergence,
          ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                key: buttonKey,
                onPressed: () => onPressed(context),
                child: Text(buttonLabel),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps a screen with a button that opens the sheet, and opens it. The
/// [progress] override skips the real New Bests read, which runs `compute`,
/// for a test about something else.
Future<void> _openSheet(
  WidgetTester tester,
  TrainingRepositories repositories,
  String workoutId, {
  required TemplateDivergenceSummary? divergenceSummary,
  ProgressFeatureRepository? progress,
  TemplateDivergenceFeatureRepository? divergence,
  SettingsRepository? settings,
  Size surfaceSize = const Size(400, 900),
  TextScaler? textScaler,
}) async {
  await _pumpHost(
    tester,
    repositories,
    buttonKey: _openKey,
    buttonLabel: 'Open',
    onPressed: (context) => unawaited(
      showFinishSummarySheet(
        context,
        workoutId: workoutId,
        divergenceSummary: divergenceSummary,
      ),
    ),
    progress: progress,
    divergence: divergence,
    settings: settings,
    surfaceSize: surfaceSize,
    textScaler: textScaler,
  );
  await tester.tap(find.byKey(_openKey));
  await tester.pump();
  await _settle(tester);
}

/// Pushes the real [WorkoutScreen] from a small opener screen, so a test can
/// see it pop back there. It uses the real New Bests read, which runs
/// `compute`, so [_waitFor] and [_settle] let it finish.
Future<void> _openWorkoutScreen(
  WidgetTester tester,
  TrainingRepositories repositories,
  String workoutId, {
  TemplateDivergenceFeatureRepository? divergence,
}) async {
  await _pumpHost(
    tester,
    repositories,
    buttonKey: _pushWorkoutKey,
    buttonLabel: 'Open Workout',
    onPressed: (context) => unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutScreen(workoutId: workoutId),
        ),
      ),
    ),
    divergence: divergence,
  );
  await tester.tap(find.byKey(_pushWorkoutKey));
  await tester.pump();
  await _waitFor(
    tester,
    () => _isShown(find.byKey(WorkoutScreen.finishButtonKey(workoutId))),
  );
  await _settle(tester);
}

/// The sheet has closed and the Workout screen has popped, each transition
/// run to its end.
Future<void> _expectBackAtOpener(WidgetTester tester) async {
  await _waitFor(tester, () => !_isShown(find.byType(WorkoutScreen)));
  expect(find.byKey(FinishSummarySheet.sheetKey), findsNothing);
  expect(find.byKey(_pushWorkoutKey), findsOneWidget);
}

bool _isShown(Finder finder) => finder.evaluate().isNotEmpty;

/// The texts under the row [key], in reading order.
List<String> _textsUnder(WidgetTester tester, Key key) {
  return tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(key), matching: find.byType(Text)),
      )
      .map((text) => text.data!)
      .toList();
}

/// The height of the New Bests section's one row, holding [text].
double _noteHeight(WidgetTester tester, String text) {
  return tester
      .getSize(
        find
            .ancestor(
                of: find.text(text), matching: find.byType(ConstrainedBox))
            .first,
      )
      .height;
}

/// Lets repository writes, and the Drift streams they wake, finish, and the
/// sheet's animation run.
Future<void> _settle(WidgetTester tester) async {
  for (var round = 0; round < 20; round += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 300; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) {
      return;
    }
  }
  fail('Timed out waiting.');
}

class _ControlledNewBests extends StubProgressFeatureRepository {
  const _ControlledNewBests(this._newBests);

  final Stream<List<NewBest>> _newBests;

  @override
  Stream<List<NewBest>> watchNewBests(
    TrainingDayDate from,
    TrainingDayDate to,
  ) {
    return _newBests;
  }
}

/// Settings that stay loading until the test says otherwise.
class _ControlledSettings implements SettingsRepository {
  final _load = Completer<AppSettings>();

  void complete(AppSettings settings) => _load.complete(settings);

  void fail(Object error) => _load.completeError(error);

  @override
  Future<AppSettings> load() => _load.future;

  @override
  Future<void> save(AppSettings settings) async {}
}

class _FakeDivergenceRepository implements TemplateDivergenceFeatureRepository {
  _FakeDivergenceRepository(this._update);

  final Future<TemplateUpdateFromWorkoutResult?> Function() _update;
  int calls = 0;

  @override
  Future<TemplateDivergenceSummary?> summaryForWorkout(String workoutId) async {
    return null;
  }

  @override
  Future<TemplateUpdateFromWorkoutResult?> updateTemplateFromWorkout(
    String workoutId,
  ) {
    calls += 1;
    return _update();
  }
}

/// Runs [_onRead] inside Finish's divergence read, so a test can act while
/// Finish is in flight or make the read fail.
class _HeldDivergenceRepository extends _FakeDivergenceRepository {
  _HeldDivergenceRepository(this._onRead) : super(() async => null);

  final Future<void> Function() _onRead;
  int reads = 0;

  @override
  Future<TemplateDivergenceSummary?> summaryForWorkout(String workoutId) async {
    reads += 1;
    await _onRead();
    return null;
  }
}
