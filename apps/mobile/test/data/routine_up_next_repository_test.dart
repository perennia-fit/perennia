import 'package:drift/drift.dart' show driftRuntimeOptions;
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
}
