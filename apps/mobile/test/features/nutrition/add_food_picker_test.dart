import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/local/food_reference_database.dart';
import 'package:perennia/data/open_food_facts/open_food_facts_client.dart';
import 'package:perennia/data/repositories/open_food_facts_repository.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/features/nutrition/repositories/add_food_repository.dart';
import 'package:perennia/features/nutrition/widgets/add_food_picker.dart';
import 'package:perennia/features/nutrition/widgets/barcode_scanner.dart';
import 'package:perennia/features/nutrition/widgets/log_portion_screen.dart';
import 'package:perennia/features/nutrition/widgets/nutrition_attribution.dart';
import 'package:perennia/features/nutrition/widgets/quick_entry_dialog.dart';
import 'package:perennia/features/settings/repositories/settings_repository.dart';
import 'package:perennia/theme/theme.dart';

import '../../data/open_food_facts_fixtures.dart';
import 'add_food_repository_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warnAboutMultipleDatabases =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  testWidgets('searches and scopes picker results with Food Source chips',
      (tester) async {
    final selected = <FoodPickerItem>[];

    await _pumpPicker(
      tester,
      repository: _StubAddFoodRepository(),
      onFoodSelected: selected.add,
    );
    await _pumpUntilFound(tester, find.text('Chicken breast'));

    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      'chick',
    );
    await _pumpSearchDebounce(tester);

    expect(find.text('Chicken breast'), findsOneWidget);
    expect(find.text('Greek yogurt'), findsNothing);

    await tester.tap(
      find.byKey(AddFoodPicker.filterChipKey(AddFoodPickerFilter.user)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Meal prep chicken'), findsOneWidget);
    expect(find.text('Chicken breast'), findsNothing);

    await tester.tap(
      find.byKey(AddFoodPicker.filterChipKey(AddFoodPickerFilter.usda)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chicken breast'), findsOneWidget);
    expect(find.text('Chickpeas, boiled'), findsOneWidget);
    expect(
      find.byKey(
          AddFoodPicker.filterChipKey(AddFoodPickerFilter.openFoodFacts)),
      findsOneWidget,
    );
    expect(find.byKey(AddFoodPicker.scanBarcodeButtonKey), findsOneWidget);

    await tester.tap(
      find.byKey(
        AddFoodPicker.resultKey(
          AddFoodPickerFilter.usda,
          'usda-chickpeas',
        ),
      ),
    );

    expect(selected.single.id, 'usda-chickpeas');
    expect(selected.single.foodSource, FoodSource.usda);
  });

  testWidgets('debounces typed food search before querying the repository',
      (tester) async {
    final repository = _TrackingAddFoodRepository();

    await _pumpPicker(
      tester,
      repository: repository,
    );
    await _pumpUntilFound(tester, find.text('Chicken breast'));
    repository.calls.clear();

    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      'c',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      'ch',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      'chi',
    );
    await tester.pump(AddFoodPicker.searchDebounceDuration ~/ 2);

    expect(repository.calls, isEmpty);

    await _pumpSearchDebounce(tester);

    expect(
      repository.calls,
      <_SearchCall>[
        const _SearchCall(AddFoodPickerFilter.recent, 'chi'),
      ],
    );
  });

  testWidgets('submitting food search applies before the debounce elapses',
      (tester) async {
    final repository = _TrackingAddFoodRepository();

    await _pumpPicker(
      tester,
      repository: repository,
    );
    await _pumpUntilFound(tester, find.text('Chicken breast'));
    repository.calls.clear();

    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      'yog',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 1));

    expect(
      repository.calls,
      <_SearchCall>[
        const _SearchCall(AddFoodPickerFilter.recent, 'yog'),
      ],
    );

    await _pumpSearchDebounce(tester);

    expect(
      repository.calls,
      <_SearchCall>[
        const _SearchCall(AddFoodPickerFilter.recent, 'yog'),
      ],
    );
    expect(find.text('Greek yogurt'), findsOneWidget);
    expect(find.text('Chicken breast'), findsNothing);
  });

  testWidgets('ignores stale food search results after a newer query wins',
      (tester) async {
    final repository = _DeferredAddFoodRepository();

    await _pumpPicker(
      tester,
      repository: repository,
    );
    await _pumpUntilFound(tester, find.text('Chicken breast'));

    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      'slow',
    );
    await _pumpSearchDebounce(tester);
    expect(
      repository.calls,
      contains(const _SearchCall(AddFoodPickerFilter.recent, 'slow')),
    );

    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      'fast',
    );
    await _pumpSearchDebounce(tester);
    repository.complete(
      'fast',
      <FoodPickerItem>[_recent[1]],
    );
    await tester.pumpAndSettle();

    expect(find.text('Greek yogurt'), findsOneWidget);
    expect(find.text('Chicken breast'), findsNothing);

    repository.complete(
      'slow',
      <FoodPickerItem>[_recent[0]],
    );
    await tester.pumpAndSettle();

    expect(find.text('Greek yogurt'), findsOneWidget);
    expect(find.text('Chicken breast'), findsNothing);
  });

  testWidgets('ignores stale food search results after the filter changes',
      (tester) async {
    final repository = _DeferredAddFoodRepository();

    await _pumpPicker(
      tester,
      repository: repository,
    );
    await _pumpUntilFound(tester, find.text('Chicken breast'));

    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      'slow',
    );
    await _pumpSearchDebounce(tester);
    expect(
      repository.calls,
      contains(const _SearchCall(AddFoodPickerFilter.recent, 'slow')),
    );

    await tester.tap(
      find.byKey(AddFoodPicker.filterChipKey(AddFoodPickerFilter.usda)),
    );
    await tester.pump();
    expect(
      repository.calls,
      contains(const _SearchCall(AddFoodPickerFilter.usda, 'slow')),
    );

    repository.complete(
      'slow',
      <FoodPickerItem>[_usda[1]],
      filter: AddFoodPickerFilter.usda,
    );
    await tester.pumpAndSettle();

    expect(find.text('Chickpeas, boiled'), findsOneWidget);
    expect(find.text('Greek yogurt'), findsNothing);

    repository.complete(
      'slow',
      <FoodPickerItem>[_recent[1]],
    );
    await tester.pumpAndSettle();

    expect(find.text('Chickpeas, boiled'), findsOneWidget);
    expect(find.text('Greek yogurt'), findsNothing);
  });

  testWidgets('ignores stale food search results after a barcode lookup',
      (tester) async {
    final repository = _DeferredAddFoodRepository();
    final selected = <FoodPickerItem>[];

    await _pumpPicker(
      tester,
      repository: repository,
      barcodeScanner: const _FakeBarcodeScanner('3017620422003'),
      onFoodSelected: selected.add,
    );
    await _pumpUntilFound(tester, find.text('Chicken breast'));

    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      'slow',
    );
    await _pumpSearchDebounce(tester);
    expect(
      repository.calls,
      contains(const _SearchCall(AddFoodPickerFilter.recent, 'slow')),
    );

    await tester.tap(find.byKey(AddFoodPicker.scanBarcodeButtonKey));
    await tester.pump();
    expect(
      repository.calls,
      contains(
        const _SearchCall(
          AddFoodPickerFilter.openFoodFacts,
          '3017620422003',
        ),
      ),
    );

    repository.complete(
      '3017620422003',
      <FoodPickerItem>[_openFoodFacts[0]],
      filter: AddFoodPickerFilter.openFoodFacts,
    );
    await tester.pumpAndSettle();

    expect(selected.single.id, '3017620422003');
    expect(find.text('Greek yogurt'), findsNothing);

    repository.complete(
      'slow',
      <FoodPickerItem>[_recent[1]],
    );
    await tester.pumpAndSettle();

    expect(selected, hasLength(1));
    expect(find.text('Greek yogurt'), findsNothing);
  });

  testWidgets('ignores stale barcode results after a newer query wins',
      (tester) async {
    final repository = _DeferredAddFoodRepository();
    final selected = <FoodPickerItem>[];

    await _pumpPicker(
      tester,
      repository: repository,
      barcodeScanner: const _FakeBarcodeScanner('3017620422003'),
      onFoodSelected: selected.add,
    );
    await _pumpUntilFound(tester, find.text('Chicken breast'));

    await tester.tap(find.byKey(AddFoodPicker.scanBarcodeButtonKey));
    await tester.pump();
    expect(
      repository.calls,
      contains(
        const _SearchCall(
          AddFoodPickerFilter.openFoodFacts,
          '3017620422003',
        ),
      ),
    );

    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      'fast',
    );
    await _pumpSearchDebounce(tester);
    repository.complete(
      'fast',
      <FoodPickerItem>[_recent[1]],
    );
    await tester.pumpAndSettle();

    expect(find.text('Greek yogurt'), findsOneWidget);
    expect(find.text('Chicken breast'), findsNothing);

    repository.complete(
      '3017620422003',
      <FoodPickerItem>[_openFoodFacts[0]],
      filter: AddFoodPickerFilter.openFoodFacts,
    );
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
    expect(find.text('Greek yogurt'), findsOneWidget);
    expect(find.text('Chicken breast'), findsNothing);
  });

  testWidgets('Open Food Facts search shows attribution and source badge',
      (tester) async {
    await _pumpPicker(
      tester,
      repository: _StubAddFoodRepository(),
    );
    await _pumpUntilFound(tester, find.text('Chicken breast'));

    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      'hazelnut',
    );
    await tester.tap(
      find.byKey(
        AddFoodPicker.filterChipKey(AddFoodPickerFilter.openFoodFacts),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(NutritionAttributionKeys.openFoodFactsNotice),
      findsOneWidget,
    );
    expect(
      find.byKey(NutritionAttributionKeys.openFoodFactsSourceLink),
      findsOneWidget,
    );
    expect(
      find.byKey(NutritionAttributionKeys.openFoodFactsOdblLink),
      findsOneWidget,
    );
    expect(find.text('Hazelnut cocoa spread'), findsOneWidget);
    expect(
      find.byKey(
        NutritionAttributionKeys.foodSourceBadge(FoodSource.openFoodFacts),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('ODbL'), findsAtLeastNWidgets(1));
  });

  testWidgets('Quick add creates a Quick Entry directly into the current Meal',
      (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(database);
    final mealId = await repositories.nutrition.createMeal(
      MealDraft(
        mealType: 'Snack',
        startedAt: DateTime.utc(2026, 6, 26, 15),
        timezone: 'Australia/Brisbane',
        localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
      ),
    );
    final meal = (await repositories.nutrition.getMealById(mealId))!;

    await _pumpPicker(
      tester,
      meal: meal,
      repositories: repositories,
      repository: const _EmptyAddFoodRepository(),
    );

    await tester.tap(find.byKey(AddFoodPicker.quickAddButtonKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(QuickEntryDialog.nameFieldKey),
      'Cafe latte',
    );
    await tester.enterText(
      find.byKey(QuickEntryDialog.energyFieldKey),
      '140',
    );
    await tester.tap(find.byKey(QuickEntryDialog.saveButtonKey));
    await tester.pumpAndSettle();

    final entries = await repositories.nutrition.listActiveEntriesForMeal(
      mealId,
    );

    expect(entries, hasLength(1));
    expect(entries.single.kind, FoodEntryKind.quickEntry);
    expect(entries.single.name, 'Cafe latte');
    expect(entries.single.foodId, isNull);
    expect(entries.single.portion, isNull);
    expect(entries.single.foodSource, isNull);
    expect(entries.single.nutrients[NutrientId.energy].value, 140);
  });

  testWidgets(
      'barcode scan resolves Open Food Facts and saves a local Food Entry',
      (tester) async {
    final requests = <http.Request>[];
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final referenceDatabase = FoodReferenceDatabase.memory();
    addTearDown(referenceDatabase.close);
    final repositories = TrainingRepositories(database);
    final openFoodFacts = DriftOpenFoodFactsRepository.forTesting(
      database: referenceDatabase,
      asset: const ThrowingBundleAsset(), // never installed here
      client: OpenFoodFactsClient(
        baseUrl: Uri.parse('https://off.test/'),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, Object?>{
              'code': '3017620422003',
              'status': 'success',
              'result': <String, Object?>{'id': 'product_found'},
              'product': <String, Object?>{
                'code': '3017620422003',
                'product_name': 'Hazelnut cocoa spread',
                'brands': 'Nutella',
                'last_modified_t': 1760000000,
                'serving_quantity': 15,
                'serving_quantity_unit': 'g',
                'product_quantity': 400,
                'product_quantity_unit': 'g',
                'nutriments': <String, Object?>{
                  'energy-kcal_100g': 539,
                  'proteins_100g': 6.3,
                  'carbohydrates_100g': 56.3,
                  'fat_100g': 30.9,
                },
              },
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );
    final mealId = await repositories.nutrition.createMeal(
      MealDraft(
        mealType: 'Snack',
        startedAt: DateTime.utc(2026, 6, 26, 15),
        timezone: 'Australia/Brisbane',
        localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
      ),
    );
    final meal = (await repositories.nutrition.getMealById(mealId))!;

    await _pumpBarcodeHarness(
      tester,
      meal: meal,
      repositories: repositories,
      openFoodFacts: openFoodFacts,
      barcodeScanner: const _FakeBarcodeScanner('3017620422003'),
    );
    await _pumpUntilFound(tester, find.text('No foods found'));

    await tester.tap(find.byKey(AddFoodPicker.scanBarcodeButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('Hazelnut cocoa spread'), findsOneWidget);
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.serving)),
      findsOneWidget,
    );
    expect(
      find.byKey(LogPortionScreen.unitChipKey(PortionUnit.package)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(LogPortionScreen.saveButtonKey));
    await tester.pumpAndSettle();

    final entries = await repositories.nutrition.listActiveEntriesForMeal(
      mealId,
    );

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/v3.6/product/3017620422003.json');
    // The live hit is kept on the device, so the next scan sends nothing.
    expect(
      (await referenceDatabase.productsByCodes(<String>['3017620422003']))
          .single
          .origin,
      originOnline,
    );
    expect(entries, hasLength(1));
    expect(entries.single.kind, FoodEntryKind.food);
    expect(entries.single.name, 'Hazelnut cocoa spread');
    expect(entries.single.foodId, '3017620422003');
    expect(entries.single.foodSource, FoodSource.openFoodFacts);
    expect(entries.single.nutrients[NutrientId.energy].value, 539);
    expect(entries.single.nutrients[NutrientId.protein].value, 6.3);
    expect(entries.single.isLiquid, isFalse);
    expect(entries.single.servingLabel, 'serving');
    expect(entries.single.servingSize, 15);
    expect(entries.single.packageSize, 400);
    expect(entries.single.portion?.value, 100);
    expect(entries.single.portion?.entered, '100');
    expect(entries.single.portion?.unit, PortionUnit.gram);
    expect(await database.select(database.foods).get(), isEmpty);
    expect(await database.select(database.metrics).get(), isEmpty);
    expect(await database.select(database.metricReadings).get(), isEmpty);
  });

  testWidgets(
      'offline barcode miss keeps Add Food open with Quick add fallback',
      (tester) async {
    await _pumpPicker(
      tester,
      repository: const _OfflineOpenFoodFactsRepository(),
      barcodeScanner: const _FakeBarcodeScanner('3017620422003'),
    );
    await _pumpUntilFound(tester, find.text('No foods found'));

    await tester.tap(find.byKey(AddFoodPicker.scanBarcodeButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(AddFoodPicker.barcodeStatusKey), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(AddFoodPicker.barcodeStatusLineKey)).data,
      "You're offline. Showing foods on this device.",
    );
    expect(find.textContaining('needs network'), findsNothing);
    expect(
        find.textContaining('USDA foods stay fully offline'), findsOneWidget);
    expect(find.byKey(AddFoodPicker.lookupUsdaButtonKey), findsOneWidget);
    expect(find.byKey(AddFoodPicker.barcodeQuickAddButtonKey), findsOneWidget);

    await tester.tap(find.byKey(AddFoodPicker.barcodeQuickAddButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(QuickEntryDialog.nameFieldKey), findsOneWidget);
  });

  testWidgets('an offline online search keeps the device matches on screen',
      (tester) async {
    final repository = _OnlineAddFoodRepository(
      online: (status: OnlineSearchStatus.offline, items: <FoodPickerItem>[]),
    );
    await _pumpOpenFoodFactsFilter(tester, repository: repository);

    await tester.enterText(find.byKey(AddFoodPicker.searchFieldKey), 'hazel');
    await _pumpSearchDebounce(tester);
    await tester.tap(find.byKey(AddFoodPicker.onlineSearchRowKey));
    await tester.pumpAndSettle();

    expect(repository.onlineQueries, <String>['hazel']);
    expect(_onlineLine(tester), "You're offline. Showing foods on this device.");
    expect(find.text('Hazelnut cocoa spread'), findsOneWidget);
    expect(find.textContaining('needs network'), findsNothing);
  });

  testWidgets('typing searches the device and sends nothing online',
      (tester) async {
    final repository = _OnlineAddFoodRepository();
    await _pumpOpenFoodFactsFilter(tester, repository: repository);

    await tester.enterText(find.byKey(AddFoodPicker.searchFieldKey), 'haz');
    await _pumpSearchDebounce(tester);
    await tester.enterText(find.byKey(AddFoodPicker.searchFieldKey), 'hazel');
    await _pumpSearchDebounce(tester);

    expect(repository.onlineQueries, isEmpty);
    expect(find.text('Hazelnut cocoa spread'), findsOneWidget);
    expect(
      find.text('Search Open Food Facts for "hazel"'),
      findsOneWidget,
    );
  });

  testWidgets('the online search row and the search action each send one',
      (tester) async {
    final repository = _OnlineAddFoodRepository();
    await _pumpOpenFoodFactsFilter(tester, repository: repository);

    await tester.enterText(find.byKey(AddFoodPicker.searchFieldKey), 'hazel');
    await _pumpSearchDebounce(tester);
    await tester.tap(find.byKey(AddFoodPicker.onlineSearchRowKey));
    await tester.pumpAndSettle();
    expect(repository.onlineQueries, <String>['hazel']);

    await tester.enterText(find.byKey(AddFoodPicker.searchFieldKey), 'cocoa');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(repository.onlineQueries, <String>['hazel', 'cocoa']);
  });

  testWidgets(
      'live results join the device matches without duplicate barcodes',
      (tester) async {
    final newerStored = _offItem(
      '3017620422003',
      'Hazelnut cocoa spread (new recipe)',
      changedAt: DateTime.utc(2026, 10, 20),
      live: true,
    );
    final repository = _OnlineAddFoodRepository(
      local: <FoodPickerItem>[
        _offItem(
          '3017620422003',
          'Hazelnut cocoa spread',
          changedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
      online: (
        status: OnlineSearchStatus.ok,
        items: <FoodPickerItem>[
          newerStored,
          _offItem('8000500310427', 'Hazelnut wafers', live: true),
        ],
      ),
    );
    await _pumpOpenFoodFactsFilter(tester, repository: repository);

    await tester.enterText(find.byKey(AddFoodPicker.searchFieldKey), 'hazel');
    await _pumpSearchDebounce(tester);
    await tester.tap(find.byKey(AddFoodPicker.onlineSearchRowKey));
    await tester.pumpAndSettle();

    // Goal 4: the newer live copy takes the stored match's place.
    expect(find.text('Hazelnut cocoa spread (new recipe)'), findsOneWidget);
    expect(find.text('Hazelnut cocoa spread'), findsNothing);
    final group = find.byKey(AddFoodPicker.onlineGroupKey);
    expect(group, findsOneWidget);
    expect(
      find.descendant(of: group, matching: find.text('Hazelnut wafers')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: group,
        matching: find.text('Hazelnut cocoa spread (new recipe)'),
      ),
      findsNothing,
    );
  });

  testWidgets('the bundle line shows while installing and after a failure',
      (tester) async {
    for (final (status, line) in <(BundleStatus, String?)>[
      (BundleStatus.unknown, null),
      (BundleStatus.installing, 'Preparing the offline food list.'),
      (BundleStatus.ready, null),
      (
        BundleStatus.failed,
        'The offline food list could not be prepared. It will try again next '
            'time the app opens.',
      ),
    ]) {
      await _pumpOpenFoodFactsFilter(
        tester,
        repository: _OnlineAddFoodRepository(),
        bundleStatus: status,
      );
      final finder = find.byKey(AddFoodPicker.bundleStatusLineKey);
      if (line == null) {
        expect(finder, findsNothing, reason: status.name);
      } else {
        expect(tester.widget<Text>(find.descendant(
          of: finder,
          matching: find.byType(Text),
        )).data, line, reason: status.name);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('the online slot shows one state, in precedence order',
      (tester) async {
    for (final (enabled, status, line) in <(bool, OnlineSearchStatus, String?)>[
      (
        false,
        OnlineSearchStatus.ok,
        'Online lookups are off. Turn them on in Settings > Food data.',
      ),
      (true, OnlineSearchStatus.offline,
          "You're offline. Showing foods on this device."),
      (true, OnlineSearchStatus.unavailable,
          'Open Food Facts is unavailable. Try again in a minute.'),
      (true, OnlineSearchStatus.noResults, 'No matches on Open Food Facts.'),
      (true, OnlineSearchStatus.ok, null),
    ]) {
      final repository = _OnlineAddFoodRepository(
        enabled: enabled,
        online: (status: status, items: <FoodPickerItem>[]),
      );
      await _pumpOpenFoodFactsFilter(tester, repository: repository);
      await tester.enterText(find.byKey(AddFoodPicker.searchFieldKey), 'hazel');
      await _pumpSearchDebounce(tester);
      if (enabled) {
        await tester.tap(find.byKey(AddFoodPicker.onlineSearchRowKey));
        await tester.pumpAndSettle();
      }

      final reason = '$enabled ${status.name}';
      if (line == null) {
        expect(find.byKey(AddFoodPicker.onlineStatusLineKey), findsNothing,
            reason: reason);
        expect(find.byKey(AddFoodPicker.onlineSearchRowKey), findsOneWidget,
            reason: reason);
      } else {
        expect(_onlineLine(tester), line, reason: reason);
        expect(find.byKey(AddFoodPicker.onlineSearchRowKey), findsNothing,
            reason: reason);
      }
      // Changing the query clears the last live request's state.
      if (enabled && line != null) {
        await tester.enterText(
            find.byKey(AddFoodPicker.searchFieldKey), 'hazelnut');
        await tester.pump();
        expect(find.byKey(AddFoodPicker.onlineSearchRowKey), findsOneWidget,
            reason: '$reason cleared');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('the device matches stay visible while a live search runs',
      (tester) async {
    final pending = Completer<
        ({OnlineSearchStatus status, List<FoodPickerItem> items})>();
    final repository = _OnlineAddFoodRepository(pendingOnline: pending);
    await _pumpOpenFoodFactsFilter(tester, repository: repository);

    await tester.enterText(find.byKey(AddFoodPicker.searchFieldKey), 'hazel');
    await _pumpSearchDebounce(tester);
    await tester.tap(find.byKey(AddFoodPicker.onlineSearchRowKey));
    await tester.pump();

    expect(find.text('Hazelnut cocoa spread'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AddFoodPicker.onlineSearchRowKey),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    pending.complete(
      (status: OnlineSearchStatus.noResults, items: <FoodPickerItem>[]),
    );
    await tester.pumpAndSettle();
    expect(_onlineLine(tester), 'No matches on Open Food Facts.');
  });

  testWidgets('an empty query asks for a product or brand name',
      (tester) async {
    await _pumpOpenFoodFactsFilter(
      tester,
      repository: _OnlineAddFoodRepository(),
    );

    expect(find.byKey(AddFoodPicker.emptyQueryLineKey), findsOneWidget);
    expect(find.text('Type a product or brand name.'), findsOneWidget);
    expect(find.byKey(AddFoodPicker.onlineSearchRowKey), findsNothing);

    await tester.enterText(find.byKey(AddFoodPicker.searchFieldKey), '*:-');
    await _pumpSearchDebounce(tester);
    expect(find.byKey(AddFoodPicker.emptyQueryLineKey), findsOneWidget);
  });

  testWidgets('a submitted barcode opens the product', (tester) async {
    final selected = <FoodPickerItem>[];
    final repository = _OnlineAddFoodRepository(
      barcode: (
        status: BarcodeLookupOutcome.found,
        item: _offItem('3017620422003', 'Hazelnut cocoa spread'),
      ),
    );
    await _pumpOpenFoodFactsFilter(
      tester,
      repository: repository,
      onFoodSelected: selected.add,
    );

    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      '3017620422003',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(repository.barcodes, <String>['3017620422003']);
    expect(repository.onlineQueries, isEmpty);
    expect(selected.single.id, '3017620422003');
  });

  testWidgets('a submitted barcode that is not found shows the miss line',
      (tester) async {
    final repository = _OnlineAddFoodRepository(
      barcode: (status: BarcodeLookupOutcome.disabled, item: null),
    );
    await _pumpOpenFoodFactsFilter(tester, repository: repository);

    await tester.enterText(
      find.byKey(AddFoodPicker.searchFieldKey),
      '3017620422003',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.byKey(AddFoodPicker.barcodeStatusKey), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(AddFoodPicker.barcodeStatusLineKey)).data,
      'Online lookups are off. Turn them on in Settings > Food data.',
    );
  });

  testWidgets('opening a live item keeps it on the device', (tester) async {
    final selected = <FoodPickerItem>[];
    final repository = _OnlineAddFoodRepository(
      online: (
        status: OnlineSearchStatus.ok,
        items: <FoodPickerItem>[
          _offItem('8000500310427', 'Hazelnut wafers', live: true),
        ],
      ),
    );
    await _pumpOpenFoodFactsFilter(
      tester,
      repository: repository,
      onFoodSelected: selected.add,
    );

    await tester.enterText(find.byKey(AddFoodPicker.searchFieldKey), 'hazel');
    await _pumpSearchDebounce(tester);
    await tester.tap(find.byKey(AddFoodPicker.onlineSearchRowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hazelnut wafers'));
    await tester.pumpAndSettle();

    expect(repository.kept.single.id, '8000500310427');
    expect(selected.single.id, '8000500310427');

    // A stored item is not kept again.
    await tester.tap(find.text('Hazelnut cocoa spread'));
    await tester.pumpAndSettle();
    expect(repository.kept, hasLength(1));
  });

  testWidgets(
      'the Open Food Facts controls meet accessibility guidelines in both '
      'themes', (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();
      final repository = _OnlineAddFoodRepository(
        online: (
          status: OnlineSearchStatus.ok,
          items: <FoodPickerItem>[
            _offItem('8000500310427', 'Hazelnut wafers', live: true),
          ],
        ),
      );
      await _pumpOpenFoodFactsFilter(
        tester,
        repository: repository,
        theme: theme,
        bundleStatus: BundleStatus.installing,
      );
      await tester.enterText(find.byKey(AddFoodPicker.searchFieldKey), 'hazel');
      await _pumpSearchDebounce(tester);
      await tester.tap(find.byKey(AddFoodPicker.onlineSearchRowKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AddFoodPicker.onlineGroupKey), findsOneWidget);
      expect(find.byKey(AddFoodPicker.onlineSearchRowKey), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Add Food picker meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await _pumpPicker(
        tester,
        theme: theme,
        repository: _StubAddFoodRepository(),
      );
      await _pumpUntilFound(tester, find.text('Chicken breast'));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'barcode fallback banner meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final semantics = tester.ensureSemantics();

      await _pumpPicker(
        tester,
        theme: theme,
        repository: const _OfflineOpenFoodFactsRepository(),
        barcodeScanner: const _FakeBarcodeScanner('3017620422003'),
      );
      await _pumpUntilFound(tester, find.text('No foods found'));
      await tester.tap(find.byKey(AddFoodPicker.scanBarcodeButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AddFoodPicker.barcodeStatusKey), findsOneWidget);
      expect(find.byKey(AddFoodPicker.barcodeStatusLineKey), findsOneWidget);
      expect(
        find.byKey(AddFoodPicker.barcodeQuickAddButtonKey),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  ThemeData? theme,
  MealRecord? meal,
  TrainingRepositories? repositories,
  required AddFoodRepository repository,
  BarcodeScanner? barcodeScanner,
  ValueChanged<FoodPickerItem>? onFoodSelected,
  BundleStatus bundleStatus = BundleStatus.ready,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repositories != null)
          trainingRepositoriesProvider.overrideWith((ref) => repositories),
        addFoodRepositoryProvider.overrideWith((ref) => repository),
        openFoodFactsRepositoryProvider.overrideWith(
          (ref) => const StubOpenFoodFactsRepository(),
        ),
        settingsRepositoryProvider.overrideWith(
          (ref) => InMemorySettingsRepository(),
        ),
        bundleStatusProvider.overrideWith(
          (ref) => Stream<BundleStatus>.value(bundleStatus),
        ),
        if (barcodeScanner != null)
          barcodeScannerProvider.overrideWith((ref) => barcodeScanner),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: Scaffold(
          body: SafeArea(
            child: AddFoodPicker(
              meal: meal ?? _meal(),
              onFoodSelected: onFoodSelected,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpBarcodeHarness(
  WidgetTester tester, {
  required MealRecord meal,
  required TrainingRepositories repositories,
  required OpenFoodFactsRepository openFoodFacts,
  required BarcodeScanner barcodeScanner,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        openFoodFactsRepositoryProvider.overrideWith((ref) => openFoodFacts),
        settingsRepositoryProvider.overrideWith(
          (ref) => InMemorySettingsRepository(),
        ),
        addFoodRepositoryProvider.overrideWith(
          (ref) => RepositoryAddFoodRepository(
            repositories,
            openFoodFacts: openFoodFacts,
          ),
        ),
        barcodeScannerProvider.overrideWith((ref) => barcodeScanner),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SafeArea(
            child: _BarcodeAddFoodHarness(
              meal: meal,
              repositories: repositories,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The picker with the Open Food Facts filter selected.
Future<void> _pumpOpenFoodFactsFilter(
  WidgetTester tester, {
  required AddFoodRepository repository,
  ThemeData? theme,
  BundleStatus bundleStatus = BundleStatus.ready,
  ValueChanged<FoodPickerItem>? onFoodSelected,
}) async {
  await _pumpPicker(
    tester,
    theme: theme,
    repository: repository,
    bundleStatus: bundleStatus,
    onFoodSelected: onFoodSelected,
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(AddFoodPicker.filterChipKey(AddFoodPickerFilter.openFoodFacts)),
  );
  await tester.pumpAndSettle();
}

String? _onlineLine(WidgetTester tester) {
  return tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(AddFoodPicker.onlineStatusLineKey),
          matching: find.byType(Text),
        ),
      )
      .data;
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 50,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Could not find $finder.');
}

Future<void> _pumpSearchDebounce(WidgetTester tester) async {
  await tester.pump(AddFoodPicker.searchDebounceDuration);
  await tester.pumpAndSettle();
}

class _BarcodeAddFoodHarness extends StatefulWidget {
  const _BarcodeAddFoodHarness({
    required this.meal,
    required this.repositories,
  });

  final MealRecord meal;
  final TrainingRepositories repositories;

  @override
  State<_BarcodeAddFoodHarness> createState() => _BarcodeAddFoodHarnessState();
}

class _BarcodeAddFoodHarnessState extends State<_BarcodeAddFoodHarness> {
  FoodPickerItem? _food;

  @override
  Widget build(BuildContext context) {
    final food = _food;
    if (food == null) {
      return AddFoodPicker(
        meal: widget.meal,
        onFoodSelected: (food) {
          setState(() {
            _food = food;
          });
        },
      );
    }
    return LogPortionScreen(
      meal: widget.meal,
      food: food,
      onSave: (draft) {
        return widget.repositories.nutrition.logFoodEntrySnapshot(
          entry: draft,
        );
      },
    );
  }
}

class _StubAddFoodRepository with NoOnlineLookups implements AddFoodRepository {
  _StubAddFoodRepository();

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    int limit = 50,
  }) async {
    final candidates = switch (filter) {
      AddFoodPickerFilter.recent => _recent,
      AddFoodPickerFilter.user => _user,
      AddFoodPickerFilter.usda => _usda,
      AddFoodPickerFilter.openFoodFacts => _openFoodFacts,
    };
    return candidates
        .where((item) => _foodNameMatchesQuery(item.name, query))
        .take(limit)
        .toList(growable: false);
  }
}

class _TrackingAddFoodRepository with NoOnlineLookups implements AddFoodRepository {
  final calls = <_SearchCall>[];

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    int limit = 50,
  }) async {
    calls.add(_SearchCall(filter, query));
    final candidates = switch (filter) {
      AddFoodPickerFilter.recent => _recent,
      AddFoodPickerFilter.user => _user,
      AddFoodPickerFilter.usda => _usda,
      AddFoodPickerFilter.openFoodFacts => _openFoodFacts,
    };
    return candidates
        .where((item) => _foodNameMatchesQuery(item.name, query))
        .take(limit)
        .toList(growable: false);
  }
}

class _DeferredAddFoodRepository with NoOnlineLookups implements AddFoodRepository {
  final calls = <_SearchCall>[];
  final _pending = <_SearchCall, Completer<List<FoodPickerItem>>>{};

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    int limit = 50,
  }) {
    final call = _SearchCall(filter, query);
    calls.add(call);
    if (query.isEmpty) {
      return Future<List<FoodPickerItem>>.value(_recent);
    }
    final completer = Completer<List<FoodPickerItem>>();
    _pending[call] = completer;
    return completer.future;
  }

  /// A scan is deferred like a search, recorded as an Open Food Facts call.
  @override
  Future<({BarcodeLookupOutcome status, FoodPickerItem? item})> lookupBarcode(
    String raw,
  ) async {
    final call = _SearchCall(AddFoodPickerFilter.openFoodFacts, raw);
    calls.add(call);
    final completer = Completer<List<FoodPickerItem>>();
    _pending[call] = completer;
    final results = await completer.future;
    return results.isEmpty
        ? (status: BarcodeLookupOutcome.notFound, item: null)
        : (status: BarcodeLookupOutcome.found, item: results.first);
  }

  void complete(
    String query,
    List<FoodPickerItem> results, {
    AddFoodPickerFilter filter = AddFoodPickerFilter.recent,
  }) {
    final completer = _pending.remove(_SearchCall(filter, query));
    if (completer == null) {
      fail('No pending ${filter.name} search for $query.');
    }
    completer.complete(results);
  }
}

class _SearchCall {
  const _SearchCall(this.filter, this.query);

  final AddFoodPickerFilter filter;
  final String query;

  @override
  bool operator ==(Object other) {
    return other is _SearchCall &&
        other.filter == filter &&
        other.query == query;
  }

  @override
  int get hashCode => Object.hash(filter, query);

  @override
  String toString() => 'search(${filter.name}, $query)';
}

class _EmptyAddFoodRepository with NoOnlineLookups implements AddFoodRepository {
  const _EmptyAddFoodRepository();

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    int limit = 50,
  }) async {
    return const <FoodPickerItem>[];
  }
}

class _OfflineOpenFoodFactsRepository
    with NoOnlineLookups
    implements AddFoodRepository {
  const _OfflineOpenFoodFactsRepository();

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    int limit = 50,
  }) async {
    return const <FoodPickerItem>[];
  }

  @override
  Future<({BarcodeLookupOutcome status, FoodPickerItem? item})> lookupBarcode(
    String raw,
  ) async {
    return (status: BarcodeLookupOutcome.offline, item: null);
  }
}


/// The Open Food Facts filter with a scripted live search and barcode lookup,
/// recording every online call.
class _OnlineAddFoodRepository implements AddFoodRepository {
  _OnlineAddFoodRepository({
    List<FoodPickerItem>? local,
    this.enabled = true,
    this.online = (
      status: OnlineSearchStatus.noResults,
      items: const <FoodPickerItem>[],
    ),
    this.pendingOnline,
    this.barcode = (status: BarcodeLookupOutcome.notFound, item: null),
  }) : local = local ?? _openFoodFacts;

  final List<FoodPickerItem> local;
  final bool enabled;
  final ({OnlineSearchStatus status, List<FoodPickerItem> items}) online;
  final Completer<({OnlineSearchStatus status, List<FoodPickerItem> items})>?
      pendingOnline;
  final ({BarcodeLookupOutcome status, FoodPickerItem? item}) barcode;

  final onlineQueries = <String>[];
  final barcodes = <String>[];
  final kept = <FoodPickerItem>[];

  @override
  Future<List<FoodPickerItem>> search({
    required AddFoodPickerFilter filter,
    required String query,
    int limit = 50,
  }) async {
    if (filter != AddFoodPickerFilter.openFoodFacts) {
      return const <FoodPickerItem>[];
    }
    return local
        .where((item) => _foodNameMatchesQuery(item.name, query))
        .toList(growable: false);
  }

  @override
  Future<bool> onlineLookupsEnabled() async => enabled;

  @override
  Future<({OnlineSearchStatus status, List<FoodPickerItem> items})>
      searchOnline(String query) {
    onlineQueries.add(query);
    return pendingOnline?.future ?? Future.value(online);
  }

  @override
  Future<({BarcodeLookupOutcome status, FoodPickerItem? item})> lookupBarcode(
    String raw,
  ) async {
    barcodes.add(raw);
    return barcode;
  }

  @override
  Future<void> keepOpenedProduct(FoodPickerItem item) async {
    kept.add(item);
  }
}

FoodPickerItem _offItem(
  String code,
  String name, {
  DateTime? changedAt,
  bool live = false,
}) {
  return FoodPickerItem(
    id: code,
    name: name,
    filter: AddFoodPickerFilter.openFoodFacts,
    foodSource: FoodSource.openFoodFacts,
    nutrientsPer100: _nutrients(energy: 500, protein: 6),
    isLiquid: false,
    brand: 'Ferrero',
    sourceModifiedAt: changedAt ?? DateTime.utc(2026, 6, 1),
    isLiveResult: live,
  );
}

class _FakeBarcodeScanner implements BarcodeScanner {
  const _FakeBarcodeScanner(this.result);

  final String? result;

  @override
  Future<String?> scan(BuildContext context) async => result;
}

final _recent = <FoodPickerItem>[
  FoodPickerItem(
    id: 'user-chicken',
    name: 'Chicken breast',
    filter: AddFoodPickerFilter.recent,
    foodSource: FoodSource.user,
    nutrientsPer100: _nutrients(energy: 165, protein: 31),
    isLiquid: false,
  ),
  FoodPickerItem(
    id: 'user-yogurt',
    name: 'Greek yogurt',
    filter: AddFoodPickerFilter.recent,
    foodSource: FoodSource.user,
    nutrientsPer100: _nutrients(energy: 100, protein: 10),
    isLiquid: false,
  ),
];

final _user = <FoodPickerItem>[
  FoodPickerItem(
    id: 'user-meal-prep-chicken',
    name: 'Meal prep chicken',
    filter: AddFoodPickerFilter.user,
    foodSource: FoodSource.user,
    nutrientsPer100: _nutrients(energy: 180, protein: 28),
    isLiquid: false,
  ),
];

final _usda = <FoodPickerItem>[
  FoodPickerItem(
    id: 'usda-chicken',
    name: 'Chicken breast',
    filter: AddFoodPickerFilter.usda,
    foodSource: FoodSource.usda,
    nutrientsPer100: _nutrients(energy: 165, protein: 31),
    isLiquid: false,
  ),
  FoodPickerItem(
    id: 'usda-chickpeas',
    name: 'Chickpeas, boiled',
    filter: AddFoodPickerFilter.usda,
    foodSource: FoodSource.usda,
    nutrientsPer100: _nutrients(energy: 164, protein: 8.9),
    isLiquid: false,
  ),
];

final _openFoodFacts = <FoodPickerItem>[
  FoodPickerItem(
    id: '3017620422003',
    name: 'Hazelnut cocoa spread',
    filter: AddFoodPickerFilter.openFoodFacts,
    foodSource: FoodSource.openFoodFacts,
    nutrientsPer100: _nutrients(energy: 539, protein: 6.3),
    isLiquid: false,
    servingLabel: 'serving',
    servingSize: 15,
    packageSize: 400,
  ),
];

MealRecord _meal() {
  return MealRecord(
    id: 'meal-snack',
    mealType: 'Snack',
    startedAt: DateTime.utc(2026, 6, 26, 15),
    timezone: 'Australia/Brisbane',
    localDate: const NutritionDayDate(year: 2026, month: 6, day: 26),
    updatedAt: DateTime.utc(2026, 6, 26, 15),
  );
}

NutrientVector _nutrients({
  required double energy,
  required double protein,
}) {
  return NutrientVector.energyAndMacros(
    energy: _complete(NutrientId.energy, energy),
    protein: _complete(NutrientId.protein, protein),
    carbohydrate: _complete(NutrientId.carbohydrate, 0),
    fat: _complete(NutrientId.fat, 0),
  );
}

NutrientAmount _complete(NutrientId id, double value) {
  final entered = value.toString().replaceFirst(RegExp(r'\.0$'), '');
  return NutrientAmount.complete(
    value: value,
    entered: entered,
    unit: id.defaultUnit,
  );
}

bool _foodNameMatchesQuery(String name, String query) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty);
  if (terms.isEmpty) {
    return true;
  }

  final searchableName = name.toLowerCase();
  return terms.every(searchableName.contains);
}
