import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/labs/lab_result.dart';
import 'package:perennia/domain/labs/lab_test_catalogue.generated.dart';
import 'package:perennia/features/labs/widgets/lab_results_screen.dart';
import 'package:perennia/features/labs/widgets/lab_test_detail_screen.dart';
import 'package:perennia/features/labs/widgets/lab_test_picker.dart';
import 'package:perennia/features/protocols/widgets/protocols_lock_screen.dart';
import 'package:perennia/features/protocols/services/protocols_pin_hasher.dart';

import 'lab_test_helpers.dart';

/// The Lab Results screen against a real in-memory database
/// (docs/designs/lab-results.md, PR 5, V11 and V12).
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

  testWidgets('panels follow catalogue order, not save order', (tester) async {
    // Full blood count is saved first; Sex hormones comes first in the
    // catalogue.
    await harness.save(
      tester,
      date: DateTime(2026, 3, 4),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(labTestKey: 'haemoglobin', value: '150'),
      ],
    );
    await harness.save(
      tester,
      date: DateTime(2026, 3, 5),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(labTestKey: 'testosterone_total', value: '20'),
      ],
    );
    await harness.pump(tester, const LabResultsScreen());

    final sexHormones =
        find.byKey(LabResultsScreen.panelHeaderKey('Sex hormones'));
    final bloodCount =
        find.byKey(LabResultsScreen.panelHeaderKey('Full blood count'));
    expect(sexHormones, findsOneWidget);
    expect(bloodCount, findsOneWidget);
    expect(
      tester.getTopLeft(sexHormones).dy,
      lessThan(tester.getTopLeft(bloodCount).dy),
    );
    // Only panels with results.
    expect(find.byKey(LabResultsScreen.panelHeaderKey('Lipids')), findsNothing);
    expect(find.byKey(LabResultsScreen.otherHeaderKey), findsNothing);
    expect(
      tester
          .getTopLeft(find.byKey(LabResultsScreen.testRowKey('haemoglobin')))
          .dy,
      greaterThan(tester.getTopLeft(bloodCount).dy),
    );
    expect(find.text('Haemoglobin'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(LabResultsScreen.testRowKey('testosterone_total')),
        matching: find.text(labTestByKey('testosterone_total')!.name),
      ),
      findsOneWidget,
    );
    await harness.unmount(tester);
  });

  testWidgets('each row shows its latest collapsed result and its date',
      (tester) async {
    await harness.save(
      tester,
      date: DateTime(2026, 3, 4),
      reportStatus: ReportStatus.interim,
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(labTestKey: 'shbg', value: '40'),
      ],
    );
    await harness.save(
      tester,
      date: DateTime(2026, 3, 4),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(labTestKey: 'shbg', value: '42'),
      ],
    );
    await harness.pump(tester, const LabResultsScreen());

    final row = find.byKey(LabResultsScreen.testRowKey('shbg'));
    expect(
      find.descendant(of: row, matching: find.text('42 nmol/L · Mar 4, 2026')),
      findsOneWidget,
    );
    expect(find.textContaining('40 nmol/L'), findsNothing);
    await harness.unmount(tester);
  });

  testWidgets(
      'an Other key is listed last, opens its detail, and its result archives',
      (tester) async {
    await harness.save(
      tester,
      date: DateTime(2026, 3, 4),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(labTestKey: 'haemoglobin', value: '150'),
      ],
    );
    final other = await harness.seedOther(tester);
    await harness.pump(tester, const LabResultsScreen());

    final otherHeader = find.byKey(LabResultsScreen.otherHeaderKey);
    final otherRow = find.byKey(LabResultsScreen.testRowKey('zinc_serum'));
    expect(otherHeader, findsOneWidget);
    expect(
      find.descendant(of: otherHeader, matching: find.text('Other')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(otherHeader).dy,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(LabResultsScreen.testRowKey('haemoglobin')),
            )
            .dy,
      ),
    );
    expect(
      tester.getTopLeft(otherRow).dy,
      greaterThan(tester.getTopLeft(otherHeader).dy),
    );
    expect(
      find.descendant(of: otherRow, matching: find.text('Zinc')),
      findsOneWidget,
    );

    await tester.tap(otherRow);
    await tester.pumpAndSettle();

    expect(find.byType(LabTestDetailScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Zinc')),
      findsOneWidget,
    );
    expect(
      find.byKey(LabTestDetailScreen.resultRowKey(other.readingId)),
      findsOneWidget,
    );
    // "Other" parses its Printed Range as a reference range, with no
    // Default Range.
    expect(find.text('Lab range 9-18'), findsOneWidget);
    expect(find.text("Within the lab's range"), findsOneWidget);
    expect(find.textContaining('General range'), findsNothing);

    await tester.tap(
      find.byKey(LabTestDetailScreen.archiveButtonKey(other.readingId)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Archive this result?'), findsOneWidget);
    await tester.tap(find.byKey(LabTestDetailScreen.archiveConfirmKey));
    await tester.pumpAndSettle();

    expect(find.byKey(LabTestDetailScreen.emptyKey), findsOneWidget);
    final archived = (await harness.readings(tester))
        .singleWhere((reading) => reading.id == other.readingId);
    expect(archived.deletedAt, isNotNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(LabResultsScreen.otherHeaderKey), findsNothing);
    expect(
      find.byKey(LabResultsScreen.testRowKey('haemoglobin')),
      findsOneWidget,
    );
    await harness.unmount(tester);
  });

  testWidgets('the empty state has one Add results and the fixed lines',
      (tester) async {
    await harness.pump(tester, const LabResultsScreen());

    expect(find.byKey(LabResultsScreen.emptyKey), findsOneWidget);
    expect(find.text('No lab results yet.'), findsOneWidget);
    expect(find.byKey(LabResultsScreen.addResultsButtonKey), findsOneWidget);
    expect(find.text('Add results'), findsOneWidget);
    expect(
      find.text('General ranges use your sex and birth year from Profile.'),
      findsOneWidget,
    );
    expect(find.byKey(LabResultsScreen.profileLinkKey), findsOneWidget);
    expect(
      find.text('Perennia recognises ${labTestCatalogue.length} lab tests'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(LabResultsScreen.recognisedLinkKey));
    await tester.pumpAndSettle();
    expect(find.byType(LabTestPicker), findsOneWidget);
    await harness.unmount(tester);
  });

  testWidgets('while locked only the lock screen shows, with no Lab Test name',
      (tester) async {
    await harness.save(
      tester,
      date: DateTime(2026, 3, 4),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(labTestKey: 'haemoglobin', value: '150'),
      ],
    );
    final hash = await tester.runAsync(
      () => const ProtocolsPinHasher(iterations: 10).hash('1234'),
    );
    harness.lockStore
      ..enabled = true
      ..pinHash = hash;
    await harness.pump(tester, const LabResultsScreen());

    expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
    expect(find.text('Haemoglobin'), findsNothing);
    expect(find.text('Full blood count'), findsNothing);
    expect(find.textContaining('150'), findsNothing);
    expect(find.byKey(LabResultsScreen.addResultsButtonKey), findsNothing);
    // The lock screen names what the user opened, not "Protocols".
    expect(find.text('Lab results'), findsOneWidget);
    expect(find.text('Lab results are locked'), findsOneWidget);
    expect(
      find.text('Lab results use the Protocols lock. Unlock to view them.'),
      findsOneWidget,
    );
    await harness.unmount(tester);
  });
}
