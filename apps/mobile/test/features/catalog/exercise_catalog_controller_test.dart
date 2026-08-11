import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/data/seeds/platform_exercise_seed.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/features/catalog/controllers/exercise_catalog_controller.dart';
import 'package:perennia/features/catalog/repositories/exercise_catalog_repository.dart';

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

  test('catalog controller streams the seeded picker by category', () async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repositories = TrainingRepositories(
      database,
      platformSeedSource: const _SingleCategorySeedSource(),
    );
    final container = ProviderContainer(
      overrides: [
        exerciseCatalogRepositoryProvider.overrideWith(
          (ref) => RepositoryExerciseCatalogRepository(repositories),
        ),
      ],
    );
    addTearDown(container.dispose);

    final states = <ExerciseCatalogState>[];
    final subscription = container.listen(
      exerciseCatalogControllerProvider,
      (_, next) {
        if (next case AsyncData(:final value)) {
          states.add(value);
        }
      },
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await _waitFor(() => states.isNotEmpty);

    expect(states.single.totalExercises, 1);
    expect(states.single.sections.single.title, 'Strength');
    expect(
        states.single.sections.single.exercises.single.name, 'Barbell Squat');
    expect(states.single.sections.single.exercises.single.isReadOnly, isTrue);
  });

  test('catalog state defensively copies sections and exercises', () {
    final exercises = <ExerciseRecord>[
      _exerciseRecord(
        id: '01910000-0000-7000-8000-000000000101',
        name: 'Barbell Squat',
        categoryId: '01910000-0000-7000-8000-000000000001',
      ),
    ];
    final section = ExerciseCatalogSectionRecord(
      category: _categoryRecord(),
      exercises: exercises,
    );
    final sections = <ExerciseCatalogSectionRecord>[section];

    final state = ExerciseCatalogState(sections: sections);

    sections.add(
      ExerciseCatalogSectionRecord(
        category: _categoryRecord(id: '01910000-0000-7000-8000-000000000002'),
        exercises: const <ExerciseRecord>[],
      ),
    );
    exercises.add(
      _exerciseRecord(
        id: '01910000-0000-7000-8000-000000000102',
        name: 'Front Squat',
        categoryId: '01910000-0000-7000-8000-000000000001',
      ),
    );

    expect(state.sections, hasLength(1));
    expect(state.sections.single.exercises, hasLength(1));
    expect(
      () => state.sections.add(section),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => state.sections.single.exercises.add(
        _exerciseRecord(
          id: '01910000-0000-7000-8000-000000000103',
          name: 'Paused Squat',
          categoryId: '01910000-0000-7000-8000-000000000001',
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });
}

class _SingleCategorySeedSource implements PlatformExerciseSeedSource {
  const _SingleCategorySeedSource();

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
          notes: null,
          updatedAt: DateTime.utc(2026),
        ),
      ],
    );
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  fail('Timed out waiting for condition.');
}

ExerciseCategoryRecord _categoryRecord({
  String id = '01910000-0000-7000-8000-000000000001',
}) {
  return ExerciseCategoryRecord(
    id: id,
    name: 'Strength',
    sortOrder: 0,
    colorHex: '#2F6FED',
    updatedAt: DateTime.utc(2026),
  );
}

ExerciseRecord _exerciseRecord({
  required String id,
  required String name,
  required String categoryId,
}) {
  return ExerciseRecord(
    id: id,
    origin: ExerciseLibraryOrigin.platform,
    name: name,
    type: ExerciseType(
      const <DimensionId>[DimensionId.load, DimensionId.reps],
    ),
    defaultLoadUnit: TrainingUnit.kilogram,
    loadMode: ExerciseLoadMode.added,
    recordProfile: RecordProfile.repMax,
    categoryId: categoryId,
    notes: null,
    isFavorite: false,
    updatedAt: DateTime.utc(2026),
  );
}
