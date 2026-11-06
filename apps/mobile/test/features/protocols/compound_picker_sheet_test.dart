import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_lock_controller.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/widgets/compound_list_screen.dart';
import 'package:perennia/features/protocols/widgets/compound_picker_sheet.dart';
import 'package:perennia/l10n/app_localizations_en.dart';
import 'package:perennia/l10n/l10n.dart';
import 'package:perennia/theme/theme.dart';

import '../../performance/performance_budget_thresholds.dart';

// The sheet runs against fake providers: these tests cover its search,
// selection and result. Reading a created Compound by id is covered by
// protocols_repository_test.dart, and a later open's fresh list by
// compound_picker_real_database_test.dart.

void main() {
  group('the list', () {
    testWidgets('sections order and fill the way the Compound list does', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('c-3', 'Zinc', isFavorite: true),
          _compound('c-1', 'Ashwagandha', isFavorite: true),
          _compound(
            'c-2',
            'Magnesium',
            unit: DoseUnit.gram,
            route: DoseRoute.sublingual,
          ),
        ],
        recentCompoundIds: <String>['c-2', 'missing'],
      );
      final host = await _openPicker(tester, harness: harness);

      expect(
        _rowOrder(tester),
        <String>[
          'favorites/c-1',
          'favorites/c-3',
          'recent/c-2',
          'all/c-1',
          'all/c-2',
          'all/c-3',
        ],
      );
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('All compounds'), findsOneWidget);
      expect(find.text('Add Compounds'), findsOneWidget);
      expect(find.text('g · Sublingual'), findsNWidgets(2));
      expect(host.results, isEmpty);
    });

    testWidgets(
      'a Compound in Favorites, Recent and All renders without key errors',
      (tester) async {
        final harness = _Harness(
          compounds: <CompoundRecord>[
            _compound('c-1', 'Ashwagandha', isFavorite: true),
          ],
          recentCompoundIds: <String>['c-1'],
        );
        await _openPicker(tester, harness: harness);

        expect(find.text('Ashwagandha'), findsNWidgets(3));
        expect(_row(CompoundPickerSection.favorites, 'c-1'), findsOneWidget);
        expect(_row(CompoundPickerSection.recent, 'c-1'), findsOneWidget);
        expect(_row(CompoundPickerSection.all, 'c-1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('ticking one section ticks that Compound in the others', (
      tester,
    ) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('c-1', 'Ashwagandha', isFavorite: true),
        ],
      );
      await _openPicker(tester, harness: harness);

      await tester.tap(_row(CompoundPickerSection.favorites, 'c-1'));
      await tester.pump();

      expect(_isTicked(tester, CompoundPickerSection.favorites, 'c-1'), isTrue);
      expect(_isTicked(tester, CompoundPickerSection.all, 'c-1'), isTrue);
    });

    testWidgets('an empty library shows the existing empty string', (
      tester,
    ) async {
      await _openPicker(
        tester,
        harness: _Harness(compounds: const <CompoundRecord>[]),
      );

      expect(find.byKey(CompoundPickerSheet.emptyStateKey), findsOneWidget);
      expect(find.text('No compounds yet.'), findsOneWidget);
      expect(find.byKey(CompoundPickerSheet.createRowKey), findsNothing);
    });

    testWidgets('search matches names only, trimmed and case-insensitive', (
      tester,
    ) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('c-1', 'Ashwagandha', isFavorite: true),
          _compound('c-2', 'Magnesium', unit: DoseUnit.gram),
        ],
        recentCompoundIds: <String>['c-2'],
      );
      await _openPicker(tester, harness: harness);

      await _search(tester, '  MAGNE ');
      expect(_rowOrder(tester), <String>['recent/c-2', 'all/c-2']);
      expect(find.text('Favorites'), findsNothing);

      // "Oral" is on every row's second line, and isn't a name.
      await _search(tester, 'oral');
      expect(_rowOrder(tester), isEmpty);
    });

    testWidgets('selection is drawn in the primary text color, never cyan', (
      tester,
    ) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[_compound('c-1', 'Ashwagandha')],
      );
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        await _openPicker(tester, harness: harness, theme: theme);
        final colors = theme.extension<AppColors>()!;

        final tile = tester.widget<CheckboxListTile>(
          _row(CompoundPickerSection.all, 'c-1'),
        );
        expect(tile.activeColor, colors.textPrimary);
        expect(tile.checkColor, colors.surface);

        final done = tester.widget<TextButton>(
          find.byKey(CompoundPickerSheet.doneButtonKey),
        );
        expect(
          done.style!.foregroundColor!.resolve(<WidgetState>{}),
          colors.textPrimary,
        );
      }
    });
  });

  group('the selection', () {
    testWidgets('search never clears it', (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('c-1', 'Ashwagandha'),
          _compound('c-2', 'Magnesium'),
        ],
      );
      final host = await _openPicker(tester, harness: harness);

      await tester.tap(_row(CompoundPickerSection.all, 'c-1'));
      await tester.pump();
      await _search(tester, 'magn');
      expect(_row(CompoundPickerSection.all, 'c-1'), findsNothing);
      expect(find.text('Done · 1'), findsOneWidget);

      await tester.tap(_row(CompoundPickerSection.all, 'c-2'));
      await tester.pump();
      await _search(tester, '');
      expect(_isTicked(tester, CompoundPickerSection.all, 'c-1'), isTrue);
      expect(_isTicked(tester, CompoundPickerSection.all, 'c-2'), isTrue);

      await _done(tester);
      expect(host.results, <List<String>?>[
        <String>['c-1', 'c-2'],
      ]);
    });

    testWidgets(
        "Done's count is listed Compounds only, and an unlisted id "
        'stays in the result', (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('c-1', 'Ashwagandha'),
          _compound('c-2', 'Magnesium'),
        ],
      );
      final host = await _openPicker(
        tester,
        harness: harness,
        selectedIds: <String>['unlisted', 'c-1'],
      );

      expect(find.text('Done · 1'), findsOneWidget);

      await tester.tap(_row(CompoundPickerSection.all, 'c-2'));
      await tester.pump();
      expect(find.text('Done · 2'), findsOneWidget);

      await tester.tap(_row(CompoundPickerSection.all, 'c-1'));
      await tester.tap(_row(CompoundPickerSection.all, 'c-2'));
      await tester.pump();
      expect(find.text('Done'), findsOneWidget);

      await _done(tester);
      expect(host.results, <List<String>?>[
        <String>['unlisted'],
      ]);
    });

    testWidgets('Done keeps members in order, then new ones in pick order', (
      tester,
    ) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('a', 'Alpha'),
          _compound('b', 'Beta'),
          _compound('c', 'Gamma'),
          _compound('d', 'Delta'),
          _compound('e', 'Epsilon'),
        ],
      );
      final host = await _openPicker(
        tester,
        harness: harness,
        selectedIds: <String>['c', 'a', 'b'],
      );

      await tester.tap(_row(CompoundPickerSection.all, 'e'));
      await tester.tap(_row(CompoundPickerSection.all, 'd'));
      await tester.tap(_row(CompoundPickerSection.all, 'a'));
      await tester.pump();

      await _done(tester);
      expect(host.results, <List<String>?>[
        <String>['c', 'b', 'e', 'd'],
      ]);
    });

    testWidgets('a member unticked and ticked again keeps its place', (
      tester,
    ) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('a', 'Alpha'),
          _compound('b', 'Beta'),
          _compound('c', 'Gamma'),
        ],
      );
      final host = await _openPicker(
        tester,
        harness: harness,
        selectedIds: <String>['a', 'b'],
      );

      await tester.tap(_row(CompoundPickerSection.all, 'c'));
      await tester.tap(_row(CompoundPickerSection.all, 'a'));
      await tester.pump();
      await tester.tap(_row(CompoundPickerSection.all, 'a'));
      await tester.pump();

      await _done(tester);
      expect(host.results, <List<String>?>[
        <String>['a', 'b', 'c'],
      ]);
    });

    testWidgets('dismissing returns null', (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[_compound('c-1', 'Ashwagandha')],
      );
      final host = await _openPicker(tester, harness: harness);

      await tester.tap(_row(CompoundPickerSection.all, 'c-1'));
      await tester.pump();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(host.results, <List<String>?>[null]);
    });
  });

  group('the Create row', () {
    final library = <CompoundRecord>[
      _compound('c-1', 'Creatine'),
      _compound('c-2', 'Creatine Malate'),
    ];

    testWidgets('shows last on a partial match, in the case typed', (
      tester,
    ) async {
      await _openPicker(tester, harness: _Harness(compounds: library));

      await _search(tester, ' CREA ');

      expect(find.text('Create "CREA"'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(CompoundPickerSheet.createRowKey)).dy,
        greaterThan(
          tester.getTopLeft(_row(CompoundPickerSection.all, 'c-2')).dy,
        ),
      );
    });

    testWidgets('hides on an exact match, trimmed and case-insensitive', (
      tester,
    ) async {
      await _openPicker(tester, harness: _Harness(compounds: library));

      await _search(tester, '  cREATINE ');

      expect(_row(CompoundPickerSection.all, 'c-1'), findsOneWidget);
      expect(find.byKey(CompoundPickerSheet.createRowKey), findsNothing);
    });

    testWidgets('hides with only whitespace typed', (tester) async {
      await _openPicker(tester, harness: _Harness(compounds: library));

      await _search(tester, '   ');

      expect(_rowOrder(tester), hasLength(2));
      expect(find.byKey(CompoundPickerSheet.createRowKey), findsNothing);
    });

    testWidgets('is the only row with no matches, also in an empty library', (
      tester,
    ) async {
      await _openPicker(tester, harness: _Harness(compounds: library));
      await _search(tester, 'zinc');
      expect(_rowOrder(tester), isEmpty);
      expect(find.text('All compounds'), findsNothing);
      expect(find.text('Create "zinc"'), findsOneWidget);
      expect(find.byKey(CompoundPickerSheet.emptyStateKey), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await _openPicker(
        tester,
        harness: _Harness(compounds: const <CompoundRecord>[]),
      );
      await _search(tester, 'zinc');
      expect(find.text('Create "zinc"'), findsOneWidget);
      expect(find.byKey(CompoundPickerSheet.emptyStateKey), findsNothing);
    });

    testWidgets('inline create selects the new Compound and clears search', (
      tester,
    ) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('c-1', 'Ashwagandha'),
          _compound('c-2', 'Magnesium'),
        ],
      );
      final host = await _openPicker(
        tester,
        harness: harness,
        selectedIds: <String>['c-2'],
      );

      await _search(tester, ' Glycine ');
      await tester.tap(find.byKey(CompoundPickerSheet.createRowKey));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(CompoundEditorSheet.nameFieldKey))
            .controller!
            .text,
        'Glycine',
      );

      await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
      await tester.pumpAndSettle();

      expect(harness.controller.createdCompounds.single.name, 'Glycine');
      expect(find.byKey(CompoundEditorSheet.nameFieldKey), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(CompoundPickerSheet.searchFieldKey))
            .controller!
            .text,
        isEmpty,
      );
      // Sits A-Z among the rows read when the sheet opened, ticked and counted.
      expect(
        _rowOrder(tester),
        <String>['all/c-1', 'all/created-1', 'all/c-2'],
      );
      expect(_isTicked(tester, CompoundPickerSection.all, 'created-1'), isTrue);
      expect(find.text('Done · 2'), findsOneWidget);

      await _done(tester);
      expect(host.results, <List<String>?>[
        <String>['c-2', 'created-1'],
      ]);
    });

    testWidgets(
      'holds the by-id read open until it answers, then releases it',
      (tester) async {
        final harness = _Harness(compounds: const <CompoundRecord>[]);
        final answer = Completer<void>();
        harness.byIdsGate = answer.future;
        await _openPicker(tester, harness: harness);

        await _search(tester, 'Glycine');
        await tester.tap(find.byKey(CompoundPickerSheet.createRowKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
        await tester.pumpAndSettle();
        expect(find.text('Create "Glycine"'), findsOneWidget);
        expect(harness.byIdsDisposals, 0);

        answer.complete();
        await tester.pumpAndSettle();

        expect(
            _isTicked(tester, CompoundPickerSection.all, 'created-1'), isTrue);
        expect(harness.byIdsDisposals, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('dismissing the editor changes nothing', (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[_compound('c-1', 'Creatine')],
      );
      await _openPicker(tester, harness: harness);

      await _search(tester, 'Crea');
      await tester.tap(find.byKey(CompoundPickerSheet.createRowKey));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byKey(CompoundEditorSheet.nameFieldKey), findsNothing);
      expect(find.text('Create "Crea"'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(harness.controller.createdCompounds, isEmpty);
    });
  });

  group('at 200 Compounds', () {
    final library = <CompoundRecord>[
      for (var index = 0; index < 200; index += 1)
        _compound(
          'c-$index',
          'Compound ${index.toString().padLeft(3, '0')}',
        ),
    ];

    testWidgets('one frame after a keystroke shows the narrowed list', (
      tester,
    ) async {
      await _openPicker(tester, harness: _Harness(compounds: library));

      await tester.enterText(
        find.byKey(CompoundPickerSheet.searchFieldKey),
        '19',
      );
      await tester.pump(setSaveConfirmationFrameBudget);

      expect(find.text('Compound 000'), findsNothing);
      expect(find.text('Compound 190'), findsOneWidget);
      expect(find.text('Compound 019'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('only a screenful of rows is built', (tester) async {
      await _openPicker(tester, harness: _Harness(compounds: library));

      expect(find.byType(CheckboxListTile).evaluate().length, lessThan(20));
      expect(find.text('Compound 199'), findsNothing);

      // Every Compound still matches, and the rows stay lazy.
      await tester.enterText(
        find.byKey(CompoundPickerSheet.searchFieldKey),
        'compound',
      );
      await tester.pump(setSaveConfirmationFrameBudget);

      expect(find.byType(CheckboxListTile).evaluate().length, lessThan(20));
      expect(find.text('Compound 199'), findsNothing);
    });

    testWidgets('a new search starts from the top of the list', (tester) async {
      await _openPicker(tester, harness: _Harness(compounds: library));

      await tester.drag(
        find.byKey(CompoundPickerSheet.listKey),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      expect(find.text('Compound 000'), findsNothing);

      await _search(tester, 'compound 0');

      expect(find.text('Compound 000'), findsOneWidget);
    });
  });

  group('the lock', () {
    testWidgets('locking closes the sheet and returns null', (tester) async {
      final lock = _SwitchableLockController();
      final harness = _Harness(
        compounds: <CompoundRecord>[_compound('c-1', 'Ashwagandha')],
      );
      final host = await _openPicker(tester, harness: harness, lock: lock);
      expect(find.text('Ashwagandha'), findsOneWidget);

      lock.set(ProtocolsLockStatus.locked);
      await tester.pump();
      // The frame the lock lands on already hides the names.
      expect(find.text('Ashwagandha'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(host.results, <List<String>?>[null]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locking closes the editor sheet above it as well', (
      tester,
    ) async {
      final lock = _SwitchableLockController();
      final harness = _Harness(compounds: const <CompoundRecord>[]);
      final host = await _openPicker(tester, harness: harness, lock: lock);

      await _search(tester, 'Glycine');
      await tester.tap(find.byKey(CompoundPickerSheet.createRowKey));
      await tester.pumpAndSettle();

      lock.set(ProtocolsLockStatus.locked);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(host.results, <List<String>?>[null]);
      expect(harness.controller.createdCompounds, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locking during the by-id read closes without an error', (
      tester,
    ) async {
      final lock = _SwitchableLockController();
      final harness = _Harness(compounds: const <CompoundRecord>[]);
      harness.byIdsGate = Completer<void>().future;
      final host = await _openPicker(tester, harness: harness, lock: lock);

      await _search(tester, 'Glycine');
      await tester.tap(find.byKey(CompoundPickerSheet.createRowKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CompoundEditorSheet.saveButtonKey));
      await tester.pumpAndSettle();

      lock.set(ProtocolsLockStatus.locked);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(host.results, <List<String>?>[null]);
      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility', () {
    testWidgets('meets the guidelines in both themes', (tester) async {
      final semantics = tester.ensureSemantics();
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        final harness = _Harness(
          compounds: <CompoundRecord>[
            _compound('c-1', 'Ashwagandha', isFavorite: true),
            _compound('c-2', 'Magnesium'),
          ],
          recentCompoundIds: <String>['c-2'],
        );
        await _openPicker(
          tester,
          harness: harness,
          theme: theme,
          selectedIds: <String>['c-1'],
        );

        expect(
          tester.getSize(find.byKey(CompoundPickerSheet.doneButtonKey)).height,
          greaterThanOrEqualTo(AppDimens.touchTarget),
        );
        expect(
          tester.getSize(_row(CompoundPickerSection.all, 'c-2')).height,
          greaterThanOrEqualTo(AppDimens.touchTarget),
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await _search(tester, 'New one');
        expect(
          tester.getSize(find.byKey(CompoundPickerSheet.createRowKey)).height,
          greaterThanOrEqualTo(AppDimens.touchTarget),
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
      semantics.dispose();
    });

    testWidgets('fits at 320 dp and 1.3x text, with the keyboard up', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('c-1', 'A compound with quite a long name to wrap'),
          _compound('c-2', 'Magnesium', isFavorite: true),
        ],
        recentCompoundIds: <String>['c-2'],
      );
      await _openPicker(
        tester,
        harness: harness,
        textScaler: const TextScaler.linear(1.3),
        selectedIds: <String>['c-1', 'c-2'],
      );
      expect(find.text('Done · 2'), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await _search(tester, 'A compound with a name nothing matches');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The search field stays above the keyboard.
      expect(
        tester.getBottomLeft(find.byKey(CompoundPickerSheet.searchFieldKey)).dy,
        lessThanOrEqualTo(568 - 260),
      );
    });

    testWidgets('no hardcoded English', (tester) async {
      final harness = _Harness(
        compounds: <CompoundRecord>[
          _compound('c-1', 'Ashwagandha', isFavorite: true),
        ],
        recentCompoundIds: <String>['c-1'],
      );

      void expectAllPrefixed({required Set<String> userData}) {
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? text.textSpan!.toPlainText());
        final unprefixed = <String>[
          for (final text in texts)
            if (!text.startsWith(_prefix) && !userData.contains(text)) text,
        ];
        expect(unprefixed, isEmpty);
      }

      await _openPicker(
        tester,
        harness: harness,
        prefixed: true,
        selectedIds: <String>['c-1'],
      );
      // "Done · 1" here, the search hint, and every section header.
      expectAllPrefixed(
        userData: <String>{
          'Open', // The test host's own button.
          'Ashwagandha',
          'mg · Oral',
        },
      );

      await tester.tap(_row(CompoundPickerSection.all, 'c-1'));
      await tester.pump();
      expect(find.text('${_prefix}Done'), findsOneWidget);

      await _search(tester, 'zinc');
      expect(find.text('${_prefix}Create "zinc"'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _openPicker(
        tester,
        harness: _Harness(compounds: const <CompoundRecord>[]),
        prefixed: true,
      );
      expect(find.text('${_prefix}No compounds yet.'), findsOneWidget);
    });
  });
}

const _prefix = '§';

class _PrefixedLocalizations extends AppLocalizationsEn {
  String _p(String value) => '$_prefix$value';

  @override
  String get compoundListSearchHint => _p(super.compoundListSearchHint);
  @override
  String get compoundListEmpty => _p(super.compoundListEmpty);
  @override
  String get compoundListFavorites => _p(super.compoundListFavorites);
  @override
  String get compoundListRecent => _p(super.compoundListRecent);
  @override
  String get compoundListAll => _p(super.compoundListAll);
  @override
  String get compoundPickerTitle => _p(super.compoundPickerTitle);
  @override
  String get compoundPickerDone => _p(super.compoundPickerDone);
  @override
  String compoundPickerDoneCount(int count) =>
      _p(super.compoundPickerDoneCount(count));
  @override
  String compoundPickerCreate(String name) =>
      _p(super.compoundPickerCreate(name));
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

Finder _row(CompoundPickerSection section, String id) {
  return find.byKey(CompoundPickerSheet.rowKey(section, id));
}

bool _isTicked(WidgetTester tester, CompoundPickerSection section, String id) {
  return tester.widget<CheckboxListTile>(_row(section, id)).value!;
}

/// The rows on screen, top to bottom, as "section/id".
List<String> _rowOrder(WidgetTester tester) {
  final rows = tester
      .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
      .map((row) => row.key! as ValueKey<String>)
      .toList();
  double top(ValueKey<String> key) => tester.getTopLeft(find.byKey(key)).dy;
  rows.sort((a, b) => top(a).compareTo(top(b)));
  return <String>[
    for (final key in rows)
      key.value
          .substring('protocols.compoundPicker.row.'.length)
          .replaceFirst('-', '/'),
  ];
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(CompoundPickerSheet.searchFieldKey), text);
  await tester.pump();
}

Future<void> _done(WidgetTester tester) async {
  await tester.tap(find.byKey(CompoundPickerSheet.doneButtonKey));
  await tester.pumpAndSettle();
}

CompoundRecord _compound(
  String id,
  String name, {
  bool isFavorite = false,
  DoseUnit unit = DoseUnit.milligram,
  DoseRoute route = DoseRoute.oral,
}) {
  return CompoundRecord(
    id: id,
    name: name,
    defaultUnit: unit,
    defaultRoute: route,
    isFavorite: isFavorite,
    updatedAt: DateTime.utc(2026, 6, 30),
  );
}

/// The library behind the sheet. A created Compound is readable by id and never
/// reaches `compoundListProvider`, like the list the sheet read when it opened:
/// the sheet has to find it through the by-id read.
class _Harness {
  _Harness({
    required this.compounds,
    this.recentCompoundIds = const <String>[],
  }) {
    controller = _FakeProtocolDayController(this);
  }

  final List<CompoundRecord> compounds;
  final List<String> recentCompoundIds;
  final created = <CompoundRecord>[];
  late final _FakeProtocolDayController controller;

  /// When set, the by-id read answers only after this completes.
  Future<void>? byIdsGate;

  /// How many times the autoDispose by-id provider was disposed.
  int byIdsDisposals = 0;

  Stream<List<CompoundScheduleOptionRecord>> compoundsByIds(
    Set<String> ids,
  ) async* {
    final gate = byIdsGate;
    if (gate != null) {
      await gate;
    } else {
      // Never synchronous: a read that isn't held open dies before this answers.
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    yield <CompoundScheduleOptionRecord>[
      for (final compound in created)
        if (ids.contains(compound.id))
          CompoundScheduleOptionRecord(
            id: compound.id,
            name: compound.name,
            defaultUnit: compound.defaultUnit,
            defaultRoute: compound.defaultRoute,
          ),
    ];
  }
}

class _FakeProtocolDayController extends ProtocolDayController {
  _FakeProtocolDayController(this._harness);

  final _Harness _harness;
  final createdCompounds = <CompoundDraft>[];

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
  Future<CreateCompoundResult> createCompound(CompoundDraft draft) async {
    createdCompounds.add(draft);
    final id = 'created-${createdCompounds.length}';
    _harness.created.add(
      CompoundRecord(
        id: id,
        name: draft.name,
        defaultUnit: draft.defaultUnit,
        defaultRoute: draft.defaultRoute,
        updatedAt: DateTime.utc(2026, 6, 30),
      ),
    );
    return CreateCompoundResult(batchId: 'batch', compoundId: id);
  }
}

/// A lock whose state a test sets directly, the way the real controller moves
/// when the app backgrounds.
class _SwitchableLockController extends ProtocolsLockController {
  @override
  Future<ProtocolsLockState> build() async {
    return const ProtocolsLockState(
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

/// Keeps the guard off the real secure-storage plugin channel.
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

/// A page with one button that opens the picker, recording what it returns.
class _PickerHost extends StatelessWidget {
  _PickerHost({required this.selectedIds});

  final List<String> selectedIds;
  final results = <List<String>?>[];

  static const openKey = Key('test.pickerHost.open');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: openKey,
          onPressed: () async {
            results.add(
              await showCompoundPickerSheet(context, selectedIds: selectedIds),
            );
          },
          child: const Text('Open'),
        ),
      ),
    );
  }
}

Future<_PickerHost> _openPicker(
  WidgetTester tester, {
  required _Harness harness,
  List<String> selectedIds = const <String>[],
  ThemeData? theme,
  TextScaler? textScaler,
  ProtocolsLockController? lock,
  bool prefixed = false,
}) async {
  final host = _PickerHost(selectedIds: selectedIds);
  await tester.pumpWidget(
    ProviderScope(
      // A new scope per call, so a loop over themes starts from nothing.
      key: UniqueKey(),
      overrides: [
        protocolDayControllerProvider.overrideWith(() => harness.controller),
        compoundListProvider.overrideWith(
          (ref) => Stream<List<CompoundRecord>>.value(harness.compounds),
        ),
        recentCompoundIdsProvider.overrideWith(
          (ref) => Stream<List<String>>.value(harness.recentCompoundIds),
        ),
        compoundsByIdsProvider.overrideWith((ref, request) {
          ref.onDispose(() => harness.byIdsDisposals += 1);
          return harness.compoundsByIds(request.idSet);
        }),
        protocolsLockStoreProvider.overrideWith((ref) => _NoLockStore()),
        if (lock != null)
          protocolsLockControllerProvider.overrideWith(() => lock),
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
        home: host,
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(_PickerHost.openKey));
  await tester.pumpAndSettle();
  return host;
}
