import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/focus_color.dart';
import 'package:perennia/features/focus/widgets/focus_manager_screen.dart';
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

  late AppDatabase database;
  late TrainingRepositories repositories;
  late String climbingId;

  // Database work runs here, or under tester.runAsync, outside the widget
  // test's fake clock.
  setUp(() async {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(
      database,
      platformSeedSource: const _FocusSeedSource(),
    );
    await repositories.catalog.ensurePlatformLibrarySeeded();
    climbingId = await repositories.focuses.create('Climbing');
  });

  tearDown(() async {
    await database.close();
  });

  Future<String?> storedColor(WidgetTester tester, String id) async {
    return tester.runAsync<String?>(
      () async => (await (database.select(database.focuses)
                ..where((row) => row.id.equals(id)))
              .getSingle())
          .colorHex,
    );
  }

  Future<List<ActivityLogEntry>> focusEntries(WidgetTester tester) async {
    final entries = await tester.runAsync(repositories.activityLog.listEntries);
    return entries!
        .where((entry) => entry.entityTable == AppDatabase.focusesTable)
        .toList();
  }

  Future<void> openColorDialog(WidgetTester tester, String focusId) async {
    await tester.tap(find.byKey(FocusManagerScreen.menuButtonKey(focusId)));
    await _settle(tester);
    await tester.tap(find.byKey(FocusManagerScreen.colorMenuKey(focusId)));
    await _settle(tester);
  }

  testWidgets('recoloring a Focus stores the swatch and logs it (CUJ 8)',
      (tester) async {
    await _pumpManager(tester, repositories);

    await openColorDialog(tester, climbingId);

    expect(find.text('Color for Climbing'), findsOneWidget);
    for (final token in focusColorTokens) {
      final swatch = tester.widget<IconButton>(
        find.byKey(FocusManagerScreen.colorSwatchKey(token)),
      );
      // The current color is the default token's, shown selected.
      expect(
        swatch.onPressed == null,
        token == focusDefaultColorToken(climbingId),
        reason: token,
      );
    }
    expect(
      focusColorTokens.map(
        (token) => tester
            .widget<IconButton>(
              find.byKey(FocusManagerScreen.colorSwatchKey(token)),
            )
            .tooltip,
      ),
      <String>['Back', 'Cardio', 'Core', 'Shoulders', 'Arms', 'Legs', 'Chest'],
    );

    final pick =
        focusDefaultColorToken(climbingId) == 'legs' ? 'chest' : 'legs';
    await tester.tap(find.byKey(FocusManagerScreen.colorSwatchKey(pick)));
    await _settle(tester);

    expect(find.text('Color for Climbing'), findsNothing);
    final expectedHex = colorToHex(DesignTokens.category[pick]!);
    expect(await storedColor(tester, climbingId), expectedHex);
    expect(
      (await focusEntries(tester)).where(
        (entry) =>
            entry.entityId == climbingId &&
            entry.afterImage?['color_hex'] == expectedHex,
      ),
      hasLength(1),
    );

    // Reordering never changes a Focus's color.
    await tester.runAsync(() async {
      final order = (await repositories.focuses.listActive())
          .map((focus) => focus.id)
          .toList()
          .reversed
          .toList();
      await repositories.focuses.reorder(order);
    });
    expect(await storedColor(tester, climbingId), expectedHex);

    // The stored color is now the selected swatch.
    await _settle(tester);
    await openColorDialog(tester, climbingId);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(FocusManagerScreen.colorSwatchKey(pick)),
          )
          .onPressed,
      isNull,
    );
    await _unmount(tester);
  });

  testWidgets('Cancel closes the color dialog without a write', (tester) async {
    final entriesBefore = (await focusEntries(tester)).length;
    await _pumpManager(tester, repositories);

    await openColorDialog(tester, starterFocusWeightsId);
    await tester.tap(find.byKey(FocusManagerScreen.colorCancelButtonKey));
    await _settle(tester);

    expect(find.text('Color for Weights'), findsNothing);
    expect(await storedColor(tester, starterFocusWeightsId), isNull);
    expect(await focusEntries(tester), hasLength(entriesBefore));
    await _unmount(tester);
  });

  testWidgets('the color swatches are at least 48 dp', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpManager(tester, repositories);

    await openColorDialog(tester, starterFocusWeightsId);

    for (final token in focusColorTokens) {
      final size = tester.getSize(
        find.byKey(FocusManagerScreen.colorSwatchKey(token)),
      );
      expect(size.width, greaterThanOrEqualTo(48), reason: token);
      expect(size.height, greaterThanOrEqualTo(48), reason: token);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
    await _unmount(tester);
  });
}

Future<void> _pumpManager(
  WidgetTester tester,
  TrainingRepositories repositories,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FocusManagerScreen(),
      ),
    ),
  );
  await _settle(tester);
}

/// Closes the screen's database streams; drift schedules their cleanup on a
/// zero-length timer that must run before the test ends.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
}

/// Lets the database's real-async work (the seed wait, stream queries,
/// writes) finish, then settles the frames it caused.
Future<void> _settle(WidgetTester tester) async {
  for (var pass = 0; pass < 3; pass += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

class _FocusSeedSource implements PlatformExerciseSeedSource {
  const _FocusSeedSource();

  @override
  Future<PlatformExerciseSeed> load() async {
    return PlatformExerciseSeed(
      categories: const <SeedExerciseCategory>[],
      focuses: <SeedFocus>[
        SeedFocus(
          id: starterFocusWeightsId,
          name: 'Weights',
          sortOrder: 0,
          updatedAt: DateTime.utc(2026, 10, 24),
        ),
        SeedFocus(
          id: starterFocusEnduranceId,
          name: 'Endurance',
          sortOrder: 1,
          updatedAt: DateTime.utc(2026, 10, 24),
        ),
      ],
      exercises: const <SeedExercise>[],
    );
  }
}
