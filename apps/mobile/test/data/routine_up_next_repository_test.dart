import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/data/local/app_database.dart';
import 'package:perennia/data/repositories/training_repositories.dart';
import 'package:perennia/domain/training/training_day.dart';

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

  group('RoutineUpNextRepository', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> createTemplate(String name) {
      return repositories.workoutTemplates.create(
        WorkoutTemplateDraft(name: name),
      );
    }

    test('a Routine without a Cadence never suggests anything', () async {
      final templateId = await createTemplate('Push A');
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Collection only'),
      );
      await repositories.routinePlans.addTemplateReference(
        routineId,
        templateId,
      );

      final suggestions = await repositories.routineUpNext
          .watchSuggestions(const TrainingDayDate(year: 2026, month: 7, day: 6))
          .first;

      expect(suggestions, isEmpty);
    });

    test('a weekly Cadence suggests only on its own weekday, and ticks a '
        'session materialized today', () async {
      final mondayTemplateId = await createTemplate('Push A');
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Weekly split'),
      );
      final entryId = await repositories.routinePlans.addTemplateReference(
        routineId,
        mondayTemplateId,
      );
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
      );
      await repositories.routinePlans.moveTemplateReferenceToSlot(
        entryId,
        DateTime.monday,
      );

      // 2026-07-07 is a Tuesday: the Monday-only Routine has nothing to
      // suggest.
      final tuesday = const TrainingDayDate(year: 2026, month: 7, day: 7);
      expect(
        await repositories.routineUpNext.watchSuggestions(tuesday).first,
        isEmpty,
      );

      final monday = const TrainingDayDate(year: 2026, month: 7, day: 6);
      var suggestions =
          await repositories.routineUpNext.watchSuggestions(monday).first;
      expect(suggestions, hasLength(1));
      expect(suggestions.single.routineId, routineId);
      expect(suggestions.single.slot, DateTime.monday);
      expect(suggestions.single.cards.single.isDone, isFalse);

      await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(
          workoutTemplateId: mondayTemplateId,
          routineId: routineId,
          slot: DateTime.monday,
        ),
        now: DateTime(2026, 7, 6, 8),
      );

      suggestions =
          await repositories.routineUpNext.watchSuggestions(monday).first;
      expect(suggestions, hasLength(1));
      expect(suggestions.single.cards.single.isDone, isTrue);
    });

    test('a rotating Cadence advances only when the whole slot is '
        'materialized, and re-anchors on an out-of-order pick', () async {
      final templateIds = <String>[];
      for (var index = 0; index < 3; index += 1) {
        templateIds.add(await createTemplate('Day ${index + 1}'));
      }
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Push Pull Legs'),
      );
      for (final templateId in templateIds) {
        await repositories.routinePlans.addTemplateReference(
          routineId,
          templateId,
        );
      }
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.rotating(3),
      );

      final anyDate = const TrainingDayDate(year: 2026, month: 7, day: 6);
      var suggestions =
          await repositories.routineUpNext.watchSuggestions(anyDate).first;
      expect(suggestions.single.slot, 1);
      expect(suggestions.single.cards.single.isDone, isFalse);

      await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(
          workoutTemplateId: templateIds[0],
          routineId: routineId,
          slot: 1,
        ),
        now: DateTime(2026, 7, 6, 8),
      );
      suggestions =
          await repositories.routineUpNext.watchSuggestions(anyDate).first;
      expect(suggestions.single.slot, 2);

      // Out-of-order pick: skip slot 2 and materialize slot 3 directly.
      await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(
          workoutTemplateId: templateIds[2],
          routineId: routineId,
          slot: 3,
        ),
        now: DateTime(2026, 7, 6, 9),
      );
      // Re-anchors to fact: the derived position wraps forward from slot 3,
      // landing back on slot 1 — never the "skipped" slot 2.
      suggestions =
          await repositories.routineUpNext.watchSuggestions(anyDate).first;
      expect(suggestions.single.slot, 1);
      expect(suggestions.single.cards.single.isDone, isFalse);

      // A second, independent repository instance over the same database
      // derives the identical position: nothing is cached or cursor-held
      // in the first instance (kill-and-reopen safe).
      final reopened = TrainingRepositories(database);
      final reopenedSuggestions = await reopened.routineUpNext
          .watchSuggestions(anyDate)
          .first;
      expect(reopenedSuggestions.single.slot, 1);
    });

    test('an entry whose Template is archived is never suggested', () async {
      final templateId = await createTemplate('Push A');
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Weekly split'),
      );
      final entryId = await repositories.routinePlans.addTemplateReference(
        routineId,
        templateId,
      );
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
      );
      await repositories.routinePlans.moveTemplateReferenceToSlot(
        entryId,
        DateTime.monday,
      );
      await repositories.workoutTemplates.archive(templateId);

      final monday = const TrainingDayDate(year: 2026, month: 7, day: 6);
      expect(
        await repositories.routineUpNext.watchSuggestions(monday).first,
        isEmpty,
      );
    });

    test('an archived Routine is never suggested', () async {
      final templateId = await createTemplate('Push A');
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Weekly split'),
      );
      final entryId = await repositories.routinePlans.addTemplateReference(
        routineId,
        templateId,
      );
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
      );
      await repositories.routinePlans.moveTemplateReferenceToSlot(
        entryId,
        DateTime.monday,
      );
      await repositories.routinePlans.archive(routineId);

      final monday = const TrainingDayDate(year: 2026, month: 7, day: 6);
      expect(
        await repositories.routineUpNext.watchSuggestions(monday).first,
        isEmpty,
      );
    });

    test('the suggestion stream reacts to a later materialize', () async {
      final templateIds = <String>[];
      for (var index = 0; index < 2; index += 1) {
        templateIds.add(await createTemplate('Day ${index + 1}'));
      }
      final routineId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Two-day split'),
      );
      for (final templateId in templateIds) {
        await repositories.routinePlans.addTemplateReference(
          routineId,
          templateId,
        );
      }
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.rotating(2),
      );

      final anyDate = const TrainingDayDate(year: 2026, month: 7, day: 6);
      final emissions = <int>[];
      final subscription = repositories.routineUpNext
          .watchSuggestions(anyDate)
          .listen((suggestions) => emissions.add(suggestions.single.slot));

      await pumpEventQueue();
      await repositories.templateMaterialize.materialize(
        TemplateMaterializeRequest(
          workoutTemplateId: templateIds[0],
          routineId: routineId,
          slot: 1,
        ),
        now: DateTime(2026, 7, 6, 8),
      );
      await pumpEventQueue();

      expect(emissions, <int>[1, 2]);
      await subscription.cancel();
    });
  });

  group('RoutineUpNextRepository.watchWeeklyPlans', () {
    late AppDatabase database;
    late TrainingRepositories repositories;

    setUp(() {
      database = AppDatabase.inMemory();
      repositories = TrainingRepositories(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<String> createTemplate(String name) {
      return repositories.workoutTemplates.create(
        WorkoutTemplateDraft(name: name),
      );
    }

    /// A weekly Routine planning each template on its weekday, in order.
    Future<(String, List<String>)> weeklyRoutine(
      String name,
      Map<String, int> weekdayByTemplateId,
    ) async {
      final routineId = await repositories.routinePlans.create(
        RoutinePlanDraft(name: name),
      );
      await repositories.routinePlans.setCadence(
        routineId,
        const Cadence.weekly(),
      );
      final entryIds = <String>[];
      for (final MapEntry(key: templateId, value: weekday)
          in weekdayByTemplateId.entries) {
        entryIds.add(
          await repositories.routinePlans.addTemplateReference(
            routineId,
            templateId,
            slot: weekday,
          ),
        );
      }
      return (routineId, entryIds);
    }

    Map<String, int> weekdaysOf(WeeklyPlanFacts plan) => <String, int>{
          for (final entry in plan.entries)
            entry.workoutTemplateId: entry.weekday,
        };

    test('lists each weekly Routine with its slots as ISO weekdays, and '
        'leaves out rotating and uncadenced Routines', () async {
      final lower = await createTemplate('Lower');
      final run = await createTemplate('Run intervals');
      final (routineId, _) = await weeklyRoutine('Hybrid block', {
        lower: DateTime.monday,
        run: DateTime.tuesday,
      });
      final rotatingId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Rotation'),
      );
      await repositories.routinePlans.addTemplateReference(rotatingId, lower);
      await repositories.routinePlans.setCadence(
        rotatingId,
        const Cadence.rotating(2),
      );
      final collectionId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Collection only'),
      );
      await repositories.routinePlans.addTemplateReference(collectionId, run);

      final plans =
          await repositories.routineUpNext.watchWeeklyPlans().first;

      expect(plans, hasLength(1));
      expect(plans.single.routineId, routineId);
      expect(plans.single.routineName, 'Hybrid block');
      expect(weekdaysOf(plans.single), <String, int>{
        lower: DateTime.monday,
        run: DateTime.tuesday,
      });
      final plan = plans.single.toWeeklyPlan();
      expect(plan.routineId, routineId);
      expect(plan.entries, hasLength(2));
      expect(
        await repositories.routineUpNext.watchHasRotatingRoutine().first,
        isTrue,
      );
    });

    test('an archived entry plans nothing', () async {
      final lower = await createTemplate('Lower');
      final upper = await createTemplate('Upper');
      final (_, entryIds) = await weeklyRoutine('Hybrid block', {
        lower: DateTime.monday,
        upper: DateTime.thursday,
      });
      await repositories.routinePlans.removeTemplateReference(entryIds.first);

      final plans =
          await repositories.routineUpNext.watchWeeklyPlans().first;

      expect(weekdaysOf(plans.single), <String, int>{
        upper: DateTime.thursday,
      });
    });

    test('an entry whose Workout Template is archived plans nothing',
        () async {
      final lower = await createTemplate('Lower');
      final upper = await createTemplate('Upper');
      await weeklyRoutine('Hybrid block', {
        lower: DateTime.monday,
        upper: DateTime.thursday,
      });
      await repositories.workoutTemplates.archive(lower);

      final plans =
          await repositories.routineUpNext.watchWeeklyPlans().first;

      expect(weekdaysOf(plans.single), <String, int>{
        upper: DateTime.thursday,
      });
    });

    test('an entry without a slot plans nothing', () async {
      final lower = await createTemplate('Lower');
      final upper = await createTemplate('Upper');
      final (_, entryIds) = await weeklyRoutine('Hybrid block', {
        lower: DateTime.monday,
        upper: DateTime.thursday,
      });
      // The editors keep every slot of a cadenced Routine set; a malformed
      // synced row is the only way to lose one.
      await (database.update(database.routineEntries)
            ..where((row) => row.id.equals(entryIds.first)))
          .write(const RoutineEntriesCompanion(slot: Value<int?>(null)));

      final plans =
          await repositories.routineUpNext.watchWeeklyPlans().first;

      expect(weekdaysOf(plans.single), <String, int>{
        upper: DateTime.thursday,
      });
    });

    test('a weekly Routine with no entries is absent, and so is one whose '
        'Routine is archived', () async {
      final lower = await createTemplate('Lower');
      await weeklyRoutine('Empty week', const <String, int>{});
      final (archivedId, _) = await weeklyRoutine('Old block', {
        lower: DateTime.monday,
      });
      await repositories.routinePlans.archive(archivedId);

      expect(
        await repositories.routineUpNext.watchWeeklyPlans().first,
        isEmpty,
      );
      expect(
        await repositories.routineUpNext.watchHasRotatingRoutine().first,
        isFalse,
      );
    });

    test('a Routine switched to weekly stops counting as rotating',
        () async {
      final rotatingId = await repositories.routinePlans.create(
        const RoutinePlanDraft(name: 'Rotation'),
      );
      await repositories.routinePlans.setCadence(
        rotatingId,
        const Cadence.rotating(3),
      );
      final emissions = <bool>[];
      final subscription = repositories.routineUpNext
          .watchHasRotatingRoutine()
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await repositories.routinePlans.setCadence(
        rotatingId,
        const Cadence.weekly(),
      );
      await pumpEventQueue();

      expect(emissions, <bool>[true, false]);
    });
  });
}
