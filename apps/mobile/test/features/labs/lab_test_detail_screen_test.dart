import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/labs/lab_result.dart';
import 'package:perennia/domain/labs/lab_test.dart';
import 'package:perennia/domain/labs/lab_test_catalogue.generated.dart';
import 'package:perennia/domain/profile/user_profile.dart';
import 'package:perennia/features/labs/controllers/lab_test_detail_controller.dart';
import 'package:perennia/features/labs/widgets/lab_result_row.dart';
import 'package:perennia/features/labs/widgets/lab_test_detail_screen.dart';

import 'lab_test_helpers.dart';

/// The Lab Test detail against a real in-memory database
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

  Future<void> pumpDetail(WidgetTester tester, String labTestKey) =>
      harness.pump(tester, LabTestDetailScreen(labTestKey: labTestKey));

  /// Male, born 1986: 40 at a 2026 collection.
  Future<void> saveProfile(WidgetTester tester) => onFakeTime(
        tester,
        () => harness.repositories.userProfile.saveSection(
          UserProfileSection.aboutYou,
          <String, Object?>{'sex': 'male', 'birth_year': 1986},
        ),
      );

  final creatinineSource =
      labTestByKey('creatinine')!.defaultRanges.first.source.title;

  testWidgets('a Limit Result always shows its comparator', (tester) async {
    final semantics = tester.ensureSemantics();
    await harness.save(
      tester,
      date: DateTime(2026, 3, 4),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(
          labTestKey: 'hs_crp',
          comparator: LabComparator.lt,
          value: '1',
        ),
      ],
    );
    await pumpDetail(tester, 'hs_crp');

    expect(find.text('< 1 mg/L'), findsOneWidget);
    expect(find.bySemanticsLabel('less than 1 mg/L'), findsOneWidget);
    semantics.dispose();
    await harness.unmount(tester);
  });

  testWidgets('a date-only collection shows no time; a timed one does',
      (tester) async {
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
      time: (hour: 8, minute: 15),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(labTestKey: 'haemoglobin', value: '151'),
      ],
    );
    await pumpDetail(tester, 'haemoglobin');

    expect(find.text('Mar 4, 2026'), findsOneWidget);
    final timed = find.textContaining('Mar 5, 2026');
    expect(timed, findsOneWidget);
    expect(tester.widget<Text>(timed).data, contains('8:15'));
    // Newest first.
    expect(
      tester.getTopLeft(timed).dy,
      lessThan(tester.getTopLeft(find.text('Mar 4, 2026')).dy),
    );
    await harness.unmount(tester);
  });

  testWidgets('a Printed Range beats the Default Range', (tester) async {
    await saveProfile(tester);
    await harness.save(
      tester,
      date: DateTime(2026, 3, 4),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(
          labTestKey: 'creatinine',
          value: '115',
          printedRange: '60-120',
        ),
      ],
    );
    await pumpDetail(tester, 'creatinine');

    expect(find.text('Lab range 60-120'), findsOneWidget);
    expect(find.textContaining('General range'), findsNothing);
    // 115 is above the general 60–110, but the lab's range is what counts.
    expect(find.text("Within the lab's range"), findsOneWidget);
    expect(find.textContaining('general range'), findsNothing);
    await harness.unmount(tester);
  });

  testWidgets('position sentences against the lab range', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final (day, value) in const <(int, String)>[
      (2, '120'),
      (3, '150'),
      (4, '190'),
    ]) {
      await harness.save(
        tester,
        date: DateTime(2026, 3, day),
        rows: <CollectionDraftRow>[
          CollectionDraftRow(
            labTestKey: 'haemoglobin',
            value: value,
            printedRange: '130-180',
            printedFlag: value == '150' ? null : (value == '120' ? 'L' : 'H'),
          ),
        ],
      );
    }
    await pumpDetail(tester, 'haemoglobin');

    expect(find.text("Below the lab's range"), findsOneWidget);
    expect(find.text("Within the lab's range"), findsOneWidget);
    expect(find.text("Above the lab's range"), findsOneWidget);
    expect(find.bySemanticsLabel("Below the lab's range"), findsOneWidget);
    expect(find.text('Lab flag: L'), findsOneWidget);
    expect(find.bySemanticsLabel('Lab flag: H'), findsOneWidget);
    expect(find.textContaining('normal'), findsNothing);
    semantics.dispose();
    await harness.unmount(tester);
  });

  testWidgets('position sentences against the general range', (tester) async {
    await saveProfile(tester);
    for (final (day, value) in const <(int, String)>[
      (2, '50'),
      (3, '80'),
      (4, '120'),
    ]) {
      await harness.save(
        tester,
        date: DateTime(2026, 3, day),
        rows: <CollectionDraftRow>[
          CollectionDraftRow(labTestKey: 'creatinine', value: value),
        ],
      );
    }
    await pumpDetail(tester, 'creatinine');

    expect(find.text('Below the general range'), findsOneWidget);
    expect(find.text('Within the general range'), findsOneWidget);
    expect(find.text('Above the general range'), findsOneWidget);
    expect(
      find.text('General range 60–110 umol/L · $creatinineSource'),
      findsNWidgets(3),
    );
    expect(find.textContaining("lab's range"), findsNothing);
    await harness.unmount(tester);
  });

  testWidgets('a riskTarget Lab Test shows Target and no position',
      (tester) async {
    await harness.save(
      tester,
      date: DateTime(2026, 3, 4),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(
          labTestKey: 'ldl_cholesterol',
          value: '3.1',
          printedRange: '< 2.0',
        ),
      ],
    );
    await pumpDetail(tester, 'ldl_cholesterol');

    expect(find.text('Target < 2.0'), findsOneWidget);
    expect(find.textContaining('Lab range'), findsNothing);
    expect(find.textContaining("lab's range"), findsNothing);
    expect(find.textContaining('general range'), findsNothing);
    await harness.unmount(tester);
  });

  testWidgets(
      'Creatinine shows its general range only once sex and birth year are '
      'saved', (tester) async {
    final semantics = tester.ensureSemantics();
    await harness.save(
      tester,
      date: DateTime(2026, 3, 4),
      reportStatus: ReportStatus.interim,
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(labTestKey: 'creatinine', value: '80'),
      ],
    );
    await pumpDetail(tester, 'creatinine');

    expect(find.text('80 umol/L'), findsOneWidget);
    expect(find.textContaining('General range'), findsNothing);
    expect(find.textContaining('general range'), findsNothing);
    expect(find.text('Interim'), findsOneWidget);
    expect(find.bySemanticsLabel('Interim result'), findsOneWidget);

    await saveProfile(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('General range 60–110 umol/L · $creatinineSource'),
      findsOneWidget,
    );
    expect(find.text('Within the general range'), findsOneWidget);
    semantics.dispose();
    await harness.unmount(tester);
  });

  testWidgets('the general range uses the age at the collection date',
      (tester) async {
    // ageAt counts calendar years from the birth year alone: born 1966 is 59
    // in 2025, when the sample was taken, and 60 in 2026, "today". The male
    // Creatinine Default Range covers ages 18-59, so it shows only if the
    // age is taken at the collection date.
    await onFakeTime(
      tester,
      () => harness.repositories.userProfile.saveSection(
        UserProfileSection.aboutYou,
        <String, Object?>{'sex': 'male', 'birth_year': 1966},
      ),
    );
    await harness.save(
      tester,
      date: DateTime(2025, 3, 4),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(labTestKey: 'creatinine', value: '80'),
      ],
    );
    await pumpDetail(tester, 'creatinine');

    expect(
      find.text('General range 60–110 umol/L · $creatinineSource'),
      findsOneWidget,
    );
    expect(find.text('Within the general range'), findsOneWidget);
    await harness.unmount(tester);
  });

  testWidgets('a Limit Result is positioned against a Printed Range',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await harness.save(
      tester,
      date: DateTime(2026, 3, 4),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(
          labTestKey: 'hs_crp',
          comparator: LabComparator.lt,
          value: '1',
          printedRange: '(2-10)',
        ),
      ],
    );
    // Every value under 5 is not below 2, so its position is unknown.
    await harness.save(
      tester,
      date: DateTime(2026, 3, 5),
      rows: const <CollectionDraftRow>[
        CollectionDraftRow(
          labTestKey: 'hs_crp',
          comparator: LabComparator.lt,
          value: '5',
          printedRange: '(2-10)',
        ),
      ],
    );
    await pumpDetail(tester, 'hs_crp');

    expect(find.text('< 1 mg/L'), findsOneWidget);
    expect(find.text('< 5 mg/L'), findsOneWidget);
    expect(find.text('Lab range (2-10)'), findsNWidgets(2));
    expect(find.text("Below the lab's range"), findsOneWidget);
    expect(find.bySemanticsLabel("Below the lab's range"), findsOneWidget);
    expect(find.text("Within the lab's range"), findsNothing);
    expect(find.text("Above the lab's range"), findsNothing);
    // The `< 1` row's position sits under its own value, not the `< 5` one.
    expect(
      tester.getTopLeft(find.text("Below the lab's range")).dy,
      greaterThan(tester.getTopLeft(find.text('< 1 mg/L')).dy),
    );
    semantics.dispose();
    await harness.unmount(tester);
  });

  testWidgets('a one-sided Default Range states its side', (tester) async {
    const source = DefaultRangeSource(
      title: 'Test source',
      url: 'https://example.org',
      version: '1',
    );
    final labTest = labTestByKey('creatinine')!;

    LabResultView view(DefaultRange range) => LabResultView(
          record: LabResultRecord(
            readingId: 'reading-1',
            metricId: 'metric-1',
            labTestKey: 'creatinine',
            entered: '80',
            enteredUnit: 'umol/L',
            scalarValue: 80,
            lab: const LabFields(collected: '2026-03-04'),
            atTime: DateTime.utc(2026, 3, 4, 12),
            updatedAt: DateTime.utc(2026, 3, 4, 12),
            identityRowCount: 1,
          ),
          labTest: labTest,
          kind: labTest.printedRangeKind,
          defaultRange: range,
          position: null,
        );

    Future<void> pumpRow(DefaultRange range) => harness.pump(
          tester,
          Scaffold(
            body: LabResultRow(view: view(range), onArchive: () {}),
          ),
        );

    await pumpRow(
      const DefaultRange(sex: DefaultRangeSex.male, high: 110, source: source),
    );
    expect(
      find.text('General range below 110 umol/L · Test source'),
      findsOneWidget,
    );

    await pumpRow(
      const DefaultRange(sex: DefaultRangeSex.male, low: 60, source: source),
    );
    expect(
      find.text('General range above 60 umol/L · Test source'),
      findsOneWidget,
    );
    await harness.unmount(tester);
  });

  testWidgets(
      'archiving an interim and its final states the count and archives both',
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
    await pumpDetail(tester, 'shbg');

    expect(find.text('42 nmol/L'), findsOneWidget);
    expect(find.text('40 nmol/L'), findsNothing);
    expect(find.text('Interim'), findsNothing);

    await tester.tap(find.byTooltip('Archive result'));
    await tester.pumpAndSettle();
    expect(
      find.text('Archive this result? 2 saved copies will be archived.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(LabTestDetailScreen.archiveConfirmKey));
    await tester.pumpAndSettle();

    final readings = await harness.readings(tester);
    expect(readings, hasLength(2));
    expect(readings.every((reading) => reading.deletedAt != null), isTrue);
    expect(find.byKey(LabTestDetailScreen.emptyKey), findsOneWidget);
    await harness.unmount(tester);
  });
}
