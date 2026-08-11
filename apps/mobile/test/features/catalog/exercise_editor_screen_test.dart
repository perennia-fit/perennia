import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/catalog/repositories/exercise_catalog_repository.dart';
import 'package:perennia/features/catalog/widgets/exercise_editor_screen.dart';
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

  setUp(() {
    database = AppDatabase.inMemory();
    repositories = TrainingRepositories(
      database,
      platformSeedSource: const _EditorSeedSource(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('editor meets accessibility guidelines in both themes',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      await _pumpEditor(tester, repositories, theme: theme);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    }
  });

  testWidgets('creates completion-only exercise and save-and-new resets form',
      (tester) async {
    await _pumpEditor(tester, repositories);

    await tester.enterText(
        find.byKey(ExerciseEditorScreen.nameFieldKey), 'Breathing Flow');
    await tester.enterText(
      find.byKey(ExerciseEditorScreen.notesFieldKey),
      'Downshift after lifting.',
    );
    await _tapVisible(
      tester,
      find.byKey(
        ExerciseEditorScreen.equipmentChipKey(ExerciseEquipment.bodyweight.id),
      ),
    );
    await _tapVisible(tester, find.text('Just track completion'));
    await _tapVisible(
      tester,
      find.byKey(ExerciseEditorScreen.saveNewButtonKey),
    );
    await tester.pumpAndSettle();

    final exercise = (await repositories.exercises.listActive())
        .singleWhere((exercise) => exercise.name == 'Breathing Flow');

    expect(exercise.type, ExerciseType.empty);
    expect(exercise.equipment, <ExerciseEquipment>[
      ExerciseEquipment.bodyweight,
    ]);
    expect(exercise.notes, 'Downshift after lifting.');
    expect(exercise.defaultLoadUnit, TrainingUnit.kilogram);
    await _tapVisible(tester, find.byKey(ExerciseEditorScreen.nameFieldKey));
    expect(
      tester
          .widget<TextField>(find.byKey(ExerciseEditorScreen.nameFieldKey))
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets(
    'prefills a searched name and saves the Exercise to the User Library',
    (tester) async {
      await _pumpEditor(
        tester,
        repositories,
        initialName: '  Nordic Curl  ',
      );

      expect(
        tester
            .widget<TextField>(
              find.byKey(ExerciseEditorScreen.nameFieldKey),
            )
            .controller
            ?.text,
        'Nordic Curl',
      );

      await _tapVisible(
        tester,
        find.byKey(ExerciseEditorScreen.saveButtonKey),
      );

      final matchingRows = (await database.select(database.exercises).get())
          .where((row) => row.name == 'Nordic Curl')
          .toList(growable: false);
      expect(matchingRows, hasLength(1));
      expect(
        matchingRows.single.libraryOrigin,
        ExerciseLibraryOrigin.user.name,
      );
    },
  );

  testWidgets('shows duplicate user-name error without saving', (tester) async {
    await repositories.exercises.create(
      ExerciseDraft(
        name: 'Tempo Row',
        type: ExerciseType(<DimensionId>[DimensionId.reps]),
      ),
    );
    await _pumpEditor(tester, repositories);

    await tester.enterText(
      find.byKey(ExerciseEditorScreen.nameFieldKey),
      ' tempo row ',
    );
    await _tapVisible(tester, find.byKey(ExerciseEditorScreen.saveButtonKey));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(ExerciseEditorScreen.nameFieldKey));

    expect(
        find.text('A user exercise with this name already exists.'), findsOne);
    final userRows = (await database.select(database.exercises).get())
        .where(
          (row) =>
              row.libraryOrigin == ExerciseLibraryOrigin.user.name &&
              row.deletedAt == null,
        )
        .toList(growable: false);
    expect(userRows, hasLength(1));
  });

  testWidgets('applies named presets to saved dimensions', (tester) async {
    await _pumpEditor(tester, repositories);

    await tester.enterText(
      find.byKey(ExerciseEditorScreen.nameFieldKey),
      'Easy Cardio',
    );
    await _tapVisible(tester, find.text('Cardio'));
    await _tapVisible(
      tester,
      find.byKey(ExerciseEditorScreen.saveNewButtonKey),
    );

    final exercise = (await repositories.exercises.listActive())
        .singleWhere((exercise) => exercise.name == 'Easy Cardio');

    expect(
      exercise.type.dimensions,
      <DimensionId>[DimensionId.distance, DimensionId.duration],
    );
  });

  testWidgets('sets assisted load mode and default record profile',
      (tester) async {
    await _pumpEditor(tester, repositories);

    await tester.enterText(
      find.byKey(ExerciseEditorScreen.nameFieldKey),
      'Assisted Pull-Up',
    );
    await _selectDropdownValue(
      tester,
      find.byKey(ExerciseEditorScreen.loadModeFieldKey),
      'Assisted',
    );

    expect(find.text('Min assistance per rep count'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(ExerciseEditorScreen.saveNewButtonKey),
    );

    final exercise = (await repositories.exercises.listActive())
        .singleWhere((exercise) => exercise.name == 'Assisted Pull-Up');
    final log = (await repositories.activityLog.listEntries()).last;

    expect(exercise.loadMode, ExerciseLoadMode.assisted);
    expect(exercise.recordProfile, RecordProfile.minAssistancePerRepCount);
    expect(log.afterImage?['load_mode'], 'assisted');
    expect(
      log.afterImage?['record_profile'],
      'minAssistancePerRepCount',
    );
  });

  testWidgets('saves unilateral and RPE annotation toggles', (tester) async {
    await _pumpEditor(tester, repositories);

    await tester.enterText(
      find.byKey(ExerciseEditorScreen.nameFieldKey),
      'Single-Leg Press',
    );
    await _tapVisible(
      tester,
      find.byKey(ExerciseEditorScreen.unilateralToggleKey),
    );
    await _tapVisible(
      tester,
      find.byKey(ExerciseEditorScreen.rpeToggleKey),
    );
    await _tapVisible(
      tester,
      find.byKey(ExerciseEditorScreen.saveNewButtonKey),
    );

    final exercise = (await repositories.exercises.listActive())
        .singleWhere((exercise) => exercise.name == 'Single-Leg Press');
    final log = (await repositories.activityLog.listEntries()).last;

    expect(exercise.isUnilateral, true);
    expect(exercise.usesRpe, true);
    expect(log.afterImage?['is_unilateral'], true);
    expect(log.afterImage?['uses_rpe'], true);
  });

  testWidgets('preserves explicit record profile override across type edits',
      (tester) async {
    await _pumpEditor(tester, repositories);

    await tester.enterText(
      find.byKey(ExerciseEditorScreen.nameFieldKey),
      'Plank Test',
    );
    await _selectDropdownValue(
      tester,
      find.byKey(ExerciseEditorScreen.recordProfileFieldKey),
      'Max reps',
    );
    await _tapVisible(tester, find.text('Timed hold'));

    expect(find.text('Max reps'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(ExerciseEditorScreen.saveNewButtonKey),
    );

    final exercise = (await repositories.exercises.listActive())
        .singleWhere((exercise) => exercise.name == 'Plank Test');

    expect(exercise.type.dimensions, <DimensionId>[DimensionId.duration]);
    expect(exercise.loadMode, ExerciseLoadMode.added);
    expect(exercise.recordProfile, RecordProfile.maxReps);
  });

  testWidgets('assigns an exercise to an active category choice',
      (tester) async {
    await repositories.catalog.ensurePlatformLibrarySeeded();
    final categoryId = await repositories.catalog.createCategory(
      const ExerciseCategoryDraft(name: 'Core'),
    );
    await _pumpEditor(tester, repositories);

    await tester.enterText(
      find.byKey(ExerciseEditorScreen.nameFieldKey),
      'Dead Bug',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Core').last);
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(ExerciseEditorScreen.saveNewButtonKey),
    );

    final exercise = (await repositories.exercises.listActive())
        .singleWhere((exercise) => exercise.name == 'Dead Bug');
    expect(exercise.categoryId, categoryId);
  });

  testWidgets('edits existing user exercise with a preset', (tester) async {
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Carry',
        type: ExerciseType(<DimensionId>[
          DimensionId.load,
          DimensionId.distance,
        ]),
        defaultLoadUnit: TrainingUnit.pound,
      ),
    );
    await _pumpEditor(tester, repositories, exerciseId: exerciseId);

    await _tapVisible(tester, find.text('Timed hold'));
    await _tapVisible(tester, find.byKey(ExerciseEditorScreen.notesFieldKey));
    await tester.enterText(
      find.byKey(ExerciseEditorScreen.notesFieldKey),
      'Hold for quality.',
    );
    await _tapVisible(tester, find.byKey(ExerciseEditorScreen.saveButtonKey));
    await tester.pumpAndSettle();

    final exercise = (await repositories.exercises.listActive())
        .singleWhere((exercise) => exercise.id == exerciseId);

    expect(exercise.type.dimensions, <DimensionId>[DimensionId.duration]);
    expect(exercise.notes, 'Hold for quality.');
    expect(exercise.defaultLoadUnit, TrainingUnit.pound);
  });

  testWidgets('archives an existing user exercise from the editor',
      (tester) async {
    final exerciseId = await repositories.exercises.create(
      ExerciseDraft(
        name: 'Tempo Row',
        type: ExerciseType(<DimensionId>[DimensionId.reps]),
      ),
    );
    await _pumpEditor(tester, repositories, exerciseId: exerciseId);

    await _tapVisible(
        tester, find.byKey(ExerciseEditorScreen.archiveButtonKey));

    final archived = await repositories.exercises.getById(exerciseId);
    final activeIds = (await repositories.exercises.listActive())
        .map((exercise) => exercise.id);

    expect(archived, isNotNull);
    expect(archived?.deletedAt, isNotNull);
    expect(activeIds, isNot(contains(exerciseId)));
  });

  testWidgets('customizing a platform exercise without changes is a no-op',
      (tester) async {
    await repositories.catalog.ensurePlatformLibrarySeeded();
    final platformExercise = (await repositories.catalog.listMergedCatalog())
        .expand((section) => section.exercises)
        .singleWhere((exercise) => exercise.name == 'Barbell Squat');

    await _pumpEditor(
      tester,
      repositories,
      platformExerciseId: platformExercise.id,
    );
    await _tapVisible(tester, find.byKey(ExerciseEditorScreen.saveButtonKey));
    await tester.pumpAndSettle();

    expect(await _activeUserExercises(repositories), isEmpty);
    final visibleSquat = (await repositories.catalog.listMergedCatalog())
        .where((section) => !section.isVirtual)
        .expand((section) => section.exercises)
        .singleWhere((exercise) => exercise.name == 'Barbell Squat');
    expect(visibleSquat.id, platformExercise.id);
    expect(visibleSquat.shadowsPlatformExercise, isFalse);
  });

  testWidgets('saving a changed platform exercise creates a user override',
      (tester) async {
    await repositories.catalog.ensurePlatformLibrarySeeded();
    final platformExercise = (await repositories.catalog.listMergedCatalog())
        .expand((section) => section.exercises)
        .singleWhere((exercise) => exercise.name == 'Barbell Squat');

    await _pumpEditor(
      tester,
      repositories,
      platformExerciseId: platformExercise.id,
    );
    await _tapVisible(tester, find.byKey(ExerciseEditorScreen.notesFieldKey));
    await tester.enterText(
      find.byKey(ExerciseEditorScreen.notesFieldKey),
      'Brace and drive evenly.',
    );
    await _tapVisible(
      tester,
      find.byKey(
        ExerciseEditorScreen.equipmentChipKey(ExerciseEquipment.bench.id),
      ),
    );
    await _tapVisible(tester, find.byKey(ExerciseEditorScreen.saveButtonKey));
    await tester.pumpAndSettle();

    final userExercises = await _activeUserExercises(repositories);
    final userCopy = userExercises.single;
    final visibleSquat = (await repositories.catalog.listMergedCatalog())
        .where((section) => !section.isVirtual)
        .expand((section) => section.exercises)
        .singleWhere((exercise) => exercise.name == 'Barbell Squat');

    expect(userCopy.name, platformExercise.name);
    expect(userCopy.equipment, <ExerciseEquipment>[
      ExerciseEquipment.barbell,
      ExerciseEquipment.bench,
    ]);
    expect(userCopy.notes, 'Brace and drive evenly.');
    expect(visibleSquat.id, userCopy.id);
    expect(visibleSquat.shadowsPlatformExercise, isTrue);
  });
}

Future<void> _pumpEditor(
  WidgetTester tester,
  TrainingRepositories repositories, {
  String? exerciseId,
  String? platformExerciseId,
  String? initialName,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingRepositoriesProvider.overrideWith((ref) => repositories),
        exerciseCatalogRepositoryProvider.overrideWith(
          (ref) => RepositoryExerciseCatalogRepository(repositories),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: ExerciseEditorScreen(
          exerciseId: exerciseId,
          platformExerciseId: platformExerciseId,
          initialName: initialName,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<List<ExerciseRecord>> _activeUserExercises(
  TrainingRepositories repositories,
) async {
  final exercises = await repositories.exercises.listActive();
  return exercises
      .where((exercise) => exercise.origin == ExerciseLibraryOrigin.user)
      .toList(growable: false);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await _scrollUntilBuilt(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final viewportHeight =
      tester.view.physicalSize.height / tester.view.devicePixelRatio;
  var center = tester.getCenter(finder);
  if (center.dy > viewportHeight - 56) {
    await tester.drag(
      find.byType(Scrollable).first,
      Offset(0, -(center.dy - viewportHeight + 96)),
    );
    await tester.pumpAndSettle();
  }
  center = tester.getCenter(finder);
  if (center.dy < 56) {
    await tester.drag(
      find.byType(Scrollable).first,
      Offset(0, 96 - center.dy),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilBuilt(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    return;
  }

  final scrollable = find.byType(Scrollable).first;
  for (final offset in const <Offset>[
    Offset(0, -240),
    Offset(0, 240),
  ]) {
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await tester.drag(scrollable, offset);
      await tester.pumpAndSettle();
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
  }
}

Future<void> _selectDropdownValue(
  WidgetTester tester,
  Finder dropdown,
  String label,
) async {
  await _tapVisible(tester, dropdown);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class _EditorSeedSource implements PlatformExerciseSeedSource {
  const _EditorSeedSource();

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
      ],
      exercises: <SeedExercise>[
        SeedExercise(
          id: '01910000-0000-7000-8000-000000000101',
          name: 'Barbell Squat',
          dimensions: <DimensionId>[DimensionId.load, DimensionId.reps],
          categoryId: '01910000-0000-7000-8000-000000000001',
          equipment: <ExerciseEquipment>[ExerciseEquipment.barbell],
          notes: null,
          updatedAt: DateTime.utc(2026),
        ),
      ],
    );
  }
}
