import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/protocols/protocol_plan_days.dart';
import 'package:perennia/features/protocols/controllers/consistency_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/widgets/compound_list_screen.dart';
import 'package:perennia/features/protocols/widgets/consistency_chart.dart';
import 'package:perennia/features/protocols/widgets/consistency_screen.dart';
import 'package:perennia/features/protocols/widgets/effect_screen.dart';
import 'package:perennia/features/protocols/widgets/protocol_screen.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  group('ConsistencyScreen', () {
    testWidgets(
        'each day shows its Day Status label and reason, with the planned '
        'and logged times and amounts', (tester) async {
      _useTallView(tester);
      await _pumpFixture(tester, _labelsRange);

      // Every Day Status reads as a word, each on its own date.
      final expected = <ProtocolDayDate, String>{
        _date(2026, 10, 1): 'Not planned',
        _date(2026, 10, 3): 'Logged',
        _date(2026, 10, 4): 'Partly logged',
        _date(2026, 10, 5): 'Paused',
        _date(2026, 10, 6): 'Not logged',
        _date(2026, 10, 7): 'Not planned',
        _date(2026, 10, 8): 'Not planned',
        _date(2026, 10, 9): 'Not planned',
        _date(2026, 10, 11): 'Off cycle',
        _date(2026, 10, 14): 'Pending',
      };
      for (final entry in expected.entries) {
        expect(
          find.descendant(
            of: find.byKey(ConsistencyScreen.dayStatusKey(_trt, entry.key)),
            matching: find.text(entry.value),
          ),
          findsOneWidget,
          reason: '${entry.key} reads ${entry.value}',
        );
      }

      // The reasons for "Not planned", in their own words.
      expect(
        _dayText(tester, _date(2026, 10, 1)),
        contains("Outside the Protocol's dates"),
      );
      expect(
        _dayText(tester, _date(2026, 10, 9)),
        contains('Not scheduled that day'),
      );
      expect(_dayText(tester, _date(2026, 10, 8)), contains('No schedule'));
      // An as-needed Dose fills nothing, so it is an extra next to the status,
      // and it never changes it.
      final asNeeded = _dayText(tester, _date(2026, 10, 7));
      expect(asNeeded, contains('As needed · 1 extra'));
      expect(asNeeded, contains('Extra · 8:00 PM · 0.1 mL'));

      // Each slot: its planned time and amount, then the Dose that filled it.
      // Both amounts resolve to an active mass, so both masses show.
      final logged = _dayText(tester, _date(2026, 10, 3));
      expect(logged, contains('Planned · 9:00 AM · 0.1 mL · ≈ 2 mg · Daily'));
      expect(logged, contains('Logged · 9:05 AM · 0.1 mL · ≈ 2 mg'));
      expect(logged, contains('Planned · 9:00 PM · 0.1 mL · ≈ 2 mg · Daily'));
      final partly = _dayText(tester, _date(2026, 10, 4));
      expect(partly, contains('Logged · 9:00 AM · 0.1 mL'));
      expect(partly, contains('Not logged'));
      // Today's unfilled slots read "Pending", not "Not logged".
      final today = _dayText(tester, _date(2026, 10, 14));
      expect(today, contains('Pending'));
      expect(today, isNot(contains('Not logged')));

      expect(find.byKey(ConsistencyChart.chartKey), findsOneWidget);
      expect(find.text(EffectScreen.disclaimerText), findsOneWidget);
    });

    testWidgets('a removed member reads Not planned, Removed', (tester) async {
      _useTallView(tester);
      await _pumpFixture(tester, _removedRange);

      expect(
        find.descendant(
          of: find.byKey(
            ConsistencyScreen.dayStatusKey(_trt, _date(2026, 10, 13)),
          ),
          matching: find.text('Not planned'),
        ),
        findsOneWidget,
      );
      expect(_dayText(tester, _date(2026, 10, 13)), contains('Removed'));
      // The archive day itself is still planned (D1).
      expect(
        find.descendant(
          of: find.byKey(
            ConsistencyScreen.dayStatusKey(_trt, _date(2026, 10, 12)),
          ),
          matching: find.text('Not logged'),
        ),
        findsOneWidget,
      );
    });

    for (final (name, theme) in <(String, ThemeData)>[
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets(
          'no copy uses a word D6 bans, and the screen meets contrast and '
          'tap-target guidelines ($name theme)', (tester) async {
        _useTallView(tester);
        final semantics = tester.ensureSemantics();
        await _pumpFixture(tester, _labelsRange, theme: theme);

        final banned = RegExp(
          r'\b(missed|late|overdue|adherence|streak|percentage|percent)\b|%',
          caseSensitive: false,
        );
        final texts = tester
            .widgetList<RichText>(find.byType(RichText))
            .map((text) => text.text.toPlainText())
            .toList();
        expect(texts, isNotEmpty);
        for (final text in texts) {
          expect(banned.hasMatch(text), isFalse, reason: text);
        }

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
      });
    }

    for (final (name, theme) in <(String, ThemeData)>[
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets(
          "a Protocol's view labels its tabs in readable colors and meets "
          'contrast and tap-target guidelines ($name theme)', (tester) async {
        _useTallView(tester);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              protocolsClockProvider.overrideWithValue(() => _now),
              // TRT's tab reads the fixture; AgeMate's read never arrives, so
              // its tab keeps the name it was opened with.
              consistencyProvider.overrideWith(
                (ref, compoundId) => compoundId == _trt
                    ? Stream<ConsistencyRange>.value(
                        _labelsRange(
                          ref.watch(consistencyRangeControllerProvider),
                        ),
                      )
                    : const Stream<ConsistencyRange>.empty(),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: theme,
              home: ConsistencyScreen.protocol(
                protocolName: 'Daily',
                members: const <ConsistencyTab>[
                  ConsistencyTab(compoundId: _trt, label: 'TRT'),
                  ConsistencyTab(compoundId: _ageMate, label: 'AgeMate'),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byKey(ConsistencyChart.chartKey), findsOneWidget);

        // The guideline does not measure the tab labels, so their colors are
        // read directly: never the theme's primary, which fails AA on the
        // light chrome.
        final colors = theme.extension<AppColors>()!;
        Color? tabColor(String compoundId, String label) => DefaultTextStyle.of(
              tester.element(
                find.descendant(
                  of: find.byKey(ConsistencyScreen.tabKey(compoundId)),
                  matching: find.text(label),
                ),
              ),
            ).style.color;
        expect(tabColor(_trt, 'TRT'), colors.textPrimary);
        expect(tabColor(_ageMate, 'AgeMate'), colors.textSecondary);

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        semantics.dispose();
      });
    }

    testWidgets(
        'the range picker opens on the last 30 days and switches to 7, 90 '
        'and 365 days, each ending today', (tester) async {
      _useTallView(tester);
      final requested = <(ProtocolDayDate, ProtocolDayDate, ProtocolDayDate)>[];
      await _pumpFixture(
        tester,
        (selection) {
          requested.add((selection.from, selection.to, selection.today));
          return _labelsRange(selection);
        },
      );

      expect(_rangeSummary(tester), 'Sep 15, 2026 – Oct 14, 2026');
      expect(_chipSelected(tester, ConsistencyRangePreset.last30), isTrue);
      expect(requested.last, (_date(2026, 9, 15), _date(2026, 10, 14), _today));

      await tester.tap(
        find.byKey(
            ConsistencyScreen.rangeChipKey(ConsistencyRangePreset.last7)),
      );
      await tester.pump();
      expect(_rangeSummary(tester), 'Oct 8, 2026 – Oct 14, 2026');
      expect(_chipSelected(tester, ConsistencyRangePreset.last7), isTrue);
      expect(requested.last.$1, _date(2026, 10, 8));

      await tester.tap(
        find.byKey(
          ConsistencyScreen.rangeChipKey(ConsistencyRangePreset.last90),
        ),
      );
      await tester.pump();
      expect(_rangeSummary(tester), 'Jul 17, 2026 – Oct 14, 2026');

      await tester.tap(
        find.byKey(
          ConsistencyScreen.rangeChipKey(ConsistencyRangePreset.last365),
        ),
      );
      await tester.pump();
      expect(_rangeSummary(tester), 'Oct 15, 2025 – Oct 14, 2026');
      expect(requested.last.$2, _today);
    });

    testWidgets('a custom range is picked with the date range picker',
        (tester) async {
      _useTallView(tester);
      await _pumpFixture(tester, _labelsRange);

      await tester.tap(find.byKey(ConsistencyScreen.customRangeChipKey));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);

      // Saving the picker's initial range keeps its dates as a custom range.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        _chipSelected(tester, ConsistencyRangePreset.custom),
        isTrue,
      );
      expect(_rangeSummary(tester), 'Sep 15, 2026 – Oct 14, 2026');
    });

    test('a custom range ends today at the latest and holds at most 366 days',
        () {
      final container = ProviderContainer(
        overrides: [
          protocolsClockProvider.overrideWithValue(() => _now),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        consistencyRangeControllerProvider,
        (_, __) {},
      );
      addTearDown(subscription.close);
      final controller =
          container.read(consistencyRangeControllerProvider.notifier);

      controller.selectCustom(_date(2026, 10, 1), _date(2026, 10, 20));
      var selection = container.read(consistencyRangeControllerProvider);
      expect(selection.preset, ConsistencyRangePreset.custom);
      expect((selection.from, selection.to), (_date(2026, 10, 1), _today));

      controller.selectCustom(_date(2024, 1, 1), _date(2026, 10, 10));
      selection = container.read(consistencyRangeControllerProvider);
      expect(selection.to, _date(2026, 10, 10));
      expect(
        selection.to.daysBetween(selection.from) + 1,
        maxConsistencyRangeDays,
      );
      expect(selection.from, _date(2025, 10, 10));
    });

    testWidgets(
        'a read that fails after it has shown a range says so, and no stale '
        'days stay on screen', (tester) async {
      _useTallView(tester);
      final reads = StreamController<ConsistencyRange>();
      addTearDown(reads.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            protocolsClockProvider.overrideWithValue(() => _now),
            consistencyProvider.overrideWith((ref, compoundId) => reads.stream),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: ConsistencyScreen.compound(
              compoundId: _trt,
              compoundName: 'TRT',
            ),
          ),
        ),
      );
      reads.add(
        _labelsRange(
          ConsistencyRangeSelection.preset(
            ConsistencyRangePreset.last30,
            _today,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(ConsistencyScreen.dayStatusKey(_trt, _today)),
        findsOneWidget,
      );

      reads.addError(StateError('The plan could not be read.'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not load this range.'), findsOneWidget);
      expect(
        find.byKey(ConsistencyScreen.dayStatusKey(_trt, _today)),
        findsNothing,
      );
      expect(find.byKey(ConsistencyChart.chartKey), findsNothing);
    });

    test(
        'each preset holds exactly its days, ending today, on a day the '
        'clocks change', () {
      // Daylight saving starts or ends on each of these dates somewhere
      // (the US, Europe, Australia), whichever zone the test runs in.
      for (final now in <DateTime>[
        DateTime(2026, 3, 8, 12),
        DateTime(2026, 3, 29, 12),
        DateTime(2026, 4, 5, 12),
        DateTime(2026, 10, 4, 12),
        DateTime(2026, 10, 25, 12),
        DateTime(2026, 11, 1, 12),
      ]) {
        final container = ProviderContainer(
          overrides: [
            protocolsClockProvider.overrideWithValue(() => now),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          consistencyRangeControllerProvider,
          (_, __) {},
        );
        addTearDown(subscription.close);
        final today = ProtocolDayDate.fromDateTime(now);

        for (final preset in ConsistencyRangePreset.values) {
          final days = preset.days;
          if (days == null) {
            continue;
          }
          container
              .read(consistencyRangeControllerProvider.notifier)
              .selectPreset(preset);
          final selection = container.read(consistencyRangeControllerProvider);
          final first = DateTime.utc(now.year, now.month, now.day)
              .subtract(Duration(days: days - 1));
          expect(selection.to, today, reason: '$now $preset');
          expect(
            selection.from,
            _date(first.year, first.month, first.day),
            reason: '$now $preset',
          );
          expect(
            selection.to.daysBetween(selection.from) + 1,
            days,
            reason: '$now $preset',
          );
        }
      }
    });

    test(
        'the repository refuses a range over 366 days or ending before it '
        'starts', () {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repositories = TrainingRepositories(database);

      expect(
        () => repositories.protocolPlan.watchConsistency(
          _trt,
          _date(2025, 1, 1),
          _date(2026, 1, 2),
          today: _today,
        ),
        throwsArgumentError,
      );
      // 366 days, both ends included, is the longest range.
      expect(
        repositories.protocolPlan.watchConsistency(
          _trt,
          _date(2025, 1, 1),
          _date(2026, 1, 1),
          today: _today,
        ),
        isA<Stream<ConsistencyRange>>(),
      );
      expect(
        () => repositories.protocolPlan.watchConsistency(
          _trt,
          _date(2026, 10, 2),
          _date(2026, 10, 1),
          today: _today,
        ),
        throwsArgumentError,
      );
    });
  });

  group('watchConsistency against the database', () {
    late AppDatabase database;
    late TrainingRepositories repositories;
    late _StackIds ids;

    setUp(() async {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
      ids = await _seedStack(repositories);
    });

    tearDown(() => database.close());

    Future<ConsistencyRange> read(String compoundId) {
      return repositories.protocolPlan
          .watchConsistency(compoundId, _start, _today, today: _today)
          .first;
    }

    DayStatus statusOn(ConsistencyRange range, ProtocolDayDate date) =>
        range.dayStatuses.singleWhere((status) => status.localDate == date);

    test(
        'a Dose tombstoned by undo or archived is left out, and fills no '
        'slot', () async {
      final undone =
          await _logTrt(repositories, ids, DateTime(2026, 10, 12, 9));
      await repositories.activityLog.undoBatch(undone.batchId);
      final archived =
          await _logTrt(repositories, ids, DateTime(2026, 10, 12, 21));
      await repositories.protocols.deleteDose(archived.doseId);

      final range = await read(ids.trt);

      expect(
        range.doses.map((dose) => dose.id),
        isNot(anyElement(anyOf(undone.doseId, archived.doseId))),
      );
      // The 13th and 14th keep their seeded 09:05 Doses; nothing is left on
      // the 12th.
      expect(range.doses.map((dose) => dose.localDate), <ProtocolDayDate>[
        _date(2026, 10, 13),
        _date(2026, 10, 14),
      ]);
      expect(
          statusOn(range, _date(2026, 10, 12)).status, DayStatusKind.notLogged);
    });

    test(
        'a member removed by an edit reads Removed after its archive day; '
        'one whose adding was undone never existed', () async {
      // AgeMate is removed on the 12th.
      await repositories.protocols.editProtocol(
        ids.protocolId,
        _dailyDraft(ids, <String>[ids.trt]),
        today: _date(2026, 10, 12),
      );
      // Melatonin is added on the 13th, then the edit is undone.
      final added = await repositories.protocols.editProtocol(
        ids.protocolId,
        _dailyDraft(ids, <String>[ids.trt, ids.melatonin]),
        today: _date(2026, 10, 13),
      );
      await repositories.activityLog.undoBatch(added);

      final ageMate = await read(ids.ageMate);
      // The archive day itself is still planned (D1).
      expect(
        statusOn(ageMate, _date(2026, 10, 12)).status,
        DayStatusKind.notLogged,
      );
      final removed = statusOn(ageMate, _date(2026, 10, 13));
      expect(removed.status, DayStatusKind.notPlanned);
      expect(removed.notPlannedReason, NotPlannedReason.removed);

      final melatonin = await read(ids.melatonin);
      expect(melatonin.isPlanned, isFalse);
      expect(melatonin.planDays, isEmpty);
      expect(melatonin.dayStatuses, isEmpty);
      // Its Dose is still listed by date, with no Day Status.
      expect(melatonin.days.single.status, isNull);
      expect(melatonin.days.single.localDate, _today);
    });

    test(
        'an archived Protocol still plans its past days through its archive '
        'day', () async {
      await repositories.protocols.archiveProtocol(
        ids.protocolId,
        today: _date(2026, 10, 12),
      );

      final range = await read(ids.trt);

      expect(range.isPlanned, isTrue);
      expect(range.protocols[ids.protocolId]?.name, 'Daily');
      expect(
        statusOn(range, _date(2026, 10, 12)).status,
        DayStatusKind.notLogged,
      );
      final after = statusOn(range, _date(2026, 10, 13));
      expect(after.status, DayStatusKind.notPlanned);
      expect(after.notPlannedReason, NotPlannedReason.removed);
      // The 13th's Dose is kept, and with no slot to fill it is an extra.
      expect(after.extraCount, 1);
    });

    test('logging a Dose or adding a Schedule Version re-emits the range',
        () async {
      final emissions = <ConsistencyRange>[];
      final subscription = repositories.protocolPlan
          .watchConsistency(ids.trt, _start, _today, today: _today)
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await _until(() => emissions.isNotEmpty);
      expect(statusOn(emissions.last, _today).status, DayStatusKind.pending);

      // Today's 21:00 slot is filled: the day reads "Logged".
      await _logTrt(repositories, ids, DateTime(2026, 10, 14, 21, 2));
      await _until(
        () => statusOn(emissions.last, _today).status == DayStatusKind.logged,
      );

      // TRT moves to 07:00 only from today: a new Schedule Version.
      await repositories.protocols.editProtocol(
        ids.protocolId,
        _dailyDraft(
          ids,
          <String>[ids.trt, ids.ageMate],
          trtTimes: const <String>['07:00'],
        ),
        today: _today,
      );
      List<String?> plannedOn(ProtocolDayDate date) => emissions.last.planDays
          .singleWhere((day) => day.localDate == date)
          .planned
          .map((planned) => planned.localTime)
          .toList();
      await _until(() => plannedOn(_today).contains('07:00'));
      expect(plannedOn(_today), <String?>['07:00']);
      expect(plannedOn(_today.addDays(-1)), <String?>['09:00', '21:00']);
    });
  });

  group('entry points', () {
    testWidgets(
        'a Compound row in the Compound list opens its Consistency view, '
        'read from the database', (tester) async {
      _useTallView(tester);
      final database = AppDatabase.inMemory();
      final repositories = TrainingRepositories(database);
      final ids = await _onFakeTime(tester, () => _seedStack(repositories));
      await _pumpLive(tester, repositories, const CompoundListScreen());
      await _pumpUntilFound(
        tester,
        find.byKey(CompoundListScreen.consistencyButtonKey(ids.trt)),
      );

      await tester.tap(
        find.byKey(CompoundListScreen.consistencyButtonKey(ids.trt)).first,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ConsistencyScreen.dayStatusKey(ids.trt, _today)),
      );

      expect(find.text('Consistency · TRT'), findsOneWidget);
      // Planned at 09:00 and 21:00 today; the 09:00 Dose fills one.
      expect(
        find.descendant(
          of: find.byKey(ConsistencyScreen.dayStatusKey(ids.trt, _today)),
          matching: find.text('Pending'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            ConsistencyScreen.dayStatusKey(ids.trt, _today.addDays(-1)),
          ),
          matching: find.text('Partly logged'),
        ),
        findsOneWidget,
      );
      // Before the Protocol's start, the days read "Outside the Protocol's
      // dates".
      expect(
        find.descendant(
          of: find.byKey(
            ConsistencyScreen.dayStatusKey(ids.trt, _start.addDays(-1)),
          ),
          matching: find.text('Not planned'),
        ),
        findsOneWidget,
      );

      await _closeLive(tester, database);
    });

    testWidgets(
        'a Compound in no Protocol lists its Doses by date with no status',
        (tester) async {
      _useTallView(tester);
      final database = AppDatabase.inMemory();
      final repositories = TrainingRepositories(database);
      final ids = await _onFakeTime(tester, () => _seedStack(repositories));
      await _pumpLive(tester, repositories, const CompoundListScreen());
      await _pumpUntilFound(
        tester,
        find.byKey(CompoundListScreen.consistencyButtonKey(ids.melatonin)),
      );

      await tester.tap(
        find
            .byKey(CompoundListScreen.consistencyButtonKey(ids.melatonin))
            .first,
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ConsistencyScreen.notInProtocolKey),
      );

      expect(
        find.byKey(ConsistencyScreen.dayKey(ids.melatonin, _today)),
        findsOneWidget,
      );
      expect(
        find.byKey(ConsistencyScreen.dayStatusKey(ids.melatonin, _today)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(ConsistencyScreen.dayKey(ids.melatonin, _today)),
          matching: find.text('7:30 AM · 3 mg'),
        ),
        findsOneWidget,
      );

      await _closeLive(tester, database);
    });

    testWidgets(
        'the Protocol screen opens a Consistency view with a tab per member',
        (tester) async {
      _useTallView(tester);
      final database = AppDatabase.inMemory();
      final repositories = TrainingRepositories(database);
      final ids = await _onFakeTime(tester, () => _seedStack(repositories));
      // AgeMate is archived from the catalogue; it stays a member, and its
      // tab still carries its name.
      await _onFakeTime(
        tester,
        () => repositories.protocols.archiveCompound(ids.ageMate),
      );
      // The stored Protocol as the Protocol list hands it to the screen: its
      // name and members are what the button reads. (Its detail stream is
      // not read here: it doesn't settle on the widget test's fake clock.)
      final protocol = ProtocolRecord(
        id: ids.protocolId,
        name: 'Daily',
        startLocalDate: _start,
        updatedAt: _now,
        members: <ProtocolMemberRecord>[
          ProtocolMemberRecord(id: 'm-trt', compoundId: ids.trt, position: 0),
          ProtocolMemberRecord(
            id: 'm-agemate',
            compoundId: ids.ageMate,
            position: 1,
          ),
        ],
      );
      await _pumpLive(
        tester,
        repositories,
        ProtocolFormScreen(protocol: protocol),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(ProtocolFormScreen.consistencyButtonKey),
      );
      expect(
        tester
            .getSize(find.byKey(ProtocolFormScreen.consistencyButtonKey))
            .height,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(find.byKey(ProtocolFormScreen.consistencyButtonKey));
      await _pumpUntilFound(
        tester,
        find.byKey(ConsistencyScreen.dayStatusKey(ids.trt, _today)),
      );

      expect(find.text('Consistency · Daily'), findsOneWidget);
      expect(find.byKey(ConsistencyScreen.tabKey(ids.trt)), findsOneWidget);
      expect(
        find.byKey(ConsistencyScreen.tabKey(ids.ageMate)),
        findsOneWidget,
      );
      // Each tab is named from its own read, which an archived Compound
      // keeps.
      await _pumpUntilFound(
        tester,
        find.descendant(
          of: find.byKey(ConsistencyScreen.tabKey(ids.ageMate)),
          matching: find.text('AgeMate'),
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(ConsistencyScreen.tabKey(ids.trt)),
          matching: find.text('TRT'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ConsistencyScreen.tabKey(ids.ageMate)));
      await _pumpUntilFound(
        tester,
        find.byKey(ConsistencyScreen.dayStatusKey(ids.ageMate, _today)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      // AgeMate at 09:00 has nothing logged today.
      expect(
        find.descendant(
          of: find.byKey(ConsistencyScreen.dayStatusKey(ids.ageMate, _today)),
          matching: find.text('Pending'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            ConsistencyScreen.dayStatusKey(ids.ageMate, _today.addDays(-1)),
          ),
          matching: find.text('Not logged'),
        ),
        findsOneWidget,
      );

      await _closeLive(tester, database);
    });
  });
}

const _trt = 'c-trt';
const _ageMate = 'c-agemate';
const _today = ProtocolDayDate(year: 2026, month: 10, day: 14);
final DateTime _now = DateTime(2026, 10, 14, 12);
const _start = ProtocolDayDate(year: 2026, month: 10, day: 10);

ProtocolDayDate _date(int year, int month, int day) =>
    ProtocolDayDate(year: year, month: month, day: day);

/// Every Day Status and reason across two weeks of one Compound in
/// "Daily", which starts on 3 October with 8 days on and 2 off, and a Pause
/// on the 5th. TRT is 0.1 mL of a 20 mg/mL Compound at 09:00 and 21:00, as
/// needed from the 7th, with no Schedule from the 8th, on Mondays only from
/// the 9th, and back to 09:00 and 21:00 daily from the 13th. Today is the
/// 14th.
ConsistencyRange _labelsRange(ConsistencyRangeSelection selection) {
  const from = ProtocolDayDate(year: 2026, month: 10, day: 1);
  final rule = _twiceDaily();
  final protocol = PlanProtocol(
    protocolId: 'p-daily',
    startLocalDate: _date(2026, 10, 3),
    period: ProtocolPeriod(
      cycle: ProtocolCycle(
        onDays: 8,
        offDays: 2,
        anchor: _date(2026, 10, 3),
        anchorIsDefault: true,
      ),
      pauses: <ProtocolPause>[
        ProtocolPause(from: _date(2026, 10, 5), to: _date(2026, 10, 5)),
      ],
    ),
    members: <PlanMember>[
      PlanMember(
        memberId: 'm-trt',
        compoundId: _trt,
        versions: <ScheduleVersion>[
          _version('v-1', _date(2026, 10, 3), rule),
          _version('v-2', _date(2026, 10, 7), const AsNeededScheduleRule()),
          _version('v-3', _date(2026, 10, 8), const UnscheduledScheduleRule()),
          _version(
            'v-4',
            _date(2026, 10, 9),
            TimedScheduleRule(
              days: WeekdayScheduleDays(const <int>[1]),
              times: const <String>['09:00'],
            ),
          ),
          _version('v-5', _date(2026, 10, 13), rule),
        ],
      ),
    ],
  );
  return _range(
    <PlanProtocol>[protocol],
    from,
    _today,
    <DoseRecord>[
      _dose('d-1', _date(2026, 10, 3), 9, 5),
      _dose('d-2', _date(2026, 10, 3), 21, 0),
      _dose('d-3', _date(2026, 10, 4), 9, 0),
      _dose('d-4', _date(2026, 10, 7), 20, 0),
      _dose('d-5', _date(2026, 10, 14), 9, 0),
    ],
  );
}

/// TRT planned daily at 09:00 from the 10th, removed on the 12th.
ConsistencyRange _removedRange(ConsistencyRangeSelection selection) {
  final protocol = PlanProtocol(
    protocolId: 'p-daily',
    startLocalDate: _date(2026, 10, 10),
    members: <PlanMember>[
      PlanMember(
        memberId: 'm-trt',
        compoundId: _trt,
        archivedOn: _date(2026, 10, 12),
        versions: <ScheduleVersion>[
          _version(
            'v-1',
            _date(2026, 10, 10),
            TimedScheduleRule(
              days: const DailyScheduleDays(),
              times: const <String>['09:00'],
            ),
          ),
        ],
      ),
    ],
  );
  return _range(
    <PlanProtocol>[protocol],
    _date(2026, 10, 10),
    _today,
    const <DoseRecord>[],
  );
}

ConsistencyRange _range(
  List<PlanProtocol> protocols,
  ProtocolDayDate from,
  ProtocolDayDate to,
  List<DoseRecord> doses,
) {
  final days = planDays(protocols, from, to);
  return ConsistencyRange(
    compoundId: _trt,
    from: from,
    to: to,
    today: _today,
    planDays: days,
    dayStatuses: dayStatuses(
      days,
      <PlanDose>[
        for (final (index, dose) in doses.indexed)
          PlanDose(
            doseId: dose.id,
            compoundId: _trt,
            localDate: dose.localDate,
            localTime: dose.localTime,
            sequence: index,
          ),
      ],
      _today,
    ),
    doses: doses,
    compound: CompoundRecord(
      id: _trt,
      name: 'TRT',
      defaultUnit: DoseUnit.milliliter,
      defaultRoute: DoseRoute.intramuscular,
      strength: _strength,
      updatedAt: DateTime.utc(2026, 10, 1),
    ),
    protocols: const <String, ProtocolOptionRecord>{
      'p-daily': ProtocolOptionRecord(id: 'p-daily', name: 'Daily'),
    },
  );
}

final CompoundStrength _strength = CompoundStrength.parse('20 mg/mL');

ScheduleRule _twiceDaily() => TimedScheduleRule(
      days: const DailyScheduleDays(),
      times: const <String>['09:00', '21:00'],
    );

ScheduleVersion _version(
  String id,
  ProtocolDayDate effectiveFrom,
  ScheduleRule rule,
) {
  final plans = rule is TimedScheduleRule || rule is UntimedScheduleRule;
  return ScheduleVersion(
    id: id,
    effectiveFrom: effectiveFrom,
    rule: rule,
    amount: plans
        ? const PlanAmount(
            amountValue: 0.1,
            amountEntered: '0.1',
            unit: DoseUnit.milliliter,
            route: DoseRoute.intramuscular,
          )
        : PlanAmount.none,
  );
}

/// A Dose of TRT at [hour]:[minute] on [date], its offset frozen at UTC so
/// its time reads the same on every test host.
DoseRecord _dose(String id, ProtocolDayDate date, int hour, int minute) {
  final tookAt = DateTime.utc(date.year, date.month, date.day, hour, minute);
  return DoseRecord(
    id: id,
    compoundId: _trt,
    compoundName: 'TRT',
    compoundStrength: _strength,
    amountValue: 0.1,
    amountEntered: '0.1',
    unit: DoseUnit.milliliter,
    route: DoseRoute.intramuscular,
    tookAt: tookAt,
    timezone: 'UTC',
    localDate: date,
    timezoneOffsetMinutes: 0,
    provenance: DoseProvenance.manual,
    updatedAt: tookAt,
  );
}

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The Consistency view for TRT over a fixed read: [build] stands in for the
/// repository, from the range the screen's controller holds.
Future<void> _pumpFixture(
  WidgetTester tester,
  ConsistencyRange Function(ConsistencyRangeSelection selection) build, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        protocolsClockProvider.overrideWithValue(() => _now),
        consistencyProvider.overrideWith(
          (ref, compoundId) => Stream<ConsistencyRange>.value(
            build(ref.watch(consistencyRangeControllerProvider)),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.light(),
        home: ConsistencyScreen.compound(compoundId: _trt, compoundName: 'TRT'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Every line of text in one date's row of the day list, joined.
String _dayText(WidgetTester tester, ProtocolDayDate date) {
  return tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(ConsistencyScreen.dayKey(_trt, date)),
          matching: find.byType(Text),
        ),
      )
      .map((text) => text.data ?? '')
      .join('\n');
}

String _rangeSummary(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(ConsistencyScreen.rangeSummaryKey)).data!;

bool _chipSelected(WidgetTester tester, ConsistencyRangePreset preset) {
  final key = preset == ConsistencyRangePreset.custom
      ? ConsistencyScreen.customRangeChipKey
      : ConsistencyScreen.rangeChipKey(preset);
  return tester.widget<ChoiceChip>(find.byKey(key)).selected;
}

typedef _StackIds = ({
  String protocolId,
  String trt,
  String ageMate,
  String melatonin,
});

/// "Daily" from 10 October: TRT at 09:00 and 21:00 and AgeMate at 09:00.
/// TRT is logged at 09:05 on the 13th and today; melatonin, in no
/// Protocol, at 07:30 today.
Future<_StackIds> _seedStack(TrainingRepositories repositories) async {
  Future<String> compound(String name, DoseUnit unit, DoseRoute route) async {
    final result = await repositories.protocols.createCompound(
      CompoundDraft(name: name, defaultUnit: unit, defaultRoute: route),
    );
    return result.compoundId;
  }

  final trt =
      await compound('TRT', DoseUnit.milliliter, DoseRoute.intramuscular);
  final ageMate = await compound('AgeMate', DoseUnit.capsule, DoseRoute.oral);
  final melatonin =
      await compound('Melatonin', DoseUnit.milligram, DoseRoute.oral);
  ScheduleDraft dailyAt(List<String> times, DoseUnit unit, DoseRoute route) {
    return ScheduleDraft(
      rule: TimedScheduleRule(days: const DailyScheduleDays(), times: times),
      doseAmountValue: 1,
      doseAmountEntered: '1',
      doseUnit: unit,
      route: route,
    );
  }

  final created = await repositories.protocols.createProtocol(
    ProtocolDraft(
      name: 'Daily',
      startLocalDate: _start,
      compoundIds: <String>[trt, ageMate],
      schedulesByCompoundId: <String, ScheduleDraft?>{
        trt: dailyAt(
          const <String>['09:00', '21:00'],
          DoseUnit.milliliter,
          DoseRoute.intramuscular,
        ),
        ageMate: dailyAt(
          const <String>['09:00'],
          DoseUnit.capsule,
          DoseRoute.oral,
        ),
      },
    ),
    today: _start,
  );

  Future<void> log(
    String compoundId,
    String name,
    DateTime tookAt,
    String amount,
    DoseUnit unit,
    DoseRoute route,
  ) async {
    await repositories.protocols.logDose(
      DoseSnapshotDraft(
        compoundId: compoundId,
        compoundName: name,
        amountValue: double.parse(amount),
        amountEntered: amount,
        unit: unit,
        route: route,
        tookAt: tookAt,
      ),
    );
  }

  await log(
    trt,
    'TRT',
    DateTime(2026, 10, 13, 9, 5),
    '1',
    DoseUnit.milliliter,
    DoseRoute.intramuscular,
  );
  await log(
    trt,
    'TRT',
    DateTime(2026, 10, 14, 9, 5),
    '1',
    DoseUnit.milliliter,
    DoseRoute.intramuscular,
  );
  await log(
    melatonin,
    'Melatonin',
    DateTime(2026, 10, 14, 7, 30),
    '3',
    DoseUnit.milligram,
    DoseRoute.oral,
  );
  return (
    protocolId: created.protocolId,
    trt: trt,
    ageMate: ageMate,
    melatonin: melatonin,
  );
}

/// "Daily" as stored by [_seedStack], with [compoundIds] as its members.
/// TRT is at 09:00 and 21:00 unless [trtTimes] says otherwise; a member's
/// unchanged Schedule gets no new version.
ProtocolDraft _dailyDraft(
  _StackIds ids,
  List<String> compoundIds, {
  List<String> trtTimes = const <String>['09:00', '21:00'],
}) {
  ScheduleDraft dailyAt(List<String> times, DoseUnit unit, DoseRoute route) {
    return ScheduleDraft(
      rule: TimedScheduleRule(days: const DailyScheduleDays(), times: times),
      doseAmountValue: 1,
      doseAmountEntered: '1',
      doseUnit: unit,
      route: route,
    );
  }

  final schedules = <String, ScheduleDraft?>{
    ids.trt: dailyAt(trtTimes, DoseUnit.milliliter, DoseRoute.intramuscular),
    ids.ageMate: dailyAt(
      const <String>['09:00'],
      DoseUnit.capsule,
      DoseRoute.oral,
    ),
    ids.melatonin: dailyAt(
      const <String>['22:00'],
      DoseUnit.milligram,
      DoseRoute.oral,
    ),
  };
  return ProtocolDraft(
    name: 'Daily',
    startLocalDate: _start,
    compoundIds: compoundIds,
    schedulesByCompoundId: <String, ScheduleDraft?>{
      for (final id in compoundIds) id: schedules[id],
    },
  );
}

Future<LogDoseResult> _logTrt(
  TrainingRepositories repositories,
  _StackIds ids,
  DateTime tookAt,
) {
  return repositories.protocols.logDose(
    DoseSnapshotDraft(
      compoundId: ids.trt,
      compoundName: 'TRT',
      amountValue: 1,
      amountEntered: '1',
      unit: DoseUnit.milliliter,
      route: DoseRoute.intramuscular,
      tookAt: tookAt,
    ),
  );
}

/// Waits, on real time, until [condition] holds.
Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('The condition never held.');
}

/// Runs [work] in the test's own zone, pumping frames until it lands, so the
/// database's queue and stream timers all run on fake time.
Future<T> _onFakeTime<T>(WidgetTester tester, Future<T> Function() work) async {
  T? result;
  var done = false;
  unawaited(
    work().then((value) {
      result = value;
      done = true;
    }),
  );
  for (var frame = 0; frame < 200 && !done; frame += 1) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done, isTrue);
  return result as T;
}

Future<void> _pumpLive(
  WidgetTester tester,
  TrainingRepositories repositories,
  Widget home,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        protocolsClockProvider.overrideWithValue(() => _now),
        // The Consistency view opens behind `ProtocolsLockGate`; a store with
        // no lock keeps it off the secure-storage plugin, which no widget
        // test has a device for.
        protocolsLockStoreProvider.overrideWith((ref) => _NoLockStore()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: home,
      ),
    ),
  );
}

/// Unmounts, then closes the database on fake time: Drift's close waits for
/// its stream-cache timers, which only frames can fire.
Future<void> _closeLive(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var closed = false;
  unawaited(database.close().then((_) => closed = true));
  for (var frame = 0; frame < 100 && !closed; frame += 1) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(closed, isTrue);
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 40,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Could not find $finder.');
}

class _NoLockStore implements ProtocolsLockStore {
  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<String?> readPinHash() async => null;

  @override
  Future<void> writePinHash(String hash) async {}

  @override
  Future<void> clearPin() async {}
}
