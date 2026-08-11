import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/metrics/widgets/metrics_screen.dart';
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

  testWidgets('renders grouped integration Reading summaries', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _seedGarminMetrics(database);
    await _pumpMetricsScreen(tester, database: database);
    await _pumpUntilFound(tester, find.text('Cardiovascular'));

    expect(find.byType(MetricsScreen), findsOneWidget);
    expect(find.text('Cardiovascular'), findsOneWidget);
    expect(find.text('Resting Heart Rate'), findsNothing);
    expect(find.text('60 bpm'), findsNothing);
    expect(find.text('Activity & Energy'), findsOneWidget);
    expect(find.text('Steps'), findsNothing);

    await tester.tap(find.text('Cardiovascular'));
    await tester.pumpAndSettle();

    expect(find.text('Heart Rate'), findsOneWidget);
    expect(find.text('Resting Heart Rate'), findsOneWidget);
    expect(find.text('60 bpm'), findsOneWidget);
    expect(find.text('Integration'), findsNothing);
    expect(find.text('Source garmin'), findsWidgets);
    expect(find.text('-2 bpm'), findsOneWidget);

    await tester.tap(find.text('Activity & Energy'));
    await tester.pumpAndSettle();

    expect(find.text('Movement'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);

    await _disposeMetricsWidgetTree(tester);
  });

  testWidgets('opens a Metric detail screen with the time series',
      (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _seedGarminMetrics(database);
    await _pumpMetricsScreen(tester, database: database);
    await _pumpUntilFound(tester, find.text('Cardiovascular'));

    await tester.tap(find.text('Cardiovascular'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resting Heart Rate').first);
    await tester.pumpAndSettle();

    expect(find.byType(MetricDetailScreen), findsOneWidget);
    expect(find.byKey(MetricDetailScreen.chartKey), findsOneWidget);
    expect(find.text('Raw'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('60 bpm'), findsWidgets);

    await _disposeMetricsWidgetTree(tester);
  });

  testWidgets('meets accessibility guidelines in both themes', (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);

      await _seedGarminMetrics(database);
      await _pumpMetricsScreen(tester, database: database, theme: theme);
      await _pumpUntilFound(tester, find.text('Cardiovascular'));
      await tester.tap(find.text('Cardiovascular'));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await _disposeMetricsWidgetTree(tester);
    }
  });

  // the Metric domain (M12) already stores/reads any Metric
  // generically (Effect view repository/golden coverage proves the read
  // side), but nothing in-app could create a manually-entered, non-body-
  // composition Metric (e.g. a biomarker) before this — `createMetric`/
  // `createManualReading` had zero call sites outside tests. This closes
  // that gap with the minimal "Add Metric" + "Log reading" affordance so a
  // biomarker Metric a user creates here is immediately selectable as an
  // Effect outcome (PROTOCOLS.md §12: "v1 uses manual biomarker Readings").
  testWidgets(
      'creates a custom biomarker Metric and logs a manual '
      'Reading to it, which then appears in its history', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _pumpMetricsScreen(tester, database: database);
    await _pumpUntilFound(tester, find.byKey(MetricsScreen.addMetricButtonKey));

    await tester.tap(find.byKey(MetricsScreen.addMetricButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(MetricsScreen.metricNameFieldKey), findsOneWidget);
    await tester.enterText(
      find.byKey(MetricsScreen.metricNameFieldKey),
      'Testosterone',
    );
    await tester.enterText(
      find.byKey(MetricsScreen.metricUnitFieldKey),
      'ng/dL',
    );
    await tester.tap(find.byKey(MetricsScreen.saveMetricButtonKey));
    await tester.pumpAndSettle();

    // Back on the (now non-empty) Metrics list, filed under the generic
    // "Custom" taxonomy bucket (never a bespoke bodyComposition group).
    await _pumpUntilFound(tester, find.text('Custom'));
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.text('Testosterone'), findsOneWidget);

    await tester.tap(find.text('Testosterone'));
    await tester.pumpAndSettle();

    expect(find.byType(MetricDetailScreen), findsOneWidget);
    expect(
      find.byKey(MetricDetailScreen.logReadingButtonKey),
      findsOneWidget,
    );
    expect(find.text('No readings yet'), findsWidgets);

    await tester.tap(find.byKey(MetricDetailScreen.logReadingButtonKey));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(MetricDetailScreen.readingValueFieldKey),
      '620',
    );
    await tester.tap(find.byKey(MetricDetailScreen.saveReadingButtonKey));
    await tester.pumpAndSettle();

    // Reactive read (Drift `.watch()`) picks up the write with no manual
    // refresh — the detail screen now shows the logged value in its history.
    expect(find.textContaining('620 ng/dL'), findsWidgets);

    await _disposeMetricsWidgetTree(tester);
  });

  testWidgets(
      'rejects an empty name and a non-numeric reading value '
      'without crashing (never a fabricated Metric/Reading)', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);

    await _pumpMetricsScreen(tester, database: database);
    await _pumpUntilFound(tester, find.byKey(MetricsScreen.addMetricButtonKey));
    await tester.tap(find.byKey(MetricsScreen.addMetricButtonKey));
    await tester.pumpAndSettle();

    // No name, no unit entered -> Save is a no-op with an inline error,
    // never a Metric created with a blank name.
    await tester.tap(find.byKey(MetricsScreen.saveMetricButtonKey));
    await tester.pump();
    expect(find.byType(MetricsScreen), findsNothing);
    expect(find.text('Name is required'), findsOneWidget);

    await tester.enterText(
      find.byKey(MetricsScreen.metricNameFieldKey),
      'Estradiol',
    );
    await tester.enterText(
      find.byKey(MetricsScreen.metricUnitFieldKey),
      'pg/mL',
    );
    await tester.tap(find.byKey(MetricsScreen.saveMetricButtonKey));
    await tester.pumpAndSettle();

    await _pumpUntilFound(tester, find.text('Custom'));
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estradiol'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(MetricDetailScreen.logReadingButtonKey));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(MetricDetailScreen.readingValueFieldKey),
      'not-a-number',
    );
    await tester.tap(find.byKey(MetricDetailScreen.saveReadingButtonKey));
    await tester.pump();

    expect(find.text('Enter a valid number'), findsOneWidget);
    // Still on the reading form -> nothing was written.
    expect(find.byKey(MetricDetailScreen.readingValueFieldKey), findsOneWidget);

    await _disposeMetricsWidgetTree(tester);
  });

  testWidgets(
      'the Add Metric and Log Reading flows meet accessibility guidelines '
      'in both themes', (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);

      await _pumpMetricsScreen(tester, database: database, theme: theme);
      await _pumpUntilFound(
        tester,
        find.byKey(MetricsScreen.addMetricButtonKey),
      );
      await tester.tap(find.byKey(MetricsScreen.addMetricButtonKey));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.enterText(
        find.byKey(MetricsScreen.metricNameFieldKey),
        'Testosterone',
      );
      await tester.enterText(
        find.byKey(MetricsScreen.metricUnitFieldKey),
        'ng/dL',
      );
      await tester.tap(find.byKey(MetricsScreen.saveMetricButtonKey));
      await tester.pumpAndSettle();
      await _pumpUntilFound(tester, find.text('Custom'));
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Testosterone'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MetricDetailScreen.logReadingButtonKey));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await _disposeMetricsWidgetTree(tester);
    }
  });
}

Future<void> _disposeMetricsWidgetTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 5; i += 1) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
}

Future<void> _seedGarminMetrics(AppDatabase database) async {
  final repositories = TrainingRepositories(database);
  final restingHeartRateMetricId = await repositories.metrics.createMetric(
    const MetricDraft(
      name: 'Resting Heart Rate',
      unit: 'beatsPerMinute',
      valueShape: MetricValueShape.scalar,
      group: MetricGroup.monitoring,
      enabled: true,
      pinned: false,
      sortOrder: 0,
    ),
  );
  final stepsMetricId = await repositories.metrics.createMetric(
    const MetricDraft(
      name: 'Steps',
      unit: 'count',
      valueShape: MetricValueShape.scalar,
      group: MetricGroup.monitoring,
      enabled: true,
      pinned: false,
      sortOrder: 1,
    ),
  );
  await repositories.metrics.upsertIntegrationReadings(
    <IntegrationMetricReadingDraft>[
      IntegrationMetricReadingDraft.scalar(
        metricId: restingHeartRateMetricId,
        valueEntered: '62',
        atTime: DateTime.utc(2026, 6, 23, 7),
        source: 'garmin',
        externalId: 'resting-heart-rate-2026-06-23',
      ),
      IntegrationMetricReadingDraft.scalar(
        metricId: restingHeartRateMetricId,
        valueEntered: '60',
        atTime: DateTime.utc(2026, 6, 24, 7),
        source: 'garmin',
        externalId: 'resting-heart-rate-2026-06-24',
      ),
      IntegrationMetricReadingDraft.scalar(
        metricId: stepsMetricId,
        valueEntered: '12420',
        windowStartedAt: DateTime.utc(2026, 6, 24),
        windowEndedAt: DateTime.utc(2026, 6, 25),
        source: 'garmin',
        externalId: 'steps-2026-06-24',
      ),
    ],
    actor: 'garmin-import-test',
  );
}

Future<void> _pumpMetricsScreen(
  WidgetTester tester, {
  required AppDatabase database,
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) => database),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.light(),
        home: const MetricsScreen(),
      ),
    ),
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .join(', ');
  fail('Could not find $finder. Visible text: $visibleText');
}
