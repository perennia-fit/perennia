import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocol_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/widgets/compound_list_screen.dart';
import 'package:perennia/features/protocols/widgets/protocols_day_view.dart';
import 'package:perennia/features/protocols/widgets/protocols_lock_screen.dart';
import 'package:perennia/l10n/app_localizations_en.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

// Mirrors protocols_day_view_test.dart's fake-controller pattern: the widget
// is exercised against fake providers (no real Drift streams), so these tests
// verify the SCREEN'S wiring — search/favourites/recents assembly and the
// calls it makes on the controller — while the repository behaviour itself
// (persistence, derivation) is covered by protocols_repository_test.dart.

void main() {
  testWidgets(
    'Compound list shows the User library and the OTC seed',
    (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('user-1', 'Ashwagandha'),
          _compound('seed-1', 'Vitamin D'),
        ],
      );

      await _pumpCompoundList(tester, harness: harness);
      await _pumpUntilFound(tester, find.byKey(CompoundListScreen.listKey));

      expect(find.text('Ashwagandha'), findsOneWidget);
      expect(find.text('Vitamin D'), findsOneWidget);
      expect(
          find.byKey(CompoundListScreen.allSectionHeaderKey), findsOneWidget);
    },
  );

  testWidgets('search filters the Compound list by name', (tester) async {
    final harness = _Harness(
      compounds: <CompoundRecord>[
        _compound('c-1', 'Ashwagandha'),
        _compound('c-2', 'L-Theanine'),
      ],
    );

    await _pumpCompoundList(tester, harness: harness);
    await _pumpUntilFound(tester, find.text('Ashwagandha'));
    expect(find.text('L-Theanine'), findsOneWidget);

    await tester.enterText(
      find.byKey(CompoundListScreen.searchFieldKey),
      'ashwa',
    );
    await tester.pumpAndSettle();

    expect(find.text('Ashwagandha'), findsOneWidget);
    expect(find.text('L-Theanine'), findsNothing);
  });

  testWidgets('search with no matches shows the empty state', (tester) async {
    final harness = _Harness(
      compounds: <CompoundRecord>[_compound('c-1', 'Ashwagandha')],
    );

    await _pumpCompoundList(tester, harness: harness);
    await _pumpUntilFound(tester, find.text('Ashwagandha'));

    await tester.enterText(
      find.byKey(CompoundListScreen.searchFieldKey),
      'nonexistent-compound-xyz',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(CompoundListScreen.emptyStateKey), findsOneWidget);
    expect(find.byKey(CompoundListScreen.listKey), findsNothing);
  });

  testWidgets('the "+" button creates a Compound through the controller', (
    tester,
  ) async {
    final harness = _Harness(compounds: <CompoundRecord>[]);

    await _pumpCompoundList(tester, harness: harness);
    await _pumpUntilFound(
      tester,
      find.byKey(CompoundListScreen.addCompoundButtonKey),
    );
    expect(find.byKey(CompoundListScreen.emptyStateKey), findsOneWidget);

    await tester.tap(find.byKey(CompoundListScreen.addCompoundButtonKey));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(CompoundEditorSheet.nameFieldKey),
      'Rhodiola',
    );
    await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
    await tester.pumpAndSettle();

    expect(harness.controller.createdCompounds, hasLength(1));
    expect(harness.controller.createdCompounds.single.name, 'Rhodiola');
    // The sheet closes back onto the list, which now shows the new row (the
    // fake controller appends it to the same list the screen watches).
    expect(find.text('Rhodiola'), findsOneWidget);
  });

  testWidgets(
    'toggling favourite hoists a virtual Favorites section and calls setFavorite',
    (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[_compound('c-1', 'Ashwagandha')],
      );

      await _pumpCompoundList(tester, harness: harness);
      await _pumpUntilFound(tester, find.text('Ashwagandha'));

      expect(
        find.byKey(CompoundListScreen.favoritesSectionHeaderKey),
        findsNothing,
      );

      await tester.tap(
        find.byKey(CompoundListScreen.favoriteButtonKey('c-1')).first,
      );
      await tester.pumpAndSettle();

      expect(harness.controller.favoriteCalls, <(String, bool)>[
        ('c-1', true),
      ]);
      expect(
        find.byKey(CompoundListScreen.favoritesSectionHeaderKey),
        findsOneWidget,
      );
      // The favourited Compound now renders TWICE — hoisted in the virtual
      // Favorites section AND still in the full library below (mirrors the
      // exercise catalog pattern: favourites is a duplicate shortcut view).
      expect(
        find.byKey(CompoundListScreen.favoriteButtonKey('c-1')),
        findsNWidgets(2),
      );

      // Toggling back off (via the Favorites section's row) drops the virtual
      // section again.
      await tester.tap(
        find.byKey(CompoundListScreen.favoriteButtonKey('c-1')).first,
      );
      await tester.pumpAndSettle();

      expect(harness.controller.favoriteCalls, <(String, bool)>[
        ('c-1', true),
        ('c-1', false),
      ]);
      expect(
        find.byKey(CompoundListScreen.favoritesSectionHeaderKey),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a recently logged Compound appears in the derived Recent section',
    (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('c-1', 'Ashwagandha'),
          _compound('c-2', 'Untouched'),
        ],
        recentCompoundIds: <String>[],
      );

      await _pumpCompoundList(tester, harness: harness);
      await _pumpUntilFound(tester, find.text('Ashwagandha'));
      // Never logged, so it never appears in the derived Recent shortlist.
      expect(
        find.byKey(CompoundListScreen.recentsSectionHeaderKey),
        findsNothing,
      );

      harness.emitRecentCompoundIds(<String>['c-1']);
      await tester.pumpAndSettle();

      expect(
        find.byKey(CompoundListScreen.recentsSectionHeaderKey),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping a Compound row opens the sheet prefilled from its last Dose — '
    'a repeat log is <=2 taps',
    (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[_compound('c-1', 'Ashwagandha')],
      );
      harness.controller.nextLastDose = _lastDose(
        compoundId: 'c-1',
        compoundName: 'Ashwagandha',
        amountValue: 500,
        amountEntered: '500',
        unit: DoseUnit.milligram,
        route: DoseRoute.oral,
      );

      await _pumpCompoundList(tester, harness: harness);
      await _pumpUntilFound(tester, find.text('Ashwagandha'));

      // Tap 1: open the Compound.
      await tester.tap(find.byKey(CompoundListScreen.compoundRowKey('c-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(LogDoseSheet.saveButtonKey), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(LogDoseSheet.unitChipKey(DoseUnit.milligram)),
            )
            .selected,
        isTrue,
      );

      // Tap 2: Save — a single tap logs the Dose, prefilled from last.
      await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.pump();

      expect(harness.controller.loggedDoses, hasLength(1));
      final dose = harness.controller.loggedDoses.single;
      expect(dose.compoundId, 'c-1');
      expect(dose.amountValue, 500);
      expect(dose.amountEntered, '500');
      expect(dose.unit, DoseUnit.milligram);
      expect(dose.route, DoseRoute.oral);
    },
  );

  testWidgets(
    'opened from the Protocol Day view, the sheet opens on the selected '
    'Protocol Day: a past day defaults to 12:00 on that date',
    (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[_compound('c-1', 'Ashwagandha')],
      );
      harness.controller.nextLastDose = _lastDose(
        compoundId: 'c-1',
        compoundName: 'Ashwagandha',
        amountValue: 500,
        amountEntered: '500',
        unit: DoseUnit.milligram,
        route: DoseRoute.oral,
      );

      await _pumpCompoundList(
        tester,
        harness: harness,
        selectedProtocolDay: const ProtocolDayDate(
          year: 2026,
          month: 10,
          day: 25,
        ),
      );
      await _pumpUntilFound(tester, find.text('Ashwagandha'));

      // Library's list → the Protocol Day view → its add button → the list
      // opened for the selected Protocol Day (file 38).
      await tester.tap(find.byKey(CompoundListScreen.viewDayButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProtocolsDayView.logDoseButtonKey));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CompoundListScreen>(find.byType(CompoundListScreen))
            .protocolDay,
        const ProtocolDayDate(year: 2026, month: 10, day: 25),
      );

      await tester.tap(find.byKey(CompoundListScreen.compoundRowKey('c-1')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(LogDoseSheet.dateFieldKey),
          matching: find.text('Oct 25, 2026'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(LogDoseSheet.timeFieldKey),
          matching: find.text('12:00 PM'),
        ),
        findsOneWidget,
      );
      // The amount still prefills from the last Dose of the Compound.
      expect(find.text('500'), findsOneWidget);

      await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.pump();

      expect(
        harness.controller.loggedDoses.single.tookAt,
        DateTime(2026, 10, 25, 12),
      );
    },
  );

  testWidgets(
    'opened as from Library after browsing a past day, the sheet opens on '
    'today, at now',
    (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[_compound('c-1', 'Ashwagandha')],
      );

      // The selected Protocol Day outlives the view that set it; the list
      // reached from Library or Settings never reads it (file 38).
      await _pumpCompoundList(
        tester,
        harness: harness,
        selectedProtocolDay: const ProtocolDayDate(
          year: 2026,
          month: 10,
          day: 25,
        ),
      );
      await _pumpUntilFound(tester, find.text('Ashwagandha'));

      await tester.tap(find.byKey(CompoundListScreen.compoundRowKey('c-1')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(LogDoseSheet.dateFieldKey),
          matching: find.text('Oct 27, 2026'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.pump();

      expect(harness.controller.loggedDoses.single.tookAt, _now);
    },
  );

  testWidgets(
    'on today\'s Protocol Day the sheet defaults to now',
    (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[_compound('c-1', 'Ashwagandha')],
      );

      await _pumpCompoundList(
        tester,
        harness: harness,
        selectedProtocolDay: const ProtocolDayDate(
          year: 2026,
          month: 10,
          day: 27,
        ),
      );
      await _pumpUntilFound(tester, find.text('Ashwagandha'));

      await tester.tap(find.byKey(CompoundListScreen.compoundRowKey('c-1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.tap(find.byKey(LogDoseSheet.saveButtonKey));
      await tester.pump();

      expect(harness.controller.loggedDoses.single.tookAt, _now);
    },
  );

  testWidgets(
    'a Compound with no prior Dose falls back to its default unit/route',
    (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          CompoundRecord(
            id: 'c-1',
            name: 'Vitamin D',
            defaultUnit: DoseUnit.internationalUnit,
            defaultRoute: DoseRoute.sublingual,
            updatedAt: DateTime.utc(2026, 6, 30),
          ),
        ],
      );

      await _pumpCompoundList(tester, harness: harness);
      await _pumpUntilFound(tester, find.text('Vitamin D'));

      await tester.tap(find.byKey(CompoundListScreen.compoundRowKey('c-1')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(
                LogDoseSheet.unitChipKey(DoseUnit.internationalUnit),
              ),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(LogDoseSheet.routeChipKey(DoseRoute.sublingual)),
            )
            .selected,
        isTrue,
      );
    },
  );

  testWidgets('the calendar action opens the Protocol Day view', (
    tester,
  ) async {
    final harness = _Harness(compounds: <CompoundRecord>[]);

    await _pumpCompoundList(tester, harness: harness);
    await _pumpUntilFound(
      tester,
      find.byKey(CompoundListScreen.viewDayButtonKey),
    );

    await tester.tap(find.byKey(CompoundListScreen.viewDayButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(ProtocolsDayView), findsOneWidget);
  });

  testWidgets(
    'Compound list meets accessibility guidelines in both themes',
    (tester) async {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final semantics = tester.ensureSemantics();
        final harness = _Harness(
          compounds: <CompoundRecord>[
            _compound('c-1', 'Ashwagandha', isFavorite: true),
          ],
        );

        await _pumpCompoundList(tester, harness: harness, theme: theme);
        await _pumpUntilFound(tester, find.text('Ashwagandha'));

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'Compound editor sheet meets accessibility guidelines in both themes',
    (tester) async {
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final semantics = tester.ensureSemantics();
        final harness = _Harness(compounds: <CompoundRecord>[]);

        await _pumpCompoundList(tester, harness: harness, theme: theme);
        await _pumpUntilFound(
          tester,
          find.byKey(CompoundListScreen.addCompoundButtonKey),
        );

        await tester.tap(find.byKey(CompoundListScreen.addCompoundButtonKey));
        await tester.pumpAndSettle();

        expect(find.byKey(CompoundEditorSheet.nameFieldKey), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  group('editing a Compound (D4)', () {
    testWidgets(
      'a long-press opens the editor prefilled, and a tap still opens the log '
      'sheet',
      (tester) async {
        final harness = _Harness(
          compounds: <CompoundRecord>[_magnesium],
        );

        await _pumpCompoundList(tester, harness: harness);
        await _pumpUntilFound(tester, find.text('Magnesium'));

        await tester.tap(find.byKey(CompoundListScreen.compoundRowKey('c-1')));
        await tester.pumpAndSettle();
        expect(find.byKey(LogDoseSheet.saveButtonKey), findsOneWidget);
        expect(find.byKey(CompoundEditorSheet.saveButtonKey), findsNothing);

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.byKey(LogDoseSheet.saveButtonKey), findsNothing);

        await tester.longPress(
          find.byKey(CompoundListScreen.compoundRowKey('c-1')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Edit compound'), findsOneWidget);
        expect(find.byKey(LogDoseSheet.saveButtonKey), findsNothing);
        expect(
            _fieldText(tester, CompoundEditorSheet.nameFieldKey), 'Magnesium');
        expect(
          _fieldText(tester, CompoundEditorSheet.strengthFieldKey),
          '200 mg/capsule',
        );
        expect(
          find.descendant(
            of: find.byKey(CompoundEditorSheet.unitFieldKey),
            matching: find.text('g'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(CompoundEditorSheet.routeFieldKey),
            matching: find.text('Sublingual'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(CompoundEditorSheet.archiveButtonKey),
          findsOneWidget,
        );
      },
    );

    testWidgets('the row\'s Edit semantics action opens the editor', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);

      await _pumpCompoundList(tester, harness: harness);
      await _pumpUntilFound(tester, find.text('Magnesium'));

      final node = tester.getSemantics(
        find
            .descendant(
              of: find.byKey(CompoundListScreen.compoundRowKey('c-1')),
              matching: find.byType(InkWell),
            )
            .first,
      );
      final actionId = CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: 'Edit'),
      );
      expect(
          node.getSemanticsData().customSemanticsActionIds, contains(actionId));

      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        actionId,
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit compound'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('create mode offers no Archive, and starts on initialName', (
      tester,
    ) async {
      final host = _SheetHost(initialName: 'Glycine');
      final harness = _Harness(compounds: <CompoundRecord>[]);

      await _pumpCompoundList(tester, harness: harness, home: host);
      await host.open(tester);

      expect(find.text('New compound'), findsOneWidget);
      expect(_fieldText(tester, CompoundEditorSheet.nameFieldKey), 'Glycine');
      expect(find.byKey(CompoundEditorSheet.archiveButtonKey), findsNothing);
    });

    testWidgets('the sheet pops the new id on create', (tester) async {
      final host = _SheetHost(initialName: 'Glycine');
      final harness = _Harness(compounds: <CompoundRecord>[]);

      await _pumpCompoundList(tester, harness: harness, home: host);
      await host.open(tester);
      await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
      await tester.pumpAndSettle();

      expect(harness.controller.createdCompounds.single.name, 'Glycine');
      expect(host.results, <String?>['created-1']);
    });

    testWidgets('the sheet pops the Compound\'s id on an edit', (tester) async {
      final host = _SheetHost(compound: _magnesium);
      final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);

      await _pumpCompoundList(tester, harness: harness, home: host);
      await host.open(tester);
      await tester.enterText(
        find.byKey(CompoundEditorSheet.nameFieldKey),
        'Magnesium glycinate',
      );
      await tester.ensureVisible(find.byKey(CompoundEditorSheet.saveButtonKey));
      await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
      await tester.pumpAndSettle();

      final (id, draft) = harness.controller.editedCompounds.single;
      expect(id, 'c-1');
      expect(draft.name, 'Magnesium glycinate');
      expect(draft.defaultUnit, DoseUnit.gram);
      expect(draft.defaultRoute, DoseRoute.sublingual);
      expect(draft.strength, CompoundStrength.parse('200 mg/capsule'));
      expect(host.results, <String?>['c-1']);
    });

    testWidgets(
      'the sheet pops the Compound\'s id on an edit that changes nothing',
      (tester) async {
        final host = _SheetHost(compound: _magnesium);
        final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);
        harness.controller.editResult = null;

        await _pumpCompoundList(tester, harness: harness, home: host);
        await host.open(tester);
        await tester.ensureVisible(
          find.byKey(CompoundEditorSheet.saveButtonKey),
        );
        await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
        await tester.pumpAndSettle();

        expect(harness.controller.editedCompounds.single.$2.strength,
            _magnesium.strength);
        expect(host.results, <String?>['c-1']);
      },
    );

    testWidgets('dismissing the sheet pops null', (tester) async {
      final host = _SheetHost(compound: _magnesium);
      final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);

      await _pumpCompoundList(tester, harness: harness, home: host);
      await host.open(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(harness.controller.editedCompounds, isEmpty);
      expect(host.results, <String?>[null]);
    });

    testWidgets(
      'an empty name and a bad strength show inline, save nothing, and clear '
      'as the user types',
      (tester) async {
        final harness = _Harness(compounds: <CompoundRecord>[]);

        await _pumpCompoundList(tester, harness: harness);
        await _pumpUntilFound(
          tester,
          find.byKey(CompoundListScreen.addCompoundButtonKey),
        );
        await tester.tap(find.byKey(CompoundListScreen.addCompoundButtonKey));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(CompoundEditorSheet.strengthFieldKey),
          'five mg',
        );
        await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
        await tester.pumpAndSettle();

        expect(find.text('Enter a name'), findsOneWidget);
        expect(find.text('Use the form 5 mg/capsule'), findsOneWidget);
        expect(harness.controller.createdCompounds, isEmpty);
        expect(find.byKey(CompoundEditorSheet.saveButtonKey), findsOneWidget);

        await tester.enterText(
          find.byKey(CompoundEditorSheet.nameFieldKey),
          'Rhodiola',
        );
        await tester.pump();
        expect(find.text('Enter a name'), findsNothing);
        expect(find.text('Use the form 5 mg/capsule'), findsOneWidget);

        await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
        await tester.pumpAndSettle();
        expect(find.text('Use the form 5 mg/capsule'), findsOneWidget);
        expect(harness.controller.createdCompounds, isEmpty);

        await tester.enterText(
          find.byKey(CompoundEditorSheet.strengthFieldKey),
          '  ',
        );
        await tester.pump();
        expect(find.text('Use the form 5 mg/capsule'), findsNothing);

        await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
        await tester.pumpAndSettle();
        // A blank strength means no strength, not an error.
        expect(harness.controller.createdCompounds.single.strength, isNull);
      },
    );

    for (final (count, expected) in <(int, String)>[
      (
        0,
        'Archiving hides Magnesium from the list and the picker. Its logged '
            'Doses stay.',
      ),
      (
        1,
        'Magnesium is in 1 active Protocol. Archiving hides it from the list '
            'and the picker; the Protocol keeps it.',
      ),
      (
        3,
        'Magnesium is in 3 active Protocols. Archiving hides it from the list '
            'and the picker; the Protocols keep it.',
      ),
    ]) {
      testWidgets('with $count Protocols, the archive dialog says so', (
        tester,
      ) async {
        final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);
        harness.controller.protocolCount = count;
        final host = _SheetHost(compound: _magnesium);

        await _pumpCompoundList(tester, harness: harness, home: host);
        await host.open(tester);
        await tester.ensureVisible(
          find.byKey(CompoundEditorSheet.archiveButtonKey),
        );
        await tester.tap(find.byKey(CompoundEditorSheet.archiveButtonKey));
        await tester.pumpAndSettle();

        expect(find.text('Archive Magnesium?'), findsOneWidget);
        expect(find.text(expected), findsOneWidget);
        expect(harness.controller.archivedCompoundIds, isEmpty);
      });
    }

    testWidgets('cancelling the archive dialog keeps the sheet open', (
      tester,
    ) async {
      final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);
      final host = _SheetHost(compound: _magnesium);

      await _pumpCompoundList(tester, harness: harness, home: host);
      await host.open(tester);
      await tester.ensureVisible(
        find.byKey(CompoundEditorSheet.archiveButtonKey),
      );
      await tester.tap(find.byKey(CompoundEditorSheet.archiveButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(harness.controller.archivedCompoundIds, isEmpty);
      expect(find.byKey(CompoundEditorSheet.archiveButtonKey), findsOneWidget);
      expect(host.results, isEmpty);
    });

    testWidgets('confirming archives the Compound and closes the sheet', (
      tester,
    ) async {
      final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);
      final host = _SheetHost(compound: _magnesium);

      await _pumpCompoundList(tester, harness: harness, home: host);
      await host.open(tester);
      await tester.ensureVisible(
        find.byKey(CompoundEditorSheet.archiveButtonKey),
      );
      await tester.tap(find.byKey(CompoundEditorSheet.archiveButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CompoundEditorSheet.archiveConfirmButtonKey));
      await tester.pumpAndSettle();

      expect(harness.controller.archivedCompoundIds, <String>['c-1']);
      expect(find.byKey(CompoundEditorSheet.nameFieldKey), findsNothing);
      expect(host.results, <String?>[null]);
    });

    testWidgets(
      'the editor meets accessibility guidelines in edit mode in both themes',
      (tester) async {
        for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
          final semantics = tester.ensureSemantics();
          final host = _SheetHost(compound: _magnesium);
          final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);

          await _pumpCompoundList(
            tester,
            harness: harness,
            theme: theme,
            home: host,
          );
          await host.open(tester);

          expect(
            tester
                .getSize(find.byKey(CompoundEditorSheet.archiveButtonKey))
                .height,
            AppDimens.touchTarget,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'the editor fits at 320 dp and 1.3x text with the keyboard up and errors '
      'showing',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.reset);
        final host = _SheetHost(compound: _magnesium);
        final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);

        await _pumpCompoundList(
          tester,
          harness: harness,
          home: host,
          textScaler: const TextScaler.linear(1.3),
        );
        await host.open(tester);

        await tester.enterText(
            find.byKey(CompoundEditorSheet.nameFieldKey), '');
        await tester.enterText(
          find.byKey(CompoundEditorSheet.strengthFieldKey),
          'nope',
        );
        await tester.ensureVisible(
          find.byKey(CompoundEditorSheet.saveButtonKey),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
        await tester.pumpAndSettle();

        expect(find.text('Enter a name'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(CompoundEditorSheet.archiveButtonKey),
        );
        await tester.pumpAndSettle();
        expect(
          tester
                  .getRect(find.byKey(CompoundEditorSheet.archiveButtonKey))
                  .bottom <=
              568 - 260,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the list and the dialog fit at 320 dp and 1.3x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _magnesium,
          _compound('c-2', 'Ashwagandha', isFavorite: true),
        ],
        recentCompoundIds: <String>['c-1'],
      );
      harness.controller.protocolCount = 3;

      await _pumpCompoundList(
        tester,
        harness: harness,
        textScaler: const TextScaler.linear(1.3),
      );
      await _pumpUntilFound(tester, find.text('Magnesium'));
      await tester.longPress(
        find.byKey(CompoundListScreen.compoundRowKey('c-1')).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(CompoundEditorSheet.archiveButtonKey),
      );
      await tester.tap(find.byKey(CompoundEditorSheet.archiveButtonKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('3 active Protocols'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Protocols sheets and the lock (D6)', () {
    testWidgets(
      'locking removes the sheet, renders nothing meanwhile, and leaves the '
      'lock screen',
      (tester) async {
        final lock = _SwitchableLockController();
        final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);

        await _pumpCompoundList(
          tester,
          harness: harness,
          lock: lock,
          gated: true,
        );
        await _pumpUntilFound(tester, find.text('Magnesium'));
        await tester.longPress(
          find.byKey(CompoundListScreen.compoundRowKey('c-1')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(CompoundEditorSheet.nameFieldKey), findsOneWidget);

        lock.set(ProtocolsLockStatus.locked);
        await tester.pump();

        // The frame the lock lands on already hides the content.
        expect(find.byKey(CompoundEditorSheet.nameFieldKey), findsNothing);
        expect(find.text('Magnesium'), findsNothing);

        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byKey(ProtocolsLockGate.lockScreenKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('an unavailable lock removes the sheet as well', (
      tester,
    ) async {
      final lock = _SwitchableLockController();
      final host = _SheetHost(compound: _magnesium);
      final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);

      await _pumpCompoundList(
        tester,
        harness: harness,
        lock: lock,
        home: host,
      );
      await host.open(tester);

      lock.set(ProtocolsLockStatus.unavailable);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(host.results, <String?>[null]);
    });

    testWidgets(
      'locking removes the archive dialog and the sheet under it, each its '
      'own route, and archives nothing',
      (tester) async {
        final lock = _SwitchableLockController();
        final host = _SheetHost(compound: _magnesium);
        final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);

        await _pumpCompoundList(
          tester,
          harness: harness,
          lock: lock,
          home: host,
        );
        await host.open(tester);
        await tester.ensureVisible(
          find.byKey(CompoundEditorSheet.archiveButtonKey),
        );
        await tester.tap(find.byKey(CompoundEditorSheet.archiveButtonKey));
        await tester.pumpAndSettle();
        expect(find.text('Archive Magnesium?'), findsOneWidget);

        lock.set(ProtocolsLockStatus.locked);
        await tester.pump();
        expect(find.text('Archive Magnesium?'), findsNothing);

        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        // The host page under both routes stays: only guarded routes go.
        expect(find.byKey(_SheetHost.openKey), findsOneWidget);
        expect(harness.controller.archivedCompoundIds, isEmpty);
        expect(host.results, <String?>[null]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the guard shows its child while the lock state loads', (
      tester,
    ) async {
      final pending = Completer<ProtocolsLockState>();
      final lock = _SwitchableLockController(initial: pending.future);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            protocolsLockControllerProvider.overrideWith(() => lock),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProtocolsLockSheetGuard(child: Text('Compound names')),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Compound names'), findsOneWidget);
      pending.complete(
        const ProtocolsLockState(
          status: ProtocolsLockStatus.unlocked,
          hasPin: true,
        ),
      );
      await tester.pump();
      expect(find.text('Compound names'), findsOneWidget);
    });
  });

  group('no hardcoded English (D7)', () {
    /// What these surfaces show that isn't their copy: user data, and the
    /// shared unit and route labels D7 leaves hardcoded.
    final exempt = <String>{
      'Open', // The test host's own button.
      'Magnesium',
      'Ashwagandha',
      '200 mg/capsule',
      'g · Sublingual · 200 mg/capsule',
      'mg · Oral',
      for (final unit in DoseUnit.values) doseUnitLabel(unit),
      for (final route in DoseRoute.values) doseRouteLabel(route),
    };

    void expectAllPrefixed(WidgetTester tester) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? text.textSpan!.toPlainText());
      final tooltips = <String?>[
        ...tester
            .widgetList<IconButton>(find.byType(IconButton))
            .map((button) => button.tooltip),
        ...tester
            .widgetList<FloatingActionButton>(
              find.byType(FloatingActionButton),
            )
            .map((button) => button.tooltip),
      ].nonNulls;
      final unprefixed = <String>[
        for (final text in <String>[...texts, ...tooltips])
          if (!text.startsWith(_prefix) && !exempt.contains(text)) text,
      ];
      expect(unprefixed, isEmpty);
    }

    testWidgets('the Compound list, with every section', (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _magnesium,
          _compound('c-2', 'Ashwagandha', isFavorite: true),
        ],
        recentCompoundIds: <String>['c-1'],
      );

      await _pumpCompoundList(tester, harness: harness, prefixed: true);
      await _pumpUntilFound(tester, find.text('Magnesium'));

      expect(find.byKey(CompoundListScreen.favoritesSectionHeaderKey),
          findsOneWidget);
      expect(find.byKey(CompoundListScreen.recentsSectionHeaderKey),
          findsOneWidget);
      expectAllPrefixed(tester);

      final semantics = tester.ensureSemantics();
      await tester.pump();
      final node = tester.getSemantics(
        find
            .descendant(
              of: find.byKey(CompoundListScreen.compoundRowKey('c-1')).first,
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(
        node.getSemanticsData().customSemanticsActionIds,
        contains(
          CustomSemanticsAction.getIdentifier(
            const CustomSemanticsAction(label: '${_prefix}Edit'),
          ),
        ),
      );
      semantics.dispose();
    });

    testWidgets('the Compound list\'s empty states', (tester) async {
      final harness = _Harness(compounds: <CompoundRecord>[]);

      await _pumpCompoundList(tester, harness: harness, prefixed: true);
      await _pumpUntilFound(
          tester, find.byKey(CompoundListScreen.emptyStateKey));
      expectAllPrefixed(tester);

      await tester.enterText(
        find.byKey(CompoundListScreen.searchFieldKey),
        'Magnesium',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(CompoundListScreen.emptyStateKey), findsOneWidget);
      expectAllPrefixed(tester);
    });

    testWidgets('the editor, its errors and both archive dialogs', (
      tester,
    ) async {
      final harness = _Harness(compounds: <CompoundRecord>[_magnesium]);
      final host = _SheetHost(compound: _magnesium);

      await _pumpCompoundList(
        tester,
        harness: harness,
        prefixed: true,
        home: host,
      );
      await host.open(tester);
      expectAllPrefixed(tester);

      await tester.enterText(find.byKey(CompoundEditorSheet.nameFieldKey), '');
      await tester.enterText(
        find.byKey(CompoundEditorSheet.strengthFieldKey),
        'nope',
      );
      await tester.ensureVisible(find.byKey(CompoundEditorSheet.saveButtonKey));
      await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a name'), findsOneWidget);
      expectAllPrefixed(tester);

      for (final count in <int>[0, 1, 3]) {
        harness.controller.protocolCount = count;
        await tester.ensureVisible(
          find.byKey(CompoundEditorSheet.archiveButtonKey),
        );
        await tester.tap(find.byKey(CompoundEditorSheet.archiveButtonKey));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expectAllPrefixed(tester);
        await tester.tap(find.text('${_prefix}Cancel'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('create mode', (tester) async {
      final harness = _Harness(compounds: <CompoundRecord>[]);
      final host = _SheetHost();

      await _pumpCompoundList(
        tester,
        harness: harness,
        prefixed: true,
        home: host,
      );
      await host.open(tester);

      expect(find.text('${_prefix}New compound'), findsOneWidget);
      expectAllPrefixed(tester);
    });
  });
}

const _prefix = 'ZZ ';

/// Prefixes every string the Compound list and editor take from
/// [AppLocalizations], so anything on screen without the prefix was hardcoded.
class _PrefixedLocalizations extends AppLocalizationsEn {
  String _p(String value) => '$_prefix$value';

  @override
  String get navCompounds => _p(super.navCompounds);
  @override
  String get consistencyButton => _p(super.consistencyButton);
  @override
  String get cancelAction => _p(super.cancelAction);
  @override
  String get compoundListViewByDay => _p(super.compoundListViewByDay);
  @override
  String get compoundListSearchHint => _p(super.compoundListSearchHint);
  @override
  String get compoundListEmpty => _p(super.compoundListEmpty);
  @override
  String get compoundListNoMatches => _p(super.compoundListNoMatches);
  @override
  String get compoundListFavorites => _p(super.compoundListFavorites);
  @override
  String get compoundListRecent => _p(super.compoundListRecent);
  @override
  String get compoundListAll => _p(super.compoundListAll);
  @override
  String get compoundListAdd => _p(super.compoundListAdd);
  @override
  String get compoundListRemoveFavorite => _p(super.compoundListRemoveFavorite);
  @override
  String get compoundListAddFavorite => _p(super.compoundListAddFavorite);
  @override
  String get compoundListEditAction => _p(super.compoundListEditAction);
  @override
  String get compoundEditorNewTitle => _p(super.compoundEditorNewTitle);
  @override
  String get compoundEditorEditTitle => _p(super.compoundEditorEditTitle);
  @override
  String get compoundEditorName => _p(super.compoundEditorName);
  @override
  String get compoundEditorStrength => _p(super.compoundEditorStrength);
  @override
  String get compoundEditorDefaultUnit => _p(super.compoundEditorDefaultUnit);
  @override
  String get compoundEditorDefaultRoute => _p(super.compoundEditorDefaultRoute);
  @override
  String get compoundEditorSave => _p(super.compoundEditorSave);
  @override
  String get compoundEditorArchive => _p(super.compoundEditorArchive);
  @override
  String get compoundEditorNameRequired => _p(super.compoundEditorNameRequired);
  @override
  String get compoundEditorStrengthInvalid =>
      _p(super.compoundEditorStrengthInvalid);
  @override
  String compoundArchiveTitle(String name) =>
      _p(super.compoundArchiveTitle(name));
  @override
  String compoundArchiveInProtocols(int count, String name) =>
      _p(super.compoundArchiveInProtocols(count, name));
  @override
  String compoundArchiveUnused(String name) =>
      _p(super.compoundArchiveUnused(name));
  @override
  String get compoundArchiveConfirm => _p(super.compoundArchiveConfirm);
}

class _PrefixedLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _PrefixedLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(_PrefixedLocalizations());

  @override
  bool shouldReload(_PrefixedLocalizationsDelegate old) => false;
}

/// A page with one button that opens the Compound editor sheet, recording what
/// it completes with.
class _SheetHost extends StatelessWidget {
  _SheetHost({this.compound, this.initialName});

  final CompoundRecord? compound;
  final String? initialName;
  final results = <String?>[];

  static const openKey = Key('test.sheetHost.open');

  Future<void> open(WidgetTester tester) async {
    await _pumpUntilFound(tester, find.byKey(openKey));
    await tester.tap(find.byKey(openKey));
    await tester.pumpAndSettle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: openKey,
          onPressed: () async {
            results.add(
              await showCompoundEditorSheet(
                context,
                compound: compound,
                initialName: initialName,
              ),
            );
          },
          child: const Text('Open'),
        ),
      ),
    );
  }
}

/// A lock whose state a test sets directly, the way the real controller moves
/// when the app backgrounds.
class _SwitchableLockController extends ProtocolsLockController {
  _SwitchableLockController({this.initial});

  final Future<ProtocolsLockState>? initial;

  @override
  Future<ProtocolsLockState> build() async {
    return initial ??
        const ProtocolsLockState(
          status: ProtocolsLockStatus.unlocked,
          hasPin: true,
        );
  }

  void set(ProtocolsLockStatus status) {
    state = AsyncData<ProtocolsLockState>(
      ProtocolsLockState(status: status, hasPin: true),
    );
  }
}

String _fieldText(WidgetTester tester, Key key) {
  return tester.widget<TextField>(find.byKey(key)).controller!.text;
}

final _magnesium = CompoundRecord(
  id: 'c-1',
  name: 'Magnesium',
  defaultUnit: DoseUnit.gram,
  defaultRoute: DoseRoute.sublingual,
  strength: CompoundStrength.parse('200 mg/capsule'),
  updatedAt: DateTime.utc(2026, 6, 30),
);

CompoundRecord _compound(
  String id,
  String name, {
  bool isFavorite = false,
}) {
  return CompoundRecord(
    id: id,
    name: name,
    defaultUnit: DoseUnit.milligram,
    defaultRoute: DoseRoute.oral,
    isFavorite: isFavorite,
    updatedAt: DateTime.utc(2026, 6, 30),
  );
}

DoseRecord _lastDose({
  required String compoundId,
  required String compoundName,
  required double amountValue,
  required String amountEntered,
  required DoseUnit unit,
  required DoseRoute route,
}) {
  return DoseRecord(
    id: 'dose-last',
    compoundId: compoundId,
    compoundName: compoundName,
    amountValue: amountValue,
    amountEntered: amountEntered,
    unit: unit,
    route: route,
    tookAt: DateTime.utc(2026, 6, 29, 8),
    timezone: 'Australia/Brisbane',
    localDate: const ProtocolDayDate(year: 2026, month: 6, day: 29),
    provenance: DoseProvenance.manual,
    updatedAt: DateTime.utc(2026, 6, 29, 8),
  );
}

/// Bundles the fake controller + the two stream controllers backing
/// [compoundListProvider]/[recentCompoundIdsProvider], so a test can drive both
/// the widget's actions (via the controller) and its data (via emit*).
class _Harness {
  _Harness({
    required List<CompoundRecord> compounds,
    List<String> recentCompoundIds = const <String>[],
  })  : _compoundsController =
            StreamController<List<CompoundRecord>>.broadcast(),
        _recentCompoundIdsController =
            StreamController<List<String>>.broadcast() {
    controller = _FakeProtocolDayController(this);
    _compounds = List<CompoundRecord>.of(compounds);
    _recentCompoundIds = List<String>.of(recentCompoundIds);
  }

  late final _FakeProtocolDayController controller;
  final StreamController<List<CompoundRecord>> _compoundsController;
  final StreamController<List<String>> _recentCompoundIdsController;
  late List<CompoundRecord> _compounds;
  late List<String> _recentCompoundIds;

  Stream<List<CompoundRecord>> get compoundsStream async* {
    yield List<CompoundRecord>.of(_compounds);
    yield* _compoundsController.stream;
  }

  Stream<List<String>> get recentCompoundIdsStream async* {
    yield List<String>.of(_recentCompoundIds);
    yield* _recentCompoundIdsController.stream;
  }

  void emitCompounds(List<CompoundRecord> compounds) {
    _compounds = compounds;
    _compoundsController.add(List<CompoundRecord>.of(_compounds));
  }

  void emitRecentCompoundIds(List<String> ids) {
    _recentCompoundIds = ids;
    _recentCompoundIdsController.add(List<String>.of(_recentCompoundIds));
  }
}

class _FakeProtocolDayController extends ProtocolDayController {
  _FakeProtocolDayController(this._harness);

  final _Harness _harness;
  final createdCompounds = <CompoundDraft>[];
  final favoriteCalls = <(String, bool)>[];
  final loggedDoses = <DoseSnapshotDraft>[];
  final editedCompounds = <(String, CompoundDraft)>[];
  final archivedCompoundIds = <String>[];

  /// What `editCompound` returns: a Batch id, or null for no change.
  String? editResult = 'batch-edit';

  /// How many active Protocols the archive dialog is told hold the Compound.
  int protocolCount = 0;

  /// The Dose `lastDoseFor` resolves to for ANY Compound, set per-test — a
  /// fake substitute for the repository's DERIVED-on-read lookup.
  DoseRecord? nextLastDose;

  @override
  Stream<ProtocolDayState> build() {
    return Stream<ProtocolDayState>.value(
      ProtocolDayState(
        day: ProtocolDayRecord(
          localDate: const ProtocolDayDate(year: 2026, month: 6, day: 30),
          doses: <DoseRecord>[],
        ),
      ),
    );
  }

  @override
  Future<DoseRecord?> lastDoseFor(String compoundId) async => nextLastDose;

  @override
  Future<LogDoseResult> logDose(
    DoseSnapshotDraft draft, {
    String? unskipId,
  }) async {
    loggedDoses.add(draft);
    return LogDoseResult(
      batchId: 'batch-${loggedDoses.length}',
      doseId: 'dose-${loggedDoses.length}',
    );
  }

  @override
  Future<CreateCompoundResult> createCompound(CompoundDraft draft) async {
    createdCompounds.add(draft);
    final record = CompoundRecord(
      id: 'created-${createdCompounds.length}',
      name: draft.name,
      defaultUnit: draft.defaultUnit,
      defaultRoute: draft.defaultRoute,
      strength: draft.strength,
      updatedAt: DateTime.utc(2026, 6, 30),
    );
    _harness.emitCompounds(<CompoundRecord>[..._harness._compounds, record]);
    return CreateCompoundResult(
      batchId: 'batch-${createdCompounds.length}',
      compoundId: record.id,
    );
  }

  @override
  Future<String?> editCompound(String compoundId, CompoundDraft draft) async {
    editedCompounds.add((compoundId, draft));
    return editResult;
  }

  @override
  Future<String> archiveCompound(String compoundId) async {
    archivedCompoundIds.add(compoundId);
    return 'batch-archive';
  }

  @override
  Future<int> countProtocolsWithCompound(String compoundId) async {
    return protocolCount;
  }

  @override
  Future<void> setFavorite(String compoundId,
      {required bool isFavorite}) async {
    favoriteCalls.add((compoundId, isFavorite));
    _harness.emitCompounds(<CompoundRecord>[
      for (final compound in _harness._compounds)
        if (compound.id == compoundId)
          CompoundRecord(
            id: compound.id,
            name: compound.name,
            defaultUnit: compound.defaultUnit,
            defaultRoute: compound.defaultRoute,
            strength: compound.strength,
            isFavorite: isFavorite,
            updatedAt: compound.updatedAt,
          )
        else
          compound,
    ]);
  }

  @override
  Future<void> ensureOtcLibrarySeeded() async {}
}

/// "Now" for the sheet's time default: the afternoon of 2026-10-27.
final DateTime _now = DateTime(2026, 10, 27, 15, 30);

class _FixedProtocolDay extends SelectedProtocolDayController {
  _FixedProtocolDay(this._date);

  final ProtocolDayDate _date;

  @override
  ProtocolDayDate build() => _date;
}

Future<void> _pumpCompoundList(
  WidgetTester tester, {
  required _Harness harness,
  ThemeData? theme,
  ProtocolDayDate? selectedProtocolDay,
  Widget? home,
  TextScaler? textScaler,
  ProtocolsLockController? lock,
  bool gated = false,
  bool prefixed = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        protocolsClockProvider.overrideWithValue(() => _now),
        if (selectedProtocolDay != null)
          selectedProtocolDayProvider.overrideWith(
            () => _FixedProtocolDay(selectedProtocolDay),
          ),
        protocolDayControllerProvider.overrideWith(() => harness.controller),
        compoundListProvider.overrideWith((ref) => harness.compoundsStream),
        recentCompoundIdsProvider.overrideWith(
          (ref) => harness.recentCompoundIdsStream,
        ),
        // The "view day" push now wraps `ProtocolsDayView` in a
        // `ProtocolsLockGate`; a fake no-lock store keeps this
        // screen's tests off the real `flutter_secure_storage` platform
        // channel, which no widget test has a device for.
        protocolsLockStoreProvider.overrideWith((ref) => _NoLockStore()),
        if (lock != null)
          protocolsLockControllerProvider.overrideWith(() => lock),
        // LogDoseSheet's OPTIONAL Protocol tag picker reads this;
        // no Protocols fixture here, so it renders empty (None-only).
        protocolOptionListProvider.overrideWith(
          (ref) => Stream<List<ProtocolOptionRecord>>.value(
            const <ProtocolOptionRecord>[],
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: prefixed
            ? <LocalizationsDelegate<dynamic>>[
                const _PrefixedLocalizationsDelegate(),
                ...AppLocalizations.localizationsDelegates.where(
                  (delegate) => delegate.type != AppLocalizations,
                ),
              ]
            : AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.light(),
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                ),
        home: home ??
            (gated
                ? const ProtocolsLockGate(child: CompoundListScreen())
                : const CompoundListScreen()),
      ),
    ),
  );
  await tester.pump();
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
  fail('Could not find $finder.');
}

/// An in-memory `ProtocolsLockStore` fake that never reports a configured
/// lock — keeps `ProtocolsLockGate` off the real secure-storage plugin
/// channel in widget tests that don't care about the lock itself.
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
