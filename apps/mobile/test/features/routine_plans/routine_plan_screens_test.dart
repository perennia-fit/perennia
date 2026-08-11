import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/home/widgets/workout_screen.dart';
import 'package:perennia/features/routine_plans/repositories/routine_plan_feature_repository.dart';
import 'package:perennia/features/routine_plans/widgets/routine_plan_editor_screen.dart';
import 'package:perennia/features/routine_plans/widgets/routine_plan_list_screen.dart';
import 'package:perennia/features/routine_plans/widgets/routine_start_sheet.dart';
import 'package:perennia/features/template_materialize/repositories/template_materialize_feature_repository.dart';
import 'package:perennia/features/workout_templates/widgets/workout_template_editor_screen.dart';
import 'package:perennia/l10n/app_localizations.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Routine Plans accessibility', () {
    for (final brightness in Brightness.values) {
      testWidgets(
        'list meets contrast, target, and label guidelines in ${brightness.name}',
        (tester) async {
          await _setLargePhone(tester);
          final fixture = await _fixture();
          _closeAfterTest(fixture);
          final archivedRoutineId = await fixture.adapter.createRoutine(
            name: 'Archived collection',
          );
          await fixture.adapter.archiveRoutine(archivedRoutineId);
          await tester.pumpWidget(
            _testApp(
              adapter: fixture.adapter,
              brightness: brightness,
              home: const RoutinePlanListScreen(),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(RoutinePlanListScreen.archivedToggleKey),
          );
          await tester.pumpAndSettle();

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(
            tester,
            meetsGuideline(androidTapTargetGuideline),
          );
          await expectLater(
            tester,
            meetsGuideline(labeledTapTargetGuideline),
          );
          await _disposeWidgetTree(tester);
        },
      );

      testWidgets(
        'editor meets contrast, target, and label guidelines in ${brightness.name}',
        (tester) async {
          await _setLargePhone(tester);
          final fixture = await _fixture();
          _closeAfterTest(fixture);
          await fixture.adapter.setCadence(
            routineId: fixture.routineId,
            cadence: const Cadence.weekly(),
          );
          await tester.pumpWidget(
            _testApp(
              adapter: fixture.adapter,
              brightness: brightness,
              home: RoutinePlanEditorScreen(
                routineId: fixture.routineId,
              ),
            ),
          );
          await tester.pumpAndSettle();

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(
            tester,
            meetsGuideline(androidTapTargetGuideline),
          );
          await expectLater(
            tester,
            meetsGuideline(labeledTapTargetGuideline),
          );
          await _disposeWidgetTree(tester);
        },
      );

      testWidgets(
        'template picker meets contrast, target, and label guidelines in ${brightness.name}',
        (tester) async {
          await _setLargePhone(tester);
          final fixture = await _fixture();
          _closeAfterTest(fixture);
          await tester.pumpWidget(
            _testApp(
              adapter: fixture.adapter,
              brightness: brightness,
              home: RoutinePlanEditorScreen(
                routineId: fixture.routineId,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(RoutinePlanEditorScreen.addTemplateButtonKey),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(RoutinePlanEditorScreen.pickerKey),
            findsOneWidget,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(
            tester,
            meetsGuideline(androidTapTargetGuideline),
          );
          await expectLater(
            tester,
            meetsGuideline(labeledTapTargetGuideline),
          );
          await _disposeWidgetTree(tester);
        },
      );

      testWidgets(
        'Start sheet meets contrast, target, and label guidelines in ${brightness.name}',
        (tester) async {
          await _setLargePhone(tester);
          final fixture = await _fixture();
          _closeAfterTest(fixture);
          await tester.pumpWidget(
            _testApp(
              adapter: fixture.adapter,
              brightness: brightness,
              home: const RoutinePlanListScreen(),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(
            find.byKey(
              RoutinePlanListScreen.startButtonKey(fixture.routineId),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byKey(RoutineStartSheet.sheetKey), findsOneWidget);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(
            tester,
            meetsGuideline(androidTapTargetGuideline),
          );
          await expectLater(
            tester,
            meetsGuideline(labeledTapTargetGuideline),
          );
          await _disposeWidgetTree(tester);
        },
      );
    }
  });

  testWidgets('creates, archives, and restores a Routine from the list',
      (tester) async {
    await _setLargePhone(tester);
    final fixture = await _fixture(seedRoutine: false);
    _closeAfterTest(fixture);
    await tester.pumpWidget(
      _testApp(
        adapter: fixture.adapter,
        home: const RoutinePlanListScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(RoutinePlanListScreen.createButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(RoutinePlanListScreen.createNameFieldKey),
      'Hybrid Base',
    );
    await tester.enterText(
      find.byKey(RoutinePlanListScreen.createNotesFieldKey),
      'Strength and running',
    );
    final createFinder = find.byKey(
      RoutinePlanListScreen.createSubmitButtonKey,
    );
    final createButton = tester.widget<FilledButton>(createFinder);
    expect(
      createButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      tester.element(createFinder).colors.save,
    );
    await tester.tap(createFinder);
    await tester.pumpAndSettle();

    expect(find.byType(RoutinePlanEditorScreen), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(RoutinePlanEditorScreen.nameFieldKey),
          )
          .controller
          ?.text,
      'Hybrid Base',
    );
    Navigator.of(tester.element(find.byType(RoutinePlanEditorScreen))).pop();
    await tester.pumpAndSettle();

    final routineRecord =
        (await fixture.repositories.routinePlans.listActiveSummaries())
            .singleWhere((routine) => routine.name == 'Hybrid Base');
    await tester.tap(
      find.byKey(RoutinePlanListScreen.archiveButtonKey(routineRecord.id)),
    );
    await tester.pumpAndSettle();
    final archiveFinder = find.widgetWithText(FilledButton, 'Archive Routine');
    final archiveButton = tester.widget<FilledButton>(archiveFinder);
    expect(
      archiveButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      Theme.of(tester.element(archiveFinder)).colorScheme.error,
    );
    await tester.tap(archiveFinder);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(RoutinePlanListScreen.archivedToggleKey));
    await tester.pumpAndSettle();
    expect(
      find.byKey(RoutinePlanListScreen.restoreButtonKey(routineRecord.id)),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(RoutinePlanListScreen.restoreButtonKey(routineRecord.id)),
    );
    await tester.pumpAndSettle();
    final restored = await fixture.repositories.routinePlans.getById(
      routineRecord.id,
    );
    expect(restored?.name, 'Hybrid Base');
    await _disposeWidgetTree(tester);
  });

  testWidgets(
      'Start opens the session picker and materializes the chosen entry '
      'with its Routine and slot', (tester) async {
    await _setLargePhone(tester);
    final fixture = await _fixture();
    _closeAfterTest(fixture);
    await fixture.adapter.setCadence(
      routineId: fixture.routineId,
      cadence: const Cadence.rotating(3),
    );
    await fixture.adapter.moveTemplateReferenceToSlot(
      routineEntryId: fixture.strengthEntryId,
      slot: 2,
    );
    await tester.pumpWidget(
      _testApp(
        adapter: fixture.adapter,
        materializeRepository: RepositoryTemplateMaterializeFeatureRepository(
          fixture.repositories,
        ),
        trainingRepositories: fixture.repositories,
        home: const RoutinePlanListScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(RoutinePlanListScreen.startButtonKey(fixture.routineId)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(RoutineStartSheet.sheetKey), findsOneWidget);
    // The archived-template entry (runEntryId) is not offered.
    expect(
      find.byKey(RoutineStartSheet.entryKey(fixture.runEntryId)),
      findsNothing,
    );

    await tester.tap(
      find.byKey(RoutineStartSheet.entryKey(fixture.strengthEntryId)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(RoutineStartSheet.sheetKey), findsNothing);
    expect(find.byType(WorkoutScreen), findsOneWidget);

    final links = await fixture.repositories.database
        .select(fixture.repositories.database.templateLinks)
        .get();
    expect(links, hasLength(1));
    expect(links.single.routineId, fixture.routineId);
    expect(links.single.slot, 2);
    await _disposeWidgetTree(tester);
  });

  testWidgets(
      'editor manages ordered live references and restores an archived template',
      (tester) async {
    await _setLargePhone(tester);
    final fixture = await _fixture();
    _closeAfterTest(fixture);
    await tester.pumpWidget(
      _testApp(
        adapter: fixture.adapter,
        home: RoutinePlanEditorScreen(routineId: fixture.routineId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Archived Workout Template'), findsOneWidget);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
    await tester.tap(
      find.byKey(
        RoutinePlanEditorScreen.restoreTemplateKey(fixture.runEntryId),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Archived Workout Template'), findsNothing);

    await tester.tap(
      find.byKey(RoutinePlanEditorScreen.addTemplateButtonKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        RoutinePlanEditorScreen.pickerTemplateKey(fixture.mobilityTemplateId),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mobility'), findsOneWidget);

    await tester.tap(
      find.byKey(
        RoutinePlanEditorScreen.entryMenuButtonKey(fixture.strengthEntryId),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        RoutinePlanEditorScreen.moveEntryLaterKey(fixture.strengthEntryId),
      ),
    );
    await tester.pumpAndSettle();
    var detail = await fixture.repositories.routinePlans.getById(
      fixture.routineId,
    );
    expect(
      detail?.entries.map((entry) => entry.templateName),
      <String>['Tempo Run', 'Strength', 'Mobility'],
    );

    final reorderable = tester.widget<ReorderableListView>(
      find.byKey(RoutinePlanEditorScreen.entryListKey),
    );
    reorderable.onReorderItem!(2, 0);
    await tester.pumpAndSettle();
    detail = await fixture.repositories.routinePlans.getById(
      fixture.routineId,
    );
    expect(detail?.entries.first.templateName, 'Mobility');

    await tester.tap(
      find.byKey(
        RoutinePlanEditorScreen.entryMenuButtonKey(fixture.runEntryId),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(RoutinePlanEditorScreen.removeEntryKey(fixture.runEntryId)),
    );
    await tester.pumpAndSettle();
    final removeFinder = find.widgetWithText(
      FilledButton,
      'Remove from Routine',
    );
    final removeButton = tester.widget<FilledButton>(removeFinder);
    expect(
      removeButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      Theme.of(tester.element(removeFinder)).colorScheme.error,
    );
    await tester.tap(removeFinder);
    await tester.pumpAndSettle();
    detail = await fixture.repositories.routinePlans.getById(
      fixture.routineId,
    );
    expect(detail?.entries, hasLength(2));

    await tester.enterText(
      find.byKey(RoutinePlanEditorScreen.nameFieldKey),
      'Hybrid Build',
    );
    await tester.enterText(
      find.byKey(RoutinePlanEditorScreen.notesFieldKey),
      'Updated notes',
    );
    await tester.tap(
      find.byKey(RoutinePlanEditorScreen.saveDetailsButtonKey),
    );
    await tester.pumpAndSettle();
    final renamed = await fixture.repositories.routinePlans.getById(
      fixture.routineId,
    );
    expect(renamed?.notes, 'Updated notes');
    await _disposeWidgetTree(tester);
  });

  testWidgets('external updates rehydrate clean fields and preserve dirty ones',
      (tester) async {
    await _setLargePhone(tester);
    final fixture = await _fixture();
    _closeAfterTest(fixture);
    await tester.pumpWidget(
      _testApp(
        adapter: fixture.adapter,
        home: RoutinePlanEditorScreen(routineId: fixture.routineId),
      ),
    );
    await tester.pumpAndSettle();

    await fixture.repositories.routinePlans.updateRoutine(
      fixture.routineId,
      name: 'External clean name',
      notes: 'External clean notes',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(RoutinePlanEditorScreen.nameFieldKey),
          )
          .controller
          ?.text,
      'External clean name',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(RoutinePlanEditorScreen.notesFieldKey),
          )
          .controller
          ?.text,
      'External clean notes',
    );

    await tester.enterText(
      find.byKey(RoutinePlanEditorScreen.nameFieldKey),
      'User draft name',
    );
    await fixture.repositories.routinePlans.updateRoutine(
      fixture.routineId,
      name: 'External second name',
      notes: 'External second notes',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(RoutinePlanEditorScreen.nameFieldKey),
          )
          .controller
          ?.text,
      'User draft name',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(RoutinePlanEditorScreen.notesFieldKey),
          )
          .controller
          ?.text,
      'External second notes',
    );

    await tester.enterText(
      find.byKey(RoutinePlanEditorScreen.notesFieldKey),
      'User draft notes',
    );
    await fixture.repositories.routinePlans.updateRoutine(
      fixture.routineId,
      name: 'External third name',
      notes: 'External third notes',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(RoutinePlanEditorScreen.nameFieldKey),
          )
          .controller
          ?.text,
      'User draft name',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(RoutinePlanEditorScreen.notesFieldKey),
          )
          .controller
          ?.text,
      'User draft notes',
    );

    await tester.tap(
      find.byKey(RoutinePlanEditorScreen.saveDetailsButtonKey),
    );
    await tester.pumpAndSettle();
    final saved = await fixture.repositories.routinePlans.getById(
      fixture.routineId,
    );
    expect(saved?.name, 'User draft name');
    expect(saved?.notes, 'User draft notes');
    await _disposeWidgetTree(tester);
  });

  testWidgets(
      'Cadence hard errors, warnings, and transitions preserve Entry identity',
      (tester) async {
    await _setLargePhone(tester);
    final fixture = await _fixture();
    _closeAfterTest(fixture);
    final originalEntryIds =
        (await fixture.repositories.routinePlans.getById(fixture.routineId))!
            .entries
            .map((entry) => entry.id)
            .toList(growable: false);
    await tester.pumpWidget(
      _testApp(
        adapter: fixture.adapter,
        home: RoutinePlanEditorScreen(routineId: fixture.routineId),
      ),
    );
    await tester.pumpAndSettle();

    await _selectCadence(tester, 'Rotating');
    await tester.enterText(
      find.byKey(RoutinePlanEditorScreen.rotatingWindowFieldKey),
      '0',
    );
    await tester.tap(
      find.byKey(RoutinePlanEditorScreen.saveCadenceButtonKey),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter a whole number of 1 or more.'), findsOneWidget);
    expect(
      (await fixture.repositories.routinePlans.getById(fixture.routineId))
          ?.cadence,
      isNull,
    );

    await tester.enterText(
      find.byKey(RoutinePlanEditorScreen.rotatingWindowFieldKey),
      '32',
    );
    await tester.tap(
      find.byKey(RoutinePlanEditorScreen.saveCadenceButtonKey),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(RoutinePlanEditorScreen.cadenceWarningDialogKey),
      findsOneWidget,
    );
    final saveAnywayFinder = find.byKey(
      RoutinePlanEditorScreen.cadenceSaveAnywayKey,
    );
    expect(
      tester
          .widget<FilledButton>(saveAnywayFinder)
          .style
          ?.backgroundColor
          ?.resolve(<WidgetState>{}),
      tester.element(saveAnywayFinder).colors.save,
    );
    await tester.tap(saveAnywayFinder);
    await tester.pumpAndSettle();

    var detail = await fixture.repositories.routinePlans.getById(
      fixture.routineId,
    );
    expect(detail?.cadence?.kind, CadenceKind.rotating);
    expect(detail?.cadence?.window, 32);
    expect(detail?.entries.map((entry) => entry.id), originalEntryIds);

    await _selectCadence(tester, 'None');
    await tester.tap(
      find.byKey(RoutinePlanEditorScreen.saveCadenceButtonKey),
    );
    await tester.pumpAndSettle();
    detail = await fixture.repositories.routinePlans.getById(fixture.routineId);
    expect(detail?.cadence, isNull);
    expect(detail?.entries.map((entry) => entry.id), originalEntryIds);
    await _disposeWidgetTree(tester);
  });

  testWidgets(
      'external Cadence updates preserve dirty drafts and rehydrate clean ones',
      (tester) async {
    await _setLargePhone(tester);
    final fixture = await _fixture();
    _closeAfterTest(fixture);
    await tester.pumpWidget(
      _testApp(
        adapter: fixture.adapter,
        home: RoutinePlanEditorScreen(routineId: fixture.routineId),
      ),
    );
    await tester.pumpAndSettle();

    await _selectCadence(tester, 'Weekly');
    await fixture.repositories.routinePlans.setCadence(
      fixture.routineId,
      const Cadence.rotating(3),
    );
    await tester.pumpAndSettle();
    expect(find.text('Weekly'), findsOneWidget);

    await tester.tap(
      find.byKey(RoutinePlanEditorScreen.saveCadenceButtonKey),
    );
    await tester.pumpAndSettle();
    expect(
      (await fixture.repositories.routinePlans.getById(fixture.routineId))
          ?.cadence
          ?.kind,
      CadenceKind.weekly,
    );

    await fixture.repositories.routinePlans.setCadence(
      fixture.routineId,
      null,
    );
    await tester.pumpAndSettle();
    expect(find.text('None'), findsOneWidget);
    await _disposeWidgetTree(tester);
  });

  testWidgets(
      'slot layout supports targeted add, drag, accessible moves, and archived references',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _fixture();
    _closeAfterTest(fixture);
    await fixture.adapter.setCadence(
      routineId: fixture.routineId,
      cadence: const Cadence.weekly(),
    );
    final mobilityEntryId = await fixture.adapter.addTemplateReference(
      routineId: fixture.routineId,
      workoutTemplateId: fixture.mobilityTemplateId,
      slot: 1,
    );
    await tester.pumpWidget(
      _testApp(
        adapter: fixture.adapter,
        home: RoutinePlanEditorScreen(routineId: fixture.routineId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rest'), findsNWidgets(5));
    await tester.tap(
      find.byKey(RoutinePlanEditorScreen.addTemplateToSlotKey(1)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        RoutinePlanEditorScreen.pickerTemplateKey(fixture.mobilityTemplateId),
      ),
    );
    await tester.pumpAndSettle();
    var detail = await fixture.repositories.routinePlans.getById(
      fixture.routineId,
    );
    final addedEntry = detail!.entries.singleWhere(
      (entry) =>
          entry.workoutTemplateId == fixture.mobilityTemplateId &&
          entry.id != mobilityEntryId,
    );
    expect(addedEntry.slot, 1);

    final dragHandle = find.byKey(
      RoutinePlanEditorScreen.reorderEntryHandleKey(fixture.strengthEntryId),
    );
    final thirdSlot = find.byKey(
      RoutinePlanEditorScreen.slotDragTargetKey(3),
    );
    await tester.dragFrom(
      tester.getCenter(dragHandle),
      tester.getCenter(thirdSlot) - tester.getCenter(dragHandle),
    );
    await tester.pumpAndSettle();
    detail = await fixture.repositories.routinePlans.getById(fixture.routineId);
    expect(
      detail?.entries
          .singleWhere(
            (entry) => entry.id == fixture.strengthEntryId,
          )
          .slot,
      3,
    );

    await tester.tap(
      find.byKey(
        RoutinePlanEditorScreen.entryMenuButtonKey(fixture.runEntryId),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        RoutinePlanEditorScreen.moveEntryToSlotKey(fixture.runEntryId),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(RoutinePlanEditorScreen.moveToSlotOptionKey(1)),
    );
    await tester.pumpAndSettle();
    detail = await fixture.repositories.routinePlans.getById(fixture.routineId);
    expect(
      detail?.entries
          .singleWhere((entry) => entry.id == fixture.runEntryId)
          .slot,
      1,
    );
    expect(
      find.byKey(
        RoutinePlanEditorScreen.restoreTemplateKey(fixture.runEntryId),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        RoutinePlanEditorScreen.restoreTemplateKey(fixture.runEntryId),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(RoutinePlanEditorScreen.entryMenuButtonKey(mobilityEntryId)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        RoutinePlanEditorScreen.moveEntryEarlierKey(mobilityEntryId),
      ),
    );
    await tester.pumpAndSettle();
    detail = await fixture.repositories.routinePlans.getById(fixture.routineId);
    expect(
      detail?.entries.where((entry) => entry.slot == 1).first.id,
      mobilityEntryId,
    );
    await _disposeWidgetTree(tester);
  });

  testWidgets('large accepted rotation lazily builds only visible slots',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _fixture();
    _closeAfterTest(fixture);
    await fixture.adapter.setCadence(
      routineId: fixture.routineId,
      cadence: const Cadence.rotating(1000),
    );
    await tester.pumpWidget(
      _testApp(
        adapter: fixture.adapter,
        home: RoutinePlanEditorScreen(routineId: fixture.routineId),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(RoutinePlanEditorScreen.slotCardKey(1)),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final detail = await fixture.repositories.routinePlans.getById(
      fixture.routineId,
    );
    expect(detail?.cadence?.window, 1000);
    expect(
      find.byType(DragTarget<RoutineEntryDetail>).evaluate().length,
      lessThan(30),
    );
    expect(
      find.byKey(RoutinePlanEditorScreen.slotCardKey(1000)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await _disposeWidgetTree(tester);
  });

  testWidgets(
      'drag handle opens Move-to and direct drag auto-scrolls with primary feedback',
      (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _fixture();
    _closeAfterTest(fixture);
    await fixture.adapter.setCadence(
      routineId: fixture.routineId,
      cadence: const Cadence.rotating(20),
    );
    await tester.pumpWidget(
      _testApp(
        adapter: fixture.adapter,
        home: RoutinePlanEditorScreen(routineId: fixture.routineId),
      ),
    );
    await tester.pumpAndSettle();

    final dragHandle = find.byKey(
      RoutinePlanEditorScreen.reorderEntryHandleKey(fixture.strengthEntryId),
    );
    await tester.scrollUntilVisible(
      dragHandle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final semanticNode = tester.getSemantics(
      find.bySemanticsLabel('Reorder Strength'),
    );
    expect(
        semanticNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(dragHandle);
    await tester.pumpAndSettle();
    expect(find.text('Move Strength'), findsOneWidget);
    Navigator.of(tester.element(find.text('Move Strength'))).pop();
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final startingOffset = scrollable.position.pixels;
    final secondSlot = find.byKey(
      RoutinePlanEditorScreen.slotDragTargetKey(2),
    );
    final gesture = await tester.startGesture(tester.getCenter(dragHandle));
    await gesture.moveTo(tester.getCenter(secondSlot));
    await tester.pump(const Duration(milliseconds: 150));

    final feedback = tester.widget<DecoratedBox>(
      find.byKey(
        RoutinePlanEditorScreen.dragFeedbackKey(fixture.strengthEntryId),
      ),
    );
    final feedbackDecoration = feedback.decoration as BoxDecoration;
    final primary = Theme.of(tester.element(secondSlot)).colorScheme.primary;
    expect(feedbackDecoration.color, primary);
    final target = tester.widget<AnimatedContainer>(
      find.byKey(RoutinePlanEditorScreen.slotHighlightKey(2)),
    );
    final targetBorder =
        (target.decoration! as BoxDecoration).border! as Border;
    expect(targetBorder.top.color, primary);

    await gesture.moveTo(const Offset(400, 1195));
    await tester.pump(const Duration(milliseconds: 900));
    expect(scrollable.position.pixels, greaterThan(startingOffset + 100));
    await gesture.up();
    await tester.pumpAndSettle();
    semanticsHandle.dispose();
    await _disposeWidgetTree(tester);
  });

  testWidgets('Cadence editor remains usable with large text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await _fixture();
    _closeAfterTest(fixture);
    await fixture.adapter.setCadence(
      routineId: fixture.routineId,
      cadence: const Cadence.rotating(2),
    );
    await tester.pumpWidget(
      _testApp(
        adapter: fixture.adapter,
        textScaler: const TextScaler.linear(2),
        home: RoutinePlanEditorScreen(routineId: fixture.routineId),
      ),
    );
    await tester.pumpAndSettle();

    final secondSlot = find.byKey(RoutinePlanEditorScreen.slotCardKey(2));
    await tester.scrollUntilVisible(
      secondSlot,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(secondSlot, findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeWidgetTree(tester);
  });

  testWidgets('create sheet remains usable with keyboard and large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 560);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final fixture = await _fixture(seedRoutine: false);
    _closeAfterTest(fixture);
    await tester.pumpWidget(
      _testApp(
        adapter: fixture.adapter,
        textScaler: const TextScaler.linear(2),
        home: const RoutinePlanListScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RoutinePlanListScreen.createButtonKey));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();

    final saveButton = find.byKey(
      RoutinePlanListScreen.createSubmitButtonKey,
    );
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    expect(saveButton, findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeWidgetTree(tester);
  });
}

/// Default materialize repository for tests that never tap Start — any call
/// is a test-shape bug, so it fails loudly instead of touching real storage.
class _UnusedTemplateMaterializeFeatureRepository
    implements TemplateMaterializeFeatureRepository {
  @override
  Future<String> materializeTemplate({
    required String workoutTemplateId,
    String? routineId,
    int? slot,
  }) {
    throw UnsupportedError(
      'This test did not provide a TemplateMaterializeFeatureRepository.',
    );
  }
}

Widget _testApp({
  required RepositoryRoutinePlanFeatureRepository adapter,
  required Widget home,
  TemplateMaterializeFeatureRepository? materializeRepository,
  TrainingRepositories? trainingRepositories,
  Brightness brightness = Brightness.light,
  TextScaler? textScaler,
}) {
  return ProviderScope(
    overrides: [
      routinePlanFeatureRepositoryProvider.overrideWith((ref) => adapter),
      templateMaterializeFeatureRepositoryProvider.overrideWith(
        (ref) =>
            materializeRepository ?? _UnusedTemplateMaterializeFeatureRepository(),
      ),
      if (trainingRepositories != null)
        trainingRepositoriesProvider.overrideWithValue(trainingRepositories),
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
        if (textScaler == null) {
          return child!;
        }
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        );
      },
      onGenerateRoute: (settings) {
        if (settings.name == RoutinePlanEditorScreen.routeName &&
            settings.arguments is String) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => RoutinePlanEditorScreen(
              routineId: settings.arguments! as String,
            ),
          );
        }
        if (settings.name == WorkoutTemplateEditorScreen.routeName) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('Template editor')),
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

Future<void> _selectCadence(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await tester.pumpAndSettle();
}

void _closeAfterTest(_RoutineFixture fixture) {
  addTearDown(fixture.close);
}

Future<void> _disposeWidgetTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<_RoutineFixture> _fixture({bool seedRoutine = true}) async {
  final database = AppDatabase.inMemory();
  final repositories = TrainingRepositories(database);
  final adapter = RepositoryRoutinePlanFeatureRepository(repositories);
  final strengthTemplateId = await repositories.workoutTemplates.create(
    const WorkoutTemplateDraft(name: 'Strength', notes: 'Main lifts'),
  );
  final runTemplateId = await repositories.workoutTemplates.create(
    const WorkoutTemplateDraft(name: 'Tempo Run', notes: 'Eight kilometres'),
  );
  final mobilityTemplateId = await repositories.workoutTemplates.create(
    const WorkoutTemplateDraft(name: 'Mobility'),
  );
  if (!seedRoutine) {
    return _RoutineFixture(
      database: database,
      repositories: repositories,
      adapter: adapter,
      routineId: '',
      strengthEntryId: '',
      runEntryId: '',
      mobilityTemplateId: mobilityTemplateId,
    );
  }
  final routineId = await adapter.createRoutine(
    name: 'Hybrid week',
    notes: 'Three sessions',
  );
  final strengthEntryId = await adapter.addTemplateReference(
    routineId: routineId,
    workoutTemplateId: strengthTemplateId,
  );
  final runEntryId = await adapter.addTemplateReference(
    routineId: routineId,
    workoutTemplateId: runTemplateId,
  );
  await repositories.workoutTemplates.archive(runTemplateId);
  return _RoutineFixture(
    database: database,
    repositories: repositories,
    adapter: adapter,
    routineId: routineId,
    strengthEntryId: strengthEntryId,
    runEntryId: runEntryId,
    mobilityTemplateId: mobilityTemplateId,
  );
}

final class _RoutineFixture {
  const _RoutineFixture({
    required this.database,
    required this.repositories,
    required this.adapter,
    required this.routineId,
    required this.strengthEntryId,
    required this.runEntryId,
    required this.mobilityTemplateId,
  });

  final AppDatabase database;
  final TrainingRepositories repositories;
  final RepositoryRoutinePlanFeatureRepository adapter;
  final String routineId;
  final String strengthEntryId;
  final String runEntryId;
  final String mobilityTemplateId;

  Future<void> close() => database.close();
}
