import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/protocols/controllers/protocol_controller.dart';
import 'package:perennia/features/protocols/controllers/protocols_day_controller.dart';
import 'package:perennia/features/protocols/services/protocols_lock_store.dart';
import 'package:perennia/features/protocols/widgets/compound_list_screen.dart';
import 'package:perennia/features/protocols/widgets/protocols_day_view.dart';
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
      expect(find.byKey(CompoundListScreen.allSectionHeaderKey), findsOneWidget);
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
}

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
  Future<LogDoseResult> logDose(DoseSnapshotDraft draft) async {
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
  Future<void> setFavorite(String compoundId, {required bool isFavorite}) async {
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

Future<void> _pumpCompoundList(
  WidgetTester tester, {
  required _Harness harness,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
        // LogDoseSheet's OPTIONAL Protocol tag picker reads this;
        // no Protocols fixture here, so it renders empty (None-only).
        protocolOptionListProvider.overrideWith(
          (ref) => Stream<List<ProtocolOptionRecord>>.value(
            const <ProtocolOptionRecord>[],
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.light(),
        home: const CompoundListScreen(),
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
