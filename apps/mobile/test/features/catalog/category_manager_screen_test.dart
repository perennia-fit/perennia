import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/catalog/widgets/category_manager_screen.dart';
import 'package:perennia/theme/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(
      database,
      platformSeedSource: const _CategorySeedSource(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('creates renames recolors and archives empty categories',
      (tester) async {
    await _pumpManager(tester, repositories);

    await tester.enterText(
      find.byKey(CategoryManagerScreen.nameFieldKey),
      'Core',
    );
    await tester.tap(find.byKey(CategoryManagerScreen.createButtonKey));
    await tester.pumpAndSettle();

    final coreCategory = (await repositories.catalog.listCategories())
        .singleWhere((category) => category.name == 'Core');
    expect(find.text('Core'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(CategoryManagerScreen.renameButtonKey(coreCategory.id)),
    );
    await tester.enterText(
      find.byKey(CategoryManagerScreen.renameFieldKey),
      'Accessory',
    );
    await tester.tap(find.byKey(CategoryManagerScreen.renameConfirmButtonKey));
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(
        CategoryManagerScreen.colorButtonKey(coreCategory.id, '#E11D48'),
      ),
    );
    await tester.pumpAndSettle();

    var category = (await repositories.catalog.listCategories())
        .singleWhere((category) => category.id == coreCategory.id);
    expect(category.name, 'Accessory');
    expect(category.colorHex, '#E11D48');

    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Dead Bug',
        type: ExerciseType.empty,
        categoryId: coreCategory.id,
      ),
    );
    await _tapVisible(
      tester,
      find.byKey(CategoryManagerScreen.archiveButtonKey(coreCategory.id)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Cannot archive Accessory while it has 1 active exercise. '
        'Reassign or archive that exercise first.',
      ),
      findsOneWidget,
    );

    await repositories.exercises.update(
      exerciseId,
      ExerciseDraft(name: 'Dead Bug', type: ExerciseType.empty),
    );
    await _tapVisible(
      tester,
      find.byKey(CategoryManagerScreen.archiveButtonKey(coreCategory.id)),
    );
    await tester.pumpAndSettle();

    expect(
      (await repositories.catalog.listCategories())
          .map((category) => category.id),
      isNot(contains(coreCategory.id)),
    );
    expect(find.text('Accessory'), findsNothing);
  });

  testWidgets('alphabetizes and manually reorders categories', (tester) async {
    await _pumpManager(tester, repositories);

    await tester.tap(find.byKey(CategoryManagerScreen.alphabetizeButtonKey));
    await tester.pumpAndSettle();

    var categories = await repositories.catalog.listCategories();
    expect(
      categories.map((category) => category.name),
      <String>['Mobility', 'Strength'],
    );

    await tester.tap(
      find.byKey(CategoryManagerScreen.moveDownButtonKey(categories.first.id)),
    );
    await tester.pumpAndSettle();

    categories = await repositories.catalog.listCategories();
    expect(
      categories.map((category) => category.name),
      <String>['Strength', 'Mobility'],
    );
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
        home: const CategoryManagerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  final viewportHeight =
      tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final center = tester.getCenter(finder);
  if (center.dy > viewportHeight - 56) {
    await tester.drag(
      find.byType(Scrollable).first,
      Offset(0, -(center.dy - viewportHeight + 96)),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _CategorySeedSource implements PlatformExerciseSeedSource {
  const _CategorySeedSource();

  @override
  Future<PlatformExerciseSeed> load() async {
    return PlatformExerciseSeed(
      categories: <SeedExerciseCategory>[
        SeedExerciseCategory(
          id: '01910000-0000-7000-8000-000000000001',
          name: 'Strength',
          sortOrder: 0,
          colorHex: '#2F6FED',
          updatedAt: DateTime.utc(2026),
        ),
        SeedExerciseCategory(
          id: '01910000-0000-7000-8000-000000000002',
          name: 'Mobility',
          sortOrder: 1,
          colorHex: '#1F9D55',
          updatedAt: DateTime.utc(2026),
        ),
      ],
      exercises: <SeedExercise>[
        SeedExercise(
          id: '01910000-0000-7000-8000-000000000101',
          name: 'Barbell Squat',
          dimensions: <DimensionId>[DimensionId.load, DimensionId.reps],
          categoryId: '01910000-0000-7000-8000-000000000001',
          notes: null,
          updatedAt: DateTime.utc(2026),
        ),
        SeedExercise(
          id: '01910000-0000-7000-8000-000000000102',
          name: 'Mobility Flow',
          dimensions: <DimensionId>[],
          categoryId: '01910000-0000-7000-8000-000000000002',
          notes: null,
          updatedAt: DateTime.utc(2026),
        ),
      ],
    );
  }
}
