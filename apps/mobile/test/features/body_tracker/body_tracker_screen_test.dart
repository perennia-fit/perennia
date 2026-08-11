import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/body_tracker/widgets/body_tracker_screen.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

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

  testWidgets('Track screen meets accessibility guidelines in both themes', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);

      await _pumpBodyTrackerScreen(tester, database: database, theme: theme);
      await _pumpUntilFound(tester, find.text('Body Weight'));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.text('Body Weight'));
      await tester.pumpAndSettle();
      await _pumpUntilFound(
          tester, find.byKey(BodyTrackerScreen.valueFieldKey));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await _disposeBodyTrackerWidgetTree(tester);
    }
  });

  testWidgets('History screen meets accessibility guidelines in both themes', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);

      await _pumpBodyTrackerScreen(tester, database: database, theme: theme);
      await _pumpUntilFound(tester, find.text('Body Weight'));

      await _saveMeasurementEntry(
        tester,
        measurementName: 'Body Weight',
        value: '82',
        measuredAt: '2026-06-23 07:30',
      );
      await _saveMeasurementEntry(
        tester,
        measurementName: 'Body Weight',
        value: '80',
        measuredAt: '2026-06-24 07:30',
        comment: 'After cut',
      );

      await tester.tap(find.byKey(BodyTrackerScreen.historyButtonKey));
      await tester.pumpAndSettle();
      await _pumpUntilFound(tester, find.text('History'));
      await _pumpUntilFound(tester, find.text('-2 kg'));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.text('80 kg'));
      await tester.pumpAndSettle();
      await _pumpUntilFound(
        tester,
        find.byKey(BodyTrackerScreen.valueFieldKey),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await _pumpUntilFound(tester, find.text('Delete measurement entry?'));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await _disposeBodyTrackerWidgetTree(tester);
    }
  });

  testWidgets(
      'Imported Body Tracker provenance states meet accessibility guidelines', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repositories = TrainingRepositories(database);
      await repositories.measurements.ensureDefaultMeasurements(
        bodyWeightUnit: MeasurementUnit.kilogram,
      );
      final bodyWeight = (await repositories.measurements.listEnabled())
          .singleWhere((measurement) => measurement.name == 'Body Weight');
      await repositories.measurements.createEntry(
        MeasurementEntryDraft(
          measurementId: bodyWeight.id,
          valueEntered: '82',
          measuredAt: DateTime.utc(2026, 6, 23, 7, 30),
        ),
      );
      await repositories.metrics.upsertIntegrationReadings(
        <IntegrationMetricReadingDraft>[
          IntegrationMetricReadingDraft.scalar(
            metricId: bodyWeight.id,
            valueEntered: '80.5',
            atTime: DateTime.utc(2026, 6, 24, 7, 30),
            source: 'garmin',
            externalId: 'scale-2026-06-24:body-weight',
          ),
        ],
      );

      await _pumpBodyTrackerScreen(tester, database: database, theme: theme);
      await _pumpUntilFound(tester, find.text('80.5 kg'));
      await tester.tap(find.byKey(BodyTrackerScreen.historyButtonKey));
      await tester.pumpAndSettle();
      await _pumpUntilFound(tester, find.text('History'));
      await _pumpUntilFound(tester, find.textContaining('Source garmin'));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _openMeasurementEntry(tester, 'Body Weight');
      await tester.tap(find.byKey(BodyTrackerScreen.progressButtonKey));
      await tester.pumpAndSettle();
      await _pumpUntilFound(tester, find.text('Progress'));

      final graph = find.byKey(BodyTrackerScreen.progressGraphKey(
        bodyWeight.id,
      ));
      await _pumpUntilFound(tester, graph);
      final graphRect = tester.getRect(graph);
      await tester.tapAt(Offset(graphRect.right - 2, graphRect.center.dy));
      await tester.pumpAndSettle();
      await _pumpUntilFound(tester, find.textContaining('Source garmin'));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await _disposeBodyTrackerWidgetTree(tester);
    }
  });

  testWidgets('Measurement management meets accessibility guidelines', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);

      await _pumpBodyTrackerScreen(tester, database: database, theme: theme);
      await _pumpUntilFound(tester, find.text('Body Weight'));

      await _openMeasurementManagement(tester);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.byKey(BodyTrackerScreen.addMeasurementButtonKey));
      await tester.pumpAndSettle();
      await _pumpUntilFound(tester, find.text('New measurement'));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await _disposeBodyTrackerWidgetTree(tester);
    }
  });

  testWidgets('Measurement management creates, toggles, archives, and resets', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _pumpBodyTrackerScreen(tester, database: database);
    await _pumpUntilFound(tester, find.text('Body Weight'));

    await _openMeasurementManagement(tester);
    await _createMeasurement(
      tester,
      name: 'Waist',
      goalLabel: 'Target',
      targetValue: '80',
    );
    await _pumpUntilFound(tester, find.text('Waist'));

    final waist = await _measurementRowByName(tester, database, 'Waist');
    expect(waist.unit, 'centimeter');
    expect(waist.goalType, 'target');
    expect(waist.goalTargetValue, 80);
    expect(waist.enabled, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Waist'));
    expect(find.text('Body Fat'), findsOneWidget);

    await _openMeasurementManagement(tester);
    final bodyFat = await _measurementRowByName(tester, database, 'Body Fat');
    await tester.tap(
      find.byKey(BodyTrackerScreen.measurementEnabledSwitchKey(bodyFat.id)),
    );
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _pumpUntilGone(tester, find.text('Body Fat'));
    expect(find.text('Waist'), findsOneWidget);

    await _openMeasurementManagement(tester);
    await tester.tap(
      find.byKey(BodyTrackerScreen.measurementDeleteButtonKey(waist.id)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Archive measurement?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();
    await _pumpUntilGone(tester, find.text('Waist'));

    final archivedWaist =
        await _measurementRowByName(tester, database, 'Waist');
    expect(archivedWaist.deletedAt, isNotNull);

    await tester.tap(find.byKey(BodyTrackerScreen.resetMeasurementsButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Reset measurements?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Body Fat'));

    expect(
      await _activeMeasurementNames(tester, database),
      <String>['Body Weight', 'Body Fat'],
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Body Fat'));
    expect(find.text('Waist'), findsNothing);

    await _disposeBodyTrackerWidgetTree(tester);
  });

  testWidgets('Progress screen meets accessibility guidelines', (
    tester,
  ) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);

      await _pumpBodyTrackerScreen(tester, database: database, theme: theme);
      await _pumpUntilFound(tester, find.text('Body Weight'));
      await _saveBodyWeightEntry(
        tester,
        value: '82',
        measuredAt: '2026-06-23 07:30',
      );
      await _saveBodyWeightEntry(
        tester,
        value: '80',
        measuredAt: '2026-06-24 07:30',
      );

      await _openMeasurementEntry(tester, 'Body Weight');
      await tester.tap(find.byKey(BodyTrackerScreen.progressButtonKey));
      await tester.pumpAndSettle();
      await _pumpUntilFound(tester, find.text('Progress'));
      final graphSemantics = find.bySemanticsLabel(
        'Progress graph, Body Weight, 2 raw points',
      );
      expect(graphSemantics, findsOneWidget);
      expect(
        tester.getSemantics(graphSemantics).getSemanticsData().hint,
        'Tap to inspect a raw graph value',
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await _disposeBodyTrackerWidgetTree(tester);
    }
  });

  testWidgets('Progress screen renders trend and conditional target lines', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _pumpBodyTrackerScreen(tester, database: database);
    await _pumpUntilFound(tester, find.text('Body Weight'));
    await _saveBodyWeightEntry(
      tester,
      value: '82',
      measuredAt: '2026-06-23 07:30',
    );
    await _saveBodyWeightEntry(
      tester,
      value: '80',
      measuredAt: '2026-06-24 07:30',
    );
    final bodyWeight = await _measurementRowByName(
      tester,
      database,
      'Body Weight',
    );

    await _openMeasurementEntry(tester, 'Body Weight');
    await tester.tap(find.byKey(BodyTrackerScreen.progressButtonKey));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Progress'));

    expect(
      find.byKey(BodyTrackerScreen.progressGraphKey(bodyWeight.id)),
      findsOneWidget,
    );
    expect(find.byKey(BodyTrackerScreen.progressTargetLineKey), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BodyTrackerScreen.historyButtonKey));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('History'));
    await tester.tap(find.byKey(BodyTrackerScreen.progressButtonKey));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Progress'));
    expect(
      find.byKey(BodyTrackerScreen.progressGraphKey(bodyWeight.id)),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openMeasurementManagement(tester);
    await _createMeasurement(
      tester,
      name: 'Waist',
      goalLabel: 'Target',
      targetValue: '80',
    );
    await _pumpUntilFound(tester, find.text('Waist'));
    final waist = await _measurementRowByName(tester, database, 'Waist');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _saveMeasurementEntry(
      tester,
      measurementName: 'Waist',
      value: '83',
      measuredAt: '2026-06-23 07:30',
    );
    await _saveMeasurementEntry(
      tester,
      measurementName: 'Waist',
      value: '81',
      measuredAt: '2026-06-24 07:30',
    );
    await _openMeasurementEntry(tester, 'Waist');
    await tester.tap(find.byKey(BodyTrackerScreen.progressButtonKey));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('Progress'));

    expect(
      find.byKey(BodyTrackerScreen.progressGraphKey(waist.id)),
      findsOneWidget,
    );
    expect(find.text('Target 80 cm'), findsOneWidget);
    expect(find.byKey(BodyTrackerScreen.progressTargetLineKey), findsOneWidget);

    await _disposeBodyTrackerWidgetTree(tester);
  });

  testWidgets('Track screen lists defaults and saves Body Weight', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _pumpBodyTrackerScreen(tester, database: database);
    await _pumpUntilFound(tester, find.text('Body Weight'));

    expect(find.text('Body Fat'), findsOneWidget);
    expect(find.text('No value yet'), findsNWidgets(2));

    await _openBodyWeightEntry(tester);
    await tester.enterText(
      find.byKey(BodyTrackerScreen.valueFieldKey),
      '82.125',
    );
    await tester.enterText(
      find.byKey(BodyTrackerScreen.commentFieldKey),
      'After breakfast',
    );
    await tester.enterText(
      find.byKey(BodyTrackerScreen.measuredAtFieldKey),
      '2026-06-23 07:30',
    );

    await tester.tap(find.byKey(BodyTrackerScreen.saveEntryButtonKey));
    await tester.pump();
    expect(
      find.byKey(BodyTrackerScreen.suspiciousValueDialogKey),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilGone(tester, find.byKey(BodyTrackerScreen.valueFieldKey));
    await _pumpUntilFound(tester, find.text('82.125 kg'));

    expect(find.text('82.125 kg'), findsOneWidget);
    expect(find.byKey(BodyTrackerScreen.deltaBadgeKey), findsNothing);
    expect(find.textContaining('Last measured'), findsOneWidget);
    expect(find.text('After breakfast'), findsNothing);

    await _disposeBodyTrackerWidgetTree(tester);
  });

  testWidgets('Track screen shows goal-direction delta after two entries', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _pumpBodyTrackerScreen(tester, database: database);
    await _pumpUntilFound(tester, find.text('Body Weight'));

    await _saveBodyWeightEntry(
      tester,
      value: '82',
      measuredAt: '2026-06-23 07:30',
    );
    await _pumpUntilFound(tester, find.text('82 kg'));

    expect(find.byKey(BodyTrackerScreen.deltaBadgeKey), findsNothing);

    await _saveBodyWeightEntry(
      tester,
      value: '80',
      measuredAt: '2026-06-24 07:30',
    );
    await _pumpUntilFound(tester, find.text('80 kg'));
    await _pumpUntilFound(tester, find.text('-2 kg'));

    final badgeDecoration = tester
        .widget<DecoratedBox>(
          find.byKey(BodyTrackerScreen.deltaBadgeKey),
        )
        .decoration as BoxDecoration;
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(BodyTrackerScreen.deltaBadgeKey),
        matching: find.byIcon(Icons.check),
      ),
    );

    expect(find.text('-2 kg'), findsOneWidget);
    expect(badgeDecoration.color, DesignTokens.save);
    expect(icon.color, DesignTokens.onSave);

    await _disposeBodyTrackerWidgetTree(tester);
  });

  testWidgets('History screen filters, edits, and deletes entries', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _pumpBodyTrackerScreen(tester, database: database);
    await _pumpUntilFound(tester, find.text('Body Weight'));

    await _saveMeasurementEntry(
      tester,
      measurementName: 'Body Weight',
      value: '82',
      measuredAt: '2026-06-23 07:30',
      comment: 'Before cut',
    );
    await _saveMeasurementEntry(
      tester,
      measurementName: 'Body Weight',
      value: '80',
      measuredAt: '2026-06-24 07:30',
      comment: 'After cut',
    );
    await _saveMeasurementEntry(
      tester,
      measurementName: 'Body Fat',
      value: '20',
      measuredAt: '2026-06-25 07:30',
    );

    await tester.tap(find.byKey(BodyTrackerScreen.historyButtonKey));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('History'));
    await _pumpUntilFound(tester, find.text('20 %'));
    await _pumpUntilFound(tester, find.text('80 kg'));
    await _pumpUntilFound(tester, find.text('-2 kg'));

    await tester.tap(find.byKey(BodyTrackerScreen.historyFilterKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Body Weight').last);
    await tester.pumpAndSettle();

    expect(find.text('20 %'), findsNothing);
    expect(find.text('80 kg'), findsOneWidget);
    expect(find.text('82 kg'), findsOneWidget);

    await tester.tap(find.text('80 kg'));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.byKey(BodyTrackerScreen.valueFieldKey));
    await tester.enterText(find.byKey(BodyTrackerScreen.valueFieldKey), '79');
    await tester.enterText(
      find.byKey(BodyTrackerScreen.commentFieldKey),
      'Updated after cut',
    );
    await tester.enterText(
      find.byKey(BodyTrackerScreen.measuredAtFieldKey),
      '2026-06-26 08:45',
    );
    await tester.tap(find.byKey(BodyTrackerScreen.saveEntryButtonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilGone(tester, find.byKey(BodyTrackerScreen.valueFieldKey));
    await _pumpUntilFound(tester, find.text('79 kg'));
    await _pumpUntilFound(tester, find.text('-3 kg'));
    expect(find.textContaining('Updated after cut'), findsOneWidget);
    expect(find.textContaining('2026-06-26 08:45'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('Delete measurement entry?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete measurement entry?'), findsNothing);
    await _pumpUntilGone(tester, find.text('79 kg'));

    expect(find.text('82 kg'), findsOneWidget);
    await _disposeBodyTrackerWidgetTree(tester);
  });

  testWidgets(
      'History marks imported body-composition Readings and keeps them read-only',
      (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    await repositories.measurements.ensureDefaultMeasurements(
      bodyWeightUnit: MeasurementUnit.kilogram,
    );
    final bodyWeight = (await repositories.measurements.listEnabled())
        .singleWhere((measurement) => measurement.name == 'Body Weight');
    final manualId = await repositories.measurements.createEntry(
      MeasurementEntryDraft(
        measurementId: bodyWeight.id,
        valueEntered: '82',
        measuredAt: DateTime.utc(2026, 6, 23, 7, 30),
      ),
    );
    final importedId = (await repositories.metrics.upsertIntegrationReadings(
      <IntegrationMetricReadingDraft>[
        IntegrationMetricReadingDraft.scalar(
          metricId: bodyWeight.id,
          valueEntered: '80.5',
          atTime: DateTime.utc(2026, 6, 24, 7, 30),
          source: 'garmin',
          externalId: 'scale-2026-06-24:body-weight',
        ),
      ],
    ))
        .single;

    await _pumpBodyTrackerScreen(tester, database: database);
    await _pumpUntilFound(tester, find.text('80.5 kg'));
    await tester.tap(find.byKey(BodyTrackerScreen.historyButtonKey));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('History'));

    expect(find.textContaining('Integration'), findsOneWidget);
    expect(find.textContaining('Source garmin'), findsOneWidget);
    expect(find.textContaining('Manual'), findsOneWidget);

    await tester.tap(
      find.byKey(BodyTrackerScreen.historyEntryTileKey(importedId)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(BodyTrackerScreen.valueFieldKey), findsNothing);

    await tester.tap(
      find.byKey(BodyTrackerScreen.historyEntryTileKey(manualId)),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.byKey(BodyTrackerScreen.valueFieldKey));

    await _disposeBodyTrackerWidgetTree(tester);
  });

  testWidgets('Track screen confirms suspicious values before saving',
      (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _pumpBodyTrackerScreen(tester, database: database);
    await _pumpUntilFound(tester, find.text('Body Weight'));
    await _openBodyWeightEntry(tester);

    await tester.enterText(
      find.byKey(BodyTrackerScreen.valueFieldKey),
      '5000',
    );
    await tester.enterText(
      find.byKey(BodyTrackerScreen.measuredAtFieldKey),
      '2026-06-23 07:30',
    );

    await tester.tap(find.byKey(BodyTrackerScreen.saveEntryButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(BodyTrackerScreen.suspiciousValueDialogKey), findsOne);
    expect(find.text('Unusual measurement value'), findsOneWidget);
    expect(
      find.text('5000 kg is outside the usual range. Save it anyway?'),
      findsOneWidget,
    );
    expect(await _measurementEntryCount(tester, database), 0);

    await tester.tap(
      find.byKey(BodyTrackerScreen.suspiciousValueConfirmButtonKey),
    );
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('5000 kg'));

    expect(await _measurementEntryCount(tester, database), 1);

    await _disposeBodyTrackerWidgetTree(tester);
  });

  testWidgets('Track screen surfaces invalid measurement values without saving',
      (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _pumpBodyTrackerScreen(tester, database: database);
    await _pumpUntilFound(tester, find.text('Body Weight'));
    await _openBodyWeightEntry(tester);

    await tester.enterText(find.byKey(BodyTrackerScreen.valueFieldKey), '-0.1');
    await tester.enterText(
      find.byKey(BodyTrackerScreen.measuredAtFieldKey),
      '2026-06-23 07:30',
    );
    await tester.tap(find.byKey(BodyTrackerScreen.saveEntryButtonKey));
    await tester.pump();

    expect(
      find.text('Enter a non-negative value with up to 5 decimals'),
      findsOneWidget,
    );
    expect(find.byKey(BodyTrackerScreen.valueFieldKey), findsOneWidget);
    expect(await _measurementEntryCount(tester, database), 0);

    await _disposeBodyTrackerWidgetTree(tester);
  });

  testWidgets('Track screen surfaces invalid measurement dates without saving',
      (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _pumpBodyTrackerScreen(tester, database: database);
    await _pumpUntilFound(tester, find.text('Body Weight'));
    await _openBodyWeightEntry(tester);

    await tester.enterText(find.byKey(BodyTrackerScreen.valueFieldKey), '82.1');
    await tester.enterText(
      find.byKey(BodyTrackerScreen.measuredAtFieldKey),
      'tomorrow morning',
    );
    await tester.tap(find.byKey(BodyTrackerScreen.saveEntryButtonKey));
    await tester.pump();

    expect(find.text('Use YYYY-MM-DD HH:mm'), findsOneWidget);
    expect(find.byKey(BodyTrackerScreen.valueFieldKey), findsOneWidget);
    expect(await _measurementEntryCount(tester, database), 0);

    await _disposeBodyTrackerWidgetTree(tester);
  });
}

Future<void> _pumpBodyTrackerScreen(
  WidgetTester tester, {
  required AppDatabase database,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => database),
        settingsRepositoryProvider.overrideWith(
          (ref) => InMemorySettingsRepository(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.light(),
        home: const BodyTrackerScreen(),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _disposeBodyTrackerWidgetTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 5; i += 1) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
}

Future<void> _openBodyWeightEntry(WidgetTester tester) async {
  await _openMeasurementEntry(tester, 'Body Weight');
}

Future<void> _openMeasurementManagement(WidgetTester tester) async {
  await tester.tap(find.byKey(BodyTrackerScreen.manageButtonKey));
  await tester.pumpAndSettle();
  await _pumpUntilFound(tester, find.text('Manage measurements'));
}

Future<void> _createMeasurement(
  WidgetTester tester, {
  required String name,
  String? goalLabel,
  String? targetValue,
}) async {
  await tester.tap(find.byKey(BodyTrackerScreen.addMeasurementButtonKey));
  await tester.pumpAndSettle();
  await _pumpUntilFound(tester, find.text('New measurement'));

  await tester.enterText(
    find.byKey(BodyTrackerScreen.measurementNameFieldKey),
    name,
  );
  if (goalLabel != null) {
    await tester.tap(find.byKey(BodyTrackerScreen.measurementGoalFieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(goalLabel).last);
    await tester.pumpAndSettle();
  }
  if (targetValue != null) {
    await tester.enterText(
      find.byKey(BodyTrackerScreen.measurementTargetValueFieldKey),
      targetValue,
    );
  }
  await tester.tap(find.byKey(BodyTrackerScreen.saveMeasurementButtonKey));
  await tester.pumpAndSettle();
}

Future<void> _openMeasurementEntry(
  WidgetTester tester,
  String measurementName,
) async {
  await tester.tap(find.text(measurementName));
  await tester.pumpAndSettle();
  await _pumpUntilFound(tester, find.byKey(BodyTrackerScreen.valueFieldKey));
}

Future<void> _saveBodyWeightEntry(
  WidgetTester tester, {
  required String value,
  required String measuredAt,
}) async {
  await _saveMeasurementEntry(
    tester,
    measurementName: 'Body Weight',
    value: value,
    measuredAt: measuredAt,
  );
}

Future<void> _saveMeasurementEntry(
  WidgetTester tester, {
  required String measurementName,
  required String value,
  required String measuredAt,
  String? comment,
}) async {
  await _openMeasurementEntry(tester, measurementName);
  await tester.enterText(find.byKey(BodyTrackerScreen.valueFieldKey), value);
  if (comment != null) {
    await tester.enterText(
      find.byKey(BodyTrackerScreen.commentFieldKey),
      comment,
    );
  }
  await tester.enterText(
    find.byKey(BodyTrackerScreen.measuredAtFieldKey),
    measuredAt,
  );
  await tester.tap(find.byKey(BodyTrackerScreen.saveEntryButtonKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await _pumpUntilGone(tester, find.byKey(BodyTrackerScreen.valueFieldKey));
}

Future<int> _measurementEntryCount(
  WidgetTester tester,
  AppDatabase database,
) async {
  final rows = await tester.runAsync(
    () => database.select(database.metricReadings).get(),
  );
  return rows?.length ?? 0;
}

Future<MetricRow> _measurementRowByName(
  WidgetTester tester,
  AppDatabase database,
  String name,
) async {
  final rows = await tester.runAsync<List<MetricRow>>(
    () => database.select(database.metrics).get(),
  );
  return rows!.singleWhere((row) => row.name == name);
}

Future<List<String>> _activeMeasurementNames(
  WidgetTester tester,
  AppDatabase database,
) async {
  final rows = await tester.runAsync<List<MetricRow>>(
    () => database.select(database.metrics).get(),
  );
  final active = rows!.where((row) => row.deletedAt == null).toList()
    ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
  return active.map((row) => row.name).toList(growable: false);
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Could not find $finder.');
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (finder.evaluate().isEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Expected $finder to be gone.');
}
