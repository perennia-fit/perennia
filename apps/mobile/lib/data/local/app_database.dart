import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/training/training_day.dart';

part 'app_database.g.dart';

@DataClassName('ExerciseCategoryRow')
class ExerciseCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();
  TextColumn get colorHex => text()();
  // an Exercise Category syncs as an ordinary LWW row,
  // mirroring `Compounds`/`Protocols`.
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ExerciseRow')
class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get libraryOrigin => text().withDefault(const Constant('user'))();
  TextColumn get name => text()();
  TextColumn get dimensionIds => text()();
  TextColumn get defaultLoadUnit =>
      text().withDefault(const Constant('kilogram'))();
  TextColumn get loadMode => text().withDefault(const Constant('added'))();
  TextColumn get recordProfile => text().withDefault(
        const Constant('repMax'),
      )();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isUnilateral => boolean().withDefault(const Constant(false))();
  BoolColumn get usesRpe => boolean().withDefault(const Constant(false))();
  TextColumn get categoryId =>
      text().nullable().references(ExerciseCategories, #id)();
  TextColumn get equipmentIds => text().withDefault(const Constant('[]'))();
  TextColumn get notes => text().nullable()();
  // only User Library exercises (and user customizations of a
  // Platform exercise, i.e. a shadowing copy per) sync — the Platform
  // Library itself is a deterministic bundled seed and never
  // crosses the server. `_pushPendingExerciseRows`/pull application only ever
  // touch rows with `libraryOrigin == user`.
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WorkoutSessionRow')
class WorkoutSessions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get startedAt => dateTime()();
  TextColumn get timezone => text()();
  TextColumn get localDate =>
      text().withDefault(const Constant('1970-01-01'))();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get comment => text().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MealTypeRow')
@TableIndex(name: 'meal_types_sort_order_index', columns: {#sortOrder})
class MealTypes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MealRow')
@TableIndex(name: 'meals_local_date_index', columns: {#localDate})
class Meals extends Table {
  TextColumn get id => text()();
  TextColumn get mealType => text()();
  DateTimeColumn get startedAt => dateTime()();
  TextColumn get timezone => text()();
  TextColumn get localDate =>
      text().withDefault(const Constant('1970-01-01'))();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FoodRow')
@TableIndex(name: 'foods_source_name_index', columns: {#foodSource, #name})
class Foods extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get foodSource => text().withDefault(const Constant('user'))();
  TextColumn get nutrientValuesJson => text()();
  BoolColumn get isLiquid => boolean().withDefault(const Constant(false))();
  TextColumn get servingLabel => text().nullable()();
  RealColumn get servingSize => real().nullable()();
  RealColumn get packageSize => real().nullable()();
  TextColumn get recipeIngredientsJson => text().nullable()();
  RealColumn get recipeServingCount => real().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FoodEntryRow')
@TableIndex(name: 'food_entries_meal_id_index', columns: {#mealId})
@TableIndex(
  name: 'food_entries_import_source_external_id_index',
  columns: {#importSource, #importExternalId},
)
class FoodEntries extends Table {
  TextColumn get id => text()();
  TextColumn get mealId => text().references(Meals, #id)();
  TextColumn get entryKind =>
      text().withDefault(const Constant('quickEntry'))();
  IntColumn get position => integer()();
  TextColumn get name => text()();
  TextColumn get nutrientValuesJson => text()();
  TextColumn get foodId => text().nullable()();
  TextColumn get portionJson => text().nullable()();
  TextColumn get foodSource => text().nullable()();
  BoolColumn get isLiquid => boolean().nullable()();
  TextColumn get servingLabel => text().nullable()();
  RealColumn get servingSize => real().nullable()();
  RealColumn get packageSize => real().nullable()();
  TextColumn get importSource => text().nullable()();
  TextColumn get importExternalId => text().nullable()();
  TextColumn get importProvider => text().nullable()();
  TextColumn get reviewFlagsJson => text().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('OpenFoodFactsCacheRow')
@TableIndex(
  name: 'open_food_facts_cache_last_accessed_at_index',
  columns: {#lastAccessedAt},
)
class OpenFoodFactsCache extends Table {
  TextColumn get lookupKey => text()();
  TextColumn get foodId => text()();
  TextColumn get name => text()();
  TextColumn get nutrientValuesJson => text()();
  BoolColumn get isLiquid => boolean().withDefault(const Constant(false))();
  TextColumn get servingLabel => text().nullable()();
  RealColumn get servingSize => real().nullable()();
  RealColumn get packageSize => real().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();
  DateTimeColumn get lastAccessedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {lookupKey};
}

@DataClassName('NutritionGoalRow')
@TableIndex(name: 'nutrition_goals_nutrient_id_index', columns: {#nutrientId})
class NutritionGoals extends Table {
  TextColumn get id => text()();
  TextColumn get nutrientId => text()();
  RealColumn get targetValue => real()();
  TextColumn get targetEntered => text()();
  TextColumn get unit => text()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The account-level half of `AppSettings` as a synced singleton
/// row: one row per user, keyed by a stable well-known client id. Fields are
/// stored as typed columns so the row is self-describing; the sync payload
/// converts them to the snake_case shape the server and agent use. Device-level
/// settings (screen-on, crash reporting, auto-backup) never live here — they
/// stay in the local `settings.json`. LWW on `updatedAt`; a settings row is
/// overwritten, never archived, so `deletedAt` stays null.
@DataClassName('UserSettingsRow')
class UserSettings extends Table {
  TextColumn get id => text()();
  TextColumn get themePreference => text()();
  TextColumn get unitSystem => text()();
  TextColumn get weekStartDay => text()();
  RealColumn get defaultWeightIncrement => real()();
  TextColumn get homeScreenDisplay => text()();
  BoolColumn get prTrackingEnabled => boolean()();
  BoolColumn get markSetsCompleteByDefault => boolean()();
  BoolColumn get autoSelectNextSet => boolean()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WorkoutExerciseRow')
@TableIndex(name: 'workout_exercises_workout_id_index', columns: {#workoutId})
class WorkoutExercises extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId => text().references(WorkoutSessions, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get position => integer()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ExerciseGroupRow')
@TableIndex(name: 'exercise_groups_workout_id_index', columns: {#workoutId})
class ExerciseGroups extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId => text().references(WorkoutSessions, #id)();
  TextColumn get name => text()();
  TextColumn get colorHex => text()();
  IntColumn get position => integer()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ExerciseGroupMemberRow')
@TableIndex(
  name: 'exercise_group_members_group_id_index',
  columns: {#groupId},
)
@TableIndex(
  name: 'exercise_group_members_workout_exercise_id_index',
  columns: {#workoutExerciseId},
)
class ExerciseGroupMembers extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text().references(ExerciseGroups, #id)();
  TextColumn get workoutExerciseId =>
      text().references(WorkoutExercises, #id)();
  IntColumn get position => integer()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('WorkoutTemplateRow')
@TableIndex(name: 'workout_templates_name_index', columns: {#name})
class WorkoutTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TemplateExerciseRow')
@TableIndex(
  name: 'template_exercises_template_id_index',
  columns: {#workoutTemplateId},
)
@TableIndex(
  name: 'template_exercises_exercise_id_index',
  columns: {#exerciseId},
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX template_exercises_active_exercise_unique '
  'ON template_exercises (workout_template_id, exercise_id) '
  'WHERE deleted_at IS NULL',
)
class TemplateExercises extends Table {
  TextColumn get id => text()();
  TextColumn get workoutTemplateId =>
      text().references(WorkoutTemplates, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get position => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TemplateGroupRow')
@TableIndex(
  name: 'template_groups_template_id_index',
  columns: {#workoutTemplateId},
)
class TemplateGroups extends Table {
  TextColumn get id => text()();
  TextColumn get workoutTemplateId =>
      text().references(WorkoutTemplates, #id)();
  TextColumn get name => text()();
  TextColumn get colorHex => text()();
  IntColumn get rounds => integer().withDefault(const Constant(1))();
  IntColumn get position => integer()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const <String>[
        'CHECK (rounds >= 1)',
      ];
}

@DataClassName('TemplateGroupMemberRow')
@TableIndex(
  name: 'template_group_members_group_id_index',
  columns: {#groupId},
)
@TableIndex(
  name: 'template_group_members_template_exercise_id_index',
  columns: {#templateExerciseId},
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX template_group_members_active_exercise_unique '
  'ON template_group_members (template_exercise_id) '
  'WHERE deleted_at IS NULL',
)
class TemplateGroupMembers extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text().references(TemplateGroups, #id)();
  TextColumn get templateExerciseId =>
      text().references(TemplateExercises, #id)();
  IntColumn get position => integer()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PrescriptionRow')
@TableIndex(
  name: 'prescriptions_template_exercise_id_index',
  columns: {#templateExerciseId},
)
class Prescriptions extends Table {
  TextColumn get id => text()();
  TextColumn get templateExerciseId =>
      text().references(TemplateExercises, #id)();
  TextColumn get mode => text().withDefault(const Constant('fixed'))();
  IntColumn get position => integer()();
  IntColumn get repeat => integer().withDefault(const Constant(1))();
  IntColumn get restAfter => integer().nullable()();

  // Self-describing planned values mirror LoggedSets. Entered text is the
  // source of truth; numeric projections support validation/materialization.
  RealColumn get loadValue => real().nullable()();
  TextColumn get loadUnit => text().nullable()();
  TextColumn get loadEntered => text().nullable()();
  RealColumn get repsValue => real().nullable()();
  TextColumn get repsUnit => text().nullable()();
  TextColumn get repsEntered => text().nullable()();
  RealColumn get durationValue => real().nullable()();
  TextColumn get durationUnit => text().nullable()();
  TextColumn get durationEntered => text().nullable()();
  RealColumn get distanceValue => real().nullable()();
  TextColumn get distanceUnit => text().nullable()();
  TextColumn get distanceEntered => text().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TemplateLinkRow')
@TableIndex(
  name: 'template_links_workout_id_unique',
  columns: {#workoutId},
  unique: true,
)
@TableIndex(
  name: 'template_links_template_id_index',
  columns: {#workoutTemplateId},
)
@TableIndex(
  name: 'template_links_routine_id_index',
  columns: {#routineId},
)
class TemplateLinks extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId => text().references(WorkoutSessions, #id)();
  TextColumn get workoutTemplateId =>
      text().references(WorkoutTemplates, #id)();

  TextColumn get routineId => text().nullable().references(PlanRoutines, #id)();
  IntColumn get slot => integer().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LoggedSetRow')
@TableIndex(name: 'logged_sets_workout_id_index', columns: {#workoutId})
@TableIndex(name: 'logged_sets_exercise_id_index', columns: {#exerciseId})
class LoggedSets extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId => text().references(WorkoutSessions, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get position => integer()();
  IntColumn get plannedRestAfter => integer().nullable()();
  DateTimeColumn get performedAt => dateTime().nullable()();

  // Numeric projections support future SQL analytics; entered text remains
  // the source of truth for reconstructing the self-describing domain value.
  RealColumn get loadValue => real().nullable()();
  TextColumn get loadUnit => text().nullable()();
  TextColumn get loadEntered => text().nullable()();
  RealColumn get repsValue => real().nullable()();
  TextColumn get repsUnit => text().nullable()();
  TextColumn get repsEntered => text().nullable()();
  RealColumn get durationValue => real().nullable()();
  TextColumn get durationUnit => text().nullable()();
  TextColumn get durationEntered => text().nullable()();
  RealColumn get distanceValue => real().nullable()();
  TextColumn get distanceUnit => text().nullable()();
  TextColumn get distanceEntered => text().nullable()();
  TextColumn get comment => text().nullable()();
  TextColumn get side => text().nullable()();
  RealColumn get rpe => real().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(
        const Constant(false),
      )();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('RestTimerRow')
@TableIndex(name: 'rest_timers_workout_id_index', columns: {#workoutId})
class RestTimers extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId =>
      text().nullable().references(WorkoutSessions, #id)();
  TextColumn get sourceSetId => text().nullable().references(LoggedSets, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get deadlineAt => dateTime()();
  IntColumn get durationSeconds => integer()();
  RealColumn get alertVolume => real().withDefault(const Constant(1.0))();
  TextColumn get status => text().withDefault(const Constant('running'))();
  DateTimeColumn get alertFiredAt => dateTime().nullable()();
  // fire-once marker for the 3-2-1 prepare cue (remaining <= 3s),
  // persisted like `alertFiredAt` so a panel remount never re-fires it.
  DateTimeColumn get prepareAlertFiredAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('IntervalTimerRow')
@TableIndex(name: 'interval_timers_workout_id_index', columns: {#workoutId})
class IntervalTimers extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId => text().references(WorkoutSessions, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get phaseStartedAt => dateTime()();
  DateTimeColumn get deadlineAt => dateTime()();
  IntColumn get currentStepIndex => integer().withDefault(
        const Constant(0),
      )();
  IntColumn get completedSetCount => integer().withDefault(
        const Constant(0),
      )();
  RealColumn get alertVolume => real().withDefault(const Constant(1.0))();
  TextColumn get phase => text().withDefault(const Constant('work'))();
  TextColumn get status => text().withDefault(const Constant('running'))();
  // fire-once marker for the current phase's 3-2-1 prepare cue. Reset
  // to null on every phase advance so each phase-end gets its own cue.
  DateTimeColumn get prepareAlertFiredAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MeasurementRow')
@TableIndex(name: 'measurements_sort_order_index', columns: {#sortOrder})
class Measurements extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get unit => text()();
  TextColumn get goalType => text()();
  RealColumn get targetValue => real().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MeasurementEntryRow')
@TableIndex(
  name: 'measurement_entries_measurement_id_index',
  columns: {#measurementId},
)
@TableIndex(
  name: 'measurement_entries_measured_at_index',
  columns: {#measuredAt},
)
class MeasurementEntries extends Table {
  TextColumn get id => text()();
  TextColumn get measurementId => text().references(Measurements, #id)();
  RealColumn get value => real()();
  TextColumn get valueEntered => text()();
  DateTimeColumn get measuredAt => dateTime()();
  TextColumn get comment => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MetricRow')
@TableIndex(name: 'metrics_sort_order_index', columns: {#sortOrder})
class Metrics extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get unit => text()();
  TextColumn get valueShape => text()();
  TextColumn get metricGroup => text()();
  TextColumn get goalType => text().nullable()();
  RealColumn get goalTargetValue => real().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MetricReadingRow')
@TableIndex(name: 'metric_readings_metric_id_index', columns: {#metricId})
@TableIndex(name: 'metric_readings_at_time_index', columns: {#atTime})
@TableIndex(
  name: 'metric_readings_source_external_id_index',
  columns: {#source, #externalId},
)
class MetricReadings extends Table {
  TextColumn get id => text()();
  TextColumn get metricId => text().references(Metrics, #id)();
  TextColumn get valueJson => text()();
  RealColumn get scalarValue => real().nullable()();
  TextColumn get scalarEntered => text().nullable()();
  DateTimeColumn get atTime => dateTime().nullable()();
  DateTimeColumn get windowStartedAt => dateTime().nullable()();
  DateTimeColumn get windowEndedAt => dateTime().nullable()();
  TextColumn get provenance => text()();
  TextColumn get source => text()();
  TextColumn get externalId => text().nullable()();
  TextColumn get comment => text().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// The Protocols catalogue entry (CONTEXT.md `Compound`): an item the user takes
// and tracks. A user-owned template carrying a name + default unit/route and an
// optional strength; NEVER categorized by substance type or legality
// (the genericity is the legal posture). Mirrors `Foods`/`Exercises`:
// archives via `deleted_at`, never cascades.
@DataClassName('CompoundRow')
@TableIndex(name: 'compounds_name_index', columns: {#name})
class Compounds extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  // Default unit/route store the curated registry enum `.name`: the
  // domain rejects any value outside the sealed `DoseUnit`/`DoseRoute`
  // registries on the way in and out, never free-text.
  TextColumn get defaultUnit => text()();
  TextColumn get defaultRoute => text()();

  // Optional strength/concentration stored as its canonical curated label (e.g.
  // "5 mg/capsule"): the structured `CompoundStrength` (curated units) serializes
  // here. The resolved active mass is derived from it on read, never stored.
  //
  TextColumn get strength => text().nullable()();

  // A UI-affordance flag only, mirroring `Exercises.isFavorite`: a
  // favourited Compound hoists into a virtual "Favorites" section atop the
  // Compound list. Never categorizes the Compound itself.
  BoolColumn get isFavorite => boolean().withDefault(
        const Constant(false),
      )();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// A single recorded administration (CONTEXT.md `Dose`): a self-describing,
// standalone timestamped event (no `Workout`-style container, PROTOCOLS.md §1.2)
// that snapshots its `Compound` at log time (name + structured strength/
//). `compoundId` is a SOFT reference (text nullable, NOT a Drift FK,
// exactly like `FoodEntries.foodId`) so a `Dose` renders without its `Compound`.
// Captures its timezone and freezes its local date at log time. A
// `Dose` is authored intake, never a `Metric`; hard-delete tombstones
// via `deleted_at`, recoverable through the Activity Log, never cascades.
@DataClassName('DoseRow')
@TableIndex(name: 'doses_local_date_index', columns: {#localDate})
@TableIndex(name: 'doses_compound_id_index', columns: {#compoundId})
class Doses extends Table {
  TextColumn get id => text()();

  // Soft reference to the catalogue `Compound`, nullable so archiving/deleting
  // the Compound never breaks a logged Dose (no `.references()` FK).
  TextColumn get compoundId => text().nullable()();

  // Denormalized snapshot so a Dose renders without its Compound (§1.1). The
  // name AND the strength/concentration are frozen at log time: editing,
  // archiving, or deleting the Compound NEVER rewrites a logged Dose.
  TextColumn get compoundName => text()();
  TextColumn get compoundStrength => text().nullable()();

  // Amount stored values-as-entered: a numeric projection + the raw entered
  // string (source of truth) + unit, mirroring LoggedSets' triplet / Portion's
  // entered string.
  RealColumn get amountValue => real()();
  TextColumn get amountEntered => text()();
  TextColumn get unit => text()();
  TextColumn get route => text()();

  // UTC instant + captured timezone + frozen local date (YYYY-MM-DD).
  DateTimeColumn get tookAt => dateTime()();
  TextColumn get timezone => text()();
  TextColumn get localDate =>
      text().withDefault(const Constant('1970-01-01'))();

  // Provenance stamp (manual/integration/agent), as elsewhere (PROTOCOLS.md §7).
  TextColumn get provenance => text().withDefault(const Constant('manual'))();

  // The OPTIONAL tag to a `Protocol` (PROTOCOLS.md §1.4, §1.2): a
  // SOFT reference (nullable, NOT a Drift FK — mirrors `compoundId` above) so
  // archiving/editing the Protocol never breaks a logged Dose, and the Dose
  // never depends on a live Protocol row to render. The Protocol's name is
  // snapshotted alongside it at tag time so the Dose keeps rendering its own
  // attribution even if the Protocol is later renamed or archived (§1.1
  // self-description holds). Null means an untagged, fully first-class
  // ad-hoc Dose.
  TextColumn get protocolId => text().nullable()();
  TextColumn get protocolName => text().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// A `Protocol` (CONTEXT.md): the Routine analog — a named, time-bounded plan
// associating one or more `Compound`s (a multi-Compound Protocol is a
// "stack", PROTOCOLS.md §1.4). A **mutable plan**: creating or editing it
// never reads or writes a logged `Dose`. Archives via `deleted_at`, never
// cascades (PROTOCOLS.md §7). `end_date` nullable means an open-ended
// (ongoing) course. Syncs as an ordinary opaque-payload LWW row (
// PROTOCOLS.md §7) — `syncDeviceId`/`syncPreviouslySynced` mirror `Compounds`.
@DataClassName('ProtocolRow')
class Protocols extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// A `Protocol`'s member `Compound` (PROTOCOLS.md §1.4): the ordered join
// between a `Protocol` and a catalogue `Compound`. A LIVE reference (a Drift
// FK, like `RoutineExercises.exerciseId`) — a Protocol is a plan, not a
// self-describing logged event, so it reads the current Compound rather than
// snapshotting it (contrast `Doses.compoundId`, a soft reference).
@DataClassName('ProtocolCompoundRow')
@TableIndex(
  name: 'protocol_compounds_protocol_id_index',
  columns: {#protocolId},
)
@TableIndex(
  name: 'protocol_compounds_compound_id_index',
  columns: {#compoundId},
)
class ProtocolCompounds extends Table {
  TextColumn get id => text()();
  TextColumn get protocolId => text().references(Protocols, #id)();
  TextColumn get compoundId => text().references(Compounds, #id)();
  IntColumn get position => integer()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// A `Schedule` (CONTEXT.md, PROTOCOLS.md §1.4): the `Prescription` analog —
// an OPTIONAL planned dose · frequency · route for one member `Compound` of a
// `Protocol` (a `ProtocolCompound` row). A LIVE reference (a Drift FK, like
// `ProtocolCompounds.compoundId`) — a Schedule is part of the mutable plan,
// never a logged event, so it is never a self-describing snapshot. Purely
// prescriptive: dose-response analysis is ALWAYS derived from the actual
// logged `Dose`s, never a Schedule. Archives via `deleted_at`, never
// cascades to a logged `Dose` (PROTOCOLS.md §7).
@DataClassName('ScheduleRow')
@TableIndex(
  name: 'schedules_protocol_compound_id_index',
  columns: {#protocolCompoundId},
)
class Schedules extends Table {
  TextColumn get id => text()();
  TextColumn get protocolCompoundId =>
      text().references(ProtocolCompounds, #id)();

  // The planned dose amount, mirroring Doses' values-as-entered triplet
  // (numeric projection + entered string, source of truth) + curated unit
  // (PROTOCOLS.md §1.3).
  RealColumn get doseAmountValue => real()();
  TextColumn get doseAmountEntered => text()();
  TextColumn get doseUnit => text()();

  // The curated frequency registry name — never free-text.
  TextColumn get frequency => text()();

  // The curated route registry name, same registry as `Doses.route`.
  TextColumn get route => text()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// A `Protocol`'s declared target outcome (CONTEXT.md `Effect`, PROTOCOLS.md
// §1.4, §4): WHICH `Metric`/performance to correlate, seeding the
// later `Effect` view (M29) — plan data only, NO analysis computed or stored
// here. A LIVE reference to `Metrics` for a `metric`-kind row (a Drift FK,
// like `ProtocolCompounds.compoundId` — Metrics only ever archive via
// `deleted_at`, never truly delete); null for a `performance`-kind row, which
// has no Metric row to reference. Archives alongside the Protocol's own
// reconciliation, never touches a logged `Dose`.
@DataClassName('ProtocolTargetOutcomeRow')
@TableIndex(
  name: 'protocol_target_outcomes_protocol_id_index',
  columns: {#protocolId},
)
class ProtocolTargetOutcomes extends Table {
  TextColumn get id => text()();
  TextColumn get protocolId => text().references(Protocols, #id)();

  // The curated outcome-kind registry name — 'metric' or
  // 'performance'; never free-text.
  TextColumn get kind => text()();

  // Populated only for a 'metric'-kind row; null for 'performance'.
  TextColumn get metricId => text().nullable().references(Metrics, #id)();
  IntColumn get position => integer()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MonitoringSeriesCacheRow')
@TableIndex(
  name: 'monitoring_series_cache_last_accessed_at_index',
  columns: {#lastAccessedAt},
)
class MonitoringSeriesCache extends Table {
  TextColumn get seriesId => text()();
  TextColumn get source => text()();
  TextColumn get externalId => text()();
  TextColumn get seriesType => text()();
  TextColumn get encoding => text()();
  TextColumn get compression => text()();
  BlobColumn get blobData => blob().named('blob')();
  IntColumn get byteLength => integer()();
  DateTimeColumn get fetchedAt => dateTime()();
  DateTimeColumn get lastAccessedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {seriesId};
}

// The log is append-only; updated_at/deleted_at exist for schema uniformity.
@DataClassName('ActivityLogRow')
@TableIndex(name: 'activity_log_batch_id_index', columns: {#batchId})
@TableIndex.sql(
  'CREATE INDEX activity_log_pending_sync_index '
  'ON activity_log (entity_table) '
  'WHERE deleted_at IS NULL '
  'AND sync_acknowledged_at IS NULL '
  'AND after_image IS NOT NULL',
)
class ActivityLog extends Table {
  TextColumn get id => text()();
  TextColumn get actor => text()();
  TextColumn get batchId => text()();
  TextColumn get entityTable => text()();
  TextColumn get entityId => text()();
  TextColumn get beforeImage => text().nullable()();
  TextColumn get afterImage => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get syncAcknowledgedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncStateRow')
class SyncStates extends Table {
  TextColumn get id => text()();
  TextColumn get pullCursor => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('idle'))();
  DateTimeColumn get lastSuccessfulSyncAt => dateTime().nullable()();
  DateTimeColumn get firstFailureAt => dateTime().nullable()();
  DateTimeColumn get lastFailureAt => dateTime().nullable()();
  TextColumn get lastFailureMessage => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('IntegrationDataClassConsentRow')
@TableIndex(
  name: 'integration_data_class_consents_credential_data_class_index',
  columns: {#credentialId, #dataClass},
)
class IntegrationDataClassConsents extends Table {
  TextColumn get id => text()();
  TextColumn get credentialId => text()();
  TextColumn get dataClass => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The redesigned Routine plan entity: a named reference to Workout Templates,
/// with an optional Cadence, rather than a rigid ordered program.
///
/// The physical name deliberately differs from the legacy `routines` table so
/// both models can coexist until the greenfield cutover removes the old six-
/// table ownership tree.
@DataClassName('PlanRoutineRow')
@TableIndex(name: 'plan_routines_name_index', columns: {#name})
class PlanRoutines extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get cadenceKind => text().nullable()();
  IntColumn get cadenceWindow => integer().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One ordered reference from a redesigned Routine to a Workout Template.
///
/// There is intentionally no uniqueness constraint on the template reference:
/// a later Cadence may place the same Template on more than one slot.
@DataClassName('RoutineEntryRow')
@TableIndex(name: 'routine_entries_routine_id_index', columns: {#routineId})
@TableIndex(
  name: 'routine_entries_template_id_index',
  columns: {#workoutTemplateId},
)
class RoutineEntries extends Table {
  TextColumn get id => text()();
  TextColumn get routineId => text().references(PlanRoutines, #id)();
  TextColumn get workoutTemplateId =>
      text().references(WorkoutTemplates, #id)();
  IntColumn get position => integer()();
  IntColumn get slot => integer().nullable()();
  TextColumn get syncDeviceId => text().nullable()();
  BoolColumn get syncPreviouslySynced => boolean().withDefault(
        const Constant(false),
      )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: <Type>[
    ExerciseCategories,
    Exercises,
    WorkoutSessions,
    MealTypes,
    Meals,
    Foods,
    FoodEntries,
    NutritionGoals,
    OpenFoodFactsCache,
    WorkoutExercises,
    ExerciseGroups,
    ExerciseGroupMembers,
    LoggedSets,
    RestTimers,
    IntervalTimers,
    ActivityLog,
    SyncStates,
    Measurements,
    MeasurementEntries,
    Metrics,
    MetricReadings,
    Compounds,
    Doses,
    Protocols,
    ProtocolCompounds,
    Schedules,
    ProtocolTargetOutcomes,
    MonitoringSeriesCache,
    IntegrationDataClassConsents,
    UserSettings,
    WorkoutTemplates,
    TemplateExercises,
    TemplateGroups,
    TemplateGroupMembers,
    Prescriptions,
    TemplateLinks,
    PlanRoutines,
    RoutineEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.inMemory() {
    return AppDatabase(NativeDatabase.memory());
  }

  factory AppDatabase.openFile(File file) {
    return AppDatabase(NativeDatabase(file));
  }

  factory AppDatabase.openDefault() {
    return AppDatabase(
      LazyDatabase(() async {
        final directory = await getApplicationDocumentsDirectory();
        final file =
            File(path.join(directory.path, 'open_workout_logger.sqlite'));
        return NativeDatabase(file);
      }),
    );
  }

  static const exerciseCategoriesTable = 'exercise_categories';
  static const exercisesTable = 'exercises';
  static const workoutSessionsTable = 'workout_sessions';
  static const mealTypesTable = 'meal_types';
  static const mealsTable = 'meals';
  static const foodsTable = 'foods';
  static const foodEntriesTable = 'food_entries';
  static const nutritionGoalsTable = 'nutrition_goals';
  static const openFoodFactsCacheTable = 'open_food_facts_cache';
  static const workoutExercisesTable = 'workout_exercises';
  static const exerciseGroupsTable = 'exercise_groups';
  static const exerciseGroupMembersTable = 'exercise_group_members';
  static const workoutTemplatesTable = 'workout_templates';
  static const templateExercisesTable = 'template_exercises';
  static const templateGroupsTable = 'template_groups';
  static const templateGroupMembersTable = 'template_group_members';
  static const planRoutinesTable = 'plan_routines';
  static const routineEntriesTable = 'routine_entries';
  static const prescriptionsTable = 'prescriptions';
  static const templateLinksTable = 'template_links';
  static const loggedSetsTable = 'logged_sets';
  static const restTimersTable = 'rest_timers';
  static const intervalTimersTable = 'interval_timers';
  static const measurementsTable = 'measurements';
  static const measurementEntriesTable = 'measurement_entries';
  static const metricsTable = 'metrics';
  static const metricReadingsTable = 'metric_readings';
  static const compoundsTable = 'compounds';
  static const dosesTable = 'doses';
  static const protocolsTable = 'protocols';
  static const protocolCompoundsTable = 'protocol_compounds';
  static const schedulesTable = 'schedules';
  static const protocolTargetOutcomesTable = 'protocol_target_outcomes';
  static const monitoringSeriesCacheTable = 'monitoring_series_cache';
  static const integrationDataClassConsentsTable =
      'integration_data_class_consents';
  static const activityLogTable = 'activity_log';
  static const syncStatesTable = 'sync_states';
  static const userSettingsTable = 'user_settings';

  static const tableNames = <String>[
    exerciseCategoriesTable,
    exercisesTable,
    workoutSessionsTable,
    mealTypesTable,
    mealsTable,
    foodsTable,
    foodEntriesTable,
    nutritionGoalsTable,
    workoutExercisesTable,
    exerciseGroupsTable,
    exerciseGroupMembersTable,
    workoutTemplatesTable,
    templateExercisesTable,
    templateGroupsTable,
    templateGroupMembersTable,
    planRoutinesTable,
    routineEntriesTable,
    prescriptionsTable,
    templateLinksTable,
    loggedSetsTable,
    restTimersTable,
    intervalTimersTable,
    measurementsTable,
    measurementEntriesTable,
    metricsTable,
    metricReadingsTable,
    compoundsTable,
    dosesTable,
    protocolsTable,
    protocolCompoundsTable,
    schedulesTable,
    protocolTargetOutcomesTable,
    userSettingsTable,
    activityLogTable,
  ];

  static const schemaTableNames = <String>[
    ...tableNames,
    monitoringSeriesCacheTable,
    openFoodFactsCacheTable,
    integrationDataClassConsentsTable,
    syncStatesTable,
  ];

  @override
  int get schemaVersion => 57;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => migrator.createAll(),
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.createTable(exerciseCategories);
            await migrator.addColumn(exercises, exercises.libraryOrigin);
            await migrator.addColumn(exercises, exercises.categoryId);
            await migrator.addColumn(exercises, exercises.notes);
          }
          if (from < 3) {
            await migrator.addColumn(exercises, exercises.defaultLoadUnit);
          }
          if (from < 4) {
            await migrator.addColumn(exercises, exercises.loadMode);
            await migrator.addColumn(exercises, exercises.recordProfile);
            await _backfillExerciseRecordProfiles();
          }
          if (from < 5) {
            await migrator.addColumn(exercises, exercises.isFavorite);
          }
          if (from < 6) {
            await migrator.addColumn(
              workoutSessions,
              workoutSessions.localDate,
            );
            await _backfillWorkoutSessionLocalDates();
          }
          if (from < 7) {
            await migrator.createTable(workoutExercises);
          }
          if (from < 8) {
            await migrator.addColumn(loggedSets, loggedSets.isCompleted);
          }
          if (from < 9) {
            await migrator.addColumn(exercises, exercises.isUnilateral);
            await migrator.addColumn(exercises, exercises.usesRpe);
            await migrator.addColumn(loggedSets, loggedSets.comment);
            await migrator.addColumn(loggedSets, loggedSets.side);
            await migrator.addColumn(loggedSets, loggedSets.rpe);
          }
          if (from < 10) {
            await migrator.addColumn(workoutSessions, workoutSessions.comment);
          }
          if (from < 11) {
            await migrator.createTable(exerciseGroups);
            await migrator.createTable(exerciseGroupMembers);
          }
          if (from < 15) {
            await migrator.addColumn(loggedSets, loggedSets.plannedRestAfter);
          }
          if (from < 16) {
            await migrator.createTable(restTimers);
          }
          if (from < 17) {
            await migrator.createTable(intervalTimers);
          }
          if (from < 18) {
            await migrator.addColumn(
              activityLog,
              activityLog.syncAcknowledgedAt,
            );
          }
          if (from < 19) {
            await migrator.createTable(syncStates);
          }
          if (from < 20) {
            await migrator.addColumn(loggedSets, loggedSets.syncDeviceId);
          }
          if (from < 21) {
            await migrator.addColumn(
              loggedSets,
              loggedSets.syncPreviouslySynced,
            );
          }
          if (from >= 19 && from < 22) {
            await migrator.addColumn(syncStates, syncStates.syncStatus);
            await migrator.addColumn(
              syncStates,
              syncStates.lastSuccessfulSyncAt,
            );
            await migrator.addColumn(syncStates, syncStates.firstFailureAt);
            await migrator.addColumn(syncStates, syncStates.lastFailureAt);
            await migrator.addColumn(syncStates, syncStates.lastFailureMessage);
          }
          if (from < 23) {
            await migrator.createTable(measurements);
            await migrator.createTable(measurementEntries);
          }
          if (from >= 23 && from < 24) {
            await migrator.addColumn(measurements, measurements.targetValue);
          }
          if (from < 25) {
            await migrator.createTable(metrics);
            await migrator.createTable(metricReadings);
          }
          if (from >= 25 && from < 26) {
            await migrator.addColumn(metricReadings, metricReadings.comment);
          }
          if (from < 26) {
            await backfillMetricsFromMeasurements();
          }
          if (from < 27) {
            await migrator.createTable(monitoringSeriesCache);
          }
          if (from < 28) {
            await migrator.createTable(integrationDataClassConsents);
          }
          if (from < 29) {
            await migrator.createTable(meals);
            await migrator.createTable(foodEntries);
          }
          if (from < 30) {
            await migrator.createTable(foods);
            if (from >= 29) {
              await migrator.addColumn(foodEntries, foodEntries.foodSource);
              await migrator.addColumn(foodEntries, foodEntries.isLiquid);
              await migrator.addColumn(foodEntries, foodEntries.servingLabel);
              await migrator.addColumn(foodEntries, foodEntries.servingSize);
              await migrator.addColumn(foodEntries, foodEntries.packageSize);
            }
          }
          if (from < 31) {
            await migrator.createTable(mealTypes);
          }
          if (from >= 30 && from < 32) {
            await migrator.addColumn(foods, foods.recipeIngredientsJson);
            await migrator.addColumn(foods, foods.recipeServingCount);
          }
          if (from < 33) {
            await migrator.createTable(openFoodFactsCache);
          }
          if (from < 34) {
            await migrator.createTable(nutritionGoals);
          }
          if (from >= 29 && from < 35) {
            await migrator.addColumn(foodEntries, foodEntries.importSource);
            await migrator.addColumn(foodEntries, foodEntries.importExternalId);
            await migrator.addColumn(foodEntries, foodEntries.reviewFlagsJson);
          }
          if (from >= 29 && from < 36) {
            await migrator.addColumn(foodEntries, foodEntries.importProvider);
          }
          if (from < 37) {
            await migrator.createTable(compounds);
            await migrator.createTable(doses);
          }
          if (from >= 37 && from < 38) {
            // the Dose snapshots the Compound's strength at log time
            // (it already snapshotted the name). Older Doses keep a null
            // strength snapshot; nothing reaches back into existing rows.
            await migrator.addColumn(doses, doses.compoundStrength);
          }
          if (from < 45 &&
              await _tableExists(exerciseCategories.actualTableName)) {
            // `ExerciseCategory`/`Exercise` (User Library rows only,
            //) sync as ordinary LWW rows, mirroring `Compounds`.
            // `ExerciseCategories`/`Exercises` have existed since schema
            // version 2, so every upgrade path needs this guarded column add
            // (unlike the Protocols tables, which were CREATED sync-capable).
            // Guarded by `_tableExists` too: some migration test fixtures
            // (e.g. a synthetic v19 snapshot) omit these tables entirely.
            // MUST run before `_backfillExerciseEquipmentFromNotes` below,
            // which does a typed `select(exercises)` against the CURRENT
            // (post-migration) generated mapper — that mapper expects these
            // columns to already exist on the physical table.
            if (!await _columnExists(
              exerciseCategories.actualTableName,
              exerciseCategories.syncDeviceId.name,
            )) {
              await migrator.addColumn(
                exerciseCategories,
                exerciseCategories.syncDeviceId,
              );
            }
            if (!await _columnExists(
              exerciseCategories.actualTableName,
              exerciseCategories.syncPreviouslySynced.name,
            )) {
              await migrator.addColumn(
                exerciseCategories,
                exerciseCategories.syncPreviouslySynced,
              );
            }
            if (await _tableExists(exercises.actualTableName)) {
              if (!await _columnExists(
                exercises.actualTableName,
                exercises.syncDeviceId.name,
              )) {
                await migrator.addColumn(exercises, exercises.syncDeviceId);
              }
              if (!await _columnExists(
                exercises.actualTableName,
                exercises.syncPreviouslySynced.name,
              )) {
                await migrator.addColumn(
                  exercises,
                  exercises.syncPreviouslySynced,
                );
              }
            }
          }
          if (from < 39 &&
              await _tableExists(exercises.actualTableName) &&
              !await _columnExists(
                exercises.actualTableName,
                exercises.equipmentIds.name,
              )) {
            await migrator.addColumn(exercises, exercises.equipmentIds);
            await _backfillExerciseEquipmentFromNotes();
          }
          if (from >= 37 && from < 40) {
            // a UI-affordance favourites flag on Compounds, mirroring
            // Exercises.isFavorite. Existing Compounds default to unfavourited.
            // Guarded to `from >= 37` (when `compounds` was first created):
            // upgrading from an EARLIER version runs `createTable(compounds)`
            // below with the CURRENT (already-favourited-capable) column set,
            // so adding the column again there would be a duplicate.
            await migrator.addColumn(compounds, compounds.isFavorite);
          }
          if (from >= 25 && from < 40) {
            if (!await _columnExists(
              metrics.actualTableName,
              metrics.syncDeviceId.name,
            )) {
              await migrator.addColumn(metrics, metrics.syncDeviceId);
            }
            if (!await _columnExists(
              metrics.actualTableName,
              metrics.syncPreviouslySynced.name,
            )) {
              await migrator.addColumn(
                metrics,
                metrics.syncPreviouslySynced,
              );
            }
            if (!await _columnExists(
              metricReadings.actualTableName,
              metricReadings.syncDeviceId.name,
            )) {
              await migrator.addColumn(
                metricReadings,
                metricReadings.syncDeviceId,
              );
            }
            if (!await _columnExists(
              metricReadings.actualTableName,
              metricReadings.syncPreviouslySynced.name,
            )) {
              await migrator.addColumn(
                metricReadings,
                metricReadings.syncPreviouslySynced,
              );
            }
          }
          if (from < 41) {
            // the `Protocol` plan-layer entity (PROTOCOLS.md §1.4) — a
            // named, time-bounded course grouping one or more Compounds (a
            // stack). A mutable plan; never touches a logged Dose.
            await migrator.createTable(protocols);
            await migrator.createTable(protocolCompounds);
          }
          if (from < 42) {
            // the OPTIONAL `Schedule` per member Compound of a
            // Protocol (PROTOCOLS.md §1.4) — planned dose · frequency · route.
            // Purely prescriptive plan data; never touches a logged Dose.
            await migrator.createTable(schedules);
          }
          if (from < 43) {
            // a Protocol's declared target outcomes (which
            // Metrics/performance to correlate, PROTOCOLS.md §1.4/§4) — plan
            // data only, seeding the later Effect view (M29); no analysis here.
            await migrator.createTable(protocolTargetOutcomes);
          }
          if (from >= 37 && from < 43) {
            // a Dose's OPTIONAL Protocol tag (PROTOCOLS.md §1.4).
            // Guarded to `from >= 37` (when `doses` was first created):
            // upgrading from an EARLIER version runs `createTable(doses)`
            // above with the CURRENT (already-taggable) column set, so adding
            // these columns again here would be a duplicate.
            await migrator.addColumn(doses, doses.protocolId);
            await migrator.addColumn(doses, doses.protocolName);
          }
          if (from >= 41 && from < 44) {
            // `Protocol`/`ProtocolCompound` sync as ordinary LWW rows
            // (PROTOCOLS.md §7) — add the `syncDeviceId`/`syncPreviouslySynced`
            // columns, mirroring `Compounds`. Guarded to `from >= 41` (when
            // these tables were first created): upgrading from an EARLIER
            // version runs `createTable` above with the CURRENT (already
            // sync-capable) column set, so adding these columns again here
            // would be a duplicate.
            if (!await _columnExists(
              protocols.actualTableName,
              protocols.syncDeviceId.name,
            )) {
              await migrator.addColumn(protocols, protocols.syncDeviceId);
            }
            if (!await _columnExists(
              protocols.actualTableName,
              protocols.syncPreviouslySynced.name,
            )) {
              await migrator.addColumn(
                protocols,
                protocols.syncPreviouslySynced,
              );
            }
            if (!await _columnExists(
              protocolCompounds.actualTableName,
              protocolCompounds.syncDeviceId.name,
            )) {
              await migrator.addColumn(
                protocolCompounds,
                protocolCompounds.syncDeviceId,
              );
            }
            if (!await _columnExists(
              protocolCompounds.actualTableName,
              protocolCompounds.syncPreviouslySynced.name,
            )) {
              await migrator.addColumn(
                protocolCompounds,
                protocolCompounds.syncPreviouslySynced,
              );
            }
          }
          if (from >= 42 && from < 44) {
            // `Schedule` syncs too — same treatment, guarded to
            // `from >= 42` (when `schedules` was first created).
            if (!await _columnExists(
              schedules.actualTableName,
              schedules.syncDeviceId.name,
            )) {
              await migrator.addColumn(schedules, schedules.syncDeviceId);
            }
            if (!await _columnExists(
              schedules.actualTableName,
              schedules.syncPreviouslySynced.name,
            )) {
              await migrator.addColumn(
                schedules,
                schedules.syncPreviouslySynced,
              );
            }
          }
          if (from >= 43 && from < 44) {
            // the Protocol's declared target outcomes sync alongside
            // it, guarded to `from >= 43` (when `protocolTargetOutcomes` was
            // first created).
            if (!await _columnExists(
              protocolTargetOutcomes.actualTableName,
              protocolTargetOutcomes.syncDeviceId.name,
            )) {
              await migrator.addColumn(
                protocolTargetOutcomes,
                protocolTargetOutcomes.syncDeviceId,
              );
            }
            if (!await _columnExists(
              protocolTargetOutcomes.actualTableName,
              protocolTargetOutcomes.syncPreviouslySynced.name,
            )) {
              await migrator.addColumn(
                protocolTargetOutcomes,
                protocolTargetOutcomes.syncPreviouslySynced,
              );
            }
          }
          if (from < 47) {
            // the 3-2-1 rest/interval prepare cue needs a fire-once
            // marker so a panel remount never re-beeps. `rest_timers` /
            // `interval_timers` have existed since early schema versions, so
            // every upgrade path needs this guarded column add.
            if (await _tableExists(restTimers.actualTableName) &&
                !await _columnExists(
                  restTimers.actualTableName,
                  restTimers.prepareAlertFiredAt.name,
                )) {
              await migrator.addColumn(
                restTimers,
                restTimers.prepareAlertFiredAt,
              );
            }
            if (await _tableExists(intervalTimers.actualTableName) &&
                !await _columnExists(
                  intervalTimers.actualTableName,
                  intervalTimers.prepareAlertFiredAt.name,
                )) {
              await migrator.addColumn(
                intervalTimers,
                intervalTimers.prepareAlertFiredAt,
              );
            }
          }
          if (from < 48) {
            // The account-level half of AppSettings becomes
            // a synced singleton. The one-time migration of any existing local
            // settings.json values into this row is handled at the repository
            // layer on first load, not here — this only creates the table.
            await migrator.createTable(userSettings);
          }
          if (from < 49 &&
              await _tableExists(loggedSets.actualTableName) &&
              !await _columnExists(
                loggedSets.actualTableName,
                loggedSets.performedAt.name,
              )) {
            // Sets may carry an optional observed timestamp while
            // position remains the source of display ordering.
            await migrator.addColumn(loggedSets, loggedSets.performedAt);
          }
          if (from < 50 && await _tableExists(loggedSets.actualTableName)) {
            await customStatement(
              '''
              CREATE INDEX IF NOT EXISTS logged_sets_exercise_id_index
                ON logged_sets (exercise_id);
              ''',
            );
          }
          if (from < 51) {
            await migrator.createTable(workoutTemplates);
            await migrator.createTable(templateExercises);
            await migrator.createTable(prescriptions);
            await migrator.createTable(templateLinks);
            // Drift's createTable() does not install @TableIndex declarations.
            // Keep the v50 -> v51 path identical to a fresh createAll().
            await migrator.createIndex(workoutTemplatesNameIndex);
            await migrator.createIndex(templateExercisesTemplateIdIndex);
            await migrator.createIndex(templateExercisesExerciseIdIndex);
            await migrator.createIndex(
              templateExercisesActiveExerciseUnique,
            );
            await migrator.createIndex(prescriptionsTemplateExerciseIdIndex);
            await migrator.createIndex(templateLinksWorkoutIdUnique);
            await migrator.createIndex(templateLinksTemplateIdIndex);
            await migrator.createIndex(templateLinksRoutineIdIndex);
          }
          if (from < 52) {
            await migrator.createTable(templateGroups);
            await migrator.createTable(templateGroupMembers);
            // Drift's createTable() does not install @TableIndex declarations.
            // Keep the v51 -> v52 path identical to a fresh createAll().
            await migrator.createIndex(templateGroupsTemplateIdIndex);
            await migrator.createIndex(templateGroupMembersGroupIdIndex);
            await migrator.createIndex(
              templateGroupMembersTemplateExerciseIdIndex,
            );
            await migrator.createIndex(
              templateGroupMembersActiveExerciseUnique,
            );
          }
          if (from < 53) {
            await migrator.createTable(planRoutines);
            await migrator.createTable(routineEntries);
            // Drift's createTable() does not install @TableIndex declarations.
            await migrator.createIndex(planRoutinesNameIndex);
            await migrator.createIndex(routineEntriesRoutineIdIndex);
            await migrator.createIndex(routineEntriesTemplateIdIndex);
            // Template Links predate the redesigned Routine. Rebuild the table
            // to add its nullable, non-cascading Routine foreign key while
            // preserving every existing link row. Its old Routine UUID seam
            // was never written by materialization, so an opaque pre-v53 value
            // with no Plan Routine has no provenance meaning and is cleared.
            if (await _tableExists(templateLinks.actualTableName)) {
              await customStatement(
                'UPDATE ${templateLinks.actualTableName} '
                'SET routine_id = NULL WHERE routine_id IS NOT NULL',
              );
            }
            await migrator.alterTable(TableMigration(templateLinks));
          }
          // Upgrade only physical v53 tables. Earlier versions create the
          // current table shape in the `from < 53` block above.
          if (from >= 53 && from < 54) {
            await migrator.addColumn(planRoutines, planRoutines.cadenceKind);
            await migrator.addColumn(planRoutines, planRoutines.cadenceWindow);
            await migrator.addColumn(routineEntries, routineEntries.slot);
          }
          if (from < 55) {
            // the alpha Routine ownership tree was replaced
            // greenfield by first-class Workout Templates and reference-only
            // Routines. An old interval timer cannot be resumed once its
            // retired plan source is intentionally discarded, so rebuild the
            // table source-neutral before dropping that FK parent.
            if (await _tableExists(intervalTimers.actualTableName) &&
                await _columnExists(
                  intervalTimers.actualTableName,
                  'routine_day_id',
                )) {
              await migrator.deleteTable(intervalTimers.actualTableName);
              await migrator.createTable(intervalTimers);
              await migrator.createIndex(intervalTimersWorkoutIdIndex);
            }
            if (await _tableExists(intervalTimers.actualTableName)) {
              await customStatement(
                'CREATE INDEX IF NOT EXISTS '
                'interval_timers_workout_id_index '
                'ON interval_timers (workout_id)',
              );
            }

            // Activity Log snapshots for the discarded ownership tree cannot
            // be replayed, undone, or synced after this cutover. Remove them
            // with their entities so they do not remain as permanent pending
            // activity or surface retired terminology in the feed.
            if (await _tableExists(activityLog.actualTableName)) {
              await customStatement(
                'DELETE FROM activity_log WHERE entity_table IN ('
                "'routines', "
                "'routine_days', "
                "'routine_exercises', "
                "'predefined_sets', "
                "'routine_exercise_groups', "
                "'routine_exercise_group_members'"
                ')',
              );
            }

            // Child-first keeps the cutover valid even when foreign-key
            // enforcement is enabled by a custom executor. Guards also cover
            // the intentionally partial historical migration fixtures.
            for (final tableName in <String>[
              'routine_exercise_group_members',
              'predefined_sets',
              'routine_exercise_groups',
              'routine_exercises',
              'routine_days',
              'routines',
            ]) {
              if (await _tableExists(tableName)) {
                await migrator.deleteTable(tableName);
              }
            }
          }
          if (from < 56) {
            // Workout sessions and their ordered/grouped structure are now
            // first-class sync entities. These columns carry the ordinary LWW
            // device tie-breaker and full-resync provenance used by every
            // other authored row.
            for (final entry in <({
              String tableName,
              GeneratedColumn<Object> column,
              Future<void> Function() add,
            })>[
              (
                tableName: workoutSessions.actualTableName,
                column: workoutSessions.syncDeviceId,
                add: () => migrator.addColumn(
                      workoutSessions,
                      workoutSessions.syncDeviceId,
                    ),
              ),
              (
                tableName: workoutSessions.actualTableName,
                column: workoutSessions.syncPreviouslySynced,
                add: () => migrator.addColumn(
                      workoutSessions,
                      workoutSessions.syncPreviouslySynced,
                    ),
              ),
              (
                tableName: workoutExercises.actualTableName,
                column: workoutExercises.syncDeviceId,
                add: () => migrator.addColumn(
                      workoutExercises,
                      workoutExercises.syncDeviceId,
                    ),
              ),
              (
                tableName: workoutExercises.actualTableName,
                column: workoutExercises.syncPreviouslySynced,
                add: () => migrator.addColumn(
                      workoutExercises,
                      workoutExercises.syncPreviouslySynced,
                    ),
              ),
              (
                tableName: exerciseGroups.actualTableName,
                column: exerciseGroups.syncDeviceId,
                add: () => migrator.addColumn(
                      exerciseGroups,
                      exerciseGroups.syncDeviceId,
                    ),
              ),
              (
                tableName: exerciseGroups.actualTableName,
                column: exerciseGroups.syncPreviouslySynced,
                add: () => migrator.addColumn(
                      exerciseGroups,
                      exerciseGroups.syncPreviouslySynced,
                    ),
              ),
              (
                tableName: exerciseGroupMembers.actualTableName,
                column: exerciseGroupMembers.syncDeviceId,
                add: () => migrator.addColumn(
                      exerciseGroupMembers,
                      exerciseGroupMembers.syncDeviceId,
                    ),
              ),
              (
                tableName: exerciseGroupMembers.actualTableName,
                column: exerciseGroupMembers.syncPreviouslySynced,
                add: () => migrator.addColumn(
                      exerciseGroupMembers,
                      exerciseGroupMembers.syncPreviouslySynced,
                    ),
              ),
            ]) {
              if (await _tableExists(entry.tableName) &&
                  !await _columnExists(
                    entry.tableName,
                    entry.column.name,
                  )) {
                await entry.add();
              }
            }
          }
          if (from < 57 && await _tableExists(activityLog.actualTableName)) {
            await customStatement(
              'CREATE INDEX IF NOT EXISTS activity_log_pending_sync_index '
              'ON activity_log (entity_table) '
              'WHERE deleted_at IS NULL '
              'AND sync_acknowledged_at IS NULL '
              'AND after_image IS NOT NULL',
            );
          }
        },
        beforeOpen: (_) async => customStatement('PRAGMA foreign_keys = ON'),
      );

  Future<void> backfillMetricsFromMeasurements() async {
    await customStatement(
      '''
        INSERT OR IGNORE INTO metrics (
          id,
          name,
          unit,
          value_shape,
          metric_group,
          goal_type,
          goal_target_value,
          enabled,
          pinned,
          sort_order,
          updated_at,
          deleted_at
        )
        SELECT
          id,
          name,
          unit,
          'scalar',
          'bodyComposition',
          goal_type,
          target_value,
          enabled,
          enabled,
          sort_order,
          updated_at,
          deleted_at
        FROM measurements;
      ''',
    );
    await customStatement(
      '''
        INSERT OR IGNORE INTO metric_readings (
          id,
          metric_id,
          value_json,
          scalar_value,
          scalar_entered,
          at_time,
          window_started_at,
          window_ended_at,
          provenance,
          source,
          external_id,
          comment,
          updated_at,
          deleted_at
        )
        SELECT
          entry.id,
          entry.measurement_id,
          json_object(
            'shape',
            'scalar',
            'value',
            entry.value,
            'entered',
            entry.value_entered
          ),
          entry.value,
          entry.value_entered,
          entry.measured_at,
          NULL,
          NULL,
          'manual',
          'manual',
          entry.id,
          entry.comment,
          entry.updated_at,
          entry.deleted_at
        FROM measurement_entries AS entry
        INNER JOIN measurements AS measurement
          ON measurement.id = entry.measurement_id;
      ''',
    );
  }

  Future<void> _backfillExerciseRecordProfiles() async {
    await customStatement(
      '''
        UPDATE exercises
        SET record_profile = CASE
          WHEN dimension_ids = '[]' THEN 'completionStreak'
          WHEN dimension_ids LIKE '%"load"%'
            AND dimension_ids LIKE '%"reps"%' THEN 'repMax'
          WHEN dimension_ids LIKE '%"reps"%' THEN 'maxReps'
          WHEN dimension_ids LIKE '%"distance"%'
            AND dimension_ids LIKE '%"duration"%' THEN 'fastestPace'
          WHEN dimension_ids LIKE '%"duration"%' THEN 'maxDuration'
          WHEN dimension_ids LIKE '%"distance"%' THEN 'maxDistance'
          WHEN dimension_ids LIKE '%"load"%' THEN 'maxLoad'
          ELSE 'completionStreak'
        END;
      ''',
    );
  }

  Future<void> _backfillWorkoutSessionLocalDates() async {
    // Migration steps run against the historical physical schema, while a
    // typed table select uses the current generated mapper. Read only the
    // columns this backfill needs so later non-null columns do not have to
    // exist yet on early-version databases.
    final rows = await customSelect(
      '''
        SELECT id, started_at
        FROM workout_sessions;
      ''',
      readsFrom: {workoutSessions},
    ).get();
    for (final row in rows) {
      final workoutId = row.read<String>('id');
      final startedAt = row.read<DateTime>('started_at');
      await (update(workoutSessions)
            ..where((table) => table.id.equals(workoutId)))
          .write(
        WorkoutSessionsCompanion(
          localDate: Value<String>(
            TrainingDayDate.fromDateTime(startedAt).storageValue,
          ),
        ),
      );
    }
  }

  Future<bool> _tableExists(String tableName) async {
    final row = await customSelect(
      '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table' AND name = ?
        LIMIT 1;
      ''',
      variables: <Variable<String>>[Variable<String>(tableName)],
    ).getSingleOrNull();
    return row != null;
  }

  Future<bool> _columnExists(String tableName, String columnName) async {
    final rows = await customSelect('PRAGMA table_info($tableName)').get();
    return rows.any((row) => row.read<String>('name') == columnName);
  }

  Future<void> _backfillExerciseEquipmentFromNotes() async {
    // This runs while upgrading historical schemas, so do not decode rows
    // through the current generated table shape: later columns may not exist
    // yet on the database being migrated.
    final rows = await customSelect(
      'SELECT id, library_origin, notes FROM exercises',
    ).get();
    for (final row in rows) {
      if (row.read<String>('library_origin') != 'platform') {
        continue;
      }

      final migration = _legacyEquipmentMigrationFromNote(
        row.readNullable<String>('notes'),
      );
      if (migration == null) {
        continue;
      }

      await customUpdate(
        'UPDATE exercises SET equipment_ids = ?, notes = ? WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<String>(jsonEncode(migration.equipmentIds)),
          Variable<String>(migration.notes),
          Variable<String>(row.read<String>('id')),
        ],
        updates: <TableInfo<Table, Object?>>{exercises},
      );
    }
  }

  Future<Map<String, Set<String>>> describeSchema() async {
    final schema = <String, Set<String>>{};

    for (final tableName in schemaTableNames) {
      final rows = await customSelect('PRAGMA table_info($tableName)').get();
      schema[tableName] = rows.map((row) => row.read<String>('name')).toSet();
    }

    return Map<String, Set<String>>.unmodifiable(schema);
  }
}

class _LegacyEquipmentMigration {
  const _LegacyEquipmentMigration({
    required this.equipmentIds,
    required this.notes,
  });

  final List<String> equipmentIds;
  final String? notes;
}

_LegacyEquipmentMigration? _legacyEquipmentMigrationFromNote(String? notes) {
  if (notes == null || !notes.startsWith(_legacyWgerAttributionPrefix)) {
    return null;
  }

  final cleanedNote = _stripLegacyWgerAttributionNote(notes);
  if (cleanedNote == null) {
    return null;
  }

  final match = RegExp(r'^Equipment:\s+(.+)\.$').firstMatch(cleanedNote);
  if (match == null) {
    return cleanedNote == notes
        ? null
        : _LegacyEquipmentMigration(
            equipmentIds: const <String>[],
            notes: cleanedNote.isEmpty ? null : cleanedNote,
          );
  }

  final equipmentIds = match
      .group(1)!
      .split(',')
      .map((name) => _legacyEquipmentIdForName(name.trim()))
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList(growable: false);
  return _LegacyEquipmentMigration(
    equipmentIds: equipmentIds,
    notes: null,
  );
}

String? _stripLegacyWgerAttributionNote(String? notes) {
  if (notes == null) {
    return null;
  }
  if (!notes.startsWith(_legacyWgerAttributionPrefix)) {
    return notes;
  }

  return notes.substring(_legacyWgerAttributionPrefix.length).trimLeft();
}

const _legacyWgerAttributionPrefix = 'Adapted from the wger exercise database.';

String _legacyEquipmentIdForName(String name) {
  final normalized = name.toLowerCase();
  return switch (normalized) {
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
    _ => _equipmentIdFromName(name),
  };
}

String _equipmentIdFromName(String name) {
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
