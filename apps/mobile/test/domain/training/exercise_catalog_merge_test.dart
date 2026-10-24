import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/domain/training/exercise_catalog_merge.dart';
import 'package:perennia/domain/training/training_dimensions.dart';
import 'package:perennia/domain/training/training_records.dart';

void main() {
  final updatedAt = DateTime.utc(2026, 1, 1);

  ExerciseRecord exercise(
    String id,
    String name, {
    ExerciseLibraryOrigin origin = ExerciseLibraryOrigin.user,
    String? categoryId,
    bool isFavorite = false,
    bool shadowsPlatformExercise = false,
  }) {
    return ExerciseRecord(
      id: id,
      origin: origin,
      name: name,
      type: ExerciseType(const <DimensionId>[DimensionId.reps]),
      defaultLoadUnit: TrainingUnit.kilogram,
      loadMode: ExerciseLoadMode.added,
      recordProfile: RecordProfile.maxReps,
      categoryId: categoryId,
      notes: null,
      isFavorite: isFavorite,
      updatedAt: updatedAt,
      shadowsPlatformExercise: shadowsPlatformExercise,
    );
  }

  ExerciseCategoryRecord category(String id, String name, int sortOrder) {
    return ExerciseCategoryRecord(
      id: id,
      name: name,
      sortOrder: sortOrder,
      colorHex: '#000000',
      updatedAt: updatedAt,
    );
  }

  const platform = ExerciseLibraryOrigin.platform;

  test('normalizeExerciseName trims and lower-cases', () {
    expect(normalizeExerciseName('  Back SQUAT '), 'back squat');
  });

  test('compareExerciseRecords orders by name, then user before Platform', () {
    final sorted = <ExerciseRecord>[
      exercise('p-squat', 'squat', origin: platform),
      exercise('bench', 'Bench'),
      exercise('u-squat', 'Squat '),
    ]..sort(compareExerciseRecords);
    expect(sorted.map((e) => e.id), <String>['bench', 'u-squat', 'p-squat']);
  });

  test('markShadowingUserExercises flags user names matching Platform', () {
    final marked = markShadowingUserExercises(<ExerciseRecord>[
      exercise('p-squat', 'Squat', origin: platform),
      exercise('u-squat', ' squat'),
      exercise('u-row', 'Row', shadowsPlatformExercise: true),
    ]);
    expect(
      <String, bool>{
        for (final e in marked) e.id: e.shadowsPlatformExercise,
      },
      <String, bool>{'p-squat': false, 'u-squat': true, 'u-row': false},
    );
  });

  test('mergedExercises hides Platform Exercises a user Exercise shadows', () {
    final merged = mergedExercises(<ExerciseRecord>[
      exercise('p-squat', 'Squat', origin: platform),
      exercise('p-row', 'Row', origin: platform),
      exercise('u-squat', 'SQUAT'),
      exercise('u-curl', 'Curl'),
    ]);
    expect(merged.map((e) => e.id), <String>['u-curl', 'p-row', 'u-squat']);
  });

  test('exerciseCatalogSections pins the section layout', () {
    final sections = exerciseCatalogSections(
      <ExerciseCategoryRecord>[
        category('legs', 'Legs', 0),
        category('empty', 'Empty', 1),
        category('back', 'Back', 2),
      ],
      <ExerciseRecord>[
        exercise('p-squat', 'Squat', origin: platform, categoryId: 'legs'),
        exercise('u-squat', 'Squat', categoryId: 'legs', isFavorite: true),
        exercise('lunge', 'Lunge', categoryId: 'legs'),
        exercise('row', 'Row', categoryId: 'back', isFavorite: true),
        exercise('loose', 'Loose'),
        exercise('z-orphan', 'Orphan Z', categoryId: 'zzz'),
        exercise('a-orphan', 'Orphan A', categoryId: 'aaa'),
      ],
    );

    expect(
      sections.map(
        (section) => <Object?>[
          section.id,
          section.title,
          section.isVirtual,
          section.exercises.map((e) => e.id).toList(),
        ],
      ),
      <List<Object?>>[
        <Object?>[
          'favorites',
          'Favorites',
          true,
          <String>['row', 'u-squat']
        ],
        <Object?>[
          'legs',
          'Legs',
          false,
          <String>['lunge', 'u-squat']
        ],
        <Object?>[
          'back',
          'Back',
          false,
          <String>['row']
        ],
        <Object?>[
          'uncategorized',
          'Uncategorized',
          false,
          <String>['a-orphan']
        ],
        <Object?>[
          'uncategorized',
          'Uncategorized',
          false,
          <String>['z-orphan']
        ],
        <Object?>[
          'uncategorized',
          'Uncategorized',
          false,
          <String>['loose']
        ],
      ],
    );
    final shadowing = sections[1].exercises.singleWhere(
          (e) => e.id == 'u-squat',
        );
    expect(shadowing.shadowsPlatformExercise, isTrue);
  });

  test('exerciseCatalogSections omits Favorites when nothing is a favorite',
      () {
    final sections = exerciseCatalogSections(
      <ExerciseCategoryRecord>[category('legs', 'Legs', 0)],
      <ExerciseRecord>[exercise('lunge', 'Lunge', categoryId: 'legs')],
    );
    expect(sections.map((section) => section.id), <String>['legs']);
  });
}
