import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/labs/lab_result.dart';
import 'package:perennia/features/labs/widgets/lab_entry_sheet.dart';
import 'package:perennia/features/labs/widgets/lab_results_screen.dart';
import 'package:perennia/features/labs/widgets/lab_test_detail_screen.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

import 'lab_test_helpers.dart';

/// Touch targets, labels, contrast and text scale on the lab screens
/// (docs/designs/lab-results.md, "The display"), in both themes.
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

  late LabScreenHarness harness;

  setUp(() {
    harness = LabScreenHarness();
  });

  tearDown(() async {
    await harness.close();
  });

  /// One Haemoglobin result that is flagged, interim and above the lab's
  /// range, so every row line the guidelines must see is drawn.
  Future<void> seed(WidgetTester tester) => harness.save(
        tester,
        date: DateTime(2026, 3, 4),
        reportStatus: ReportStatus.interim,
        rows: const <CollectionDraftRow>[
          CollectionDraftRow(
            labTestKey: 'haemoglobin',
            value: '190',
            printedRange: '130-180',
            printedFlag: '+',
          ),
        ],
      );

  /// Pumps [home] on a phone-width surface in [theme], resolving the Lab
  /// Test detail route as `app.dart` does.
  Future<void> pumpLab(
    WidgetTester tester,
    Widget home, {
    required ThemeData theme,
    TextScaler? textScaler,
  }) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // A new scope for each pump, so each theme starts from the database.
        key: UniqueKey(),
        overrides: harness.overrides(),
        child: MaterialApp(
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: textScaler == null
              ? null
              : (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: textScaler),
                    child: child!,
                  ),
          onGenerateRoute: (settings) {
            if (settings.name == LabTestDetailScreen.routeName) {
              final labTestKey = settings.arguments;
              if (labTestKey is! String) return null;
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => LabTestDetailScreen(labTestKey: labTestKey),
              );
            }
            return null;
          },
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openEntrySheet(WidgetTester tester) async {
    final addResults = find.byKey(LabResultsScreen.addResultsButtonKey);
    await tester.ensureVisible(addResults);
    await tester.pumpAndSettle();
    await tester.tap(addResults);
    await tester.pumpAndSettle();
    expect(find.byType(LabEntrySheet), findsOneWidget);
  }

  Future<void> expectGuidelines(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  final themes = <String, ThemeData Function()>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  };

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    testWidgets('the Lab Results screen meets the guidelines ($name)', (
      tester,
    ) async {
      await seed(tester);
      final semantics = tester.ensureSemantics();
      await pumpLab(tester, const LabResultsScreen(), theme: theme());

      expect(find.byKey(LabResultsScreen.testRowKey('haemoglobin')),
          findsOneWidget);
      await expectGuidelines(tester);
      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('the Lab Test detail meets the guidelines ($name)', (
      tester,
    ) async {
      await seed(tester);
      final semantics = tester.ensureSemantics();
      await pumpLab(
        tester,
        const LabTestDetailScreen(labTestKey: 'haemoglobin'),
        theme: theme(),
      );

      expect(find.bySemanticsLabel('Lab flag: +'), findsOneWidget);
      expect(find.bySemanticsLabel("Above the lab's range"), findsOneWidget);
      expect(find.bySemanticsLabel('Interim result'), findsOneWidget);
      await expectGuidelines(tester);
      semantics.dispose();
      await harness.unmount(tester);
    });

    testWidgets('the lab entry sheet meets the guidelines ($name)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpLab(tester, const LabResultsScreen(), theme: theme());
      await openEntrySheet(tester);

      await expectGuidelines(tester);
      semantics.dispose();
      await harness.unmount(tester);
    });
  }

  group('at text scale 2.0 nothing overflows', () {
    const scale = TextScaler.linear(2);

    testWidgets('the Lab Results screen', (tester) async {
      await seed(tester);
      await pumpLab(
        tester,
        const LabResultsScreen(),
        theme: AppTheme.light(),
        textScaler: scale,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(LabResultsScreen.addResultsButtonKey), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('the Lab Test detail', (tester) async {
      await seed(tester);
      await pumpLab(
        tester,
        const LabTestDetailScreen(labTestKey: 'haemoglobin'),
        theme: AppTheme.light(),
        textScaler: scale,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Lab flag: +'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('the lab entry sheet', (tester) async {
      await pumpLab(
        tester,
        const LabResultsScreen(),
        theme: AppTheme.light(),
        textScaler: scale,
      );
      await openEntrySheet(tester);

      expect(tester.takeException(), isNull);
      await harness.unmount(tester);
    });
  });
}
