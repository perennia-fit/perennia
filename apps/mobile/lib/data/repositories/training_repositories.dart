import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../domain/body_tracker/measurement_validation.dart';
import '../../domain/effect/effect.dart';
import '../../domain/nutrition/nutrition.dart';
import '../../domain/nutrition/nutrition_import.dart';
import '../../domain/protocols/dose_validation.dart';
import '../../domain/protocols/protocols.dart';
import '../../domain/settings/account_settings.dart';
import '../../domain/training/plan_validation.dart' as plan_validation;
import '../../domain/training/routine_cadence.dart';
import '../../domain/training/routine_up_next.dart';
import '../../domain/training/set_validation.dart';
import '../../domain/training/template_divergence.dart';
import '../../domain/training/template_materialize.dart';
import '../../domain/training/training_day.dart';
import '../../domain/training/training_dimensions.dart';
import '../../domain/training/workout_capture.dart';
import '../local/app_database.dart';
import '../local/uuid_v7.dart';
import '../seeds/otc_compound_seed.dart';
import '../seeds/platform_exercise_seed.dart';
import '../seeds/usda_food_seed.dart';
import '../sync/sync_lww.dart';

export '../../domain/body_tracker/measurement_validation.dart'
    show
        MeasurementValidationWarning,
        MeasurementValidationWarningCode,
        MeasurementValueException,
        MeasurementValueValidation;
export '../../domain/effect/effect.dart';
export '../../domain/nutrition/nutrition.dart';
export '../../domain/nutrition/nutrition_import.dart';
export '../../domain/protocols/dose_validation.dart'
    show
        DoseValidationException,
        DoseValidationIssue,
        DoseValidationLimits,
        DoseValidationResult,
        DoseUnitLimit,
        validateDose;
export '../../domain/protocols/protocols.dart';
export '../../domain/training/routine_cadence.dart';
export '../../domain/training/routine_up_next.dart'
    show
        RoutineUpNextSuggestion,
        UpNextCard,
        UpNextRoutineEntry,
        UpNextTemplateLinkFact,
        deriveRoutineUpNext;
export '../../domain/training/template_divergence.dart'
    show
        TemplateContentSnapshot,
        TemplateDivergenceExerciseRef,
        TemplateDivergenceExerciseSnapshot,
        TemplateDivergenceGroupSnapshot,
        TemplateDivergencePrescriptionMode,
        TemplateDivergencePrescriptionSnapshot,
        TemplateDivergenceResult;
export '../../domain/training/workout_capture.dart';
export '../../domain/training/set_validation.dart'
    show
        NutrientValidationException,
        NutrientValidationLimits,
        NutrientValidationResult,
        SetValidationException,
        SetValidationIssue,
        SetValidationLimits,
        SetValidationResult,
        validateNutritionGoalTargets;

part 'csv_export_repository.dart';
part 'portable_archive_repository.dart';
part 'plan_sync_repository.dart';
part 'routine_plan_repository.dart';
part 'routine_up_next_repository.dart';
part 'template_divergence_repository.dart';
part 'template_materialize_repository.dart';
part 'workout_capture_repository.dart';
part 'workout_template_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.openDefault();
  ref.onDispose(database.close);
  return database;
});

final trainingRepositoriesProvider = Provider<TrainingRepositories>((ref) {
  return TrainingRepositories(ref.watch(appDatabaseProvider));
});

const defaultOpenFoodFactsMaxCacheEntries = 5000;

class TrainingRepositories {
  TrainingRepositories(
    this.database, {
    UuidV7Generator? uuidGenerator,
    PlatformExerciseSeedSource? platformSeedSource,
    UsdaFoodSeedSource? usdaFoodSeedSource,
    OtcCompoundSeedSource? otcCompoundSeedSource,
    Uri? openFoodFactsBaseUrl,
    http.Client? openFoodFactsHttpClient,
    int openFoodFactsMaxCacheEntries = defaultOpenFoodFactsMaxCacheEntries,
    DateTime Function()? openFoodFactsClock,
  }) : uuidGenerator = uuidGenerator ?? UuidV7Generator() {
    activityLog = ActivityLogRepository._(this);
    catalog = CatalogRepository._(
      this,
      platformSeedSource ?? const AssetPlatformExerciseSeedSource(),
    );
    exercises = ExerciseRepository._(this);
    workoutSessions = WorkoutSessionRepository._(this);
    workoutExercises = WorkoutExerciseRepository._(this);
    exerciseGroups = ExerciseGroupRepository._(this);
    workoutCapture = WorkoutCaptureRepository._(this);
    workoutTemplates = WorkoutTemplateRepository._(this);
    routinePlans = RoutinePlanRepository._(this);
    routineUpNext = RoutineUpNextRepository._(this);
    templateMaterialize = TemplateMaterializeRepository._(this);
    templateDivergence = TemplateDivergenceRepository._(this);
    sets = LoggedSetRepository._(this);
    platformFoods = PlatformFoodRepository._(
      usdaFoodSeedSource ?? const AssetUsdaFoodSeedSource(),
    );
    openFoodFacts = OpenFoodFactsRepository._(
      this,
      baseUrl:
          openFoodFactsBaseUrl ?? Uri.parse('https://world.openfoodfacts.org/'),
      httpClient: openFoodFactsHttpClient ?? http.Client(),
      maxCacheEntries: openFoodFactsMaxCacheEntries,
      clock: openFoodFactsClock,
    );
    nutrition = NutritionRepository._(this);
    accountSettings = AccountSettingsRepository._(this);
    protocols = ProtocolsRepository._(
      this,
      otcCompoundSeedSource ?? const DefaultOtcCompoundSeedSource(),
    );
    effect = EffectRepository._(this);
    restTimers = RestTimerRepository._(this);
    measurements = MeasurementRepository._(this);
    metrics = MetricRepository._(this);
    csvExports = CsvExportRepository._(this);
    portableArchives = PortableArchiveRepository._(this);
  }

  final AppDatabase database;
  final UuidV7Generator uuidGenerator;

  late final ActivityLogRepository activityLog;
  late final CatalogRepository catalog;
  late final ExerciseRepository exercises;
  late final WorkoutSessionRepository workoutSessions;
  late final WorkoutExerciseRepository workoutExercises;
  late final ExerciseGroupRepository exerciseGroups;
  late final WorkoutCaptureRepository workoutCapture;
  late final WorkoutTemplateRepository workoutTemplates;
  late final RoutinePlanRepository routinePlans;
  late final RoutineUpNextRepository routineUpNext;
  late final TemplateMaterializeRepository templateMaterialize;
  late final TemplateDivergenceRepository templateDivergence;
  late final LoggedSetRepository sets;
  late final PlatformFoodRepository platformFoods;
  late final OpenFoodFactsRepository openFoodFacts;
  late final NutritionRepository nutrition;
  late final AccountSettingsRepository accountSettings;
  late final ProtocolsRepository protocols;
  late final EffectRepository effect;
  late final RestTimerRepository restTimers;
  late final MeasurementRepository measurements;
  late final MetricRepository metrics;
  late final CsvExportRepository csvExports;
  late final PortableArchiveRepository portableArchives;

  static const starterWeightRepsExerciseName = 'Barbell Squat';
  static const starterTimedExerciseName = 'Plank';

  Future<List<ExerciseRecord>> ensureStarterExercises({
    String actor = 'app',
  }) async {
    await catalog.ensurePlatformLibrarySeeded(actor: actor);
    return exercises.listActive();
  }

  Future<LogWorkoutResult> logDefaultWeightRepsSet({
    DateTime? now,
    String? timezone,
    String actor = 'app',
  }) async {
    final starterExercises = await ensureStarterExercises(actor: actor);
    final exercise = _defaultWeightRepsExercise(starterExercises);
    final localNow = (now ?? DateTime.now()).toLocal();
    final localDate = TrainingDayDate.fromDateTime(localNow);
    final context = _createWriteContext(actor: actor);

    return database.transaction(() async {
      final workout = await _findWorkoutForLocalDate(localDate);
      final workoutId = workout == null
          ? await workoutSessions._create(
              WorkoutSessionDraft(
                startedAt: localNow,
                timezone: timezone ?? localNow.timeZoneName,
                localDate: localDate,
              ),
              context,
            )
          : workout.id;
      final existingSets = await sets.listActiveForWorkout(workoutId);
      final setId = await sets._create(
        LoggedSetDraft(
          workoutId: workoutId,
          exerciseId: exercise.id,
          position: existingSets.length,
          values: LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '100',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '5',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
        context,
      );

      return LogWorkoutResult(
        batchId: context.batchId,
        workoutSessionId: workoutId,
        loggedSetId: setId,
      );
    });
  }

  Future<void> eraseAllData() {
    final context = _createWriteContext(actor: 'settings');
    return database.transaction(() async {
      await _appendLoggedSetEraseTombstones(context);
      await _softDeleteDomainRowsForErase(context.timestamp);
    });
  }

  Future<void> _appendLoggedSetEraseTombstones(_WriteContext context) async {
    final rows = await (database.select(database.loggedSets)
          ..where((row) => row.deletedAt.isNull()))
        .get();
    for (final before in rows) {
      await (database.update(database.loggedSets)
            ..where((row) => row.id.equals(before.id)))
          .write(
        LoggedSetsCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await sets._requireRow(before.id);
      await activityLog._append(
        context,
        entityTable: AppDatabase.loggedSetsTable,
        entityId: before.id,
        beforeImage: _loggedSetImage(before),
        afterImage: _loggedSetImage(after),
      );
    }
  }

  Future<void> _softDeleteDomainRowsForErase(DateTime timestamp) async {
    await (database.update(database.intervalTimers)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      IntervalTimersCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.restTimers)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      RestTimersCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.loggedSets)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      LoggedSetsCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.foodEntries)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      FoodEntriesCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.foods)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      FoodsCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.mealTypes)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      MealTypesCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.meals)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      MealsCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.metricReadings)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      MetricReadingsCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.metrics)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      MetricsCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.exerciseGroupMembers)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      ExerciseGroupMembersCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.exerciseGroups)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      ExerciseGroupsCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.workoutExercises)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      WorkoutExercisesCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.workoutSessions)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      WorkoutSessionsCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.exercises)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      ExercisesCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
    await (database.update(database.exerciseCategories)
          ..where((row) => row.deletedAt.isNull()))
        .write(
      ExerciseCategoriesCompanion(
        updatedAt: Value<DateTime>(timestamp),
        deletedAt: Value<DateTime?>(timestamp),
      ),
    );
  }

  Future<LogWorkoutResult> logWorkoutWithSet(
    WorkoutSessionDraft workout,
    LoggedSetDraft set, {
    String actor = 'app',
  }) {
    final context = _createWriteContext(actor: actor);

    return database.transaction(() async {
      final workoutId = await workoutSessions._create(workout, context);
      final setId = await sets._create(
        set.copyWith(workoutId: workoutId),
        context,
      );

      return LogWorkoutResult(
        batchId: context.batchId,
        workoutSessionId: workoutId,
        loggedSetId: setId,
      );
    });
  }

  Future<WorkoutPlanLogResult> logWorkoutPlan(
    WorkoutSessionDraft workout, {
    required List<WorkoutPlanExerciseDraft> exercises,
    String actor = 'app',
  }) {
    if (exercises.isEmpty) {
      throw ArgumentError.value(
        exercises,
        'exercises',
        'A workout plan requires at least one selected exercise.',
      );
    }

    final context = _createWriteContext(actor: actor);

    return database.transaction(() async {
      final workoutId = await workoutSessions._create(workout, context);
      final workoutExerciseIds = <String>[];
      final loggedSetIds = <String>[];
      var nextSetPosition = 0;

      for (final exercise in exercises) {
        final workoutExerciseId = await workoutExercises._create(
          WorkoutExerciseDraft(
            workoutId: workoutId,
            exerciseId: exercise.exerciseId,
          ),
          context,
        );
        workoutExerciseIds.add(workoutExerciseId);

        for (final set in exercise.sets) {
          final setId = await sets._create(
            LoggedSetDraft(
              workoutId: workoutId,
              exerciseId: exercise.exerciseId,
              position: nextSetPosition,
              values: set.values,
              plannedRestAfter: set.plannedRestAfter,
            ),
            context,
          );
          loggedSetIds.add(setId);
          nextSetPosition += 1;
        }
      }

      return WorkoutPlanLogResult(
        batchId: context.batchId,
        workoutId: workoutId,
        workoutExerciseIds: List<String>.unmodifiable(workoutExerciseIds),
        loggedSetIds: List<String>.unmodifiable(loggedSetIds),
      );
    });
  }

  _WriteContext _createWriteContext({required String actor, String? batchId}) {
    final timestamp = DateTime.now().toUtc();
    return _WriteContext(
      actor: actor,
      batchId: batchId ?? uuidGenerator.generate(timestamp: timestamp),
      timestamp: timestamp,
    );
  }

  String createId(DateTime timestamp) {
    return uuidGenerator.generate(timestamp: timestamp);
  }

  ExerciseRecord _defaultWeightRepsExercise(List<ExerciseRecord> exercises) {
    return exercises.firstWhere(
      (exercise) => exercise.name == starterWeightRepsExerciseName,
      orElse: () => exercises.firstWhere(
        (exercise) => exercise.type.accepts(
          LoggedSet.fromValues(
            const <SetDimensionValue>[
              SetDimensionValue(
                dimension: DimensionId.load,
                entered: '100',
                unit: TrainingUnit.kilogram,
              ),
              SetDimensionValue(
                dimension: DimensionId.reps,
                entered: '5',
                unit: TrainingUnit.repetition,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<WorkoutSessionRecord?> _findWorkoutForLocalDate(
    TrainingDayDate localDate,
  ) async {
    final sessions = await workoutSessions.listActiveForLocalDate(localDate);
    return sessions.isEmpty ? null : sessions.first;
  }
}

class CatalogRepository {
  CatalogRepository._(
    this._repositories,
    this._platformSeedSource,
  );

  final TrainingRepositories _repositories;
  final PlatformExerciseSeedSource _platformSeedSource;
  Future<void>? _platformSeedFuture;

  AppDatabase get _database => _repositories.database;

  Future<void> ensurePlatformLibrarySeeded({
    String actor = 'platform_seed',
  }) {
    final existingFuture = _platformSeedFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    late final Future<void> nextFuture;
    nextFuture = _ensurePlatformLibrarySeeded(actor: actor).catchError(
      (Object error, StackTrace stackTrace) {
        if (identical(_platformSeedFuture, nextFuture)) {
          _platformSeedFuture = null;
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _platformSeedFuture = nextFuture;
    return nextFuture;
  }

  Future<void> _ensurePlatformLibrarySeeded({
    required String actor,
  }) async {
    final seed = await _platformSeedSource.load();
    if (seed.categories.isEmpty && seed.exercises.isEmpty) {
      return;
    }

    final context = _repositories._createWriteContext(actor: actor);

    await _database.transaction(() async {
      final existingCategoryIds =
          (await _database.select(_database.exerciseCategories).get())
              .map((row) => row.id)
              .toSet();
      final existingExerciseIds =
          (await _database.select(_database.exercises).get())
              .map((row) => row.id)
              .toSet();

      for (final category in seed.categories) {
        if (existingCategoryIds.contains(category.id)) {
          continue;
        }

        await _database.into(_database.exerciseCategories).insert(
              ExerciseCategoriesCompanion.insert(
                id: category.id,
                name: category.name,
                sortOrder: category.sortOrder,
                colorHex: category.colorHex,
                updatedAt: category.updatedAt,
              ),
            );
        final after = await _requireCategoryRow(category.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.exerciseCategoriesTable,
          entityId: category.id,
          beforeImage: null,
          afterImage: _exerciseCategoryImage(after),
        );
      }

      for (final exercise in seed.exercises) {
        if (existingExerciseIds.contains(exercise.id)) {
          continue;
        }

        final exerciseType = ExerciseType(exercise.dimensions);
        const loadMode = ExerciseLoadMode.added;
        await _database.into(_database.exercises).insert(
              ExercisesCompanion.insert(
                id: exercise.id,
                libraryOrigin: Value<String>(
                  ExerciseLibraryOrigin.platform.name,
                ),
                name: exercise.name,
                dimensionIds: _encodeDimensions(exerciseType),
                loadMode: Value<String>(loadMode.name),
                recordProfile: Value<String>(
                  defaultRecordProfileFor(
                    type: exerciseType,
                    loadMode: loadMode,
                  ).name,
                ),
                defaultLoadUnit: Value<String>(
                  TrainingUnit.kilogram.name,
                ),
                isUnilateral: const Value<bool>(false),
                usesRpe: const Value<bool>(false),
                categoryId: Value<String?>(exercise.categoryId),
                equipmentIds:
                    Value<String>(_encodeEquipment(exercise.equipment)),
                notes: Value<String?>(exercise.notes),
                updatedAt: exercise.updatedAt,
              ),
            );
        final after = await _requireExerciseRow(exercise.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.exercisesTable,
          entityId: exercise.id,
          beforeImage: null,
          afterImage: _exerciseImage(after),
        );
      }

      await _applyPlatformExerciseRedirects(seed, context);

      await _sanitizeLegacyWgerAttributionNotes(context);
      await _backfillExistingPlatformSeedEquipment(seed, context);
    });
  }

  Future<void> _applyPlatformExerciseRedirects(
    PlatformExerciseSeed seed,
    _WriteContext context,
  ) async {
    if (seed.redirects.isEmpty) {
      return;
    }

    final exercisesById = <String, SeedExercise>{
      for (final exercise in seed.exercises) exercise.id: exercise,
    };
    for (final redirect in seed.redirects) {
      final canonical = exercisesById[redirect.toExerciseId];
      if (canonical == null) {
        throw StateError(
          'Platform exercise redirect ${redirect.fromExerciseId} points to '
          'missing exercise ${redirect.toExerciseId}.',
        );
      }

      final existing = await (_database.select(_database.exercises)
            ..where((row) => row.id.equals(redirect.fromExerciseId)))
          .getSingleOrNull();
      if (existing != null) {
        if (existing.libraryOrigin != ExerciseLibraryOrigin.platform.name) {
          throw StateError(
            'Platform exercise redirect ${redirect.fromExerciseId} conflicts '
            'with a User Library Exercise.',
          );
        }
        if (existing.deletedAt != null) {
          continue;
        }

        await (_database.update(_database.exercises)
              ..where((row) => row.id.equals(redirect.fromExerciseId)))
            .write(
          ExercisesCompanion(
            updatedAt: Value<DateTime>(canonical.updatedAt),
            deletedAt: Value<DateTime?>(canonical.updatedAt),
          ),
        );
        final after = await _requireExerciseRow(redirect.fromExerciseId);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.exercisesTable,
          entityId: redirect.fromExerciseId,
          beforeImage: _exerciseImage(existing),
          afterImage: _exerciseImage(after),
        );
        continue;
      }

      final exerciseType = ExerciseType(canonical.dimensions);
      const loadMode = ExerciseLoadMode.added;
      await _database.into(_database.exercises).insert(
            ExercisesCompanion.insert(
              id: redirect.fromExerciseId,
              libraryOrigin: Value<String>(
                ExerciseLibraryOrigin.platform.name,
              ),
              name: canonical.name,
              dimensionIds: _encodeDimensions(exerciseType),
              loadMode: Value<String>(loadMode.name),
              recordProfile: Value<String>(
                defaultRecordProfileFor(
                  type: exerciseType,
                  loadMode: loadMode,
                ).name,
              ),
              defaultLoadUnit: Value<String>(TrainingUnit.kilogram.name),
              isUnilateral: const Value<bool>(false),
              usesRpe: const Value<bool>(false),
              categoryId: Value<String?>(canonical.categoryId),
              equipmentIds:
                  Value<String>(_encodeEquipment(canonical.equipment)),
              notes: Value<String?>(canonical.notes),
              updatedAt: canonical.updatedAt,
              deletedAt: Value<DateTime?>(canonical.updatedAt),
            ),
          );
      final alias = await _requireExerciseRow(redirect.fromExerciseId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exercisesTable,
        entityId: redirect.fromExerciseId,
        beforeImage: null,
        afterImage: _exerciseImage(alias),
      );
    }
  }

  Future<void> _backfillExistingPlatformSeedEquipment(
    PlatformExerciseSeed seed,
    _WriteContext context,
  ) async {
    for (final exercise in seed.exercises) {
      if (exercise.equipment.isEmpty) {
        continue;
      }

      final before = await (_database.select(_database.exercises)
            ..where((row) => row.id.equals(exercise.id)))
          .getSingleOrNull();
      if (before == null ||
          before.libraryOrigin != ExerciseLibraryOrigin.platform.name ||
          _decodeEquipment(before.equipmentIds).isNotEmpty) {
        continue;
      }

      await (_database.update(_database.exercises)
            ..where((row) => row.id.equals(exercise.id)))
          .write(
        ExercisesCompanion(
          equipmentIds: Value<String>(_encodeEquipment(exercise.equipment)),
          updatedAt: Value<DateTime>(exercise.updatedAt),
        ),
      );
      final after = await _requireExerciseRow(exercise.id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exercisesTable,
        entityId: exercise.id,
        beforeImage: _exerciseImage(before),
        afterImage: _exerciseImage(after),
      );
    }
  }

  Future<void> _sanitizeLegacyWgerAttributionNotes(
    _WriteContext context,
  ) async {
    final rows = await _database.select(_database.exercises).get();
    for (final before in rows) {
      if (before.libraryOrigin != ExerciseLibraryOrigin.platform.name) {
        continue;
      }

      final migration = _legacyEquipmentMigrationFromNote(before.notes);
      final cleanedNote = migration != null
          ? migration.notes
          : _cleanLegacyWgerAttributionNote(before.notes);
      final existingEquipment = _decodeEquipment(before.equipmentIds);
      final migratedEquipment =
          migration?.equipment ?? const <ExerciseEquipment>[];
      final nextEquipment =
          existingEquipment.isEmpty && migratedEquipment.isNotEmpty
              ? migratedEquipment
              : existingEquipment;
      if (cleanedNote == before.notes &&
          _equipmentListEquals(nextEquipment, existingEquipment)) {
        continue;
      }

      await (_database.update(_database.exercises)
            ..where((row) => row.id.equals(before.id)))
          .write(
        ExercisesCompanion(
          equipmentIds: Value<String>(_encodeEquipment(nextEquipment)),
          notes: Value<String?>(cleanedNote),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireExerciseRow(before.id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exercisesTable,
        entityId: before.id,
        beforeImage: _exerciseImage(before),
        afterImage: _exerciseImage(after),
      );
    }
  }

  Future<List<ExerciseCatalogSectionRecord>> listMergedCatalog() async {
    final categories = await _activeCategoryQuery().get();
    final exercises = await _activeExerciseQuery().get();

    return _catalogSectionsFrom(
      categories.map(_exerciseCategoryFromRow).toList(growable: false),
      exercises.map(_exerciseFromRow).toList(growable: false),
    );
  }

  Future<List<ExerciseCategoryRecord>> listCategories({
    CategoryOrdering ordering = CategoryOrdering.manual,
  }) async {
    final rows = await _activeCategoryQuery(ordering: ordering).get();
    return rows.map(_exerciseCategoryFromRow).toList(growable: false);
  }

  Future<String> createCategory(
    ExerciseCategoryDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() => _createCategory(draft, context));
  }

  Future<void> renameCategory(
    String id, {
    required String name,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireCategoryRow(id);
      await _ensureUniqueActiveCategoryName(name, exceptId: id);
      await (_database.update(_database.exerciseCategories)
            ..where((row) => row.id.equals(id)))
          .write(
        ExerciseCategoriesCompanion(
          name: Value<String>(_normalizeCategoryNameForStorage(name)),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireCategoryRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exerciseCategoriesTable,
        entityId: id,
        beforeImage: _exerciseCategoryImage(before),
        afterImage: _exerciseCategoryImage(after),
      );
    });
  }

  Future<void> recolorCategory(
    String id, {
    required String colorHex,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireCategoryRow(id);
      await (_database.update(_database.exerciseCategories)
            ..where((row) => row.id.equals(id)))
          .write(
        ExerciseCategoriesCompanion(
          colorHex: Value<String>(_normalizeColorHex(colorHex)),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireCategoryRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exerciseCategoriesTable,
        entityId: id,
        beforeImage: _exerciseCategoryImage(before),
        afterImage: _exerciseCategoryImage(after),
      );
    });
  }

  Future<void> reorderCategories(
    List<String> categoryIds, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final activeRows = await _activeCategoryQuery().get();
      final activeIds = activeRows.map((row) => row.id).toSet();
      if (categoryIds.length != activeIds.length ||
          categoryIds.toSet().length != categoryIds.length ||
          !categoryIds.every(activeIds.contains)) {
        throw ArgumentError.value(
          categoryIds,
          'categoryIds',
          'Ordering must include each active category exactly once.',
        );
      }

      final beforeById = <String, ExerciseCategoryRow>{
        for (final row in activeRows) row.id: row,
      };
      for (var index = 0; index < categoryIds.length; index += 1) {
        final id = categoryIds[index];
        final before = beforeById[id]!;
        if (before.sortOrder == index) {
          continue;
        }
        await (_database.update(_database.exerciseCategories)
              ..where((row) => row.id.equals(id)))
            .write(
          ExerciseCategoriesCompanion(
            sortOrder: Value<int>(index),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        final after = await _requireCategoryRow(id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.exerciseCategoriesTable,
          entityId: id,
          beforeImage: _exerciseCategoryImage(before),
          afterImage: _exerciseCategoryImage(after),
        );
      }
    });
  }

  Future<void> alphabetizeCategories({
    String actor = 'app',
    String? batchId,
  }) async {
    final categories = await listCategories(ordering: CategoryOrdering.name);
    await reorderCategories(
      categories.map((category) => category.id).toList(growable: false),
      actor: actor,
      batchId: batchId,
    );
  }

  Future<void> archiveCategory(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireCategoryRow(id);
      final activeMemberCount = await _activeCategoryMemberCount(id);
      if (activeMemberCount > 0) {
        throw CategoryHasActiveExercisesException(
          categoryId: id,
          activeExerciseCount: activeMemberCount,
        );
      }
      await (_database.update(_database.exerciseCategories)
            ..where((row) => row.id.equals(id)))
          .write(
        ExerciseCategoriesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireCategoryRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exerciseCategoriesTable,
        entityId: id,
        beforeImage: _exerciseCategoryImage(before),
        afterImage: _exerciseCategoryImage(after),
      );
    });
  }

  Stream<List<ExerciseCatalogSectionRecord>> watchMergedCatalog() {
    late final StreamSubscription<List<ExerciseCategoryRow>>
        categorySubscription;
    late final StreamSubscription<List<ExerciseRow>> exerciseSubscription;

    final controller = StreamController<List<ExerciseCatalogSectionRecord>>();
    List<ExerciseCategoryRecord>? latestCategories;
    List<ExerciseRecord>? latestExercises;

    void emitIfReady() {
      final categories = latestCategories;
      final exercises = latestExercises;
      if (categories == null || exercises == null) {
        return;
      }

      controller.add(_catalogSectionsFrom(categories, exercises));
    }

    controller.onListen = () {
      categorySubscription = _activeCategoryQuery().watch().listen(
        (rows) {
          latestCategories =
              rows.map(_exerciseCategoryFromRow).toList(growable: false);
          emitIfReady();
        },
        onError: controller.addError,
      );
      exerciseSubscription = _activeExerciseQuery().watch().listen(
        (rows) {
          latestExercises = rows.map(_exerciseFromRow).toList(growable: false);
          emitIfReady();
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () async {
      await categorySubscription.cancel();
      await exerciseSubscription.cancel();
    };

    return controller.stream;
  }

  SimpleSelectStatement<$ExerciseCategoriesTable, ExerciseCategoryRow>
      _activeCategoryQuery({
    CategoryOrdering ordering = CategoryOrdering.manual,
  }) {
    final query = _database.select(_database.exerciseCategories)
      ..where((row) => row.deletedAt.isNull());
    switch (ordering) {
      case CategoryOrdering.manual:
        query.orderBy([
          (row) => OrderingTerm.asc(row.sortOrder),
          (row) => OrderingTerm.asc(row.name),
        ]);
      case CategoryOrdering.name:
        query.orderBy([
          (row) => OrderingTerm.asc(row.name),
          (row) => OrderingTerm.asc(row.sortOrder),
        ]);
    }
    return query;
  }

  SimpleSelectStatement<$ExercisesTable, ExerciseRow> _activeExerciseQuery() {
    return _database.select(_database.exercises)
      ..where((row) => row.deletedAt.isNull());
  }

  Future<ExerciseCategoryRow> _requireCategoryRow(String id) async {
    final row = await (_database.select(_database.exerciseCategories)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Exercise category not found: $id.');
    }
    return row;
  }

  Future<ExerciseRow> _requireExerciseRow(String id) async {
    final row = await (_database.select(_database.exercises)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Exercise not found: $id.');
    }
    return row;
  }

  /// Applies a pulled `ExerciseCategory`/`Exercise` sync image: upserts the
  /// opaque row via `insertOnConflictUpdate` (stamping the source device +
  /// previously-synced) and appends a sync-acknowledged Activity Log entry so
  /// the overwritten value is recoverable (undo/recovery). Only
  /// User Library rows (and user customizations of a Platform exercise, i.e. a
  /// shadowing copy per) ever reach this path — the Platform Library
  /// is a deterministic bundled seed and never syncs.
  static const _syncEntityTables = <String>{
    AppDatabase.exerciseCategoriesTable,
    AppDatabase.exercisesTable,
  };

  Future<void> applySyncImage({
    required String entityTable,
    required Map<String, Object?> image,
    required String deviceId,
    required String batchId,
    String actor = 'sync',
    String? activityLogId,
    Map<String, Object?>? activityBeforeImage,
    Map<String, Object?>? activityAfterImage,
    DateTime? activityOccurredAt,
  }) {
    if (!_syncEntityTables.contains(entityTable)) {
      throw ArgumentError.value(
        entityTable,
        'entityTable',
        'Unsupported catalog sync entity.',
      );
    }
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final id = _activityRequiredString(image, 'id');
      final localBeforeImage = await _catalogSyncImageFor(
        entityTable: entityTable,
        entityId: id,
      );

      switch (entityTable) {
        case AppDatabase.exerciseCategoriesTable:
          await _database
              .into(_database.exerciseCategories)
              .insertOnConflictUpdate(
                _exerciseCategorySyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
        case AppDatabase.exercisesTable:
          await _database.into(_database.exercises).insertOnConflictUpdate(
                _exerciseSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
      }

      final localAfterImage = await _catalogSyncImageFor(
        entityTable: entityTable,
        entityId: id,
      );
      if (localAfterImage == null ||
          (localBeforeImage != null &&
              _activityImagesEqual(localBeforeImage, localAfterImage))) {
        return;
      }

      await _repositories.activityLog._append(
        context,
        entityTable: entityTable,
        entityId: id,
        beforeImage: activityBeforeImage ?? localBeforeImage,
        afterImage: activityAfterImage ?? localAfterImage,
        id: activityLogId,
        occurredAt: activityOccurredAt,
        syncAcknowledgedAt: context.timestamp,
      );
    });
  }

  Future<Map<String, Object?>?> _catalogSyncImageFor({
    required String entityTable,
    required String entityId,
  }) async {
    switch (entityTable) {
      case AppDatabase.exerciseCategoriesTable:
        final row = await (_database.select(_database.exerciseCategories)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _exerciseCategoryImage(row);
      case AppDatabase.exercisesTable:
        final row = await (_database.select(_database.exercises)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _exerciseImage(row);
      default:
        throw ArgumentError.value(
          entityTable,
          'entityTable',
          'Unsupported catalog sync entity.',
        );
    }
  }

  Future<String> _createCategory(
    ExerciseCategoryDraft draft,
    _WriteContext context,
  ) async {
    await _ensureUniqueActiveCategoryName(draft.name);
    final activeRows = await _activeCategoryQuery().get();
    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.exerciseCategories).insert(
          ExerciseCategoriesCompanion.insert(
            id: id,
            name: _normalizeCategoryNameForStorage(draft.name),
            sortOrder: _nextSortOrder(activeRows),
            colorHex: _normalizeColorHex(
              draft.colorHex ?? _nextCategoryColor(activeRows.length),
            ),
            updatedAt: context.timestamp,
          ),
        );

    final after = await _requireCategoryRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.exerciseCategoriesTable,
      entityId: id,
      beforeImage: null,
      afterImage: _exerciseCategoryImage(after),
    );

    return id;
  }

  Future<void> _ensureUniqueActiveCategoryName(
    String name, {
    String? exceptId,
  }) async {
    final normalizedName = _normalizeCategoryName(name);
    final rows = await _activeCategoryQuery().get();
    final duplicate = rows.any(
      (row) =>
          row.id != exceptId &&
          _normalizeCategoryName(row.name) == normalizedName,
    );
    if (duplicate) {
      throw DuplicateExerciseCategoryNameException(name);
    }
  }

  Future<int> _activeCategoryMemberCount(String categoryId) async {
    final rows = await (_database.select(_database.exercises)
          ..where(
            (row) => row.deletedAt.isNull() & row.categoryId.equals(categoryId),
          ))
        .get();
    return rows.length;
  }
}

class ExerciseRepository {
  const ExerciseRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<String> create(
    ExerciseDraft draft, {
    String actor = 'app',
    String? batchId,
  }) async {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    final row = await _database.transaction(() => _create(draft, context));
    return row.id;
  }

  Future<ExerciseRecord> createRecord(
    ExerciseDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final row = await _create(draft, context);
      return _exerciseFromRow(row);
    });
  }

  Future<void> update(
    String id,
    ExerciseDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      _ensureUserEditable(before);
      await _ensureUniqueActiveUserName(draft.name, exceptId: id);
      await (_database.update(_database.exercises)
            ..where((row) => row.id.equals(id)))
          .write(
        ExercisesCompanion(
          name: Value<String>(_normalizeExerciseNameForStorage(draft.name)),
          dimensionIds: Value<String>(_encodeDimensions(draft.type)),
          defaultLoadUnit: Value<String>(draft.defaultLoadUnit.name),
          loadMode: Value<String>(draft.effectiveLoadMode.name),
          recordProfile: Value<String>(draft.effectiveRecordProfile.name),
          isUnilateral: Value<bool>(draft.isUnilateral),
          usesRpe: Value<bool>(draft.usesRpe),
          categoryId: Value<String?>(draft.categoryId),
          equipmentIds: Value<String>(_encodeEquipment(draft.equipment)),
          notes: Value<String?>(draft.notes),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exercisesTable,
        entityId: id,
        beforeImage: _exerciseImage(before),
        afterImage: _exerciseImage(after),
      );
    });
  }

  Future<void> rename(
    String id, {
    required String name,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      _ensureUserEditable(before);
      await _ensureUniqueActiveUserName(name, exceptId: id);
      await (_database.update(_database.exercises)
            ..where((row) => row.id.equals(id)))
          .write(
        ExercisesCompanion(
          name: Value<String>(_normalizeExerciseNameForStorage(name)),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exercisesTable,
        entityId: id,
        beforeImage: _exerciseImage(before),
        afterImage: _exerciseImage(after),
      );
    });
  }

  Future<void> softDelete(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      _ensureUserEditable(before);
      await (_database.update(_database.exercises)
            ..where((row) => row.id.equals(id)))
          .write(
        ExercisesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exercisesTable,
        entityId: id,
        beforeImage: _exerciseImage(before),
        afterImage: _exerciseImage(after),
      );
    });
  }

  Future<void> restore(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      _ensureUserEditable(before);
      if (before.deletedAt == null) {
        return;
      }
      await _ensureUniqueActiveUserName(before.name, exceptId: id);
      await (_database.update(_database.exercises)
            ..where((row) => row.id.equals(id)))
          .write(
        ExercisesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: const Value<DateTime?>(null),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exercisesTable,
        entityId: id,
        beforeImage: _exerciseImage(before),
        afterImage: _exerciseImage(after),
      );
    });
  }

  Future<void> setFavorite(
    String id, {
    required bool isFavorite,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      if (before.isFavorite == isFavorite) {
        return;
      }
      await (_database.update(_database.exercises)
            ..where((row) => row.id.equals(id)))
          .write(
        ExercisesCompanion(
          isFavorite: Value<bool>(isFavorite),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exercisesTable,
        entityId: id,
        beforeImage: _exerciseImage(before),
        afterImage: _exerciseImage(after),
      );
    });
  }

  Future<String> customizePlatformExercise(
    String id, {
    ExerciseDraft? draft,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final platform = await _requireRow(id);
      if (platform.libraryOrigin != ExerciseLibraryOrigin.platform.name ||
          platform.deletedAt != null) {
        throw UnsupportedError(
          'Only active platform exercises can be customized.',
        );
      }
      final customization = draft ??
          ExerciseDraft(
            name: platform.name,
            type: _decodeDimensions(platform.dimensionIds),
            defaultLoadUnit: TrainingUnit.values.byName(
              platform.defaultLoadUnit,
            ),
            loadMode: ExerciseLoadMode.values.byName(platform.loadMode),
            recordProfile: RecordProfile.values.byName(
              platform.recordProfile,
            ),
            isUnilateral: platform.isUnilateral,
            usesRpe: platform.usesRpe,
            categoryId: platform.categoryId,
            equipment: _decodeEquipment(platform.equipmentIds),
            notes: platform.notes,
          );
      await _ensureUniqueActiveUserName(customization.name);

      final copyId = _repositories.createId(context.timestamp);
      await _database.into(_database.exercises).insert(
            ExercisesCompanion.insert(
              id: copyId,
              libraryOrigin: Value<String>(ExerciseLibraryOrigin.user.name),
              name: _normalizeExerciseNameForStorage(customization.name),
              dimensionIds: _encodeDimensions(customization.type),
              defaultLoadUnit: Value<String>(
                customization.defaultLoadUnit.name,
              ),
              loadMode: Value<String>(customization.effectiveLoadMode.name),
              recordProfile: Value<String>(
                customization.effectiveRecordProfile.name,
              ),
              isUnilateral: Value<bool>(customization.isUnilateral),
              usesRpe: Value<bool>(customization.usesRpe),
              isFavorite: Value<bool>(platform.isFavorite),
              categoryId: Value<String?>(customization.categoryId),
              equipmentIds: Value<String>(
                _encodeEquipment(customization.equipment),
              ),
              notes: Value<String?>(customization.notes),
              updatedAt: context.timestamp,
            ),
          );

      final after = await _requireRow(copyId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exercisesTable,
        entityId: copyId,
        beforeImage: null,
        afterImage: _exerciseImage(after),
      );

      return copyId;
    });
  }

  Future<void> restorePlatformVersion(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      _ensureUserEditable(before);
      if (before.deletedAt != null) {
        return;
      }
      if (!await _shadowsActivePlatformExercise(before)) {
        throw UnsupportedError(
          'Only active customized exercises can restore the platform version.',
        );
      }

      await (_database.update(_database.exercises)
            ..where((row) => row.id.equals(id)))
          .write(
        ExercisesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exercisesTable,
        entityId: id,
        beforeImage: _exerciseImage(before),
        afterImage: _exerciseImage(after),
      );
    });
  }

  Future<List<ExerciseRecord>> listActive() async {
    final query = _activeExerciseQuery();
    final rows = await query.get();
    return rows.map(_exerciseFromRow).toList(growable: false);
  }

  Future<List<ExerciseRecord>> listActiveByIds(Set<String> ids) async {
    if (ids.isEmpty) {
      return const <ExerciseRecord>[];
    }

    final rows = await _activeExerciseQuery(ids: ids).get();
    return rows.map(_exerciseFromRow).toList(growable: false);
  }

  Future<ExerciseRecord?> getById(String id) async {
    final row = await (_database.select(_database.exercises)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _exerciseFromRow(row);
  }

  Future<List<ExerciseRecord>> listArchivedUser() async {
    final rows = await (_database.select(_database.exercises)
          ..where(
            (row) =>
                row.deletedAt.isNotNull() &
                row.libraryOrigin.equals(ExerciseLibraryOrigin.user.name),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.name)]))
        .get();
    return rows.map(_exerciseFromRow).toList(growable: false);
  }

  Stream<List<ExerciseRecord>> watchActive() {
    return _activeExerciseQuery().watch().map(
          (rows) => rows.map(_exerciseFromRow).toList(growable: false),
        );
  }

  Stream<List<ExerciseRecord>> watchActiveByIds(Set<String> ids) {
    if (ids.isEmpty) {
      return Stream<List<ExerciseRecord>>.value(const <ExerciseRecord>[]);
    }

    return _activeExerciseQuery(ids: ids).watch().map(
          (rows) => rows.map(_exerciseFromRow).toList(growable: false),
        );
  }

  SimpleSelectStatement<$ExercisesTable, ExerciseRow> _activeExerciseQuery({
    Set<String>? ids,
  }) {
    return _database.select(_database.exercises)
      ..where((row) {
        var predicate = row.deletedAt.isNull();
        if (ids != null) {
          predicate = predicate & row.id.isIn(ids);
        }
        return predicate;
      })
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
  }

  Future<ExerciseRow> _create(
    ExerciseDraft draft,
    _WriteContext context,
  ) async {
    await _ensureUniqueActiveUserName(draft.name);
    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.exercises).insert(
          ExercisesCompanion.insert(
            id: id,
            libraryOrigin: Value<String>(ExerciseLibraryOrigin.user.name),
            name: _normalizeExerciseNameForStorage(draft.name),
            dimensionIds: _encodeDimensions(draft.type),
            defaultLoadUnit: Value<String>(draft.defaultLoadUnit.name),
            loadMode: Value<String>(draft.effectiveLoadMode.name),
            recordProfile: Value<String>(draft.effectiveRecordProfile.name),
            isUnilateral: Value<bool>(draft.isUnilateral),
            usesRpe: Value<bool>(draft.usesRpe),
            categoryId: Value<String?>(draft.categoryId),
            equipmentIds: Value<String>(_encodeEquipment(draft.equipment)),
            notes: Value<String?>(draft.notes),
            updatedAt: context.timestamp,
          ),
        );

    final after = await _requireRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.exercisesTable,
      entityId: id,
      beforeImage: null,
      afterImage: _exerciseImage(after),
    );

    return after;
  }

  Future<ExerciseRow> _requireRow(String id) async {
    final row = await (_database.select(_database.exercises)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Exercise not found: $id.');
    }
    return row;
  }

  void _ensureUserEditable(ExerciseRow row) {
    if (row.libraryOrigin == ExerciseLibraryOrigin.platform.name) {
      throw UnsupportedError('Platform exercises are read-only.');
    }
  }

  Future<bool> _shadowsActivePlatformExercise(ExerciseRow row) async {
    if (row.libraryOrigin != ExerciseLibraryOrigin.user.name ||
        row.deletedAt != null) {
      return false;
    }

    final platformRows = await (_database.select(_database.exercises)
          ..where(
            (exercise) =>
                exercise.deletedAt.isNull() &
                exercise.libraryOrigin.equals(
                  ExerciseLibraryOrigin.platform.name,
                ),
          ))
        .get();
    final normalizedName = _normalizeExerciseName(row.name);
    return platformRows.any(
      (platform) => _normalizeExerciseName(platform.name) == normalizedName,
    );
  }

  Future<void> _ensureUniqueActiveUserName(
    String name, {
    String? exceptId,
  }) async {
    final normalizedName = _normalizeExerciseName(name);
    final rows = await (_database.select(_database.exercises)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.libraryOrigin.equals(ExerciseLibraryOrigin.user.name),
          ))
        .get();

    final duplicate = rows.any(
      (row) =>
          row.id != exceptId &&
          _normalizeExerciseName(row.name) == normalizedName,
    );
    if (duplicate) {
      throw DuplicateExerciseNameException(name);
    }
  }
}

class WorkoutSessionRepository {
  const WorkoutSessionRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<String> create(
    WorkoutSessionDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() => _create(draft, context));
  }

  Future<void> updateEndedAt(
    String id, {
    DateTime? endedAt,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      final normalizedEndedAt = endedAt?.toUtc();
      if (normalizedEndedAt != null &&
          normalizedEndedAt.isBefore(before.startedAt)) {
        throw ArgumentError.value(
          endedAt,
          'endedAt',
          'Workout finish time cannot be before the start time.',
        );
      }
      if (before.endedAt == normalizedEndedAt) {
        return;
      }
      await (_database.update(_database.workoutSessions)
            ..where((row) => row.id.equals(id)))
          .write(
        WorkoutSessionsCompanion(
          endedAt: Value<DateTime?>(normalizedEndedAt),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.workoutSessionsTable,
        entityId: id,
        beforeImage: _workoutSessionImage(before),
        afterImage: _workoutSessionImage(after),
      );
    });
  }

  Future<List<AutoFinishedWorkoutRecord>> autoFinishStaleOpenWorkouts({
    required Duration idleThreshold,
    required DateTime now,
    DateTime? lastInteractionAt,
    String actor = 'app.autoFinish',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    final normalizedNow = now.toUtc();
    final normalizedLastInteractionAt = lastInteractionAt?.toUtc();

    return _database.transaction(() async {
      final openWorkouts = await (_database.select(_database.workoutSessions)
            ..where(
              (row) =>
                  row.deletedAt.isNull() &
                  row.endedAt.isNull() &
                  row.startedAt.isSmallerOrEqualValue(normalizedNow),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.startedAt)]))
          .get();

      final finished = <AutoFinishedWorkoutRecord>[];
      for (final before in openWorkouts) {
        final lastWorkoutActivityAt = await _latestWorkoutActivityAt(before);
        var effectiveLastInteractionAt = lastWorkoutActivityAt;
        if (normalizedLastInteractionAt != null &&
            !normalizedLastInteractionAt.isBefore(before.startedAt) &&
            !normalizedLastInteractionAt.isAfter(normalizedNow) &&
            normalizedLastInteractionAt.isAfter(effectiveLastInteractionAt)) {
          effectiveLastInteractionAt = normalizedLastInteractionAt;
        }

        final endedAt = effectiveLastInteractionAt.add(idleThreshold);
        if (endedAt.isAfter(normalizedNow)) {
          continue;
        }

        await (_database.update(_database.workoutSessions)
              ..where((row) => row.id.equals(before.id)))
            .write(
          WorkoutSessionsCompanion(
            endedAt: Value<DateTime?>(endedAt),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        final after = await _requireRow(before.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.workoutSessionsTable,
          entityId: before.id,
          beforeImage: _workoutSessionImage(before),
          afterImage: _workoutSessionImage(after),
        );
        finished.add(
          AutoFinishedWorkoutRecord(
            workoutId: before.id,
            lastInteractionAt: effectiveLastInteractionAt,
            endedAt: endedAt,
          ),
        );
      }
      return finished;
    });
  }

  Future<void> updateStartedAt(
    String id, {
    required DateTime startedAt,
    required TrainingDayDate localDate,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      final normalizedStartedAt = startedAt.toUtc();
      if (before.endedAt != null &&
          before.endedAt!.isBefore(normalizedStartedAt)) {
        throw ArgumentError.value(
          startedAt,
          'startedAt',
          'Workout start time cannot be after the finish time.',
        );
      }
      if (before.startedAt == normalizedStartedAt &&
          before.localDate == localDate.storageValue) {
        return;
      }

      await (_database.update(_database.workoutSessions)
            ..where((row) => row.id.equals(id)))
          .write(
        WorkoutSessionsCompanion(
          startedAt: Value<DateTime>(normalizedStartedAt),
          localDate: Value<String>(localDate.storageValue),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.workoutSessionsTable,
        entityId: id,
        beforeImage: _workoutSessionImage(before),
        afterImage: _workoutSessionImage(after),
      );
    });
  }

  Future<void> updateComment(
    String id, {
    String? comment,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    final normalizedComment = _normalizeWorkoutComment(comment);

    return _database.transaction(() async {
      final before = await _requireRow(id);
      if (before.comment == normalizedComment) {
        return;
      }

      await (_database.update(_database.workoutSessions)
            ..where((row) => row.id.equals(id)))
          .write(
        WorkoutSessionsCompanion(
          comment: Value<String?>(normalizedComment),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.workoutSessionsTable,
        entityId: id,
        beforeImage: _workoutSessionImage(before),
        afterImage: _workoutSessionImage(after),
      );
    });
  }

  Future<void> moveToTrainingDay(
    String id, {
    required TrainingDayDate localDate,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      if (before.localDate == localDate.storageValue) {
        return;
      }

      await (_database.update(_database.workoutSessions)
            ..where((row) => row.id.equals(id)))
          .write(
        WorkoutSessionsCompanion(
          localDate: Value<String>(localDate.storageValue),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.workoutSessionsTable,
        entityId: id,
        beforeImage: _workoutSessionImage(before),
        afterImage: _workoutSessionImage(after),
      );
    });
  }

  Future<String> copyWorkout(
    String id, {
    required TrainingDayDate localDate,
    DateTime? now,
    String? timezone,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final source = await _requireRow(id);
      if (source.deletedAt != null) {
        throw StateError('Workout session is deleted: $id.');
      }

      final sourceWorkoutExercises = await _repositories.workoutExercises
          ._activeWorkoutExerciseQuery(workoutId: id)
          .get();
      final sourceSets =
          await _repositories.sets._activeLoggedSetQuery(workoutId: id).get();
      final copyStartedAt =
          localDate.atLocalTimeOf((now ?? DateTime.now()).toLocal()).toUtc();
      final sourceDuration = source.endedAt?.difference(source.startedAt);
      final copyEndedAt =
          sourceDuration == null ? null : copyStartedAt.add(sourceDuration);
      final copyId = _repositories.createId(context.timestamp);

      await _database.into(_database.workoutSessions).insert(
            WorkoutSessionsCompanion.insert(
              id: copyId,
              startedAt: copyStartedAt,
              timezone: timezone ?? source.timezone,
              localDate: Value<String>(localDate.storageValue),
              endedAt: Value<DateTime?>(copyEndedAt),
              comment: Value<String?>(source.comment),
              updatedAt: context.timestamp,
            ),
          );
      final copiedWorkout = await _requireRow(copyId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.workoutSessionsTable,
        entityId: copyId,
        beforeImage: null,
        afterImage: _workoutSessionImage(copiedWorkout),
      );

      for (final sourceWorkoutExercise in sourceWorkoutExercises) {
        final copyWorkoutExerciseId = _repositories.createId(context.timestamp);
        await _database.into(_database.workoutExercises).insert(
              WorkoutExercisesCompanion.insert(
                id: copyWorkoutExerciseId,
                workoutId: copyId,
                exerciseId: sourceWorkoutExercise.exerciseId,
                position: sourceWorkoutExercise.position,
                updatedAt: context.timestamp,
              ),
            );
        final after = await _repositories.workoutExercises
            ._requireRow(copyWorkoutExerciseId);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.workoutExercisesTable,
          entityId: copyWorkoutExerciseId,
          beforeImage: null,
          afterImage: _workoutExerciseImage(after),
        );
      }

      for (final sourceSet in sourceSets) {
        final copySetId = _repositories.createId(context.timestamp);
        await _database.into(_database.loggedSets).insert(
              _loggedSetInsertCompanion(
                id: copySetId,
                workoutId: copyId,
                exerciseId: sourceSet.exerciseId,
                position: sourceSet.position,
                isCompleted: sourceSet.isCompleted,
                columns: _loggedSetColumnsFromRow(sourceSet),
                plannedRestAfter: sourceSet.plannedRestAfter == null
                    ? null
                    : Duration(seconds: sourceSet.plannedRestAfter!),
                performedAt: sourceSet.performedAt,
                comment: sourceSet.comment,
                side: sourceSet.side == null
                    ? null
                    : SetSide.values.byName(sourceSet.side!),
                rpe: sourceSet.rpe,
                updatedAt: context.timestamp,
              ),
            );
        final after = await _repositories.sets._requireRow(copySetId);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.loggedSetsTable,
          entityId: copySetId,
          beforeImage: null,
          afterImage: _loggedSetImage(after),
        );
      }

      return copyId;
    });
  }

  Future<String> shareSummary(String id) async {
    final workout = await _requireRow(id);
    if (workout.deletedAt != null) {
      throw StateError('Workout session is deleted: $id.');
    }

    final workoutExercises = await _repositories.workoutExercises
        ._activeWorkoutExerciseQuery(workoutId: id)
        .get();
    final sets =
        await _repositories.sets._activeLoggedSetQuery(workoutId: id).get();
    final exerciseIds = <String>{
      for (final workoutExercise in workoutExercises)
        workoutExercise.exerciseId,
      for (final set in sets) set.exerciseId,
    };
    final exerciseRows = exerciseIds.isEmpty
        ? <ExerciseRow>[]
        : await (_database.select(_database.exercises)
              ..where((row) => row.id.isIn(exerciseIds)))
            .get();
    final exercisesById = <String, ExerciseRecord>{
      for (final row in exerciseRows) row.id: _exerciseFromRow(row),
    };

    return _workoutShareSummary(
      workout: _workoutSessionFromRow(workout),
      workoutExercises:
          workoutExercises.map(_workoutExerciseFromRow).toList(growable: false),
      sets: sets.map(_loggedSetFromRow).toList(growable: false),
      exercisesById: exercisesById,
    );
  }

  Future<void> softDelete(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      if (before.deletedAt != null) {
        return;
      }

      await _softDeleteWorkoutChildren(id, context);
      await (_database.update(_database.workoutSessions)
            ..where((row) => row.id.equals(id)))
          .write(
        WorkoutSessionsCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.workoutSessionsTable,
        entityId: id,
        beforeImage: _workoutSessionImage(before),
        afterImage: _workoutSessionImage(after),
      );
    });
  }

  Future<List<WorkoutSessionRecord>> listActive() async {
    final query = _activeWorkoutSessionQuery();
    final rows = await query.get();
    return rows.map(_workoutSessionFromRow).toList(growable: false);
  }

  Future<List<WorkoutSessionRecord>> listActiveByIds(Set<String> ids) async {
    if (ids.isEmpty) {
      return const <WorkoutSessionRecord>[];
    }

    final rows = await _activeWorkoutSessionQuery(ids: ids).get();
    return rows.map(_workoutSessionFromRow).toList(growable: false);
  }

  Future<WorkoutSessionRecord?> getById(String id) async {
    final row = await (_database.select(_database.workoutSessions)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _workoutSessionFromRow(row);
  }

  Future<List<WorkoutSessionRecord>> listActiveForLocalDate(
    TrainingDayDate localDate,
  ) async {
    final rows = await _activeWorkoutSessionQuery(localDate: localDate).get();
    return rows.map(_workoutSessionFromRow).toList(growable: false);
  }

  Stream<List<WorkoutSessionRecord>> watchActive() {
    return _activeWorkoutSessionQuery().watch().map(
          (rows) => rows.map(_workoutSessionFromRow).toList(growable: false),
        );
  }

  Stream<List<WorkoutSessionRecord>> watchActiveByIds(Set<String> ids) {
    if (ids.isEmpty) {
      return Stream<List<WorkoutSessionRecord>>.value(
        const <WorkoutSessionRecord>[],
      );
    }

    return _activeWorkoutSessionQuery(ids: ids).watch().map(
          (rows) => rows.map(_workoutSessionFromRow).toList(growable: false),
        );
  }

  Stream<List<WorkoutSessionRecord>> watchActiveForLocalDate(
    TrainingDayDate localDate,
  ) {
    return _activeWorkoutSessionQuery(localDate: localDate).watch().map(
          (rows) => rows.map(_workoutSessionFromRow).toList(growable: false),
        );
  }

  SimpleSelectStatement<$WorkoutSessionsTable, WorkoutSessionRow>
      _activeWorkoutSessionQuery({
    TrainingDayDate? localDate,
    Set<String>? ids,
  }) {
    final query = _database.select(_database.workoutSessions)
      ..where((row) {
        var predicate = row.deletedAt.isNull();
        if (localDate != null) {
          predicate = predicate & row.localDate.equals(localDate.storageValue);
        }
        if (ids != null) {
          predicate = predicate & row.id.isIn(ids);
        }
        return predicate;
      })
      ..orderBy([(row) => OrderingTerm.asc(row.startedAt)]);
    return query;
  }

  Future<DateTime> _latestWorkoutActivityAt(WorkoutSessionRow workout) async {
    var latest = workout.updatedAt.isAfter(workout.startedAt)
        ? workout.updatedAt
        : workout.startedAt;

    void include(DateTime value) {
      if (value.isAfter(latest)) {
        latest = value;
      }
    }

    for (final row in await (_database.select(_database.workoutExercises)
          ..where((row) => row.workoutId.equals(workout.id)))
        .get()) {
      include(row.updatedAt);
    }
    for (final row in await (_database.select(_database.exerciseGroups)
          ..where((row) => row.workoutId.equals(workout.id)))
        .get()) {
      include(row.updatedAt);
    }
    for (final row in await (_database.select(_database.loggedSets)
          ..where((row) => row.workoutId.equals(workout.id)))
        .get()) {
      include(row.updatedAt);
    }
    for (final row in await (_database.select(_database.restTimers)
          ..where((row) => row.workoutId.equals(workout.id)))
        .get()) {
      include(row.updatedAt);
      include(row.deadlineAt);
    }
    for (final row in await (_database.select(_database.intervalTimers)
          ..where((row) => row.workoutId.equals(workout.id)))
        .get()) {
      include(row.updatedAt);
      include(row.deadlineAt);
    }

    return latest.toUtc();
  }

  Future<String> _create(
    WorkoutSessionDraft draft,
    _WriteContext context,
  ) async {
    final id = _repositories.createId(context.timestamp);
    final localDate =
        draft.localDate ?? TrainingDayDate.fromDateTime(draft.startedAt);
    await _database.into(_database.workoutSessions).insert(
          WorkoutSessionsCompanion.insert(
            id: id,
            startedAt: draft.startedAt.toUtc(),
            timezone: draft.timezone,
            localDate: Value<String>(localDate.storageValue),
            endedAt: Value<DateTime?>(draft.endedAt?.toUtc()),
            comment: Value<String?>(_normalizeWorkoutComment(draft.comment)),
            updatedAt: context.timestamp,
          ),
        );

    final after = await _requireRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.workoutSessionsTable,
      entityId: id,
      beforeImage: null,
      afterImage: _workoutSessionImage(after),
    );

    return id;
  }

  Future<void> _softDeleteWorkoutChildren(
    String workoutId,
    _WriteContext context,
  ) async {
    final restTimers = await (_database.select(_database.restTimers)
          ..where(
            (row) => row.deletedAt.isNull() & row.workoutId.equals(workoutId),
          ))
        .get();
    for (final timer in restTimers) {
      await _repositories.restTimers._writeCanceled(timer, context);
    }

    final intervalTimers = await (_database.select(_database.intervalTimers)
          ..where(
            (row) => row.deletedAt.isNull() & row.workoutId.equals(workoutId),
          ))
        .get();
    for (final before in intervalTimers) {
      if (before.status == 'canceled') {
        continue;
      }
      await (_database.update(_database.intervalTimers)
            ..where((row) => row.id.equals(before.id)))
          .write(
        IntervalTimersCompanion(
          status: const Value<String>('canceled'),
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await (_database.select(_database.intervalTimers)
            ..where((row) => row.id.equals(before.id)))
          .getSingle();
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.intervalTimersTable,
        entityId: before.id,
        beforeImage: _intervalTimerImage(before),
        afterImage: _intervalTimerImage(after),
      );
    }

    final groups = await _repositories.exerciseGroups
        ._activeExerciseGroupQuery(workoutId: workoutId)
        .get();
    for (final group in groups) {
      await _repositories.exerciseGroups._softDeleteGroup(group.id, context);
    }

    final workoutExercises = await _repositories.workoutExercises
        ._activeWorkoutExerciseQuery(workoutId: workoutId)
        .get();
    for (final workoutExercise in workoutExercises) {
      await _softDeleteWorkoutExercise(workoutExercise, context);
    }

    final sets = await _repositories.sets
        ._activeLoggedSetQuery(workoutId: workoutId)
        .get();
    for (final set in sets) {
      await _softDeleteLoggedSet(set, context);
    }
  }

  Future<void> _softDeleteExerciseGroupMember(
    ExerciseGroupMemberRow before,
    _WriteContext context,
  ) async {
    await (_database.update(_database.exerciseGroupMembers)
          ..where((row) => row.id.equals(before.id)))
        .write(
      ExerciseGroupMembersCompanion(
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: Value<DateTime?>(context.timestamp),
      ),
    );
    final after = await _repositories.exerciseGroups._requireMemberRow(
      before.id,
    );
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.exerciseGroupMembersTable,
      entityId: before.id,
      beforeImage: _exerciseGroupMemberImage(before),
      afterImage: _exerciseGroupMemberImage(after),
    );
  }

  Future<void> _softDeleteExerciseGroup(
    ExerciseGroupRow before,
    _WriteContext context,
  ) async {
    await (_database.update(_database.exerciseGroups)
          ..where((row) => row.id.equals(before.id)))
        .write(
      ExerciseGroupsCompanion(
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: Value<DateTime?>(context.timestamp),
      ),
    );
    final after = await _repositories.exerciseGroups._requireRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.exerciseGroupsTable,
      entityId: before.id,
      beforeImage: _exerciseGroupImage(before),
      afterImage: _exerciseGroupImage(after),
    );
  }

  Future<void> _softDeleteWorkoutExercise(
    WorkoutExerciseRow before,
    _WriteContext context,
  ) async {
    await (_database.update(_database.workoutExercises)
          ..where((row) => row.id.equals(before.id)))
        .write(
      WorkoutExercisesCompanion(
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: Value<DateTime?>(context.timestamp),
      ),
    );
    final after = await _repositories.workoutExercises._requireRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.workoutExercisesTable,
      entityId: before.id,
      beforeImage: _workoutExerciseImage(before),
      afterImage: _workoutExerciseImage(after),
    );
  }

  Future<void> _softDeleteLoggedSet(
    LoggedSetRow before,
    _WriteContext context,
  ) async {
    await (_database.update(_database.loggedSets)
          ..where((row) => row.id.equals(before.id)))
        .write(
      LoggedSetsCompanion(
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: Value<DateTime?>(context.timestamp),
      ),
    );
    final after = await _repositories.sets._requireRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.loggedSetsTable,
      entityId: before.id,
      beforeImage: _loggedSetImage(before),
      afterImage: _loggedSetImage(after),
    );
  }

  Future<WorkoutSessionRow> _requireRow(String id) async {
    final row = await (_database.select(_database.workoutSessions)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Workout session not found: $id.');
    }
    return row;
  }
}

class PlatformFoodRepository {
  PlatformFoodRepository._(this._usdaFoodSeedSource);

  final UsdaFoodSeedSource _usdaFoodSeedSource;
  Future<UsdaFoodSeed>? _usdaFoodSeed;

  Future<UsdaFoodSeedMetadata> usdaMetadata() async {
    final seed = await _loadUsdaSeed();
    return seed.metadata;
  }

  Future<List<PlatformFoodRecord>> listUsdaFoods() async {
    final seed = await _loadUsdaSeed();
    return seed.foods;
  }

  Future<PlatformFoodRecord?> getUsdaFoodById(String id) async {
    final seed = await _loadUsdaSeed();
    for (final food in seed.foods) {
      if (food.id == id) {
        return food;
      }
    }
    return null;
  }

  Future<List<PlatformFoodRecord>> searchUsdaFoods(
    String query, {
    int limit = 50,
  }) async {
    final seed = await _loadUsdaSeed();
    return seed.foods
        .where((food) => foodNameMatchesQuery(food.name, query))
        .take(limit)
        .toList(growable: false);
  }

  Future<UsdaFoodSeed> _loadUsdaSeed() {
    return _usdaFoodSeed ??= _usdaFoodSeedSource.load();
  }
}

class OpenFoodFactsRepository {
  OpenFoodFactsRepository._(
    this._repositories, {
    required Uri baseUrl,
    required http.Client httpClient,
    required int maxCacheEntries,
    DateTime Function()? clock,
  })  : _baseUrl = baseUrl,
        _httpClient = httpClient,
        _maxCacheEntries = maxCacheEntries,
        _clock = clock ?? DateTime.now;

  final TrainingRepositories _repositories;
  final Uri _baseUrl;
  final http.Client _httpClient;
  final int _maxCacheEntries;
  final DateTime Function() _clock;

  AppDatabase get _database => _repositories.database;

  Future<List<PlatformFoodRecord>> search(
    String query, {
    int limit = 50,
  }) async {
    if (limit <= 0) {
      return const <PlatformFoodRecord>[];
    }
    final food = await lookup(query, limit: limit);
    return food == null
        ? const <PlatformFoodRecord>[]
        : <PlatformFoodRecord>[food];
  }

  Future<PlatformFoodRecord?> lookup(
    String query, {
    int limit = 50,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || limit <= 0) {
      return null;
    }

    final lookupKey = _openFoodFactsLookupKey(normalizedQuery);
    final cached = await _cachedLookup(lookupKey);
    if (cached != null) {
      final accessedAt = _clock().toUtc();
      await (_database.update(_database.openFoodFactsCache)
            ..where((row) => row.lookupKey.equals(lookupKey)))
          .write(
        OpenFoodFactsCacheCompanion(
          lastAccessedAt: Value<DateTime>(accessedAt),
        ),
      );
      return _openFoodFactsRecordFromCacheRow(cached);
    }

    final fetched = await _fetchOpenFoodFacts(normalizedQuery, limit: limit);
    if (fetched == null) {
      return null;
    }

    final timestamp = _clock().toUtc();
    await _database.into(_database.openFoodFactsCache).insertOnConflictUpdate(
          OpenFoodFactsCacheCompanion.insert(
            lookupKey: lookupKey,
            foodId: fetched.id,
            name: fetched.name,
            nutrientValuesJson: fetched.nutrientsPer100.toJsonString(),
            isLiquid: Value<bool>(fetched.isLiquid),
            servingLabel: Value<String?>(fetched.servingLabel),
            servingSize: Value<double?>(fetched.servingSize),
            packageSize: Value<double?>(fetched.packageSize),
            fetchedAt: timestamp,
            lastAccessedAt: timestamp,
          ),
        );
    await _enforceCacheLimit();

    return fetched;
  }

  Future<OpenFoodFactsCacheRow?> _cachedLookup(String lookupKey) {
    return (_database.select(_database.openFoodFactsCache)
          ..where((row) => row.lookupKey.equals(lookupKey)))
        .getSingleOrNull();
  }

  Future<PlatformFoodRecord?> _fetchOpenFoodFacts(
    String query, {
    required int limit,
  }) async {
    final barcode = _openFoodFactsBarcode(query);
    final uri = barcode == null
        ? _baseUrl.resolve('/cgi/search.pl').replace(
            queryParameters: <String, String>{
              'search_terms': query,
              'search_simple': '1',
              'action': 'process',
              'json': '1',
              'page_size': limit.toString(),
              'fields':
                  'code,product_name,generic_name,nutriments,serving_quantity,serving_quantity_unit,serving_size,product_quantity,product_quantity_unit,quantity,categories_tags',
            },
          )
        : _baseUrl.resolve('/api/v2/product/$barcode.json').replace(
            queryParameters: const <String, String>{
              'fields':
                  'code,product_name,generic_name,nutriments,serving_quantity,serving_quantity_unit,serving_size,product_quantity,product_quantity_unit,quantity,categories_tags',
            },
          );
    final response = await _httpClient.get(
      uri,
      headers: const <String, String>{'accept': 'application/json'},
    );
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Open Food Facts lookup failed with HTTP ${response.statusCode}.',
        uri,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw FormatException('Expected Open Food Facts JSON object.');
    }
    final body = Map<String, Object?>.from(decoded);

    if (barcode != null) {
      if (body['status'] == 0) {
        return null;
      }
      final product = body['product'];
      if (product is! Map) {
        return null;
      }
      return _openFoodFactsRecordFromProduct(
        Map<String, Object?>.from(product),
        fallbackCode: barcode,
      );
    }

    final products = body['products'];
    if (products is! List<Object?>) {
      return null;
    }
    for (final product in products) {
      if (product is! Map) {
        continue;
      }
      final record = _openFoodFactsRecordFromProduct(
        Map<String, Object?>.from(product),
      );
      if (record != null) {
        return record;
      }
    }
    return null;
  }

  Future<void> _enforceCacheLimit() async {
    if (_maxCacheEntries < 0) {
      throw ArgumentError.value(
        _maxCacheEntries,
        'openFoodFactsMaxCacheEntries',
        'Open Food Facts cache size must be non-negative.',
      );
    }
    final query = _database.select(_database.openFoodFactsCache)
      ..orderBy([
        (row) => OrderingTerm.asc(row.lastAccessedAt),
        (row) => OrderingTerm.asc(row.lookupKey),
      ]);
    final rows = await query.get();
    final overflow = rows.length - _maxCacheEntries;
    if (overflow <= 0) {
      return;
    }

    final evictedKeys =
        rows.take(overflow).map((row) => row.lookupKey).toList(growable: false);
    await (_database.delete(_database.openFoodFactsCache)
          ..where((row) => row.lookupKey.isIn(evictedKeys)))
        .go();
  }
}

class NutritionRepository {
  const NutritionRepository._(this._repositories);

  final TrainingRepositories _repositories;

  static const _defaultMealTypes = <_DefaultMealTypeSeed>[
    _DefaultMealTypeSeed(
      id: 'meal-type-breakfast',
      name: 'Breakfast',
      sortOrder: 0,
    ),
    _DefaultMealTypeSeed(
      id: 'meal-type-lunch',
      name: 'Lunch',
      sortOrder: 1,
    ),
    _DefaultMealTypeSeed(
      id: 'meal-type-dinner',
      name: 'Dinner',
      sortOrder: 2,
    ),
    _DefaultMealTypeSeed(
      id: 'meal-type-snack',
      name: 'Snack',
      sortOrder: 3,
    ),
  ];

  AppDatabase get _database => _repositories.database;

  Future<void> applySyncImage({
    required String entityTable,
    required Map<String, Object?> image,
    required String deviceId,
    required String batchId,
    String actor = 'sync',
    String? activityLogId,
    Map<String, Object?>? activityBeforeImage,
    Map<String, Object?>? activityAfterImage,
    DateTime? activityOccurredAt,
  }) {
    if (entityTable != AppDatabase.mealsTable &&
        entityTable != AppDatabase.foodEntriesTable &&
        entityTable != AppDatabase.nutritionGoalsTable &&
        entityTable != AppDatabase.foodsTable &&
        entityTable != AppDatabase.mealTypesTable) {
      throw ArgumentError.value(
        entityTable,
        'entityTable',
        'Unsupported nutrition sync entity.',
      );
    }
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final id = _activityRequiredString(image, 'id');
      final localBeforeImage = await _nutritionSyncImageFor(
        entityTable: entityTable,
        entityId: id,
      );

      switch (entityTable) {
        case AppDatabase.mealsTable:
          await _database.into(_database.meals).insertOnConflictUpdate(
                _mealSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
        case AppDatabase.foodEntriesTable:
          await _database.into(_database.foodEntries).insertOnConflictUpdate(
                _foodEntrySyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
        case AppDatabase.nutritionGoalsTable:
          await _database.into(_database.nutritionGoals).insertOnConflictUpdate(
                _nutritionGoalSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
        case AppDatabase.foodsTable:
          await _database.into(_database.foods).insertOnConflictUpdate(
                _foodSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
        case AppDatabase.mealTypesTable:
          await _database.into(_database.mealTypes).insertOnConflictUpdate(
                _mealTypeSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
      }

      final localAfterImage = await _nutritionSyncImageFor(
        entityTable: entityTable,
        entityId: id,
      );
      if (localAfterImage == null ||
          (localBeforeImage != null &&
              _activityImagesEqual(localBeforeImage, localAfterImage))) {
        return;
      }

      await _repositories.activityLog._append(
        context,
        entityTable: entityTable,
        entityId: id,
        beforeImage: activityBeforeImage ?? localBeforeImage,
        afterImage: activityAfterImage ?? localAfterImage,
        id: activityLogId,
        occurredAt: activityOccurredAt,
        syncAcknowledgedAt: context.timestamp,
      );
    });
  }

  Future<String> createMeal(
    MealDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() => _createMeal(draft, context));
  }

  Future<Map<String, Object?>?> _nutritionSyncImageFor({
    required String entityTable,
    required String entityId,
  }) async {
    switch (entityTable) {
      case AppDatabase.mealsTable:
        final row = await (_database.select(_database.meals)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _mealImage(row);
      case AppDatabase.foodEntriesTable:
        final row = await (_database.select(_database.foodEntries)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _foodEntryImage(row);
      case AppDatabase.nutritionGoalsTable:
        final row = await (_database.select(_database.nutritionGoals)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _nutritionGoalImage(row);
      case AppDatabase.foodsTable:
        final row = await (_database.select(_database.foods)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _foodImage(row);
      case AppDatabase.mealTypesTable:
        final row = await (_database.select(_database.mealTypes)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _mealTypeImage(row);
      default:
        throw ArgumentError.value(
          entityTable,
          'entityTable',
          'Unsupported nutrition sync entity.',
        );
    }
  }

  Future<void> ensureDefaultMealTypes({
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      for (final seed in _defaultMealTypes) {
        final existing = await _mealTypeRowById(seed.id);
        if (existing != null) {
          continue;
        }
        await _database.into(_database.mealTypes).insert(
              MealTypesCompanion.insert(
                id: seed.id,
                name: seed.name,
                sortOrder: seed.sortOrder,
                updatedAt: context.timestamp,
              ),
            );
        final after = await _requireMealTypeRow(seed.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.mealTypesTable,
          entityId: seed.id,
          beforeImage: null,
          afterImage: _mealTypeImage(after),
        );
      }
    });
  }

  Future<String> createMealType(
    MealTypeDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() => _createMealType(draft, context));
  }

  Future<void> updateMealType(
    String id,
    MealTypeDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireMealTypeRow(id);
      await _ensureUniqueActiveMealTypeName(draft.name, exceptId: id);
      await (_database.update(_database.mealTypes)
            ..where((row) => row.id.equals(id)))
          .write(_mealTypeCompanionFromDraft(draft, context.timestamp));
      final after = await _requireMealTypeRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.mealTypesTable,
        entityId: id,
        beforeImage: _mealTypeImage(before),
        afterImage: _mealTypeImage(after),
      );
    });
  }

  Future<void> archiveMealType(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireMealTypeRow(id);
      await (_database.update(_database.mealTypes)
            ..where((row) => row.id.equals(id)))
          .write(
        MealTypesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireMealTypeRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.mealTypesTable,
        entityId: id,
        beforeImage: _mealTypeImage(before),
        afterImage: _mealTypeImage(after),
      );
    });
  }

  Future<void> reorderMealTypes(
    List<String> orderedIds, {
    String actor = 'app',
    String? batchId,
  }) async {
    await ensureDefaultMealTypes(actor: actor);
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final activeRows = await _activeMealTypeQuery().get();
      final activeIds = activeRows.map((row) => row.id).toSet();
      final orderedIdSet = orderedIds.toSet();
      if (orderedIds.length != orderedIdSet.length ||
          orderedIdSet.length != activeIds.length ||
          !activeIds.containsAll(orderedIdSet)) {
        throw ArgumentError.value(
          orderedIds,
          'orderedIds',
          'Meal Type reorder must include each active Meal Type exactly once.',
        );
      }

      final rowsById = <String, MealTypeRow>{
        for (final row in activeRows) row.id: row,
      };
      for (var index = 0; index < orderedIds.length; index += 1) {
        final id = orderedIds[index];
        final before = rowsById[id]!;
        if (before.sortOrder == index) {
          continue;
        }
        await (_database.update(_database.mealTypes)
              ..where((row) => row.id.equals(id)))
            .write(
          MealTypesCompanion(
            sortOrder: Value<int>(index),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        final after = await _requireMealTypeRow(id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.mealTypesTable,
          entityId: id,
          beforeImage: _mealTypeImage(before),
          afterImage: _mealTypeImage(after),
        );
      }
    });
  }

  Future<MealTypeRecord?> getMealTypeById(String id) async {
    final row = await _mealTypeRowById(id);
    return row == null ? null : _mealTypeFromRow(row);
  }

  Future<List<MealTypeRecord>> listMealTypes() async {
    await ensureDefaultMealTypes();
    final rows = await _activeMealTypeQuery().get();
    return rows.map(_mealTypeFromRow).toList(growable: false);
  }

  Stream<List<MealTypeRecord>> watchMealTypes() {
    return Stream<void>.fromFuture(ensureDefaultMealTypes()).asyncExpand((_) {
      return _activeMealTypeQuery().watch();
    }).map(
      (rows) => rows.map(_mealTypeFromRow).toList(growable: false),
    );
  }

  /// Persists one nutrition `Goal` target for a goalable `Nutrient`, upserting
  /// the single active row for that nutrient so it stays a stable LWW row
  /// (UUIDv7, `updated_at`, `deleted_at`) that syncs like the other nutrition
  /// rows (NUTRITION.md §7). The row stores only the configured target — never
  /// a computed total — because totals are derived analytics. The
  /// shared two-tier validator hard-rejects an impossible target before any
  /// write (NUTRITION.md §6); writing is a local transaction that does not
  /// block on the network.
  Future<String> saveNutritionGoal(
    NutritionGoalTarget target, {
    String actor = 'app',
    String? batchId,
  }) {
    validateNutritionGoalTargets(<NutritionGoalTarget>[target])
        .throwIfRejected();
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final existing = await _activeNutritionGoalRowFor(target.nutrient);
      if (existing == null) {
        final id = _repositories.createId(context.timestamp);
        await _database.into(_database.nutritionGoals).insert(
              _nutritionGoalCompanionFromTarget(target, context.timestamp)
                  .copyWith(id: Value<String>(id)),
            );
        final after = await _requireNutritionGoalRow(id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.nutritionGoalsTable,
          entityId: id,
          beforeImage: null,
          afterImage: _nutritionGoalImage(after),
        );
        return id;
      }

      final before = _nutritionGoalImage(existing);
      await (_database.update(_database.nutritionGoals)
            ..where((row) => row.id.equals(existing.id)))
          .write(_nutritionGoalCompanionFromTarget(target, context.timestamp));
      final after = await _requireNutritionGoalRow(existing.id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.nutritionGoalsTable,
        entityId: existing.id,
        beforeImage: before,
        afterImage: _nutritionGoalImage(after),
      );
      return existing.id;
    });
  }

  /// Clears the active nutrition `Goal` for [nutrient] with a normal LWW
  /// soft-delete (tombstone via `deleted_at`); the history survives in the
  /// Activity Log. A no-op when no active goal exists for the nutrient.
  Future<void> clearNutritionGoal(
    NutrientId nutrient, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final existing = await _activeNutritionGoalRowFor(nutrient);
      if (existing == null) {
        return;
      }
      final before = _nutritionGoalImage(existing);
      await (_database.update(_database.nutritionGoals)
            ..where((row) => row.id.equals(existing.id)))
          .write(
        NutritionGoalsCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireNutritionGoalRow(existing.id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.nutritionGoalsTable,
        entityId: existing.id,
        beforeImage: before,
        afterImage: _nutritionGoalImage(after),
      );
    });
  }

  Future<List<NutritionGoalRecord>> listNutritionGoals() async {
    final rows = await _activeNutritionGoalQuery().get();
    return rows.map(_nutritionGoalFromRow).toList(growable: false);
  }

  Stream<List<NutritionGoalRecord>> watchNutritionGoals() {
    return _activeNutritionGoalQuery().watch().map(
          (rows) => rows.map(_nutritionGoalFromRow).toList(growable: false),
        );
  }

  Future<NutritionGoalRecord?> getNutritionGoal(NutrientId nutrient) async {
    final row = await _activeNutritionGoalRowFor(nutrient);
    return row == null ? null : _nutritionGoalFromRow(row);
  }

  SimpleSelectStatement<$NutritionGoalsTable, NutritionGoalRow>
      _activeNutritionGoalQuery() {
    return _database.select(_database.nutritionGoals)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.asc(row.nutrientId)]);
  }

  Future<NutritionGoalRow?> _activeNutritionGoalRowFor(NutrientId nutrient) {
    return (_database.select(_database.nutritionGoals)
          ..where(
            (row) =>
                row.nutrientId.equals(nutrient.storageKey) &
                row.deletedAt.isNull(),
          ))
        .getSingleOrNull();
  }

  Future<NutritionGoalRow> _requireNutritionGoalRow(String id) async {
    final row = await (_database.select(_database.nutritionGoals)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Nutrition Goal not found: $id.');
    }
    return row;
  }

  NutritionGoalsCompanion _nutritionGoalCompanionFromTarget(
    NutritionGoalTarget target,
    DateTime timestamp,
  ) {
    return NutritionGoalsCompanion(
      nutrientId: Value<String>(target.nutrient.storageKey),
      targetValue: Value<double>(target.value),
      targetEntered: Value<String>(target.entered),
      unit: Value<String>(target.unit.name),
      updatedAt: Value<DateTime>(timestamp),
      deletedAt: const Value<DateTime?>(null),
    );
  }

  Future<LogQuickEntryResult> logQuickEntry({
    required MealDraft meal,
    required QuickFoodEntryDraft entry,
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);
    final validation = validateFoodEntryNutrition(nutrients: entry.nutrients);
    validation.throwIfRejected();

    return _database.transaction(() async {
      final mealId = await _createMeal(meal, context);
      final foodEntryId = await _createQuickEntry(
        mealId: mealId,
        draft: entry,
        context: context,
      );
      return LogQuickEntryResult(
        batchId: context.batchId,
        mealId: mealId,
        foodEntryId: foodEntryId,
        warnings: validation.warnings,
      );
    });
  }

  Future<LogQuickEntryResult> logQuickEntryForMeal({
    required String mealId,
    required QuickFoodEntryDraft entry,
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);
    final validation = validateFoodEntryNutrition(nutrients: entry.nutrients);
    validation.throwIfRejected();

    return _database.transaction(() async {
      final foodEntryId = await _createQuickEntry(
        mealId: mealId,
        draft: entry,
        context: context,
      );
      return LogQuickEntryResult(
        batchId: context.batchId,
        mealId: mealId,
        foodEntryId: foodEntryId,
        warnings: validation.warnings,
      );
    });
  }

  Future<String> createUserFood(
    UserFoodDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() => _createUserFood(draft, context));
  }

  Future<String> createRecipe(
    RecipeDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() => _createRecipe(draft, context));
  }

  Future<String> forkUsdaFoodToUserFood(
    String usdaFoodId, {
    UserFoodForkDraft edits = const UserFoodForkDraft(),
    String actor = 'app',
    String? batchId,
  }) async {
    final source = await _repositories.platformFoods.getUsdaFoodById(
      usdaFoodId,
    );
    if (source == null) {
      throw StateError('USDA Food not found: $usdaFoodId.');
    }

    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    final draft = UserFoodDraft(
      name: edits.name ?? source.name,
      nutrientsPer100: edits.nutrientsPer100 ?? source.nutrientsPer100,
      isLiquid: edits.isLiquid ?? source.isLiquid,
      servingLabel: edits.servingLabel ?? source.servingLabel,
      servingSize: edits.servingSize ?? source.servingSize,
      packageSize: edits.packageSize ?? source.packageSize,
    );

    return _database.transaction(() => _createUserFood(draft, context));
  }

  Future<void> updateUserFood(
    String id,
    UserFoodDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireFoodRow(id);
      _ensureUserFood(before);
      _ensureNotRecipe(before);
      await _ensureUniqueActiveUserFoodName(draft.name, exceptId: id);
      await (_database.update(_database.foods)
            ..where((row) => row.id.equals(id)))
          .write(_userFoodCompanionFromDraft(draft, context.timestamp));
      final after = await _requireFoodRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.foodsTable,
        entityId: id,
        beforeImage: _foodImage(before),
        afterImage: _foodImage(after),
      );
    });
  }

  Future<void> archiveUserFood(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireFoodRow(id);
      _ensureUserFood(before);
      await (_database.update(_database.foods)
            ..where((row) => row.id.equals(id)))
          .write(
        FoodsCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireFoodRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.foodsTable,
        entityId: id,
        beforeImage: _foodImage(before),
        afterImage: _foodImage(after),
      );
    });
  }

  Future<LogFoodEntryResult> logFoodEntry({
    required FoodEntryDraft entry,
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final created = await _createFoodEntry(
        draft: entry,
        context: context,
      );
      return LogFoodEntryResult(
        batchId: context.batchId,
        mealId: entry.mealId,
        foodEntryId: created.foodEntryId,
        warnings: created.warnings,
      );
    });
  }

  Future<LogFoodEntryResult> logFoodEntrySnapshot({
    required FoodEntrySnapshotDraft entry,
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final created = await _createFoodEntrySnapshot(
        draft: entry,
        context: context,
      );
      return LogFoodEntryResult(
        batchId: context.batchId,
        mealId: entry.mealId,
        foodEntryId: created.foodEntryId,
        warnings: created.warnings,
      );
    });
  }

  /// Lands a provider-neutral [NutritionImportBatch] at the edge as ONE
  /// reversible Activity Log batch (NUTRITION.md §9; INTEGRATIONS.md §7):
  ///
  /// - **Edge-only consent gate**: [consentCheck] is consulted first; if it
  ///   resolves false the importer throws
  ///   [NutritionImportConsentRequiredException] and lands NOTHING (§2
  ///   placement rule). No hosted-service path calls this.
  /// - **Idempotent by `(source, externalId)`**: a row already imported under
  ///   the same key is updated in place (last-import-wins), never duplicated.
  /// - **Tombstone-respecting**: a previously-deleted imported entry is NOT
  ///   resurrected on re-import.
  /// - **Read-only observations**: entries land with [importSource] set so the
  ///   read model marks them immutable; never auto-creates a User Food.
  /// - **Shared validator (no rule change)**: each mapped entry runs through
  ///   [validateFoodEntryNutrition]; a hard-reject drops that row while the
  ///   rest of the batch lands; soft-warns persist as non-blocking review
  ///   flags on the entry (NUTRITION.md §6).
  /// - **Local-first**: a single transaction, no network.
  Future<NutritionImportResult> importNutritionBatch({
    required NutritionImportBatch batch,
    required String provider,
    required Future<bool> Function() consentCheck,
    String actor = 'import',
  }) async {
    if (!await consentCheck()) {
      throw const NutritionImportConsentRequiredException();
    }

    // Cross-cutting provenance rule (NUTRITION.md §9): resolve the provider to
    // its specific `Food Source` where recognised, else the generic `Imported`
    // origin PRESERVING the exact provider string (INTEGRATIONS.md §6). This is
    // the single resolution seam every importer obeys.
    final resolution = resolveImportedFoodSource(provider);
    final foodSource = resolution.foodSource;
    final importSource = resolution.importSource;
    final importProvider = resolution.preservedProvider;

    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final landedMealIds = <String>[];
      final landedEntryIds = <String>[];
      var importedCount = 0;
      var updatedCount = 0;
      var skippedTombstoned = 0;
      var rejectedCount = 0;
      var reviewFlagCount = 0;

      for (final importMeal in batch.meals) {
        if (importMeal.entries.isEmpty) {
          continue;
        }

        String? mealId;
        for (final importEntry in importMeal.entries) {
          // Idempotency: find any prior row (active OR tombstoned) for this
          // (source, externalId) key.
          final existing = await _foodEntryByImportKey(
            importSource: importSource,
            importExternalId: importEntry.externalId,
          );
          if (existing != null && existing.deletedAt != null) {
            // Tombstone-respecting: never resurrect a deleted imported entry.
            skippedTombstoned += 1;
            continue;
          }

          // Validate the resolved (scaled) vector through the SHARED validator.
          final resolvedBaseQuantity = resolvePortionBaseQuantity(
            importEntry.portion,
            servingSize: importEntry.servingSize,
            packageSize: importEntry.packageSize,
          );
          final validation = validateFoodEntryNutrition(
            nutrients:
                importEntry.nutrientsPer100.scale(resolvedBaseQuantity / 100),
            resolvedBaseQuantity: resolvedBaseQuantity,
          );
          if (!validation.accepted) {
            // Hard-reject caps drop this row; the rest of the batch still lands.
            rejectedCount += 1;
            continue;
          }
          final reviewFlags = validation.warnings
              .map(NutritionReviewFlag.fromValidationIssue)
              .toList(growable: false);
          reviewFlagCount += reviewFlags.length;

          // Create the grouping Meal lazily, only once a row will actually land.
          mealId ??= await _findOrCreateImportMeal(importMeal, context);
          if (!landedMealIds.contains(mealId)) {
            landedMealIds.add(mealId);
          }

          if (existing != null) {
            await _updateImportedFoodEntry(
              existing: existing,
              mealId: mealId,
              importEntry: importEntry,
              foodSource: foodSource,
              importSource: importSource,
              importProvider: importProvider,
              reviewFlags: reviewFlags,
              context: context,
            );
            updatedCount += 1;
            landedEntryIds.add(existing.id);
          } else {
            final created = await _createFoodEntrySnapshot(
              draft: FoodEntrySnapshotDraft(
                mealId: mealId,
                foodId: null,
                name: importEntry.name,
                foodSource: foodSource,
                nutrientsPer100: importEntry.nutrientsPer100,
                isLiquid: importEntry.isLiquid,
                servingLabel: importEntry.servingLabel,
                servingSize: importEntry.servingSize,
                packageSize: importEntry.packageSize,
                portion: importEntry.portion,
                importSource: importSource,
                importExternalId: importEntry.externalId,
                importProvider: importProvider,
                reviewFlags: reviewFlags,
              ),
              context: context,
            );
            importedCount += 1;
            landedEntryIds.add(created.foodEntryId);
          }
        }
      }

      return NutritionImportResult(
        batchId: context.batchId,
        mealIds: List<String>.unmodifiable(landedMealIds),
        foodEntryIds: List<String>.unmodifiable(landedEntryIds),
        importedCount: importedCount,
        updatedCount: updatedCount,
        skippedTombstoned: skippedTombstoned,
        rejectedCount: rejectedCount,
        reviewFlagCount: reviewFlagCount,
      );
    });
  }

  Future<FoodEntryRow?> _foodEntryByImportKey({
    required String importSource,
    required String importExternalId,
  }) {
    return (_database.select(_database.foodEntries)
          ..where(
            (row) =>
                row.importSource.equals(importSource) &
                row.importExternalId.equals(importExternalId),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<String> _findOrCreateImportMeal(
    NutritionImportMeal importMeal,
    _WriteContext context,
  ) async {
    final mealTypeForStorage =
        _normalizeMealTypeForStorage(importMeal.mealType);
    final existing = await (_activeMealQuery(localDate: importMeal.localDate)
          ..where((row) => row.mealType.equals(mealTypeForStorage)))
        .get();
    if (existing.isNotEmpty) {
      return existing.first.id;
    }
    return _createMeal(
      MealDraft(
        mealType: importMeal.mealType,
        startedAt: importMeal.startedAt,
        localDate: importMeal.localDate,
      ),
      context,
    );
  }

  Future<void> _updateImportedFoodEntry({
    required FoodEntryRow existing,
    required String mealId,
    required NutritionImportFoodEntry importEntry,
    required FoodSource foodSource,
    required String importSource,
    required String? importProvider,
    required List<NutritionReviewFlag> reviewFlags,
    required _WriteContext context,
  }) async {
    final normalizedServing = _normalizeServing(
      label: importEntry.servingLabel,
      size: importEntry.servingSize,
    );
    final normalizedPackageSize = _normalizeOptionalPositive(
      importEntry.packageSize,
      'packageSize',
    );
    final before = existing;
    await (_database.update(_database.foodEntries)
          ..where((row) => row.id.equals(existing.id)))
        .write(
      FoodEntriesCompanion(
        mealId: Value<String>(mealId),
        entryKind: Value<String>(FoodEntryKind.food.name),
        name: Value<String>(
          _normalizeFoodEntryNameForStorage(importEntry.name),
        ),
        nutrientValuesJson:
            Value<String>(importEntry.nutrientsPer100.toJsonString()),
        foodId: const Value<String?>(null),
        portionJson: Value<String?>(importEntry.portion.toJsonString()),
        foodSource: Value<String?>(foodSource.name),
        isLiquid: Value<bool?>(importEntry.isLiquid),
        servingLabel: Value<String?>(normalizedServing.label),
        servingSize: Value<double?>(normalizedServing.size),
        packageSize: Value<double?>(normalizedPackageSize),
        importSource: Value<String?>(importSource),
        importExternalId: Value<String?>(importEntry.externalId),
        importProvider: Value<String?>(importProvider),
        reviewFlagsJson: Value<String?>(
          reviewFlags.isEmpty ? null : NutritionReviewFlag.encode(reviewFlags),
        ),
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: const Value<DateTime?>(null),
      ),
    );
    final after = await _requireFoodEntryRow(existing.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.foodEntriesTable,
      entityId: existing.id,
      beforeImage: _foodEntryImage(before),
      afterImage: _foodEntryImage(after),
    );
  }

  /// Edits a manually-authored `Food Entry`'s [portion] in place.
  ///
  /// An **imported** `Food Entry` is a read-only immutable observation
  /// (NUTRITION.md §7, mirroring `Reading` editability per): this
  /// method throws [ImportedEntryImmutableException] and the user must instead
  /// delete it and add a manual entry. Re-importing refreshes the observation
  /// idempotently — it is never an in-place edit. This is the immutability seam
  /// that nutrition edit UIs (and) consult.
  Future<LogFoodEntryResult> updateFoodEntryPortion({
    required String id,
    required Portion portion,
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final before = await _requireFoodEntryRow(id);
      if (before.deletedAt != null) {
        throw StateError('Food Entry is deleted: $id.');
      }
      if (before.importSource != null) {
        // Imported entries are immutable — never edited in place.
        throw ImportedEntryImmutableException(id);
      }
      if (before.entryKind != FoodEntryKind.food.name) {
        throw StateError('Only a Food-backed entry has an editable Portion.');
      }

      final normalizedServing = _normalizeServing(
        label: before.servingLabel,
        size: before.servingSize,
      );
      final normalizedPackageSize = _normalizeOptionalPositive(
        before.packageSize,
        'packageSize',
      );
      _requireAllowedPortion(
        isLiquid: before.isLiquid ?? false,
        servingLabel: normalizedServing.label,
        servingSize: normalizedServing.size,
        packageSize: normalizedPackageSize,
        portion: portion,
      );
      final nutrientsPer100 =
          NutrientVector.fromJsonString(before.nutrientValuesJson);
      final resolvedBaseQuantity = resolvePortionBaseQuantity(
        portion,
        servingSize: normalizedServing.size,
        packageSize: normalizedPackageSize,
      );
      final validation = validateFoodEntryNutrition(
        nutrients: nutrientsPer100.scale(resolvedBaseQuantity / 100),
        resolvedBaseQuantity: resolvedBaseQuantity,
      );
      validation.throwIfRejected();

      await (_database.update(_database.foodEntries)
            ..where((row) => row.id.equals(id)))
          .write(
        FoodEntriesCompanion(
          portionJson: Value<String?>(portion.toJsonString()),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireFoodEntryRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.foodEntriesTable,
        entityId: id,
        beforeImage: _foodEntryImage(before),
        afterImage: _foodEntryImage(after),
      );

      return LogFoodEntryResult(
        batchId: context.batchId,
        mealId: after.mealId,
        foodEntryId: id,
        warnings: validation.warnings,
      );
    });
  }

  Future<String> deleteMeal(
    String id, {
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final beforeMeal = await _requireMealRow(id);
      if (beforeMeal.deletedAt != null) {
        throw StateError('Meal is deleted: $id.');
      }

      final activeEntries = await _activeFoodEntryQuery(
        mealIds: <String>{id},
      ).get();
      for (final beforeEntry in activeEntries) {
        await _deleteFoodEntryRow(beforeEntry, context);
      }

      await (_database.update(_database.meals)
            ..where((row) => row.id.equals(id)))
          .write(
        MealsCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final afterMeal = await _requireMealRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.mealsTable,
        entityId: id,
        beforeImage: _mealImage(beforeMeal),
        afterImage: _mealImage(afterMeal),
      );

      return context.batchId;
    });
  }

  Future<String> deleteFoodEntry(
    String id, {
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final before = await _requireFoodEntryRow(id);
      if (before.deletedAt != null) {
        throw StateError('Food Entry is deleted: $id.');
      }
      await _deleteFoodEntryRow(before, context);
      return context.batchId;
    });
  }

  Future<MealRecord?> getMealById(String id) async {
    final row = await (_database.select(_database.meals)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _mealFromRow(row);
  }

  Future<UserFoodRecord?> getUserFoodById(String id) async {
    final row = await (_database.select(_database.foods)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _userFoodFromRow(row);
  }

  Future<FoodEntryRecord?> getFoodEntryById(String id) async {
    final row = await (_database.select(_database.foodEntries)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _foodEntryFromRow(row);
  }

  Future<List<UserFoodRecord>> listActiveUserFoods() async {
    final rows = await _activeFoodQuery().get();
    return rows.map(_userFoodFromRow).toList(growable: false);
  }

  Future<List<UserFoodRecord>> searchActiveUserFoods(
    String query, {
    int limit = 50,
  }) async {
    if (limit <= 0) {
      return const <UserFoodRecord>[];
    }

    final searchTerms = _foodSearchTerms(query);
    final foodQuery = _activeFoodQuery();
    if (searchTerms.isNotEmpty) {
      foodQuery.where((row) {
        Expression<bool>? predicate;
        for (final term in searchTerms) {
          final termPredicate = row.name.like(
            '%${_escapeSqlLikeTerm(term)}%',
            escapeChar: '\\',
          );
          predicate =
              predicate == null ? termPredicate : predicate & termPredicate;
        }
        return predicate!;
      });
    }
    foodQuery.limit(limit);

    final rows = await foodQuery.get();
    return rows
        .where((row) => foodNameMatchesQuery(row.name, query))
        .map(_userFoodFromRow)
        .toList(growable: false);
  }

  Future<List<PortionUnit>> availablePortionUnits(String foodId) async {
    final food = await _requireFoodRow(foodId);
    if (food.deletedAt != null) {
      return const <PortionUnit>[];
    }
    return _userFoodFromRow(food).availablePortionUnits;
  }

  Future<List<FoodEntryRecord>> listActiveEntriesForMeal(String mealId) async {
    final rows = await _activeFoodEntryQuery(mealIds: <String>{mealId}).get();
    return rows.map(_foodEntryFromRow).toList(growable: false);
  }

  Future<List<FoodEntryRecord>> listRecentFoodEntries({
    int limit = 50,
  }) async {
    if (limit <= 0) {
      return const <FoodEntryRecord>[];
    }
    final query = _database.select(_database.foodEntries)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.entryKind.equals(FoodEntryKind.food.name) &
            row.foodId.isNotNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.updatedAt),
        (row) => OrderingTerm.desc(row.id),
      ])
      ..limit(limit);
    final rows = await query.get();
    return rows.map(_foodEntryFromRow).toList(growable: false);
  }

  Future<Portion?> lastPortionForFood({
    required String foodId,
    required FoodSource foodSource,
  }) async {
    final query = _database.select(_database.foodEntries)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.entryKind.equals(FoodEntryKind.food.name) &
            row.foodId.equals(foodId) &
            row.foodSource.equals(foodSource.name) &
            row.portionJson.isNotNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.updatedAt),
        (row) => OrderingTerm.desc(row.id),
      ])
      ..limit(1);
    final row = await query.getSingleOrNull();
    final portionJson = row?.portionJson;
    return portionJson == null ? null : Portion.fromJsonString(portionJson);
  }

  Future<NutritionDayRecord> nutritionDay(NutritionDayDate localDate) async {
    final mealRows = await _activeMealQuery(localDate: localDate).get();
    final mealIds = mealRows.map((row) => row.id).toSet();
    final entryRows = mealIds.isEmpty
        ? <FoodEntryRow>[]
        : await _activeFoodEntryQuery(mealIds: mealIds).get();
    final mealTypeRows = await _activeMealTypeQuery().get();
    return _nutritionDayFromRows(
      localDate,
      mealRows,
      entryRows,
      mealTypeRows,
    );
  }

  Stream<NutritionDayRecord> watchNutritionDay(
    NutritionDayDate localDate,
  ) {
    return _watchNutritionRows(
      _activeMealQuery(localDate: localDate).watch(),
      (mealRows, entryRows, mealTypeRows) => _nutritionDayFromRows(
        localDate,
        mealRows,
        entryRows,
        mealTypeRows,
      ),
    );
  }

  Stream<T> _watchNutritionRows<T>(
    Stream<List<MealRow>> mealRows,
    T Function(
      List<MealRow> mealRows,
      List<FoodEntryRow> entryRows,
      List<MealTypeRow> mealTypeRows,
    ) build,
  ) {
    late final StreamSubscription<List<MealRow>> mealSubscription;
    StreamSubscription<List<FoodEntryRow>>? entrySubscription;
    late final StreamSubscription<List<MealTypeRow>> mealTypeSubscription;
    final controller = StreamController<T>();
    List<MealRow>? latestMeals;
    List<FoodEntryRow>? latestEntries;
    List<MealTypeRow>? latestMealTypes;
    List<String> watchedMealIds = const <String>[];
    List<MealRow>? emittedMeals;
    List<FoodEntryRow>? emittedEntries;
    List<MealTypeRow>? emittedMealTypes;

    void emitIfReady() {
      final mealRows = latestMeals;
      final entryRows = latestEntries;
      final mealTypeRows = latestMealTypes;
      if (mealRows == null || entryRows == null || mealTypeRows == null) {
        return;
      }

      if (_sameRowList(emittedMeals, mealRows) &&
          _sameRowList(emittedEntries, entryRows) &&
          _sameRowList(emittedMealTypes, mealTypeRows)) {
        return;
      }

      emittedMeals = List<MealRow>.of(mealRows, growable: false);
      emittedEntries = List<FoodEntryRow>.of(entryRows, growable: false);
      emittedMealTypes = List<MealTypeRow>.of(mealTypeRows, growable: false);
      controller.add(
        build(mealRows, entryRows, mealTypeRows),
      );
    }

    void watchEntriesFor(List<MealRow> mealRows) {
      final mealIds = mealRows.map((row) => row.id).toList(growable: false);
      if (_sameRowList(watchedMealIds, mealIds) && latestEntries != null) {
        emitIfReady();
        return;
      }

      watchedMealIds = mealIds;
      latestEntries = null;
      entrySubscription?.cancel().ignore();
      entrySubscription = null;
      if (mealIds.isEmpty) {
        latestEntries = const <FoodEntryRow>[];
        emitIfReady();
        return;
      }

      entrySubscription =
          _activeFoodEntryQuery(mealIds: mealIds).watch().listen(
        (rows) {
          latestEntries = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    }

    controller.onListen = () {
      mealSubscription = mealRows.listen(
        (rows) {
          latestMeals = rows;
          watchEntriesFor(rows);
        },
        onError: controller.addError,
      );
      mealTypeSubscription = _activeMealTypeQuery().watch().listen(
        (rows) {
          latestMealTypes = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () {
      mealSubscription.cancel().ignore();
      entrySubscription?.cancel().ignore();
      mealTypeSubscription.cancel().ignore();
    };

    return controller.stream;
  }

  SimpleSelectStatement<$MealsTable, MealRow> _activeMealQuery({
    NutritionDayDate? localDate,
    NutritionDayRange? range,
  }) {
    final query = _database.select(_database.meals)
      ..where((row) {
        var predicate = row.deletedAt.isNull();
        if (localDate != null) {
          predicate = predicate & row.localDate.equals(localDate.storageValue);
        }
        if (range != null) {
          // `local_date` is a YYYY-MM-DD string, so a lexicographic BETWEEN is
          // exactly a calendar-day range filter.
          predicate = predicate &
              row.localDate.isBiggerOrEqualValue(range.start.storageValue) &
              row.localDate.isSmallerOrEqualValue(range.end.storageValue);
        }
        return predicate;
      })
      ..orderBy([
        (row) => OrderingTerm.asc(row.startedAt),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query;
  }

  /// Reads the derived `Nutrition Day` for every calendar day in [range],
  /// inclusive. A day with no logged `Meal`s yields an empty record (a
  /// genuine zero day, never a gap). Totals/trends are derived on read over
  /// `Food Entry` snapshots — this reads nothing new and writes nothing;
  /// there is no recalculate/repair path.
  Future<List<NutritionDayRecord>> nutritionDaysInRange(
    NutritionDayRange range,
  ) async {
    final mealRows = await _activeMealQuery(range: range).get();
    final mealIds = mealRows.map((row) => row.id).toSet();
    final entryRows = mealIds.isEmpty
        ? <FoodEntryRow>[]
        : await _activeFoodEntryQuery(mealIds: mealIds).get();
    final mealTypeRows = await _activeMealTypeQuery().get();

    return _nutritionDaysInRangeFromRows(
      range,
      mealRows,
      entryRows,
      mealTypeRows,
    );
  }

  /// Reactive variant of [nutritionDaysInRange]: re-emits whenever any `Meal`,
  /// `Food Entry`, or `Meal Type` changes, so derived totals/trends invalidate
  /// mechanically on a `Food Entry` change — no manual recalculate path.
  Stream<List<NutritionDayRecord>> watchNutritionDaysInRange(
    NutritionDayRange range,
  ) {
    return _watchNutritionRows(
      _activeMealQuery(range: range).watch(),
      (mealRows, entryRows, mealTypeRows) => _nutritionDaysInRangeFromRows(
        range,
        mealRows,
        entryRows,
        mealTypeRows,
      ),
    );
  }

  SimpleSelectStatement<$MealTypesTable, MealTypeRow> _activeMealTypeQuery() {
    final query = _database.select(_database.mealTypes)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query;
  }

  SimpleSelectStatement<$FoodsTable, FoodRow> _activeFoodQuery() {
    final query = _database.select(_database.foods)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.foodSource.equals(FoodSource.user.name),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query;
  }

  SimpleSelectStatement<$FoodEntriesTable, FoodEntryRow> _activeFoodEntryQuery({
    Iterable<String>? mealIds,
  }) {
    final normalizedMealIds = mealIds?.toSet();
    final query = _database.select(_database.foodEntries)
      ..where((row) => row.deletedAt.isNull());
    if (normalizedMealIds != null && normalizedMealIds.isNotEmpty) {
      query.where((row) => row.mealId.isIn(normalizedMealIds));
    }
    query.orderBy([
      (row) => OrderingTerm.asc(row.mealId),
      (row) => OrderingTerm.asc(row.position),
      (row) => OrderingTerm.asc(row.id),
    ]);
    return query;
  }

  Future<String> _createMeal(MealDraft draft, _WriteContext context) async {
    final startedAt = draft.startedAt;
    final endedAt = draft.endedAt;
    if (endedAt != null && !endedAt.isAfter(startedAt)) {
      throw ArgumentError.value(
        endedAt,
        'endedAt',
        'Meal end must be after start.',
      );
    }

    final id = _repositories.createId(context.timestamp);
    final localDate =
        draft.localDate ?? NutritionDayDate.fromDateTime(startedAt);
    final timezone = _normalizeOptionalText(draft.timezone) ??
        startedAt.toLocal().timeZoneName;

    await _database.into(_database.meals).insert(
          MealsCompanion.insert(
            id: id,
            mealType: _normalizeMealTypeForStorage(draft.mealType),
            startedAt: startedAt.toUtc(),
            timezone: timezone,
            localDate: Value<String>(localDate.storageValue),
            endedAt: Value<DateTime?>(endedAt?.toUtc()),
            updatedAt: context.timestamp,
          ),
        );

    final after = await _requireMealRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.mealsTable,
      entityId: id,
      beforeImage: null,
      afterImage: _mealImage(after),
    );

    return id;
  }

  Future<String> _createMealType(
    MealTypeDraft draft,
    _WriteContext context,
  ) async {
    await _ensureUniqueActiveMealTypeName(draft.name);
    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.mealTypes).insert(
          _mealTypeCompanionFromDraft(
            draft,
            context.timestamp,
          ).copyWith(id: Value<String>(id)),
        );

    final after = await _requireMealTypeRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.mealTypesTable,
      entityId: id,
      beforeImage: null,
      afterImage: _mealTypeImage(after),
    );

    return id;
  }

  Future<void> _ensureUniqueActiveMealTypeName(
    String name, {
    String? exceptId,
  }) async {
    final normalizedName = _normalizeMealTypeName(name);
    final rows = await _activeMealTypeQuery().get();
    final duplicate = rows.any(
      (row) =>
          row.id != exceptId &&
          _normalizeMealTypeName(row.name) == normalizedName,
    );
    if (duplicate) {
      throw DuplicateMealTypeNameException(name);
    }
  }

  Future<String> _createUserFood(
    UserFoodDraft draft,
    _WriteContext context,
  ) async {
    await _ensureUniqueActiveUserFoodName(draft.name);
    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.foods).insert(
          _userFoodCompanionFromDraft(
            draft,
            context.timestamp,
          ).copyWith(id: Value<String>(id)),
        );

    final after = await _requireFoodRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.foodsTable,
      entityId: id,
      beforeImage: null,
      afterImage: _foodImage(after),
    );

    return id;
  }

  Future<String> _createRecipe(
    RecipeDraft draft,
    _WriteContext context,
  ) async {
    await _ensureUniqueActiveUserFoodName(draft.name);
    final normalized = await _normalizeRecipeDraft(draft);
    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.foods).insert(
          _recipeFoodCompanionFromDraft(
            name: draft.name,
            normalizedRecipe: normalized,
            timestamp: context.timestamp,
          ).copyWith(id: Value<String>(id)),
        );

    final after = await _requireFoodRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.foodsTable,
      entityId: id,
      beforeImage: null,
      afterImage: _foodImage(after),
    );

    return id;
  }

  Future<void> _ensureUniqueActiveUserFoodName(
    String name, {
    String? exceptId,
  }) async {
    final normalizedName = _normalizeFoodName(name);
    final rows = await _activeFoodQuery().get();
    final duplicate = rows.any(
      (row) =>
          row.id != exceptId && _normalizeFoodName(row.name) == normalizedName,
    );
    if (duplicate) {
      throw DuplicateUserFoodNameException(name);
    }
  }

  Future<String> _createQuickEntry({
    required String mealId,
    required QuickFoodEntryDraft draft,
    required _WriteContext context,
  }) async {
    final meal = await _requireMealRow(mealId);
    if (meal.deletedAt != null) {
      throw StateError('Cannot add a Food Entry to an archived Meal: $mealId.');
    }

    final id = _repositories.createId(context.timestamp);
    final activeEntries = await _activeFoodEntryQuery(
      mealIds: <String>{mealId},
    ).get();

    await _database.into(_database.foodEntries).insert(
          FoodEntriesCompanion.insert(
            id: id,
            mealId: mealId,
            entryKind: Value<String>(FoodEntryKind.quickEntry.name),
            position: activeEntries.length,
            name: _normalizeFoodEntryNameForStorage(draft.name),
            nutrientValuesJson: draft.nutrients.toJsonString(),
            foodId: const Value<String?>(null),
            portionJson: const Value<String?>(null),
            foodSource: const Value<String?>(null),
            isLiquid: const Value<bool?>(null),
            servingLabel: const Value<String?>(null),
            servingSize: const Value<double?>(null),
            packageSize: const Value<double?>(null),
            updatedAt: context.timestamp,
          ),
        );

    final after = await _requireFoodEntryRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.foodEntriesTable,
      entityId: id,
      beforeImage: null,
      afterImage: _foodEntryImage(after),
    );

    return id;
  }

  Future<_CreatedFoodEntry> _createFoodEntry({
    required FoodEntryDraft draft,
    required _WriteContext context,
  }) async {
    final food = await _requireFoodRow(draft.foodId);
    if (food.deletedAt != null) {
      throw StateError('Cannot log an archived User Food: ${draft.foodId}.');
    }
    _ensureUserFood(food);
    final snapshot = _userFoodFromRow(food);

    return _createFoodEntrySnapshot(
      draft: FoodEntrySnapshotDraft(
        mealId: draft.mealId,
        foodId: snapshot.id,
        name: snapshot.name,
        foodSource: snapshot.foodSource,
        nutrientsPer100: snapshot.nutrientsPer100,
        isLiquid: snapshot.isLiquid,
        servingLabel: snapshot.servingLabel,
        servingSize: snapshot.servingSize,
        packageSize: snapshot.packageSize,
        portion: draft.portion,
      ),
      context: context,
    );
  }

  Future<_CreatedFoodEntry> _createFoodEntrySnapshot({
    required FoodEntrySnapshotDraft draft,
    required _WriteContext context,
  }) async {
    final meal = await _requireMealRow(draft.mealId);
    if (meal.deletedAt != null) {
      throw StateError(
        'Cannot add a Food Entry to an archived Meal: ${draft.mealId}.',
      );
    }
    final normalizedServing = _normalizeServing(
      label: draft.servingLabel,
      size: draft.servingSize,
    );
    final normalizedPackageSize = _normalizeOptionalPositive(
      draft.packageSize,
      'packageSize',
    );
    _requireAllowedPortion(
      isLiquid: draft.isLiquid,
      servingLabel: normalizedServing.label,
      servingSize: normalizedServing.size,
      packageSize: normalizedPackageSize,
      portion: draft.portion,
    );
    final resolvedBaseQuantity = resolvePortionBaseQuantity(
      draft.portion,
      servingSize: normalizedServing.size,
      packageSize: normalizedPackageSize,
    );
    final validation = validateFoodEntryNutrition(
      nutrients: draft.nutrientsPer100.scale(resolvedBaseQuantity / 100),
      resolvedBaseQuantity: resolvedBaseQuantity,
    );
    validation.throwIfRejected();

    final id = _repositories.createId(context.timestamp);
    final activeEntries = await _activeFoodEntryQuery(
      mealIds: <String>{draft.mealId},
    ).get();

    await _database.into(_database.foodEntries).insert(
          FoodEntriesCompanion.insert(
            id: id,
            mealId: draft.mealId,
            entryKind: Value<String>(FoodEntryKind.food.name),
            position: activeEntries.length,
            name: _normalizeFoodEntryNameForStorage(draft.name),
            nutrientValuesJson: draft.nutrientsPer100.toJsonString(),
            foodId: Value<String?>(draft.foodId),
            portionJson: Value<String?>(draft.portion.toJsonString()),
            foodSource: Value<String?>(draft.foodSource.name),
            isLiquid: Value<bool?>(draft.isLiquid),
            servingLabel: Value<String?>(normalizedServing.label),
            servingSize: Value<double?>(normalizedServing.size),
            packageSize: Value<double?>(normalizedPackageSize),
            importSource: Value<String?>(draft.importSource),
            importExternalId: Value<String?>(draft.importExternalId),
            importProvider: Value<String?>(draft.importProvider),
            reviewFlagsJson: Value<String?>(
              draft.reviewFlags.isEmpty
                  ? null
                  : NutritionReviewFlag.encode(draft.reviewFlags),
            ),
            updatedAt: context.timestamp,
          ),
        );

    final after = await _requireFoodEntryRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.foodEntriesTable,
      entityId: id,
      beforeImage: null,
      afterImage: _foodEntryImage(after),
    );

    return _CreatedFoodEntry(
      foodEntryId: id,
      warnings: validation.warnings,
    );
  }

  Future<void> _deleteFoodEntryRow(
    FoodEntryRow before,
    _WriteContext context,
  ) async {
    await (_database.update(_database.foodEntries)
          ..where((row) => row.id.equals(before.id)))
        .write(
      FoodEntriesCompanion(
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: Value<DateTime?>(context.timestamp),
      ),
    );
    final after = await _requireFoodEntryRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.foodEntriesTable,
      entityId: before.id,
      beforeImage: _foodEntryImage(before),
      afterImage: _foodEntryImage(after),
    );
  }

  Future<MealRow> _requireMealRow(String id) async {
    final row = await (_database.select(_database.meals)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Meal not found: $id.');
    }
    return row;
  }

  Future<MealTypeRow?> _mealTypeRowById(String id) {
    return (_database.select(_database.mealTypes)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
  }

  Future<MealTypeRow> _requireMealTypeRow(String id) async {
    final row = await _mealTypeRowById(id);
    if (row == null) {
      throw StateError('Meal Type not found: $id.');
    }
    return row;
  }

  Future<FoodRow> _requireFoodRow(String id) async {
    final row = await (_database.select(_database.foods)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Food not found: $id.');
    }
    return row;
  }

  Future<FoodEntryRow> _requireFoodEntryRow(String id) async {
    final row = await (_database.select(_database.foodEntries)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Food Entry not found: $id.');
    }
    return row;
  }

  FoodsCompanion _userFoodCompanionFromDraft(
    UserFoodDraft draft,
    DateTime timestamp,
  ) {
    final normalizedServing = _normalizeServing(
      label: draft.servingLabel,
      size: draft.servingSize,
    );
    return FoodsCompanion(
      name: Value<String>(_normalizeFoodNameForStorage(draft.name)),
      foodSource: Value<String>(FoodSource.user.name),
      nutrientValuesJson: Value<String>(draft.nutrientsPer100.toJsonString()),
      isLiquid: Value<bool>(draft.isLiquid),
      servingLabel: Value<String?>(normalizedServing.label),
      servingSize: Value<double?>(normalizedServing.size),
      packageSize: Value<double?>(_normalizeOptionalPositive(
        draft.packageSize,
        'packageSize',
      )),
      updatedAt: Value<DateTime>(timestamp),
    );
  }

  Future<_NormalizedRecipeDraft> _normalizeRecipeDraft(
    RecipeDraft draft,
  ) async {
    final normalizedServingCount = _normalizeOptionalPositive(
      draft.servingCount,
      'servingCount',
    )!;
    if (draft.ingredients.isEmpty) {
      throw ArgumentError.value(
        draft.ingredients,
        'ingredients',
        'Recipe requires at least one ingredient.',
      );
    }

    final normalizedIngredients = <RecipeIngredient>[];
    for (final ingredient in draft.ingredients) {
      final normalizedServing = _normalizeServing(
        label: ingredient.servingLabel,
        size: ingredient.servingSize,
      );
      final normalizedPackageSize = _normalizeOptionalPositive(
        ingredient.packageSize,
        'packageSize',
      );
      final normalized = RecipeIngredient(
        foodId: _normalizeRequiredText(ingredient.foodId, 'foodId'),
        name: _normalizeFoodEntryNameForStorage(ingredient.name),
        foodSource: ingredient.foodSource,
        nutrientsPer100: ingredient.nutrientsPer100,
        isLiquid: ingredient.isLiquid,
        portion: ingredient.portion,
        servingLabel: normalizedServing.label,
        servingSize: normalizedServing.size,
        packageSize: normalizedPackageSize,
      );
      _requireAllowedPortion(
        isLiquid: normalized.isLiquid,
        servingLabel: normalized.servingLabel,
        servingSize: normalized.servingSize,
        packageSize: normalized.packageSize,
        portion: normalized.portion,
      );
      await _validateRecipeIngredientSource(normalized);
      normalized.resolvedBaseQuantity;
      normalizedIngredients.add(normalized);
    }

    return _NormalizedRecipeDraft(
      ingredients: List<RecipeIngredient>.unmodifiable(normalizedIngredients),
      servingCount: normalizedServingCount,
      nutrition: deriveRecipeNutrition(
        ingredients: normalizedIngredients,
        servingCount: normalizedServingCount,
      ),
    );
  }

  Future<void> _validateRecipeIngredientSource(
    RecipeIngredient ingredient,
  ) async {
    switch (ingredient.foodSource) {
      case FoodSource.user:
        final row = await _requireFoodRow(ingredient.foodId);
        _ensureUserFood(row);
        if (row.deletedAt != null) {
          throw StateError(
            'Cannot use an archived User Food as a Recipe ingredient: '
            '${ingredient.foodId}.',
          );
        }
        if (_isRecipeRow(row)) {
          throw UnsupportedError(
            'Recipe nesting is deferred for flat v1 composition.',
          );
        }
      case FoodSource.usda:
        final row = await _repositories.platformFoods.getUsdaFoodById(
          ingredient.foodId,
        );
        if (row == null) {
          throw StateError('USDA Food not found: ${ingredient.foodId}.');
        }
      case FoodSource.openFoodFacts:
        throw UnsupportedError(
          'Open Food Facts Recipe ingredients are not available in this slice.',
        );
      case FoodSource.cronometer:
      case FoodSource.myFitnessPal:
      case FoodSource.yazio:
      case FoodSource.lifesum:
      case FoodSource.imported:
        throw UnsupportedError(
          'Imported Food Entries are read-only observations and cannot be used '
          'as Recipe ingredients.',
        );
    }
  }

  FoodsCompanion _recipeFoodCompanionFromDraft({
    required String name,
    required _NormalizedRecipeDraft normalizedRecipe,
    required DateTime timestamp,
  }) {
    return FoodsCompanion(
      name: Value<String>(_normalizeFoodNameForStorage(name)),
      foodSource: Value<String>(FoodSource.user.name),
      nutrientValuesJson: Value<String>(
        normalizedRecipe.nutrition.nutrientsPer100.toJsonString(),
      ),
      isLiquid: const Value<bool>(false),
      servingLabel: const Value<String?>('serving'),
      servingSize: Value<double?>(normalizedRecipe.nutrition.servingSize),
      packageSize: const Value<double?>(null),
      recipeIngredientsJson: Value<String?>(
        _recipeIngredientsToJsonString(normalizedRecipe.ingredients),
      ),
      recipeServingCount: Value<double?>(normalizedRecipe.servingCount),
      updatedAt: Value<DateTime>(timestamp),
    );
  }

  MealTypesCompanion _mealTypeCompanionFromDraft(
    MealTypeDraft draft,
    DateTime timestamp,
  ) {
    return MealTypesCompanion(
      name: Value<String>(_normalizeMealTypeForStorage(draft.name)),
      sortOrder: Value<int>(_normalizeMealTypeSortOrder(draft.sortOrder)),
      updatedAt: Value<DateTime>(timestamp),
    );
  }

  void _ensureUserFood(FoodRow row) {
    if (row.foodSource != FoodSource.user.name) {
      throw UnsupportedError('Only User Food is editable in this slice.');
    }
  }

  void _ensureNotRecipe(FoodRow row) {
    if (_isRecipeRow(row)) {
      throw UnsupportedError('Use Recipe editing for Recipe foods.');
    }
  }

  void _requireAllowedPortion({
    required bool isLiquid,
    required String? servingLabel,
    required double? servingSize,
    required double? packageSize,
    required Portion portion,
  }) {
    final available = availablePortionUnitsForFood(
      isLiquid: isLiquid,
      servingLabel: servingLabel,
      servingSize: servingSize,
      packageSize: packageSize,
    );
    if (!available.contains(portion.unit)) {
      throw ArgumentError.value(
        portion.unit,
        'portion.unit',
        'Portion unit is not available for this Food.',
      );
    }
  }
}

class _CreatedFoodEntry {
  const _CreatedFoodEntry({
    required this.foodEntryId,
    required this.warnings,
  });

  final String foodEntryId;
  final List<NutrientValidationIssue> warnings;
}

/// The result of creating a `Compound`: the single reversible Activity Log
/// [batchId] for the create and the new [compoundId].
class CreateCompoundResult {
  const CreateCompoundResult({
    required this.batchId,
    required this.compoundId,
  });

  final String batchId;
  final String compoundId;
}

/// The result of logging a `Dose`: the single Activity Log [batchId] for the
/// write, the new [doseId], and any non-blocking [warnings]. The shared two-tier
/// validator guards the logging path: hard-reject rules throw before
/// anything persists, while soft-warn rules surface here as their stable rule
/// ids without blocking the save (PROTOCOLS.md §6).
class LogDoseResult {
  LogDoseResult({
    required this.batchId,
    required this.doseId,
    List<String> warnings = const <String>[],
  }) : warnings = List<String>.unmodifiable(warnings);

  final String batchId;
  final String doseId;
  final List<String> warnings;
}

/// The result of creating a `Protocol`: the single reversible Activity Log
/// [batchId] covering the Protocol row and its member rows, and the new
/// [protocolId].
class CreateProtocolResult {
  const CreateProtocolResult({
    required this.batchId,
    required this.protocolId,
  });

  final String batchId;
  final String protocolId;
}

/// The account-level Settings repository. Owns the synced
/// `user_settings` singleton — the account half of `AppSettings` (theme, unit
/// system, week start, default weight increment, home-screen display, and the
/// logging-workflow toggles). Every write flows through the Activity Log like
/// every other synced domain, local-first with no network. Device-level
/// settings never reach here; they stay in the local `settings.json`.
class AccountSettingsRepository {
  AccountSettingsRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  /// The single (non-tombstoned) account-level Settings row, or null when the
  /// user has never customized any account setting (defaults apply).
  Future<AccountSettings?> load() async {
    final row = await _activeRow();
    return row == null ? null : _accountSettingsFromRow(row);
  }

  Stream<AccountSettings?> watch() {
    return _activeQuery().watch().map(
          (rows) => rows.isEmpty ? null : _accountSettingsFromRow(rows.first),
        );
  }

  /// Upserts the singleton to [settings]. Creates the row (minting a stable
  /// UUIDv7 id) on first write, otherwise LWW-updates the existing row. The
  /// change is recorded as one Activity Log entry so Synced Mode replicates it.
  Future<void> save(
    AccountSettings settings, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final existing = await _activeRow();
      if (existing == null) {
        final id = _repositories.createId(context.timestamp);
        await _database.into(_database.userSettings).insert(
              _companionFromSettings(settings, context.timestamp)
                  .copyWith(id: Value<String>(id)),
            );
        final after = await _requireRow(id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.userSettingsTable,
          entityId: id,
          beforeImage: null,
          afterImage: _userSettingsImage(after),
        );
        return;
      }

      final before = _userSettingsImage(existing);
      await (_database.update(_database.userSettings)
            ..where((row) => row.id.equals(existing.id)))
          .write(_companionFromSettings(settings, context.timestamp));
      final after = await _requireRow(existing.id);
      if (_activityImagesEqual(before, _userSettingsImage(after))) {
        return;
      }
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.userSettingsTable,
        entityId: existing.id,
        beforeImage: before,
        afterImage: _userSettingsImage(after),
      );
    });
  }

  Future<void> applySyncImage({
    required Map<String, Object?> image,
    required String deviceId,
    required String batchId,
    String actor = 'sync',
    String? activityLogId,
    Map<String, Object?>? activityBeforeImage,
    Map<String, Object?>? activityAfterImage,
    DateTime? activityOccurredAt,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final id = _activityRequiredString(image, 'id');
      final beforeRow = await (_database.select(_database.userSettings)
            ..where((row) => row.id.equals(id)))
          .getSingleOrNull();
      final localBeforeImage =
          beforeRow == null ? null : _userSettingsImage(beforeRow);

      await _database.into(_database.userSettings).insertOnConflictUpdate(
            _userSettingsSyncCompanionFromImage(image, syncDeviceId: deviceId),
          );

      final afterRow = await _requireRow(id);
      final localAfterImage = _userSettingsImage(afterRow);
      if (localBeforeImage != null &&
          _activityImagesEqual(localBeforeImage, localAfterImage)) {
        return;
      }

      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.userSettingsTable,
        entityId: id,
        beforeImage: activityBeforeImage ?? localBeforeImage,
        afterImage: activityAfterImage ?? localAfterImage,
        id: activityLogId,
        occurredAt: activityOccurredAt,
        syncAcknowledgedAt: context.timestamp,
      );
    });
  }

  Future<UserSettingsRow?> _activeRow() => _activeQuery().getSingleOrNull();

  SimpleSelectStatement<$UserSettingsTable, UserSettingsRow> _activeQuery() {
    return _database.select(_database.userSettings)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
      ..limit(1);
  }

  Future<UserSettingsRow> _requireRow(String id) {
    return (_database.select(_database.userSettings)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  UserSettingsCompanion _companionFromSettings(
    AccountSettings settings,
    DateTime timestamp,
  ) {
    return UserSettingsCompanion(
      themePreference: Value<String>(settings.themePreference),
      unitSystem: Value<String>(settings.unitSystem),
      weekStartDay: Value<String>(settings.weekStartDay),
      defaultWeightIncrement: Value<double>(settings.defaultWeightIncrement),
      homeScreenDisplay: Value<String>(settings.homeScreenDisplay),
      prTrackingEnabled: Value<bool>(settings.prTrackingEnabled),
      markSetsCompleteByDefault:
          Value<bool>(settings.markSetsCompleteByDefault),
      autoSelectNextSet: Value<bool>(settings.autoSelectNextSet),
      updatedAt: Value<DateTime>(timestamp),
      deletedAt: const Value<DateTime?>(null),
    );
  }
}

/// The Protocols repository (CONTEXT.md `Compound`/`Dose`/`Protocol Day`). The
/// fourth authored domain, mirroring the training/nutrition write path: every
/// write flows through the Activity Log (PROTOCOLS.md §7; no direct store writes
/// from a controller), local-first with no network (set save confirms without
/// blocking).
///
/// Subtle by construction: the model never names or categorizes a
/// `Compound` by substance type or legality. A `Dose` is authored intake, never
/// a `Metric`; the `Protocol Day` is derived on read, nothing stored.
///
class ProtocolsRepository {
  ProtocolsRepository._(this._repositories, this._otcSeedSource);

  final TrainingRepositories _repositories;
  final OtcCompoundSeedSource _otcSeedSource;

  /// Guards against concurrent seed loads (mirrors `CatalogRepository`): the
  /// first caller's future is shared, and cleared on failure so a transient
  /// error can be retried.
  Future<void>? _otcSeedFuture;

  AppDatabase get _database => _repositories.database;

  /// Idempotently loads the tiny OTC seed `Compound` library (PROTOCOLS.md §3,
  ///). Mirrors the platform-exercise / usda-food seed precedent: each
  /// seed row carries a STABLE id, so a row already present is skipped — running
  /// the seed twice never duplicates a `Compound`. Each new row is inserted with
  /// its default unit/route (and optional strength) and recorded in the Activity
  /// Log like any other write.
  ///
  /// Neutral by construction: the seed carries no substance
  /// type/legality field — it is a handful of generic starter rows, not a typed
  /// catalogue.
  Future<void> ensureOtcLibrarySeeded({
    String actor = 'otc_seed',
  }) {
    final existingFuture = _otcSeedFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    late final Future<void> nextFuture;
    nextFuture = _ensureOtcLibrarySeeded(actor: actor).catchError(
      (Object error, StackTrace stackTrace) {
        if (identical(_otcSeedFuture, nextFuture)) {
          _otcSeedFuture = null;
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _otcSeedFuture = nextFuture;
    return nextFuture;
  }

  Future<void> _ensureOtcLibrarySeeded({
    required String actor,
  }) async {
    final rows = _otcSeedSource.load();
    if (rows.isEmpty) {
      return;
    }

    final context = _repositories._createWriteContext(actor: actor);

    await _database.transaction(() async {
      // Idempotency is by the seed's STABLE id: a Compound already present
      // (including one the user has since archived) is left untouched. The seed
      // never resurrects an archived row or overwrites user edits.
      final existingIds = (await _database.select(_database.compounds).get())
          .map((row) => row.id)
          .toSet();

      for (final seed in rows) {
        if (existingIds.contains(seed.id)) {
          continue;
        }

        await _database.into(_database.compounds).insert(
              CompoundsCompanion.insert(
                id: seed.id,
                name: seed.name,
                defaultUnit: seed.defaultUnit.name,
                defaultRoute: seed.defaultRoute.name,
                strength: Value<String?>(seed.strength?.storageValue),
                updatedAt: context.timestamp,
              ),
            );
        final after = await _requireCompoundRow(seed.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.compoundsTable,
          entityId: seed.id,
          beforeImage: null,
          afterImage: _compoundImage(after),
        );
      }
    });
  }

  /// Creates a `Compound` (catalogue/template). One reversible Activity Log
  /// batch; local-first, no network.
  Future<CreateCompoundResult> createCompound(
    CompoundDraft draft, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final id = await _createCompound(draft, context);
      return CreateCompoundResult(
        batchId: context.batchId,
        compoundId: id,
      );
    });
  }

  /// Logs a self-describing `Dose` (PROTOCOLS.md §1.1/§1.2). Snapshots the
  /// Compound's name now; captures the timezone and freezes the local date at
  /// log time. One reversible Activity Log batch; local-first.
  Future<LogDoseResult> logDose(
    DoseSnapshotDraft draft, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final outcome = await _logDose(draft, context);
      return LogDoseResult(
        batchId: context.batchId,
        doseId: outcome.doseId,
        warnings: outcome.warnings,
      );
    });
  }

  /// Edits a logged `Dose` in place (amount/unit/route/time), keeping its
  /// identity ('s review surface: tap a Dose to open it for edit).
  /// Runs the SAME shared two-tier validator as [logDose] (PROTOCOLS.md §6) —
  /// a hard-reject throws before anything is written. The Dose's local date
  /// is NEVER re-derived from the device's CURRENT timezone here: when
  /// [draft.localDate]/[draft.timezone] are omitted, the ALREADY-FROZEN values
  /// on the existing row carry over untouched, so editing a Dose can never
  /// silently move it to a different `Protocol Day` after the device travels.
  /// One reversible Activity Log batch; never bypasses it.
  Future<String> editDose(
    String doseId,
    DoseSnapshotDraft draft, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      await _editDose(doseId, draft, context);
      return context.batchId;
    });
  }

  /// Tags (or untags) a logged `Dose` to a `Protocol` AFTER the fact
  /// (PROTOCOLS.md §1.4, §1.2) — a lighter path than a full
  /// [editDose] that touches ONLY the tag. Pass a [protocolId] to tag the
  /// Dose to that Protocol (its current name is resolved and snapshotted
  /// alongside the id, mirroring the Compound snapshot, §1.1); pass null to
  /// untag it back to a fully first-class ad-hoc Dose. Never validates the
  /// Protocol as active — an already-archived Protocol can still be tagged/
  /// referenced historically, since tagging never cascades either way. One
  /// reversible Activity Log batch; touches no other Dose field.
  Future<String> tagDoseToProtocol(
    String doseId, {
    required String? protocolId,
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      await _tagDoseToProtocol(doseId, protocolId, context);
      return context.batchId;
    });
  }

  /// Edits a `Compound`'s catalogue fields (name, default unit/route, strength)
  /// in place. This mutates the live `Compound` row ONLY — by design it never
  /// touches any previously logged `Dose`, whose snapshot is frozen (§1.1).
  /// One reversible Activity Log batch.
  Future<String> editCompound(
    String compoundId,
    CompoundDraft draft, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      await _editCompound(compoundId, draft, context);
      return context.batchId;
    });
  }

  /// Archives a `Compound` (soft-delete via `deletedAt`): it drops from pickers
  /// but its history — and every `Dose` snapshot — survives. No cascade
  /// (PROTOCOLS.md §7). One reversible Activity Log batch.
  Future<String> archiveCompound(
    String compoundId, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      await _setCompoundDeletedAt(compoundId, context.timestamp, context);
      return context.batchId;
    });
  }

  /// Hard-deletes a `Compound` row from the catalogue. Logged `Dose`s are
  /// untouched and still render from their own snapshot — proof that a `Dose`
  /// has no live dependency on its `Compound` (§1.1). No cascade, ever.
  Future<String> deleteCompound(
    String compoundId, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      await _deleteCompound(compoundId, context);
      return context.batchId;
    });
  }

  /// Deletes a logged `Dose`. A Dose is user log, so this hard-deletes it to a
  /// tombstone (`deletedAt`), recoverable through the Activity Log (undo
  /// restores the before-image) — and NEVER cascades to its Compound or any
  /// other row (PROTOCOLS.md §7). On the sync rails the tombstone is an ordinary
  /// LWW update that other devices converge to. One reversible Activity Log
  /// batch.
  Future<String> deleteDose(
    String doseId, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      await _setDoseDeletedAt(doseId, context.timestamp, context);
      return context.batchId;
    });
  }

  Future<void> _setDoseDeletedAt(
    String doseId,
    DateTime deletedAt,
    _WriteContext context,
  ) async {
    final before = await _requireDoseRow(doseId);
    await (_database.update(_database.doses)
          ..where((row) => row.id.equals(doseId)))
        .write(
      DosesCompanion(
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: Value<DateTime?>(deletedAt),
      ),
    );

    final after = await _requireDoseRow(doseId);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.dosesTable,
      entityId: doseId,
      beforeImage: _doseImage(before),
      afterImage: _doseImage(after),
    );
  }

  /// Applies a pulled `Compound`/`Dose` sync image: upserts the opaque row via
  /// `insertOnConflictUpdate` (stamping the source device + previously-synced)
  /// and appends a sync-acknowledged Activity Log entry so the overwritten value
  /// is recoverable (undo/recovery). Self-describing — a Dose never
  /// requires its `Compound` to be present on this device.
  static const _syncEntityTables = <String>{
    AppDatabase.compoundsTable,
    AppDatabase.dosesTable,
    AppDatabase.protocolsTable,
    AppDatabase.protocolCompoundsTable,
    AppDatabase.schedulesTable,
    AppDatabase.protocolTargetOutcomesTable,
  };

  Future<void> applySyncImage({
    required String entityTable,
    required Map<String, Object?> image,
    required String deviceId,
    required String batchId,
    String actor = 'sync',
    String? activityLogId,
    Map<String, Object?>? activityBeforeImage,
    Map<String, Object?>? activityAfterImage,
    DateTime? activityOccurredAt,
  }) {
    if (!_syncEntityTables.contains(entityTable)) {
      throw ArgumentError.value(
        entityTable,
        'entityTable',
        'Unsupported protocols sync entity.',
      );
    }
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final id = _activityRequiredString(image, 'id');
      final localBeforeImage = await _protocolsSyncImageFor(
        entityTable: entityTable,
        entityId: id,
      );

      switch (entityTable) {
        case AppDatabase.compoundsTable:
          await _database.into(_database.compounds).insertOnConflictUpdate(
                _compoundSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
        case AppDatabase.dosesTable:
          await _database.into(_database.doses).insertOnConflictUpdate(
                _doseSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
        case AppDatabase.protocolsTable:
          await _database.into(_database.protocols).insertOnConflictUpdate(
                _protocolSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
        case AppDatabase.protocolCompoundsTable:
          await _database
              .into(_database.protocolCompounds)
              .insertOnConflictUpdate(
                _protocolCompoundSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
        case AppDatabase.schedulesTable:
          await _database.into(_database.schedules).insertOnConflictUpdate(
                _scheduleSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
        case AppDatabase.protocolTargetOutcomesTable:
          await _database
              .into(_database.protocolTargetOutcomes)
              .insertOnConflictUpdate(
                _protocolTargetOutcomeSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
      }

      final localAfterImage = await _protocolsSyncImageFor(
        entityTable: entityTable,
        entityId: id,
      );
      if (localAfterImage == null ||
          (localBeforeImage != null &&
              _activityImagesEqual(localBeforeImage, localAfterImage))) {
        return;
      }

      await _repositories.activityLog._append(
        context,
        entityTable: entityTable,
        entityId: id,
        beforeImage: activityBeforeImage ?? localBeforeImage,
        afterImage: activityAfterImage ?? localAfterImage,
        id: activityLogId,
        occurredAt: activityOccurredAt,
        syncAcknowledgedAt: context.timestamp,
      );
    });
  }

  Future<Map<String, Object?>?> _protocolsSyncImageFor({
    required String entityTable,
    required String entityId,
  }) async {
    switch (entityTable) {
      case AppDatabase.compoundsTable:
        final row = await (_database.select(_database.compounds)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _compoundImage(row);
      case AppDatabase.dosesTable:
        final row = await (_database.select(_database.doses)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _doseImage(row);
      case AppDatabase.protocolsTable:
        final row = await (_database.select(_database.protocols)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _protocolImage(row);
      case AppDatabase.protocolCompoundsTable:
        final row = await (_database.select(_database.protocolCompounds)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _protocolCompoundImage(row);
      case AppDatabase.schedulesTable:
        final row = await (_database.select(_database.schedules)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _scheduleImage(row);
      case AppDatabase.protocolTargetOutcomesTable:
        final row = await (_database.select(_database.protocolTargetOutcomes)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _protocolTargetOutcomeImage(row);
      default:
        throw ArgumentError.value(
          entityTable,
          'entityTable',
          'Unsupported protocols sync entity.',
        );
    }
  }

  Future<String> _createCompound(
    CompoundDraft draft,
    _WriteContext context,
  ) async {
    final name = draft.name.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(draft.name, 'name', 'Compound name is empty.');
    }
    // The structured strength serializes to its canonical curated label; storage
    // never carries a free-text strength.
    final strength = draft.strength?.storageValue;
    final id = _repositories.createId(context.timestamp);

    await _database.into(_database.compounds).insert(
          CompoundsCompanion.insert(
            id: id,
            name: name,
            defaultUnit: draft.defaultUnit.name,
            defaultRoute: draft.defaultRoute.name,
            strength: Value<String?>(strength),
            updatedAt: context.timestamp,
          ),
        );

    final after = await _requireCompoundRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.compoundsTable,
      entityId: id,
      beforeImage: null,
      afterImage: _compoundImage(after),
    );

    return id;
  }

  Future<void> _editCompound(
    String compoundId,
    CompoundDraft draft,
    _WriteContext context,
  ) async {
    final before = await _requireCompoundRow(compoundId);
    final name = draft.name.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(draft.name, 'name', 'Compound name is empty.');
    }
    final strength = draft.strength?.storageValue;

    await (_database.update(_database.compounds)
          ..where((row) => row.id.equals(compoundId)))
        .write(
      CompoundsCompanion(
        name: Value<String>(name),
        defaultUnit: Value<String>(draft.defaultUnit.name),
        defaultRoute: Value<String>(draft.defaultRoute.name),
        strength: Value<String?>(strength),
        updatedAt: Value<DateTime>(context.timestamp),
      ),
    );

    final after = await _requireCompoundRow(compoundId);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.compoundsTable,
      entityId: compoundId,
      beforeImage: _compoundImage(before),
      afterImage: _compoundImage(after),
    );
  }

  Future<void> _setCompoundDeletedAt(
    String compoundId,
    DateTime deletedAt,
    _WriteContext context,
  ) async {
    final before = await _requireCompoundRow(compoundId);
    await (_database.update(_database.compounds)
          ..where((row) => row.id.equals(compoundId)))
        .write(
      CompoundsCompanion(
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: Value<DateTime?>(deletedAt),
      ),
    );

    final after = await _requireCompoundRow(compoundId);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.compoundsTable,
      entityId: compoundId,
      beforeImage: _compoundImage(before),
      afterImage: _compoundImage(after),
    );
  }

  Future<void> _deleteCompound(
    String compoundId,
    _WriteContext context,
  ) async {
    final before = await _requireCompoundRow(compoundId);
    await (_database.delete(_database.compounds)
          ..where((row) => row.id.equals(compoundId)))
        .go();

    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.compoundsTable,
      entityId: compoundId,
      beforeImage: _compoundImage(before),
      afterImage: null,
    );
  }

  Future<({String doseId, List<String> warnings})> _logDose(
    DoseSnapshotDraft draft,
    _WriteContext context,
  ) async {
    final compoundName = draft.compoundName.trim();
    if (compoundName.isEmpty) {
      throw ArgumentError.value(
        draft.compoundName,
        'compoundName',
        'Dose compound name snapshot is empty.',
      );
    }
    final amountEntered = draft.amountEntered.trim();
    if (amountEntered.isEmpty) {
      throw ArgumentError.value(
        draft.amountEntered,
        'amountEntered',
        'Entered Dose amount must not be empty.',
      );
    }

    // The SHARED two-tier validator guards the logging path (PROTOCOLS.md §6,
    //) — not a Protocols-specific fork. A hard-reject (negative amount,
    // absurd per-dose cap, malformed unit/route) throws here so nothing is
    // persisted; soft warnings (out-of-range-for-unit) are non-blocking and
    // surfaced on the result. The entered amount is the source of truth.
    final validation = validateDose(
      amount: amountEntered,
      unit: draft.unit.name,
      route: draft.route.name,
    );
    validation.throwIfRejected();
    final warnings = validation.warnings
        .map((warning) => warning.rule)
        .toList(growable: false);

    // store the UTC instant, capture the timezone, and freeze the
    // local date from the dose instant when not supplied.
    final tookAtUtc = draft.tookAt.toUtc();
    final timezone = _normalizeOptionalText(draft.timezone) ??
        draft.tookAt.toLocal().timeZoneName;
    final localDate =
        draft.localDate ?? ProtocolDayDate.fromDateTime(draft.tookAt);
    final protocolTag = _validateDoseProtocolTag(draft);

    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.doses).insert(
          DosesCompanion.insert(
            id: id,
            compoundId: Value<String?>(draft.compoundId),
            compoundName: compoundName,
            compoundStrength:
                Value<String?>(draft.compoundStrength?.storageValue),
            amountValue: draft.amountValue,
            amountEntered: amountEntered,
            unit: draft.unit.name,
            route: draft.route.name,
            tookAt: tookAtUtc,
            timezone: timezone,
            localDate: Value<String>(localDate.storageValue),
            provenance: Value<String>(draft.provenance.name),
            protocolId: Value<String?>(protocolTag.protocolId),
            protocolName: Value<String?>(protocolTag.protocolName),
            updatedAt: context.timestamp,
          ),
        );

    final after = await _requireDoseRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.dosesTable,
      entityId: id,
      beforeImage: null,
      afterImage: _doseImage(after),
    );

    return (doseId: id, warnings: warnings);
  }

  Future<void> _editDose(
    String doseId,
    DoseSnapshotDraft draft,
    _WriteContext context,
  ) async {
    final before = await _requireDoseRow(doseId);
    final compoundName = draft.compoundName.trim();
    if (compoundName.isEmpty) {
      throw ArgumentError.value(
        draft.compoundName,
        'compoundName',
        'Dose compound name snapshot is empty.',
      );
    }
    final amountEntered = draft.amountEntered.trim();
    if (amountEntered.isEmpty) {
      throw ArgumentError.value(
        draft.amountEntered,
        'amountEntered',
        'Entered Dose amount must not be empty.',
      );
    }

    // The SAME shared two-tier validator guards edits as logging (§6).
    final validation = validateDose(
      amount: amountEntered,
      unit: draft.unit.name,
      route: draft.route.name,
    );
    validation.throwIfRejected();

    final tookAtUtc = draft.tookAt.toUtc();
    // Never re-derive the local date/timezone from the (possibly-changed)
    // device timezone on edit — an omitted value stays pinned to whatever was
    // ALREADY FROZEN on the row, so an edit can never silently move
    // a Dose to a different Protocol Day after the device travels.
    final timezone = _normalizeOptionalText(draft.timezone) ?? before.timezone;
    final localDate =
        draft.localDate ?? ProtocolDayDate.parse(before.localDate);
    final protocolTag = _validateDoseProtocolTag(draft);

    await (_database.update(_database.doses)
          ..where((row) => row.id.equals(doseId)))
        .write(
      DosesCompanion(
        compoundId: Value<String?>(draft.compoundId),
        compoundName: Value<String>(compoundName),
        compoundStrength: Value<String?>(draft.compoundStrength?.storageValue),
        amountValue: Value<double>(draft.amountValue),
        amountEntered: Value<String>(amountEntered),
        unit: Value<String>(draft.unit.name),
        route: Value<String>(draft.route.name),
        tookAt: Value<DateTime>(tookAtUtc),
        timezone: Value<String>(timezone),
        localDate: Value<String>(localDate.storageValue),
        provenance: Value<String>(draft.provenance.name),
        protocolId: Value<String?>(protocolTag.protocolId),
        protocolName: Value<String?>(protocolTag.protocolName),
        updatedAt: Value<DateTime>(context.timestamp),
      ),
    );

    final after = await _requireDoseRow(doseId);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.dosesTable,
      entityId: doseId,
      beforeImage: _doseImage(before),
      afterImage: _doseImage(after),
    );
  }

  /// Resolves + hard-rejects a [DoseSnapshotDraft]'s Protocol tag pairing:
  /// a non-null [DoseSnapshotDraft.protocolId] requires a non-blank
  /// [DoseSnapshotDraft.protocolName] snapshot (the caller — via
  /// `DoseSnapshotDraft.fromCompound`'s `protocol` param, or built directly —
  /// is responsible for supplying it, mirroring the Compound name/strength
  /// snapshot); a null [DoseSnapshotDraft.protocolId] always normalizes to a
  /// fully untagged Dose, discarding any stray name. This is a soft
  /// reference — it never queries the `protocols` table, so a Dose never
  /// depends on a live Protocol row (self-description holds, PROTOCOLS.md
  /// §1.1).
  ({String? protocolId, String? protocolName}) _validateDoseProtocolTag(
    DoseSnapshotDraft draft,
  ) {
    final protocolId = draft.protocolId;
    if (protocolId == null) {
      return (protocolId: null, protocolName: null);
    }
    final protocolName = draft.protocolName?.trim() ?? '';
    if (protocolName.isEmpty) {
      throw ArgumentError.value(
        draft.protocolName,
        'protocolName',
        'A Dose tagged to a Protocol requires its name snapshot.',
      );
    }
    return (protocolId: protocolId, protocolName: protocolName);
  }

  Future<void> _tagDoseToProtocol(
    String doseId,
    String? protocolId,
    _WriteContext context,
  ) async {
    final before = await _requireDoseRow(doseId);

    // Resolving the CURRENT Protocol name only happens at the moment of
    // tagging — once written, the Dose reads its own frozen snapshot, never
    // a live Protocol row (§1.1). Any Protocol (including an archived one)
    // may be tagged; tagging never cascades either way (PROTOCOLS.md §7).
    String? protocolName;
    if (protocolId != null) {
      final protocolRow = await _requireProtocolRow(protocolId);
      protocolName = protocolRow.name;
    }

    if (before.protocolId == protocolId &&
        before.protocolName == protocolName) {
      return;
    }

    await (_database.update(_database.doses)
          ..where((row) => row.id.equals(doseId)))
        .write(
      DosesCompanion(
        protocolId: Value<String?>(protocolId),
        protocolName: Value<String?>(protocolName),
        updatedAt: Value<DateTime>(context.timestamp),
      ),
    );

    final after = await _requireDoseRow(doseId);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.dosesTable,
      entityId: doseId,
      beforeImage: _doseImage(before),
      afterImage: _doseImage(after),
    );
  }

  /// Lists active (non-archived) `Compound`s, newest name order. Archived
  /// Compounds drop from pickers but their history survives (PROTOCOLS.md §7).
  Future<List<CompoundRecord>> listCompounds() async {
    final rows = await _activeCompoundQuery().get();
    return rows.map(_compoundFromRow).toList(growable: false);
  }

  /// Lists active `Compound` source options for read paths that only need a
  /// label. Full `CompoundRecord`s remain available to Dose logging, where
  /// default unit/route and strength are part of the self-describing snapshot.
  Future<List<CompoundOptionRecord>> listCompoundOptions() async {
    final rows = await _activeCompoundQuery().get();
    return _compoundOptionsFromRows(rows);
  }

  /// Lists active `Compound` schedule options for Protocol plan editors. This
  /// carries the default unit/route needed to seed a `Schedule`, without
  /// subscribing those editors to strength/favorite/detail-only changes.
  Future<List<CompoundScheduleOptionRecord>>
      listCompoundScheduleOptions() async {
    final rows = await _activeCompoundQuery().get();
    return _compoundScheduleOptionsFromRows(rows);
  }

  Stream<List<CompoundRecord>> watchCompounds() {
    return _activeCompoundQuery().watch().map(
          (rows) => rows.map(_compoundFromRow).toList(growable: false),
        );
  }

  /// Reactive variant of [listCompoundOptions]. It emits only when the visible
  /// option set changes, so strength/default/favorite edits do not rebuild
  /// source pickers that only render `Compound` identity.
  Stream<List<CompoundOptionRecord>> watchCompoundOptions() {
    return _activeCompoundQuery()
        .watch()
        .map(_compoundOptionsFromRows)
        .distinct(_sameCompoundOptionRecords);
  }

  /// Reactive variant of [listCompoundScheduleOptions]. It emits when the
  /// visible schedule seed data changes (id/name/default unit/default route),
  /// while suppressing strength/favorite/detail-only Compound edits.
  Stream<List<CompoundScheduleOptionRecord>> watchCompoundScheduleOptions() {
    return _activeCompoundQuery()
        .watch()
        .map(_compoundScheduleOptionsFromRows)
        .distinct(_sameCompoundScheduleOptionRecords);
  }

  Stream<Map<String, String>> watchCompoundNamesByIds(Set<String> ids) {
    if (ids.isEmpty) {
      return Stream<Map<String, String>>.value(const <String, String>{});
    }

    return _activeCompoundQuery(ids: ids).watch().map((rows) {
      return Map<String, String>.unmodifiable(
        <String, String>{for (final row in rows) row.id: row.name},
      );
    }).distinct(_stringMapEquals);
  }

  /// Sets a Compound's [isFavorite] UI-affordance flag, mirroring
  /// `ExerciseRepository.setFavorite`. A no-op transaction (no Activity Log
  /// entry) when the flag is already at the requested value. One reversible
  /// Activity Log batch otherwise.
  Future<void> setFavorite(
    String compoundId, {
    required bool isFavorite,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireCompoundRow(compoundId);
      if (before.isFavorite == isFavorite) {
        return;
      }
      await (_database.update(_database.compounds)
            ..where((row) => row.id.equals(compoundId)))
          .write(
        CompoundsCompanion(
          isFavorite: Value<bool>(isFavorite),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireCompoundRow(compoundId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.compoundsTable,
        entityId: compoundId,
        beforeImage: _compoundImage(before),
        afterImage: _compoundImage(after),
      );
    });
  }

  /// The most recently logged distinct Compounds, DERIVED on read from each
  /// Compound's most recent (non-deleted) `Dose.tookAt` — nothing stored.
  /// Small N (default 5): a "recently logged" shortlist, not a
  /// history view. A Compound with no Doses never appears; an archived
  /// Compound is excluded (mirrors [watchCompounds]).
  Future<List<CompoundRecord>> recentCompounds({int limit = 5}) async {
    final rows = await _recentCompoundRows(limit: limit);
    return rows.map(_compoundFromRow).toList(growable: false);
  }

  /// Lightweight id-only variant for the Compound list's Recent section. The
  /// list screen already watches the full active library for Dose logging
  /// defaults, so recency only needs ordered ids from Dose history.
  Future<List<String>> recentCompoundIds({int limit = 5}) {
    return _recentCompoundIdQuery(limit: limit).get();
  }

  /// Reactive variant of [recentCompounds]: a `readsFrom` on both
  /// `compounds`/`doses` re-emits whenever EITHER table changes, so the
  /// derived recency ordering invalidates mechanically (no stored cache).
  Stream<List<CompoundRecord>> watchRecentCompounds({int limit = 5}) {
    return _recentCompoundQuery(limit: limit).watch().map(
          (rows) => rows.map(_compoundFromRow).toList(growable: false),
        );
  }

  /// Reactive id-only variant of [recentCompoundIds]. Table invalidations still
  /// come from both `doses` and `compounds` so archives are reflected, but
  /// unrelated Compound detail edits are filtered out by id-list equality.
  Stream<List<String>> watchRecentCompoundIds({int limit = 5}) {
    return _recentCompoundIdQuery(limit: limit)
        .watch()
        .distinct(_sameStringList);
  }

  Future<List<CompoundRow>> _recentCompoundRows({required int limit}) {
    return _recentCompoundQuery(limit: limit).get();
  }

  Selectable<String> _recentCompoundIdQuery({required int limit}) {
    return _database.customSelect(
      '''
      SELECT recent.compound_id AS compound_id FROM compounds c
      INNER JOIN (
        SELECT compound_id, MAX(took_at) AS last_took_at
        FROM doses
        WHERE deleted_at IS NULL AND compound_id IS NOT NULL
        GROUP BY compound_id
      ) recent ON recent.compound_id = c.id
      WHERE c.deleted_at IS NULL
      ORDER BY recent.last_took_at DESC
      LIMIT ?1
      ''',
      variables: [Variable<int>(limit)],
      readsFrom: {_database.compounds, _database.doses},
    ).map((row) => row.data['compound_id']! as String);
  }

  /// Distinct compoundId ordered by the most recent Dose.tookAt: a raw SQL
  /// aggregate is simplest here (Drift's query builder has no clean
  /// group-by-max-then-join shorthand), scoped to non-deleted Doses with a
  /// soft `compoundId` reference, joined back to the ACTIVE Compound.
  Selectable<CompoundRow> _recentCompoundQuery({required int limit}) {
    return _database.customSelect(
      '''
      SELECT c.* FROM compounds c
      INNER JOIN (
        SELECT compound_id, MAX(took_at) AS last_took_at
        FROM doses
        WHERE deleted_at IS NULL AND compound_id IS NOT NULL
        GROUP BY compound_id
      ) recent ON recent.compound_id = c.id
      WHERE c.deleted_at IS NULL
      ORDER BY recent.last_took_at DESC
      LIMIT ?1
      ''',
      variables: [Variable<int>(limit)],
      readsFrom: {_database.compounds, _database.doses},
    ).map((row) => _database.compounds.map(row.data));
  }

  /// The Compound's most recently logged (non-deleted) `Dose`, DERIVED on read
  /// — nothing stored. Seeds the ≤2-tap "prefill-from-last" Dose
  /// entry sheet (PROTOCOLS.md §5): null when the Compound has never
  /// been logged, so the caller falls back to its default unit/route.
  Future<DoseRecord?> lastDoseFor(String compoundId) async {
    final rows = await _lastDoseQuery(compoundId).get();
    return rows.isEmpty ? null : _doseFromRow(rows.single);
  }

  /// Reactive variant of [lastDoseFor]: a `readsFrom` on `doses` re-emits
  /// whenever a Dose for this Compound is logged/edited/deleted, so the
  /// prefill invalidates mechanically (mirrors the Future/Stream pairing used
  /// throughout this repository, e.g. [recentCompounds]/[watchRecentCompounds]).
  Stream<DoseRecord?> watchLastDose(String compoundId) {
    return _lastDoseQuery(compoundId).watch().map(
          (rows) => rows.isEmpty ? null : _doseFromRow(rows.single),
        );
  }

  SimpleSelectStatement<$DosesTable, DoseRow> _lastDoseQuery(
    String compoundId,
  ) {
    return _database.select(_database.doses)
      ..where(
        (row) => row.deletedAt.isNull() & row.compoundId.equals(compoundId),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.tookAt)])
      ..limit(1);
  }

  /// The ACTUAL logged `Dose`s for [compoundId] (any Protocol tag, or none —
  /// an ad-hoc `Effect` window over a single Compound), oldest
  /// first.
  Future<List<DoseRecord>> dosesForCompound(String compoundId) async {
    final rows = await (_database.select(_database.doses)
          ..where(
            (row) => row.deletedAt.isNull() & row.compoundId.equals(compoundId),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.tookAt)]))
        .get();
    return rows.map(_doseFromRow).toList(growable: false);
  }

  /// The ACTUAL logged `Dose`s TAGGED to [protocolId] (PROTOCOLS.md §1.4,
  ///), oldest first — the dose-overlay timeline's source for a
  /// `Protocol` window. An untagged Dose of a member `Compound` is
  /// EXCLUDED, even if logged during the Protocol's dates: the overlay reads
  /// the actual tag on the Dose, never infers it from the Compound/window.
  Future<List<DoseRecord>> dosesForProtocol(String protocolId) async {
    final rows = await (_database.select(_database.doses)
          ..where(
            (row) => row.deletedAt.isNull() & row.protocolId.equals(protocolId),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.tookAt)]))
        .get();
    return rows.map(_doseFromRow).toList(growable: false);
  }

  /// The derived `Protocol Day` for [localDate]: the day's `Dose`s grouped by
  /// their frozen local date, computed on read (nothing stored).
  Future<ProtocolDayRecord> protocolDay(ProtocolDayDate localDate) async {
    final rows = await _activeDoseQuery(localDate: localDate).get();
    return _protocolDayFromRows(localDate, rows);
  }

  /// Reactive variant of [protocolDay]: re-emits whenever any `Dose` changes,
  /// so the derived day-view invalidates mechanically (no recalculate path).
  Stream<ProtocolDayRecord> watchProtocolDay(ProtocolDayDate localDate) {
    return _activeDoseQuery(localDate: localDate).watch().map(
          (rows) => _protocolDayFromRows(localDate, rows),
        );
  }

  SimpleSelectStatement<$CompoundsTable, CompoundRow> _activeCompoundQuery({
    Set<String>? ids,
  }) {
    return _database.select(_database.compounds)
      ..where((row) {
        var predicate = row.deletedAt.isNull();
        if (ids != null) {
          predicate = predicate & row.id.isIn(ids);
        }
        return predicate;
      })
      ..orderBy([
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.id),
      ]);
  }

  SimpleSelectStatement<$DosesTable, DoseRow> _activeDoseQuery({
    ProtocolDayDate? localDate,
  }) {
    final query = _database.select(_database.doses)
      ..where((row) {
        var predicate = row.deletedAt.isNull();
        if (localDate != null) {
          predicate = predicate & row.localDate.equals(localDate.storageValue);
        }
        return predicate;
      })
      ..orderBy([
        (row) => OrderingTerm.asc(row.tookAt),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query;
  }

  ProtocolDayRecord _protocolDayFromRows(
    ProtocolDayDate localDate,
    List<DoseRow> rows,
  ) {
    return ProtocolDayRecord(
      localDate: localDate,
      doses: rows.map(_doseFromRow).toList(growable: false),
    );
  }

  CompoundRecord _compoundFromRow(CompoundRow row) {
    return CompoundRecord(
      id: row.id,
      name: row.name,
      // Curated registries are enforced on read too: a unit/route outside the
      // registry is rejected rather than silently surfaced.
      defaultUnit: doseUnitFromName(row.defaultUnit),
      defaultRoute: doseRouteFromName(row.defaultRoute),
      strength: CompoundStrength.tryParse(row.strength),
      isFavorite: row.isFavorite,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }

  List<CompoundOptionRecord> _compoundOptionsFromRows(
    List<CompoundRow> rows,
  ) {
    return rows.map(_compoundOptionFromRow).toList(growable: false);
  }

  CompoundOptionRecord _compoundOptionFromRow(CompoundRow row) {
    return CompoundOptionRecord(id: row.id, name: row.name);
  }

  List<CompoundScheduleOptionRecord> _compoundScheduleOptionsFromRows(
    List<CompoundRow> rows,
  ) {
    return rows.map(_compoundScheduleOptionFromRow).toList(growable: false);
  }

  CompoundScheduleOptionRecord _compoundScheduleOptionFromRow(
    CompoundRow row,
  ) {
    return CompoundScheduleOptionRecord(
      id: row.id,
      name: row.name,
      defaultUnit: doseUnitFromName(row.defaultUnit),
      defaultRoute: doseRouteFromName(row.defaultRoute),
    );
  }

  DoseRecord _doseFromRow(DoseRow row) {
    return DoseRecord(
      id: row.id,
      compoundId: row.compoundId,
      compoundName: row.compoundName,
      // The frozen strength snapshot re-parses to its structure so the resolved
      // active mass can be derived on read (PROTOCOLS.md §1.3).
      compoundStrength: CompoundStrength.tryParse(row.compoundStrength),
      amountValue: row.amountValue,
      amountEntered: row.amountEntered,
      unit: doseUnitFromName(row.unit),
      route: doseRouteFromName(row.route),
      tookAt: row.tookAt,
      timezone: row.timezone,
      localDate: ProtocolDayDate.parse(row.localDate),
      provenance: DoseProvenance.values.byName(row.provenance),
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
      protocolId: row.protocolId,
      protocolName: row.protocolName,
    );
  }

  Future<CompoundRow> _requireCompoundRow(String id) async {
    final row = await (_database.select(_database.compounds)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Compound not found: $id.');
    }
    return row;
  }

  Future<DoseRow> _requireDoseRow(String id) async {
    final row = await (_database.select(_database.doses)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Dose not found: $id.');
    }
    return row;
  }

  // ---------------------------------------------------------------------
  // `Protocol` (PROTOCOLS.md §1.4): the Routine analog — a named,
  // time-bounded plan grouping one or more Compounds (a stack). A MUTABLE
  // PLAN: every write below touches only `protocols`/`protocol_compounds`/
  // `protocol_target_outcomes`, NEVER a logged `Dose`. Schedules
  // and target outcomes + the Dose tag (seeding the later Effect
  // view — no analysis here) have landed; sync is still a later M28 slice —
  // this stays local-first like the rest of the domain until then.
  // ---------------------------------------------------------------------

  /// Creates a `Protocol` (one or more Compounds — a stack). One reversible
  /// Activity Log batch covering the Protocol row and every member row.
  Future<CreateProtocolResult> createProtocol(
    ProtocolDraft draft, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final id = await _createProtocol(draft, context);
      return CreateProtocolResult(batchId: context.batchId, protocolId: id);
    });
  }

  /// Edits a `Protocol`'s name/window and reconciles its membership to
  /// exactly [ProtocolDraft.compoundIds] (added/removed/reordered). Mutates
  /// the live Protocol plan ONLY — by design it never reads or writes a
  /// logged `Dose` (§1.4). One reversible Activity Log batch.
  Future<String> editProtocol(
    String protocolId,
    ProtocolDraft draft, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      await _editProtocol(protocolId, draft, context);
      return context.batchId;
    });
  }

  /// Archives a `Protocol` (soft-delete via `deletedAt`): it drops from the
  /// active list but its history survives, and this never cascades to a
  /// logged `Dose` (PROTOCOLS.md §7). One reversible Activity Log batch.
  Future<String> archiveProtocol(
    String protocolId, {
    String actor = 'manual',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      await _setProtocolDeletedAt(protocolId, context.timestamp, context);
      return context.batchId;
    });
  }

  /// Lists active (non-archived) `Protocol`s with their ordered members (each
  /// carrying its optional `Schedule`) and declared target outcomes,
  /// newest-name order.
  Future<List<ProtocolRecord>> listProtocols() async {
    final protocolRows = await _activeProtocolQuery().get();
    final memberRows = await _activeProtocolCompoundQuery().get();
    final scheduleRows = await _activeScheduleQuery().get();
    final targetOutcomeRows = await _activeProtocolTargetOutcomeQuery().get();
    return _protocolsFromRows(
      protocolRows,
      memberRows,
      scheduleRows,
      targetOutcomeRows,
    );
  }

  /// Lists active `Protocol` row summaries for the Protocol landing screen.
  /// Schedules and target outcomes are loaded only by detail/edit reads.
  Future<List<ProtocolSummaryRecord>> listProtocolSummaries() async {
    final protocolRows = await _activeProtocolQuery().get();
    final memberRows = await _activeProtocolCompoundQuery().get();
    return _protocolSummariesFromRows(protocolRows, memberRows);
  }

  /// Lists active `Protocol` tag options for Dose logging. This deliberately
  /// reads only the Protocol row identity needed for the Dose's self-described
  /// optional tag; membership, Schedules, and target outcomes are detail reads.
  Future<List<ProtocolOptionRecord>> listProtocolOptions() async {
    final protocolRows = await _activeProtocolQuery().get();
    return _protocolOptionsFromRows(protocolRows);
  }

  /// Reactive variant of [listProtocolOptions]. It emits only when the visible
  /// tag option set changes, so plan-detail edits do not rebuild Dose logging.
  Stream<List<ProtocolOptionRecord>> watchProtocolOptions() {
    return _activeProtocolQuery()
        .watch()
        .map(_protocolOptionsFromRows)
        .distinct(_sameProtocolOptionRecords);
  }

  /// Lists active `Protocol` options for the Effect source picker. This carries
  /// the target outcomes needed to seed Effect selections, while intentionally
  /// excluding Protocol members and Schedules.
  Future<List<ProtocolEffectOptionRecord>> listProtocolEffectOptions() async {
    final protocolRows = await _activeProtocolQuery().get();
    final targetOutcomeRows = await _activeProtocolTargetOutcomeQuery().get();
    return _protocolEffectOptionsFromRows(protocolRows, targetOutcomeRows);
  }

  /// Reactive variant of [listProtocolEffectOptions]. It re-emits when a
  /// Protocol's visible identity or declared target outcomes change, not when
  /// membership/Schedule plan details change.
  Stream<List<ProtocolEffectOptionRecord>> watchProtocolEffectOptions() {
    late final StreamSubscription<List<ProtocolRow>> protocolSubscription;
    late final StreamSubscription<List<ProtocolTargetOutcomeRow>>
        targetOutcomeSubscription;
    final controller = StreamController<List<ProtocolEffectOptionRecord>>();
    List<ProtocolRow>? latestProtocols;
    List<ProtocolTargetOutcomeRow>? latestTargetOutcomes;
    List<ProtocolEffectOptionRecord>? lastEmitted;

    void emitIfReady() {
      final protocolRows = latestProtocols;
      final targetOutcomeRows = latestTargetOutcomes;
      if (protocolRows == null || targetOutcomeRows == null) {
        return;
      }

      final next = _protocolEffectOptionsFromRows(
        protocolRows,
        targetOutcomeRows,
      );
      if (lastEmitted != null &&
          _sameProtocolEffectOptionRecords(lastEmitted!, next)) {
        return;
      }
      lastEmitted = next;
      controller.add(next);
    }

    controller.onListen = () {
      protocolSubscription = _activeProtocolQuery().watch().listen(
        (rows) {
          latestProtocols = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
      targetOutcomeSubscription =
          _activeProtocolTargetOutcomeQuery().watch().listen(
        (rows) {
          latestTargetOutcomes = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () async {
      await protocolSubscription.cancel();
      await targetOutcomeSubscription.cancel();
    };

    return controller.stream;
  }

  /// Reactive variant of [listProtocolSummaries]. It emits when a Protocol row
  /// or ordered membership changes, not when Schedule or target-outcome detail
  /// changes.
  Stream<List<ProtocolSummaryRecord>> watchProtocolSummaries() {
    late final StreamSubscription<List<ProtocolRow>> protocolSubscription;
    late final StreamSubscription<List<ProtocolCompoundRow>> memberSubscription;
    final controller = StreamController<List<ProtocolSummaryRecord>>();
    List<ProtocolRow>? latestProtocols;
    List<ProtocolCompoundRow>? latestMembers;
    List<ProtocolSummaryRecord>? lastEmitted;

    void emitIfReady() {
      final protocolRows = latestProtocols;
      final memberRows = latestMembers;
      if (protocolRows == null || memberRows == null) {
        return;
      }

      final next = _protocolSummariesFromRows(protocolRows, memberRows);
      if (lastEmitted != null &&
          _sameProtocolSummaryRecords(lastEmitted!, next)) {
        return;
      }
      lastEmitted = next;
      controller.add(next);
    }

    controller.onListen = () {
      protocolSubscription = _activeProtocolQuery().watch().listen(
        (rows) {
          latestProtocols = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
      memberSubscription = _activeProtocolCompoundQuery().watch().listen(
        (rows) {
          latestMembers = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () async {
      await protocolSubscription.cancel();
      await memberSubscription.cancel();
    };

    return controller.stream;
  }

  /// Reactive variant of [listProtocols]: re-emits whenever a `Protocol`, its
  /// membership, a member's `Schedule`, or its target outcomes change.
  Stream<List<ProtocolRecord>> watchProtocols() {
    late final StreamSubscription<List<ProtocolRow>> protocolSubscription;
    late final StreamSubscription<List<ProtocolCompoundRow>> memberSubscription;
    late final StreamSubscription<List<ScheduleRow>> scheduleSubscription;
    late final StreamSubscription<List<ProtocolTargetOutcomeRow>>
        targetOutcomeSubscription;
    final controller = StreamController<List<ProtocolRecord>>();
    List<ProtocolRow>? latestProtocols;
    List<ProtocolCompoundRow>? latestMembers;
    List<ScheduleRow>? latestSchedules;
    List<ProtocolTargetOutcomeRow>? latestTargetOutcomes;

    void emitIfReady() {
      final protocolRows = latestProtocols;
      final memberRows = latestMembers;
      final scheduleRows = latestSchedules;
      final targetOutcomeRows = latestTargetOutcomes;
      if (protocolRows == null ||
          memberRows == null ||
          scheduleRows == null ||
          targetOutcomeRows == null) {
        return;
      }
      controller.add(
        _protocolsFromRows(
          protocolRows,
          memberRows,
          scheduleRows,
          targetOutcomeRows,
        ),
      );
    }

    controller.onListen = () {
      protocolSubscription = _activeProtocolQuery().watch().listen(
        (rows) {
          latestProtocols = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
      memberSubscription = _activeProtocolCompoundQuery().watch().listen(
        (rows) {
          latestMembers = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
      scheduleSubscription = _activeScheduleQuery().watch().listen(
        (rows) {
          latestSchedules = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
      targetOutcomeSubscription =
          _activeProtocolTargetOutcomeQuery().watch().listen(
        (rows) {
          latestTargetOutcomes = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () async {
      await protocolSubscription.cancel();
      await memberSubscription.cancel();
      await scheduleSubscription.cancel();
      await targetOutcomeSubscription.cancel();
    };

    return controller.stream;
  }

  /// Reactive detail stream for one active `Protocol`. This powers selected
  /// read paths (like the `Effect` view) without subscribing to every Protocol
  /// plan and every Schedule in the library.
  Stream<ProtocolRecord?> watchProtocol(String id) {
    late final StreamSubscription<List<ProtocolRow>> protocolSubscription;
    late final StreamSubscription<List<ProtocolCompoundRow>> memberSubscription;
    StreamSubscription<List<ScheduleRow>>? scheduleSubscription;
    late final StreamSubscription<List<ProtocolTargetOutcomeRow>>
        targetOutcomeSubscription;
    final controller = StreamController<ProtocolRecord?>();
    List<ProtocolRow>? latestProtocols;
    List<ProtocolCompoundRow>? latestMembers;
    List<ScheduleRow>? latestSchedules;
    List<ProtocolTargetOutcomeRow>? latestTargetOutcomes;
    var subscribedScheduleMemberIds = const <String>{};
    ProtocolRecord? lastEmitted;
    var emittedNull = false;

    void addIfChanged(ProtocolRecord? protocol) {
      if (protocol == null) {
        if (emittedNull && lastEmitted == null) {
          return;
        }
        emittedNull = true;
        lastEmitted = null;
        controller.add(null);
        return;
      }

      if (_sameProtocolRecord(lastEmitted, protocol)) {
        return;
      }
      emittedNull = false;
      lastEmitted = protocol;
      controller.add(protocol);
    }

    void emitIfReady() {
      final protocolRows = latestProtocols;
      if (protocolRows == null) {
        return;
      }
      if (protocolRows.isEmpty) {
        addIfChanged(null);
        return;
      }

      final memberRows = latestMembers;
      final scheduleRows = latestSchedules;
      final targetOutcomeRows = latestTargetOutcomes;
      if (memberRows == null ||
          scheduleRows == null ||
          targetOutcomeRows == null) {
        return;
      }

      addIfChanged(
        _protocolsFromRows(
          protocolRows,
          memberRows,
          scheduleRows,
          targetOutcomeRows,
        ).single,
      );
    }

    void subscribeToSchedules(List<ProtocolCompoundRow> memberRows) {
      final nextIds = memberRows.map((row) => row.id).toSet();
      if (_sameStringSet(nextIds, subscribedScheduleMemberIds) &&
          scheduleSubscription != null) {
        return;
      }

      subscribedScheduleMemberIds = nextIds;
      latestSchedules = null;
      unawaited(scheduleSubscription?.cancel());
      scheduleSubscription = null;
      if (nextIds.isEmpty) {
        latestSchedules = const <ScheduleRow>[];
        emitIfReady();
        return;
      }

      scheduleSubscription = _activeScheduleQuery(
        protocolCompoundIds: nextIds,
      ).watch().listen(
        (rows) {
          if (!_sameStringSet(nextIds, subscribedScheduleMemberIds)) {
            return;
          }
          latestSchedules = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    }

    controller.onListen = () {
      protocolSubscription = _activeProtocolQuery(id: id).watch().listen(
        (rows) {
          latestProtocols = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
      memberSubscription = _activeProtocolCompoundQuery(
        protocolId: id,
      ).watch().listen(
        (rows) {
          latestMembers = rows;
          subscribeToSchedules(rows);
          emitIfReady();
        },
        onError: controller.addError,
      );
      targetOutcomeSubscription = _activeProtocolTargetOutcomeQuery(
        protocolId: id,
      ).watch().listen(
        (rows) {
          latestTargetOutcomes = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () async {
      await protocolSubscription.cancel();
      await memberSubscription.cancel();
      await scheduleSubscription?.cancel();
      await targetOutcomeSubscription.cancel();
    };

    return controller.stream;
  }

  Future<String> _createProtocol(
    ProtocolDraft draft,
    _WriteContext context,
  ) async {
    final name = _validateProtocolName(draft.name);
    _validateProtocolWindow(draft.startDate, draft.endDate);
    final compoundIds = _validateProtocolMembership(draft.compoundIds);
    final compoundRows = await _requireActiveCompoundRows(compoundIds);
    final targetOutcomes = _validateProtocolTargetOutcomes(
      draft.targetOutcomes,
    );
    await _requireActiveMetricRows(_metricIdsOf(targetOutcomes));

    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.protocols).insert(
          ProtocolsCompanion.insert(
            id: id,
            name: name,
            startDate: draft.startDate.toUtc(),
            endDate: Value<DateTime?>(draft.endDate?.toUtc()),
            updatedAt: context.timestamp,
          ),
        );
    final after = await _requireProtocolRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.protocolsTable,
      entityId: id,
      beforeImage: null,
      afterImage: _protocolImage(after),
    );

    for (var index = 0; index < compoundRows.length; index += 1) {
      final compoundId = compoundRows[index].id;
      final memberId = await _insertProtocolMember(
        protocolId: id,
        compoundId: compoundId,
        position: index,
        context: context,
      );
      await _reconcileSchedule(
        memberId,
        draft.schedulesByCompoundId[compoundId],
        context,
      );
    }

    await _replaceProtocolTargetOutcomes(id, targetOutcomes, context);

    return id;
  }

  Future<void> _editProtocol(
    String protocolId,
    ProtocolDraft draft,
    _WriteContext context,
  ) async {
    final before = await _requireProtocolRow(protocolId);
    if (before.deletedAt != null) {
      throw StateError('Protocol is archived: $protocolId.');
    }
    final name = _validateProtocolName(draft.name);
    _validateProtocolWindow(draft.startDate, draft.endDate);
    final compoundIds = _validateProtocolMembership(draft.compoundIds);
    final compoundRows = await _requireActiveCompoundRows(compoundIds);
    final targetOutcomes = _validateProtocolTargetOutcomes(
      draft.targetOutcomes,
    );
    await _requireActiveMetricRows(_metricIdsOf(targetOutcomes));

    final startDate = draft.startDate.toUtc();
    final endDate = draft.endDate?.toUtc();
    if (before.name != name ||
        before.startDate != startDate ||
        before.endDate != endDate) {
      await (_database.update(_database.protocols)
            ..where((row) => row.id.equals(protocolId)))
          .write(
        ProtocolsCompanion(
          name: Value<String>(name),
          startDate: Value<DateTime>(startDate),
          endDate: Value<DateTime?>(endDate),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireProtocolRow(protocolId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.protocolsTable,
        entityId: protocolId,
        beforeImage: _protocolImage(before),
        afterImage: _protocolImage(after),
      );
    }

    await _replaceProtocolMembers(
      protocolId,
      compoundRows.map((row) => row.id).toList(growable: false),
      draft.schedulesByCompoundId,
      context,
    );

    await _replaceProtocolTargetOutcomes(protocolId, targetOutcomes, context);
  }

  Future<void> _setProtocolDeletedAt(
    String protocolId,
    DateTime deletedAt,
    _WriteContext context,
  ) async {
    final before = await _requireProtocolRow(protocolId);
    await (_database.update(_database.protocols)
          ..where((row) => row.id.equals(protocolId)))
        .write(
      ProtocolsCompanion(
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: Value<DateTime?>(deletedAt),
      ),
    );

    final after = await _requireProtocolRow(protocolId);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.protocolsTable,
      entityId: protocolId,
      beforeImage: _protocolImage(before),
      afterImage: _protocolImage(after),
    );
  }

  Future<String> _insertProtocolMember({
    required String protocolId,
    required String compoundId,
    required int position,
    required _WriteContext context,
  }) async {
    final memberId = _repositories.createId(context.timestamp);
    await _database.into(_database.protocolCompounds).insert(
          ProtocolCompoundsCompanion.insert(
            id: memberId,
            protocolId: protocolId,
            compoundId: compoundId,
            position: position,
            updatedAt: context.timestamp,
          ),
        );
    final member = await _requireProtocolCompoundRow(memberId);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.protocolCompoundsTable,
      entityId: memberId,
      beforeImage: null,
      afterImage: _protocolCompoundImage(member),
    );
    return memberId;
  }

  /// Reconciles a `Protocol`'s membership to exactly [compoundIds] (mirrors
  /// `_replaceRoutineExerciseGroupMembers`): removed members are tombstoned
  /// (along with their `Schedule`, if any), new ones inserted, and
  /// kept ones repositioned in place. [schedulesByCompoundId] reconciles each
  /// KEPT/NEW member's optional `Schedule` too, regardless of whether its
  /// position changed.
  Future<void> _replaceProtocolMembers(
    String protocolId,
    List<String> compoundIds,
    Map<String, ScheduleDraft?> schedulesByCompoundId,
    _WriteContext context,
  ) async {
    final activeRows = await _activeProtocolCompoundQuery(
      protocolId: protocolId,
    ).get();
    final activeByCompoundId = <String, ProtocolCompoundRow>{
      for (final row in activeRows) row.compoundId: row,
    };
    final targetIds = compoundIds.toSet();

    for (final row in activeRows) {
      if (!targetIds.contains(row.compoundId)) {
        await (_database.update(_database.protocolCompounds)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ProtocolCompoundsCompanion(
            updatedAt: Value<DateTime>(context.timestamp),
            deletedAt: Value<DateTime?>(context.timestamp),
          ),
        );
        final after = await _requireProtocolCompoundRow(row.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.protocolCompoundsTable,
          entityId: row.id,
          beforeImage: _protocolCompoundImage(row),
          afterImage: _protocolCompoundImage(after),
        );
        // The member is gone — its Schedule (if any) retires with it. No
        // orphaned plan row (PROTOCOLS.md §1.4, §7).
        await _reconcileSchedule(row.id, null, context);
      }
    }

    for (var index = 0; index < compoundIds.length; index += 1) {
      final compoundId = compoundIds[index];
      final existing = activeByCompoundId[compoundId];
      final desiredSchedule = schedulesByCompoundId[compoundId];
      if (existing == null) {
        final memberId = await _insertProtocolMember(
          protocolId: protocolId,
          compoundId: compoundId,
          position: index,
          context: context,
        );
        await _reconcileSchedule(memberId, desiredSchedule, context);
        continue;
      }

      if (existing.position != index) {
        await (_database.update(_database.protocolCompounds)
              ..where((table) => table.id.equals(existing.id)))
            .write(
          ProtocolCompoundsCompanion(
            position: Value<int>(index),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        final after = await _requireProtocolCompoundRow(existing.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.protocolCompoundsTable,
          entityId: existing.id,
          beforeImage: _protocolCompoundImage(existing),
          afterImage: _protocolCompoundImage(after),
        );
      }

      await _reconcileSchedule(existing.id, desiredSchedule, context);
    }
  }

  /// Reconciles ONE member's optional `Schedule` to [desired]: null
  /// tombstones an existing Schedule (or is a no-op with none); a non-null
  /// draft creates a new Schedule row, or updates an existing one in place —
  /// never a new identity. Runs the SAME shared two-tier validator as a
  /// logged `Dose` (PROTOCOLS.md §6, `validateDose`) against the planned dose
  /// amount/unit/route — a hard-reject throws before anything persists; there
  /// is NO parallel Schedule validator. Purely plan-layer: never reads or
  /// writes a logged `Dose`.
  Future<void> _reconcileSchedule(
    String protocolCompoundId,
    ScheduleDraft? desired,
    _WriteContext context,
  ) async {
    final existing = await _activeScheduleQuery(
      protocolCompoundId: protocolCompoundId,
    ).getSingleOrNull();

    if (desired == null) {
      if (existing == null) {
        return;
      }
      await (_database.update(_database.schedules)
            ..where((row) => row.id.equals(existing.id)))
          .write(
        SchedulesCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireScheduleRow(existing.id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.schedulesTable,
        entityId: existing.id,
        beforeImage: _scheduleImage(existing),
        afterImage: _scheduleImage(after),
      );
      return;
    }

    final amountEntered = desired.doseAmountEntered.trim();
    if (amountEntered.isEmpty) {
      throw ArgumentError.value(
        desired.doseAmountEntered,
        'doseAmountEntered',
        'Entered Schedule dose amount must not be empty.',
      );
    }
    // PROTOCOLS.md §6: the SAME shared two-tier validator a logged Dose runs
    // — a hard-reject (e.g. negative amount, absurd per-dose cap, malformed
    // unit/route) throws here so nothing persists.
    final validation = validateDose(
      amount: amountEntered,
      unit: desired.doseUnit.name,
      route: desired.route.name,
    );
    validation.throwIfRejected();

    if (existing == null) {
      final scheduleId = _repositories.createId(context.timestamp);
      await _database.into(_database.schedules).insert(
            SchedulesCompanion.insert(
              id: scheduleId,
              protocolCompoundId: protocolCompoundId,
              doseAmountValue: desired.doseAmountValue,
              doseAmountEntered: amountEntered,
              doseUnit: desired.doseUnit.name,
              frequency: desired.frequency.name,
              route: desired.route.name,
              updatedAt: context.timestamp,
            ),
          );
      final after = await _requireScheduleRow(scheduleId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.schedulesTable,
        entityId: scheduleId,
        beforeImage: null,
        afterImage: _scheduleImage(after),
      );
      return;
    }

    final unchanged = existing.doseAmountValue == desired.doseAmountValue &&
        existing.doseAmountEntered == amountEntered &&
        existing.doseUnit == desired.doseUnit.name &&
        existing.frequency == desired.frequency.name &&
        existing.route == desired.route.name;
    if (unchanged) {
      return;
    }

    await (_database.update(_database.schedules)
          ..where((row) => row.id.equals(existing.id)))
        .write(
      SchedulesCompanion(
        doseAmountValue: Value<double>(desired.doseAmountValue),
        doseAmountEntered: Value<String>(amountEntered),
        doseUnit: Value<String>(desired.doseUnit.name),
        frequency: Value<String>(desired.frequency.name),
        route: Value<String>(desired.route.name),
        updatedAt: Value<DateTime>(context.timestamp),
      ),
    );
    final after = await _requireScheduleRow(existing.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.schedulesTable,
      entityId: existing.id,
      beforeImage: _scheduleImage(existing),
      afterImage: _scheduleImage(after),
    );
  }

  /// The identity key for ONE target outcome (kind + Metric id):
  /// what [_replaceProtocolTargetOutcomes] diffs existing rows against, and
  /// what [_validateProtocolTargetOutcomes] uses to reject a duplicate.
  String _protocolTargetOutcomeKey(String kindName, String? metricId) {
    return '$kindName|${metricId ?? ''}';
  }

  /// Reconciles a `Protocol`'s declared target outcomes to exactly [outcomes]
  /// (mirrors [_replaceProtocolMembers]): outcomes no longer present
  /// are tombstoned, new ones inserted, and kept ones repositioned in place.
  /// [outcomes] must already be validated ([_validateProtocolTargetOutcomes])
  /// and its Metric ids confirmed active ([_requireActiveMetricRows]). Purely
  /// plan-layer: never reads or writes a logged `Dose`, and computes NO
  /// `Effect` (that analysis is a later M29 slice).
  Future<void> _replaceProtocolTargetOutcomes(
    String protocolId,
    List<ProtocolTargetOutcomeDraft> outcomes,
    _WriteContext context,
  ) async {
    final activeRows = await _activeProtocolTargetOutcomeQuery(
      protocolId: protocolId,
    ).get();
    final activeByKey = <String, ProtocolTargetOutcomeRow>{
      for (final row in activeRows)
        _protocolTargetOutcomeKey(row.kind, row.metricId): row,
    };
    final desiredKeys = <String>{
      for (final outcome in outcomes)
        _protocolTargetOutcomeKey(outcome.kind.name, outcome.metricId),
    };

    for (final row in activeRows) {
      final key = _protocolTargetOutcomeKey(row.kind, row.metricId);
      if (!desiredKeys.contains(key)) {
        await (_database.update(_database.protocolTargetOutcomes)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ProtocolTargetOutcomesCompanion(
            updatedAt: Value<DateTime>(context.timestamp),
            deletedAt: Value<DateTime?>(context.timestamp),
          ),
        );
        final after = await _requireProtocolTargetOutcomeRow(row.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.protocolTargetOutcomesTable,
          entityId: row.id,
          beforeImage: _protocolTargetOutcomeImage(row),
          afterImage: _protocolTargetOutcomeImage(after),
        );
      }
    }

    for (var index = 0; index < outcomes.length; index += 1) {
      final outcome = outcomes[index];
      final key =
          _protocolTargetOutcomeKey(outcome.kind.name, outcome.metricId);
      final existing = activeByKey[key];
      if (existing == null) {
        final outcomeId = _repositories.createId(context.timestamp);
        await _database.into(_database.protocolTargetOutcomes).insert(
              ProtocolTargetOutcomesCompanion.insert(
                id: outcomeId,
                protocolId: protocolId,
                kind: outcome.kind.name,
                metricId: Value<String?>(outcome.metricId),
                position: index,
                updatedAt: context.timestamp,
              ),
            );
        final after = await _requireProtocolTargetOutcomeRow(outcomeId);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.protocolTargetOutcomesTable,
          entityId: outcomeId,
          beforeImage: null,
          afterImage: _protocolTargetOutcomeImage(after),
        );
        continue;
      }

      if (existing.position != index) {
        await (_database.update(_database.protocolTargetOutcomes)
              ..where((table) => table.id.equals(existing.id)))
            .write(
          ProtocolTargetOutcomesCompanion(
            position: Value<int>(index),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        final after = await _requireProtocolTargetOutcomeRow(existing.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.protocolTargetOutcomesTable,
          entityId: existing.id,
          beforeImage: _protocolTargetOutcomeImage(existing),
          afterImage: _protocolTargetOutcomeImage(after),
        );
      }
    }
  }

  /// Hard-rejects an empty/blank name (structural validation — not the shared
  /// Dose two-tier validator, which guards logging amounts, PROTOCOLS.md §6).
  String _validateProtocolName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Protocol name is empty.');
    }
    return trimmed;
  }

  /// Hard-rejects an end date before the start date. A null [endDate] means
  /// an open-ended (ongoing) course — always valid.
  void _validateProtocolWindow(DateTime startDate, DateTime? endDate) {
    if (endDate != null && endDate.isBefore(startDate)) {
      throw ArgumentError.value(
        endDate,
        'endDate',
        'Protocol end date must not be before its start date.',
      );
    }
  }

  /// Hard-rejects an empty or duplicated membership list. A Protocol
  /// associates ONE OR MORE Compounds (PROTOCOLS.md §1.4); a repeated
  /// Compound id is never a meaningful stack member.
  List<String> _validateProtocolMembership(List<String> compoundIds) {
    if (compoundIds.isEmpty) {
      throw ArgumentError.value(
        compoundIds,
        'compoundIds',
        'A Protocol requires at least one Compound.',
      );
    }
    final uniqueIds = compoundIds.toSet();
    if (uniqueIds.length != compoundIds.length) {
      throw ArgumentError.value(
        compoundIds,
        'compoundIds',
        'A Protocol cannot list the same Compound twice.',
      );
    }
    return compoundIds;
  }

  /// Resolves + hard-rejects any [compoundIds] that doesn't reference an
  /// active (non-archived) catalogue `Compound`, in the given order.
  Future<List<CompoundRow>> _requireActiveCompoundRows(
    List<String> compoundIds,
  ) async {
    final rows = await (_database.select(_database.compounds)
          ..where(
            (row) => row.deletedAt.isNull() & row.id.isIn(compoundIds),
          ))
        .get();
    final rowsById = <String, CompoundRow>{
      for (final row in rows) row.id: row,
    };
    if (!compoundIds.every(rowsById.containsKey)) {
      throw ArgumentError.value(
        compoundIds,
        'compoundIds',
        'A Protocol must reference active catalogue Compounds.',
      );
    }
    return <CompoundRow>[for (final id in compoundIds) rowsById[id]!];
  }

  /// Hard-rejects a malformed or duplicated target-outcome list: a
  /// `metric` outcome requires a non-blank [ProtocolTargetOutcomeDraft.metricId],
  /// and no two outcomes may declare the SAME thing twice (the same Metric
  /// twice, or `performance` twice). An EMPTY list is always valid — a
  /// Protocol MAY declare target outcomes, never must (PROTOCOLS.md §1.4).
  List<ProtocolTargetOutcomeDraft> _validateProtocolTargetOutcomes(
    List<ProtocolTargetOutcomeDraft> outcomes,
  ) {
    final seenKeys = <String>{};
    for (final outcome in outcomes) {
      if (outcome.kind == ProtocolOutcomeKind.metric) {
        final metricId = outcome.metricId?.trim() ?? '';
        if (metricId.isEmpty) {
          throw ArgumentError.value(
            outcome.metricId,
            'metricId',
            'A metric target outcome requires a Metric id.',
          );
        }
      }
      final key =
          _protocolTargetOutcomeKey(outcome.kind.name, outcome.metricId);
      if (!seenKeys.add(key)) {
        throw ArgumentError.value(
          outcomes,
          'targetOutcomes',
          'A Protocol cannot declare the same target outcome twice.',
        );
      }
    }
    return outcomes;
  }

  /// The distinct [ProtocolOutcomeKind.metric] ids declared across [outcomes],
  /// in encounter order — the set [_requireActiveMetricRows] validates.
  List<String> _metricIdsOf(List<ProtocolTargetOutcomeDraft> outcomes) {
    return <String>[
      for (final outcome in outcomes)
        if (outcome.kind == ProtocolOutcomeKind.metric) outcome.metricId!,
    ];
  }

  /// Hard-rejects any [metricIds] that doesn't reference an active
  /// (non-archived) catalogue `Metric` — mirrors [_requireActiveCompoundRows].
  /// An empty list is a no-op (a Protocol with no `metric` outcomes never
  /// queries `Metrics` at all).
  Future<void> _requireActiveMetricRows(List<String> metricIds) async {
    if (metricIds.isEmpty) {
      return;
    }
    final rows = await (_database.select(_database.metrics)
          ..where((row) => row.deletedAt.isNull() & row.id.isIn(metricIds)))
        .get();
    final activeIds = rows.map((row) => row.id).toSet();
    if (!metricIds.every(activeIds.contains)) {
      throw ArgumentError.value(
        metricIds,
        'metricIds',
        'A Protocol target outcome must reference an active Metric.',
      );
    }
  }

  SimpleSelectStatement<$ProtocolsTable, ProtocolRow> _activeProtocolQuery({
    String? id,
  }) {
    final query = _database.select(_database.protocols)
      ..where((row) => row.deletedAt.isNull());
    if (id != null) {
      query.where((row) => row.id.equals(id));
    }
    query.orderBy([
      (row) => OrderingTerm.asc(row.name),
      (row) => OrderingTerm.asc(row.id),
    ]);
    return query;
  }

  SimpleSelectStatement<$ProtocolCompoundsTable, ProtocolCompoundRow>
      _activeProtocolCompoundQuery({String? protocolId}) {
    return _database.select(_database.protocolCompounds)
      ..where((row) {
        var predicate = row.deletedAt.isNull();
        if (protocolId != null) {
          predicate = predicate & row.protocolId.equals(protocolId);
        }
        return predicate;
      })
      ..orderBy([(row) => OrderingTerm.asc(row.position)]);
  }

  /// Active (non-archived) `Schedule` rows, optionally scoped to one member
  /// (`ProtocolCompound`) row.
  SimpleSelectStatement<$SchedulesTable, ScheduleRow> _activeScheduleQuery({
    String? protocolCompoundId,
    Set<String>? protocolCompoundIds,
  }) {
    final query = _database.select(_database.schedules)
      ..where((row) => row.deletedAt.isNull());
    if (protocolCompoundId != null) {
      query.where((row) => row.protocolCompoundId.equals(protocolCompoundId));
    } else if (protocolCompoundIds != null) {
      query.where((row) => row.protocolCompoundId.isIn(protocolCompoundIds));
    }
    query.orderBy([
      (row) => OrderingTerm.asc(row.protocolCompoundId),
      (row) => OrderingTerm.asc(row.id),
    ]);
    return query;
  }

  /// Active (non-archived) target-outcome rows, optionally scoped to one
  /// Protocol.
  SimpleSelectStatement<$ProtocolTargetOutcomesTable, ProtocolTargetOutcomeRow>
      _activeProtocolTargetOutcomeQuery({String? protocolId}) {
    return _database.select(_database.protocolTargetOutcomes)
      ..where((row) {
        var predicate = row.deletedAt.isNull();
        if (protocolId != null) {
          predicate = predicate & row.protocolId.equals(protocolId);
        }
        return predicate;
      })
      ..orderBy([(row) => OrderingTerm.asc(row.position)]);
  }

  List<ProtocolOptionRecord> _protocolOptionsFromRows(
    List<ProtocolRow> protocolRows,
  ) {
    return protocolRows.map(_protocolOptionFromRow).toList(growable: false);
  }

  ProtocolOptionRecord _protocolOptionFromRow(ProtocolRow row) {
    return ProtocolOptionRecord(
      id: row.id,
      name: row.name,
    );
  }

  List<ProtocolSummaryRecord> _protocolSummariesFromRows(
    List<ProtocolRow> protocolRows,
    List<ProtocolCompoundRow> memberRows,
  ) {
    final membersByProtocolId = <String, List<ProtocolCompoundRow>>{};
    for (final member in memberRows) {
      membersByProtocolId.putIfAbsent(member.protocolId, () => []).add(member);
    }

    return protocolRows.map((row) {
      final members = List<ProtocolCompoundRow>.of(
        membersByProtocolId[row.id] ?? const <ProtocolCompoundRow>[],
      )..sort((a, b) => a.position.compareTo(b.position));
      return ProtocolSummaryRecord(
        id: row.id,
        name: row.name,
        startDate: row.startDate,
        endDate: row.endDate,
        compoundIds: members.map((member) => member.compoundId).toList(
              growable: false,
            ),
      );
    }).toList(growable: false);
  }

  List<ProtocolEffectOptionRecord> _protocolEffectOptionsFromRows(
    List<ProtocolRow> protocolRows,
    List<ProtocolTargetOutcomeRow> targetOutcomeRows,
  ) {
    final targetOutcomesByProtocolId =
        <String, List<ProtocolTargetOutcomeRow>>{};
    for (final outcome in targetOutcomeRows) {
      targetOutcomesByProtocolId
          .putIfAbsent(outcome.protocolId, () => [])
          .add(outcome);
    }

    return protocolRows.map((row) {
      final targetOutcomes = List<ProtocolTargetOutcomeRow>.of(
        targetOutcomesByProtocolId[row.id] ??
            const <ProtocolTargetOutcomeRow>[],
      )..sort((a, b) => a.position.compareTo(b.position));
      return ProtocolEffectOptionRecord(
        id: row.id,
        name: row.name,
        targetOutcomes: targetOutcomes
            .map(_protocolTargetOutcomeRecordFromRow)
            .toList(growable: false),
      );
    }).toList(growable: false);
  }

  List<ProtocolRecord> _protocolsFromRows(
    List<ProtocolRow> protocolRows,
    List<ProtocolCompoundRow> memberRows,
    List<ScheduleRow> scheduleRows,
    List<ProtocolTargetOutcomeRow> targetOutcomeRows,
  ) {
    final membersByProtocolId = <String, List<ProtocolCompoundRow>>{};
    for (final member in memberRows) {
      membersByProtocolId.putIfAbsent(member.protocolId, () => []).add(member);
    }
    final scheduleByProtocolCompoundId = <String, ScheduleRow>{
      for (final schedule in scheduleRows)
        schedule.protocolCompoundId: schedule,
    };
    final targetOutcomesByProtocolId =
        <String, List<ProtocolTargetOutcomeRow>>{};
    for (final outcome in targetOutcomeRows) {
      targetOutcomesByProtocolId
          .putIfAbsent(outcome.protocolId, () => [])
          .add(outcome);
    }

    return protocolRows.map((row) {
      final members = List<ProtocolCompoundRow>.of(
        membersByProtocolId[row.id] ?? const <ProtocolCompoundRow>[],
      )..sort((a, b) => a.position.compareTo(b.position));
      final targetOutcomes = List<ProtocolTargetOutcomeRow>.of(
        targetOutcomesByProtocolId[row.id] ??
            const <ProtocolTargetOutcomeRow>[],
      )..sort((a, b) => a.position.compareTo(b.position));
      return ProtocolRecord(
        id: row.id,
        name: row.name,
        startDate: row.startDate,
        endDate: row.endDate,
        members: members.map(
          (member) {
            final scheduleRow = scheduleByProtocolCompoundId[member.id];
            return ProtocolMemberRecord(
              id: member.id,
              compoundId: member.compoundId,
              position: member.position,
              schedule: scheduleRow == null
                  ? null
                  : _scheduleRecordFromRow(scheduleRow),
            );
          },
        ).toList(growable: false),
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
        targetOutcomes: targetOutcomes
            .map(_protocolTargetOutcomeRecordFromRow)
            .toList(growable: false),
      );
    }).toList(growable: false);
  }

  /// Maps a persisted target-outcome row to its read model, REJECTING a kind
  /// stored outside the curated registry (same discipline as
  /// [_scheduleRecordFromRow]).
  ProtocolTargetOutcomeRecord _protocolTargetOutcomeRecordFromRow(
    ProtocolTargetOutcomeRow row,
  ) {
    return ProtocolTargetOutcomeRecord(
      id: row.id,
      kind: protocolOutcomeKindFromName(row.kind),
      metricId: row.metricId,
      position: row.position,
    );
  }

  /// Maps a persisted `Schedule` row to its read model, REJECTING a unit,
  /// route, or frequency stored outside the curated registries (
  /// the same registry chokepoint discipline as `DoseRecord`).
  ScheduleRecord _scheduleRecordFromRow(ScheduleRow row) {
    return ScheduleRecord(
      id: row.id,
      protocolCompoundId: row.protocolCompoundId,
      doseAmountValue: row.doseAmountValue,
      doseAmountEntered: row.doseAmountEntered,
      doseUnit: doseUnitFromName(row.doseUnit),
      frequency: scheduleFrequencyFromName(row.frequency),
      route: doseRouteFromName(row.route),
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }

  bool _sameStringSet(Set<String> left, Set<String> right) {
    return left.length == right.length && left.containsAll(right);
  }

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  bool _sameCompoundOptionRecords(
    List<CompoundOptionRecord> left,
    List<CompoundOptionRecord> right,
  ) {
    return _sameProtocolList(left, right, _sameCompoundOptionRecord);
  }

  bool _sameCompoundOptionRecord(
    CompoundOptionRecord left,
    CompoundOptionRecord right,
  ) {
    return left.id == right.id && left.name == right.name;
  }

  bool _sameCompoundScheduleOptionRecords(
    List<CompoundScheduleOptionRecord> left,
    List<CompoundScheduleOptionRecord> right,
  ) {
    return _sameProtocolList(left, right, _sameCompoundScheduleOptionRecord);
  }

  bool _sameCompoundScheduleOptionRecord(
    CompoundScheduleOptionRecord left,
    CompoundScheduleOptionRecord right,
  ) {
    return left.id == right.id &&
        left.name == right.name &&
        left.defaultUnit == right.defaultUnit &&
        left.defaultRoute == right.defaultRoute;
  }

  bool _sameProtocolOptionRecords(
    List<ProtocolOptionRecord> left,
    List<ProtocolOptionRecord> right,
  ) {
    return _sameProtocolList(left, right, _sameProtocolOptionRecord);
  }

  bool _sameProtocolOptionRecord(
    ProtocolOptionRecord left,
    ProtocolOptionRecord right,
  ) {
    return left.id == right.id && left.name == right.name;
  }

  bool _sameProtocolSummaryRecords(
    List<ProtocolSummaryRecord> left,
    List<ProtocolSummaryRecord> right,
  ) {
    return _sameProtocolList(left, right, _sameProtocolSummaryRecord);
  }

  bool _sameProtocolSummaryRecord(
    ProtocolSummaryRecord left,
    ProtocolSummaryRecord right,
  ) {
    return left.id == right.id &&
        left.name == right.name &&
        left.startDate == right.startDate &&
        left.endDate == right.endDate &&
        _sameStringList(left.compoundIds, right.compoundIds);
  }

  bool _sameProtocolEffectOptionRecords(
    List<ProtocolEffectOptionRecord> left,
    List<ProtocolEffectOptionRecord> right,
  ) {
    return _sameProtocolList(left, right, _sameProtocolEffectOptionRecord);
  }

  bool _sameProtocolEffectOptionRecord(
    ProtocolEffectOptionRecord left,
    ProtocolEffectOptionRecord right,
  ) {
    return left.id == right.id &&
        left.name == right.name &&
        _sameProtocolTargetOutcomeRecords(
          left.targetOutcomes,
          right.targetOutcomes,
        );
  }

  bool _sameProtocolRecord(ProtocolRecord? left, ProtocolRecord? right) {
    if (identical(left, right)) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    return left.id == right.id &&
        left.name == right.name &&
        left.startDate == right.startDate &&
        left.endDate == right.endDate &&
        left.updatedAt == right.updatedAt &&
        left.deletedAt == right.deletedAt &&
        _sameProtocolMemberRecords(left.members, right.members) &&
        _sameProtocolTargetOutcomeRecords(
          left.targetOutcomes,
          right.targetOutcomes,
        );
  }

  bool _sameProtocolMemberRecords(
    List<ProtocolMemberRecord> left,
    List<ProtocolMemberRecord> right,
  ) {
    return _sameProtocolList(left, right, _sameProtocolMemberRecord);
  }

  bool _sameProtocolMemberRecord(
    ProtocolMemberRecord left,
    ProtocolMemberRecord right,
  ) {
    return left.id == right.id &&
        left.compoundId == right.compoundId &&
        left.position == right.position &&
        _sameScheduleRecord(left.schedule, right.schedule);
  }

  bool _sameScheduleRecord(ScheduleRecord? left, ScheduleRecord? right) {
    if (identical(left, right)) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    return left.id == right.id &&
        left.protocolCompoundId == right.protocolCompoundId &&
        left.doseAmountValue == right.doseAmountValue &&
        left.doseAmountEntered == right.doseAmountEntered &&
        left.doseUnit == right.doseUnit &&
        left.frequency == right.frequency &&
        left.route == right.route &&
        left.updatedAt == right.updatedAt &&
        left.deletedAt == right.deletedAt;
  }

  bool _sameProtocolTargetOutcomeRecords(
    List<ProtocolTargetOutcomeRecord> left,
    List<ProtocolTargetOutcomeRecord> right,
  ) {
    return _sameProtocolList(left, right, _sameProtocolTargetOutcomeRecord);
  }

  bool _sameProtocolTargetOutcomeRecord(
    ProtocolTargetOutcomeRecord left,
    ProtocolTargetOutcomeRecord right,
  ) {
    return left.id == right.id &&
        left.kind == right.kind &&
        left.metricId == right.metricId &&
        left.position == right.position;
  }

  bool _sameProtocolList<T>(
    List<T> left,
    List<T> right,
    bool Function(T left, T right) equals,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!equals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  Future<ProtocolRow> _requireProtocolRow(String id) async {
    final row = await (_database.select(_database.protocols)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Protocol not found: $id.');
    }
    return row;
  }

  Future<ProtocolCompoundRow> _requireProtocolCompoundRow(String id) async {
    final row = await (_database.select(_database.protocolCompounds)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Protocol member not found: $id.');
    }
    return row;
  }

  Future<ScheduleRow> _requireScheduleRow(String id) async {
    final row = await (_database.select(_database.schedules)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Schedule not found: $id.');
    }
    return row;
  }

  Future<ProtocolTargetOutcomeRow> _requireProtocolTargetOutcomeRow(
    String id,
  ) async {
    final row = await (_database.select(_database.protocolTargetOutcomes)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Protocol target outcome not found: $id.');
    }
    return row;
  }
}

/// Which entity an `Effect` window is anchored to (PROTOCOLS.md §1.4, §4,
///): a `Protocol` course, or a single `Compound`'s own logged Dose
/// timeline (ad hoc — no Protocol required). Exactly one of
/// [protocolId]/[compoundId] is set.
class EffectWindowSource {
  const EffectWindowSource.protocol(this.protocolId) : compoundId = null;

  const EffectWindowSource.compound(this.compoundId) : protocolId = null;

  final String? protocolId;
  final String? compoundId;

  bool get isProtocol => protocolId != null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is EffectWindowSource &&
            runtimeType == other.runtimeType &&
            protocolId == other.protocolId &&
            compoundId == other.compoundId;
  }

  @override
  int get hashCode => Object.hash(protocolId, compoundId);
}

/// Assembles the `Effect` view's window + outcome deltas (PROTOCOLS.md §4,
///) — the foundation of the Protocols payoff screen. Every read here
/// is a fresh computation off the existing stores: it never writes anything,
/// and the delta computation itself (`computeOutcomeEffect`) is a pure
/// function it merely feeds ("join, never merge", §2). No new table, no new
/// sync entity — this composes [ProtocolsRepository] (the actual logged Dose
/// timeline) and [MetricRepository] (outcome Readings) plus a direct,
/// read-only Workout volume query for the `performance` outcome kind.
class EffectRepository {
  const EffectRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  /// The `Effect` window for a `Protocol` (PROTOCOLS.md §1.4, §4): DURING is
  /// the Protocol's own declared start/end — never the Schedule/plan, but a
  /// Protocol's start/end ARE plan dates by definition (§1.4), which is why a
  /// Compound-only window ([windowForCompound]) instead derives DURING from
  /// the actual logged Doses.
  EffectWindow windowForProtocol(ProtocolRecord protocol, {DateTime? now}) {
    return EffectWindow(
      duringStart: protocol.startDate,
      duringEnd: protocol.endDate,
      now: now ?? DateTime.now(),
    );
  }

  /// The `Effect` window for a single `Compound`, ad hoc (no `Protocol`
  /// required, PROTOCOLS.md §1.4): DURING is derived from the bounds of the
  /// Compound's ACTUAL logged `Dose`s (earliest to latest), never a plan —
  /// there is no Schedule to fall back to at this level anyway. Returns
  /// `null` when the Compound has no logged Dose (no window can be derived).
  Future<EffectWindow?> windowForCompound(
    String compoundId, {
    DateTime? now,
  }) async {
    final doses = await _repositories.protocols.dosesForCompound(compoundId);
    if (doses.isEmpty) {
      return null;
    }
    final tookAtTimes = doses.map((dose) => dose.tookAt).toList()..sort();
    return EffectWindow(
      duringStart: tookAtTimes.first,
      duringEnd: tookAtTimes.length == 1 ? null : tookAtTimes.last,
      now: now ?? DateTime.now(),
    );
  }

  /// The outcome samples for [outcome] over [window]'s full before-through-
  /// after span — the raw input to `computeOutcomeEffect`. A `metric`
  /// outcome reads the existing `Metric` Readings; a `performance`
  /// outcome reads [performanceVolumeSamples]. Never fabricates a sample: a
  /// Reading missing a scalar value/instant is simply excluded, not zeroed.
  Future<List<EffectSample>> samplesFor(
    EffectOutcomeSelection outcome,
    EffectWindow window,
  ) async {
    switch (outcome.kind) {
      case ProtocolOutcomeKind.metric:
        final metricId = outcome.metricId;
        if (metricId == null) {
          return const <EffectSample>[];
        }
        final series = await _repositories.metrics.metricSeries(
          metricId,
          from: window.beforeStart,
          to: window.afterEnd,
        );
        if (series == null) {
          return const <EffectSample>[];
        }
        return series.readings
            .where(
              (reading) =>
                  reading.atTime != null && reading.scalarValue != null,
            )
            .map(
              (reading) => EffectSample(
                at: reading.atTime!,
                value: reading.scalarValue!,
              ),
            )
            .toList(growable: false);
      case ProtocolOutcomeKind.performance:
        return performanceVolumeSamples(
          from: window.beforeStart,
          to: window.afterEnd,
        );
    }
  }

  /// The ACTUAL logged `Dose` markers for the `Effect` view's dose-overlay
  /// timeline (PROTOCOLS.md §4): the real (tz-frozen) `Dose.tookAt`
  /// times for [source], scoped to [window]'s full before-through-after span
  /// — the same span [samplesFor] reads outcomes over, so the outcome series
  /// and the dose markers always share one time axis. Oldest first. NEVER
  /// reads the Schedule/plan (§1.4): a Protocol source reads Doses TAGGED to
  /// it, and a Compound source reads its own logged Dose timeline
  /// ([dosesForCompound]) — either way, this is a pure read that stores
  /// nothing.
  Future<List<DoseRecord>> doseMarkersFor(
    EffectWindowSource source,
    EffectWindow window,
  ) async {
    final doses = source.isProtocol
        ? await _repositories.protocols.dosesForProtocol(source.protocolId!)
        : await _repositories.protocols.dosesForCompound(source.compoundId!);
    return doses
        .where(
          (dose) =>
              !dose.tookAt.isBefore(window.beforeStart) &&
              dose.tookAt.isBefore(window.afterEnd),
        )
        .toList(growable: false);
  }

  /// The before/during/after delta for ONE outcome over [window] — the
  /// composed read + the pure `computeOutcomeEffect` in one call.
  Future<OutcomeEffectResult> computeOutcome({
    required EffectWindow window,
    required EffectOutcomeSelection outcome,
  }) async {
    final samples = await samplesFor(outcome, window);
    return computeOutcomeEffect(window: window, samples: samples);
  }

  /// The dose-response table for ONE outcome over [window] (PROTOCOLS.md
  /// §4): the composed read (the ACTUAL logged `Dose` markers via
  /// [doseMarkersFor] — NEVER the Schedule/plan — plus the outcome's
  /// samples via [samplesFor]) + the pure `computeDoseResponseTable` in one
  /// call. Mirrors [computeOutcome]'s shape; a read-only composition that
  /// stores nothing.
  Future<List<DoseResponseRow>> doseResponseFor({
    required EffectWindowSource source,
    required EffectWindow window,
    required EffectOutcomeSelection outcome,
  }) async {
    final doses = await doseMarkersFor(source, window);
    final samples = await samplesFor(outcome, window);
    return computeDoseResponseTable(doses: doses, samples: samples);
  }

  /// A read-only performance proxy (PROTOCOLS.md §4: "performance comes from
  /// Workout analytics") for the `Effect` view: one [EffectSample] per
  /// Workout session in `[from, to)` whose `at` is the session's start and
  /// whose value is the session's total logged volume (Σ load × reps over
  /// its completed, load-and-reps-bearing `LoggedSet`s). A session with no
  /// such set is EXCLUDED (not fabricated as a zero) — e.g. an
  /// endurance/duration-only session contributes no volume sample.
  Future<List<EffectSample>> performanceVolumeSamples({
    required DateTime from,
    required DateTime to,
  }) async {
    final sessionRows = await (_database.select(_database.workoutSessions)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.startedAt.isBiggerOrEqualValue(from) &
                row.startedAt.isSmallerThanValue(to),
          ))
        .get();
    if (sessionRows.isEmpty) {
      return const <EffectSample>[];
    }

    final sessionIds = sessionRows.map((row) => row.id).toList();
    final setRows = await (_database.select(_database.loggedSets)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.isCompleted.equals(true) &
                row.workoutId.isIn(sessionIds) &
                row.loadValue.isNotNull() &
                row.repsValue.isNotNull(),
          ))
        .get();

    final volumeBySessionId = <String, double>{};
    for (final row in setRows) {
      final volume = row.loadValue! * row.repsValue!;
      volumeBySessionId.update(
        row.workoutId,
        (existing) => existing + volume,
        ifAbsent: () => volume,
      );
    }

    final samples = <EffectSample>[];
    for (final session in sessionRows) {
      final volume = volumeBySessionId[session.id];
      if (volume == null) {
        continue;
      }
      samples.add(EffectSample(at: session.startedAt, value: volume));
    }
    return samples;
  }
}

/// A chosen outcome to correlate in the `Effect` view (PROTOCOLS.md §1.4, §4,
///): either one specific catalogue `Metric`, or `performance`
/// (Workout analytics broadly — no `Metric` row backs it). Mirrors
/// [ProtocolTargetOutcomeDraft]/[ProtocolTargetOutcomeRecord]'s shape so a
/// Protocol's declared target outcomes seed this 1:1, but a value here is
/// never persisted — the `Effect` view's outcome selection is always ad hoc
/// and in-memory (PROTOCOLS.md §4: "can be adjusted ad hoc").
class EffectOutcomeSelection {
  const EffectOutcomeSelection.metric(this.metricId)
      : kind = ProtocolOutcomeKind.metric;

  const EffectOutcomeSelection.performance()
      : kind = ProtocolOutcomeKind.performance,
        metricId = null;

  /// Seeds one selection from a Protocol's declared target outcome
  /// — the same kind/metricId, just detached from the Protocol so
  /// it can be adjusted ad hoc without touching the plan.
  factory EffectOutcomeSelection.fromTargetOutcome(
    ProtocolTargetOutcomeRecord outcome,
  ) {
    return outcome.kind == ProtocolOutcomeKind.metric
        ? EffectOutcomeSelection.metric(outcome.metricId!)
        : const EffectOutcomeSelection.performance();
  }

  final ProtocolOutcomeKind kind;
  final String? metricId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is EffectOutcomeSelection &&
            runtimeType == other.runtimeType &&
            kind == other.kind &&
            metricId == other.metricId;
  }

  @override
  int get hashCode => Object.hash(kind, metricId);
}

class WorkoutExerciseRepository {
  const WorkoutExerciseRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<String> create(
    WorkoutExerciseDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() => _create(draft, context));
  }

  Future<WorkoutExerciseRecord?> getById(String id) async {
    final row = await (_database.select(_database.workoutExercises)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _workoutExerciseFromRow(row);
  }

  Future<List<WorkoutExerciseRecord>> listActiveForWorkout(
    String workoutId,
  ) async {
    final rows = await _activeWorkoutExerciseQuery(workoutId: workoutId).get();
    return rows.map(_workoutExerciseFromRow).toList(growable: false);
  }

  Future<List<WorkoutExerciseRecord>> listActiveForWorkoutIds(
    Set<String> workoutIds,
  ) async {
    if (workoutIds.isEmpty) {
      return const <WorkoutExerciseRecord>[];
    }

    final rows =
        await _activeWorkoutExerciseQuery(workoutIds: workoutIds).get();
    return rows.map(_workoutExerciseFromRow).toList(growable: false);
  }

  Future<List<WorkoutExerciseRecord>> listAllActive() async {
    final rows = await _activeWorkoutExerciseQuery().get();
    return rows.map(_workoutExerciseFromRow).toList(growable: false);
  }

  Future<void> softDelete(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      if (before.deletedAt != null) {
        return;
      }

      await _softDeleteAffectedExerciseGroupMemberships(before, context);
      await _repositories.workoutSessions._softDeleteWorkoutExercise(
        before,
        context,
      );

      final sets = await _repositories.sets
          ._activeLoggedSetQuery(workoutId: before.workoutId)
          .get();
      for (final set
          in sets.where((row) => row.exerciseId == before.exerciseId)) {
        await _repositories.workoutSessions._softDeleteLoggedSet(set, context);
      }
    });
  }

  Future<void> reorderForWorkout({
    required String workoutId,
    required List<String> orderedIds,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final activeRows =
          await _activeWorkoutExerciseQuery(workoutId: workoutId).get();
      final rowById = <String, WorkoutExerciseRow>{
        for (final row in activeRows) row.id: row,
      };
      final uniqueOrderedIds = orderedIds.toSet();
      if (uniqueOrderedIds.length != orderedIds.length ||
          uniqueOrderedIds.length != rowById.length ||
          !rowById.keys.toSet().containsAll(orderedIds)) {
        throw ArgumentError.value(
          orderedIds,
          'orderedIds',
          'Reorder ids must include each active workout exercise exactly once.',
        );
      }

      for (var index = 0; index < orderedIds.length; index += 1) {
        final row = rowById[orderedIds[index]]!;
        if (row.position == index) {
          continue;
        }

        await (_database.update(_database.workoutExercises)
              ..where((table) => table.id.equals(row.id)))
            .write(
          WorkoutExercisesCompanion(
            position: Value<int>(index),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        final after = await _requireRow(row.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.workoutExercisesTable,
          entityId: row.id,
          beforeImage: _workoutExerciseImage(row),
          afterImage: _workoutExerciseImage(after),
        );
      }

      await _repositories.exerciseGroups._reconcileAfterWorkoutExerciseReorder(
        workoutId: workoutId,
        orderedWorkoutExerciseIds: orderedIds,
        context: context,
      );
    });
  }

  Stream<List<WorkoutExerciseRecord>> watchAllActive() {
    return _activeWorkoutExerciseQuery().watch().map(
          (rows) => rows.map(_workoutExerciseFromRow).toList(growable: false),
        );
  }

  Stream<List<WorkoutExerciseRecord>> watchActiveForWorkout(String workoutId) {
    return _activeWorkoutExerciseQuery(workoutId: workoutId).watch().map(
          (rows) => rows.map(_workoutExerciseFromRow).toList(growable: false),
        );
  }

  Stream<List<WorkoutExerciseRecord>> watchActiveForWorkoutIds(
    Set<String> workoutIds,
  ) {
    if (workoutIds.isEmpty) {
      return Stream<List<WorkoutExerciseRecord>>.value(
        const <WorkoutExerciseRecord>[],
      );
    }

    return _activeWorkoutExerciseQuery(workoutIds: workoutIds).watch().map(
          (rows) => rows.map(_workoutExerciseFromRow).toList(growable: false),
        );
  }

  SimpleSelectStatement<$WorkoutExercisesTable, WorkoutExerciseRow>
      _activeWorkoutExerciseQuery({
    String? workoutId,
    Set<String>? workoutIds,
  }) {
    final query = _database.select(_database.workoutExercises)
      ..where((row) => row.deletedAt.isNull());
    if (workoutId != null) {
      query.where((row) => row.workoutId.equals(workoutId));
    } else if (workoutIds != null) {
      query.where((row) => row.workoutId.isIn(workoutIds));
    }
    query.orderBy([
      (row) => OrderingTerm.asc(row.workoutId),
      (row) => OrderingTerm.asc(row.position),
    ]);
    return query;
  }

  Future<String> _create(
    WorkoutExerciseDraft draft,
    _WriteContext context,
  ) async {
    final existing = await (_database.select(_database.workoutExercises)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.workoutId.equals(draft.workoutId) &
                row.exerciseId.equals(draft.exerciseId),
          )
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) {
      return existing.id;
    }

    final activeRows =
        await _activeWorkoutExerciseQuery(workoutId: draft.workoutId).get();
    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.workoutExercises).insert(
          WorkoutExercisesCompanion.insert(
            id: id,
            workoutId: draft.workoutId,
            exerciseId: draft.exerciseId,
            position: _nextWorkoutExercisePosition(activeRows),
            updatedAt: context.timestamp,
          ),
        );

    final after = await _requireRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.workoutExercisesTable,
      entityId: id,
      beforeImage: null,
      afterImage: _workoutExerciseImage(after),
    );

    return id;
  }

  Future<void> _softDeleteAffectedExerciseGroupMemberships(
    WorkoutExerciseRow workoutExercise,
    _WriteContext context,
  ) async {
    final memberships = await (_database.select(_database.exerciseGroupMembers)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.workoutExerciseId.equals(workoutExercise.id),
          ))
        .get();
    if (memberships.isEmpty) {
      return;
    }

    for (final membership in memberships) {
      final group = await (_database.select(_database.exerciseGroups)
            ..where(
              (row) =>
                  row.id.equals(membership.groupId) &
                  row.deletedAt.isNull() &
                  row.workoutId.equals(workoutExercise.workoutId),
            ))
          .getSingleOrNull();
      if (group == null) {
        continue;
      }

      final activeMembers = await _repositories.exerciseGroups
          ._activeExerciseGroupMemberQuery(groupId: group.id)
          .get();
      final remainingMembers = activeMembers
          .where((row) => row.workoutExerciseId != workoutExercise.id)
          .toList(growable: false);

      await _repositories.workoutSessions._softDeleteExerciseGroupMember(
        membership,
        context,
      );
      if (remainingMembers.length < 2) {
        for (final member in remainingMembers) {
          await _repositories.workoutSessions._softDeleteExerciseGroupMember(
            member,
            context,
          );
        }
        await _repositories.workoutSessions._softDeleteExerciseGroup(
          group,
          context,
        );
      } else {
        await _writeExerciseGroupMemberPositions(remainingMembers, context);
      }
    }
  }

  Future<void> _writeExerciseGroupMemberPositions(
    List<ExerciseGroupMemberRow> members,
    _WriteContext context,
  ) async {
    for (var index = 0; index < members.length; index += 1) {
      final member = members[index];
      if (member.position == index) {
        continue;
      }

      await (_database.update(_database.exerciseGroupMembers)
            ..where((row) => row.id.equals(member.id)))
          .write(
        ExerciseGroupMembersCompanion(
          position: Value<int>(index),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after =
          await _repositories.exerciseGroups._requireMemberRow(member.id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exerciseGroupMembersTable,
        entityId: member.id,
        beforeImage: _exerciseGroupMemberImage(member),
        afterImage: _exerciseGroupMemberImage(after),
      );
    }
  }

  Future<WorkoutExerciseRow> _requireRow(String id) async {
    final row = await (_database.select(_database.workoutExercises)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Workout exercise not found: $id.');
    }
    return row;
  }
}

class ExerciseGroupRepository {
  const ExerciseGroupRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<String> create(
    ExerciseGroupDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() => _create(draft, context));
  }

  Future<void> update(
    String id, {
    required String name,
    required String colorHex,
    required List<String> workoutExerciseIds,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(
      () => _update(
        id,
        name: name,
        colorHex: colorHex,
        workoutExerciseIds: workoutExerciseIds,
        context: context,
      ),
    );
  }

  /// Links neighboring workout exercises into one Exercise Group.
  ///
  /// Repeated calls extend an existing group, and linking the boundary between
  /// two existing groups merges them. Members are always ordered by the
  /// Workout's exercise order so set logging advances predictably and wraps
  /// from the final member back to the first.
  Future<void> linkAdjacent({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final workoutExercises = await _requireAdjacentActiveWorkoutExercises(
        workoutId: workoutId,
        firstWorkoutExerciseId: firstWorkoutExerciseId,
        secondWorkoutExerciseId: secondWorkoutExerciseId,
      );

      final groups = await listActiveForWorkout(workoutId);
      final groupByWorkoutExerciseId = <String, ExerciseGroupRecord>{
        for (final group in groups)
          for (final memberId in group.workoutExerciseIds) memberId: group,
      };
      final firstGroup = groupByWorkoutExerciseId[firstWorkoutExerciseId];
      final secondGroup = groupByWorkoutExerciseId[secondWorkoutExerciseId];
      if (firstGroup != null && firstGroup.id == secondGroup?.id) {
        return;
      }

      final linkedIds = <String>{
        firstWorkoutExerciseId,
        secondWorkoutExerciseId,
        ...?firstGroup?.workoutExerciseIds,
        ...?secondGroup?.workoutExerciseIds,
      };
      final orderedLinkedIds = workoutExercises
          .where((exercise) => linkedIds.contains(exercise.id))
          .map((exercise) => exercise.id)
          .toList(growable: false);
      final primaryGroup = firstGroup ?? secondGroup;
      if (primaryGroup == null) {
        await _create(
          ExerciseGroupDraft(
            workoutId: workoutId,
            name: _nextGroupName(groups, baseName: 'Superset'),
            colorHex: _nextGroupColor(groups),
            workoutExerciseIds: orderedLinkedIds,
          ),
          context,
        );
        return;
      }

      final secondaryGroup = firstGroup != null && secondGroup != null
          ? (primaryGroup.id == firstGroup.id ? secondGroup : firstGroup)
          : null;
      if (secondaryGroup != null) {
        await _softDeleteGroup(secondaryGroup.id, context);
      }
      await _update(
        primaryGroup.id,
        name: primaryGroup.name,
        colorHex: primaryGroup.colorHex,
        workoutExerciseIds: orderedLinkedIds,
        context: context,
      );
    });
  }

  /// Removes the Exercise Group link between neighboring Workout exercises.
  ///
  /// Removing an outside link leaves the remaining members grouped. Removing
  /// a link from the middle of a longer circuit splits it into two groups when
  /// both sides still contain at least two exercises. A two-member group is
  /// removed entirely.
  Future<void> unlinkAdjacent({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final workoutExercises = await _requireAdjacentActiveWorkoutExercises(
        workoutId: workoutId,
        firstWorkoutExerciseId: firstWorkoutExerciseId,
        secondWorkoutExerciseId: secondWorkoutExerciseId,
      );

      final groups = await listActiveForWorkout(workoutId);
      final group = groups
          .where(
            (candidate) =>
                candidate.workoutExerciseIds.contains(firstWorkoutExerciseId) &&
                candidate.workoutExerciseIds.contains(secondWorkoutExerciseId),
          )
          .firstOrNull;
      if (group == null) {
        return;
      }

      final orderedGroupIds = workoutExercises
          .where((exercise) => group.workoutExerciseIds.contains(exercise.id))
          .map((exercise) => exercise.id)
          .toList(growable: false);
      final groupFirstIndex = orderedGroupIds.indexOf(firstWorkoutExerciseId);
      final groupSecondIndex = orderedGroupIds.indexOf(secondWorkoutExerciseId);
      if ((groupFirstIndex - groupSecondIndex).abs() != 1) {
        throw StateError(
          'Linked Workout exercises must be adjacent in their Exercise Group.',
        );
      }

      final splitIndex = groupFirstIndex < groupSecondIndex
          ? groupFirstIndex + 1
          : groupSecondIndex + 1;
      final beforeLink = orderedGroupIds.sublist(0, splitIndex);
      final afterLink = orderedGroupIds.sublist(splitIndex);
      final beforeSurvives = beforeLink.length >= 2;
      final afterSurvives = afterLink.length >= 2;

      if (!beforeSurvives && !afterSurvives) {
        await _softDeleteGroup(group.id, context);
        return;
      }

      final retainedIds = beforeSurvives ? beforeLink : afterLink;
      await _update(
        group.id,
        name: group.name,
        colorHex: group.colorHex,
        workoutExerciseIds: retainedIds,
        context: context,
      );
      if (beforeSurvives && afterSurvives) {
        await _create(
          ExerciseGroupDraft(
            workoutId: workoutId,
            name: _nextGroupName(
              groups,
              baseName: group.name,
              firstSuffix: 2,
            ),
            colorHex: _nextGroupColor(
              groups,
              excludedColorHex: group.colorHex,
            ),
            workoutExerciseIds: afterLink,
          ),
          context,
        );
      }
    });
  }

  Future<ExerciseGroupRecord?> getById(String id) async {
    final row = await (_database.select(_database.exerciseGroups)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }

    final memberRows = await _activeExerciseGroupMemberQuery(groupId: id).get();
    return _exerciseGroupFromRow(row, memberRows);
  }

  Future<List<ExerciseGroupRecord>> listActiveForWorkout(
    String workoutId,
  ) async {
    final rows = await _activeExerciseGroupQuery(workoutId: workoutId).get();
    final groupIds = rows.map((row) => row.id).toSet();
    final memberRows = groupIds.isEmpty
        ? <ExerciseGroupMemberRow>[]
        : await _activeExerciseGroupMemberQuery(groupIds: groupIds).get();
    return _exerciseGroupsFromRows(rows, memberRows);
  }

  Stream<List<ExerciseGroupRecord>> watchActiveForWorkout(String workoutId) {
    return watchActiveForWorkoutIds(<String>{workoutId});
  }

  Stream<List<ExerciseGroupRecord>> watchActiveForWorkoutIds(
    Set<String> workoutIds,
  ) {
    if (workoutIds.isEmpty) {
      return Stream<List<ExerciseGroupRecord>>.value(
        const <ExerciseGroupRecord>[],
      );
    }
    late final StreamSubscription<List<ExerciseGroupRow>> groupSubscription;
    StreamSubscription<List<ExerciseGroupMemberRow>>? memberSubscription;
    final controller = StreamController<List<ExerciseGroupRecord>>();
    List<ExerciseGroupRow>? latestGroups;
    List<ExerciseGroupMemberRow>? latestMembers;
    List<String> watchedGroupIds = const <String>[];
    List<ExerciseGroupRow>? emittedGroups;
    List<ExerciseGroupMemberRow>? emittedMembers;
    var memberSubscriptionVersion = 0;

    void emitIfReady() {
      final groups = latestGroups;
      final members = latestMembers;
      if (groups == null || members == null) {
        return;
      }
      if (_sameRowList(emittedGroups, groups) &&
          _sameRowList(emittedMembers, members)) {
        return;
      }

      emittedGroups = groups;
      emittedMembers = members;
      controller.add(_exerciseGroupsFromRows(groups, members));
    }

    void watchMembersFor(List<ExerciseGroupRow> groups) {
      final groupIds = groups.map((row) => row.id).toList(growable: false);
      if (_sameRowList(watchedGroupIds, groupIds) && latestMembers != null) {
        emitIfReady();
        return;
      }

      watchedGroupIds = groupIds;
      latestMembers = null;
      final version = ++memberSubscriptionVersion;
      memberSubscription?.cancel().ignore();
      memberSubscription = null;
      if (groupIds.isEmpty) {
        latestMembers = const <ExerciseGroupMemberRow>[];
        emitIfReady();
        return;
      }

      memberSubscription = _activeExerciseGroupMemberQuery(
        groupIds: groupIds.toSet(),
      ).watch().listen(
        (rows) {
          if (version != memberSubscriptionVersion ||
              _sameRowList(latestMembers, rows)) {
            return;
          }
          latestMembers = rows;
          emitIfReady();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (version == memberSubscriptionVersion) {
            controller.addError(error, stackTrace);
          }
        },
      );
    }

    void handleGroups(List<ExerciseGroupRow> rows) {
      if (_sameRowList(latestGroups, rows)) {
        watchMembersFor(rows);
        return;
      }
      latestGroups = rows;
      watchMembersFor(rows);
    }

    controller.onListen = () {
      groupSubscription =
          _activeExerciseGroupQuery(workoutIds: workoutIds).watch().listen(
                handleGroups,
                onError: controller.addError,
              );
    };
    controller.onCancel = () async {
      memberSubscriptionVersion++;
      await groupSubscription.cancel();
      await memberSubscription?.cancel();
    };

    return controller.stream;
  }

  Future<String?> findNextWorkoutExerciseIdAfter(
    String workoutExerciseId,
  ) async {
    final memberships = await (_database.select(_database.exerciseGroupMembers)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.workoutExerciseId.equals(workoutExerciseId),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.position)]))
        .get();

    for (final membership in memberships) {
      final group = await (_database.select(_database.exerciseGroups)
            ..where(
              (row) =>
                  row.id.equals(membership.groupId) & row.deletedAt.isNull(),
            ))
          .getSingleOrNull();
      if (group == null) {
        continue;
      }

      final members =
          await _activeExerciseGroupMemberQuery(groupId: group.id).get();
      if (members.length < 2) {
        continue;
      }

      final currentIndex = members.indexWhere(
        (member) => member.workoutExerciseId == workoutExerciseId,
      );
      if (currentIndex == -1) {
        continue;
      }

      final next = members[(currentIndex + 1) % members.length];
      final nextWorkoutExercise =
          await _repositories.workoutExercises.getById(next.workoutExerciseId);
      if (nextWorkoutExercise != null &&
          nextWorkoutExercise.deletedAt == null) {
        return nextWorkoutExercise.id;
      }
    }

    return null;
  }

  SimpleSelectStatement<$ExerciseGroupsTable, ExerciseGroupRow>
      _activeExerciseGroupQuery({
    String? workoutId,
    Set<String>? workoutIds,
  }) {
    assert(workoutId == null || workoutIds == null);
    final query = _database.select(_database.exerciseGroups)
      ..where((row) => row.deletedAt.isNull());
    if (workoutId != null) {
      query.where((row) => row.workoutId.equals(workoutId));
    } else if (workoutIds != null) {
      query.where((row) => row.workoutId.isIn(workoutIds));
    }
    query.orderBy([
      (row) => OrderingTerm.asc(row.workoutId),
      (row) => OrderingTerm.asc(row.position),
    ]);
    return query;
  }

  SimpleSelectStatement<$ExerciseGroupMembersTable, ExerciseGroupMemberRow>
      _activeExerciseGroupMemberQuery({
    String? groupId,
    Set<String>? groupIds,
  }) {
    assert(groupId == null || groupIds == null);
    final query = _database.select(_database.exerciseGroupMembers)
      ..where((row) => row.deletedAt.isNull());
    if (groupId != null) {
      query.where((row) => row.groupId.equals(groupId));
    }
    if (groupIds != null) {
      query.where((row) => row.groupId.isIn(groupIds));
    }
    query.orderBy([
      (row) => OrderingTerm.asc(row.groupId),
      (row) => OrderingTerm.asc(row.position),
    ]);
    return query;
  }

  Future<void> _update(
    String id, {
    required String name,
    required String colorHex,
    required List<String> workoutExerciseIds,
    required _WriteContext context,
  }) async {
    final before = await _requireRow(id);
    if (before.deletedAt != null) {
      throw StateError('Exercise group is deleted: $id.');
    }

    final normalizedName = _normalizeGroupNameForStorage(name);
    final normalizedColorHex = _normalizeColorHex(colorHex);
    await _requireActiveWorkoutExerciseRows(
      workoutId: before.workoutId,
      workoutExerciseIds: workoutExerciseIds,
      groupId: id,
    );

    if (before.name != normalizedName ||
        before.colorHex != normalizedColorHex) {
      await (_database.update(_database.exerciseGroups)
            ..where((row) => row.id.equals(id)))
          .write(
        ExerciseGroupsCompanion(
          name: Value<String>(normalizedName),
          colorHex: Value<String>(normalizedColorHex),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exerciseGroupsTable,
        entityId: id,
        beforeImage: _exerciseGroupImage(before),
        afterImage: _exerciseGroupImage(after),
      );
    }

    await _replaceMembers(id, workoutExerciseIds, context);
  }

  Future<List<WorkoutExerciseRecord>> _requireAdjacentActiveWorkoutExercises({
    required String workoutId,
    required String firstWorkoutExerciseId,
    required String secondWorkoutExerciseId,
  }) async {
    final workoutExercises =
        await _repositories.workoutExercises.listActiveForWorkout(workoutId);
    final firstIndex = workoutExercises.indexWhere(
      (exercise) => exercise.id == firstWorkoutExerciseId,
    );
    final secondIndex = workoutExercises.indexWhere(
      (exercise) => exercise.id == secondWorkoutExerciseId,
    );
    if (firstIndex == -1 ||
        secondIndex == -1 ||
        (firstIndex - secondIndex).abs() != 1) {
      throw ArgumentError(
        'Superset links require two adjacent active Workout exercises.',
      );
    }
    return workoutExercises;
  }

  Future<void> _softDeleteGroup(
    String groupId,
    _WriteContext context,
  ) async {
    final group = await _requireRow(groupId);
    final members =
        await _activeExerciseGroupMemberQuery(groupId: groupId).get();
    for (final member in members) {
      await _repositories.workoutSessions
          ._softDeleteExerciseGroupMember(member, context);
    }
    await _repositories.workoutSessions._softDeleteExerciseGroup(
      group,
      context,
    );
  }

  Future<void> _reconcileAfterWorkoutExerciseReorder({
    required String workoutId,
    required List<String> orderedWorkoutExerciseIds,
    required _WriteContext context,
  }) async {
    final groups = await listActiveForWorkout(workoutId);
    for (final group in groups) {
      final memberIds = group.workoutExerciseIds.toSet();
      final runs = <List<String>>[];
      var currentRun = <String>[];
      for (final workoutExerciseId in orderedWorkoutExerciseIds) {
        if (memberIds.contains(workoutExerciseId)) {
          currentRun.add(workoutExerciseId);
          continue;
        }
        if (currentRun.isNotEmpty) {
          runs.add(currentRun);
          currentRun = <String>[];
        }
      }
      if (currentRun.isNotEmpty) {
        runs.add(currentRun);
      }

      final survivingRuns =
          runs.where((run) => run.length >= 2).toList(growable: false);
      if (survivingRuns.isEmpty) {
        await _softDeleteGroup(group.id, context);
        continue;
      }

      await _update(
        group.id,
        name: group.name,
        colorHex: group.colorHex,
        workoutExerciseIds: survivingRuns.first,
        context: context,
      );
      for (var index = 1; index < survivingRuns.length; index += 1) {
        final activeGroups = await listActiveForWorkout(workoutId);
        await _create(
          ExerciseGroupDraft(
            workoutId: workoutId,
            name: _nextGroupName(
              activeGroups,
              baseName: group.name,
              firstSuffix: index + 1,
            ),
            colorHex: _nextGroupColor(
              activeGroups,
              excludedColorHex: group.colorHex,
            ),
            workoutExerciseIds: survivingRuns[index],
          ),
          context,
        );
      }
    }
  }

  String _nextGroupColor(
    Iterable<ExerciseGroupRecord> groups, {
    String? excludedColorHex,
  }) {
    final unavailableColors = groups.map((group) => group.colorHex).toSet();
    if (excludedColorHex != null) {
      unavailableColors.add(excludedColorHex);
    }
    return _categoryColorPalette.firstWhere(
      (colorHex) => !unavailableColors.contains(colorHex),
      orElse: () => _categoryColorPalette.firstWhere(
        (colorHex) => colorHex != excludedColorHex,
        orElse: () => _categoryColorPalette.first,
      ),
    );
  }

  String _nextGroupName(
    Iterable<ExerciseGroupRecord> groups, {
    required String baseName,
    int firstSuffix = 1,
  }) {
    final activeNames = groups.map((group) => group.name).toSet();
    var suffix = firstSuffix;
    while (activeNames.contains('$baseName $suffix')) {
      suffix += 1;
    }
    return '$baseName $suffix';
  }

  Future<String> _create(
    ExerciseGroupDraft draft,
    _WriteContext context,
  ) async {
    final workoutExerciseRows = await _requireActiveWorkoutExerciseRows(
      workoutId: draft.workoutId,
      workoutExerciseIds: draft.workoutExerciseIds,
    );
    final activeGroups =
        await _activeExerciseGroupQuery(workoutId: draft.workoutId).get();
    final id = _repositories.createId(context.timestamp);

    await _database.into(_database.exerciseGroups).insert(
          ExerciseGroupsCompanion.insert(
            id: id,
            workoutId: draft.workoutId,
            name: _normalizeGroupNameForStorage(draft.name),
            colorHex: _normalizeColorHex(draft.colorHex),
            position: _nextExerciseGroupPosition(activeGroups),
            updatedAt: context.timestamp,
          ),
        );
    final after = await _requireRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.exerciseGroupsTable,
      entityId: id,
      beforeImage: null,
      afterImage: _exerciseGroupImage(after),
    );

    for (var index = 0; index < workoutExerciseRows.length; index += 1) {
      final memberId = _repositories.createId(context.timestamp);
      await _database.into(_database.exerciseGroupMembers).insert(
            ExerciseGroupMembersCompanion.insert(
              id: memberId,
              groupId: id,
              workoutExerciseId: workoutExerciseRows[index].id,
              position: index,
              updatedAt: context.timestamp,
            ),
          );
      final member = await _requireMemberRow(memberId);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exerciseGroupMembersTable,
        entityId: memberId,
        beforeImage: null,
        afterImage: _exerciseGroupMemberImage(member),
      );
    }

    return id;
  }

  Future<List<WorkoutExerciseRow>> _requireActiveWorkoutExerciseRows({
    required String workoutId,
    required List<String> workoutExerciseIds,
    String? groupId,
  }) async {
    final uniqueIds = workoutExerciseIds.toSet();
    if (workoutExerciseIds.length < 2 ||
        uniqueIds.length != workoutExerciseIds.length) {
      throw ArgumentError.value(
        workoutExerciseIds,
        'workoutExerciseIds',
        'Exercise groups require at least two unique workout exercises.',
      );
    }

    final rows = await (_database.select(_database.workoutExercises)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.workoutId.equals(workoutId) &
                row.id.isIn(workoutExerciseIds),
          ))
        .get();
    final rowsById = <String, WorkoutExerciseRow>{
      for (final row in rows) row.id: row,
    };
    if (!uniqueIds.every(rowsById.containsKey)) {
      throw ArgumentError.value(
        workoutExerciseIds,
        'workoutExerciseIds',
        'All group members must be active exercises on the same workout.',
      );
    }

    await _ensureMembersAvailable(
      workoutId: workoutId,
      workoutExerciseIds: uniqueIds,
      groupId: groupId,
    );

    return <WorkoutExerciseRow>[
      for (final id in workoutExerciseIds) rowsById[id]!,
    ];
  }

  Future<void> _ensureMembersAvailable({
    required String workoutId,
    required Set<String> workoutExerciseIds,
    String? groupId,
  }) async {
    final activeGroups =
        await _activeExerciseGroupQuery(workoutId: workoutId).get();
    final otherGroupIds = activeGroups
        .where((group) => group.id != groupId)
        .map((group) => group.id)
        .toSet();
    if (otherGroupIds.isEmpty) {
      return;
    }

    final activeMembers =
        await _activeExerciseGroupMemberQuery(groupIds: otherGroupIds).get();
    final duplicate = activeMembers.any(
      (member) => workoutExerciseIds.contains(member.workoutExerciseId),
    );
    if (duplicate) {
      throw ArgumentError.value(
        workoutExerciseIds.toList(growable: false),
        'workoutExerciseIds',
        'Workout exercises can only belong to one active group.',
      );
    }
  }

  Future<void> _replaceMembers(
    String groupId,
    List<String> workoutExerciseIds,
    _WriteContext context,
  ) async {
    final activeRows =
        await _activeExerciseGroupMemberQuery(groupId: groupId).get();
    final activeByWorkoutExerciseId = <String, ExerciseGroupMemberRow>{
      for (final row in activeRows) row.workoutExerciseId: row,
    };
    final targetIds = workoutExerciseIds.toSet();

    for (final row in activeRows) {
      if (!targetIds.contains(row.workoutExerciseId)) {
        await (_database.update(_database.exerciseGroupMembers)
              ..where((table) => table.id.equals(row.id)))
            .write(
          ExerciseGroupMembersCompanion(
            updatedAt: Value<DateTime>(context.timestamp),
            deletedAt: Value<DateTime?>(context.timestamp),
          ),
        );
        final after = await _requireMemberRow(row.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.exerciseGroupMembersTable,
          entityId: row.id,
          beforeImage: _exerciseGroupMemberImage(row),
          afterImage: _exerciseGroupMemberImage(after),
        );
      }
    }

    for (var index = 0; index < workoutExerciseIds.length; index += 1) {
      final workoutExerciseId = workoutExerciseIds[index];
      final existing = activeByWorkoutExerciseId[workoutExerciseId];
      if (existing == null) {
        final memberId = _repositories.createId(context.timestamp);
        await _database.into(_database.exerciseGroupMembers).insert(
              ExerciseGroupMembersCompanion.insert(
                id: memberId,
                groupId: groupId,
                workoutExerciseId: workoutExerciseId,
                position: index,
                updatedAt: context.timestamp,
              ),
            );
        final after = await _requireMemberRow(memberId);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.exerciseGroupMembersTable,
          entityId: memberId,
          beforeImage: null,
          afterImage: _exerciseGroupMemberImage(after),
        );
        continue;
      }

      if (existing.position == index) {
        continue;
      }

      await (_database.update(_database.exerciseGroupMembers)
            ..where((table) => table.id.equals(existing.id)))
          .write(
        ExerciseGroupMembersCompanion(
          position: Value<int>(index),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireMemberRow(existing.id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.exerciseGroupMembersTable,
        entityId: existing.id,
        beforeImage: _exerciseGroupMemberImage(existing),
        afterImage: _exerciseGroupMemberImage(after),
      );
    }
  }

  Future<ExerciseGroupRow> _requireRow(String id) async {
    final row = await (_database.select(_database.exerciseGroups)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Exercise group not found: $id.');
    }
    return row;
  }

  Future<ExerciseGroupMemberRow> _requireMemberRow(String id) async {
    final row = await (_database.select(_database.exerciseGroupMembers)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Exercise group member not found: $id.');
    }
    return row;
  }
}

class RestTimerRepository {
  const RestTimerRepository._(this._repositories);

  static const defaultDuration = Duration(seconds: 120);
  static const defaultAlertVolume = 1.0;

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<String> start(
    RestTimerDraft draft, {
    String actor = 'app',
    String? batchId,
    DateTime? now,
  }) {
    if (draft.duration <= Duration.zero) {
      throw ArgumentError.value(
        draft.duration,
        'duration',
        'Rest timer duration must be positive.',
      );
    }

    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    final startedAt = (now ?? DateTime.now()).toUtc();
    final alertVolume = _normalizeAlertVolume(draft.alertVolume);

    return _database.transaction(() async {
      await _cancelCurrentForWorkout(draft.workoutId, context);

      final id = _repositories.createId(context.timestamp);
      await _database.into(_database.restTimers).insert(
            RestTimersCompanion.insert(
              id: id,
              workoutId: Value<String?>(draft.workoutId),
              sourceSetId: Value<String?>(draft.sourceSetId),
              startedAt: startedAt,
              deadlineAt: startedAt.add(draft.duration),
              durationSeconds: draft.duration.inSeconds,
              alertVolume: Value<double>(alertVolume),
              status: Value<String>(RestTimerStatus.running.name),
              updatedAt: context.timestamp,
            ),
          );

      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.restTimersTable,
        entityId: id,
        beforeImage: null,
        afterImage: _restTimerImage(after),
      );

      return id;
    });
  }

  Future<String> startForSet(
    LoggedSetRecord set, {
    Duration defaultDuration = RestTimerRepository.defaultDuration,
    double alertVolume = defaultAlertVolume,
    String actor = 'app',
    String? batchId,
    DateTime? now,
  }) {
    return start(
      RestTimerDraft(
        workoutId: set.workoutId,
        sourceSetId: set.id,
        duration: set.plannedRestAfter ?? defaultDuration,
        alertVolume: alertVolume,
      ),
      actor: actor,
      batchId: batchId,
      now: now,
    );
  }

  Future<void> cancel(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      await _writeCanceled(before, context);
    });
  }

  Future<void> markAlertFired(
    String id, {
    String actor = 'app',
    String? batchId,
    DateTime? now,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    final firedAt = (now ?? DateTime.now()).toUtc();

    return _database.transaction(() async {
      final before = await _requireRow(id);
      if (before.alertFiredAt != null) {
        return;
      }

      await (_database.update(_database.restTimers)
            ..where((row) => row.id.equals(id)))
          .write(
        RestTimersCompanion(
          status: Value<String>(RestTimerStatus.expired.name),
          alertFiredAt: Value<DateTime?>(firedAt),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.restTimersTable,
        entityId: id,
        beforeImage: _restTimerImage(before),
        afterImage: _restTimerImage(after),
      );
    });
  }

  /// Marks the 3-2-1 prepare cue as fired for this rest timer.
  ///
  /// Unlike [markAlertFired] this never transitions status: the timer is still
  /// running toward its deadline. Fire-once: a no-op if already set.
  Future<void> markPrepareAlertFired(
    String id, {
    String actor = 'app',
    String? batchId,
    DateTime? now,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    final firedAt = (now ?? DateTime.now()).toUtc();

    return _database.transaction(() async {
      final before = await _requireRow(id);
      if (before.prepareAlertFiredAt != null) {
        return;
      }

      await (_database.update(_database.restTimers)
            ..where((row) => row.id.equals(id)))
          .write(
        RestTimersCompanion(
          prepareAlertFiredAt: Value<DateTime?>(firedAt),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.restTimersTable,
        entityId: id,
        beforeImage: _restTimerImage(before),
        afterImage: _restTimerImage(after),
      );
    });
  }

  Future<void> updateAlertVolume(
    String id, {
    required double alertVolume,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );
    final normalized = _normalizeAlertVolume(alertVolume);

    return _database.transaction(() async {
      final before = await _requireRow(id);
      if (before.alertVolume == normalized) {
        return;
      }

      await (_database.update(_database.restTimers)
            ..where((row) => row.id.equals(id)))
          .write(
        RestTimersCompanion(
          alertVolume: Value<double>(normalized),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.restTimersTable,
        entityId: id,
        beforeImage: _restTimerImage(before),
        afterImage: _restTimerImage(after),
      );
    });
  }

  Future<RestTimerRecord?> getById(String id) async {
    final row = await (_database.select(_database.restTimers)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _restTimerFromRow(row);
  }

  Future<RestTimerRecord?> getCurrentForWorkout(String workoutId) async {
    final rows = await _currentForWorkoutQuery(workoutId).get();
    return rows.isEmpty ? null : _restTimerFromRow(rows.first);
  }

  Stream<RestTimerRecord?> watchCurrentForWorkout(String workoutId) {
    return _currentForWorkoutQuery(workoutId).watch().map(
          (rows) => rows.isEmpty ? null : _restTimerFromRow(rows.first),
        );
  }

  SimpleSelectStatement<$RestTimersTable, RestTimerRow> _currentForWorkoutQuery(
      String workoutId) {
    final query = _database.select(_database.restTimers)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.workoutId.equals(workoutId) &
            row.status.equals(RestTimerStatus.canceled.name).not(),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.updatedAt),
        (row) => OrderingTerm.desc(row.startedAt),
      ])
      ..limit(1);
    return query;
  }

  Future<void> _cancelCurrentForWorkout(
    String? workoutId,
    _WriteContext context,
  ) async {
    if (workoutId == null) {
      return;
    }

    final rows = await _currentForWorkoutQuery(workoutId).get();
    for (final row in rows) {
      await _writeCanceled(row, context);
    }
  }

  Future<void> _writeCanceled(
    RestTimerRow before,
    _WriteContext context,
  ) async {
    if (before.deletedAt != null ||
        before.status == RestTimerStatus.canceled.name) {
      return;
    }

    await (_database.update(_database.restTimers)
          ..where((row) => row.id.equals(before.id)))
        .write(
      RestTimersCompanion(
        status: Value<String>(RestTimerStatus.canceled.name),
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: Value<DateTime?>(context.timestamp),
      ),
    );
    final after = await _requireRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.restTimersTable,
      entityId: before.id,
      beforeImage: _restTimerImage(before),
      afterImage: _restTimerImage(after),
    );
  }

  Future<RestTimerRow> _requireRow(String id) async {
    final row = await (_database.select(_database.restTimers)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Rest timer not found: $id.');
    }
    return row;
  }
}

class LoggedSetRepository {
  const LoggedSetRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<String> create(
    LoggedSetDraft draft, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() => _create(draft, context));
  }

  Future<SetValidationResult> validateEntry(LoggedSetDraft draft) {
    return _validateDraft(draft);
  }

  Future<void> applySyncImage({
    required Map<String, Object?> image,
    required String deviceId,
    required String batchId,
    String actor = 'sync',
    String? activityLogId,
    Map<String, Object?>? activityBeforeImage,
    Map<String, Object?>? activityAfterImage,
    DateTime? activityOccurredAt,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final id = _activityRequiredString(image, 'id');
      final before = await (_database.select(_database.loggedSets)
            ..where((row) => row.id.equals(id)))
          .getSingleOrNull();
      final localBeforeImage = before == null ? null : _loggedSetImage(before);

      await _ensureSyncWorkoutParent(image, deviceId: deviceId);
      await _database.into(_database.loggedSets).insertOnConflictUpdate(
            _loggedSetSyncCompanionFromImage(
              image,
              syncDeviceId: deviceId,
            ),
          );

      final after = await _requireRow(id);
      final localAfterImage = _loggedSetImage(after);
      if (localBeforeImage != null &&
          _activityImagesEqual(localBeforeImage, localAfterImage)) {
        return;
      }
      final normalizedActivityBeforeImage = activityBeforeImage == null
          ? null
          : _loggedSetActivityImageFromSyncImage(activityBeforeImage);
      final normalizedActivityAfterImage = activityAfterImage == null
          ? null
          : _loggedSetActivityImageFromSyncImage(activityAfterImage);

      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.loggedSetsTable,
        entityId: id,
        beforeImage: normalizedActivityBeforeImage ?? localBeforeImage,
        afterImage: normalizedActivityAfterImage ?? localAfterImage,
        id: activityLogId,
        occurredAt: activityOccurredAt,
        syncAcknowledgedAt: context.timestamp,
      );
    });
  }

  Future<void> _ensureSyncWorkoutParent(
    Map<String, Object?> image, {
    required String deviceId,
  }) async {
    final workoutStartedAt = _activityNullableDateTime(
      image,
      'workout_started_at',
    );
    final workoutTimezone = _activityNullableString(
      image,
      'workout_timezone',
    );
    if (workoutStartedAt == null || workoutTimezone == null) {
      return;
    }

    final workoutId = _activityRequiredString(image, 'workout_id');
    final existing = await (_database.select(_database.workoutSessions)
          ..where((row) => row.id.equals(workoutId)))
        .getSingleOrNull();
    if (existing != null) {
      return;
    }

    await _database.into(_database.workoutSessions).insert(
          WorkoutSessionsCompanion.insert(
            id: workoutId,
            startedAt: workoutStartedAt,
            timezone: workoutTimezone,
            localDate: Value<String>(
              _activityNullableString(image, 'workout_local_date') ??
                  TrainingDayDate.fromDateTime(workoutStartedAt).storageValue,
            ),
            endedAt: Value<DateTime?>(
              _activityNullableDateTime(image, 'workout_ended_at'),
            ),
            comment: Value<String?>(
              _activityNullableString(image, 'workout_comment'),
            ),
            syncDeviceId: Value<String?>(deviceId),
            syncPreviouslySynced: const Value<bool>(true),
            updatedAt: _activityRequiredDateTime(image, 'updated_at'),
            deletedAt: Value<DateTime?>(
              _activityNullableDateTime(image, 'deleted_at'),
            ),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> updateValues(
    String id, {
    required LoggedSet values,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      final validation = await _validateValuesForExercise(
        exerciseId: before.exerciseId,
        values: values.values.values,
        rpe: before.rpe,
        side: before.side,
      );
      validation.throwIfRejected();

      final columns = _setColumns(values);
      await (_database.update(_database.loggedSets)
            ..where((row) => row.id.equals(id)))
          .write(
        _loggedSetValueCompanion(
          columns,
          updatedAt: context.timestamp,
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.loggedSetsTable,
        entityId: id,
        beforeImage: _loggedSetImage(before),
        afterImage: _loggedSetImage(after),
      );
    });
  }

  Future<void> updateAnnotations(
    String id, {
    String? comment,
    SetSide? side,
    double? rpe,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      final normalizedComment = _normalizeSetComment(comment);
      final normalizedSide = side?.name;
      final validation = await _validateValuesForExercise(
        exerciseId: before.exerciseId,
        values: _loggedSetValuesFromRow(before).values.values,
        rpe: rpe,
        side: normalizedSide,
      );
      validation.throwIfRejected();
      final normalizedRpe = _normalizeRpe(rpe);

      if (before.comment == normalizedComment &&
          before.side == normalizedSide &&
          before.rpe == normalizedRpe) {
        return;
      }

      await (_database.update(_database.loggedSets)
            ..where((row) => row.id.equals(id)))
          .write(
        LoggedSetsCompanion(
          comment: Value<String?>(normalizedComment),
          side: Value<String?>(normalizedSide),
          rpe: Value<double?>(normalizedRpe),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.loggedSetsTable,
        entityId: id,
        beforeImage: _loggedSetImage(before),
        afterImage: _loggedSetImage(after),
      );
    });
  }

  Future<void> softDelete(
    String id, {
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      await (_database.update(_database.loggedSets)
            ..where((row) => row.id.equals(id)))
          .write(
        LoggedSetsCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.loggedSetsTable,
        entityId: id,
        beforeImage: _loggedSetImage(before),
        afterImage: _loggedSetImage(after),
      );
    });
  }

  Future<void> setCompleted(
    String id, {
    required bool isCompleted,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final before = await _requireRow(id);
      await (_database.update(_database.loggedSets)
            ..where((row) => row.id.equals(id)))
          .write(
        LoggedSetsCompanion(
          isCompleted: Value<bool>(isCompleted),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.loggedSetsTable,
        entityId: id,
        beforeImage: _loggedSetImage(before),
        afterImage: _loggedSetImage(after),
      );
    });
  }

  Future<void> markComplete(
    String id, {
    required bool isCompleted,
    String actor = 'app',
    String? batchId,
  }) {
    return setCompleted(
      id,
      isCompleted: isCompleted,
      actor: actor,
      batchId: batchId,
    );
  }

  Future<void> reorderForWorkoutExercise({
    required String workoutId,
    required String exerciseId,
    required List<String> orderedIds,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final activeRows =
          await _activeLoggedSetQuery(workoutId: workoutId).get();
      final targetRows = activeRows
          .where((row) => row.exerciseId == exerciseId)
          .toList(growable: false);
      final rowById = <String, LoggedSetRow>{
        for (final row in targetRows) row.id: row,
      };
      final uniqueOrderedIds = orderedIds.toSet();
      if (uniqueOrderedIds.length != orderedIds.length ||
          !rowById.keys.toSet().containsAll(orderedIds)) {
        throw ArgumentError.value(
          orderedIds,
          'orderedIds',
          'Reorder ids must belong to the workout exercise exactly once.',
        );
      }

      final positions = targetRows.map((row) => row.position).toList()..sort();
      final reorderedRows = <LoggedSetRow>[
        for (final id in orderedIds) rowById[id]!,
        for (final row in targetRows)
          if (!uniqueOrderedIds.contains(row.id)) row,
      ];
      await _writePositions(reorderedRows, positions, context);
    });
  }

  Future<void> reorderForWorkout({
    required String workoutId,
    required List<String> orderedIds,
    String actor = 'app',
    String? batchId,
  }) {
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final activeRows =
          await _activeLoggedSetQuery(workoutId: workoutId).get();
      final rowById = <String, LoggedSetRow>{
        for (final row in activeRows) row.id: row,
      };
      final uniqueOrderedIds = orderedIds.toSet();
      if (uniqueOrderedIds.length != orderedIds.length ||
          !rowById.keys.toSet().containsAll(orderedIds)) {
        throw ArgumentError.value(
          orderedIds,
          'orderedIds',
          'Reorder ids must belong to the workout exactly once.',
        );
      }

      final reorderedRows = <LoggedSetRow>[
        for (final id in orderedIds) rowById[id]!,
        for (final row in activeRows)
          if (!uniqueOrderedIds.contains(row.id)) row,
      ];
      await _writePositions(
        reorderedRows,
        List<int>.generate(reorderedRows.length, (index) => index),
        context,
      );
    });
  }

  Future<void> reorder(
    String workoutId,
    List<String> orderedIds, {
    String actor = 'app',
    String? batchId,
  }) {
    return reorderForWorkout(
      workoutId: workoutId,
      orderedIds: orderedIds,
      actor: actor,
      batchId: batchId,
    );
  }

  Future<LoggedSetRecord?> getById(String id) async {
    final row = await (_database.select(_database.loggedSets)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _loggedSetFromRow(row);
  }

  Future<List<LoggedSetRecord>> listActiveForWorkout(String workoutId) async {
    final query = _activeLoggedSetQuery(workoutId: workoutId);
    final rows = await query.get();
    return rows.map(_loggedSetFromRow).toList(growable: false);
  }

  Future<List<LoggedSetRecord>> listActiveForWorkoutIds(
    Set<String> workoutIds,
  ) async {
    if (workoutIds.isEmpty) {
      return const <LoggedSetRecord>[];
    }

    final query = _activeLoggedSetQuery(workoutIds: workoutIds);
    final rows = await query.get();
    return rows.map(_loggedSetFromRow).toList(growable: false);
  }

  Future<List<LoggedSetRecord>> listActiveForExercise(String exerciseId) async {
    final query = _activeLoggedSetQuery(exerciseId: exerciseId);
    final rows = await query.get();
    return rows.map(_loggedSetFromRow).toList(growable: false);
  }

  Future<int> nextPositionForWorkout(String workoutId) async {
    final maxPosition = _database.loggedSets.position.max();
    final query = _database.selectOnly(_database.loggedSets)
      ..addColumns([maxPosition])
      ..where(
        _database.loggedSets.deletedAt.isNull() &
            _database.loggedSets.workoutId.equals(workoutId),
      );
    final row = await query.getSingle();
    return (row.read(maxPosition) ?? -1) + 1;
  }

  Future<List<LoggedSetRecord>> listAllActive() async {
    final query = _activeLoggedSetQuery();
    final rows = await query.get();
    return rows.map(_loggedSetFromRow).toList(growable: false);
  }

  Future<LoggedSetRecord?> findLatestPriorForExercise({
    required String exerciseId,
    required String beforeWorkoutId,
    required List<DimensionId> dimensions,
  }) async {
    final currentWorkout = await (_database.select(_database.workoutSessions)
          ..where((row) => row.id.equals(beforeWorkoutId)))
        .getSingleOrNull();
    if (currentWorkout == null) {
      throw StateError('Workout session not found: $beforeWorkoutId.');
    }

    return _findLatestPriorForExercise(
      exerciseId: exerciseId,
      beforeStartedAt: currentWorkout.startedAt,
      dimensions: dimensions,
      excludeWorkoutId: beforeWorkoutId,
    );
  }

  Future<LoggedSetRecord?> findLatestPriorForExerciseBefore({
    required String exerciseId,
    required DateTime beforeStartedAt,
    required List<DimensionId> dimensions,
  }) {
    return _findLatestPriorForExercise(
      exerciseId: exerciseId,
      beforeStartedAt: beforeStartedAt,
      dimensions: dimensions,
    );
  }

  Future<LoggedSetRecord?> _findLatestPriorForExercise({
    required String exerciseId,
    required DateTime beforeStartedAt,
    required List<DimensionId> dimensions,
    String? excludeWorkoutId,
  }) async {
    final setRows = await (_database.select(_database.loggedSets)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.exerciseId.equals(exerciseId) &
                (excludeWorkoutId == null
                    ? const Constant(true)
                    : row.workoutId.equals(excludeWorkoutId).not()),
          ))
        .get();
    if (setRows.isEmpty) {
      return null;
    }

    final workoutIds = setRows.map((row) => row.workoutId).toSet();
    final workoutRows = await (_database.select(_database.workoutSessions)
          ..where((row) => row.id.isIn(workoutIds)))
        .get();
    final workoutById = <String, WorkoutSessionRow>{
      for (final row in workoutRows) row.id: row,
    };
    final candidates = <({LoggedSetRow set, WorkoutSessionRow workout})>[];
    for (final setRow in setRows) {
      final workout = workoutById[setRow.workoutId];
      if (workout == null ||
          workout.deletedAt != null ||
          !workout.startedAt.isBefore(beforeStartedAt)) {
        continue;
      }

      final set = _loggedSetFromRow(setRow);
      if (!_sameDimensionIds(set.values.dimensionIds, dimensions)) {
        continue;
      }

      candidates.add((set: setRow, workout: workout));
    }

    candidates.sort((left, right) {
      final workoutComparison =
          right.workout.startedAt.compareTo(left.workout.startedAt);
      if (workoutComparison != 0) {
        return workoutComparison;
      }

      final positionComparison = right.set.position.compareTo(
        left.set.position,
      );
      if (positionComparison != 0) {
        return positionComparison;
      }

      return right.set.updatedAt.compareTo(left.set.updatedAt);
    });

    return candidates.isEmpty ? null : _loggedSetFromRow(candidates.first.set);
  }

  Stream<List<LoggedSetRecord>> watchActiveForWorkout(String workoutId) {
    return _activeLoggedSetQuery(workoutId: workoutId).watch().map(
          (rows) => rows.map(_loggedSetFromRow).toList(growable: false),
        );
  }

  Stream<List<LoggedSetRecord>> watchActiveForWorkoutIds(
    Set<String> workoutIds,
  ) {
    if (workoutIds.isEmpty) {
      return Stream<List<LoggedSetRecord>>.value(
        const <LoggedSetRecord>[],
      );
    }

    return _activeLoggedSetQuery(workoutIds: workoutIds).watch().map(
          (rows) => rows.map(_loggedSetFromRow).toList(growable: false),
        );
  }

  Stream<List<LoggedSetRecord>> watchAllActive() {
    return _activeLoggedSetQuery().watch().map(
          (rows) => rows.map(_loggedSetFromRow).toList(growable: false),
        );
  }

  SimpleSelectStatement<$LoggedSetsTable, LoggedSetRow> _activeLoggedSetQuery({
    String? workoutId,
    Set<String>? workoutIds,
    String? exerciseId,
  }) {
    final query = _database.select(_database.loggedSets)
      ..where((row) => row.deletedAt.isNull());
    if (workoutId != null) {
      query.where((row) => row.workoutId.equals(workoutId));
      query.orderBy([(row) => OrderingTerm.asc(row.position)]);
    } else if (workoutIds != null) {
      query.where((row) => row.workoutId.isIn(workoutIds));
      query.orderBy([
        (row) => OrderingTerm.asc(row.workoutId),
        (row) => OrderingTerm.asc(row.position),
        (row) => OrderingTerm.asc(row.updatedAt),
      ]);
    } else if (exerciseId != null) {
      query.where((row) => row.exerciseId.equals(exerciseId));
      query.orderBy([
        (row) => OrderingTerm.asc(row.workoutId),
        (row) => OrderingTerm.asc(row.position),
        (row) => OrderingTerm.asc(row.updatedAt),
      ]);
    } else {
      query.orderBy([
        (row) => OrderingTerm.asc(row.workoutId),
        (row) => OrderingTerm.asc(row.position),
        (row) => OrderingTerm.asc(row.updatedAt),
      ]);
    }
    return query;
  }

  Future<String> _create(LoggedSetDraft draft, _WriteContext context) async {
    final workoutId = draft.workoutId;
    if (workoutId == null) {
      throw ArgumentError.value(
        draft,
        'draft',
        'Logged set creation requires a workout id.',
      );
    }
    final validation = await _validateDraft(draft);
    validation.throwIfRejected();

    final id = _repositories.createId(context.timestamp);
    final columns = _setColumns(draft.values);
    await _database.into(_database.loggedSets).insert(
          _loggedSetInsertCompanion(
            id: id,
            workoutId: workoutId,
            exerciseId: draft.exerciseId,
            position: draft.position,
            isCompleted: draft.isCompleted,
            columns: columns,
            plannedRestAfter: draft.plannedRestAfter,
            performedAt: draft.performedAt ?? context.timestamp,
            comment: _normalizeSetComment(draft.comment),
            side: draft.side,
            rpe: _normalizeRpe(draft.rpe),
            updatedAt: context.timestamp,
          ),
        );

    final after = await _requireRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.loggedSetsTable,
      entityId: id,
      beforeImage: null,
      afterImage: _loggedSetImage(after),
    );

    return id;
  }

  Future<SetValidationResult> _validateDraft(LoggedSetDraft draft) {
    return _validateValuesForExercise(
      exerciseId: draft.exerciseId,
      values: draft.values.values.values,
      rpe: draft.rpe,
      side: draft.side?.name,
    );
  }

  Future<SetValidationResult> _validateValuesForExercise({
    required String exerciseId,
    required Iterable<SetDimensionValue> values,
    required Object? rpe,
    required String? side,
  }) async {
    final exerciseRow = await (_database.select(_database.exercises)
          ..where((row) => row.id.equals(exerciseId)))
        .getSingleOrNull();
    if (exerciseRow == null) {
      throw StateError('Exercise not found: $exerciseId.');
    }
    final exercise = _exerciseFromRow(exerciseRow);

    return validateSetValues(
      type: exercise.type,
      loadMode: exercise.loadMode,
      values: values,
      rpe: rpe,
      side: side,
    );
  }

  Future<void> _writePositions(
    List<LoggedSetRow> rows,
    List<int> positions,
    _WriteContext context,
  ) async {
    for (var index = 0; index < rows.length; index += 1) {
      final row = rows[index];
      final position = positions[index];
      if (row.position == position) {
        continue;
      }

      await (_database.update(_database.loggedSets)
            ..where((table) => table.id.equals(row.id)))
          .write(
        LoggedSetsCompanion(
          position: Value<int>(position),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireRow(row.id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.loggedSetsTable,
        entityId: row.id,
        beforeImage: _loggedSetImage(row),
        afterImage: _loggedSetImage(after),
      );
    }
  }

  Future<LoggedSetRow> _requireRow(String id) async {
    final row = await (_database.select(_database.loggedSets)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Logged set not found: $id.');
    }
    return row;
  }
}

class MeasurementRepository {
  const MeasurementRepository._(this._repositories);

  static const defaultBodyWeightName = 'Body Weight';
  static const defaultBodyFatName = 'Body Fat';

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<void> ensureDefaultMeasurements({
    required MeasurementUnit bodyWeightUnit,
    String actor = 'app',
  }) async {
    final context = _repositories._createWriteContext(actor: actor);

    await _database.transaction(() async {
      final existing = await _manageableMeasurementQuery().get();
      final activeNames = existing.map((row) => row.name).toSet();

      if (!activeNames.contains(defaultBodyWeightName)) {
        await _createMeasurementMetric(
          MeasurementDraft(
            name: defaultBodyWeightName,
            unit: bodyWeightUnit,
            goalType: MeasurementGoalType.decrease,
            enabled: true,
            sortOrder: 0,
          ),
          context,
        );
      }
      if (!activeNames.contains(defaultBodyFatName)) {
        await _createMeasurementMetric(
          const MeasurementDraft(
            name: defaultBodyFatName,
            unit: MeasurementUnit.percent,
            goalType: MeasurementGoalType.decrease,
            enabled: true,
            sortOrder: 1,
          ),
          context,
        );
      }
    });
  }

  Future<List<MeasurementRecord>> listEnabled() async {
    final rows = await _enabledMeasurementQuery().get();
    return rows.map(_measurementRecordFromMetricRow).toList(growable: false);
  }

  Future<List<MeasurementRecord>> listActive() async {
    final rows = await _manageableMeasurementQuery().get();
    return rows.map(_measurementRecordFromMetricRow).toList(growable: false);
  }

  Future<List<MeasurementRecord>> listCuratedActive() async {
    final rows = await _curatedMeasurementQuery().get();
    return rows.map(_measurementRecordFromMetricRow).toList(growable: false);
  }

  Stream<List<MeasurementRecord>> watchCuratedActive() async* {
    List<MeasurementRecord>? lastEmitted;

    await for (final rows in _curatedMeasurementQuery().watch()) {
      final next =
          rows.map(_measurementRecordFromMetricRow).toList(growable: false);
      if (_sameMeasurementRecords(lastEmitted, next)) {
        continue;
      }

      lastEmitted = next;
      yield next;
    }
  }

  Stream<MeasurementRecord?> watchCuratedActiveById(String id) async* {
    final query = _curatedMeasurementQuery()..where((row) => row.id.equals(id));
    MeasurementRecord? lastEmitted;
    var hasLastEmitted = false;

    await for (final rows in query.watch()) {
      final next =
          rows.isEmpty ? null : _measurementRecordFromMetricRow(rows.single);
      if (hasLastEmitted && _sameNullableMeasurementRecord(lastEmitted, next)) {
        continue;
      }

      hasLastEmitted = true;
      lastEmitted = next;
      yield next;
    }
  }

  Stream<List<MeasurementRecord>> watchActive() async* {
    List<MeasurementRecord>? lastEmitted;

    await for (final rows in _manageableMeasurementQuery().watch()) {
      final next =
          rows.map(_measurementRecordFromMetricRow).toList(growable: false);
      if (_sameMeasurementRecords(lastEmitted, next)) {
        continue;
      }

      lastEmitted = next;
      yield next;
    }
  }

  Future<List<MeasurementTrackSummary>> listTrackSummaries() async {
    final measurements = await _enabledMeasurementQuery().get();
    final entryRowsByMeasurementId = await _latestEntryRowsByMeasurementId(
      measurements,
    );
    return _trackSummariesFromRows(measurements, entryRowsByMeasurementId);
  }

  Future<List<MeasurementHistoryEntry>> listHistoryEntries({
    String? measurementId,
  }) async {
    final measurementRows = await _curatedMeasurementQuery().get();

    final query = _activeEntryQuery();
    if (measurementId != null) {
      query.where((row) => row.metricId.equals(measurementId));
    }
    query.orderBy([
      (row) => OrderingTerm.desc(row.atTime),
      (row) => OrderingTerm.desc(row.id),
    ]);
    final rows = await query.get();

    return _measurementHistoryEntriesFromRows(measurementRows, rows);
  }

  List<MeasurementHistoryEntry> _measurementHistoryEntriesFromRows(
    List<MetricRow> measurementRows,
    List<MetricReadingRow> rows,
  ) {
    final measurementsById = <String, MeasurementRecord>{
      for (final row in measurementRows)
        row.id: _measurementRecordFromMetricRow(row),
    };

    final rowsByMeasurementId = <String, List<MetricReadingRow>>{};
    for (final row in rows) {
      rowsByMeasurementId.putIfAbsent(row.metricId, () => []).add(row);
    }
    final history = <MeasurementHistoryEntry>[];
    for (final row in rows) {
      final measurement = measurementsById[row.metricId];
      if (measurement == null) {
        continue;
      }
      final measurementRows = rowsByMeasurementId[row.metricId]!;
      final index = measurementRows.indexWhere((entry) => entry.id == row.id);
      final previousEntry = index == -1 || index + 1 >= measurementRows.length
          ? null
          : _measurementEntryRecordFromMetricReadingRow(
              measurementRows[index + 1],
            );

      history.add(
        MeasurementHistoryEntry(
          measurement: measurement,
          entry: _measurementEntryRecordFromMetricReadingRow(row),
          previousEntry: previousEntry,
        ),
      );
    }
    return List<MeasurementHistoryEntry>.unmodifiable(history);
  }

  Stream<List<MeasurementTrackSummary>> watchTrackSummaries() {
    late final StreamSubscription<List<MetricRow>> measurementSubscription;
    final entrySubscriptions =
        <String, StreamSubscription<List<MetricReadingRow>>>{};
    final entryRowsByMeasurementId = <String, List<MetricReadingRow>>{};
    final controller = StreamController<List<MeasurementTrackSummary>>();
    List<MetricRow>? latestMeasurements;
    List<String> watchedMeasurementIds = const <String>[];
    List<MeasurementTrackSummary>? lastEmitted;

    void addIfChanged(List<MeasurementTrackSummary> summaries) {
      if (_sameMeasurementTrackSummaries(lastEmitted, summaries)) {
        return;
      }
      lastEmitted = summaries;
      controller.add(summaries);
    }

    bool entriesReadyFor(List<String> measurementIds) {
      for (final measurementId in measurementIds) {
        if (!entryRowsByMeasurementId.containsKey(measurementId)) {
          return false;
        }
      }
      return true;
    }

    void emitIfReady() {
      final measurements = latestMeasurements;
      if (measurements == null || !entriesReadyFor(watchedMeasurementIds)) {
        return;
      }

      addIfChanged(
        _trackSummariesFromRows(measurements, entryRowsByMeasurementId),
      );
    }

    void watchEntriesFor(List<MetricRow> measurements) {
      final measurementIds =
          measurements.map((row) => row.id).toList(growable: false);
      if (_sameMeasurementIdList(watchedMeasurementIds, measurementIds)) {
        emitIfReady();
        return;
      }

      final measurementIdSet = measurementIds.toSet();
      for (final measurementId in entrySubscriptions.keys.toList()) {
        if (measurementIdSet.contains(measurementId)) {
          continue;
        }
        entrySubscriptions.remove(measurementId)?.cancel().ignore();
        entryRowsByMeasurementId.remove(measurementId);
      }

      watchedMeasurementIds = measurementIds;
      if (measurementIds.isEmpty) {
        emitIfReady();
        return;
      }

      for (final measurementId in measurementIds) {
        if (entrySubscriptions.containsKey(measurementId)) {
          continue;
        }
        entryRowsByMeasurementId.remove(measurementId);
        entrySubscriptions[measurementId] = _latestEntryRows(
          measurementId,
          limit: 2,
        ).watch().listen(
          (rows) {
            entryRowsByMeasurementId[measurementId] =
                List<MetricReadingRow>.unmodifiable(rows);
            emitIfReady();
          },
          onError: controller.addError,
        );
      }
      emitIfReady();
    }

    controller.onListen = () {
      measurementSubscription = _enabledMeasurementQuery().watch().listen(
        (rows) {
          latestMeasurements = rows;
          watchEntriesFor(rows);
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () {
      measurementSubscription.cancel().ignore();
      for (final subscription in entrySubscriptions.values) {
        subscription.cancel().ignore();
      }
    };

    return controller.stream;
  }

  Future<Map<String, List<MetricReadingRow>>> _latestEntryRowsByMeasurementId(
    List<MetricRow> measurements,
  ) async {
    final entriesByMeasurementId = <String, List<MetricReadingRow>>{};
    for (final measurement in measurements) {
      final entries = await _latestEntryRows(measurement.id, limit: 2).get();
      entriesByMeasurementId[measurement.id] =
          List<MetricReadingRow>.unmodifiable(entries);
    }
    return Map<String, List<MetricReadingRow>>.unmodifiable(
      entriesByMeasurementId,
    );
  }

  List<MeasurementTrackSummary> _trackSummariesFromRows(
    List<MetricRow> measurements,
    Map<String, List<MetricReadingRow>> entryRowsByMeasurementId,
  ) {
    return List<MeasurementTrackSummary>.unmodifiable(
      measurements.map((measurement) {
        final entries = entryRowsByMeasurementId[measurement.id] ??
            const <MetricReadingRow>[];
        return MeasurementTrackSummary(
          measurement: _measurementRecordFromMetricRow(measurement),
          latestEntry: entries.isEmpty
              ? null
              : _measurementEntryRecordFromMetricReadingRow(entries.first),
          previousEntry: entries.length < 2
              ? null
              : _measurementEntryRecordFromMetricReadingRow(entries[1]),
        );
      }),
    );
  }

  Stream<List<MeasurementHistoryEntry>> watchHistoryEntries({
    String? measurementId,
  }) async* {
    if (measurementId != null) {
      yield* _watchMeasurementHistoryEntries(measurementId);
      return;
    }

    yield* _watchAllMeasurementHistoryEntries();
  }

  Stream<List<MeasurementHistoryEntry>> _watchAllMeasurementHistoryEntries() {
    late final StreamSubscription<List<MetricRow>> measurementSubscription;
    StreamSubscription<List<MetricReadingRow>>? entrySubscription;
    final controller = StreamController<List<MeasurementHistoryEntry>>();
    List<MetricRow>? latestMeasurements;
    List<MetricReadingRow>? latestEntries;
    List<String> watchedMeasurementIds = const <String>[];
    List<MeasurementHistoryEntry>? lastEmitted;

    void emitIfReady() {
      final measurements = latestMeasurements;
      final entries = latestEntries;
      if (measurements == null || entries == null) {
        return;
      }

      final history = _measurementHistoryEntriesFromRows(
        measurements,
        entries,
      );
      if (_sameMeasurementHistoryEntries(lastEmitted, history)) {
        return;
      }
      lastEmitted = history;
      controller.add(history);
    }

    void watchEntriesFor(List<MetricRow> measurements) {
      final measurementIds =
          measurements.map((row) => row.id).toList(growable: false);
      if (_sameMeasurementIdList(watchedMeasurementIds, measurementIds)) {
        emitIfReady();
        return;
      }

      watchedMeasurementIds = measurementIds;
      latestEntries = null;
      entrySubscription?.cancel().ignore();
      entrySubscription = null;
      if (measurementIds.isEmpty) {
        latestEntries = const <MetricReadingRow>[];
        emitIfReady();
        return;
      }

      entrySubscription =
          _activeEntryRowsForMeasurements(measurementIds).watch().listen(
        (rows) {
          latestEntries = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    }

    controller.onListen = () {
      measurementSubscription = _curatedMeasurementQuery().watch().listen(
        (rows) {
          latestMeasurements = rows;
          watchEntriesFor(rows);
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () {
      measurementSubscription.cancel().ignore();
      entrySubscription?.cancel().ignore();
    };

    return controller.stream;
  }

  Stream<List<MeasurementHistoryEntry>> _watchMeasurementHistoryEntries(
    String measurementId,
  ) {
    late final StreamSubscription<List<MetricRow>> measurementSubscription;
    late final StreamSubscription<List<MetricReadingRow>> entrySubscription;
    final controller = StreamController<List<MeasurementHistoryEntry>>();
    List<MetricRow>? latestMeasurements;
    List<MetricReadingRow>? latestEntries;
    List<MeasurementHistoryEntry>? lastEmitted;

    void emitIfReady() {
      final measurements = latestMeasurements;
      final entries = latestEntries;
      if (measurements == null || entries == null) {
        return;
      }

      final history = _measurementHistoryEntriesFromRows(
        measurements,
        entries,
      );
      if (_sameMeasurementHistoryEntries(lastEmitted, history)) {
        return;
      }
      lastEmitted = history;
      controller.add(history);
    }

    controller.onListen = () {
      measurementSubscription = (_curatedMeasurementQuery()
            ..where((row) => row.id.equals(measurementId)))
          .watch()
          .listen(
        (rows) {
          latestMeasurements = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
      entrySubscription = (_activeEntryQuery()
            ..where((row) => row.metricId.equals(measurementId))
            ..orderBy([
              (row) => OrderingTerm.desc(row.atTime),
              (row) => OrderingTerm.desc(row.id),
            ]))
          .watch()
          .listen(
        (rows) {
          latestEntries = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () {
      measurementSubscription.cancel().ignore();
      entrySubscription.cancel().ignore();
    };

    return controller.stream;
  }

  bool _sameMeasurementHistoryEntries(
    List<MeasurementHistoryEntry>? left,
    List<MeasurementHistoryEntry> right,
  ) {
    if (left == null || left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_sameMeasurementHistoryEntry(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _sameMeasurementRecords(
    List<MeasurementRecord>? left,
    List<MeasurementRecord> right,
  ) {
    if (left == null || left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_sameMeasurementRecord(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _sameMeasurementTrackSummaries(
    List<MeasurementTrackSummary>? left,
    List<MeasurementTrackSummary> right,
  ) {
    if (left == null || left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_sameMeasurementTrackSummary(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _sameMeasurementTrackSummary(
    MeasurementTrackSummary left,
    MeasurementTrackSummary right,
  ) {
    return _sameMeasurementRecord(left.measurement, right.measurement) &&
        _sameNullableMeasurementEntryRecord(
          left.latestEntry,
          right.latestEntry,
        ) &&
        _sameNullableMeasurementEntryRecord(
          left.previousEntry,
          right.previousEntry,
        );
  }

  bool _sameMeasurementHistoryEntry(
    MeasurementHistoryEntry left,
    MeasurementHistoryEntry right,
  ) {
    return _sameMeasurementRecord(left.measurement, right.measurement) &&
        _sameMeasurementEntryRecord(left.entry, right.entry) &&
        _sameNullableMeasurementEntryRecord(
          left.previousEntry,
          right.previousEntry,
        );
  }

  bool _sameMeasurementRecord(MeasurementRecord left, MeasurementRecord right) {
    return left.id == right.id &&
        left.name == right.name &&
        left.unit == right.unit &&
        left.goalType == right.goalType &&
        left.targetValue == right.targetValue &&
        left.enabled == right.enabled &&
        left.sortOrder == right.sortOrder &&
        left.updatedAt == right.updatedAt &&
        left.deletedAt == right.deletedAt;
  }

  bool _sameNullableMeasurementRecord(
    MeasurementRecord? left,
    MeasurementRecord? right,
  ) {
    if (identical(left, right)) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    return _sameMeasurementRecord(left, right);
  }

  bool _sameNullableMeasurementEntryRecord(
    MeasurementEntryRecord? left,
    MeasurementEntryRecord? right,
  ) {
    if (identical(left, right)) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    return _sameMeasurementEntryRecord(left, right);
  }

  bool _sameMeasurementIdList(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  bool _sameMeasurementEntryRecord(
    MeasurementEntryRecord left,
    MeasurementEntryRecord right,
  ) {
    return left.id == right.id &&
        left.measurementId == right.measurementId &&
        left.value == right.value &&
        left.valueEntered == right.valueEntered &&
        left.measuredAt == right.measuredAt &&
        left.provenance == right.provenance &&
        left.source == right.source &&
        left.externalId == right.externalId &&
        left.comment == right.comment &&
        left.updatedAt == right.updatedAt &&
        left.deletedAt == right.deletedAt;
  }

  Future<String> createMeasurement(
    MeasurementDraft draft, {
    String actor = 'app',
  }) async {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final activeRows = await _manageableMeasurementQuery().get();
      return _createMeasurementMetric(
        draft.copyWith(
          sortOrder: draft.sortOrder ?? _nextMeasurementSortOrder(activeRows),
        ),
        context,
      );
    });
  }

  Future<void> setMeasurementEnabled(
    String id,
    bool enabled, {
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final before = await _requireActiveMeasurement(id);
      if (before.enabled == enabled) {
        return;
      }

      await (_database.update(_database.metrics)
            ..where((row) => row.id.equals(id)))
          .write(
        MetricsCompanion(
          enabled: Value<bool>(enabled),
          pinned: enabled ? const Value<bool>(true) : const Value.absent(),
          updatedAt: Value<DateTime>(context.timestamp),
        ),
      );
      final after = await _requireMeasurementRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.metricsTable,
        entityId: id,
        beforeImage: _metricImage(before),
        afterImage: _metricImage(after),
      );
    });
  }

  Future<void> reorderMeasurements(
    List<String> orderedIds, {
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final activeRows = await _manageableMeasurementQuery().get();
      final activeById = <String, MetricRow>{
        for (final row in activeRows) row.id: row,
      };
      final nextRows = <MetricRow>[];
      for (final id in orderedIds) {
        final row = activeById.remove(id);
        if (row != null) {
          nextRows.add(row);
        }
      }
      nextRows.addAll(activeById.values);

      for (var index = 0; index < nextRows.length; index += 1) {
        final before = nextRows[index];
        if (before.sortOrder == index) {
          continue;
        }
        await (_database.update(_database.metrics)
              ..where((row) => row.id.equals(before.id)))
            .write(
          MetricsCompanion(
            sortOrder: Value<int>(index),
            updatedAt: Value<DateTime>(context.timestamp),
          ),
        );
        final after = await _requireMeasurementRow(before.id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.metricsTable,
          entityId: before.id,
          beforeImage: _metricImage(before),
          afterImage: _metricImage(after),
        );
      }
    });
  }

  Future<void> resetDefaultMeasurements({
    required MeasurementUnit bodyWeightUnit,
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final activeRows = await _manageableMeasurementQuery().get();
      final rowsByName = <String, MetricRow>{
        for (final row in activeRows) row.name: row,
      };

      await _upsertDefaultMeasurement(
        existing: rowsByName[defaultBodyWeightName],
        draft: MeasurementDraft(
          name: defaultBodyWeightName,
          unit: bodyWeightUnit,
          goalType: MeasurementGoalType.decrease,
          enabled: true,
          sortOrder: 0,
        ),
        context: context,
      );
      await _upsertDefaultMeasurement(
        existing: rowsByName[defaultBodyFatName],
        draft: const MeasurementDraft(
          name: defaultBodyFatName,
          unit: MeasurementUnit.percent,
          goalType: MeasurementGoalType.decrease,
          enabled: true,
          sortOrder: 1,
        ),
        context: context,
      );

      for (final row in activeRows) {
        if (row.name == defaultBodyWeightName ||
            row.name == defaultBodyFatName) {
          continue;
        }
        await _softDeleteMeasurementRow(row, context);
      }
    });
  }

  Future<void> softDeleteMeasurement(
    String id, {
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final before = await _requireActiveMeasurement(id);
      await _softDeleteMeasurementRow(before, context);
    });
  }

  Future<String> createEntry(
    MeasurementEntryDraft draft, {
    String actor = 'app',
  }) async {
    final comment = _normalizeMeasurementComment(draft.comment);

    final measurement = await _requireActiveMeasurement(draft.measurementId);
    final validation = _validateMeasurementEntryValue(
      draft,
      measurement: measurement,
    );
    return _repositories.metrics.createManualReading(
      ManualMetricReadingDraft.scalar(
        metricId: measurement.id,
        valueEntered: validation.valueEntered,
        atTime: draft.measuredAt.toUtc(),
        source: MetricReadingProvenance.manual.name,
        comment: comment,
      ),
      actor: actor,
    );
  }

  Future<void> updateEntry(
    String id,
    MeasurementEntryDraft draft, {
    String actor = 'app',
  }) async {
    final comment = _normalizeMeasurementComment(draft.comment);
    final measurement = await _requireActiveMeasurement(draft.measurementId);
    final validation = _validateMeasurementEntryValue(
      draft,
      measurement: measurement,
    );

    return _repositories.metrics.updateReading(
      id,
      MetricReadingUpdateDraft.scalar(
        metricId: draft.measurementId,
        valueEntered: validation.valueEntered,
        atTime: draft.measuredAt.toUtc(),
        comment: comment,
      ),
      actor: actor,
    );
  }

  Future<void> softDeleteEntry(
    String id, {
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final before = await _requireActiveEntryRow(id);
      await (_database.update(_database.metricReadings)
            ..where((row) => row.id.equals(id)))
          .write(
        MetricReadingsCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireEntryRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.metricReadingsTable,
        entityId: id,
        beforeImage: _metricReadingImage(before),
        afterImage: _metricReadingImage(after),
      );
    });
  }

  Future<MeasurementValueValidation> validateEntry(
    MeasurementEntryDraft draft,
  ) async {
    final measurement = await _requireActiveMeasurement(draft.measurementId);
    return _validateMeasurementEntryValue(draft, measurement: measurement);
  }

  Future<String> _createMeasurementMetric(
    MeasurementDraft draft,
    _WriteContext context,
  ) async {
    final normalized = _normalizeMeasurementDraft(draft);
    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.metrics).insert(
          MetricsCompanion.insert(
            id: id,
            name: normalized.name,
            unit: normalized.unit.name,
            valueShape: MetricValueShape.scalar.name,
            metricGroup: MetricGroup.bodyComposition.name,
            goalType: Value<String?>(normalized.goalType.name),
            goalTargetValue: Value<double?>(normalized.targetValue),
            enabled: Value<bool>(normalized.enabled),
            pinned: const Value<bool>(true),
            sortOrder: normalized.sortOrder!,
            updatedAt: context.timestamp,
          ),
        );
    final after = await _requireMeasurementRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.metricsTable,
      entityId: id,
      beforeImage: null,
      afterImage: _metricImage(after),
    );
    return id;
  }

  Future<void> _upsertDefaultMeasurement({
    required MetricRow? existing,
    required MeasurementDraft draft,
    required _WriteContext context,
  }) async {
    if (existing == null) {
      await _createMeasurementMetric(draft, context);
      return;
    }

    final normalized = _normalizeMeasurementDraft(draft);
    final targetValue = normalized.targetValue;
    final unchanged = existing.name == normalized.name &&
        existing.unit == normalized.unit.name &&
        existing.valueShape == MetricValueShape.scalar.name &&
        existing.metricGroup == MetricGroup.bodyComposition.name &&
        existing.goalType == normalized.goalType.name &&
        existing.goalTargetValue == targetValue &&
        existing.enabled == normalized.enabled &&
        existing.pinned &&
        existing.sortOrder == normalized.sortOrder;
    if (unchanged) {
      return;
    }

    await (_database.update(_database.metrics)
          ..where((row) => row.id.equals(existing.id)))
        .write(
      MetricsCompanion(
        name: Value<String>(normalized.name),
        unit: Value<String>(normalized.unit.name),
        valueShape: Value<String>(MetricValueShape.scalar.name),
        metricGroup: Value<String>(MetricGroup.bodyComposition.name),
        goalType: Value<String?>(normalized.goalType.name),
        goalTargetValue: Value<double?>(targetValue),
        enabled: Value<bool>(normalized.enabled),
        pinned: const Value<bool>(true),
        sortOrder: Value<int>(normalized.sortOrder!),
        updatedAt: Value<DateTime>(context.timestamp),
      ),
    );
    final after = await _requireMeasurementRow(existing.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.metricsTable,
      entityId: existing.id,
      beforeImage: _metricImage(existing),
      afterImage: _metricImage(after),
    );
  }

  Future<void> _softDeleteMeasurementRow(
    MetricRow before,
    _WriteContext context,
  ) async {
    await (_database.update(_database.metrics)
          ..where((row) => row.id.equals(before.id)))
        .write(
      MetricsCompanion(
        updatedAt: Value<DateTime>(context.timestamp),
        deletedAt: Value<DateTime?>(context.timestamp),
      ),
    );
    final after = await _requireMeasurementRow(before.id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.metricsTable,
      entityId: before.id,
      beforeImage: _metricImage(before),
      afterImage: _metricImage(after),
    );
  }

  Future<MetricRow> _requireActiveMeasurement(String id) async {
    final query = _manageableMeasurementQuery()
      ..where((row) => row.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) {
      throw StateError('Measurement not found: $id.');
    }
    return row;
  }

  Future<MetricRow> _requireMeasurementRow(String id) async {
    final row = await (_database.select(_database.metrics)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Measurement not found: $id.');
    }
    return row;
  }

  Future<MetricReadingRow> _requireEntryRow(String id) async {
    final row = await (_database.select(_database.metricReadings)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Measurement entry not found: $id.');
    }
    return row;
  }

  Future<MetricReadingRow> _requireActiveEntryRow(String id) async {
    final row = await (_database.select(_database.metricReadings)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Measurement entry not found: $id.');
    }
    return row;
  }

  SimpleSelectStatement<$MetricsTable, MetricRow>
      _manageableMeasurementQuery() {
    return _database.select(_database.metrics)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.valueShape.equals(MetricValueShape.scalar.name) &
            row.metricGroup.equals(MetricGroup.bodyComposition.name) &
            row.goalType.isNotNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.id),
      ]);
  }

  SimpleSelectStatement<$MetricsTable, MetricRow> _curatedMeasurementQuery() {
    return _manageableMeasurementQuery()
      ..where((row) => row.pinned.equals(true));
  }

  SimpleSelectStatement<$MetricsTable, MetricRow> _enabledMeasurementQuery() {
    return _curatedMeasurementQuery()..where((row) => row.enabled.equals(true));
  }

  SimpleSelectStatement<$MetricReadingsTable, MetricReadingRow>
      _activeEntryQuery() {
    return _database.select(_database.metricReadings)
      ..where((row) => row.deletedAt.isNull());
  }

  SimpleSelectStatement<$MetricReadingsTable, MetricReadingRow>
      _latestEntryRows(String measurementId, {required int limit}) {
    return _database.select(_database.metricReadings)
      ..where(
        (row) => row.deletedAt.isNull() & row.metricId.equals(measurementId),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.atTime),
        (row) => OrderingTerm.desc(row.id),
      ])
      ..limit(limit);
  }

  SimpleSelectStatement<$MetricReadingsTable, MetricReadingRow>
      _activeEntryRowsForMeasurements(List<String> measurementIds) {
    return _database.select(_database.metricReadings)
      ..where(
        (row) => row.deletedAt.isNull() & row.metricId.isIn(measurementIds),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.atTime),
        (row) => OrderingTerm.desc(row.id),
      ]);
  }

  MeasurementValueValidation _validateMeasurementEntryValue(
    MeasurementEntryDraft draft, {
    required MetricRow measurement,
  }) {
    return validateMeasurementValue(
      entered: draft.valueEntered,
      unit: measurement.unit,
    );
  }

  MeasurementDraft _normalizeMeasurementDraft(MeasurementDraft draft) {
    final name = draft.name.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(draft.name, 'name', 'Name is required.');
    }

    final targetValue = validateMeasurementTargetValue(
      goalType: draft.goalType.name,
      targetValue: draft.targetValue,
    );

    return MeasurementDraft(
      name: name,
      unit: draft.unit,
      goalType: draft.goalType,
      targetValue: targetValue,
      enabled: draft.enabled,
      sortOrder: draft.sortOrder,
    );
  }

  int _nextMeasurementSortOrder(List<MetricRow> rows) {
    var next = 0;
    for (final row in rows) {
      if (row.sortOrder >= next) {
        next = row.sortOrder + 1;
      }
    }
    return next;
  }

  MeasurementRecord _measurementRecordFromMetricRow(MetricRow row) {
    return MeasurementRecord(
      id: row.id,
      name: row.name,
      unit: MeasurementUnit.values.byName(row.unit),
      goalType: MeasurementGoalType.values.byName(row.goalType!),
      targetValue: row.goalTargetValue,
      enabled: row.enabled,
      sortOrder: row.sortOrder,
      updatedAt: row.updatedAt.toUtc(),
      deletedAt: row.deletedAt?.toUtc(),
    );
  }

  MeasurementEntryRecord _measurementEntryRecordFromMetricReadingRow(
    MetricReadingRow row,
  ) {
    return MeasurementEntryRecord(
      id: row.id,
      measurementId: row.metricId,
      value: _metricReadingScalarValue(row),
      valueEntered: _metricReadingScalarEntered(row),
      measuredAt: (row.atTime ?? row.windowStartedAt ?? row.updatedAt).toUtc(),
      provenance: MetricReadingProvenance.values.byName(row.provenance),
      source: row.source,
      externalId: row.externalId,
      comment: row.comment,
      updatedAt: row.updatedAt.toUtc(),
      deletedAt: row.deletedAt?.toUtc(),
    );
  }

  double _metricReadingScalarValue(MetricReadingRow row) {
    final scalarValue = row.scalarValue;
    if (scalarValue != null) {
      return scalarValue;
    }
    final decoded = jsonDecode(row.valueJson);
    if (decoded is Map<String, Object?> && decoded['value'] is num) {
      return (decoded['value']! as num).toDouble();
    }
    throw StateError('Metric Reading ${row.id} does not have a scalar value.');
  }

  String _metricReadingScalarEntered(MetricReadingRow row) {
    final scalarEntered = row.scalarEntered;
    if (scalarEntered != null) {
      return scalarEntered;
    }
    final decoded = jsonDecode(row.valueJson);
    if (decoded is Map<String, Object?> && decoded['entered'] is String) {
      return decoded['entered']! as String;
    }
    return _formatMetricReadingScalar(_metricReadingScalarValue(row));
  }

  String _formatMetricReadingScalar(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    var result = value.toString();
    while (result.contains('.') && result.endsWith('0')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}

class MetricRepository {
  const MetricRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  @Deprecated('Demo monitoring seed data is no longer ingested.')
  Future<void> ensureDefaultMonitoringReadings({
    String actor = 'integration-seed',
  }) async {}

  Future<List<MetricRecord>> listActive() async {
    final rows = await _activeMetricQuery().get();
    return rows.map(_metricRecordFromRow).toList(growable: false);
  }

  /// Lists active `Metric` outcome options for picker paths that only need an
  /// id and label. Full `MetricRecord`s remain available to series and detail
  /// reads that need units, groups, goals, or lifecycle metadata.
  Future<List<MetricOptionRecord>> listMetricOptions() async {
    final rows = await _activeMetricQuery().get();
    return _metricOptionsFromRows(rows);
  }

  /// Reactive variant of [listMetricOptions]. It emits only when the visible
  /// option set changes, so unit/goal/enabled edits do not rebuild outcome
  /// pickers that only render Metric identity.
  Stream<List<MetricOptionRecord>> watchMetricOptions() {
    return _activeMetricQuery()
        .watch()
        .map(_metricOptionsFromRows)
        .distinct(_sameMetricOptionRecords);
  }

  Future<List<MetricRecord>> listEnabled() async {
    final rows = await (_database.select(_database.metrics)
          ..where((row) => row.deletedAt.isNull() & row.enabled.equals(true))
          ..orderBy([
            (row) => OrderingTerm.desc(row.pinned),
            (row) => OrderingTerm.asc(row.sortOrder),
            (row) => OrderingTerm.asc(row.name),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
    return rows.map(_metricRecordFromRow).toList(growable: false);
  }

  Future<String> createMetric(
    MetricDraft draft, {
    String actor = 'app',
  }) async {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final activeRows = await _activeMetricQuery().get();
      return _createMetric(
        draft.copyWith(
          sortOrder: draft.sortOrder ?? _nextMetricSortOrder(activeRows),
        ),
        context,
      );
    });
  }

  Future<List<MetricReadingRecord>> listReadings(String metricId) async {
    final rows = await (_database.select(_database.metricReadings)
          ..where(
            (row) => row.deletedAt.isNull() & row.metricId.equals(metricId),
          )
          ..orderBy([
            (row) => OrderingTerm.desc(row.atTime),
            (row) => OrderingTerm.desc(row.windowStartedAt),
            (row) => OrderingTerm.desc(row.id),
          ]))
        .get();
    return rows.map(_metricReadingRecordFromRow).toList(growable: false);
  }

  /// The first enabled `Metric` whose name matches [name], or `null`.
  ///
  /// A read-only lookup used by the trends surface to resolve a `Metric` series
  /// family (e.g. calories burned) to read alongside the derived nutrition
  /// analytics. The two families stay distinct stores: this only reads the
  /// Metric domain (NUTRITION.md §2, "join, never merge").
  Future<MetricRecord?> findEnabledMetricByName(String name) async {
    final row = await (_database.select(_database.metrics)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.enabled.equals(true) &
                row.name.equals(name),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.sortOrder),
            (row) => OrderingTerm.asc(row.id),
          ])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _metricRecordFromRow(row);
  }

  /// A read-only `Metric` series: the metric and its active `Reading`s,
  /// optionally scoped to the `[from, to]` window. Returns `null` when the
  /// metric is unknown.
  ///
  /// This is a pure read off the Metric store — the stored, provenance-stamped
  /// signals. It performs no writes and exposes no recalculate path;
  /// the trends surface joins it with the derived nutrition analytics only at
  /// display time, never merging the two into a shared series table.
  Future<MetricSeriesData?> metricSeries(
    String metricId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final metricRow = await (_database.select(_database.metrics)
          ..where((row) => row.id.equals(metricId) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (metricRow == null) {
      return null;
    }
    final readings = await _metricSeriesReadingRows(
      metricId,
      from: from,
      to: to,
    ).get();
    return MetricSeriesData(
      metric: _metricRecordFromRow(metricRow),
      readings:
          readings.map(_metricReadingRecordFromRow).toList(growable: false),
    );
  }

  /// Reactive [metricSeries] — re-emits when the metric or its Readings change.
  Stream<MetricSeriesData?> watchMetricSeries(
    String metricId, {
    DateTime? from,
    DateTime? to,
  }) {
    late final StreamSubscription<List<MetricRow>> metricSubscription;
    late final StreamSubscription<List<MetricReadingRow>> readingSubscription;
    final controller = StreamController<MetricSeriesData?>();
    List<MetricRow>? latestMetrics;
    List<MetricReadingRow>? latestReadings;
    MetricSeriesData? lastEmitted;
    var emittedNull = false;

    void addIfChanged(MetricSeriesData? series) {
      if (series == null) {
        if (emittedNull && lastEmitted == null) {
          return;
        }
        emittedNull = true;
        lastEmitted = null;
        controller.add(null);
        return;
      }

      if (_sameMetricSeriesData(lastEmitted, series)) {
        return;
      }
      emittedNull = false;
      lastEmitted = series;
      controller.add(series);
    }

    void emitIfReady() {
      final metrics = latestMetrics;
      final readings = latestReadings;
      if (metrics == null || readings == null) {
        return;
      }
      if (metrics.isEmpty) {
        addIfChanged(null);
        return;
      }

      addIfChanged(
        MetricSeriesData(
          metric: _metricRecordFromRow(metrics.single),
          readings:
              readings.map(_metricReadingRecordFromRow).toList(growable: false),
        ),
      );
    }

    controller.onListen = () {
      metricSubscription = (_database.select(_database.metrics)
            ..where((row) => row.id.equals(metricId) & row.deletedAt.isNull()))
          .watch()
          .listen(
        (rows) {
          latestMetrics = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
      readingSubscription = _metricSeriesReadingRows(
        metricId,
        from: from,
        to: to,
      ).watch().listen(
        (rows) {
          latestReadings = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () {
      metricSubscription.cancel().ignore();
      readingSubscription.cancel().ignore();
    };

    return controller.stream;
  }

  /// Reactive lookup for one enabled monitoring `Metric` series by name.
  ///
  /// This is narrower than [watchEnabledMetricSeries]: callers that need one
  /// well-known tracker signal, such as calories burned for energy balance, do
  /// not subscribe to every enabled monitoring metric in the window.
  Stream<MetricSeriesData?> watchMonitoringMetricSeriesByName(
    String name, {
    DateTime? from,
    DateTime? to,
  }) {
    late final StreamSubscription<List<MetricRow>> metricSubscription;
    StreamSubscription<List<MetricReadingRow>>? readingSubscription;
    final controller = StreamController<MetricSeriesData?>();
    MetricRow? latestMetric;
    List<MetricReadingRow>? latestReadings;
    String? watchedMetricId;
    MetricSeriesData? lastEmitted;
    var emittedNull = false;

    void addIfChanged(MetricSeriesData? series) {
      if (series == null) {
        if (emittedNull && lastEmitted == null) {
          return;
        }
        emittedNull = true;
        lastEmitted = null;
        controller.add(null);
        return;
      }

      if (_sameMetricSeriesData(lastEmitted, series)) {
        return;
      }
      emittedNull = false;
      lastEmitted = series;
      controller.add(series);
    }

    void emitIfReady() {
      final metric = latestMetric;
      if (metric == null) {
        addIfChanged(null);
        return;
      }
      final readings = latestReadings;
      if (readings == null) {
        return;
      }

      addIfChanged(
        MetricSeriesData(
          metric: _metricRecordFromRow(metric),
          readings:
              readings.map(_metricReadingRecordFromRow).toList(growable: false),
        ),
      );
    }

    void watchReadingsFor(MetricRow? metric) {
      final metricId = metric?.id;
      if (watchedMetricId == metricId) {
        emitIfReady();
        return;
      }

      watchedMetricId = metricId;
      latestReadings = null;
      readingSubscription?.cancel().ignore();
      readingSubscription = null;
      if (metricId == null) {
        latestReadings = const <MetricReadingRow>[];
        emitIfReady();
        return;
      }

      readingSubscription = _metricSeriesReadingRows(
        metricId,
        from: from,
        to: to,
      ).watch().listen(
        (rows) {
          latestReadings = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    }

    controller.onListen = () {
      metricSubscription = _monitoringMetricByNameQuery(name).watch().listen(
        (rows) {
          latestMetric = rows.isEmpty ? null : rows.first;
          watchReadingsFor(latestMetric);
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () {
      metricSubscription.cancel().ignore();
      readingSubscription?.cancel().ignore();
    };

    return controller.stream;
  }

  SimpleSelectStatement<$MetricReadingsTable, MetricReadingRow>
      _metricSeriesReadingRows(
    String metricId, {
    DateTime? from,
    DateTime? to,
  }) {
    final query = _database.select(_database.metricReadings)
      ..where(
        (row) => row.deletedAt.isNull() & row.metricId.equals(metricId),
      );
    if (from != null) {
      query.where(
        (row) =>
            row.atTime.isBiggerOrEqualValue(from) |
            row.windowEndedAt.isBiggerOrEqualValue(from),
      );
    }
    if (to != null) {
      query.where(
        (row) =>
            row.atTime.isSmallerThanValue(to) |
            row.windowStartedAt.isSmallerThanValue(to),
      );
    }
    return query
      ..orderBy([
        (row) => OrderingTerm.asc(row.atTime),
        (row) => OrderingTerm.asc(row.windowEndedAt),
        (row) => OrderingTerm.asc(row.id),
      ]);
  }

  SimpleSelectStatement<$MetricReadingsTable, MetricReadingRow>
      _enabledMetricSeriesReadingRows(
    List<String> metricIds, {
    DateTime? from,
    DateTime? to,
  }) {
    final query = _database.select(_database.metricReadings)
      ..where(
        (row) => row.deletedAt.isNull() & row.metricId.isIn(metricIds),
      );
    if (from != null) {
      query.where(
        (row) =>
            row.atTime.isBiggerOrEqualValue(from) |
            row.windowEndedAt.isBiggerOrEqualValue(from),
      );
    }
    if (to != null) {
      query.where(
        (row) =>
            row.atTime.isSmallerThanValue(to) |
            row.windowStartedAt.isSmallerThanValue(to),
      );
    }
    return query
      ..orderBy([
        (row) => OrderingTerm.asc(row.metricId),
        (row) => OrderingTerm.asc(row.atTime),
        (row) => OrderingTerm.asc(row.windowEndedAt),
        (row) => OrderingTerm.asc(row.id),
      ]);
  }

  Future<List<MonitoringMetricSummary>> listMonitoringSummaries() async {
    final metricRows = await _monitoringMetricQuery().get();
    final readingRowsByMetricId = await _latestReadingRowsByMetricId(
      metricRows,
    );
    return _monitoringSummariesFromRows(metricRows, readingRowsByMetricId);
  }

  Future<List<MetricSummary>> listMetricSummaries() async {
    final metricRows = await _activeMetricQuery().get();
    final readingRowsByMetricId = await _latestReadingRowsByMetricId(
      metricRows,
    );
    return _metricSummariesFromRows(metricRows, readingRowsByMetricId);
  }

  Stream<List<MonitoringMetricSummary>> watchMonitoringSummaries() {
    return _watchMetricSummaryRows<MonitoringMetricSummary>(
      metricQuery: _monitoringMetricQuery,
      buildSummaries: _monitoringSummariesFromRows,
      sameSummaries: _sameMonitoringMetricSummaries,
    );
  }

  Stream<List<MetricSummary>> watchMetricSummaries() {
    return _watchMetricSummaryRows<MetricSummary>(
      metricQuery: _activeMetricQuery,
      buildSummaries: _metricSummariesFromRows,
      sameSummaries: _sameMetricSummaries,
    );
  }

  Future<Map<String, List<MetricReadingRow>>> _latestReadingRowsByMetricId(
    List<MetricRow> metricRows,
  ) async {
    final readingsByMetricId = <String, List<MetricReadingRow>>{};
    for (final metricRow in metricRows) {
      final readingRows = await _latestMetricReadingRows(
        metricRow.id,
        limit: 2,
      ).get();
      readingsByMetricId[metricRow.id] = List<MetricReadingRow>.unmodifiable(
        readingRows,
      );
    }
    return Map<String, List<MetricReadingRow>>.unmodifiable(
      readingsByMetricId,
    );
  }

  Stream<List<TSummary>> _watchMetricSummaryRows<TSummary>({
    required SimpleSelectStatement<$MetricsTable, MetricRow> Function()
        metricQuery,
    required List<TSummary> Function(
      List<MetricRow> metricRows,
      Map<String, List<MetricReadingRow>> readingRowsByMetricId,
    ) buildSummaries,
    required bool Function(List<TSummary>? left, List<TSummary> right)
        sameSummaries,
  }) {
    late final StreamSubscription<List<MetricRow>> metricSubscription;
    final readingSubscriptions =
        <String, StreamSubscription<List<MetricReadingRow>>>{};
    final readingRowsByMetricId = <String, List<MetricReadingRow>>{};
    final controller = StreamController<List<TSummary>>();
    List<MetricRow>? latestMetrics;
    List<String> watchedMetricIds = const <String>[];
    List<TSummary>? lastEmitted;

    void addIfChanged(List<TSummary> summaries) {
      if (sameSummaries(lastEmitted, summaries)) {
        return;
      }
      lastEmitted = summaries;
      controller.add(summaries);
    }

    bool readingsReadyFor(List<String> metricIds) {
      for (final metricId in metricIds) {
        if (!readingRowsByMetricId.containsKey(metricId)) {
          return false;
        }
      }
      return true;
    }

    void emitIfReady() {
      final metricRows = latestMetrics;
      if (metricRows == null || !readingsReadyFor(watchedMetricIds)) {
        return;
      }

      addIfChanged(buildSummaries(metricRows, readingRowsByMetricId));
    }

    void watchReadingsFor(List<MetricRow> metricRows) {
      final metricIds = metricRows.map((row) => row.id).toList(growable: false);
      if (_sameStringList(watchedMetricIds, metricIds)) {
        emitIfReady();
        return;
      }

      final metricIdSet = metricIds.toSet();
      for (final metricId in readingSubscriptions.keys.toList()) {
        if (metricIdSet.contains(metricId)) {
          continue;
        }
        readingSubscriptions.remove(metricId)?.cancel().ignore();
        readingRowsByMetricId.remove(metricId);
      }

      watchedMetricIds = metricIds;
      if (metricIds.isEmpty) {
        emitIfReady();
        return;
      }

      for (final metricId in metricIds) {
        if (readingSubscriptions.containsKey(metricId)) {
          continue;
        }
        readingRowsByMetricId.remove(metricId);
        readingSubscriptions[metricId] = _latestMetricReadingRows(
          metricId,
          limit: 2,
        ).watch().listen(
          (rows) {
            readingRowsByMetricId[metricId] =
                List<MetricReadingRow>.unmodifiable(rows);
            emitIfReady();
          },
          onError: controller.addError,
        );
      }
      emitIfReady();
    }

    controller.onListen = () {
      metricSubscription = metricQuery().watch().listen(
        (rows) {
          latestMetrics = rows;
          watchReadingsFor(rows);
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () {
      metricSubscription.cancel().ignore();
      for (final subscription in readingSubscriptions.values) {
        subscription.cancel().ignore();
      }
    };

    return controller.stream;
  }

  /// Every enabled monitoring `Metric` as a read-only series scoped to the
  /// `[from, to)` window. Read-only; the Metric family the trends surface shows
  /// alongside the derived nutrition analytics (NUTRITION.md §2).
  Future<List<MetricSeriesData>> listEnabledMetricSeries({
    DateTime? from,
    DateTime? to,
  }) async {
    final metricRows = await _monitoringMetricQuery().get();
    final series = <MetricSeriesData>[];
    for (final metricRow in metricRows) {
      final readings = await _metricSeriesReadingRows(
        metricRow.id,
        from: from,
        to: to,
      ).get();
      series.add(
        MetricSeriesData(
          metric: _metricRecordFromRow(metricRow),
          readings:
              readings.map(_metricReadingRecordFromRow).toList(growable: false),
        ),
      );
    }
    return List<MetricSeriesData>.unmodifiable(series);
  }

  /// Reactive [listEnabledMetricSeries] — re-emits when a metric or Reading
  /// changes. Purely a read off the Metric store; no writes.
  Stream<List<MetricSeriesData>> watchEnabledMetricSeries({
    DateTime? from,
    DateTime? to,
  }) {
    late final StreamSubscription<List<MetricRow>> metricSubscription;
    StreamSubscription<List<MetricReadingRow>>? readingSubscription;
    final controller = StreamController<List<MetricSeriesData>>();
    List<MetricRow>? latestMetrics;
    List<MetricReadingRow>? latestReadings;
    List<String> watchedMetricIds = const <String>[];
    List<MetricSeriesData>? lastEmitted;

    void addIfChanged(List<MetricSeriesData> series) {
      if (_sameMetricSeriesDataList(lastEmitted, series)) {
        return;
      }
      lastEmitted = series;
      controller.add(series);
    }

    void emitIfReady() {
      final metricRows = latestMetrics;
      final readingRows = latestReadings;
      if (metricRows == null || readingRows == null) {
        return;
      }

      addIfChanged(_metricSeriesDataListFromRows(metricRows, readingRows));
    }

    void watchReadingsFor(List<MetricRow> metricRows) {
      final metricIds = metricRows.map((row) => row.id).toList(growable: false);
      if (_sameStringList(watchedMetricIds, metricIds)) {
        emitIfReady();
        return;
      }

      watchedMetricIds = metricIds;
      latestReadings = null;
      readingSubscription?.cancel().ignore();
      readingSubscription = null;
      if (metricIds.isEmpty) {
        latestReadings = const <MetricReadingRow>[];
        emitIfReady();
        return;
      }

      readingSubscription = _enabledMetricSeriesReadingRows(
        metricIds,
        from: from,
        to: to,
      ).watch().listen(
        (rows) {
          latestReadings = rows;
          emitIfReady();
        },
        onError: controller.addError,
      );
    }

    controller.onListen = () {
      metricSubscription = _monitoringMetricQuery().watch().listen(
        (rows) {
          latestMetrics = rows;
          watchReadingsFor(rows);
        },
        onError: controller.addError,
      );
    };
    controller.onCancel = () {
      metricSubscription.cancel().ignore();
      readingSubscription?.cancel().ignore();
    };

    return controller.stream;
  }

  Future<void> applySyncImage({
    required String entityTable,
    required Map<String, Object?> image,
    required String deviceId,
    required String batchId,
    String actor = 'sync',
    String? activityLogId,
    Map<String, Object?>? activityBeforeImage,
    Map<String, Object?>? activityAfterImage,
    DateTime? activityOccurredAt,
  }) {
    if (entityTable != AppDatabase.metricsTable &&
        entityTable != AppDatabase.metricReadingsTable) {
      throw ArgumentError.value(
        entityTable,
        'entityTable',
        'Unsupported metric sync entity.',
      );
    }
    final context = _repositories._createWriteContext(
      actor: actor,
      batchId: batchId,
    );

    return _database.transaction(() async {
      final id = _activityRequiredString(image, 'id');
      final localBeforeImage = await _metricSyncImageFor(
        entityTable: entityTable,
        entityId: id,
      );

      switch (entityTable) {
        case AppDatabase.metricsTable:
          await _database.into(_database.metrics).insertOnConflictUpdate(
                _metricSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
        case AppDatabase.metricReadingsTable:
          await _database.into(_database.metricReadings).insertOnConflictUpdate(
                _metricReadingSyncCompanionFromImage(
                  image,
                  syncDeviceId: deviceId,
                ),
              );
      }

      final localAfterImage = await _metricSyncImageFor(
        entityTable: entityTable,
        entityId: id,
      );
      if (localAfterImage == null ||
          (localBeforeImage != null &&
              _activityImagesEqual(localBeforeImage, localAfterImage))) {
        return;
      }

      await _repositories.activityLog._append(
        context,
        entityTable: entityTable,
        entityId: id,
        beforeImage: activityBeforeImage ?? localBeforeImage,
        afterImage: activityAfterImage ?? localAfterImage,
        id: activityLogId,
        occurredAt: activityOccurredAt,
        syncAcknowledgedAt: context.timestamp,
      );
    });
  }

  Future<String> createManualReading(
    ManualMetricReadingDraft draft, {
    String actor = 'app',
  }) async {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final metric = await _requireActiveMetric(draft.metricId);
      final normalized = _normalizeManualReadingDraft(draft, metric: metric);
      final id = _repositories.createId(context.timestamp);
      await _database.into(_database.metricReadings).insert(
            MetricReadingsCompanion.insert(
              id: id,
              metricId: metric.id,
              valueJson: normalized.valueJson,
              scalarValue: Value<double?>(normalized.scalarValue),
              scalarEntered: Value<String?>(normalized.scalarEntered),
              atTime: Value<DateTime?>(normalized.atTime),
              windowStartedAt: Value<DateTime?>(
                normalized.windowStartedAt,
              ),
              windowEndedAt: Value<DateTime?>(normalized.windowEndedAt),
              provenance: MetricReadingProvenance.manual.name,
              source: normalized.source,
              externalId: Value<String?>(normalized.externalId),
              comment: Value<String?>(normalized.comment),
              updatedAt: context.timestamp,
            ),
          );
      final after = await _requireReadingRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.metricReadingsTable,
        entityId: id,
        beforeImage: null,
        afterImage: _metricReadingImage(after),
      );
      return id;
    });
  }

  Future<void> updateReading(
    String id,
    MetricReadingUpdateDraft draft, {
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final before = await _requireActiveReadingRow(id);
      final provenance = MetricReadingProvenance.values.byName(
        before.provenance,
      );
      if (provenance == MetricReadingProvenance.integration) {
        throw StateError(
          'Integration Metric Readings are immutable; delete and add a '
          'manual Reading to override: $id.',
        );
      }
      if (before.metricId != draft.metricId) {
        throw StateError('Metric Reading cannot change Metric.');
      }
      final metric = await _requireActiveMetric(draft.metricId);
      final normalized = _normalizeMetricReadingUpdateDraft(
        draft,
        metric: metric,
      );
      await _writeMetricReadingValues(
        id,
        normalized,
        updatedAt: context.timestamp,
      );
      final after = await _requireReadingRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.metricReadingsTable,
        entityId: id,
        beforeImage: _metricReadingImage(before),
        afterImage: _metricReadingImage(after),
      );
    });
  }

  Future<List<String>> upsertIntegrationReadings(
    List<IntegrationMetricReadingDraft> drafts, {
    String actor = 'integration',
  }) {
    if (drafts.isEmpty) {
      return Future<List<String>>.value(const <String>[]);
    }
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final ids = <String>[];
      for (final draft in drafts) {
        final metric = await _requireActiveMetric(draft.metricId);
        final normalized = _normalizeIntegrationReadingDraft(
          draft,
          metric: metric,
        );
        final existing = await _findIntegrationReadingByImportKey(
          source: normalized.source,
          externalId: normalized.externalId!,
        );
        if (existing != null) {
          ids.add(existing.id);
          if (existing.deletedAt != null) {
            continue;
          }
          await _writeMetricReadingValues(
            existing.id,
            normalized,
            metricId: metric.id,
            provenance: MetricReadingProvenance.integration,
            source: normalized.source,
            externalId: normalized.externalId,
            updatedAt: context.timestamp,
          );
          final after = await _requireReadingRow(existing.id);
          await _repositories.activityLog._append(
            context,
            entityTable: AppDatabase.metricReadingsTable,
            entityId: existing.id,
            beforeImage: _metricReadingImage(existing),
            afterImage: _metricReadingImage(after),
          );
          continue;
        }

        final id = _repositories.createId(context.timestamp);
        await _database.into(_database.metricReadings).insert(
              MetricReadingsCompanion.insert(
                id: id,
                metricId: metric.id,
                valueJson: normalized.valueJson,
                scalarValue: Value<double?>(normalized.scalarValue),
                scalarEntered: Value<String?>(normalized.scalarEntered),
                atTime: Value<DateTime?>(normalized.atTime),
                windowStartedAt: Value<DateTime?>(
                  normalized.windowStartedAt,
                ),
                windowEndedAt: Value<DateTime?>(normalized.windowEndedAt),
                provenance: MetricReadingProvenance.integration.name,
                source: normalized.source,
                externalId: Value<String?>(normalized.externalId),
                comment: Value<String?>(normalized.comment),
                updatedAt: context.timestamp,
              ),
            );
        final after = await _requireReadingRow(id);
        await _repositories.activityLog._append(
          context,
          entityTable: AppDatabase.metricReadingsTable,
          entityId: id,
          beforeImage: null,
          afterImage: _metricReadingImage(after),
        );
        ids.add(id);
      }
      return List<String>.unmodifiable(ids);
    });
  }

  Future<void> softDeleteReading(
    String id, {
    String actor = 'app',
  }) {
    final context = _repositories._createWriteContext(actor: actor);

    return _database.transaction(() async {
      final before = await _requireActiveReadingRow(id);
      await (_database.update(_database.metricReadings)
            ..where((row) => row.id.equals(id)))
          .write(
        MetricReadingsCompanion(
          updatedAt: Value<DateTime>(context.timestamp),
          deletedAt: Value<DateTime?>(context.timestamp),
        ),
      );
      final after = await _requireReadingRow(id);
      await _repositories.activityLog._append(
        context,
        entityTable: AppDatabase.metricReadingsTable,
        entityId: id,
        beforeImage: _metricReadingImage(before),
        afterImage: _metricReadingImage(after),
      );
    });
  }

  Future<String> _createMetric(
    MetricDraft draft,
    _WriteContext context,
  ) async {
    final normalized = _normalizeMetricDraft(draft);
    final id = _repositories.createId(context.timestamp);
    await _database.into(_database.metrics).insert(
          MetricsCompanion.insert(
            id: id,
            name: normalized.name,
            unit: normalized.unit,
            valueShape: normalized.valueShape.name,
            metricGroup: normalized.group.name,
            goalType: Value<String?>(normalized.goalType?.name),
            goalTargetValue: Value<double?>(normalized.goalTargetValue),
            enabled: Value<bool>(normalized.enabled),
            pinned: Value<bool>(normalized.pinned),
            sortOrder: normalized.sortOrder!,
            updatedAt: context.timestamp,
          ),
        );
    final after = await _requireMetricRow(id);
    await _repositories.activityLog._append(
      context,
      entityTable: AppDatabase.metricsTable,
      entityId: id,
      beforeImage: null,
      afterImage: _metricImage(after),
    );
    return id;
  }

  Future<MetricRow> _requireActiveMetric(String id) async {
    final row = await (_database.select(_database.metrics)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Metric not found: $id.');
    }
    return row;
  }

  Future<MetricRow> _requireMetricRow(String id) async {
    final row = await (_database.select(_database.metrics)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Metric not found: $id.');
    }
    return row;
  }

  Future<MetricReadingRow> _requireReadingRow(String id) async {
    final row = await (_database.select(_database.metricReadings)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Metric Reading not found: $id.');
    }
    return row;
  }

  Future<MetricReadingRow> _requireActiveReadingRow(String id) async {
    final row = await (_database.select(_database.metricReadings)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Metric Reading not found: $id.');
    }
    return row;
  }

  Future<MetricReadingRow?> _findIntegrationReadingByImportKey({
    required String source,
    required String externalId,
  }) async {
    final rows = await (_database.select(_database.metricReadings)
          ..where(
            (row) =>
                row.provenance
                    .equals(MetricReadingProvenance.integration.name) &
                row.source.equals(source) &
                row.externalId.equals(externalId),
          )
          ..orderBy([
            (row) => OrderingTerm.desc(row.updatedAt),
            (row) => OrderingTerm.desc(row.id),
          ]))
        .get();
    if (rows.isEmpty) {
      return null;
    }
    for (final row in rows) {
      if (row.deletedAt != null) {
        return row;
      }
    }
    return rows.first;
  }

  Future<void> _writeMetricReadingValues(
    String id,
    _NormalizedMetricReadingValues normalized, {
    required DateTime updatedAt,
    String? metricId,
    MetricReadingProvenance? provenance,
    String? source,
    String? externalId,
  }) {
    return (_database.update(_database.metricReadings)
          ..where((row) => row.id.equals(id)))
        .write(
      MetricReadingsCompanion(
        metricId:
            metricId == null ? const Value<String>.absent() : Value(metricId),
        valueJson: Value<String>(normalized.valueJson),
        scalarValue: Value<double?>(normalized.scalarValue),
        scalarEntered: Value<String?>(normalized.scalarEntered),
        atTime: Value<DateTime?>(normalized.atTime),
        windowStartedAt: Value<DateTime?>(normalized.windowStartedAt),
        windowEndedAt: Value<DateTime?>(normalized.windowEndedAt),
        provenance: provenance == null
            ? const Value<String>.absent()
            : Value(provenance.name),
        source: source == null ? const Value<String>.absent() : Value(source),
        externalId: externalId == null
            ? const Value<String?>.absent()
            : Value<String?>(externalId),
        comment: Value<String?>(normalized.comment),
        updatedAt: Value<DateTime>(updatedAt),
      ),
    );
  }

  SimpleSelectStatement<$MetricsTable, MetricRow> _activeMetricQuery() {
    return _database.select(_database.metrics)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.desc(row.pinned),
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.id),
      ]);
  }

  SimpleSelectStatement<$MetricsTable, MetricRow> _monitoringMetricQuery() {
    return _database.select(_database.metrics)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.enabled.equals(true) &
            row.valueShape.equals(MetricValueShape.scalar.name) &
            row.metricGroup.equals(MetricGroup.monitoring.name),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.id),
      ]);
  }

  SimpleSelectStatement<$MetricsTable, MetricRow> _monitoringMetricByNameQuery(
    String name,
  ) {
    return _database.select(_database.metrics)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.enabled.equals(true) &
            row.valueShape.equals(MetricValueShape.scalar.name) &
            row.metricGroup.equals(MetricGroup.monitoring.name) &
            row.name.equals(name),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
        (row) => OrderingTerm.asc(row.id),
      ])
      ..limit(1);
  }

  Future<Map<String, Object?>?> _metricSyncImageFor({
    required String entityTable,
    required String entityId,
  }) async {
    switch (entityTable) {
      case AppDatabase.metricsTable:
        final row = await (_database.select(_database.metrics)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _metricImage(row);
      case AppDatabase.metricReadingsTable:
        final row = await (_database.select(_database.metricReadings)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _metricReadingImage(row);
      default:
        return null;
    }
  }

  SimpleSelectStatement<$MetricReadingsTable, MetricReadingRow>
      _latestMetricReadingRows(
    String metricId, {
    required int limit,
  }) {
    return _database.select(_database.metricReadings)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.metricId.equals(metricId) &
            (row.atTime.isNotNull() |
                (row.windowStartedAt.isNotNull() &
                    row.windowEndedAt.isNotNull())),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.atTime),
        (row) => OrderingTerm.desc(row.windowEndedAt),
        (row) => OrderingTerm.desc(row.id),
      ])
      ..limit(limit);
  }

  List<MonitoringMetricSummary> _monitoringSummariesFromRows(
    List<MetricRow> metricRows,
    Map<String, List<MetricReadingRow>> readingRowsByMetricId,
  ) {
    final summaries = <MonitoringMetricSummary>[];
    for (final metricRow in metricRows) {
      final readingRows =
          readingRowsByMetricId[metricRow.id] ?? const <MetricReadingRow>[];
      if (readingRows.isEmpty) {
        continue;
      }

      summaries.add(
        MonitoringMetricSummary(
          metric: _metricRecordFromRow(metricRow),
          latestReading: _metricReadingRecordFromRow(readingRows.first),
          previousReading: readingRows.length < 2
              ? null
              : _metricReadingRecordFromRow(readingRows[1]),
        ),
      );
    }
    return List<MonitoringMetricSummary>.unmodifiable(summaries);
  }

  List<MetricSummary> _metricSummariesFromRows(
    List<MetricRow> metricRows,
    Map<String, List<MetricReadingRow>> readingRowsByMetricId,
  ) {
    return List<MetricSummary>.unmodifiable(
      metricRows.map((metricRow) {
        final readingRows =
            readingRowsByMetricId[metricRow.id] ?? const <MetricReadingRow>[];
        return MetricSummary(
          metric: _metricRecordFromRow(metricRow),
          latestReading: readingRows.isEmpty
              ? null
              : _metricReadingRecordFromRow(readingRows.first),
          previousReading: readingRows.length < 2
              ? null
              : _metricReadingRecordFromRow(readingRows[1]),
        );
      }),
    );
  }

  List<MetricOptionRecord> _metricOptionsFromRows(List<MetricRow> rows) {
    return rows.map(_metricOptionFromRow).toList(growable: false);
  }

  MetricOptionRecord _metricOptionFromRow(MetricRow row) {
    return MetricOptionRecord(id: row.id, name: row.name);
  }

  bool _sameMetricOptionRecords(
    List<MetricOptionRecord>? left,
    List<MetricOptionRecord> right,
  ) {
    if (left == null || left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_sameMetricOptionRecord(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _sameMetricOptionRecord(
    MetricOptionRecord left,
    MetricOptionRecord right,
  ) {
    return left.id == right.id && left.name == right.name;
  }

  bool _sameMetricSummaries(
    List<MetricSummary>? left,
    List<MetricSummary> right,
  ) {
    if (left == null || left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_sameMetricSummary(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _sameMetricSummary(MetricSummary left, MetricSummary right) {
    return _sameMetricRecord(left.metric, right.metric) &&
        _sameNullableMetricReadingRecord(
          left.latestReading,
          right.latestReading,
        ) &&
        _sameNullableMetricReadingRecord(
          left.previousReading,
          right.previousReading,
        );
  }

  bool _sameMonitoringMetricSummaries(
    List<MonitoringMetricSummary>? left,
    List<MonitoringMetricSummary> right,
  ) {
    if (left == null || left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_sameMonitoringMetricSummary(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _sameMonitoringMetricSummary(
    MonitoringMetricSummary left,
    MonitoringMetricSummary right,
  ) {
    return _sameMetricRecord(left.metric, right.metric) &&
        _sameMetricReadingRecord(left.latestReading, right.latestReading) &&
        _sameNullableMetricReadingRecord(
          left.previousReading,
          right.previousReading,
        );
  }

  bool _sameNullableMetricReadingRecord(
    MetricReadingRecord? left,
    MetricReadingRecord? right,
  ) {
    if (identical(left, right)) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    return _sameMetricReadingRecord(left, right);
  }

  bool _sameMetricSeriesData(
    MetricSeriesData? left,
    MetricSeriesData? right,
  ) {
    if (identical(left, right)) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    return _sameMetricRecord(left.metric, right.metric) &&
        _sameMetricReadingRecords(left.readings, right.readings);
  }

  bool _sameMetricRecord(MetricRecord left, MetricRecord right) {
    return left.id == right.id &&
        left.name == right.name &&
        left.unit == right.unit &&
        left.valueShape == right.valueShape &&
        left.group == right.group &&
        left.goalType == right.goalType &&
        left.goalTargetValue == right.goalTargetValue &&
        left.enabled == right.enabled &&
        left.pinned == right.pinned &&
        left.sortOrder == right.sortOrder &&
        left.updatedAt == right.updatedAt &&
        left.deletedAt == right.deletedAt;
  }

  bool _sameMetricReadingRecords(
    List<MetricReadingRecord> left,
    List<MetricReadingRecord> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_sameMetricReadingRecord(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _sameMetricReadingRecord(
    MetricReadingRecord left,
    MetricReadingRecord right,
  ) {
    return left.id == right.id &&
        left.metricId == right.metricId &&
        left.valueJson == right.valueJson &&
        left.scalarValue == right.scalarValue &&
        left.scalarEntered == right.scalarEntered &&
        left.atTime == right.atTime &&
        left.windowStartedAt == right.windowStartedAt &&
        left.windowEndedAt == right.windowEndedAt &&
        left.provenance == right.provenance &&
        left.source == right.source &&
        left.externalId == right.externalId &&
        left.comment == right.comment &&
        left.updatedAt == right.updatedAt &&
        left.deletedAt == right.deletedAt;
  }

  List<MetricSeriesData> _metricSeriesDataListFromRows(
    List<MetricRow> metricRows,
    List<MetricReadingRow> readingRows,
  ) {
    final readingsByMetricId = <String, List<MetricReadingRecord>>{};
    for (final row in readingRows) {
      readingsByMetricId
          .putIfAbsent(row.metricId, () => <MetricReadingRecord>[])
          .add(_metricReadingRecordFromRow(row));
    }

    return List<MetricSeriesData>.unmodifiable(
      metricRows.map((metricRow) {
        return MetricSeriesData(
          metric: _metricRecordFromRow(metricRow),
          readings: List<MetricReadingRecord>.unmodifiable(
            readingsByMetricId[metricRow.id] ?? const <MetricReadingRecord>[],
          ),
        );
      }),
    );
  }

  bool _sameMetricSeriesDataList(
    List<MetricSeriesData>? left,
    List<MetricSeriesData> right,
  ) {
    if (left == null || left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_sameMetricSeriesData(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  MetricDraft _normalizeMetricDraft(MetricDraft draft) {
    final name = draft.name.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(draft.name, 'name', 'Name is required.');
    }
    final unit = draft.unit.trim();
    if (unit.isEmpty) {
      throw ArgumentError.value(draft.unit, 'unit', 'Unit is required.');
    }
    final targetValue = draft.goalTargetValue;
    if (targetValue != null && !targetValue.isFinite) {
      throw ArgumentError.value(
        targetValue,
        'goalTargetValue',
        'Goal target value must be finite.',
      );
    }
    return MetricDraft(
      name: name,
      unit: unit,
      valueShape: draft.valueShape,
      group: draft.group,
      goalType: draft.goalType,
      goalTargetValue: targetValue,
      enabled: draft.enabled,
      pinned: draft.pinned,
      sortOrder: draft.sortOrder,
    );
  }

  _NormalizedMetricReadingDraft _normalizeManualReadingDraft(
    ManualMetricReadingDraft draft, {
    required MetricRow metric,
  }) {
    final source = draft.source.trim();
    if (source.isEmpty) {
      throw ArgumentError.value(draft.source, 'source', 'Source is required.');
    }
    final externalId = _normalizeOptionalText(draft.externalId);
    final values = _normalizeMetricReadingValues(
      valueEntered: draft.valueEntered,
      atTime: draft.atTime,
      windowStartedAt: draft.windowStartedAt,
      windowEndedAt: draft.windowEndedAt,
      comment: draft.comment,
      metric: metric,
      shapeErrorMessage:
          'Manual scalar Reading requires a scalar Metric: ${metric.id}.',
    );
    return _NormalizedMetricReadingDraft(
      values: values,
      source: source,
      externalId: externalId,
    );
  }

  _NormalizedMetricReadingValues _normalizeMetricReadingUpdateDraft(
    MetricReadingUpdateDraft draft, {
    required MetricRow metric,
  }) {
    return _normalizeMetricReadingValues(
      valueEntered: draft.valueEntered,
      atTime: draft.atTime,
      windowStartedAt: draft.windowStartedAt,
      windowEndedAt: draft.windowEndedAt,
      comment: draft.comment,
      metric: metric,
      shapeErrorMessage:
          'Scalar Reading update requires a scalar Metric: ${metric.id}.',
    );
  }

  _NormalizedMetricReadingDraft _normalizeIntegrationReadingDraft(
    IntegrationMetricReadingDraft draft, {
    required MetricRow metric,
  }) {
    final source = draft.source.trim();
    if (source.isEmpty) {
      throw ArgumentError.value(draft.source, 'source', 'Source is required.');
    }
    final externalId = _normalizeOptionalText(draft.externalId);
    if (externalId == null) {
      throw ArgumentError.value(
        draft.externalId,
        'externalId',
        'Integration Reading externalId is required.',
      );
    }
    final values = _normalizeMetricReadingValues(
      valueEntered: draft.valueEntered,
      atTime: draft.atTime,
      windowStartedAt: draft.windowStartedAt,
      windowEndedAt: draft.windowEndedAt,
      comment: draft.comment,
      metric: metric,
      shapeErrorMessage:
          'Integration scalar Reading requires a scalar Metric: ${metric.id}.',
    );
    return _NormalizedMetricReadingDraft(
      values: values,
      source: source,
      externalId: externalId,
    );
  }

  _NormalizedMetricReadingValues _normalizeMetricReadingValues({
    required String valueEntered,
    required DateTime? atTime,
    required DateTime? windowStartedAt,
    required DateTime? windowEndedAt,
    required String? comment,
    required MetricRow metric,
    required String shapeErrorMessage,
  }) {
    final metricShape = MetricValueShape.values.byName(metric.valueShape);
    if (metricShape != MetricValueShape.scalar) {
      throw StateError(shapeErrorMessage);
    }

    final normalizedValueEntered = valueEntered.trim();
    final scalarValue = double.tryParse(normalizedValueEntered);
    if (scalarValue == null || !scalarValue.isFinite) {
      throw ArgumentError.value(
        valueEntered,
        'valueEntered',
        'Scalar Reading value must be finite.',
      );
    }

    final normalizedAtTime = atTime?.toUtc();
    final normalizedWindowStartedAt = windowStartedAt?.toUtc();
    final normalizedWindowEndedAt = windowEndedAt?.toUtc();
    final hasInstant = normalizedAtTime != null;
    final hasWindow =
        normalizedWindowStartedAt != null || normalizedWindowEndedAt != null;
    if (hasInstant == hasWindow) {
      throw ArgumentError(
        'A Reading must have either atTime or a complete window, not both.',
      );
    }
    if (hasWindow) {
      if (normalizedWindowStartedAt == null ||
          normalizedWindowEndedAt == null) {
        throw ArgumentError('Window Readings require start and end times.');
      }
      if (!normalizedWindowEndedAt.isAfter(normalizedWindowStartedAt)) {
        throw ArgumentError('Window end must be after window start.');
      }
    }

    final valueJson = jsonEncode(<String, Object?>{
      'shape': MetricValueShape.scalar.name,
      'value': scalarValue,
      'entered': normalizedValueEntered,
    });
    return _NormalizedMetricReadingValues(
      valueJson: valueJson,
      scalarValue: scalarValue,
      scalarEntered: normalizedValueEntered,
      atTime: normalizedAtTime,
      windowStartedAt: normalizedWindowStartedAt,
      windowEndedAt: normalizedWindowEndedAt,
      comment: _normalizeOptionalText(comment),
    );
  }

  int _nextMetricSortOrder(List<MetricRow> rows) {
    var next = 0;
    for (final row in rows) {
      if (row.sortOrder >= next) {
        next = row.sortOrder + 1;
      }
    }
    return next;
  }
}

class ActivityLogRepository {
  const ActivityLogRepository._(this._repositories);

  final TrainingRepositories _repositories;

  AppDatabase get _database => _repositories.database;

  Future<List<ActivityLogEntry>> listEntries() async {
    final rows = await _activityLogQuery().get();
    return rows.map(_activityLogEntryFromRow).toList(growable: false);
  }

  Future<List<ActivityLogEntry>> listEntriesSince(DateTime cutoff) async {
    final rows = await _activityLogQuery(
      occurredAtOnOrAfter: cutoff.toUtc(),
      newestFirst: true,
    ).get();
    return rows.map(_activityLogEntryFromRow).toList(growable: false);
  }

  Stream<List<ActivityLogEntry>> watchEntries() {
    return _activityLogQuery().watch().map(
          (rows) => rows.map(_activityLogEntryFromRow).toList(growable: false),
        );
  }

  Stream<List<ActivityLogEntry>> watchEntriesSince(DateTime cutoff) {
    return _activityLogQuery(
      occurredAtOnOrAfter: cutoff.toUtc(),
      newestFirst: true,
    ).watch().map(
          (rows) => rows.map(_activityLogEntryFromRow).toList(growable: false),
        );
  }

  Future<ActivityLogUndoResult> undoBatch(
    String batchId, {
    String actor = 'app',
  }) {
    return _database.transaction(() async {
      final entries = await _listEntriesForBatch(batchId);
      if (entries.isEmpty) {
        throw StateError('Activity batch not found: $batchId.');
      }

      final conflicts = <ActivityLogUndoConflict>[];
      for (final entry in entries) {
        final expected = entry.afterImage;
        final current = await _currentImageFor(
          entityTable: entry.entityTable,
          entityId: entry.entityId,
        );
        if (current == null) {
          conflicts.add(
            ActivityLogUndoConflict(
              entryId: entry.id,
              entityTable: entry.entityTable,
              entityId: entry.entityId,
              reason: ActivityLogUndoConflictReason.missing,
              expectedImage: expected,
              currentImage: null,
            ),
          );
          continue;
        }
        if (expected == null ||
            !_activityImagesEqualForEntity(
              entry.entityTable,
              current,
              expected,
            )) {
          conflicts.add(
            ActivityLogUndoConflict(
              entryId: entry.id,
              entityTable: entry.entityTable,
              entityId: entry.entityId,
              reason: expected == null
                  ? ActivityLogUndoConflictReason.unsupported
                  : ActivityLogUndoConflictReason.stale,
              expectedImage: expected,
              currentImage: current,
            ),
          );
        }
      }

      if (conflicts.isEmpty) {
        conflicts.addAll(
          await _templateGroupMemberUndoConflicts(entries),
        );
      }

      if (conflicts.isNotEmpty) {
        return ActivityLogUndoResult(
          originalBatchId: batchId,
          undoBatchId: null,
          appliedEntries: const <ActivityLogEntry>[],
          conflicts: List<ActivityLogUndoConflict>.unmodifiable(conflicts),
        );
      }

      final context = _repositories._createWriteContext(actor: actor);
      final appliedEntries = <ActivityLogEntry>[];
      final routineUndoScope = _routineUndoScope(entries);
      for (final entry in entries.reversed) {
        final before = await _currentImageFor(
          entityTable: entry.entityTable,
          entityId: entry.entityId,
        );
        final target = _inverseImageForUndo(entry, context.timestamp);
        await _writeImageFor(
          entityTable: entry.entityTable,
          entityId: entry.entityId,
          image: target,
        );
        final after = await _currentImageFor(
          entityTable: entry.entityTable,
          entityId: entry.entityId,
        );
        await _append(
          context,
          entityTable: entry.entityTable,
          entityId: entry.entityId,
          beforeImage: before,
          afterImage: after,
        );
        appliedEntries.add(entry);
      }
      await _normalizeRoutineEntriesAfterUndo(
        routineUndoScope,
        context,
      );

      return ActivityLogUndoResult(
        originalBatchId: batchId,
        undoBatchId: context.batchId,
        appliedEntries: List<ActivityLogEntry>.unmodifiable(appliedEntries),
        conflicts: const <ActivityLogUndoConflict>[],
      );
    });
  }

  Future<List<ActivityLogUndoConflict>> _templateGroupMemberUndoConflicts(
    List<ActivityLogEntry> entries,
  ) async {
    final memberEntries = entries
        .where(
          (entry) => entry.entityTable == AppDatabase.templateGroupMembersTable,
        )
        .toList(growable: false);
    if (memberEntries.isEmpty) {
      return const <ActivityLogUndoConflict>[];
    }

    final targetsById = <String, Map<String, Object?>>{};
    final activeTargetsByExerciseId = <String, List<ActivityLogEntry>>{};
    for (final entry in memberEntries) {
      final source = entry.beforeImage ?? entry.afterImage;
      if (source == null) {
        continue;
      }
      final target = Map<String, Object?>.from(source);
      if (entry.beforeImage == null) {
        target['deleted_at'] = 'undo-tombstone';
      }
      targetsById[entry.entityId] = target;
      if (target['deleted_at'] == null) {
        final templateExerciseId =
            _activityRequiredString(target, 'template_exercise_id');
        activeTargetsByExerciseId
            .putIfAbsent(
              templateExerciseId,
              () => <ActivityLogEntry>[],
            )
            .add(entry);
      }
    }
    if (activeTargetsByExerciseId.isEmpty) {
      return const <ActivityLogUndoConflict>[];
    }

    final conflictingEntryIds = <String>{};
    for (final targetEntries in activeTargetsByExerciseId.values) {
      if (targetEntries.length > 1) {
        conflictingEntryIds.addAll(
          targetEntries.map((entry) => entry.id),
        );
      }
    }
    final activeRows = await (_database.select(_database.templateGroupMembers)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.templateExerciseId.isIn(
                  activeTargetsByExerciseId.keys,
                ),
          ))
        .get();
    for (final row in activeRows) {
      final targetEntries = activeTargetsByExerciseId[row.templateExerciseId]!;
      for (final targetEntry in targetEntries) {
        if (row.id == targetEntry.entityId) {
          continue;
        }
        final conflictingTarget = targetsById[row.id];
        if (conflictingTarget != null &&
            conflictingTarget['deleted_at'] != null) {
          continue;
        }
        conflictingEntryIds.add(targetEntry.id);
      }
    }

    final conflicts = <ActivityLogUndoConflict>[];
    for (final entry in memberEntries) {
      if (!conflictingEntryIds.contains(entry.id)) {
        continue;
      }
      conflicts.add(
        ActivityLogUndoConflict(
          entryId: entry.id,
          entityTable: entry.entityTable,
          entityId: entry.entityId,
          reason: ActivityLogUndoConflictReason.stale,
          expectedImage: entry.afterImage,
          currentImage: await _currentImageFor(
            entityTable: entry.entityTable,
            entityId: entry.entityId,
          ),
        ),
      );
    }
    return List<ActivityLogUndoConflict>.unmodifiable(conflicts);
  }

  _RoutineUndoScope _routineUndoScope(List<ActivityLogEntry> entries) {
    final routineIds = <String>{};
    final cadenceChangedRoutineIds = <String>{};
    final entryIdsByRoutine = <String, Set<String>>{};
    for (final entry in entries) {
      if (entry.entityTable == AppDatabase.planRoutinesTable) {
        routineIds.add(entry.entityId);
        final before = entry.beforeImage;
        final after = entry.afterImage;
        if (before != null &&
            after != null &&
            (before['cadence_kind'] != after['cadence_kind'] ||
                before['cadence_window'] != after['cadence_window'])) {
          cadenceChangedRoutineIds.add(entry.entityId);
        }
        continue;
      }
      if (entry.entityTable != AppDatabase.routineEntriesTable) {
        continue;
      }
      final image = entry.beforeImage ?? entry.afterImage;
      if (image == null) {
        continue;
      }
      final routineId = _activityRequiredString(image, 'routine_id');
      routineIds.add(routineId);
      entryIdsByRoutine
          .putIfAbsent(routineId, () => <String>{})
          .add(entry.entityId);
    }
    return _RoutineUndoScope(
      routineIds: routineIds,
      cadenceChangedRoutineIds: cadenceChangedRoutineIds,
      entryIdsByRoutine: entryIdsByRoutine,
    );
  }

  Future<void> _normalizeRoutineEntriesAfterUndo(
    _RoutineUndoScope scope,
    _WriteContext context,
  ) async {
    for (final routineId in scope.routineIds.toList()..sort()) {
      final routine = await (_database.select(_database.planRoutines)
            ..where((row) => row.id.equals(routineId)))
          .getSingleOrNull();
      if (routine == null) {
        continue;
      }
      final cadence = _cadenceFromRow(routine);
      final rows = await (_database.select(_database.routineEntries)
            ..where(
              (row) => row.routineId.equals(routineId) & row.deletedAt.isNull(),
            )
            ..orderBy([
              (row) => OrderingTerm.asc(row.position),
              (row) => OrderingTerm.asc(row.id),
            ]))
          .get();
      for (var position = 0; position < rows.length; position += 1) {
        final before = rows[position];
        final slot = scope.cadenceChangedRoutineIds.contains(routineId) &&
                !(scope.entryIdsByRoutine[routineId]?.contains(before.id) ??
                    false)
            ? _defaultRoutineEntrySlot(position, cadence)
            : _reconciledRoutineEntrySlot(
                before.slot,
                position: position,
                cadence: cadence,
              );
        if (before.position == position && before.slot == slot) {
          continue;
        }
        final updatedAt = context.timestamp.isAfter(before.updatedAt)
            ? context.timestamp
            : before.updatedAt.add(const Duration(seconds: 1));
        await (_database.update(_database.routineEntries)
              ..where((row) => row.id.equals(before.id)))
            .write(
          RoutineEntriesCompanion(
            position: Value<int>(position),
            slot: Value<int?>(slot),
            updatedAt: Value<DateTime>(updatedAt),
          ),
        );
        final after = await (_database.select(_database.routineEntries)
              ..where((row) => row.id.equals(before.id)))
            .getSingle();
        await _append(
          context,
          entityTable: AppDatabase.routineEntriesTable,
          entityId: before.id,
          beforeImage: _routineEntryImage(before),
          afterImage: _routineEntryImage(after),
        );
      }
    }
  }

  Future<List<ActivityLogEntry>> _listEntriesForBatch(String batchId) async {
    final rows = await (_database.select(_database.activityLog)
          ..where(
            (row) => row.deletedAt.isNull() & row.batchId.equals(batchId),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAt),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
    return rows.map(_activityLogEntryFromRow).toList(growable: false);
  }

  SimpleSelectStatement<$ActivityLogTable, ActivityLogRow> _activityLogQuery({
    DateTime? occurredAtOnOrAfter,
    bool newestFirst = false,
  }) {
    final query = _database.select(_database.activityLog)
      ..where((row) => row.deletedAt.isNull());
    if (occurredAtOnOrAfter != null) {
      query.where(
        (row) => row.occurredAt.isBiggerOrEqualValue(occurredAtOnOrAfter),
      );
    }
    query.orderBy([
      (row) => newestFirst
          ? OrderingTerm.desc(row.occurredAt)
          : OrderingTerm.asc(row.occurredAt),
      (row) =>
          newestFirst ? OrderingTerm.desc(row.id) : OrderingTerm.asc(row.id),
    ]);
    return query;
  }

  Future<void> _append(
    _WriteContext context, {
    required String entityTable,
    required String entityId,
    required Map<String, Object?>? beforeImage,
    required Map<String, Object?>? afterImage,
    String? id,
    DateTime? occurredAt,
    DateTime? syncAcknowledgedAt,
  }) {
    final activityLogId = id ?? _repositories.createId(context.timestamp);
    final activityOccurredAt = occurredAt ?? context.timestamp;
    return _database.into(_database.activityLog).insert(
          ActivityLogCompanion.insert(
            id: activityLogId,
            actor: context.actor,
            batchId: context.batchId,
            entityTable: entityTable,
            entityId: entityId,
            beforeImage: Value<String?>(
              beforeImage == null ? null : jsonEncode(beforeImage),
            ),
            afterImage: Value<String?>(
              afterImage == null ? null : jsonEncode(afterImage),
            ),
            occurredAt: activityOccurredAt,
            syncAcknowledgedAt: Value<DateTime?>(syncAcknowledgedAt),
            updatedAt: context.timestamp,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<Map<String, Object?>?> _currentImageFor({
    required String entityTable,
    required String entityId,
  }) async {
    switch (entityTable) {
      case AppDatabase.exerciseCategoriesTable:
        final row = await (_database.select(_database.exerciseCategories)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _exerciseCategoryImage(row);
      case AppDatabase.exercisesTable:
        final row = await (_database.select(_database.exercises)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _exerciseImage(row);
      case AppDatabase.workoutSessionsTable:
        final row = await (_database.select(_database.workoutSessions)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _workoutSessionImage(row);
      case AppDatabase.mealTypesTable:
        final row = await (_database.select(_database.mealTypes)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _mealTypeImage(row);
      case AppDatabase.mealsTable:
        final row = await (_database.select(_database.meals)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _mealImage(row);
      case AppDatabase.foodsTable:
        final row = await (_database.select(_database.foods)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _foodImage(row);
      case AppDatabase.foodEntriesTable:
        final row = await (_database.select(_database.foodEntries)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _foodEntryImage(row);
      case AppDatabase.nutritionGoalsTable:
        final row = await (_database.select(_database.nutritionGoals)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _nutritionGoalImage(row);
      case AppDatabase.workoutExercisesTable:
        final row = await (_database.select(_database.workoutExercises)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _workoutExerciseImage(row);
      case AppDatabase.exerciseGroupsTable:
        final row = await (_database.select(_database.exerciseGroups)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _exerciseGroupImage(row);
      case AppDatabase.exerciseGroupMembersTable:
        final row = await (_database.select(_database.exerciseGroupMembers)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _exerciseGroupMemberImage(row);
      case AppDatabase.workoutTemplatesTable:
        final row = await (_database.select(_database.workoutTemplates)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _workoutTemplateImage(row);
      case AppDatabase.templateExercisesTable:
        final row = await (_database.select(_database.templateExercises)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _templateExerciseImage(row);
      case AppDatabase.templateGroupsTable:
        final row = await (_database.select(_database.templateGroups)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _templateGroupImage(row);
      case AppDatabase.templateGroupMembersTable:
        final row = await (_database.select(_database.templateGroupMembers)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _templateGroupMemberImage(row);
      case AppDatabase.prescriptionsTable:
        final row = await (_database.select(_database.prescriptions)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _prescriptionImage(row);
      case AppDatabase.templateLinksTable:
        final row = await (_database.select(_database.templateLinks)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        if (row == null) {
          return null;
        }
        final workout = await _repositories.workoutSessions._requireRow(
          row.workoutId,
        );
        return _templateLinkImage(row, workout: workout);
      case AppDatabase.planRoutinesTable:
        final row = await (_database.select(_database.planRoutines)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _planRoutineImage(row);
      case AppDatabase.routineEntriesTable:
        final row = await (_database.select(_database.routineEntries)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _routineEntryImage(row);
      case AppDatabase.loggedSetsTable:
        final row = await (_database.select(_database.loggedSets)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _loggedSetImage(row);
      case AppDatabase.restTimersTable:
        final row = await (_database.select(_database.restTimers)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _restTimerImage(row);
      case AppDatabase.intervalTimersTable:
        final row = await (_database.select(_database.intervalTimers)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _intervalTimerImage(row);
      case AppDatabase.measurementsTable:
        final row = await (_database.select(_database.measurements)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _measurementImage(row);
      case AppDatabase.measurementEntriesTable:
        final row = await (_database.select(_database.measurementEntries)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _measurementEntryImage(row);
      case AppDatabase.metricsTable:
        final row = await (_database.select(_database.metrics)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _metricImage(row);
      case AppDatabase.metricReadingsTable:
        final row = await (_database.select(_database.metricReadings)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _metricReadingImage(row);
      case AppDatabase.compoundsTable:
        final row = await (_database.select(_database.compounds)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _compoundImage(row);
      case AppDatabase.dosesTable:
        final row = await (_database.select(_database.doses)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _doseImage(row);
      case AppDatabase.protocolsTable:
        final row = await (_database.select(_database.protocols)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _protocolImage(row);
      case AppDatabase.protocolCompoundsTable:
        final row = await (_database.select(_database.protocolCompounds)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _protocolCompoundImage(row);
      case AppDatabase.schedulesTable:
        final row = await (_database.select(_database.schedules)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _scheduleImage(row);
      case AppDatabase.protocolTargetOutcomesTable:
        final row = await (_database.select(_database.protocolTargetOutcomes)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _protocolTargetOutcomeImage(row);
      case AppDatabase.userSettingsTable:
        final row = await (_database.select(_database.userSettings)
              ..where((row) => row.id.equals(entityId)))
            .getSingleOrNull();
        return row == null ? null : _userSettingsImage(row);
      default:
        return null;
    }
  }

  Future<void> _writeImageFor({
    required String entityTable,
    required String entityId,
    required Map<String, Object?> image,
  }) {
    return switch (entityTable) {
      AppDatabase.exerciseCategoriesTable =>
        (_database.update(_database.exerciseCategories)
              ..where((row) => row.id.equals(entityId)))
            .write(_exerciseCategoryCompanionFromImage(image)),
      AppDatabase.exercisesTable => (_database.update(_database.exercises)
            ..where((row) => row.id.equals(entityId)))
          .write(_exerciseCompanionFromImage(image)),
      AppDatabase.workoutSessionsTable =>
        (_database.update(_database.workoutSessions)
              ..where((row) => row.id.equals(entityId)))
            .write(_workoutSessionCompanionFromImage(image)),
      AppDatabase.mealTypesTable => (_database.update(_database.mealTypes)
            ..where((row) => row.id.equals(entityId)))
          .write(_mealTypeCompanionFromImage(image)),
      AppDatabase.mealsTable => (_database.update(_database.meals)
            ..where((row) => row.id.equals(entityId)))
          .write(_mealCompanionFromImage(image)),
      AppDatabase.foodsTable => (_database.update(_database.foods)
            ..where((row) => row.id.equals(entityId)))
          .write(_foodCompanionFromImage(image)),
      AppDatabase.foodEntriesTable => (_database.update(_database.foodEntries)
            ..where((row) => row.id.equals(entityId)))
          .write(_foodEntryCompanionFromImage(image)),
      AppDatabase.nutritionGoalsTable =>
        (_database.update(_database.nutritionGoals)
              ..where((row) => row.id.equals(entityId)))
            .write(_nutritionGoalCompanionFromImage(image)),
      AppDatabase.workoutExercisesTable =>
        (_database.update(_database.workoutExercises)
              ..where((row) => row.id.equals(entityId)))
            .write(_workoutExerciseCompanionFromImage(image)),
      AppDatabase.exerciseGroupsTable =>
        (_database.update(_database.exerciseGroups)
              ..where((row) => row.id.equals(entityId)))
            .write(_exerciseGroupCompanionFromImage(image)),
      AppDatabase.exerciseGroupMembersTable =>
        (_database.update(_database.exerciseGroupMembers)
              ..where((row) => row.id.equals(entityId)))
            .write(_exerciseGroupMemberCompanionFromImage(image)),
      AppDatabase.workoutTemplatesTable =>
        (_database.update(_database.workoutTemplates)
              ..where((row) => row.id.equals(entityId)))
            .write(_workoutTemplateCompanionFromImage(image)),
      AppDatabase.templateExercisesTable =>
        (_database.update(_database.templateExercises)
              ..where((row) => row.id.equals(entityId)))
            .write(_templateExerciseCompanionFromImage(image)),
      AppDatabase.templateGroupsTable =>
        (_database.update(_database.templateGroups)
              ..where((row) => row.id.equals(entityId)))
            .write(_templateGroupCompanionFromImage(image)),
      AppDatabase.templateGroupMembersTable =>
        (_database.update(_database.templateGroupMembers)
              ..where((row) => row.id.equals(entityId)))
            .write(_templateGroupMemberCompanionFromImage(image)),
      AppDatabase.prescriptionsTable =>
        (_database.update(_database.prescriptions)
              ..where((row) => row.id.equals(entityId)))
            .write(_prescriptionCompanionFromImage(image)),
      AppDatabase.templateLinksTable =>
        (_database.update(_database.templateLinks)
              ..where((row) => row.id.equals(entityId)))
            .write(_templateLinkCompanionFromImage(image)),
      AppDatabase.planRoutinesTable => (_database.update(_database.planRoutines)
            ..where((row) => row.id.equals(entityId)))
          .write(_planRoutineCompanionFromImage(image)),
      AppDatabase.routineEntriesTable =>
        (_database.update(_database.routineEntries)
              ..where((row) => row.id.equals(entityId)))
            .write(_routineEntryCompanionFromImage(image)),
      AppDatabase.loggedSetsTable => (_database.update(_database.loggedSets)
            ..where((row) => row.id.equals(entityId)))
          .write(_loggedSetCompanionFromImage(image)),
      AppDatabase.restTimersTable => (_database.update(_database.restTimers)
            ..where((row) => row.id.equals(entityId)))
          .write(_restTimerCompanionFromImage(image)),
      AppDatabase.intervalTimersTable =>
        (_database.update(_database.intervalTimers)
              ..where((row) => row.id.equals(entityId)))
            .write(_intervalTimerCompanionFromImage(image)),
      AppDatabase.measurementsTable => (_database.update(_database.measurements)
            ..where((row) => row.id.equals(entityId)))
          .write(_measurementCompanionFromImage(image)),
      AppDatabase.measurementEntriesTable =>
        (_database.update(_database.measurementEntries)
              ..where((row) => row.id.equals(entityId)))
            .write(_measurementEntryCompanionFromImage(image)),
      AppDatabase.metricsTable => (_database.update(_database.metrics)
            ..where((row) => row.id.equals(entityId)))
          .write(_metricCompanionFromImage(image)),
      AppDatabase.metricReadingsTable =>
        (_database.update(_database.metricReadings)
              ..where((row) => row.id.equals(entityId)))
            .write(_metricReadingCompanionFromImage(image)),
      AppDatabase.compoundsTable => (_database.update(_database.compounds)
            ..where((row) => row.id.equals(entityId)))
          .write(_compoundCompanionFromImage(image)),
      AppDatabase.dosesTable => (_database.update(_database.doses)
            ..where((row) => row.id.equals(entityId)))
          .write(_doseCompanionFromImage(image)),
      AppDatabase.protocolsTable => (_database.update(_database.protocols)
            ..where((row) => row.id.equals(entityId)))
          .write(_protocolCompanionFromImage(image)),
      AppDatabase.protocolCompoundsTable =>
        (_database.update(_database.protocolCompounds)
              ..where((row) => row.id.equals(entityId)))
            .write(_protocolCompoundCompanionFromImage(image)),
      AppDatabase.schedulesTable => (_database.update(_database.schedules)
            ..where((row) => row.id.equals(entityId)))
          .write(_scheduleCompanionFromImage(image)),
      AppDatabase.protocolTargetOutcomesTable =>
        (_database.update(_database.protocolTargetOutcomes)
              ..where((row) => row.id.equals(entityId)))
            .write(_protocolTargetOutcomeCompanionFromImage(image)),
      AppDatabase.userSettingsTable => (_database.update(_database.userSettings)
            ..where((row) => row.id.equals(entityId)))
          .write(_userSettingsCompanionFromImage(image)),
      _ => throw StateError('Unsupported activity entity table: $entityTable.'),
    };
  }
}

class ExerciseDraft {
  ExerciseDraft({
    required this.name,
    required this.type,
    this.defaultLoadUnit = TrainingUnit.kilogram,
    this.loadMode = ExerciseLoadMode.added,
    this.recordProfile,
    this.isUnilateral = false,
    this.usesRpe = false,
    this.categoryId,
    List<ExerciseEquipment> equipment = const <ExerciseEquipment>[],
    this.notes,
  }) : equipment = List<ExerciseEquipment>.unmodifiable(equipment);

  final String name;
  final ExerciseType type;
  final TrainingUnit defaultLoadUnit;
  final ExerciseLoadMode loadMode;
  final RecordProfile? recordProfile;
  final bool isUnilateral;
  final bool usesRpe;
  final String? categoryId;
  final List<ExerciseEquipment> equipment;
  final String? notes;

  ExerciseLoadMode get effectiveLoadMode {
    if (!type.hasDimension(DimensionId.load)) {
      return ExerciseLoadMode.added;
    }
    return loadMode;
  }

  RecordProfile get effectiveRecordProfile {
    return recordProfile ??
        defaultRecordProfileFor(
          type: type,
          loadMode: effectiveLoadMode,
        );
  }
}

class ExerciseCategoryDraft {
  const ExerciseCategoryDraft({
    required this.name,
    this.colorHex,
  });

  final String name;
  final String? colorHex;
}

class WorkoutSessionDraft {
  const WorkoutSessionDraft({
    required this.startedAt,
    required this.timezone,
    this.localDate,
    this.endedAt,
    this.comment,
  });

  final DateTime startedAt;
  final String timezone;
  final TrainingDayDate? localDate;
  final DateTime? endedAt;
  final String? comment;
}

class WorkoutExerciseDraft {
  const WorkoutExerciseDraft({
    required this.workoutId,
    required this.exerciseId,
  });

  final String workoutId;
  final String exerciseId;
}

class ExerciseGroupDraft {
  ExerciseGroupDraft({
    required this.workoutId,
    required this.name,
    required this.colorHex,
    required Iterable<String> workoutExerciseIds,
  }) : workoutExerciseIds = List<String>.unmodifiable(workoutExerciseIds);

  final String workoutId;
  final String name;
  final String colorHex;
  final List<String> workoutExerciseIds;
}

class LoggedSetDraft {
  const LoggedSetDraft({
    this.workoutId,
    required this.exerciseId,
    required this.position,
    required this.values,
    this.plannedRestAfter,
    this.performedAt,
    this.isCompleted = false,
    this.comment,
    this.side,
    this.rpe,
  });

  final String? workoutId;
  final String exerciseId;
  final int position;
  final LoggedSet values;
  final Duration? plannedRestAfter;
  final DateTime? performedAt;
  final bool isCompleted;
  final String? comment;
  final SetSide? side;
  final double? rpe;

  LoggedSetDraft copyWith({
    String? workoutId,
    String? exerciseId,
    int? position,
    LoggedSet? values,
    Duration? plannedRestAfter,
    DateTime? performedAt,
    bool? isCompleted,
    String? comment,
    SetSide? side,
    double? rpe,
  }) {
    return LoggedSetDraft(
      workoutId: workoutId ?? this.workoutId,
      exerciseId: exerciseId ?? this.exerciseId,
      position: position ?? this.position,
      values: values ?? this.values,
      plannedRestAfter: plannedRestAfter ?? this.plannedRestAfter,
      performedAt: performedAt ?? this.performedAt,
      isCompleted: isCompleted ?? this.isCompleted,
      comment: comment ?? this.comment,
      side: side ?? this.side,
      rpe: rpe ?? this.rpe,
    );
  }
}

class WorkoutPlanExerciseDraft {
  WorkoutPlanExerciseDraft({
    required this.exerciseId,
    required Iterable<WorkoutPlanSetDraft> sets,
  }) : sets = List<WorkoutPlanSetDraft>.unmodifiable(sets);

  final String exerciseId;
  final List<WorkoutPlanSetDraft> sets;
}

class WorkoutPlanSetDraft {
  const WorkoutPlanSetDraft({
    required this.values,
    this.plannedRestAfter,
  });

  final LoggedSet values;
  final Duration? plannedRestAfter;
}

class RestTimerDraft {
  const RestTimerDraft({
    required this.workoutId,
    this.sourceSetId,
    required this.duration,
    this.alertVolume = RestTimerRepository.defaultAlertVolume,
  });

  final String? workoutId;
  final String? sourceSetId;
  final Duration duration;
  final double alertVolume;
}

class ExerciseRecord {
  ExerciseRecord({
    required this.id,
    required this.origin,
    required this.name,
    required this.type,
    required this.defaultLoadUnit,
    required this.loadMode,
    required this.recordProfile,
    this.isUnilateral = false,
    this.usesRpe = false,
    required this.categoryId,
    List<ExerciseEquipment> equipment = const <ExerciseEquipment>[],
    required this.notes,
    required this.isFavorite,
    required this.updatedAt,
    this.shadowsPlatformExercise = false,
    this.deletedAt,
  }) : equipment = List<ExerciseEquipment>.unmodifiable(equipment);

  final String id;
  final ExerciseLibraryOrigin origin;
  final String name;
  final ExerciseType type;
  final TrainingUnit defaultLoadUnit;
  final ExerciseLoadMode loadMode;
  final RecordProfile recordProfile;
  final bool isUnilateral;
  final bool usesRpe;
  final String? categoryId;
  final List<ExerciseEquipment> equipment;
  final String? notes;
  final bool isFavorite;
  final DateTime updatedAt;
  final bool shadowsPlatformExercise;
  final DateTime? deletedAt;

  bool get isReadOnly => origin == ExerciseLibraryOrigin.platform;

  ExerciseRecord copyWith({
    bool? shadowsPlatformExercise,
  }) {
    return ExerciseRecord(
      id: id,
      origin: origin,
      name: name,
      type: type,
      defaultLoadUnit: defaultLoadUnit,
      loadMode: loadMode,
      recordProfile: recordProfile,
      isUnilateral: isUnilateral,
      usesRpe: usesRpe,
      categoryId: categoryId,
      equipment: equipment,
      notes: notes,
      isFavorite: isFavorite,
      updatedAt: updatedAt,
      shadowsPlatformExercise:
          shadowsPlatformExercise ?? this.shadowsPlatformExercise,
      deletedAt: deletedAt,
    );
  }
}

class WorkoutSessionRecord {
  const WorkoutSessionRecord({
    required this.id,
    required this.startedAt,
    required this.timezone,
    required this.localDate,
    required this.updatedAt,
    this.endedAt,
    this.comment,
    this.deletedAt,
  });

  final String id;
  final DateTime startedAt;
  final String timezone;
  final TrainingDayDate localDate;
  final DateTime? endedAt;
  final String? comment;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class AutoFinishedWorkoutRecord {
  const AutoFinishedWorkoutRecord({
    required this.workoutId,
    required this.lastInteractionAt,
    required this.endedAt,
  });

  final String workoutId;
  final DateTime lastInteractionAt;
  final DateTime endedAt;
}

class WorkoutExerciseRecord {
  const WorkoutExerciseRecord({
    required this.id,
    required this.workoutId,
    required this.exerciseId,
    required this.position,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String workoutId;
  final String exerciseId;
  final int position;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class ExerciseGroupRecord {
  ExerciseGroupRecord({
    required this.id,
    required this.workoutId,
    required this.name,
    required this.colorHex,
    required this.position,
    required Iterable<ExerciseGroupMemberRecord> members,
    required this.updatedAt,
    this.deletedAt,
  }) : members = List<ExerciseGroupMemberRecord>.unmodifiable(members);

  final String id;
  final String workoutId;
  final String name;
  final String colorHex;
  final int position;
  final List<ExerciseGroupMemberRecord> members;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  List<String> get workoutExerciseIds {
    return members.map((member) => member.workoutExerciseId).toList(
          growable: false,
        );
  }
}

class ExerciseGroupMemberRecord {
  const ExerciseGroupMemberRecord({
    required this.id,
    required this.groupId,
    required this.workoutExerciseId,
    required this.position,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String groupId;
  final String workoutExerciseId;
  final int position;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class LoggedSetRecord {
  const LoggedSetRecord({
    required this.id,
    required this.workoutId,
    required this.exerciseId,
    required this.position,
    required this.values,
    required this.plannedRestAfter,
    this.performedAt,
    required this.isCompleted,
    required this.updatedAt,
    this.comment,
    this.side,
    this.rpe,
    this.deletedAt,
  });

  final String id;
  final String workoutId;
  final String exerciseId;
  final int position;
  final LoggedSet values;
  final Duration? plannedRestAfter;
  final DateTime? performedAt;
  final bool isCompleted;
  final DateTime updatedAt;
  final String? comment;
  final SetSide? side;
  final double? rpe;
  final DateTime? deletedAt;
}

class RestTimerRecord {
  const RestTimerRecord({
    required this.id,
    required this.workoutId,
    required this.sourceSetId,
    required this.startedAt,
    required this.deadlineAt,
    required this.duration,
    required this.alertVolume,
    required this.status,
    required this.updatedAt,
    this.alertFiredAt,
    this.prepareAlertFiredAt,
    this.deletedAt,
  });

  final String id;
  final String? workoutId;
  final String? sourceSetId;
  final DateTime startedAt;
  final DateTime deadlineAt;
  final Duration duration;
  final double alertVolume;
  final RestTimerStatus status;
  final DateTime? alertFiredAt;
  final DateTime? prepareAlertFiredAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Duration remainingAt(DateTime now) {
    final remaining = deadlineAt.difference(now.toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool isExpiredAt(DateTime now) => remainingAt(now) == Duration.zero;
}

final class _RoutineUndoScope {
  _RoutineUndoScope({
    required Set<String> routineIds,
    required Set<String> cadenceChangedRoutineIds,
    required Map<String, Set<String>> entryIdsByRoutine,
  })  : routineIds = Set<String>.unmodifiable(routineIds),
        cadenceChangedRoutineIds =
            Set<String>.unmodifiable(cadenceChangedRoutineIds),
        entryIdsByRoutine = Map<String, Set<String>>.unmodifiable(
          entryIdsByRoutine.map(
            (routineId, entryIds) => MapEntry(
              routineId,
              Set<String>.unmodifiable(entryIds),
            ),
          ),
        );

  final Set<String> routineIds;
  final Set<String> cadenceChangedRoutineIds;
  final Map<String, Set<String>> entryIdsByRoutine;
}

final class ActivityLogEntry {
  ActivityLogEntry({
    required this.id,
    required this.actor,
    required this.batchId,
    required this.entityTable,
    required this.entityId,
    required this.occurredAt,
    required this.updatedAt,
    Map<String, Object?>? beforeImage,
    Map<String, Object?>? afterImage,
    this.deletedAt,
  })  : beforeImage = _immutableActivityLogImage(beforeImage),
        afterImage = _immutableActivityLogImage(afterImage);

  final String id;
  final String actor;
  final String batchId;
  final String entityTable;
  final String entityId;
  final Map<String, Object?>? beforeImage;
  final Map<String, Object?>? afterImage;
  final DateTime occurredAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

Map<String, Object?>? _immutableActivityLogImage(
  Map<String, Object?>? image,
) {
  if (image == null) {
    return null;
  }
  return Map<String, Object?>.unmodifiable(
    image.map(
      (key, value) => MapEntry(key, _immutableActivityLogValue(value)),
    ),
  );
}

Object? _immutableActivityLogValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _immutableActivityLogImage(value);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map(_immutableActivityLogValue),
    );
  }
  return value;
}

enum MeasurementUnit {
  kilogram,
  pound,
  centimeter,
  inch,
  percent;
}

enum MeasurementGoalType {
  increase,
  decrease,
  target;
}

enum MetricValueShape {
  scalar,
  structured,
  series;
}

enum MetricGroup {
  bodyComposition,
  monitoring,
  custom;
}

enum MetricGoalType {
  increase,
  decrease,
  target;
}

enum MetricReadingProvenance {
  manual,
  integration,
  agent;
}

class MeasurementDraft {
  const MeasurementDraft({
    required this.name,
    required this.unit,
    required this.goalType,
    required this.enabled,
    this.sortOrder,
    this.targetValue,
  });

  final String name;
  final MeasurementUnit unit;
  final MeasurementGoalType goalType;
  final double? targetValue;
  final bool enabled;
  final int? sortOrder;

  MeasurementDraft copyWith({
    String? name,
    MeasurementUnit? unit,
    MeasurementGoalType? goalType,
    double? targetValue,
    bool? enabled,
    int? sortOrder,
  }) {
    return MeasurementDraft(
      name: name ?? this.name,
      unit: unit ?? this.unit,
      goalType: goalType ?? this.goalType,
      targetValue: targetValue ?? this.targetValue,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class MeasurementEntryDraft {
  const MeasurementEntryDraft({
    required this.measurementId,
    required this.valueEntered,
    required this.measuredAt,
    this.comment,
  });

  final String measurementId;
  final String valueEntered;
  final DateTime measuredAt;
  final String? comment;
}

class MeasurementRecord {
  const MeasurementRecord({
    required this.id,
    required this.name,
    required this.unit,
    required this.goalType,
    required this.enabled,
    required this.sortOrder,
    required this.updatedAt,
    this.targetValue,
    this.deletedAt,
  });

  final String id;
  final String name;
  final MeasurementUnit unit;
  final MeasurementGoalType goalType;
  final double? targetValue;
  final bool enabled;
  final int sortOrder;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class MeasurementEntryRecord {
  const MeasurementEntryRecord({
    required this.id,
    required this.measurementId,
    required this.value,
    required this.valueEntered,
    required this.measuredAt,
    required this.updatedAt,
    this.provenance = MetricReadingProvenance.manual,
    this.source = 'manual',
    this.externalId,
    this.comment,
    this.deletedAt,
  });

  final String id;
  final String measurementId;
  final double value;
  final String valueEntered;
  final DateTime measuredAt;
  final MetricReadingProvenance provenance;
  final String source;
  final String? externalId;
  final String? comment;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get canEditInPlace => provenance != MetricReadingProvenance.integration;
}

class MetricDraft {
  const MetricDraft({
    required this.name,
    required this.unit,
    required this.valueShape,
    required this.group,
    required this.enabled,
    required this.pinned,
    this.goalType,
    this.goalTargetValue,
    this.sortOrder,
  });

  final String name;
  final String unit;
  final MetricValueShape valueShape;
  final MetricGroup group;
  final MetricGoalType? goalType;
  final double? goalTargetValue;
  final bool enabled;
  final bool pinned;
  final int? sortOrder;

  MetricDraft copyWith({
    String? name,
    String? unit,
    MetricValueShape? valueShape,
    MetricGroup? group,
    MetricGoalType? goalType,
    double? goalTargetValue,
    bool? enabled,
    bool? pinned,
    int? sortOrder,
  }) {
    return MetricDraft(
      name: name ?? this.name,
      unit: unit ?? this.unit,
      valueShape: valueShape ?? this.valueShape,
      group: group ?? this.group,
      goalType: goalType ?? this.goalType,
      goalTargetValue: goalTargetValue ?? this.goalTargetValue,
      enabled: enabled ?? this.enabled,
      pinned: pinned ?? this.pinned,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class ManualMetricReadingDraft {
  const ManualMetricReadingDraft.scalar({
    required this.metricId,
    required this.valueEntered,
    required this.source,
    this.atTime,
    this.windowStartedAt,
    this.windowEndedAt,
    this.externalId,
    this.comment,
  }) : valueShape = MetricValueShape.scalar;

  final String metricId;
  final MetricValueShape valueShape;
  final String valueEntered;
  final DateTime? atTime;
  final DateTime? windowStartedAt;
  final DateTime? windowEndedAt;
  final String source;
  final String? externalId;
  final String? comment;
}

class MetricReadingUpdateDraft {
  const MetricReadingUpdateDraft.scalar({
    required this.metricId,
    required this.valueEntered,
    this.atTime,
    this.windowStartedAt,
    this.windowEndedAt,
    this.comment,
  }) : valueShape = MetricValueShape.scalar;

  final String metricId;
  final MetricValueShape valueShape;
  final String valueEntered;
  final DateTime? atTime;
  final DateTime? windowStartedAt;
  final DateTime? windowEndedAt;
  final String? comment;
}

class IntegrationMetricReadingDraft {
  const IntegrationMetricReadingDraft.scalar({
    required this.metricId,
    required this.valueEntered,
    required this.source,
    required this.externalId,
    this.atTime,
    this.windowStartedAt,
    this.windowEndedAt,
    this.comment,
  }) : valueShape = MetricValueShape.scalar;

  final String metricId;
  final MetricValueShape valueShape;
  final String valueEntered;
  final DateTime? atTime;
  final DateTime? windowStartedAt;
  final DateTime? windowEndedAt;
  final String source;
  final String externalId;
  final String? comment;
}

class MetricRecord {
  const MetricRecord({
    required this.id,
    required this.name,
    required this.unit,
    required this.valueShape,
    required this.group,
    required this.enabled,
    required this.pinned,
    required this.sortOrder,
    required this.updatedAt,
    this.goalType,
    this.goalTargetValue,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String unit;
  final MetricValueShape valueShape;
  final MetricGroup group;
  final MetricGoalType? goalType;
  final double? goalTargetValue;
  final bool enabled;
  final bool pinned;
  final int sortOrder;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// A lightweight active `Metric` picker/read option. This intentionally carries
/// only the identity an outcome picker needs; units, groups, goals, enabled
/// state, and lifecycle timestamps are detail/series concerns.
class MetricOptionRecord {
  const MetricOptionRecord({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

class MetricReadingRecord {
  const MetricReadingRecord({
    required this.id,
    required this.metricId,
    required this.valueJson,
    required this.provenance,
    required this.source,
    required this.updatedAt,
    this.scalarValue,
    this.scalarEntered,
    this.atTime,
    this.windowStartedAt,
    this.windowEndedAt,
    this.externalId,
    this.comment,
    this.deletedAt,
  });

  final String id;
  final String metricId;
  final String valueJson;
  final double? scalarValue;
  final String? scalarEntered;
  final DateTime? atTime;
  final DateTime? windowStartedAt;
  final DateTime? windowEndedAt;
  final MetricReadingProvenance provenance;
  final String source;
  final String? externalId;
  final String? comment;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class MetricSummary {
  const MetricSummary({
    required this.metric,
    this.latestReading,
    this.previousReading,
  });

  final MetricRecord metric;
  final MetricReadingRecord? latestReading;
  final MetricReadingRecord? previousReading;

  double? get trendDelta {
    final latestValue = latestReading?.scalarValue;
    final previousValue = previousReading?.scalarValue;
    if (latestValue == null || previousValue == null) {
      return null;
    }
    return latestValue - previousValue;
  }
}

class MonitoringMetricSummary {
  const MonitoringMetricSummary({
    required this.metric,
    required this.latestReading,
    this.previousReading,
  });

  final MetricRecord metric;
  final MetricReadingRecord latestReading;
  final MetricReadingRecord? previousReading;

  double? get trendDelta {
    final latestValue = latestReading.scalarValue;
    final previousValue = previousReading?.scalarValue;
    if (latestValue == null || previousValue == null) {
      return null;
    }
    return latestValue - previousValue;
  }
}

/// A read-only `Metric` series: the metric and its ordered active `Reading`s.
///
/// This is the stored, provenance-stamped Metric family the trends
/// surface renders **alongside** the derived nutrition analytics. It is read
/// from the Metric store only; it is never written to from nutrition data and
/// the two families are never merged into one series store ("join, never
/// merge", NUTRITION.md §2).
class MetricSeriesData {
  MetricSeriesData({
    required this.metric,
    required Iterable<MetricReadingRecord> readings,
  }) : readings = List<MetricReadingRecord>.unmodifiable(readings);

  final MetricRecord metric;
  final List<MetricReadingRecord> readings;
}

class _NormalizedMetricReadingValues {
  const _NormalizedMetricReadingValues({
    required this.valueJson,
    required this.scalarValue,
    required this.scalarEntered,
    this.atTime,
    this.windowStartedAt,
    this.windowEndedAt,
    this.comment,
  });

  final String valueJson;
  final double scalarValue;
  final String scalarEntered;
  final DateTime? atTime;
  final DateTime? windowStartedAt;
  final DateTime? windowEndedAt;
  final String? comment;
}

class _NormalizedMetricReadingDraft extends _NormalizedMetricReadingValues {
  _NormalizedMetricReadingDraft({
    required _NormalizedMetricReadingValues values,
    required this.source,
    this.externalId,
  }) : super(
          valueJson: values.valueJson,
          scalarValue: values.scalarValue,
          scalarEntered: values.scalarEntered,
          atTime: values.atTime,
          windowStartedAt: values.windowStartedAt,
          windowEndedAt: values.windowEndedAt,
          comment: values.comment,
        );

  final String source;
  final String? externalId;
}

class MeasurementTrackSummary {
  const MeasurementTrackSummary({
    required this.measurement,
    this.latestEntry,
    this.previousEntry,
  });

  final MeasurementRecord measurement;
  final MeasurementEntryRecord? latestEntry;
  final MeasurementEntryRecord? previousEntry;
}

class MeasurementHistoryEntry {
  const MeasurementHistoryEntry({
    required this.measurement,
    required this.entry,
    this.previousEntry,
  });

  final MeasurementRecord measurement;
  final MeasurementEntryRecord entry;
  final MeasurementEntryRecord? previousEntry;
}

class ActivityLogUndoResult {
  ActivityLogUndoResult({
    required this.originalBatchId,
    required this.undoBatchId,
    required Iterable<ActivityLogEntry> appliedEntries,
    required Iterable<ActivityLogUndoConflict> conflicts,
  })  : appliedEntries = List<ActivityLogEntry>.unmodifiable(appliedEntries),
        conflicts = List<ActivityLogUndoConflict>.unmodifiable(conflicts);

  final String originalBatchId;
  final String? undoBatchId;
  final List<ActivityLogEntry> appliedEntries;
  final List<ActivityLogUndoConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

class ActivityLogUndoConflict {
  const ActivityLogUndoConflict({
    required this.entryId,
    required this.entityTable,
    required this.entityId,
    required this.reason,
    required this.expectedImage,
    required this.currentImage,
  });

  final String entryId;
  final String entityTable;
  final String entityId;
  final ActivityLogUndoConflictReason reason;
  final Map<String, Object?>? expectedImage;
  final Map<String, Object?>? currentImage;
}

enum ActivityLogUndoConflictReason {
  stale,
  missing,
  unsupported,
}

class LogWorkoutResult {
  const LogWorkoutResult({
    required this.batchId,
    required this.workoutSessionId,
    required this.loggedSetId,
  });

  final String batchId;
  final String workoutSessionId;
  final String loggedSetId;
}

class WorkoutPlanLogResult {
  WorkoutPlanLogResult({
    required this.batchId,
    required this.workoutId,
    required Iterable<String> workoutExerciseIds,
    required Iterable<String> loggedSetIds,
  })  : workoutExerciseIds = List<String>.unmodifiable(workoutExerciseIds),
        loggedSetIds = List<String>.unmodifiable(loggedSetIds);

  final String batchId;
  final String workoutId;
  final List<String> workoutExerciseIds;
  final List<String> loggedSetIds;
}

enum ExerciseLibraryOrigin {
  platform,
  user,
}

enum SetSide {
  left,
  right,
}

enum RestTimerStatus {
  running,
  expired,
  canceled,
}

enum CategoryOrdering {
  manual,
  name,
}

class DuplicateExerciseNameException implements Exception {
  const DuplicateExerciseNameException(this.name);

  final String name;

  @override
  String toString() => 'Duplicate user exercise name: $name.';
}

class DuplicateExerciseCategoryNameException implements Exception {
  const DuplicateExerciseCategoryNameException(this.name);

  final String name;

  @override
  String toString() => 'Duplicate exercise category name: $name.';
}

class DuplicateUserFoodNameException implements Exception {
  const DuplicateUserFoodNameException(this.name);

  final String name;

  @override
  String toString() => 'Duplicate User Food name: $name.';
}

class DuplicateMealTypeNameException implements Exception {
  const DuplicateMealTypeNameException(this.name);

  final String name;

  @override
  String toString() => 'Duplicate Meal Type name: $name.';
}

class CategoryHasActiveExercisesException implements Exception {
  const CategoryHasActiveExercisesException({
    required this.categoryId,
    required this.activeExerciseCount,
  });

  final String categoryId;
  final int activeExerciseCount;

  @override
  String toString() {
    return 'Category $categoryId has $activeExerciseCount active exercises.';
  }
}

class ExerciseCategoryRecord {
  const ExerciseCategoryRecord({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.colorHex,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final int sortOrder;
  final String colorHex;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

final class ExerciseCatalogSectionRecord {
  ExerciseCatalogSectionRecord({
    required this.category,
    required List<ExerciseRecord> exercises,
    this.virtualId,
    this.virtualTitle,
  }) : exercises = List<ExerciseRecord>.unmodifiable(exercises);

  ExerciseCatalogSectionRecord.virtualFavorites({
    required List<ExerciseRecord> exercises,
  })  : category = null,
        exercises = List<ExerciseRecord>.unmodifiable(exercises),
        virtualId = favoritesId,
        virtualTitle = 'Favorites';

  static const favoritesId = 'favorites';

  final ExerciseCategoryRecord? category;
  final List<ExerciseRecord> exercises;
  final String? virtualId;
  final String? virtualTitle;

  String get id => virtualId ?? category?.id ?? 'uncategorized';

  String get title => virtualTitle ?? category?.name ?? 'Uncategorized';

  bool get isVirtual => virtualId != null;
}

class _WriteContext {
  const _WriteContext({
    required this.actor,
    required this.batchId,
    required this.timestamp,
  });

  final String actor;
  final String batchId;
  final DateTime timestamp;
}

class _DefaultMealTypeSeed {
  const _DefaultMealTypeSeed({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final int sortOrder;
}

class _DimensionColumns {
  const _DimensionColumns({
    this.value,
    this.unit,
    this.entered,
  });

  final double? value;
  final String? unit;
  final String? entered;
}

class _LoggedSetColumns {
  const _LoggedSetColumns({
    required this.load,
    required this.reps,
    required this.duration,
    required this.distance,
  });

  final _DimensionColumns load;
  final _DimensionColumns reps;
  final _DimensionColumns duration;
  final _DimensionColumns distance;
}

ExerciseCategoryRecord _exerciseCategoryFromRow(ExerciseCategoryRow row) {
  return ExerciseCategoryRecord(
    id: row.id,
    name: row.name,
    sortOrder: row.sortOrder,
    colorHex: row.colorHex,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

ExerciseRecord _exerciseFromRow(ExerciseRow row) {
  return ExerciseRecord(
    id: row.id,
    origin: ExerciseLibraryOrigin.values.byName(row.libraryOrigin),
    name: row.name,
    type: _decodeDimensions(row.dimensionIds),
    defaultLoadUnit: TrainingUnit.values.byName(row.defaultLoadUnit),
    loadMode: ExerciseLoadMode.values.byName(row.loadMode),
    recordProfile: RecordProfile.values.byName(row.recordProfile),
    isUnilateral: row.isUnilateral,
    usesRpe: row.usesRpe,
    categoryId: row.categoryId,
    equipment: _decodeEquipment(row.equipmentIds),
    notes: row.notes,
    isFavorite: row.isFavorite,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

WorkoutSessionRecord _workoutSessionFromRow(WorkoutSessionRow row) {
  return WorkoutSessionRecord(
    id: row.id,
    startedAt: row.startedAt.toUtc(),
    timezone: row.timezone,
    localDate: TrainingDayDate.parse(row.localDate),
    endedAt: row.endedAt?.toUtc(),
    comment: row.comment,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

MealRecord _mealFromRow(MealRow row) {
  return MealRecord(
    id: row.id,
    mealType: row.mealType,
    startedAt: row.startedAt.toUtc(),
    timezone: row.timezone,
    localDate: NutritionDayDate.parse(row.localDate),
    endedAt: row.endedAt?.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

UserFoodRecord _userFoodFromRow(FoodRow row) {
  final recipeIngredients = _recipeIngredientsFromJsonString(
    row.recipeIngredientsJson,
  );
  final recipeServingCount = row.recipeServingCount;
  final recipeNutrition =
      recipeServingCount == null || recipeIngredients.isEmpty
          ? null
          : deriveRecipeNutrition(
              ingredients: recipeIngredients,
              servingCount: recipeServingCount,
            );
  return UserFoodRecord(
    id: row.id,
    name: row.name,
    foodSource: FoodSource.values.byName(row.foodSource),
    nutrientsPer100: recipeNutrition?.nutrientsPer100 ??
        NutrientVector.fromJsonString(row.nutrientValuesJson),
    isLiquid: recipeNutrition == null ? row.isLiquid : false,
    servingLabel: recipeNutrition == null ? row.servingLabel : 'serving',
    servingSize: recipeNutrition?.servingSize ?? row.servingSize,
    packageSize: recipeNutrition == null ? row.packageSize : null,
    recipeIngredients: recipeIngredients,
    recipeServingCount: recipeServingCount,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

PlatformFoodRecord _openFoodFactsRecordFromCacheRow(
  OpenFoodFactsCacheRow row,
) {
  return PlatformFoodRecord(
    id: row.foodId,
    name: row.name,
    foodSource: FoodSource.openFoodFacts,
    nutrientsPer100: NutrientVector.fromJsonString(row.nutrientValuesJson),
    isLiquid: row.isLiquid,
    servingLabel: row.servingLabel,
    servingSize: row.servingSize,
    packageSize: row.packageSize,
  );
}

PlatformFoodRecord? _openFoodFactsRecordFromProduct(
  Map<String, Object?> product, {
  String? fallbackCode,
}) {
  final code = _openFoodFactsString(product['code']) ?? fallbackCode;
  final name = _firstOpenFoodFactsString(
    product,
    const <String>['product_name', 'product_name_en', 'generic_name'],
  );
  if (code == null || code.trim().isEmpty || name == null) {
    return null;
  }

  final serving = _openFoodFactsQuantity(
    value: product['serving_quantity'],
    unit: product['serving_quantity_unit'],
    fallbackText: product['serving_size'],
  );
  final package = _openFoodFactsQuantity(
    value: product['product_quantity'],
    unit: product['product_quantity_unit'],
    fallbackText: product['quantity'],
  );

  return PlatformFoodRecord(
    id: code.trim(),
    name: name.trim(),
    foodSource: FoodSource.openFoodFacts,
    nutrientsPer100: _openFoodFactsNutrientVector(product['nutriments']),
    isLiquid: serving?.isLiquid ?? package?.isLiquid ?? false,
    servingLabel: serving == null ? null : 'serving',
    servingSize: serving?.baseQuantity,
    packageSize: package?.baseQuantity,
  );
}

NutrientVector _openFoodFactsNutrientVector(Object? value) {
  if (value is! Map) {
    return NutrientVector.full(const <NutrientId, NutrientAmount>{});
  }
  final nutriments = Map<String, Object?>.from(value);
  final amounts = <NutrientId, NutrientAmount>{};

  void add(
    NutrientId id,
    List<String> keys, {
    double multiplier = 1,
  }) {
    final sourceValue = _firstOpenFoodFactsNumber(nutriments, keys);
    if (sourceValue == null || sourceValue < 0) {
      return;
    }
    final normalizedValue = sourceValue * multiplier;
    amounts[id] = NutrientAmount.complete(
      value: normalizedValue,
      entered: _formatOpenFoodFactsNumber(normalizedValue),
      unit: id.defaultUnit,
    );
  }

  add(NutrientId.energy, const <String>[
    'energy-kcal_100g',
    'energy-kcal_value',
  ]);
  add(NutrientId.protein, const <String>['proteins_100g']);
  add(NutrientId.carbohydrate, const <String>['carbohydrates_100g']);
  add(NutrientId.sugar, const <String>['sugars_100g']);
  add(NutrientId.fat, const <String>['fat_100g']);
  add(NutrientId.saturatedFat, const <String>['saturated-fat_100g']);
  add(NutrientId.monounsaturatedFat, const <String>[
    'monounsaturated-fat_100g',
    'mono-unsaturated-fat_100g',
  ]);
  add(NutrientId.polyunsaturatedFat, const <String>[
    'polyunsaturated-fat_100g',
    'poly-unsaturated-fat_100g',
  ]);
  add(NutrientId.fiber, const <String>['fiber_100g', 'fibers_100g']);
  add(NutrientId.sodium, const <String>['sodium_100g'], multiplier: 1000);
  add(
    NutrientId.cholesterol,
    const <String>['cholesterol_100g'],
    multiplier: 1000,
  );
  add(NutrientId.caffeine, const <String>['caffeine_100g'], multiplier: 1000);

  return NutrientVector.full(amounts);
}

String _openFoodFactsLookupKey(String query) {
  final barcode = _openFoodFactsBarcode(query);
  if (barcode != null) {
    return 'barcode:$barcode';
  }
  final normalized = query.trim().toLowerCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
  return 'search:$normalized';
}

String? _openFoodFactsBarcode(String query) {
  final compact = query.trim().replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp(r'^\d{6,18}$').hasMatch(compact)) {
    return compact;
  }
  return null;
}

String? _firstOpenFoodFactsString(
  Map<String, Object?> values,
  List<String> keys,
) {
  for (final key in keys) {
    final value = _openFoodFactsString(values[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

String? _openFoodFactsString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

double? _firstOpenFoodFactsNumber(
  Map<String, Object?> values,
  List<String> keys,
) {
  for (final key in keys) {
    final value = _openFoodFactsNumber(values[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

double? _openFoodFactsNumber(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  if (value is String) {
    final normalized = value.trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalized);
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  return null;
}

String _formatOpenFoodFactsNumber(double value) {
  final fixed = value.toStringAsFixed(6);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

_OpenFoodFactsQuantity? _openFoodFactsQuantity({
  required Object? value,
  required Object? unit,
  required Object? fallbackText,
}) {
  final parsedValue = _openFoodFactsNumber(value);
  final parsedUnit = _openFoodFactsString(unit);
  if (parsedValue != null && parsedUnit != null) {
    final quantity = _openFoodFactsQuantityFromValue(
      parsedValue,
      parsedUnit,
    );
    if (quantity != null) {
      return quantity;
    }
  }

  final text = _openFoodFactsString(fallbackText);
  if (text == null) {
    return null;
  }
  final match = RegExp(r'(-?\d+(?:[\.,]\d+)?)\s*([A-Za-z ]+)').firstMatch(
    text,
  );
  if (match == null) {
    return null;
  }
  final fallbackValue = _openFoodFactsNumber(match.group(1));
  final fallbackUnit = match.group(2);
  if (fallbackValue == null || fallbackUnit == null) {
    return null;
  }
  return _openFoodFactsQuantityFromValue(fallbackValue, fallbackUnit);
}

_OpenFoodFactsQuantity? _openFoodFactsQuantityFromValue(
  double value,
  String unit,
) {
  if (!value.isFinite || value <= 0) {
    return null;
  }
  final normalizedUnit = unit
      .trim()
      .toLowerCase()
      .replaceAll('.', '')
      .replaceAll(RegExp(r'\s+'), ' ');
  return switch (normalizedUnit) {
    'g' || 'gram' || 'grams' => _OpenFoodFactsQuantity(
        baseQuantity: value,
        isLiquid: false,
      ),
    'kg' || 'kilogram' || 'kilograms' => _OpenFoodFactsQuantity(
        baseQuantity: value * 1000,
        isLiquid: false,
      ),
    'oz' || 'ounce' || 'ounces' => _OpenFoodFactsQuantity(
        baseQuantity: value * 28.349523125,
        isLiquid: false,
      ),
    'ml' ||
    'milliliter' ||
    'milliliters' ||
    'millilitre' ||
    'millilitres' =>
      _OpenFoodFactsQuantity(
        baseQuantity: value,
        isLiquid: true,
      ),
    'l' || 'liter' || 'liters' || 'litre' || 'litres' => _OpenFoodFactsQuantity(
        baseQuantity: value * 1000,
        isLiquid: true,
      ),
    'fl oz' ||
    'floz' ||
    'fluid ounce' ||
    'fluid ounces' =>
      _OpenFoodFactsQuantity(
        baseQuantity: value * 29.5735295625,
        isLiquid: true,
      ),
    _ => null,
  };
}

class _OpenFoodFactsQuantity {
  const _OpenFoodFactsQuantity({
    required this.baseQuantity,
    required this.isLiquid,
  });

  final double baseQuantity;
  final bool isLiquid;
}

MealTypeRecord _mealTypeFromRow(MealTypeRow row) {
  return MealTypeRecord(
    id: row.id,
    name: row.name,
    sortOrder: row.sortOrder,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

NutritionGoalRecord _nutritionGoalFromRow(NutritionGoalRow row) {
  return NutritionGoalRecord(
    id: row.id,
    target: NutritionGoalTarget(
      nutrient: NutrientId.byStorageKey(row.nutrientId),
      value: row.targetValue,
      entered: row.targetEntered,
      unit: NutrientUnit.values.byName(row.unit),
    ),
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

FoodEntryRecord _foodEntryFromRow(FoodEntryRow row) {
  return FoodEntryRecord(
    id: row.id,
    mealId: row.mealId,
    kind: FoodEntryKind.values.byName(row.entryKind),
    position: row.position,
    name: row.name,
    nutrients: NutrientVector.fromJsonString(row.nutrientValuesJson),
    foodId: row.foodId,
    portion: row.portionJson == null
        ? null
        : Portion.fromJsonString(row.portionJson!),
    foodSource: row.foodSource == null
        ? null
        : FoodSource.values.byName(row.foodSource!),
    isLiquid: row.isLiquid,
    servingLabel: row.servingLabel,
    servingSize: row.servingSize,
    packageSize: row.packageSize,
    importSource: row.importSource,
    importExternalId: row.importExternalId,
    importProvider: row.importProvider,
    reviewFlags: NutritionReviewFlag.decode(row.reviewFlagsJson),
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

bool _isRecipeRow(FoodRow row) {
  return row.recipeServingCount != null || row.recipeIngredientsJson != null;
}

List<String> _foodSearchTerms(String query) {
  return query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList(growable: false);
}

String _escapeSqlLikeTerm(String term) {
  return term
      .replaceAll('\\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

List<RecipeIngredient> _recipeIngredientsFromJsonString(String? value) {
  if (value == null) {
    return const <RecipeIngredient>[];
  }
  final decoded = jsonDecode(value);
  if (decoded is! List<Object?>) {
    throw FormatException('Expected Recipe ingredient list.', value);
  }
  return List<RecipeIngredient>.unmodifiable(
    decoded.map((item) {
      if (item is! Map) {
        throw FormatException('Expected Recipe ingredient object.', item);
      }
      return RecipeIngredient.fromJson(Map<String, Object?>.from(item));
    }),
  );
}

String _recipeIngredientsToJsonString(List<RecipeIngredient> ingredients) {
  return jsonEncode(
    ingredients
        .map((ingredient) => ingredient.toJson())
        .toList(growable: false),
  );
}

NutritionDayRecord _nutritionDayFromRows(
  NutritionDayDate localDate,
  List<MealRow> mealRows,
  List<FoodEntryRow> entryRows,
  List<MealTypeRow> mealTypeRows,
) {
  final entriesByMealId = <String, List<FoodEntryRecord>>{};
  for (final row in entryRows) {
    entriesByMealId
        .putIfAbsent(row.mealId, () => <FoodEntryRecord>[])
        .add(_foodEntryFromRow(row));
  }
  final mealTypeSortOrders = <String, int>{
    for (final row in mealTypeRows) row.name: row.sortOrder,
  };
  final sortedMeals = List<MealRow>.of(mealRows)
    ..sort((left, right) {
      final leftSortOrder = mealTypeSortOrders[left.mealType] ?? 1 << 30;
      final rightSortOrder = mealTypeSortOrders[right.mealType] ?? 1 << 30;
      final orderComparison = leftSortOrder.compareTo(rightSortOrder);
      if (orderComparison != 0) {
        return orderComparison;
      }
      final startedComparison = left.startedAt.compareTo(right.startedAt);
      if (startedComparison != 0) {
        return startedComparison;
      }
      final typeComparison = left.mealType.compareTo(right.mealType);
      if (typeComparison != 0) {
        return typeComparison;
      }
      return left.id.compareTo(right.id);
    });

  return NutritionDayRecord(
    localDate: localDate,
    meals: List<NutritionDayMealRecord>.unmodifiable(
      sortedMeals.map(
        (row) => NutritionDayMealRecord(
          meal: _mealFromRow(row),
          entries: List<FoodEntryRecord>.unmodifiable(
            entriesByMealId[row.id] ?? const <FoodEntryRecord>[],
          ),
        ),
      ),
    ),
  );
}

List<NutritionDayRecord> _nutritionDaysInRangeFromRows(
  NutritionDayRange range,
  List<MealRow> mealRows,
  List<FoodEntryRow> entryRows,
  List<MealTypeRow> mealTypeRows,
) {
  final mealsByDate = <String, List<MealRow>>{};
  for (final row in mealRows) {
    mealsByDate.putIfAbsent(row.localDate, () => <MealRow>[]).add(row);
  }

  return List<NutritionDayRecord>.unmodifiable(
    range.days.map(
      (date) => _nutritionDayFromRows(
        date,
        mealsByDate[date.storageValue] ?? const <MealRow>[],
        entryRows,
        mealTypeRows,
      ),
    ),
  );
}

bool _sameRowList<T>(List<T>? left, List<T> right) {
  if (left == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

WorkoutExerciseRecord _workoutExerciseFromRow(WorkoutExerciseRow row) {
  return WorkoutExerciseRecord(
    id: row.id,
    workoutId: row.workoutId,
    exerciseId: row.exerciseId,
    position: row.position,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

ExerciseGroupRecord _exerciseGroupFromRow(
  ExerciseGroupRow row,
  List<ExerciseGroupMemberRow> memberRows,
) {
  final sortedMembers = List<ExerciseGroupMemberRow>.of(memberRows)
    ..sort((left, right) => left.position.compareTo(right.position));
  return ExerciseGroupRecord(
    id: row.id,
    workoutId: row.workoutId,
    name: row.name,
    colorHex: row.colorHex,
    position: row.position,
    members: List<ExerciseGroupMemberRecord>.unmodifiable(
      sortedMembers.map(_exerciseGroupMemberFromRow),
    ),
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

List<ExerciseGroupRecord> _exerciseGroupsFromRows(
  List<ExerciseGroupRow> rows,
  List<ExerciseGroupMemberRow> memberRows,
) {
  final membersByGroupId = <String, List<ExerciseGroupMemberRow>>{};
  for (final member in memberRows) {
    membersByGroupId
        .putIfAbsent(member.groupId, () => <ExerciseGroupMemberRow>[])
        .add(member);
  }

  return rows
      .map(
        (row) => _exerciseGroupFromRow(
          row,
          membersByGroupId[row.id] ?? const <ExerciseGroupMemberRow>[],
        ),
      )
      .toList(growable: false);
}

ExerciseGroupMemberRecord _exerciseGroupMemberFromRow(
  ExerciseGroupMemberRow row,
) {
  return ExerciseGroupMemberRecord(
    id: row.id,
    groupId: row.groupId,
    workoutExerciseId: row.workoutExerciseId,
    position: row.position,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

LoggedSetRecord _loggedSetFromRow(LoggedSetRow row) {
  return LoggedSetRecord(
    id: row.id,
    workoutId: row.workoutId,
    exerciseId: row.exerciseId,
    position: row.position,
    values: _loggedSetValuesFromRow(row),
    plannedRestAfter: row.plannedRestAfter == null
        ? null
        : Duration(seconds: row.plannedRestAfter!),
    performedAt: row.performedAt?.toUtc(),
    isCompleted: row.isCompleted,
    updatedAt: row.updatedAt.toUtc(),
    comment: row.comment,
    side: row.side == null ? null : SetSide.values.byName(row.side!),
    rpe: row.rpe,
    deletedAt: row.deletedAt?.toUtc(),
  );
}

RestTimerRecord _restTimerFromRow(RestTimerRow row) {
  return RestTimerRecord(
    id: row.id,
    workoutId: row.workoutId,
    sourceSetId: row.sourceSetId,
    startedAt: row.startedAt.toUtc(),
    deadlineAt: row.deadlineAt.toUtc(),
    duration: Duration(seconds: row.durationSeconds),
    alertVolume: row.alertVolume,
    status: RestTimerStatus.values.byName(row.status),
    alertFiredAt: row.alertFiredAt?.toUtc(),
    prepareAlertFiredAt: row.prepareAlertFiredAt?.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

bool _sameDimensionIds(
  List<DimensionId> left,
  List<DimensionId> right,
) {
  if (left.length != right.length) {
    return false;
  }

  final expected = right.toSet();
  return expected.length == right.length && left.every(expected.contains);
}

ActivityLogEntry _activityLogEntryFromRow(ActivityLogRow row) {
  return ActivityLogEntry(
    id: row.id,
    actor: row.actor,
    batchId: row.batchId,
    entityTable: row.entityTable,
    entityId: row.entityId,
    beforeImage: _decodeImage(row.beforeImage),
    afterImage: _decodeImage(row.afterImage),
    occurredAt: row.occurredAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

MetricRecord _metricRecordFromRow(MetricRow row) {
  return MetricRecord(
    id: row.id,
    name: row.name,
    unit: row.unit,
    valueShape: MetricValueShape.values.byName(row.valueShape),
    group: MetricGroup.values.byName(row.metricGroup),
    goalType: row.goalType == null
        ? null
        : MetricGoalType.values.byName(row.goalType!),
    goalTargetValue: row.goalTargetValue,
    enabled: row.enabled,
    pinned: row.pinned,
    sortOrder: row.sortOrder,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

MetricReadingRecord _metricReadingRecordFromRow(MetricReadingRow row) {
  return MetricReadingRecord(
    id: row.id,
    metricId: row.metricId,
    valueJson: row.valueJson,
    scalarValue: row.scalarValue,
    scalarEntered: row.scalarEntered,
    atTime: row.atTime?.toUtc(),
    windowStartedAt: row.windowStartedAt?.toUtc(),
    windowEndedAt: row.windowEndedAt?.toUtc(),
    provenance: MetricReadingProvenance.values.byName(row.provenance),
    source: row.source,
    externalId: row.externalId,
    comment: row.comment,
    updatedAt: row.updatedAt.toUtc(),
    deletedAt: row.deletedAt?.toUtc(),
  );
}

Map<String, Object?> _exerciseImage(ExerciseRow row) {
  return <String, Object?>{
    'id': row.id,
    'library_origin': row.libraryOrigin,
    'name': row.name,
    'dimension_ids': row.dimensionIds,
    'default_load_unit': row.defaultLoadUnit,
    'load_mode': row.loadMode,
    'record_profile': row.recordProfile,
    'is_favorite': row.isFavorite,
    'is_unilateral': row.isUnilateral,
    'uses_rpe': row.usesRpe,
    'category_id': row.categoryId,
    'equipment_ids': row.equipmentIds,
    'notes': row.notes,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _measurementImage(MeasurementRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'unit': row.unit,
    'goal_type': row.goalType,
    'target_value': row.targetValue,
    'enabled': row.enabled,
    'sort_order': row.sortOrder,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _measurementEntryImage(MeasurementEntryRow row) {
  return <String, Object?>{
    'id': row.id,
    'measurement_id': row.measurementId,
    'value': row.value,
    'value_entered': row.valueEntered,
    'measured_at': _iso(row.measuredAt),
    'comment': row.comment,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _metricImage(MetricRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'unit': row.unit,
    'value_shape': row.valueShape,
    'metric_group': row.metricGroup,
    'goal_type': row.goalType,
    'goal_target_value': row.goalTargetValue,
    'enabled': row.enabled,
    'pinned': row.pinned,
    'sort_order': row.sortOrder,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _metricReadingImage(MetricReadingRow row) {
  return <String, Object?>{
    'id': row.id,
    'metric_id': row.metricId,
    'value_json': row.valueJson,
    'scalar_value': row.scalarValue,
    'scalar_entered': row.scalarEntered,
    'at_time': row.atTime == null ? null : _iso(row.atTime!),
    'window_started_at':
        row.windowStartedAt == null ? null : _iso(row.windowStartedAt!),
    'window_ended_at':
        row.windowEndedAt == null ? null : _iso(row.windowEndedAt!),
    'provenance': row.provenance,
    'source': row.source,
    'external_id': row.externalId,
    'comment': row.comment,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _exerciseCategoryImage(ExerciseCategoryRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'sort_order': row.sortOrder,
    'color_hex': row.colorHex,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _workoutSessionImage(WorkoutSessionRow row) {
  return <String, Object?>{
    'id': row.id,
    'started_at': _iso(row.startedAt),
    'timezone': row.timezone,
    'local_date': row.localDate,
    'ended_at': row.endedAt == null ? null : _iso(row.endedAt!),
    'comment': row.comment,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _mealImage(MealRow row) {
  return <String, Object?>{
    'id': row.id,
    'meal_type': row.mealType,
    'started_at': _iso(row.startedAt),
    'timezone': row.timezone,
    'local_date': row.localDate,
    'ended_at': row.endedAt == null ? null : _iso(row.endedAt!),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _mealTypeImage(MealTypeRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'sort_order': row.sortOrder,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _nutritionGoalImage(NutritionGoalRow row) {
  return <String, Object?>{
    'id': row.id,
    'nutrient_id': row.nutrientId,
    'target_value': row.targetValue,
    'target_entered': row.targetEntered,
    'unit': row.unit,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

AccountSettings _accountSettingsFromRow(UserSettingsRow row) {
  return AccountSettings(
    themePreference: row.themePreference,
    unitSystem: row.unitSystem,
    weekStartDay: row.weekStartDay,
    defaultWeightIncrement: row.defaultWeightIncrement,
    homeScreenDisplay: row.homeScreenDisplay,
    prTrackingEnabled: row.prTrackingEnabled,
    markSetsCompleteByDefault: row.markSetsCompleteByDefault,
    autoSelectNextSet: row.autoSelectNextSet,
  );
}

Map<String, Object?> _userSettingsImage(UserSettingsRow row) {
  return <String, Object?>{
    'id': row.id,
    'theme_preference': row.themePreference,
    'unit_system': row.unitSystem,
    'week_start_day': row.weekStartDay,
    'default_weight_increment': row.defaultWeightIncrement,
    'home_screen_display': row.homeScreenDisplay,
    'pr_tracking_enabled': row.prTrackingEnabled,
    'mark_sets_complete_by_default': row.markSetsCompleteByDefault,
    'auto_select_next_set': row.autoSelectNextSet,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

UserSettingsCompanion _userSettingsCompanionFromImage(
  Map<String, Object?> image,
) {
  return UserSettingsCompanion(
    themePreference: Value<String>(
      _activityRequiredString(image, 'theme_preference'),
    ),
    unitSystem: Value<String>(_activityRequiredString(image, 'unit_system')),
    weekStartDay: Value<String>(
      _activityRequiredString(image, 'week_start_day'),
    ),
    defaultWeightIncrement: Value<double>(
      _activityRequiredDouble(image, 'default_weight_increment'),
    ),
    homeScreenDisplay: Value<String>(
      _activityRequiredString(image, 'home_screen_display'),
    ),
    prTrackingEnabled: Value<bool>(
      _activityRequiredBool(image, 'pr_tracking_enabled'),
    ),
    markSetsCompleteByDefault: Value<bool>(
      _activityRequiredBool(image, 'mark_sets_complete_by_default'),
    ),
    autoSelectNextSet: Value<bool>(
      _activityRequiredBool(image, 'auto_select_next_set'),
    ),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

UserSettingsCompanion _userSettingsSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _userSettingsCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

Map<String, Object?> _foodImage(FoodRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'food_source': row.foodSource,
    'nutrient_values_json': row.nutrientValuesJson,
    'is_liquid': row.isLiquid,
    'serving_label': row.servingLabel,
    'serving_size': row.servingSize,
    'package_size': row.packageSize,
    'recipe_ingredients_json': row.recipeIngredientsJson,
    'recipe_serving_count': row.recipeServingCount,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _foodEntryImage(FoodEntryRow row) {
  return <String, Object?>{
    'id': row.id,
    'meal_id': row.mealId,
    'entry_kind': row.entryKind,
    'position': row.position,
    'name': row.name,
    'nutrient_values_json': row.nutrientValuesJson,
    'food_id': row.foodId,
    'portion_json': row.portionJson,
    'food_source': row.foodSource,
    'is_liquid': row.isLiquid,
    'serving_label': row.servingLabel,
    'serving_size': row.servingSize,
    'package_size': row.packageSize,
    'import_source': row.importSource,
    'import_external_id': row.importExternalId,
    'import_provider': row.importProvider,
    'review_flags_json': row.reviewFlagsJson,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _compoundImage(CompoundRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'default_unit': row.defaultUnit,
    'default_route': row.defaultRoute,
    'strength': row.strength,
    'is_favorite': row.isFavorite,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _doseImage(DoseRow row) {
  return <String, Object?>{
    'id': row.id,
    'compound_id': row.compoundId,
    'compound_name': row.compoundName,
    'compound_strength': row.compoundStrength,
    'amount_value': row.amountValue,
    'amount_entered': row.amountEntered,
    'unit': row.unit,
    'route': row.route,
    'took_at': _iso(row.tookAt),
    'timezone': row.timezone,
    'local_date': row.localDate,
    'provenance': row.provenance,
    'protocol_id': row.protocolId,
    'protocol_name': row.protocolName,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _protocolImage(ProtocolRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'start_date': _iso(row.startDate),
    'end_date': row.endDate == null ? null : _iso(row.endDate!),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _protocolCompoundImage(ProtocolCompoundRow row) {
  return <String, Object?>{
    'id': row.id,
    'protocol_id': row.protocolId,
    'compound_id': row.compoundId,
    'position': row.position,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _scheduleImage(ScheduleRow row) {
  return <String, Object?>{
    'id': row.id,
    'protocol_compound_id': row.protocolCompoundId,
    'dose_amount_value': row.doseAmountValue,
    'dose_amount_entered': row.doseAmountEntered,
    'dose_unit': row.doseUnit,
    'frequency': row.frequency,
    'route': row.route,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _protocolTargetOutcomeImage(
  ProtocolTargetOutcomeRow row,
) {
  return <String, Object?>{
    'id': row.id,
    'protocol_id': row.protocolId,
    'kind': row.kind,
    'metric_id': row.metricId,
    'position': row.position,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _workoutExerciseImage(WorkoutExerciseRow row) {
  return <String, Object?>{
    'id': row.id,
    'workout_id': row.workoutId,
    'exercise_id': row.exerciseId,
    'position': row.position,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _exerciseGroupImage(ExerciseGroupRow row) {
  return <String, Object?>{
    'id': row.id,
    'workout_id': row.workoutId,
    'name': row.name,
    'color_hex': row.colorHex,
    'position': row.position,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _exerciseGroupMemberImage(ExerciseGroupMemberRow row) {
  return <String, Object?>{
    'id': row.id,
    'group_id': row.groupId,
    'workout_exercise_id': row.workoutExerciseId,
    'position': row.position,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _workoutTemplateImage(WorkoutTemplateRow row) {
  return <String, Object?>{
    'id': row.id,
    'name': row.name,
    'notes': row.notes,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _templateExerciseImage(TemplateExerciseRow row) {
  return <String, Object?>{
    'id': row.id,
    'workout_template_id': row.workoutTemplateId,
    'exercise_id': row.exerciseId,
    'position': row.position,
    'note': row.note,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _templateGroupImage(TemplateGroupRow row) {
  return <String, Object?>{
    'id': row.id,
    'workout_template_id': row.workoutTemplateId,
    'name': row.name,
    'color_hex': row.colorHex,
    'rounds': row.rounds,
    'position': row.position,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _templateGroupMemberImage(TemplateGroupMemberRow row) {
  return <String, Object?>{
    'id': row.id,
    'group_id': row.groupId,
    'template_exercise_id': row.templateExerciseId,
    'position': row.position,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _prescriptionImage(PrescriptionRow row) {
  return <String, Object?>{
    'id': row.id,
    'template_exercise_id': row.templateExerciseId,
    'mode': row.mode,
    'position': row.position,
    'repeat': row.repeat,
    'rest_after': row.restAfter,
    'load_value': row.loadValue,
    'load_unit': row.loadUnit,
    'load_entered': row.loadEntered,
    'reps_value': row.repsValue,
    'reps_unit': row.repsUnit,
    'reps_entered': row.repsEntered,
    'duration_value': row.durationValue,
    'duration_unit': row.durationUnit,
    'duration_entered': row.durationEntered,
    'distance_value': row.distanceValue,
    'distance_unit': row.distanceUnit,
    'distance_entered': row.distanceEntered,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _templateLinkImage(
  TemplateLinkRow row, {
  WorkoutSessionRow? workout,
  List<WorkoutExerciseRow>? workoutExercises,
  List<ExerciseGroupRow>? exerciseGroups,
  List<ExerciseGroupMemberRow>? exerciseGroupMembers,
}) {
  return <String, Object?>{
    'id': row.id,
    'workout_id': row.workoutId,
    'workout_template_id': row.workoutTemplateId,
    'routine_id': row.routineId,
    'slot': row.slot,
    if (workout != null) ...<String, Object?>{
      'workout_started_at': _iso(workout.startedAt),
      'workout_timezone': workout.timezone,
      'workout_local_date': workout.localDate,
      'workout_ended_at':
          workout.endedAt == null ? null : _iso(workout.endedAt!),
      'workout_comment': workout.comment,
      'workout_updated_at': _iso(workout.updatedAt),
      'workout_deleted_at':
          workout.deletedAt == null ? null : _iso(workout.deletedAt!),
    },
    if (workoutExercises != null)
      'workout_exercises':
          workoutExercises.map(_workoutExerciseImage).toList(growable: false),
    if (exerciseGroups != null)
      'workout_exercise_groups':
          exerciseGroups.map(_exerciseGroupImage).toList(growable: false),
    if (exerciseGroupMembers != null)
      'workout_exercise_group_members': exerciseGroupMembers
          .map(_exerciseGroupMemberImage)
          .toList(growable: false),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _loggedSetImage(LoggedSetRow row) {
  return <String, Object?>{
    'id': row.id,
    'workout_id': row.workoutId,
    'exercise_id': row.exerciseId,
    'position': row.position,
    'planned_rest_after': row.plannedRestAfter,
    'performed_at': row.performedAt == null ? null : _iso(row.performedAt!),
    'is_completed': row.isCompleted,
    'load_value': row.loadValue,
    'load_unit': row.loadUnit,
    'load_entered': row.loadEntered,
    'reps_value': row.repsValue,
    'reps_unit': row.repsUnit,
    'reps_entered': row.repsEntered,
    'duration_value': row.durationValue,
    'duration_unit': row.durationUnit,
    'duration_entered': row.durationEntered,
    'distance_value': row.distanceValue,
    'distance_unit': row.distanceUnit,
    'distance_entered': row.distanceEntered,
    'comment': row.comment,
    'side': row.side,
    'rpe': row.rpe,
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _loggedSetActivityImageFromSyncImage(
  Map<String, Object?> image,
) {
  final performedAt = _activityNullableDateTime(image, 'performed_at');
  return <String, Object?>{
    'id': _activityRequiredString(image, 'id'),
    'workout_id': _activityRequiredString(image, 'workout_id'),
    'exercise_id': _activityRequiredString(image, 'exercise_id'),
    'position': _activityRequiredInt(image, 'position'),
    'planned_rest_after': _activityNullableInt(image, 'planned_rest_after'),
    'performed_at': performedAt == null ? null : _iso(performedAt),
    'is_completed': _activityBoolWithDefault(image, 'is_completed', false),
    'load_value': _activityNullableDouble(image, 'load_value'),
    'load_unit': _activityNullableString(image, 'load_unit'),
    'load_entered': _activityNullableString(image, 'load_entered'),
    'reps_value': _activityNullableDouble(image, 'reps_value'),
    'reps_unit': _activityNullableString(image, 'reps_unit'),
    'reps_entered': _activityNullableString(image, 'reps_entered'),
    'duration_value': _activityNullableDouble(image, 'duration_value'),
    'duration_unit': _activityNullableString(image, 'duration_unit'),
    'duration_entered': _activityNullableString(image, 'duration_entered'),
    'distance_value': _activityNullableDouble(image, 'distance_value'),
    'distance_unit': _activityNullableString(image, 'distance_unit'),
    'distance_entered': _activityNullableString(image, 'distance_entered'),
    'comment': _activityNullableString(image, 'comment'),
    'side': _activityNullableString(image, 'side'),
    'rpe': _activityNullableDouble(image, 'rpe'),
    'updated_at': _iso(_activityRequiredDateTime(image, 'updated_at')),
    'deleted_at': _activityNullableDateTime(image, 'deleted_at') == null
        ? null
        : _iso(_activityNullableDateTime(image, 'deleted_at')!),
  };
}

Map<String, Object?> _restTimerImage(RestTimerRow row) {
  return <String, Object?>{
    'id': row.id,
    'workout_id': row.workoutId,
    'source_set_id': row.sourceSetId,
    'started_at': _iso(row.startedAt),
    'deadline_at': _iso(row.deadlineAt),
    'duration_seconds': row.durationSeconds,
    'alert_volume': row.alertVolume,
    'status': row.status,
    'alert_fired_at': row.alertFiredAt == null ? null : _iso(row.alertFiredAt!),
    'prepare_alert_fired_at':
        row.prepareAlertFiredAt == null ? null : _iso(row.prepareAlertFiredAt!),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _intervalTimerImage(IntervalTimerRow row) {
  return <String, Object?>{
    'id': row.id,
    'workout_id': row.workoutId,
    'started_at': _iso(row.startedAt),
    'phase_started_at': _iso(row.phaseStartedAt),
    'deadline_at': _iso(row.deadlineAt),
    'current_step_index': row.currentStepIndex,
    'completed_set_count': row.completedSetCount,
    'alert_volume': row.alertVolume,
    'phase': row.phase,
    'status': row.status,
    'prepare_alert_fired_at':
        row.prepareAlertFiredAt == null ? null : _iso(row.prepareAlertFiredAt!),
    'updated_at': _iso(row.updatedAt),
    'deleted_at': row.deletedAt == null ? null : _iso(row.deletedAt!),
  };
}

Map<String, Object?> _inverseImageForUndo(
  ActivityLogEntry entry,
  DateTime timestamp,
) {
  final source = entry.beforeImage ?? entry.afterImage;
  if (source == null) {
    throw StateError('Activity entry has no invertible image: ${entry.id}.');
  }

  final target = Map<String, Object?>.from(source);
  target['updated_at'] = _iso(timestamp);
  if (entry.beforeImage == null) {
    target['deleted_at'] = _iso(timestamp);
  }
  return target;
}

bool _stringMapEquals(Map<String, String> left, Map<String, String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final key in left.keys) {
    if (right[key] != left[key]) {
      return false;
    }
  }
  return true;
}

bool _activityImagesEqual(
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (final key in left.keys) {
    if (!right.containsKey(key) ||
        !_activityImageValuesEqual(left[key], right[key])) {
      return false;
    }
  }
  return true;
}

const _templateLinkWorkoutSnapshotFields = <String>{
  'workout_started_at',
  'workout_timezone',
  'workout_local_date',
  'workout_ended_at',
  'workout_comment',
  'workout_updated_at',
  'workout_deleted_at',
  'workout_exercises',
  'workout_exercise_groups',
  'workout_exercise_group_members',
};

bool _activityImagesEqualForEntity(
  String entityTable,
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  if (entityTable != AppDatabase.templateLinksTable) {
    return _activityImagesEqual(left, right);
  }

  final normalizedLeft = Map<String, Object?>.from(left)
    ..removeWhere(
      (key, _) => _templateLinkWorkoutSnapshotFields.contains(key),
    );
  final normalizedRight = Map<String, Object?>.from(right)
    ..removeWhere(
      (key, _) => _templateLinkWorkoutSnapshotFields.contains(key),
    );
  return _activityImagesEqual(normalizedLeft, normalizedRight);
}

bool _activityImageValuesEqual(Object? left, Object? right) {
  if (left is num && right is num) {
    return left.toDouble() == right.toDouble();
  }
  return left == right;
}

ExerciseCategoriesCompanion _exerciseCategoryCompanionFromImage(
  Map<String, Object?> image,
) {
  return ExerciseCategoriesCompanion(
    name: Value<String>(_activityRequiredString(image, 'name')),
    sortOrder: Value<int>(_activityRequiredInt(image, 'sort_order')),
    colorHex: Value<String>(_activityRequiredString(image, 'color_hex')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

ExercisesCompanion _exerciseCompanionFromImage(Map<String, Object?> image) {
  return ExercisesCompanion(
    libraryOrigin:
        Value<String>(_activityRequiredString(image, 'library_origin')),
    name: Value<String>(_activityRequiredString(image, 'name')),
    dimensionIds:
        Value<String>(_activityRequiredString(image, 'dimension_ids')),
    defaultLoadUnit: Value<String>(
      _activityRequiredString(image, 'default_load_unit'),
    ),
    loadMode: Value<String>(_activityRequiredString(image, 'load_mode')),
    recordProfile:
        Value<String>(_activityRequiredString(image, 'record_profile')),
    isFavorite: Value<bool>(_activityRequiredBool(image, 'is_favorite')),
    isUnilateral: Value<bool>(_activityRequiredBool(image, 'is_unilateral')),
    usesRpe: Value<bool>(_activityRequiredBool(image, 'uses_rpe')),
    categoryId: Value<String?>(_activityNullableString(image, 'category_id')),
    equipmentIds: Value<String>(
      _activityNullableString(image, 'equipment_ids') ?? '[]',
    ),
    notes: Value<String?>(_activityNullableString(image, 'notes')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

ExerciseCategoriesCompanion _exerciseCategorySyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _exerciseCategoryCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

ExercisesCompanion _exerciseSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _exerciseCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

WorkoutSessionsCompanion _workoutSessionCompanionFromImage(
  Map<String, Object?> image,
) {
  return WorkoutSessionsCompanion(
    startedAt: Value<DateTime>(_activityRequiredDateTime(image, 'started_at')),
    timezone: Value<String>(_activityRequiredString(image, 'timezone')),
    localDate: Value<String>(_activityRequiredString(image, 'local_date')),
    endedAt: Value<DateTime?>(_activityNullableDateTime(image, 'ended_at')),
    comment: Value<String?>(_activityNullableString(image, 'comment')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

MealsCompanion _mealCompanionFromImage(Map<String, Object?> image) {
  return MealsCompanion(
    mealType: Value<String>(_activityRequiredString(image, 'meal_type')),
    startedAt: Value<DateTime>(_activityRequiredDateTime(image, 'started_at')),
    timezone: Value<String>(_activityRequiredString(image, 'timezone')),
    localDate: Value<String>(_activityRequiredString(image, 'local_date')),
    endedAt: Value<DateTime?>(_activityNullableDateTime(image, 'ended_at')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

MealsCompanion _mealSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _mealCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

MealTypesCompanion _mealTypeCompanionFromImage(Map<String, Object?> image) {
  return MealTypesCompanion(
    name: Value<String>(_activityRequiredString(image, 'name')),
    sortOrder: Value<int>(_activityRequiredInt(image, 'sort_order')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

MealTypesCompanion _mealTypeSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _mealTypeCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

NutritionGoalsCompanion _nutritionGoalCompanionFromImage(
  Map<String, Object?> image,
) {
  return NutritionGoalsCompanion(
    nutrientId: Value<String>(_activityRequiredString(image, 'nutrient_id')),
    targetValue: Value<double>(_activityRequiredDouble(image, 'target_value')),
    targetEntered: Value<String>(
      _activityRequiredString(image, 'target_entered'),
    ),
    unit: Value<String>(_activityRequiredString(image, 'unit')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

NutritionGoalsCompanion _nutritionGoalSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _nutritionGoalCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

FoodsCompanion _foodCompanionFromImage(Map<String, Object?> image) {
  return FoodsCompanion(
    name: Value<String>(_activityRequiredString(image, 'name')),
    foodSource: Value<String>(_activityRequiredString(image, 'food_source')),
    nutrientValuesJson: Value<String>(
      _activityRequiredString(image, 'nutrient_values_json'),
    ),
    isLiquid: Value<bool>(_activityRequiredBool(image, 'is_liquid')),
    servingLabel: Value<String?>(
      _activityNullableString(image, 'serving_label'),
    ),
    servingSize: Value<double?>(
      _activityNullableDouble(image, 'serving_size'),
    ),
    packageSize: Value<double?>(
      _activityNullableDouble(image, 'package_size'),
    ),
    recipeIngredientsJson: Value<String?>(
      _activityNullableString(image, 'recipe_ingredients_json'),
    ),
    recipeServingCount: Value<double?>(
      _activityNullableDouble(image, 'recipe_serving_count'),
    ),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

FoodsCompanion _foodSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _foodCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

FoodEntriesCompanion _foodEntryCompanionFromImage(
  Map<String, Object?> image,
) {
  return FoodEntriesCompanion(
    mealId: Value<String>(_activityRequiredString(image, 'meal_id')),
    entryKind: Value<String>(_activityRequiredString(image, 'entry_kind')),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    name: Value<String>(_activityRequiredString(image, 'name')),
    nutrientValuesJson: Value<String>(
      _activityRequiredString(image, 'nutrient_values_json'),
    ),
    foodId: Value<String?>(_activityNullableString(image, 'food_id')),
    portionJson: Value<String?>(_activityNullableString(image, 'portion_json')),
    foodSource: Value<String?>(_activityNullableString(image, 'food_source')),
    isLiquid: Value<bool?>(_activityNullableBool(image, 'is_liquid')),
    servingLabel: Value<String?>(
      _activityNullableString(image, 'serving_label'),
    ),
    servingSize: Value<double?>(
      _activityNullableDouble(image, 'serving_size'),
    ),
    packageSize: Value<double?>(
      _activityNullableDouble(image, 'package_size'),
    ),
    importSource: Value<String?>(
      _activityNullableString(image, 'import_source'),
    ),
    importExternalId: Value<String?>(
      _activityNullableString(image, 'import_external_id'),
    ),
    importProvider: Value<String?>(
      _activityNullableString(image, 'import_provider'),
    ),
    reviewFlagsJson: Value<String?>(
      _activityNullableString(image, 'review_flags_json'),
    ),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

FoodEntriesCompanion _foodEntrySyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _foodEntryCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

CompoundsCompanion _compoundCompanionFromImage(Map<String, Object?> image) {
  return CompoundsCompanion(
    name: Value<String>(_activityRequiredString(image, 'name')),
    defaultUnit: Value<String>(_activityRequiredString(image, 'default_unit')),
    defaultRoute: Value<String>(
      _activityRequiredString(image, 'default_route'),
    ),
    strength: Value<String?>(_activityNullableString(image, 'strength')),
    // Nullable-with-default: older Activity Log images predating carry
    // no `is_favorite` key, and replaying/undoing them must not throw.
    isFavorite:
        Value<bool>(_activityNullableBool(image, 'is_favorite') ?? false),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

DosesCompanion _doseCompanionFromImage(Map<String, Object?> image) {
  return DosesCompanion(
    compoundId: Value<String?>(_activityNullableString(image, 'compound_id')),
    compoundName:
        Value<String>(_activityRequiredString(image, 'compound_name')),
    compoundStrength:
        Value<String?>(_activityNullableString(image, 'compound_strength')),
    amountValue: Value<double>(_activityRequiredDouble(image, 'amount_value')),
    amountEntered: Value<String>(
      _activityRequiredString(image, 'amount_entered'),
    ),
    unit: Value<String>(_activityRequiredString(image, 'unit')),
    route: Value<String>(_activityRequiredString(image, 'route')),
    tookAt: Value<DateTime>(_activityRequiredDateTime(image, 'took_at')),
    timezone: Value<String>(_activityRequiredString(image, 'timezone')),
    localDate: Value<String>(_activityRequiredString(image, 'local_date')),
    provenance: Value<String>(_activityRequiredString(image, 'provenance')),
    // Nullable-with-default: Activity Log images predating carry no
    // `protocol_id`/`protocol_name` keys, and replaying/undoing them must not
    // throw — they simply replay as an untagged ad-hoc Dose.
    protocolId: Value<String?>(_activityNullableString(image, 'protocol_id')),
    protocolName:
        Value<String?>(_activityNullableString(image, 'protocol_name')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

ProtocolsCompanion _protocolCompanionFromImage(Map<String, Object?> image) {
  return ProtocolsCompanion(
    name: Value<String>(_activityRequiredString(image, 'name')),
    startDate: Value<DateTime>(_activityRequiredDateTime(image, 'start_date')),
    endDate: Value<DateTime?>(_activityNullableDateTime(image, 'end_date')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

ProtocolCompoundsCompanion _protocolCompoundCompanionFromImage(
  Map<String, Object?> image,
) {
  return ProtocolCompoundsCompanion(
    protocolId: Value<String>(_activityRequiredString(image, 'protocol_id')),
    compoundId: Value<String>(_activityRequiredString(image, 'compound_id')),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

SchedulesCompanion _scheduleCompanionFromImage(Map<String, Object?> image) {
  return SchedulesCompanion(
    protocolCompoundId:
        Value<String>(_activityRequiredString(image, 'protocol_compound_id')),
    doseAmountValue:
        Value<double>(_activityRequiredDouble(image, 'dose_amount_value')),
    doseAmountEntered:
        Value<String>(_activityRequiredString(image, 'dose_amount_entered')),
    doseUnit: Value<String>(_activityRequiredString(image, 'dose_unit')),
    frequency: Value<String>(_activityRequiredString(image, 'frequency')),
    route: Value<String>(_activityRequiredString(image, 'route')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

ProtocolTargetOutcomesCompanion _protocolTargetOutcomeCompanionFromImage(
  Map<String, Object?> image,
) {
  return ProtocolTargetOutcomesCompanion(
    protocolId: Value<String>(_activityRequiredString(image, 'protocol_id')),
    kind: Value<String>(_activityRequiredString(image, 'kind')),
    metricId: Value<String?>(_activityNullableString(image, 'metric_id')),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

CompoundsCompanion _compoundSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _compoundCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

DosesCompanion _doseSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _doseCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

ProtocolsCompanion _protocolSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _protocolCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

ProtocolCompoundsCompanion _protocolCompoundSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _protocolCompoundCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

SchedulesCompanion _scheduleSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _scheduleCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

ProtocolTargetOutcomesCompanion _protocolTargetOutcomeSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _protocolTargetOutcomeCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

WorkoutExercisesCompanion _workoutExerciseCompanionFromImage(
  Map<String, Object?> image,
) {
  return WorkoutExercisesCompanion(
    workoutId: Value<String>(_activityRequiredString(image, 'workout_id')),
    exerciseId: Value<String>(_activityRequiredString(image, 'exercise_id')),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

ExerciseGroupsCompanion _exerciseGroupCompanionFromImage(
  Map<String, Object?> image,
) {
  return ExerciseGroupsCompanion(
    workoutId: Value<String>(_activityRequiredString(image, 'workout_id')),
    name: Value<String>(_activityRequiredString(image, 'name')),
    colorHex: Value<String>(_activityRequiredString(image, 'color_hex')),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

ExerciseGroupMembersCompanion _exerciseGroupMemberCompanionFromImage(
  Map<String, Object?> image,
) {
  return ExerciseGroupMembersCompanion(
    groupId: Value<String>(_activityRequiredString(image, 'group_id')),
    workoutExerciseId: Value<String>(
      _activityRequiredString(image, 'workout_exercise_id'),
    ),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

WorkoutTemplatesCompanion _workoutTemplateCompanionFromImage(
  Map<String, Object?> image,
) {
  return WorkoutTemplatesCompanion(
    name: Value<String>(_activityRequiredString(image, 'name')),
    notes: Value<String?>(_activityNullableString(image, 'notes')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

TemplateExercisesCompanion _templateExerciseCompanionFromImage(
  Map<String, Object?> image,
) {
  return TemplateExercisesCompanion(
    workoutTemplateId: Value<String>(
      _activityRequiredString(image, 'workout_template_id'),
    ),
    exerciseId: Value<String>(_activityRequiredString(image, 'exercise_id')),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    note: Value<String?>(_activityNullableString(image, 'note')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

TemplateGroupsCompanion _templateGroupCompanionFromImage(
  Map<String, Object?> image,
) {
  return TemplateGroupsCompanion(
    workoutTemplateId: Value<String>(
      _activityRequiredString(image, 'workout_template_id'),
    ),
    name: Value<String>(_activityRequiredString(image, 'name')),
    colorHex: Value<String>(_activityRequiredString(image, 'color_hex')),
    rounds: Value<int>(_activityRequiredInt(image, 'rounds')),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

TemplateGroupMembersCompanion _templateGroupMemberCompanionFromImage(
  Map<String, Object?> image,
) {
  return TemplateGroupMembersCompanion(
    groupId: Value<String>(_activityRequiredString(image, 'group_id')),
    templateExerciseId: Value<String>(
      _activityRequiredString(image, 'template_exercise_id'),
    ),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

PrescriptionsCompanion _prescriptionCompanionFromImage(
  Map<String, Object?> image,
) {
  return PrescriptionsCompanion(
    templateExerciseId: Value<String>(
      _activityRequiredString(image, 'template_exercise_id'),
    ),
    mode: Value<String>(_activityRequiredString(image, 'mode')),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    repeat: Value<int>(_activityRequiredInt(image, 'repeat')),
    restAfter: Value<int?>(_activityNullableInt(image, 'rest_after')),
    loadValue: Value<double?>(_activityNullableDouble(image, 'load_value')),
    loadUnit: Value<String?>(_activityNullableString(image, 'load_unit')),
    loadEntered: Value<String?>(_activityNullableString(image, 'load_entered')),
    repsValue: Value<double?>(_activityNullableDouble(image, 'reps_value')),
    repsUnit: Value<String?>(_activityNullableString(image, 'reps_unit')),
    repsEntered: Value<String?>(_activityNullableString(image, 'reps_entered')),
    durationValue:
        Value<double?>(_activityNullableDouble(image, 'duration_value')),
    durationUnit:
        Value<String?>(_activityNullableString(image, 'duration_unit')),
    durationEntered: Value<String?>(
      _activityNullableString(image, 'duration_entered'),
    ),
    distanceValue:
        Value<double?>(_activityNullableDouble(image, 'distance_value')),
    distanceUnit:
        Value<String?>(_activityNullableString(image, 'distance_unit')),
    distanceEntered: Value<String?>(
      _activityNullableString(image, 'distance_entered'),
    ),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

TemplateLinksCompanion _templateLinkCompanionFromImage(
  Map<String, Object?> image,
) {
  return TemplateLinksCompanion(
    workoutId: Value<String>(_activityRequiredString(image, 'workout_id')),
    workoutTemplateId: Value<String>(
      _activityRequiredString(image, 'workout_template_id'),
    ),
    routineId: Value<String?>(_activityNullableString(image, 'routine_id')),
    slot: Value<int?>(_activityNullableInt(image, 'slot')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

PlanRoutinesCompanion _planRoutineCompanionFromImage(
  Map<String, Object?> image,
) {
  return PlanRoutinesCompanion(
    name: Value<String>(_activityRequiredString(image, 'name')),
    notes: Value<String?>(_activityNullableString(image, 'notes')),
    cadenceKind: Value<String?>(_activityNullableString(image, 'cadence_kind')),
    cadenceWindow: Value<int?>(_activityNullableInt(image, 'cadence_window')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

RoutineEntriesCompanion _routineEntryCompanionFromImage(
  Map<String, Object?> image,
) {
  return RoutineEntriesCompanion(
    routineId: Value<String>(_activityRequiredString(image, 'routine_id')),
    workoutTemplateId: Value<String>(
      _activityRequiredString(image, 'workout_template_id'),
    ),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    slot: Value<int?>(_activityNullableInt(image, 'slot')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

LoggedSetsCompanion _loggedSetCompanionFromImage(Map<String, Object?> image) {
  return LoggedSetsCompanion(
    workoutId: Value<String>(_activityRequiredString(image, 'workout_id')),
    exerciseId: Value<String>(_activityRequiredString(image, 'exercise_id')),
    position: Value<int>(_activityRequiredInt(image, 'position')),
    plannedRestAfter:
        Value<int?>(_activityNullableInt(image, 'planned_rest_after')),
    performedAt:
        Value<DateTime?>(_activityNullableDateTime(image, 'performed_at')),
    isCompleted: Value<bool>(
      _activityBoolWithDefault(image, 'is_completed', false),
    ),
    loadValue: Value<double?>(_activityNullableDouble(image, 'load_value')),
    loadUnit: Value<String?>(_activityNullableString(image, 'load_unit')),
    loadEntered: Value<String?>(_activityNullableString(image, 'load_entered')),
    repsValue: Value<double?>(_activityNullableDouble(image, 'reps_value')),
    repsUnit: Value<String?>(_activityNullableString(image, 'reps_unit')),
    repsEntered: Value<String?>(_activityNullableString(image, 'reps_entered')),
    durationValue:
        Value<double?>(_activityNullableDouble(image, 'duration_value')),
    durationUnit:
        Value<String?>(_activityNullableString(image, 'duration_unit')),
    durationEntered: Value<String?>(
      _activityNullableString(image, 'duration_entered'),
    ),
    distanceValue:
        Value<double?>(_activityNullableDouble(image, 'distance_value')),
    distanceUnit:
        Value<String?>(_activityNullableString(image, 'distance_unit')),
    distanceEntered: Value<String?>(
      _activityNullableString(image, 'distance_entered'),
    ),
    comment: Value<String?>(_activityNullableString(image, 'comment')),
    side: Value<String?>(_activityNullableString(image, 'side')),
    rpe: Value<double?>(_activityNullableDouble(image, 'rpe')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

LoggedSetsCompanion _loggedSetSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _loggedSetCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

RestTimersCompanion _restTimerCompanionFromImage(Map<String, Object?> image) {
  return RestTimersCompanion(
    workoutId: Value<String?>(_activityNullableString(image, 'workout_id')),
    sourceSetId:
        Value<String?>(_activityNullableString(image, 'source_set_id')),
    startedAt: Value<DateTime>(_activityRequiredDateTime(image, 'started_at')),
    deadlineAt:
        Value<DateTime>(_activityRequiredDateTime(image, 'deadline_at')),
    durationSeconds:
        Value<int>(_activityRequiredInt(image, 'duration_seconds')),
    alertVolume: Value<double>(_activityRequiredDouble(image, 'alert_volume')),
    status: Value<String>(_activityRequiredString(image, 'status')),
    alertFiredAt: Value<DateTime?>(
      _activityNullableDateTime(image, 'alert_fired_at'),
    ),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

IntervalTimersCompanion _intervalTimerCompanionFromImage(
  Map<String, Object?> image,
) {
  return IntervalTimersCompanion(
    workoutId: Value<String>(_activityRequiredString(image, 'workout_id')),
    startedAt: Value<DateTime>(_activityRequiredDateTime(image, 'started_at')),
    phaseStartedAt: Value<DateTime>(
      _activityRequiredDateTime(image, 'phase_started_at'),
    ),
    deadlineAt:
        Value<DateTime>(_activityRequiredDateTime(image, 'deadline_at')),
    currentStepIndex:
        Value<int>(_activityRequiredInt(image, 'current_step_index')),
    completedSetCount:
        Value<int>(_activityRequiredInt(image, 'completed_set_count')),
    alertVolume: Value<double>(_activityRequiredDouble(image, 'alert_volume')),
    phase: Value<String>(_activityRequiredString(image, 'phase')),
    status: Value<String>(_activityRequiredString(image, 'status')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

MeasurementsCompanion _measurementCompanionFromImage(
  Map<String, Object?> image,
) {
  return MeasurementsCompanion(
    name: Value<String>(_activityRequiredString(image, 'name')),
    unit: Value<String>(_activityRequiredString(image, 'unit')),
    goalType: Value<String>(_activityRequiredString(image, 'goal_type')),
    targetValue: Value<double?>(_activityNullableDouble(image, 'target_value')),
    enabled: Value<bool>(_activityRequiredBool(image, 'enabled')),
    sortOrder: Value<int>(_activityRequiredInt(image, 'sort_order')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

MeasurementEntriesCompanion _measurementEntryCompanionFromImage(
  Map<String, Object?> image,
) {
  return MeasurementEntriesCompanion(
    measurementId:
        Value<String>(_activityRequiredString(image, 'measurement_id')),
    value: Value<double>(_activityRequiredDouble(image, 'value')),
    valueEntered: Value<String>(
      _activityRequiredString(image, 'value_entered'),
    ),
    measuredAt:
        Value<DateTime>(_activityRequiredDateTime(image, 'measured_at')),
    comment: Value<String?>(_activityNullableString(image, 'comment')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

MetricsCompanion _metricCompanionFromImage(Map<String, Object?> image) {
  return MetricsCompanion(
    name: Value<String>(_activityRequiredString(image, 'name')),
    unit: Value<String>(_activityRequiredString(image, 'unit')),
    valueShape: Value<String>(_activityRequiredString(image, 'value_shape')),
    metricGroup: Value<String>(_activityRequiredString(image, 'metric_group')),
    goalType: Value<String?>(_activityNullableString(image, 'goal_type')),
    goalTargetValue:
        Value<double?>(_activityNullableDouble(image, 'goal_target_value')),
    enabled: Value<bool>(_activityRequiredBool(image, 'enabled')),
    pinned: Value<bool>(_activityRequiredBool(image, 'pinned')),
    sortOrder: Value<int>(_activityRequiredInt(image, 'sort_order')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

MetricsCompanion _metricSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _metricCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

MetricReadingsCompanion _metricReadingCompanionFromImage(
  Map<String, Object?> image,
) {
  return MetricReadingsCompanion(
    metricId: Value<String>(_activityRequiredString(image, 'metric_id')),
    valueJson: Value<String>(_activityRequiredString(image, 'value_json')),
    scalarValue: Value<double?>(_activityNullableDouble(image, 'scalar_value')),
    scalarEntered:
        Value<String?>(_activityNullableString(image, 'scalar_entered')),
    atTime: Value<DateTime?>(_activityNullableDateTime(image, 'at_time')),
    windowStartedAt: Value<DateTime?>(
      _activityNullableDateTime(image, 'window_started_at'),
    ),
    windowEndedAt: Value<DateTime?>(
      _activityNullableDateTime(image, 'window_ended_at'),
    ),
    provenance: Value<String>(_activityRequiredString(image, 'provenance')),
    source: Value<String>(_activityRequiredString(image, 'source')),
    externalId: Value<String?>(_activityNullableString(image, 'external_id')),
    comment: Value<String?>(_activityNullableString(image, 'comment')),
    updatedAt: Value<DateTime>(_activityRequiredDateTime(image, 'updated_at')),
    deletedAt: Value<DateTime?>(_activityNullableDateTime(image, 'deleted_at')),
  );
}

MetricReadingsCompanion _metricReadingSyncCompanionFromImage(
  Map<String, Object?> image, {
  required String syncDeviceId,
}) {
  return _metricReadingCompanionFromImage(image).copyWith(
    id: Value<String>(_activityRequiredString(image, 'id')),
    syncDeviceId: Value<String?>(syncDeviceId),
    syncPreviouslySynced: const Value<bool>(true),
  );
}

String _activityRequiredString(Map<String, Object?> image, String key) {
  final value = image[key];
  if (value is String) {
    return value;
  }
  throw StateError('Activity image field $key must be a string.');
}

String? _activityNullableString(Map<String, Object?> image, String key) {
  final value = image[key];
  if (value == null || value is String) {
    return value as String?;
  }
  throw StateError('Activity image field $key must be a string or null.');
}

int _activityRequiredInt(Map<String, Object?> image, String key) {
  final value = image[key];
  if (value is int) {
    return value;
  }
  if (value is num && value.toInt() == value) {
    return value.toInt();
  }
  throw StateError('Activity image field $key must be an integer.');
}

int? _activityNullableInt(Map<String, Object?> image, String key) {
  final value = image[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num && value.toInt() == value) {
    return value.toInt();
  }
  throw StateError('Activity image field $key must be an integer or null.');
}

double _activityRequiredDouble(Map<String, Object?> image, String key) {
  final value = image[key];
  if (value is num) {
    return value.toDouble();
  }
  throw StateError('Activity image field $key must be a number.');
}

double? _activityNullableDouble(Map<String, Object?> image, String key) {
  final value = image[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw StateError('Activity image field $key must be a number or null.');
}

bool _activityRequiredBool(Map<String, Object?> image, String key) {
  final value = image[key];
  if (value is bool) {
    return value;
  }
  throw StateError('Activity image field $key must be a boolean.');
}

bool _activityBoolWithDefault(
  Map<String, Object?> image,
  String key,
  bool defaultValue,
) {
  final value = image[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is bool) {
    return value;
  }
  throw StateError('Activity image field $key must be a boolean or absent.');
}

bool? _activityNullableBool(Map<String, Object?> image, String key) {
  final value = image[key];
  if (value == null || value is bool) {
    return value as bool?;
  }
  throw StateError('Activity image field $key must be a boolean or null.');
}

DateTime _activityRequiredDateTime(Map<String, Object?> image, String key) {
  final value = image[key];
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    return DateTime.parse(value).toUtc();
  }
  throw StateError('Activity image field $key must be a date-time string.');
}

DateTime? _activityNullableDateTime(Map<String, Object?> image, String key) {
  final value = image[key];
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    return DateTime.parse(value).toUtc();
  }
  throw StateError(
    'Activity image field $key must be a date-time string or null.',
  );
}

List<ExerciseCatalogSectionRecord> _catalogSectionsFrom(
  List<ExerciseCategoryRecord> categories,
  List<ExerciseRecord> exercises,
) {
  final categoryById = <String, ExerciseCategoryRecord>{
    for (final category in categories) category.id: category,
  };
  final shadowAwareExercises = _markShadowingUserExercises(exercises);
  final selectedExercises = _mergedExercises(shadowAwareExercises);
  final exercisesByCategoryId = <String?, List<ExerciseRecord>>{};
  for (final exercise in selectedExercises) {
    exercisesByCategoryId
        .putIfAbsent(exercise.categoryId, () => <ExerciseRecord>[])
        .add(exercise);
  }

  for (final exerciseList in exercisesByCategoryId.values) {
    exerciseList.sort(_compareExerciseRecords);
  }

  final sections = <ExerciseCatalogSectionRecord>[];
  final favoriteExercises = selectedExercises
      .where((exercise) => exercise.isFavorite)
      .toList(growable: false);
  if (favoriteExercises.isNotEmpty) {
    sections.add(
      ExerciseCatalogSectionRecord.virtualFavorites(
        exercises: List<ExerciseRecord>.unmodifiable(favoriteExercises),
      ),
    );
  }

  for (final category in categories) {
    final exerciseList = exercisesByCategoryId.remove(category.id);
    if (exerciseList == null || exerciseList.isEmpty) {
      continue;
    }

    sections.add(
      ExerciseCatalogSectionRecord(
        category: category,
        exercises: List<ExerciseRecord>.unmodifiable(exerciseList),
      ),
    );
  }

  final remainingCategoryIds = exercisesByCategoryId.keys.toList()
    ..sort((left, right) {
      if (left == null && right == null) {
        return 0;
      }
      if (left == null) {
        return 1;
      }
      if (right == null) {
        return -1;
      }
      return left.compareTo(right);
    });
  for (final categoryId in remainingCategoryIds) {
    final exerciseList = exercisesByCategoryId[categoryId]!;
    sections.add(
      ExerciseCatalogSectionRecord(
        category: categoryId == null ? null : categoryById[categoryId],
        exercises: List<ExerciseRecord>.unmodifiable(exerciseList),
      ),
    );
  }

  return List<ExerciseCatalogSectionRecord>.unmodifiable(sections);
}

List<ExerciseRecord> _mergedExercises(List<ExerciseRecord> exercises) {
  final userNames = exercises
      .where((exercise) => exercise.origin == ExerciseLibraryOrigin.user)
      .map((exercise) => _normalizeExerciseName(exercise.name))
      .toSet();
  final selected = exercises
      .where(
        (exercise) =>
            exercise.origin == ExerciseLibraryOrigin.user ||
            !userNames.contains(_normalizeExerciseName(exercise.name)),
      )
      .toList(growable: false);

  selected.sort(_compareExerciseRecords);
  return selected;
}

List<ExerciseRecord> _markShadowingUserExercises(
  List<ExerciseRecord> exercises,
) {
  final platformNames = exercises
      .where((exercise) => exercise.origin == ExerciseLibraryOrigin.platform)
      .map((exercise) => _normalizeExerciseName(exercise.name))
      .toSet();

  return exercises.map((exercise) {
    final shadowsPlatform = exercise.origin == ExerciseLibraryOrigin.user &&
        platformNames.contains(_normalizeExerciseName(exercise.name));
    return exercise.copyWith(shadowsPlatformExercise: shadowsPlatform);
  }).toList(growable: false);
}

int _compareExerciseRecords(ExerciseRecord left, ExerciseRecord right) {
  final leftName = _normalizeExerciseName(left.name);
  final rightName = _normalizeExerciseName(right.name);
  final nameComparison = leftName.compareTo(rightName);
  if (nameComparison != 0) {
    return nameComparison;
  }

  return _originRank(left.origin).compareTo(_originRank(right.origin));
}

int _originRank(ExerciseLibraryOrigin origin) {
  return switch (origin) {
    ExerciseLibraryOrigin.user => 0,
    ExerciseLibraryOrigin.platform => 1,
  };
}

String _normalizeExerciseName(String name) {
  return name.trim().toLowerCase();
}

String _normalizeExerciseNameForStorage(String name) {
  return name.trim();
}

String _normalizeCategoryName(String name) {
  return name.trim().toLowerCase();
}

String _normalizeCategoryNameForStorage(String name) {
  return name.trim();
}

String _normalizeGroupNameForStorage(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(name, 'name', 'Exercise group name is required.');
  }
  return normalized;
}

String _normalizeMealTypeForStorage(String mealType) {
  final normalized = mealType.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(
      mealType,
      'mealType',
      'Meal Type is required.',
    );
  }
  return normalized;
}

String _normalizeMealTypeName(String mealType) {
  return _normalizeMealTypeForStorage(mealType).toLowerCase();
}

String _normalizeFoodEntryNameForStorage(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(name, 'name', 'Food Entry name is required.');
  }
  return normalized;
}

String _normalizeFoodName(String name) {
  return name.trim().toLowerCase();
}

int _normalizeMealTypeSortOrder(int sortOrder) {
  if (sortOrder < 0) {
    throw ArgumentError.value(
      sortOrder,
      'sortOrder',
      'Meal Type display order must not be negative.',
    );
  }
  return sortOrder;
}

String _normalizeFoodNameForStorage(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(name, 'name', 'Food name is required.');
  }
  return normalized;
}

_NormalizedServing _normalizeServing({
  required String? label,
  required double? size,
}) {
  final normalizedLabel = _normalizeOptionalText(label);
  final normalizedSize = _normalizeOptionalPositive(size, 'servingSize');
  if ((normalizedLabel == null) != (normalizedSize == null)) {
    throw ArgumentError(
      'Serving label and serving size must be provided together.',
    );
  }
  return _NormalizedServing(normalizedLabel, normalizedSize);
}

double? _normalizeOptionalPositive(double? value, String name) {
  if (value == null) {
    return null;
  }
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, '$name must be positive.');
  }
  return value;
}

String? _normalizeOptionalText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _normalizeRequiredText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, '$name is required.');
  }
  return trimmed;
}

class _NormalizedServing {
  const _NormalizedServing(this.label, this.size);

  final String? label;
  final double? size;
}

class _NormalizedRecipeDraft {
  const _NormalizedRecipeDraft({
    required this.ingredients,
    required this.servingCount,
    required this.nutrition,
  });

  final List<RecipeIngredient> ingredients;
  final double servingCount;
  final RecipeNutrition nutrition;
}

int _nextSortOrder(List<ExerciseCategoryRow> activeRows) {
  var next = 0;
  for (final row in activeRows) {
    if (row.sortOrder >= next) {
      next = row.sortOrder + 1;
    }
  }
  return next;
}

int _nextWorkoutExercisePosition(List<WorkoutExerciseRow> activeRows) {
  var next = 0;
  for (final row in activeRows) {
    if (row.position >= next) {
      next = row.position + 1;
    }
  }
  return next;
}

int _nextExerciseGroupPosition(List<ExerciseGroupRow> activeRows) {
  var next = 0;
  for (final row in activeRows) {
    if (row.position >= next) {
      next = row.position + 1;
    }
  }
  return next;
}

String _nextCategoryColor(int index) {
  return _categoryColorPalette[index % _categoryColorPalette.length];
}

String _normalizeColorHex(String colorHex) {
  final trimmed = colorHex.trim();
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(trimmed)) {
    throw ArgumentError.value(
      colorHex,
      'colorHex',
      'Expected a #RRGGBB color.',
    );
  }
  return trimmed.toUpperCase();
}

const _categoryColorPalette = <String>[
  '#2F6FED',
  '#1F9D55',
  '#E11D48',
  '#7C3AED',
  '#EA580C',
  '#0891B2',
];

String _encodeDimensions(ExerciseType type) {
  return jsonEncode(
    type.dimensions.map((dimension) => dimension.name).toList(),
  );
}

ExerciseType _decodeDimensions(String encoded) {
  final dimensionNames = jsonDecode(encoded) as List<Object?>;
  return ExerciseType(
    dimensionNames.map((name) => DimensionId.values.byName(name! as String)),
  );
}

String _encodeEquipment(List<ExerciseEquipment> equipment) {
  return jsonEncode(_normalizedEquipmentIds(equipment));
}

List<ExerciseEquipment> _decodeEquipment(String encoded) {
  final equipmentIds = jsonDecode(encoded) as List<Object?>;
  return equipmentIds
      .whereType<String>()
      .where((id) => id.trim().isNotEmpty)
      .map(ExerciseEquipment.fromId)
      .toList(growable: false);
}

List<String> _normalizedEquipmentIds(Iterable<ExerciseEquipment> equipment) {
  final ids = <String>[];
  final seen = <String>{};
  for (final item in equipment) {
    final id = item.id.trim();
    if (id.isEmpty || !seen.add(id)) {
      continue;
    }
    ids.add(id);
  }
  return ids;
}

bool _equipmentListEquals(
  List<ExerciseEquipment> left,
  List<ExerciseEquipment> right,
) {
  final leftIds = _normalizedEquipmentIds(left);
  final rightIds = _normalizedEquipmentIds(right);
  if (leftIds.length != rightIds.length) {
    return false;
  }
  final rightIdSet = rightIds.toSet();
  return leftIds.every(rightIdSet.contains);
}

_LegacyEquipmentMigration? _legacyEquipmentMigrationFromNote(String? notes) {
  if (notes == null || !notes.startsWith(_legacyWgerAttributionPrefix)) {
    return null;
  }

  final cleanedNote = _cleanLegacyWgerAttributionNote(notes);
  if (cleanedNote == null) {
    return _LegacyEquipmentMigration(
      equipment: const <ExerciseEquipment>[],
      notes: null,
    );
  }

  final match = RegExp(r'^Equipment:\s+(.+)\.$').firstMatch(cleanedNote);
  if (match == null) {
    return cleanedNote == notes
        ? null
        : _LegacyEquipmentMigration(
            equipment: const <ExerciseEquipment>[],
            notes: cleanedNote.isEmpty ? null : cleanedNote,
          );
  }

  final equipment = match
      .group(1)!
      .split(',')
      .map((name) => _equipmentFromLegacyName(name.trim()))
      .whereType<ExerciseEquipment>()
      .toList(growable: false);
  return _LegacyEquipmentMigration(
    equipment: equipment,
    notes: null,
  );
}

String? _cleanLegacyWgerAttributionNote(String? notes) {
  if (notes == null || !notes.startsWith(_legacyWgerAttributionPrefix)) {
    return notes;
  }

  final cleaned =
      notes.substring(_legacyWgerAttributionPrefix.length).trimLeft();
  return cleaned.isEmpty ? null : cleaned;
}

const _legacyWgerAttributionPrefix = 'Adapted from the wger exercise database.';

ExerciseEquipment? _equipmentFromLegacyName(String name) {
  final id = switch (name.toLowerCase()) {
    'none (bodyweight exercise)' => 'bodyweight',
    'resistance band' => 'band',
    'pull-up bar' => 'pullUpBar',
    'incline bench' => 'inclineBench',
    'gym mat' => 'gymMat',
    'swiss ball' => 'swissBall',
    'sz-bar' => 'ezBar',
    'barbell' => 'barbell',
    'bench' => 'bench',
    'dumbbell' => 'dumbbell',
    'kettlebell' => 'kettlebell',
    'plate' => 'plate',
    _ => _equipmentIdFromLegacyName(name),
  };
  return id.isEmpty ? null : ExerciseEquipment.fromId(id);
}

String _equipmentIdFromLegacyName(String name) {
  final words = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) {
    return '';
  }

  final buffer = StringBuffer(words.first);
  for (final word in words.skip(1)) {
    buffer.write(word[0].toUpperCase());
    buffer.write(word.substring(1));
  }
  return buffer.toString();
}

class _LegacyEquipmentMigration {
  const _LegacyEquipmentMigration({
    required this.equipment,
    required this.notes,
  });

  final List<ExerciseEquipment> equipment;
  final String? notes;
}

LoggedSet _loggedSetValuesFromRow(LoggedSetRow row) {
  final values = <SetDimensionValue>[];
  _addSetValue(
    values,
    dimension: DimensionId.load,
    entered: row.loadEntered,
    unitName: row.loadUnit,
  );
  _addSetValue(
    values,
    dimension: DimensionId.reps,
    entered: row.repsEntered,
    unitName: row.repsUnit,
  );
  _addSetValue(
    values,
    dimension: DimensionId.duration,
    entered: row.durationEntered,
    unitName: row.durationUnit,
  );
  _addSetValue(
    values,
    dimension: DimensionId.distance,
    entered: row.distanceEntered,
    unitName: row.distanceUnit,
  );

  return values.isEmpty ? LoggedSet.completion() : LoggedSet.fromValues(values);
}

void _addSetValue(
  List<SetDimensionValue> values, {
  required DimensionId dimension,
  required String? entered,
  required String? unitName,
}) {
  if (entered == null || unitName == null) {
    return;
  }

  values.add(
    SetDimensionValue(
      dimension: dimension,
      entered: entered,
      unit: TrainingUnit.values.byName(unitName),
    ),
  );
}

_LoggedSetColumns _setColumns(LoggedSet set) {
  return _LoggedSetColumns(
    load: _dimensionColumns(set.valueFor(DimensionId.load)),
    reps: _dimensionColumns(set.valueFor(DimensionId.reps)),
    duration: _dimensionColumns(set.valueFor(DimensionId.duration)),
    distance: _dimensionColumns(set.valueFor(DimensionId.distance)),
  );
}

_LoggedSetColumns _loggedSetColumnsFromRow(LoggedSetRow row) {
  return _LoggedSetColumns(
    load: _DimensionColumns(
      value: row.loadValue,
      unit: row.loadUnit,
      entered: row.loadEntered,
    ),
    reps: _DimensionColumns(
      value: row.repsValue,
      unit: row.repsUnit,
      entered: row.repsEntered,
    ),
    duration: _DimensionColumns(
      value: row.durationValue,
      unit: row.durationUnit,
      entered: row.durationEntered,
    ),
    distance: _DimensionColumns(
      value: row.distanceValue,
      unit: row.distanceUnit,
      entered: row.distanceEntered,
    ),
  );
}

_DimensionColumns _dimensionColumns(SetDimensionValue? value) {
  return _DimensionColumns(
    value: value?.numericValue,
    unit: value?.unit.name,
    entered: value?.entered,
  );
}

String? _normalizeWorkoutComment(String? comment) {
  final trimmed = comment?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _normalizeSetComment(String? comment) {
  final trimmed = comment?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _normalizeMeasurementComment(String? comment) {
  final trimmed = comment?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

double? _normalizeRpe(double? rpe) {
  if (rpe == null) {
    return null;
  }
  if (rpe < 0 || rpe > 10 || (rpe * 2).roundToDouble() != rpe * 2) {
    throw ArgumentError.value(
      rpe,
      'rpe',
      'RPE must be between 0 and 10 in half-step increments.',
    );
  }
  return rpe;
}

double _normalizeAlertVolume(double volume) {
  if (volume.isNaN) {
    throw ArgumentError.value(
      volume,
      'volume',
      'Alert volume must be a number.',
    );
  }
  return volume.clamp(0, 1).toDouble();
}

LoggedSetsCompanion _loggedSetInsertCompanion({
  required String id,
  required String workoutId,
  required String exerciseId,
  required int position,
  required bool isCompleted,
  required _LoggedSetColumns columns,
  required Duration? plannedRestAfter,
  required DateTime? performedAt,
  required String? comment,
  required SetSide? side,
  required double? rpe,
  required DateTime updatedAt,
}) {
  return LoggedSetsCompanion.insert(
    id: id,
    workoutId: workoutId,
    exerciseId: exerciseId,
    position: position,
    plannedRestAfter: Value<int?>(plannedRestAfter?.inSeconds),
    performedAt: Value<DateTime?>(performedAt),
    isCompleted: Value<bool>(isCompleted),
    loadValue: Value<double?>(columns.load.value),
    loadUnit: Value<String?>(columns.load.unit),
    loadEntered: Value<String?>(columns.load.entered),
    repsValue: Value<double?>(columns.reps.value),
    repsUnit: Value<String?>(columns.reps.unit),
    repsEntered: Value<String?>(columns.reps.entered),
    durationValue: Value<double?>(columns.duration.value),
    durationUnit: Value<String?>(columns.duration.unit),
    durationEntered: Value<String?>(columns.duration.entered),
    distanceValue: Value<double?>(columns.distance.value),
    distanceUnit: Value<String?>(columns.distance.unit),
    distanceEntered: Value<String?>(columns.distance.entered),
    comment: Value<String?>(comment),
    side: Value<String?>(side?.name),
    rpe: Value<double?>(rpe),
    updatedAt: updatedAt,
  );
}

LoggedSetsCompanion _loggedSetValueCompanion(
  _LoggedSetColumns columns, {
  required DateTime updatedAt,
}) {
  return LoggedSetsCompanion(
    loadValue: Value<double?>(columns.load.value),
    loadUnit: Value<String?>(columns.load.unit),
    loadEntered: Value<String?>(columns.load.entered),
    repsValue: Value<double?>(columns.reps.value),
    repsUnit: Value<String?>(columns.reps.unit),
    repsEntered: Value<String?>(columns.reps.entered),
    durationValue: Value<double?>(columns.duration.value),
    durationUnit: Value<String?>(columns.duration.unit),
    durationEntered: Value<String?>(columns.duration.entered),
    distanceValue: Value<double?>(columns.distance.value),
    distanceUnit: Value<String?>(columns.distance.unit),
    distanceEntered: Value<String?>(columns.distance.entered),
    updatedAt: Value<DateTime>(updatedAt),
  );
}

Map<String, Object?>? _decodeImage(String? encoded) {
  if (encoded == null) {
    return null;
  }

  final decoded = jsonDecode(encoded) as Map<String, Object?>;
  return Map<String, Object?>.unmodifiable(decoded);
}

String _iso(DateTime value) => value.toUtc().toIso8601String();

String _workoutShareSummary({
  required WorkoutSessionRecord workout,
  required List<WorkoutExerciseRecord> workoutExercises,
  required List<LoggedSetRecord> sets,
  required Map<String, ExerciseRecord> exercisesById,
}) {
  final buffer = StringBuffer()
    ..writeln('Workout on ${workout.localDate.storageValue}');
  final duration = _formatWorkoutDuration(
    workout.endedAt?.difference(workout.startedAt),
  );
  if (duration != null) {
    buffer.writeln('Duration: $duration');
  }
  final comment = _normalizeWorkoutComment(workout.comment);
  if (comment != null) {
    buffer.writeln('Comment: $comment');
  }

  final exerciseIds = <String>[
    for (final workoutExercise in workoutExercises) workoutExercise.exerciseId,
  ];
  final knownIds = exerciseIds.toSet();
  for (final set in sets) {
    if (knownIds.add(set.exerciseId)) {
      exerciseIds.add(set.exerciseId);
    }
  }

  if (exerciseIds.isEmpty) {
    buffer
      ..writeln()
      ..writeln('No exercises logged.');
    return buffer.toString().trimRight();
  }

  for (final exerciseId in exerciseIds) {
    final exercise = exercisesById[exerciseId];
    final exerciseSets = sets
        .where((set) => set.exerciseId == exerciseId)
        .toList(growable: false);
    buffer
      ..writeln()
      ..writeln(exercise?.name ?? 'Unknown exercise');
    if (exerciseSets.isEmpty) {
      buffer.writeln('- No sets logged');
      continue;
    }

    for (var index = 0; index < exerciseSets.length; index += 1) {
      final set = exerciseSets[index];
      final parts = <String>[
        'Set ${index + 1}: ${_formatSetSummary(set)}',
        if (set.isCompleted) 'completed',
        if (set.side != null) set.side!.name,
        if (set.rpe != null) 'RPE ${_formatDecimal(set.rpe!)}',
      ];
      buffer.writeln('- ${parts.join(' | ')}');
      final setComment = _normalizeSetComment(set.comment);
      if (setComment != null) {
        buffer.writeln('  Note: $setComment');
      }
    }
  }

  return buffer.toString().trimRight();
}

String? _formatWorkoutDuration(Duration? duration) {
  if (duration == null || duration.isNegative) {
    return null;
  }

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return '${minutes}m';
  }
  return '${seconds}s';
}

String _formatSetSummary(LoggedSetRecord set) {
  final load = set.values.load;
  final reps = set.values.reps;
  final duration = set.values.duration;
  final distance = set.values.distance;
  if (load != null && reps != null) {
    return '${load.entered} ${_unitLabel(load.unit)} x '
        '${reps.entered} ${_unitLabel(reps.unit)}';
  }
  if (distance != null && duration != null) {
    return '${distance.entered} ${_unitLabel(distance.unit)} in '
        '${duration.entered} ${_unitLabel(duration.unit)}';
  }

  final parts = set.values.values.values
      .map((value) => '${value.entered} ${_unitLabel(value.unit)}')
      .toList(growable: false);
  return parts.isEmpty ? 'Completed' : parts.join(', ');
}

String _formatDecimal(double value) {
  final rounded = value.roundToDouble();
  return rounded == value ? rounded.toInt().toString() : value.toString();
}

String _unitLabel(TrainingUnit unit) {
  return switch (unit) {
    TrainingUnit.kilogram => 'kg',
    TrainingUnit.pound => 'lb',
    TrainingUnit.repetition => 'reps',
    TrainingUnit.second => 'sec',
    TrainingUnit.kilometer => 'km',
    TrainingUnit.mile => 'mi',
  };
}
